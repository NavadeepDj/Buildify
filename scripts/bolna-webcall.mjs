import http from 'node:http';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateVoiceSession } from './voice-session.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

export function validatePublicOrigin(value) {
  if (!value) return null;
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password || url.pathname !== '/' || url.search || url.hash) {
    throw new Error('The phone call origin must be an HTTPS origin without a path or credentials.');
  }
  return url.origin;
}

export function pairedTargetFingerprint(paired) {
  return createHash('sha256').update(JSON.stringify([paired.agentId, paired.platform, paired.identity])).digest('hex');
}

/** Reuse only an invitation for this exact target, agent and pair of call origins. */
export function reusableInvitation(previous, { sessionPath, port, publicOrigin, targetFingerprint }) {
  try {
    const pathKey = value => {
      const path = resolve(value);
      return process.platform === 'win32' ? path.toLowerCase() : path;
    };
    if (!/^[a-f0-9]{64}$/.test(targetFingerprint ?? '') || previous.target_fingerprint !== targetFingerprint) throw new Error();
    if (typeof previous.session_file !== 'string' || pathKey(previous.session_file) !== pathKey(sessionPath)) throw new Error();
    const local = new URL(previous.url);
    const token = /^#invite=([A-Za-z0-9_-]{43})$/.exec(local.hash)?.[1];
    const validUrl = (url, origin) => url.origin === origin && url.pathname === '/' && !url.search && !url.username && !url.password && url.hash === `#invite=${token}`;
    if (!token || !validUrl(local, `http://127.0.0.1:${port}`)) throw new Error();
    const phoneOrigin = validatePublicOrigin(publicOrigin);
    if (phoneOrigin ? !previous.phone_url || !validUrl(new URL(previous.phone_url), phoneOrigin) : previous.phone_url != null) throw new Error();
    return token;
  } catch (_) {
    throw new Error('Cannot reuse this call invitation: the saved target, origins or token do not match. Start without --reuse-state to create a new invitation.');
  }
}

function sameToken(value, expected) {
  if (typeof value !== 'string') return false;
  const actual = Buffer.from(value);
  const wanted = Buffer.from(expected);
  return actual.length === wanted.length && timingSafeEqual(actual, wanted);
}

export function createWebcallServer({ key, getAgentId, targetPlatform = null, port = 19001, publicOrigin, inviteToken = randomBytes(32).toString('base64url'), fetchImpl = fetch, now = Date.now, cooldownMs = 20000, maxMints = 8 }) {
  const localOrigin = `http://127.0.0.1:${port}`;
  const phoneOrigin = validatePublicOrigin(publicOrigin);
  const origins = new Set([localOrigin, ...(phoneOrigin ? [phoneOrigin] : [])]);
  const hosts = new Set([...origins].map(origin => new URL(origin).host));
  let lastMint = -Infinity;
  let mintCount = 0;
  if (targetPlatform != null && !['android', 'windows'].includes(targetPlatform)) throw new Error('Unknown call target.');
  const targetLabel = targetPlatform === 'android' ? 'Runs on your Android phone' : targetPlatform === 'windows' ? 'Runs on your laptop' : 'Paired Buildify device';
  const page = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Call Buildify</title>
<style>body{margin:0;background:#121514;color:#edf2ee;font:16px system-ui;line-height:1.6}main{max-width:760px;margin:5vh auto;padding:24px}h1{font-size:36px;line-height:1.2}p{color:#bdc9c0}button{border:1px solid #607068;padding:14px 24px;border-radius:8px;background:#20362a;color:white;font:inherit;cursor:pointer;margin:8px 8px 8px 0}button:disabled{opacity:.45;cursor:default}#status{padding:16px;background:#1c2420;border-radius:8px;margin:20px 0}li{margin:8px 0}.small{font-size:13px}</style>
<main><p>BUILDIFY VOICE</p><h1>You call. Buildify listens.</h1><h2>${targetLabel}</h2><p>Start a browser voice call with your paired Bolna agent. On Android, use Chrome and allow microphone access. No phone number or outbound callback is needed.</p>
<button id="start" disabled>Call Buildify</button><button id="stop" disabled>End call</button><div id="status" role="status">Checking your call invitation…</div>
<h2>Try these requests</h2><ul><li>What models are installed on this Buildify device?</li><li>Prepare a compatible model for short answers.</li><li>What is the setup progress?</li><li>List my projects and explain the latest error.</li></ul>
<p>Keep the paired Buildify app and its connection open. Review and approve requested changes in that app. Keep this call invitation private; anyone with it can start calls against your Bolna account.</p><p class="small">Your voice is processed by Bolna and its configured providers. Your account API key stays on the computer running the call helper. This is a browser voice call, not a telephone dial-in service.</p></main>
<script src="https://cdn.jsdelivr.net/gh/bolna-ai/web-call@v3.0.1/dist/bolna-web-call.min.js"></script>
<script>
const start=document.querySelector('#start'),stop=document.querySelector('#stop'),status=document.querySelector('#status');
const fragment=new URLSearchParams(location.hash.slice(1));
let invitation=fragment.get('invite');
try{if(invitation){sessionStorage.setItem('buildify-call-invite',invitation);history.replaceState(null,'',location.pathname);}else{invitation=sessionStorage.getItem('buildify-call-invite');}}catch(_){}
const microphoneAvailable=!!navigator.mediaDevices&&typeof navigator.mediaDevices.getUserMedia==='function';
const ready=!!invitation&&window.isSecureContext&&typeof BolnaWebCall==='function'&&microphoneAvailable;
status.textContent=!invitation?'Open the private call invitation generated by Buildify.':!window.isSecureContext?'Open this invitation over HTTPS to use your microphone.':typeof BolnaWebCall!=='function'?'The voice SDK could not load. Check your connection and reload.':!microphoneAvailable?'Microphone access is unavailable. Open this link in Chrome.':'Ready. Keep the paired Buildify app and its connection open.';
start.disabled=!ready;
if(ready){
let active=null;
const current=attempt=>active===attempt&&!attempt.ended;
const cancelled=()=>new Error('Call cancelled.');
const stopSdk=attempt=>{try{Promise.resolve(attempt.call?.stop()).catch(()=>{});}catch(_){}};
const finish=(attempt,message)=>{
  if(!current(attempt))return;
  attempt.ended=true;active=null;clearTimeout(attempt.timer);attempt.abort.abort();attempt.cancel();
  start.disabled=false;stop.disabled=true;stop.textContent='End call';status.textContent=message;
  // Do not wait for network hangup before restoring controls. Each attempt has its own SDK instance.
  stopSdk(attempt);
};
const messageFor=error=>{
  const code=error?.code||error?.name;
  if(code==='NotAllowedError'||code==='SecurityError'||code==='microphone_denied')return 'Microphone permission was denied. Allow the microphone in browser site settings, then retry.';
  if(code==='NotFoundError')return 'No microphone was found. Connect one, then retry.';
  if(code==='NotReadableError'||code==='AbortError')return 'The microphone or connection was interrupted. Close other apps using the microphone, then retry.';
  if(code==='at_capacity')return 'Bolna has no free call slots. Wait for another call to finish, then retry.';
  if(code==='autoplay_blocked')return 'The browser blocked call audio. End other calls and tap Call Buildify again.';
  if(code==='call_rejected')return 'Bolna declined this call. Retry with a fresh session; if it repeats, check the paired agent and account.';
  if(code==='connect_failed')return 'The voice connection failed. Check your network or try another connection, then retry.';
  if(code==='mint_failed'&&error.message)return error.message;
  return error?.message||'Could not start the call. Check your connection and retry.';
};
start.onclick=()=>{
  if(active)return;
  let cancel;
  const attempt={ended:false,phase:'microphone',abort:new AbortController(),cancelled:new Promise(resolve=>{cancel=resolve;})};
  attempt.cancel=cancel;active=attempt;
  start.disabled=true;stop.disabled=false;stop.textContent='Cancel call';
  status.textContent='Allow microphone access when your browser asks. You can cancel while connecting.';
  attempt.timer=setTimeout(()=>finish(attempt,attempt.phase==='microphone'?'Microphone permission timed out. Dismiss the browser prompt, allow access in site settings, then retry.':'Call connection timed out. Check your network and Bolna account, then retry.'),45000);
  try{
    attempt.call=new BolnaWebCall({getSession:async()=>{
      if(!current(attempt))throw cancelled();
      // v3.0.1 normally mints before its mic prompt. Obtain permission first so a long
      // prompt cannot expire the short-lived session. Always release even a late grant.
      const permission=navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true,autoGainControl:true},video:false}).then(stream=>{
        stream.getTracks().forEach(track=>track.stop());
        if(!current(attempt))throw cancelled();
      }).catch(error=>{throw new Error(messageFor(error));});
      await Promise.race([permission,attempt.cancelled.then(()=>{throw cancelled();})]);
      if(!current(attempt))throw cancelled();
      attempt.phase='session';status.textContent='Requesting a fresh call session…';
      const response=await fetch('/session',{method:'POST',signal:attempt.abort.signal,headers:{'X-Buildify-Webcall':'1','Authorization':'Bearer '+invitation}});
      if(!current(attempt))throw cancelled();
      if(!response.ok){
        if(response.status===429){
          const detail=await response.json().catch(()=>({}));
          throw new Error(detail.error==='at_capacity'?'Bolna has no free call slots. Wait for another call to finish, then retry.':detail.error==='call_budget_exhausted'?'This helper has reached its eight-call limit. Restart the call helper to continue.':'Please wait 20 seconds before starting another call.');
        }
        throw new Error(response.status===403?'The call invitation is invalid or expired. Open the latest private call link.':'The call helper could not reach Bolna ('+response.status+'). Check the account and connection, then retry.');
      }
      const session=await response.json();
      if(!current(attempt))throw cancelled();
      attempt.phase='connecting';status.textContent='Connecting the voice call. You can cancel.';
      return session;
    }});
    attempt.call.on('state-change',state=>{if(current(attempt)&&state==='ringing')status.textContent='Calling Buildify. Waiting for the agent to answer…';});
    attempt.call.on('call-start',()=>{
      if(!current(attempt)){stopSdk(attempt);return;}
      clearTimeout(attempt.timer);attempt.phase='active';stop.textContent='End call';status.textContent='Connected. Speak to Buildify.';
    });
    attempt.call.on('call-end',()=>finish(attempt,'Call ended. You can start another call.'));
    attempt.call.on('error',error=>finish(attempt,messageFor(error)));
    // Start directly in the click handler; never let an unresolved SDK promise trap controls.
    Promise.resolve(attempt.call.start()).catch(error=>{if(current(attempt))finish(attempt,messageFor(error));});
  }catch(error){finish(attempt,messageFor(error));}
};
stop.onclick=()=>{if(active)finish(active,active.phase==='active'?'Call ended. You can start another call.':'Call cancelled. You can retry. Dismiss any remaining microphone prompt.');};
window.addEventListener('pagehide',()=>{if(active)finish(active,'Call ended.');});
}
</script></html>`;
  const server = http.createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Permissions-Policy', 'microphone=(self)');
    if (!hosts.has(req.headers.host)) { res.writeHead(403).end(); return; }
    if (req.method === 'GET' && req.url === '/health') { res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ helper_version: 2, startup_timeout_ms: 45000 })); return; }
    if (req.method === 'GET' && req.url === '/target') {
      if (!targetPlatform || !sameToken(req.headers.authorization, `Bearer ${inviteToken}`)) { res.writeHead(403).end(); return; }
      res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ platform: targetPlatform })); return;
    }
    if (req.method === 'GET' && req.url === '/') { res.setHeader('Content-Type', 'text/html; charset=utf-8'); res.end(page); return; }
    const expectedOrigin = req.headers.host === new URL(localOrigin).host ? localOrigin : phoneOrigin;
    if (req.method !== 'POST' || req.url !== '/session' || req.headers.origin !== expectedOrigin || !origins.has(req.headers.origin) || req.headers['x-buildify-webcall'] !== '1' || !sameToken(req.headers.authorization, `Bearer ${inviteToken}`)) {
      res.writeHead(403).end(); return;
    }
    // Reserve before the network call so parallel requests cannot spend beyond the limit.
    if (now() - lastMint < cooldownMs || mintCount >= maxMints) {
      res.setHeader('Content-Type', 'application/json');
      if (mintCount < maxMints) res.setHeader('Retry-After', String(Math.ceil(cooldownMs / 1000)));
      res.writeHead(429).end(JSON.stringify({ error: mintCount >= maxMints ? 'call_budget_exhausted' : 'call_cooldown' })); return;
    }
    lastMint = now(); mintCount++;
    try {
      const agentId = await getAgentId();
      if (!agentId || typeof agentId !== 'string') throw new Error('Missing paired agent.');
      const response = await fetchImpl('https://api.bolna.ai/web-call/freeswitch-session', {
        method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ agent_id: agentId }), signal: AbortSignal.timeout(15000),
      });
      if (response.status === 429) { res.setHeader('Content-Type', 'application/json'); res.writeHead(429).end(JSON.stringify({ error: 'at_capacity' })); return; }
      if (!response.ok) { res.writeHead(502).end('Bolna could not create a call session.'); return; }
      const session = await response.json();
      res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(session));
    } catch (_) { res.writeHead(502).end('Bolna connection unavailable.'); }
  });
  return { server, url: `${localOrigin}/#invite=${inviteToken}`, phoneUrl: phoneOrigin ? `${phoneOrigin}/#invite=${inviteToken}` : null };
}

function option(name, fallback) {
  const prefix = `--${name}=`;
  const inline = process.argv.find(arg => arg.startsWith(prefix));
  if (inline) return inline.slice(prefix.length);
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

async function main() {
  const sessionPath = resolve(root, option('session', 'build/status-probe/session.json'));
  const statePath = resolve(root, option('state-file', resolve(dirname(sessionPath), 'webcall-server.json')));
  const env = await readFile(resolve(root, '.env'), 'utf8');
  const line = env.split(/\r?\n/).find(line => /^\s*BOLNA\s*=/.test(line));
  const key = line?.slice(line.indexOf('=') + 1).trim().replace(/^(['"])(.*)\1$/, '$2');
  const loadPair = async () => {
    const source = validateVoiceSession(JSON.parse((await readFile(sessionPath, 'utf8')).replace(/^\uFEFF/, '')));
    const targetPath = resolve(root, source.target_session ?? sessionPath);
    const target = targetPath === sessionPath ? source : validateVoiceSession(JSON.parse((await readFile(targetPath, 'utf8')).replace(/^\uFEFF/, '')));
    return { agentId: source.agent_id, platform: target.platform ?? 'windows', identity: JSON.stringify([targetPath, target.platform, target.public_url, target.token, source.voice_mode ?? null]) };
  };
  const paired = await loadPair();
  const getAgentId = async () => {
    const current = await loadPair();
    if (current.identity !== paired.identity || current.agentId !== paired.agentId) throw new Error('Call target changed. Restart the call helper.');
    return current.agentId;
  };
  if (!key || !(await getAgentId())) throw new Error('Configure the paired Bolna agent first.');
  const port = Number(option('port', '19001'));
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Use a port between 1024 and 65535.');
  const publicOrigin = validatePublicOrigin(option('public-origin', process.env.BOLNA_WEBCALL_PUBLIC_ORIGIN));
  if (process.argv.includes('--check-start')) {
    if (process.argv.includes('--reuse-state') || process.argv.includes('--check-reuse-state')) throw new Error('Choose fresh-start or invitation-reuse validation.');
    console.log(JSON.stringify({ valid: true, target_platform: paired.platform, helper_version: 2 }));
    return;
  }
  const targetFingerprint = pairedTargetFingerprint(paired);
  const checkReuse = process.argv.includes('--check-reuse-state');
  const inviteToken = process.argv.includes('--reuse-state') || checkReuse
    ? reusableInvitation(JSON.parse((await readFile(statePath, 'utf8')).replace(/^\uFEFF/, '')), { sessionPath, port, publicOrigin, targetFingerprint })
    : undefined;
  if (checkReuse) {
    console.log(JSON.stringify({ valid: true, target_platform: paired.platform, helper_version: 2 }));
    return;
  }
  const webcall = createWebcallServer({ key, getAgentId, targetPlatform: paired.platform, port, publicOrigin, inviteToken });
  await new Promise((resolveListen, reject) => {
    webcall.server.once('error', reject);
    webcall.server.listen(port, '127.0.0.1', resolveListen);
  });
  await mkdir(dirname(statePath), { recursive: true });
  try {
    await writeFile(statePath, JSON.stringify({ pid: process.pid, helper_version: 2, url: webcall.url, phone_url: webcall.phoneUrl, session_file: sessionPath, target_platform: paired.platform, target_fingerprint: targetFingerprint }, null, 2), { mode: 0o600 });
  } catch (error) { webcall.server.close(); throw error; }
  console.log(`Call helper ready. Private invitation saved in ${statePath}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
