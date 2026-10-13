const { test } = require('node:test');
const assert = require('node:assert/strict');
process.env.CF_API_TOKEN = 'test-only';
process.env.CF_ZONE_ID = 'test-only';
const { ingress } = require('./setup-tunnel');
test('wildcard follows specific rules, preserves settings, and is idempotent', () => {
  const original = { originRequest: { connectTimeout: 10 }, ingress: [
    { hostname: 'api.buildiify.tech', service: 'http://localhost:9000', originRequest: { httpHostHeader: 'api.local' } },
    { service: 'http_status:404' },
  ] };
  const output = ingress(original);
  assert.equal(output.ingress[0], original.ingress[0]);
  assert.equal(output.ingress[1].hostname, '*.buildiify.tech');
  assert.equal(output.ingress[1].service, 'http://localhost:8787');
  assert.equal(output.ingress[1].originRequest, undefined);
  assert.equal(output.ingress[2].service, 'http_status:404');
  assert.deepEqual(ingress(output), output);
  assert.equal(original.ingress.length, 2);
});
test('conflicting host override, wildcard target and catch-all are rejected', () => {
  assert.throws(() => ingress({ originRequest: { httpHostHeader: 'override' }, ingress: [{ service: 'http_status:404' }] }));
  assert.throws(() => ingress({ ingress: [{ hostname: '*.buildiify.tech', service: 'http://localhost:3000' }, { service: 'http_status:404' }] }));
  assert.throws(() => ingress({ ingress: [{ service: 'http://localhost:9000' }] }));
});
test('local YAML setup preserves tunnel/settings and reruns without mutations', async () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const YAML = require('yaml');
  const directory = fs.mkdtempSync(path.join(require('node:os').tmpdir(), 'buildiify-setup-test-'));
  const file = path.join(directory, 'config.yml');
  fs.writeFileSync(file, `tunnel: b3ff649c-04c3-48d4-9d7a-aa9cda8f8efd
credentials-file: /existing/credentials.json
ingress:
  - hostname: api.buildiify.tech
    service: http://localhost:9000
  - service: http_status:404
`);
  process.env.CF_TUNNEL_MANAGEMENT = 'local';
  process.env.CF_TUNNEL_CONFIG = file;
  let records = [], creates = 0;
  const fetchOriginal = global.fetch;
  global.fetch = async (_url, options) => {
    if (options.method === 'POST') {
      creates++;
      records = [{ id: 'record', ...JSON.parse(options.body) }];
    }
    return { ok: true, status: 200, json: async () => ({ success: true, result: records }) };
  };
  try {
    await require('./setup-tunnel').main();
    const first = fs.readFileSync(file, 'utf8');
    const parsed = YAML.parse(first);
    assert.equal(parsed['credentials-file'], '/existing/credentials.json');
    assert.equal(parsed.ingress[0].hostname, 'api.buildiify.tech');
    assert.equal(parsed.ingress[1].hostname, '*.buildiify.tech');
    assert.equal(parsed.ingress[2].service, 'http_status:404');
    assert.ok(fs.existsSync(`${file}.buildiify-backup`));
    await require('./setup-tunnel').main();
    assert.equal(fs.readFileSync(file, 'utf8'), first);
    assert.equal(creates, 1);
  } finally {
    global.fetch = fetchOriginal;
    delete process.env.CF_TUNNEL_MANAGEMENT;
    delete process.env.CF_TUNNEL_CONFIG;
    fs.rmSync(directory, { recursive: true });
  }
});
