import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { manifestUrl, sessionFile, validateVoiceSession, androidVoicePlan, androidVoiceSession, voiceSessionCommand } from './voice-session.mjs';

const session = { platform: 'android', public_url: 'https://paired-phone.trycloudflare.com/v1/status', token: 'synthetic-android-pairing-token-1234567890' };
test('Android uses its own authenticated device manifest; Windows keeps loopback', () => {
  assert.equal(manifestUrl(session), 'https://paired-phone.trycloudflare.com/v1/tools');
  assert.equal(manifestUrl({ ...session, platform: 'windows' }), 'http://127.0.0.1:18791/v1/tools');
  assert.match(sessionFile(['--session=build/android-voice/session.json'], process.cwd()), /android-voice/);
});

test('phone is the default and laptop mode has an independent session, helper directory, and port', () => {
  const phone = androidVoicePlan(process.cwd());
  const laptop = androidVoicePlan(process.cwd(), { runOn: 'laptop' });
  assert.equal(phone.runOn, 'phone');
  assert.equal(phone.targetSession, undefined);
  assert.equal(phone.port, 19002);
  assert.equal(laptop.port, 19003);
  assert.equal(laptop.targetSession, resolve('build/status-probe/session.json'));
  assert.notEqual(phone.sessionPath, laptop.sessionPath);
  assert.notEqual(phone.demoDir, laptop.demoDir);
  assert.match(laptop.demoDir, /mobile-laptop-voice$/);
});

test('legacy TargetSession deliberately selects laptop and conflicting explicit phone selection fails', () => {
  assert.equal(androidVoicePlan(process.cwd(), { targetSession: 'build/custom/session.json' }).runOn, 'laptop');
  assert.throws(() => androidVoicePlan(process.cwd(), { runOn: 'phone', runOnExplicit: true, targetSession: 'build/custom/session.json' }), /TargetSession selects a laptop/);
  assert.equal(androidVoicePlan(process.cwd(), { runOn: 'laptop', runOnExplicit: true, targetSession: 'build/custom/session.json' }).targetSession, resolve('build/custom/session.json'));
  assert.throws(() => androidVoicePlan(process.cwd(), { runOn: 'server' }));
  for (const port of [0, 1023, 65536, 'secret', 19002.5]) assert.throws(() => androidVoicePlan(process.cwd(), { port }));
});

test('phone mode drops stale laptop routing and its agent instead of silently reusing either', () => {
  const plan = androidVoicePlan(process.cwd());
  const stale = { ...session, agent_id: 'previous-laptop-agent', target_session: resolve('build/status-probe/session.json') };
  const configured = androidVoiceSession(session, plan, stale);
  assert.equal(configured.voice_mode, 'phone');
  assert.equal(configured.target_session, undefined);
  assert.equal(configured.agent_id, undefined);
  assert.equal(stale.agent_id, 'previous-laptop-agent');
  assert.equal(androidVoiceSession(session, plan, { ...session, agent_id: 'compatible-phone-agent' }).agent_id, 'compatible-phone-agent');
});

test('declared mode and target routing must agree before any connector can use a session', () => {
  assert.throws(() => validateVoiceSession({ ...session, voice_mode: 'phone', target_session: 'build/status-probe/session.json' }), /Phone mode cannot point/);
  assert.throws(() => validateVoiceSession({ ...session, voice_mode: 'laptop' }), /explicit target/);
  assert.throws(() => validateVoiceSession({ ...session, voice_mode: 'other' }), /Unsupported mobile/);
  assert.equal(validateVoiceSession({ ...session, voice_mode: 'phone' }).voice_mode, 'phone');
  assert.equal(validateVoiceSession({ ...session, platform: 'windows', voice_mode: 'laptop', target_session: 'build/status-probe/session.json' }).platform, 'windows');
  // Legacy sessions remain readable so an explicit reconfiguration can migrate them.
  assert.equal(validateVoiceSession({ ...session, target_session: 'legacy-target.json' }).target_session, 'legacy-target.json');
});

test('laptop mode requires a Windows target and retains only its own compatible source agent', () => {
  const plan = androidVoicePlan(process.cwd(), { runOn: 'laptop' });
  const windows = { ...session, platform: 'windows' };
  const previous = { ...session, voice_mode: 'laptop', target_session: plan.targetSession, agent_id: 'compatible-laptop-agent' };
  assert.equal(androidVoiceSession(session, plan, previous, windows).agent_id, 'compatible-laptop-agent');
  assert.equal(androidVoiceSession(session, plan, { ...previous, target_session: 'another-target.json' }, windows).agent_id, undefined);
  assert.equal(androidVoiceSession(session, plan, { ...previous, voice_mode: 'phone' }, windows).agent_id, undefined);
  assert.throws(() => androidVoiceSession(session, plan, previous, session), /Windows target/);
  assert.throws(() => androidVoiceSession(windows, androidVoicePlan(process.cwd()), previous), /Android pairing/);
  assert.equal(androidVoiceSession(undefined, plan, previous, windows).platform, 'windows');
  assert.equal(androidVoiceSession(undefined, plan, previous, windows).token, windows.token);
});

test('configuring either mode cannot rewrite the other mode session, token, target, or agent', async t => {
  const root = await mkdtemp(join(tmpdir(), 'buildify-voice-routing-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const phone = androidVoicePlan(root);
  const laptop = androidVoicePlan(root, { runOn: 'laptop' });
  await mkdir(join(root, 'build/status-probe'), { recursive: true });
  await writeFile(laptop.targetSession, JSON.stringify({ ...session, platform: 'windows', agent_id: 'desktop-agent' }));
  await mkdir(phone.demoDir, { recursive: true });
  await writeFile(phone.sessionPath, JSON.stringify({ ...session, target_session: laptop.targetSession, agent_id: 'legacy-cross-target-agent' }));
  const configure = async (mode, pairing) => voiceSessionCommand(['configure-android', `--root=${root}`, `--run-on=${mode}`, '--run-on-explicit'], JSON.stringify(pairing));
  await configure('phone', session);
  const read = async path => JSON.parse(await readFile(path, 'utf8'));
  assert.equal((await read(phone.sessionPath)).agent_id, undefined);
  await writeFile(phone.sessionPath, JSON.stringify({ ...await read(phone.sessionPath), agent_id: 'phone-agent' }));
  const phoneBefore = await readFile(phone.sessionPath, 'utf8');
  await configure('laptop', session);
  assert.equal(await readFile(phone.sessionPath, 'utf8'), phoneBefore);
  await writeFile(laptop.sessionPath, JSON.stringify({ ...await read(laptop.sessionPath), agent_id: 'laptop-agent' }));
  const laptopBefore = await readFile(laptop.sessionPath, 'utf8');
  await configure('phone', { ...session, token: 'rotated-private-phone-token-123456789012345' });
  assert.equal(await readFile(laptop.sessionPath, 'utf8'), laptopBefore);
  assert.equal((await read(phone.sessionPath)).agent_id, 'phone-agent');
  await configure('laptop', session);
  assert.equal((await read(laptop.sessionPath)).agent_id, 'laptop-agent');
  assert.equal((await read(laptop.sessionPath)).target_session, laptop.targetSession);
  assert.equal((await read(phone.sessionPath)).target_session, undefined);
  assert.equal((await read(laptop.targetSession)).agent_id, 'desktop-agent');
});

test('configure CLI receives pairing on stdin and prints only its routing plan', async t => {
  const root = await mkdtemp(join(tmpdir(), 'buildify-voice-cli-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const script = fileURLToPath(new URL('./voice-session.mjs', import.meta.url));
  const output = execFileSync(process.execPath, [script, 'configure-android', `--root=${root}`, '--run-on=phone'], { input: JSON.stringify(session), encoding: 'utf8' });
  assert.equal(output.includes(session.token), false);
  assert.equal(output.includes(session.public_url), false);
  const plan = JSON.parse(output);
  assert.equal(plan.runOn, 'phone');
  assert.equal(JSON.parse(await readFile(plan.sessionPath, 'utf8')).token, session.token);
});

test('laptop configure CLI needs no Android pairing input and uses only Windows target credentials', async t => {
  const root = await mkdtemp(join(tmpdir(), 'buildify-laptop-voice-cli-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const laptop = androidVoicePlan(root, { runOn: 'laptop' });
  const windows = { platform: 'windows', public_url: 'https://laptop-host.trycloudflare.com/v1/status', token: 'private-windows-target-token-1234567890', agent_id: 'existing-desktop-agent' };
  await mkdir(join(root, 'build/status-probe'), { recursive: true });
  await writeFile(laptop.targetSession, JSON.stringify(windows));
  const script = fileURLToPath(new URL('./voice-session.mjs', import.meta.url));
  const output = execFileSync(process.execPath, [script, 'configure-android', `--root=${root}`, '--run-on=laptop', '--run-on-explicit'], { encoding: 'utf8', timeout: 3000 });
  assert.equal(output.includes(windows.token), false);
  const configured = JSON.parse(await readFile(laptop.sessionPath, 'utf8'));
  assert.equal(configured.platform, 'windows');
  assert.equal(configured.voice_mode, 'laptop');
  assert.equal(configured.token, windows.token);
  assert.equal(configured.public_url, windows.public_url);
  assert.equal(configured.target_session, laptop.targetSession);
  assert.equal(configured.agent_id, undefined);
  // Legacy callers may still supply copied APK details; laptop mode ignores them.
  await voiceSessionCommand(['configure-android', `--root=${root}`, '--run-on=laptop'], JSON.stringify(session));
  assert.equal(JSON.parse(await readFile(laptop.sessionPath, 'utf8')).token, windows.token);
  assert.equal(JSON.parse(await readFile(laptop.targetSession, 'utf8')).agent_id, windows.agent_id);
});

test('Windows launcher ShowPlan previews explicit routing before any pairing or API access', { skip: process.platform !== 'win32' }, () => {
  const launcher = fileURLToPath(new URL('./start-android-voice.ps1', import.meta.url));
  const show = (...args) => JSON.parse(execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', launcher, '-ShowPlan', ...args], { encoding: 'utf8' }));
  assert.equal(show().runOn, 'phone');
  assert.equal(show('-RunOn', 'laptop').port, 19003);
  assert.equal(show('-TargetSession', 'build/status-probe/session.json').runOn, 'laptop');
  const rejected = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', launcher, '-ShowPlan', '-RunOn', 'phone', '-TargetSession', 'build/status-probe/session.json'], { encoding: 'utf8' });
  assert.notEqual(rejected.status, 0);
});
test('rejects arbitrary URLs, credentials, routes, tokens and platforms before connecting', () => {
  for (const public_url of ['http://paired-phone.trycloudflare.com/v1/status', 'https://evil.example/v1/status', 'https://user@paired-phone.trycloudflare.com/v1/status', 'https://paired-phone.trycloudflare.com/v1/status?token=x', 'https://paired-phone.trycloudflare.com/v1/tools']) {
    assert.throws(() => validateVoiceSession({ ...session, public_url }));
  }
  for (const token of ['', 'short', ' '.repeat(32), 'x'.repeat(257)]) assert.throws(() => validateVoiceSession({ ...session, token }));
  assert.throws(() => validateVoiceSession({ ...session, platform: 'other' }));
});
