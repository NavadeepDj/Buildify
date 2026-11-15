import http from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';

const root = new URL('../', import.meta.url);
const session = JSON.parse((await readFile(new URL('build/status-probe/session.json', root), 'utf8')).replace(/^\uFEFF/, ''));
const env = await readFile(new URL('.env', root), 'utf8');
const line = env.split(/\r?\n/).find(line => /^\s*BOLNA\s*=/.test(line));
const key = line?.slice(line.indexOf('=') + 1).trim().replace(/^(['"])(.*)\1$/, '$2');
if (!key || !session.agent_id) throw new Error('Configure the paired Bolna agent first.');
const origin = 'http://127.0.0.1:19001';
let lastMint = 0;
let mintCount = 0;
const page = `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Call Buildify</title>
<style>body{margin:0;background:#121514;color:#edf2ee;font:16px system-ui;line-height:1.6}main{max-width:760px;margin:8vh auto;padding:24px}h1{font-size:36px;line-height:1.2}p{color:#bdc9c0}button{border:1px solid #607068;padding:14px 24px;border-radius:8px;background:#20362a;color:white;font:inherit;cursor:pointer;margin:8px 8px 8px 0}button:disabled{opacity:.45;cursor:default}#status{padding:16px;background:#1c2420;border-radius:8px;margin:20px 0}li{margin:8px 0}.small{font-size:13px}</style>
<main><p>BUILDIFY VOICE PROTOTYPE</p><h1>You call. Buildify listens.</h1><p>Start a browser voice call with your paired Bolna agent. No phone number or outbound callback is needed.</p>
<button id="start">Call Buildify</button><button id="stop" disabled>End call</button><div id="status" role="status">Ready. Keep the Buildify desktop app and tool tunnel open.</div>
<h2>Try these requests</h2><ul><li>What models are installed on my laptop?</li><li>Run TinyLlama for short answers.</li><li>What is the setup progress?</li><li>List my projects and explain the latest error.</li></ul>
<p>When Buildify shows a plan or action, review and approve it in the desktop app. The agent cannot bypass that approval. Secrets and account sign-in stay in the app.</p><p class="small">This call uses your Bolna account balance. Your voice is processed by Bolna and its configured providers. This local page does not contain your API key.</p></main>
<script src="https://cdn.jsdelivr.net/gh/bolna-ai/web-call@v3.0.1/dist/bolna-web-call.min.js"></script>
<script>
const start=document.querySelector('#start'),stop=document.querySelector('#stop'),status=document.querySelector('#status');
const call=new BolnaWebCall({getSession:async()=>{const response=await fetch('/session',{method:'POST',headers:{'X-Buildify-Webcall':'1'}});if(!response.ok)throw new Error('Could not start call ('+response.status+').');return response.json();}});
call.on('state-change',state=>{status.textContent='Call status: '+state;});
call.on('call-start',()=>{start.disabled=true;stop.disabled=false;status.textContent='Connected. Speak to Buildify.';});
call.on('call-end',()=>{start.disabled=false;stop.disabled=true;status.textContent='Call ended. You can start another call.';});
call.on('error',error=>{status.textContent='Call error: '+error.code+'. Check microphone access and your Bolna account.';start.disabled=false;stop.disabled=true;});
start.onclick=async()=>{start.disabled=true;status.textContent='Connecting. Allow microphone access when your browser asks.';try{await call.start();}catch(error){status.textContent=error.message;start.disabled=false;}};
stop.onclick=()=>call.stop();
</script></html>`;
const server = http.createServer(async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  if (req.headers.host !== '127.0.0.1:19001') { res.writeHead(403).end(); return; }
  if (req.method === 'GET' && req.url === '/') { res.setHeader('Content-Type','text/html; charset=utf-8');res.end(page);return; }
  if (req.method !== 'POST' || req.url !== '/session' || req.headers.origin !== origin || req.headers['x-buildify-webcall'] !== '1') { res.writeHead(403).end();return; }
  if (Date.now()-lastMint < 20000 || mintCount >= 8) { res.writeHead(429).end();return; }
  lastMint=Date.now();mintCount++;
  try {
    const response=await fetch('https://api.bolna.ai/web-call/freeswitch-session',{
      method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},
      body:JSON.stringify({agent_id:session.agent_id}),signal:AbortSignal.timeout(15000),
    });
    if(!response.ok){res.writeHead(502).end('Bolna could not create a call session.');return;}
    res.setHeader('Content-Type','application/json');res.end(await response.text());
  } catch (_) { res.writeHead(502).end('Bolna connection unavailable.'); }
});
server.listen(19001,'127.0.0.1',async()=>{
  await writeFile(new URL('build/status-probe/webcall-server.json',root),JSON.stringify({pid:process.pid,url:origin}));
  console.log('Call Buildify at '+origin);
});
