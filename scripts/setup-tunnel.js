// Node 22+. No secrets are written to disk or sent to the app.
const fs = require('node:fs');
const env = process.env;
const domain = env.BASE_DOMAIN || 'buildiify.tech';
const tunnel = env.CF_TUNNEL_ID || 'b3ff649c-04c3-48d4-9d7a-aa9cda8f8efd';
const port = Number(env.ROUTER_PORT || 8787);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw Error('Invalid ROUTER_PORT');
for (const key of ['CF_API_TOKEN', 'CF_ZONE_ID']) if (!env[key]) throw Error(`${key} is required`);
async function api(path, method = 'GET', body) {
  const response = await fetch(`https://api.cloudflare.com/client/v4${path}`, {
    method, headers: { Authorization: `Bearer ${env.CF_API_TOKEN}`, 'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(30000),
  });
  const result = await response.json();
  if (!response.ok || !result.success) throw Error(`Cloudflare ${method} failed (${response.status}): ${JSON.stringify(result.errors)}`);
  return result.result;
}
function ingress(config) {
  const rules = [...(config.ingress || [])];
  const wildcard = `*.${domain}`;
  const existing = rules.find(r => r.hostname === wildcard);
  const service = `http://localhost:${port}`;
  if (existing && (existing.service !== service || existing.path || existing.originRequest?.httpHostHeader)) {
    throw Error('Existing wildcard rule conflicts with router configuration; review it before retrying');
  }
  if (config.originRequest?.httpHostHeader) throw Error('Global httpHostHeader overrides Host; remove it or scope it to specific rules');
  const remaining = rules.filter(r => r.hostname !== wildcard);
  const catchAll = remaining.findIndex(r => !r.hostname && !r.path);
  if (catchAll !== remaining.length - 1 || catchAll < 0 || remaining[catchAll].service !== 'http_status:404') {
    throw Error('Expected a final http_status:404 catch-all; existing rules were preserved');
  }
  remaining.splice(catchAll, 0, existing || { hostname: wildcard, service });
  return { ...config, ingress: remaining };
}
async function main() {
  const mode = env.CF_TUNNEL_MANAGEMENT || 'remote';
  let save;
  if (mode === 'local') {
    const file = env.CF_TUNNEL_CONFIG;
    if (!file) throw Error('CF_TUNNEL_CONFIG must point to an existing config.yml');
    let YAML;
    try { YAML = require('yaml'); } catch { throw Error('Local mode requires: npm install --prefix scripts --ignore-scripts'); }
    const original = fs.readFileSync(file, 'utf8');
    const document = YAML.parseDocument(original, { uniqueKeys: true });
    if (document.errors.length) throw Error(`Invalid local YAML: ${document.errors[0].message}`);
    const config = document.toJS();
    if (config.tunnel !== tunnel) throw Error('Local config tunnel ID does not match CF_TUNNEL_ID');
    const next = ingress(config);
    document.set('ingress', next.ingress);
    const updated = document.toString();
    save = async () => {
      if (JSON.stringify(config) === JSON.stringify(next)) return;
      if (!fs.existsSync(`${file}.buildiify-backup`)) fs.writeFileSync(`${file}.buildiify-backup`, original, { flag: 'wx' });
      fs.writeFileSync(`${file}.buildiify-tmp`, updated);
      fs.renameSync(`${file}.buildiify-tmp`, file);
    };
  } else if (mode === 'remote') {
    if (!env.CF_ACCOUNT_ID) throw Error('CF_ACCOUNT_ID is required');
    const path = `/accounts/${env.CF_ACCOUNT_ID}/cfd_tunnel/${tunnel}`;
    const details = await api(path);
    if (details.config_src !== 'cloudflare') throw Error('Tunnel is locally managed; set CF_TUNNEL_MANAGEMENT=local');
    const current = await api(`${path}/configurations`);
    const config = ingress(current.config);
    save = async () => {
      if (JSON.stringify(config) !== JSON.stringify(current.config)) await api(`${path}/configurations`, 'PUT', { config });
    };
  } else throw Error('CF_TUNNEL_MANAGEMENT must be remote or local');
  const path = `/zones/${env.CF_ZONE_ID}/dns_records`;
  const records = await api(`${path}?name=${encodeURIComponent(`*.${domain}`)}`);
  const desired = { type: 'CNAME', name: `*.${domain}`, content: `${tunnel}.cfargotunnel.com`, proxied: true, ttl: 1 };
  if (records.length > 1 || records.some(r => r.type !== 'CNAME' || r.content !== desired.content)) {
    throw Error('Wildcard DNS conflicts with existing records; no records were overwritten');
  }
  await save();
  if (!records.length) await api(path, 'POST', desired);
  else if (!records[0].proxied) await api(`${path}/${records[0].id}`, 'PATCH', { proxied: true });
  console.log(`Wildcard routing ready: *.${domain} -> ${tunnel} -> ${desired.name} router on ${port}`);
}
if (require.main === module) main().catch(e => { console.error(e.message); process.exitCode = 1; });
module.exports = { ingress, main };
