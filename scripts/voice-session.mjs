import { resolve, join } from 'node:path';
import { readFile, writeFile, mkdir, rename } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

export function sessionFile(args, rootPath) {
  const value = args.find(arg => arg.startsWith('--session='));
  return resolve(rootPath, value ? value.slice('--session='.length) : 'build/status-probe/session.json');
}

export function validateVoiceSession(session) {
  if (!session || !/^https:\/\/[a-z0-9-]+\.trycloudflare\.com\/v1\/status$/.test(session.public_url ?? '')) {
    throw new Error('Start the authenticated device voice tunnel first.');
  }
  if (typeof session.token !== 'string' || !/^[A-Za-z0-9_+/=\-]{32,256}$/.test(session.token)) {
    throw new Error('A valid device pairing token is required.');
  }
  if (session.platform != null && !['android', 'windows'].includes(session.platform)) {
    throw new Error('Unsupported voice target platform.');
  }
  if (session.voice_mode != null) {
    if (!['phone', 'laptop'].includes(session.voice_mode) || (session.voice_mode === 'phone' && session.platform !== 'android')) throw new Error('Unsupported mobile voice mode.');
    if (session.voice_mode === 'phone' && session.target_session) throw new Error('Phone mode cannot point at a laptop session. Reconfigure phone pairing.');
    if (session.voice_mode === 'laptop' && (typeof session.target_session !== 'string' || !session.target_session.trim())) throw new Error('Laptop mode needs an explicit target session.');
  }
  return session;
}

export function manifestUrl(session) {
  validateVoiceSession(session);
  return session.platform === 'android'
    ? session.public_url.replace(/\/v1\/status$/, '/v1/tools')
    : 'http://127.0.0.1:18791/v1/tools';
}

export function androidVoicePlan(rootPath, { runOn = 'phone', runOnExplicit = false, targetSession, port } = {}) {
  if (!['phone', 'laptop'].includes(runOn)) throw new Error('Choose RunOn phone or laptop.');
  if (targetSession && runOnExplicit && runOn === 'phone') throw new Error('TargetSession selects a laptop. Use RunOn laptop or remove TargetSession.');
  const mode = targetSession && !runOnExplicit ? 'laptop' : runOn;
  const demoDir = resolve(rootPath, mode === 'phone' ? 'build/android-voice' : 'build/mobile-laptop-voice');
  const chosenPort = port == null ? (mode === 'phone' ? 19002 : 19003) : Number(port);
  if (!Number.isInteger(chosenPort) || chosenPort < 1024 || chosenPort > 65535) throw new Error('Choose a local port from 1024 to 65535.');
  return { runOn: mode, demoDir, sessionPath: join(demoDir, 'session.json'), port: chosenPort,
    ...(mode === 'laptop' ? { targetSession: resolve(rootPath, targetSession || 'build/status-probe/session.json') } : {}) };
}

export function androidVoiceSession(pairing, plan, previous, target) {
  let session;
  if (plan.runOn === 'laptop') {
    validateVoiceSession(target);
    if (target.platform === 'android') throw new Error('Laptop mode needs a Windows target session.');
    session = { platform: 'windows', public_url: target.public_url, token: target.token, voice_mode: 'laptop', target_session: plan.targetSession };
  } else {
    validateVoiceSession(pairing);
    if (pairing.platform !== 'android') throw new Error('Copy Android pairing details from the APK.');
    session = { platform: 'android', public_url: pairing.public_url, token: pairing.token, voice_mode: 'phone' };
  }
  const oldMode = previous?.voice_mode ?? (previous?.target_session ? 'laptop' : 'phone');
  const sameTarget = plan.runOn === 'phone' ? !previous?.target_session : previous?.target_session === plan.targetSession;
  if (oldMode === plan.runOn && sameTarget && typeof previous?.agent_id === 'string') session.agent_id = previous.agent_id;
  return session;
}

export async function voiceSessionCommand(args, input) {
  const [command, ...options] = args;
  if (!['android-plan', 'configure-android'].includes(command) || options.some(option => !/^--(?:root=.+|run-on=(?:phone|laptop)|run-on-explicit|target-session=.+|port=\d+)$/.test(option))) throw new Error('Use android-plan or configure-android with valid routing options.');
  const option = name => options.find(value => value.startsWith(`--${name}=`))?.slice(name.length + 3);
  const root = resolve(option('root') ?? fileURLToPath(new URL('../', import.meta.url)));
  const plan = androidVoicePlan(root, { runOn: option('run-on'), runOnExplicit: options.includes('--run-on-explicit'), targetSession: option('target-session'), port: option('port') });
  if (command === 'android-plan') return plan;
  const readJson = async path => JSON.parse((await readFile(path, 'utf8')).replace(/^\uFEFF/, ''));
  let previous, target, pairing;
  try { previous = await readJson(plan.sessionPath); } catch (error) { if (error.code !== 'ENOENT') throw new Error('The previous voice session could not be read.'); }
  if (plan.targetSession) {
    try { target = await readJson(plan.targetSession); } catch (_) { throw new Error('Start the Windows voice bridge before selecting laptop mode.'); }
  } else {
    try {
      if (input == null) { input = ''; for await (const chunk of process.stdin) input += chunk; }
      pairing = JSON.parse(input.replace(/^\uFEFF/, ''));
    } catch (_) { throw new Error('Invalid Android pairing details. Copy them again from the app.'); }
  }
  const session = androidVoiceSession(pairing, plan, previous, target);
  await mkdir(plan.demoDir, { recursive: true });
  const temporary = `${plan.sessionPath}.${randomUUID()}.tmp`;
  await writeFile(temporary, JSON.stringify(session, null, 2), { mode: 0o600 });
  await rename(temporary, plan.sessionPath);
  return plan;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  voiceSessionCommand(process.argv.slice(2)).then(result => console.log(JSON.stringify(result))).catch(error => {
    console.error(error?.code ? 'The local voice session could not be configured.' : error.message);
    process.exitCode = 1;
  });
}
