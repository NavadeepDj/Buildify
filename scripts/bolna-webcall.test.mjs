import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import vm from 'node:vm';
import { resolve } from 'node:path';
import { mkdtemp, mkdir, writeFile, readFile, rm, access } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createWebcallServer, validatePublicOrigin, reusableInvitation, pairedTargetFingerprint } from './bolna-webcall.mjs';

const invitation = 'synthetic-private-invitation';
test('call pages identify their device and authenticated target checks cannot mint calls', async t => {
  for (const [platform, label] of [['android', 'Runs on your Android phone'], ['windows', 'Runs on your laptop']]) {
    const f = await fixture(t, { targetPlatform: platform });
    const page = await f.request({}, 'GET', '/');
    assert.ok(page.body.includes(label));
    assert.equal((await f.request({ Authorization: '' }, 'GET', '/target')).status, 403);
    const target = await f.request({}, 'GET', '/target');
    assert.deepEqual(JSON.parse(target.body), { platform });
    assert.equal(f.calls.length, 0);
  }
});
async function fixture(t, options = {}) {
  const calls = [];
  const helper = createWebcallServer({
    key: 'synthetic-api-key', inviteToken: invitation, getAgentId: async () => 'paired-android-agent',
    publicOrigin: 'https://phone.example.com',
    fetchImpl: async (url, options) => { calls.push({ url, ...options }); return Response.json({ session_id: 'ephemeral-test-session' }); },
    ...options,
  });
  await new Promise(resolve => helper.server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => helper.server.close(resolve)));
  const request = (headers = {}, method = 'POST', path = '/session') => new Promise((resolve, reject) => {
    const req = http.request({ hostname: '127.0.0.1', port: helper.server.address().port, path, method, headers: {
      Host: 'phone.example.com', Origin: 'https://phone.example.com', 'X-Buildify-Webcall': '1', Authorization: `Bearer ${invitation}`, ...headers,
    } }, res => { let body = ''; res.on('data', part => body += part); res.on('end', () => resolve({ status: res.statusCode, body, headers: res.headers })); });
    req.on('error', reject); req.end();
  });
  return { ...helper, calls, request };
}

const flush = async () => { await new Promise(resolve => setImmediate(resolve)); };
function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

async function browser(t, options = {}) {
  const f = await fixture(t);
  const page = await f.request({}, 'GET', '/');
  const script = /<script>\s*([\s\S]*?)<\/script>/.exec(page.body)[1];
  const elements = Object.fromEntries(['#start', '#stop', '#status'].map(id => [id, {}]));
  const storage = new Map();
  const timers = new Map();
  const events = new Map();
  const instances = [];
  const requests = [];
  let timerId = 0;
  let replacedUrl;
  let tracksStopped = 0;
  let mediaCalls = 0;
  const stream = { getTracks: () => [{ stop: () => { tracksStopped++; } }] };
  vm.runInNewContext(script, {
    document: { querySelector: id => elements[id] },
    location: { hash: `#invite=${invitation}`, pathname: '/' },
    history: { replaceState: (_state, _title, url) => { replacedUrl = url; } },
    sessionStorage: { setItem: (key, value) => storage.set(key, value), getItem: key => storage.get(key) },
    window: { isSecureContext: true, addEventListener: (name, callback) => events.set(name, callback) },
    navigator: { mediaDevices: { getUserMedia: () => { mediaCalls++; return options.microphone ? options.microphone() : Promise.resolve(stream); } } },
    URLSearchParams, AbortController,
    setTimeout: (callback, ms) => { const id = ++timerId; timers.set(id, { callback, ms }); return id; },
    clearTimeout: id => timers.delete(id),
    BolnaWebCall: class {
      constructor(config) { this.options = config; this.events = new Map(); this.stops = 0; instances.push(this); }
      on(name, callback) { this.events.set(name, callback); }
      emit(name, payload) { this.events.get(name)?.(payload); }
      async start() {
        if (options.start) return options.start(this);
        await this.options.getSession();
        if (!this.stops) this.emit('call-start');
      }
      stop() { this.stops++; return options.stop ? options.stop(this) : Promise.resolve(); }
    },
    fetch: async (url, config) => { requests.push({ url, ...config }); return options.fetch ? options.fetch(url, config) : { ok: true, json: async () => ({ session_id: 'short-lived' }) }; },
  });
  return {
    elements, storage, instances, requests, timers, events, stream,
    get replacedUrl() { return replacedUrl; },
    get tracksStopped() { return tracksStopped; },
    get mediaCalls() { return mediaCalls; },
    click: async () => { elements['#start'].onclick(); await flush(); },
    cancel: async () => { elements['#stop'].onclick(); await flush(); },
    expire: async () => { for (const { callback } of [...timers.values()]) callback(); await flush(); },
  };
}

test('public call origins require HTTPS and reject paths, fragments and credentials', () => {
  for (const value of ['http://phone.example.com', 'https://u:p@phone.example.com', 'https://phone.example.com/path', 'https://phone.example.com/#invite=x', 'https://phone.example.com/?x=1']) assert.throws(() => validatePublicOrigin(value));
  assert.equal(validatePublicOrigin('https://phone.example.com/'), 'https://phone.example.com');
});

test('phone invitation mints only the configured agent and keeps account key on server', async t => {
  const f = await fixture(t);
  const result = await f.request();
  assert.equal(result.status, 200);
  assert.deepEqual(JSON.parse(result.body), { session_id: 'ephemeral-test-session' });
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].headers.Authorization, 'Bearer synthetic-api-key');
  assert.deepEqual(JSON.parse(f.calls[0].body), { agent_id: 'paired-android-agent' });
  const page = await f.request({}, 'GET', '/');
  assert.equal(page.status, 200);
  assert.ok(!page.body.includes('synthetic-api-key'));
  assert.ok(!page.body.includes(invitation));
  assert.equal(page.headers['referrer-policy'], 'no-referrer');
  assert.equal(f.phoneUrl, `https://phone.example.com/#invite=${invitation}`);
});

test('missing or mismatched invitation, host, origin and request marker cannot spend credits', async t => {
  const f = await fixture(t);
  for (const headers of [
    { Authorization: '' }, { Authorization: 'Bearer wrong' }, { Origin: '' },
    { Origin: 'https://evil.example.com' }, { Host: 'evil.example.com' },
    { Host: '127.0.0.1:19001' }, { 'X-Buildify-Webcall': '' },
  ]) assert.equal((await f.request(headers)).status, 403);
  assert.equal((await f.request({}, 'GET', '/session')).status, 403);
  assert.equal(f.calls.length, 0);
});

test('unauthenticated public landing page has no session credentials', async t => {
  const f = await fixture(t);
  const result = await f.request({ Authorization: '', Origin: '' }, 'GET', '/');
  assert.equal(result.status, 200);
  assert.equal(f.calls.length, 0);
  assert.ok(!result.body.includes(invitation));
});

test('rate limit reserves in flight calls and caps calls per helper lifetime', async t => {
  let now = 1000;
  const f = await fixture(t, { now: () => now, maxMints: 2 });
  const results = await Promise.all([f.request(), f.request()]);
  assert.deepEqual(results.map(result => result.status).sort(), [200, 429]);
  now += 20001;
  assert.equal((await f.request()).status, 200);
  now += 20001;
  assert.equal((await f.request()).status, 429);
  assert.equal(f.calls.length, 2);
});

test('provider failures are redacted from callers', async t => {
  const f = await fixture(t, { fetchImpl: async () => { throw new Error('synthetic-api-key secret upstream error'); } });
  const result = await f.request();
  assert.equal(result.status, 502);
  assert.equal(result.body, 'Bolna connection unavailable.');
});

test('phone page consumes fragment invitation, removes it from address bar and authenticates mint', async t => {
  const b = await browser(t);
  assert.equal(b.elements['#start'].disabled, false);
  assert.equal(b.replacedUrl, '/');
  assert.equal(b.storage.get('buildify-call-invite'), invitation);
  await b.click();
  assert.equal(b.requests[0].url, '/session');
  assert.equal(b.requests[0].headers.Authorization, `Bearer ${invitation}`);
  assert.equal(b.tracksStopped, 1);
  assert.match(b.elements['#status'].textContent, /Connected/);
  assert.equal(b.timers.size, 0);
});

test('local call origin remains usable with private invitation', async t => {
  const f = await fixture(t);
  const result = await f.request({ Host: '127.0.0.1:19001', Origin: 'http://127.0.0.1:19001' });
  assert.equal(result.status, 200);
  assert.equal(f.calls.length, 1);
});

test('microphone permission precedes mint; cancelling pending permission releases late tracks without mint', async t => {
  const permission = deferred();
  const b = await browser(t, { microphone: () => permission.promise });
  await b.click();
  assert.equal(b.mediaCalls, 1);
  assert.equal(b.requests.length, 0);
  assert.equal(b.elements['#start'].disabled, true);
  assert.equal(b.elements['#stop'].disabled, false);
  await b.cancel();
  assert.equal(b.elements['#start'].disabled, false);
  assert.equal(b.elements['#stop'].disabled, true);
  assert.equal(b.instances[0].stops, 1);
  permission.resolve(b.stream);
  await flush();
  assert.equal(b.tracksStopped, 1);
  assert.equal(b.requests.length, 0);
  assert.match(b.elements['#status'].textContent, /cancelled/);
});

test('ignored microphone prompt times out with retry controls and does not mint after a late grant', async t => {
  const permission = deferred();
  const b = await browser(t, { microphone: () => permission.promise });
  await b.click();
  assert.equal([...b.timers.values()][0].ms, 45000);
  await b.expire();
  assert.match(b.elements['#status'].textContent, /Microphone permission timed out/);
  assert.equal(b.elements['#start'].disabled, false);
  assert.equal(b.elements['#stop'].disabled, true);
  permission.resolve(b.stream);
  await flush();
  assert.equal(b.tracksStopped, 1);
  assert.equal(b.requests.length, 0);
});

test('hung SDK startup is bounded, supports retry and ignores old instance events and promises', async t => {
  const oldStart = deferred();
  const b = await browser(t, { start: async sdk => { await sdk.options.getSession(); return oldStart.promise; }, stop: () => new Promise(() => {}) });
  await b.click();
  assert.equal(b.requests.length, 1);
  assert.equal(b.elements['#stop'].disabled, false);
  await b.expire();
  assert.match(b.elements['#status'].textContent, /connection timed out/);
  assert.equal(b.elements['#start'].disabled, false);
  await b.click();
  assert.equal(b.instances.length, 2);
  const oldSdk = b.instances[0];
  oldSdk.emit('call-start');
  oldSdk.emit('error', { code: 'connect_failed' });
  oldSdk.emit('call-end');
  oldStart.resolve();
  await flush();
  assert.equal(b.elements['#start'].disabled, true);
  assert.equal(b.elements['#stop'].disabled, false);
  assert.ok(oldSdk.stops >= 2);
  b.instances[1].emit('call-start');
  assert.match(b.elements['#status'].textContent, /Connected/);
  await b.cancel();
  assert.equal(b.elements['#start'].disabled, false);
});

test('cancelling aborts pending session fetch and a late response cannot reconnect', async t => {
  const mint = deferred();
  const b = await browser(t, { fetch: () => mint.promise });
  await b.click();
  await b.cancel();
  assert.equal(b.requests[0].signal.aborted, true);
  mint.resolve({ ok: true, json: async () => ({ session_id: 'late' }) });
  await flush();
  assert.match(b.elements['#status'].textContent, /cancelled/);
  assert.equal(b.elements['#start'].disabled, false);
});

test('denied microphone explains permission recovery and consumes no minted sessions', async t => {
  const b = await browser(t, { microphone: () => Promise.reject(Object.assign(new Error('Permission denied'), { name: 'NotAllowedError' })) });
  await b.click();
  assert.match(b.elements['#status'].textContent, /browser site settings/);
  assert.equal(b.requests.length, 0);
  assert.equal(b.elements['#start'].disabled, false);
  assert.equal(b.elements['#stop'].disabled, true);
});

test('upstream capacity is distinct from local cooldown and lifetime budget', async t => {
  const f = await fixture(t, { fetchImpl: async () => Response.json({ private: 'do-not-forward' }, { status: 429 }) });
  const response = await f.request();
  assert.equal(response.status, 429);
  assert.deepEqual(JSON.parse(response.body), { error: 'at_capacity' });
  const cooldown = await f.request();
  assert.deepEqual(JSON.parse(cooldown.body), { error: 'call_cooldown' });
  assert.equal(cooldown.headers['retry-after'], '20');
});

test('reuse-state preserves only a valid invitation for the same session and both origins', () => {
  const token = 'a'.repeat(43);
  const sessionPath = resolve('build/android-voice/session.json');
  const targetFingerprint = pairedTargetFingerprint({ agentId: 'paired-agent', platform: 'android', identity: 'fixed-phone-target' });
  const options = { sessionPath, port: 19002, publicOrigin: 'https://phone.example.com', targetFingerprint };
  const previous = { session_file: sessionPath, target_fingerprint: targetFingerprint, url: `http://127.0.0.1:19002/#invite=${token}`, phone_url: `https://phone.example.com/#invite=${token}` };
  assert.equal(reusableInvitation(previous, options), token);
  for (const changed of [
    { session_file: resolve('build/status-probe/session.json') },
    { url: `http://127.0.0.1:19001/#invite=${token}` },
    { url: `http://127.0.0.1:19002/?leak=1#invite=${token}` },
    { url: `http://127.0.0.1:19002/#invite=${'b'.repeat(42)}` },
    { phone_url: `https://other.example.com/#invite=${token}` },
    { phone_url: `https://phone.example.com/#invite=${'b'.repeat(43)}` },
    { phone_url: null },
    { target_fingerprint: undefined },
    { target_fingerprint: 'b'.repeat(64) },
  ]) assert.throws(() => reusableInvitation({ ...previous, ...changed }, options), /Cannot reuse/);
  assert.throws(() => reusableInvitation(previous, { ...options, publicOrigin: undefined }), /Cannot reuse/);
  assert.equal(reusableInvitation({ ...previous, phone_url: null }, { ...options, publicOrigin: undefined }), token);
  assert.throws(() => reusableInvitation(previous, { ...options, targetFingerprint: pairedTargetFingerprint({ agentId: 'paired-agent', platform: 'windows', identity: 'fixed-laptop-target' }) }), /Cannot reuse/);
  assert.throws(() => reusableInvitation(previous, { ...options, targetFingerprint: pairedTargetFingerprint({ agentId: 'different-agent', platform: 'android', identity: 'fixed-phone-target' }) }), /Cannot reuse/);
});

test('public health exposes version only, without invitations or account credentials', async t => {
  const f = await fixture(t);
  const response = await f.request({ Authorization: '', Origin: '' }, 'GET', '/health');
  assert.equal(response.status, 200);
  assert.deepEqual(JSON.parse(response.body), { helper_version: 2, startup_timeout_ms: 45000 });
  assert.equal(f.calls.length, 0);
});

test('fresh-start CLI preflight validates without network or an existing metadata file', async t => {
  const directory = await mkdtemp(resolve(tmpdir(), 'buildify-webcall-preflight-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const scripts = resolve(directory, 'scripts');
  await mkdir(scripts);
  for (const filename of ['bolna-webcall.mjs', 'voice-session.mjs']) {
    await writeFile(resolve(scripts, filename), await readFile(new URL(filename, import.meta.url)));
  }
  await writeFile(resolve(directory, '.env'), 'BOLNA=synthetic-preflight-key\n');
  const sessionPath = resolve(directory, 'session.json');
  const statePath = resolve(directory, 'does-not-exist.json');
  await writeFile(sessionPath, JSON.stringify({ platform: 'android', public_url: 'https://synthetic-phone.trycloudflare.com/v1/status', token: 'x'.repeat(43), agent_id: 'synthetic-paired-agent' }));
  const scriptPath = resolve(scripts, 'bolna-webcall.mjs');
  const args = ['--import=data:text/javascript,globalThis.fetch=()=>{throw new Error("Unexpected network access")}', scriptPath, `--session=${sessionPath}`, `--state-file=${statePath}`, '--port=19031', '--public-origin=https://phone.example.com', '--check-start'];
  const run = promisify(execFile);
  const result = await run(process.execPath, args, { timeout: 5000, env: { ...process.env, BOLNA_WEBCALL_PUBLIC_ORIGIN: '' } });
  assert.deepEqual(JSON.parse(result.stdout), { valid: true, target_platform: 'android', helper_version: 2 });
  assert.equal(result.stderr, '');
  assert.ok(!result.stdout.includes('synthetic-preflight-key'));
  await assert.rejects(access(statePath), { code: 'ENOENT' });
  await assert.rejects(run(process.execPath, args.map(arg => arg === '--public-origin=https://phone.example.com' ? '--public-origin=http://phone.example.com' : arg), { timeout: 5000 }), /HTTPS origin/);
  await assert.rejects(access(statePath), { code: 'ENOENT' });
});
