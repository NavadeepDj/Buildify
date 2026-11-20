import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';

const spec = JSON.parse(readFileSync(new URL('../devices/openapi.json', import.meta.url)));
const definitions = JSON.parse(JSON.stringify(spec.components.schemas).replaceAll('#/components/schemas/', '#/$defs/'));
const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);
const validators = new Map();
function accepts(name, value) {
  if (!validators.has(name)) validators.set(name, ajv.compile({ $schema: 'https://json-schema.org/draft/2020-12/schema', $defs: definitions, $ref: `#/$defs/${name}` }));
  return validators.get(name)(value);
}
const id = '11111111-1111-4111-8111-111111111111';
const requestId = '22222222-2222-4222-8222-222222222222';
const enrollment = () => ({ enrollment_id: id, display_name: 'My phone', platform: 'android', protocol_version: 'v1', capabilities: ['host.ai'], credential_secret: 'A'.repeat(43) });
const device = () => ({ id, enrollment_id: id, display_name: 'My phone', platform: 'android', protocol_version: 'v1', capabilities: ['host.ai'], status: 'active', revision: 1, credential_version: 1, created_at: '2026-11-07T00:00:00Z', updated_at: '2026-11-07T00:00:00Z', revoked_at: null });

test('draft supports Android and desktop without claiming hosting support', () => {
  for (const platform of ['android', 'windows', 'macos', 'linux']) assert.equal(accepts('DeviceEnrollment', { ...enrollment(), platform }), true);
  for (const platform of ['web', 'ios', 'unknown']) assert.equal(accepts('DeviceEnrollment', { ...enrollment(), platform }), false);
  assert.equal(spec.info.version, '0.1.0-draft.1');
  for (const path of Object.values(spec.paths)) for (const operation of Object.values(path)) assert.equal(operation['x-release-status'], 'proposed-not-deployed');
});
test('enrollment rejects caller ownership, privileges, hardware identifiers and runtime secrets', () => {
  for (const field of ['owner_id', 'id', 'status', 'credential_version', 'is_admin', 'subscription', 'hardware_id', 'cloudflare_token', 'project_path']) {
    assert.equal(accepts('DeviceEnrollment', { ...enrollment(), [field]: 'forbidden' }), false, field);
  }
  assert.equal(accepts('DeviceEnrollment', { ...enrollment(), enrollment_id: 'not-a-uuid' }), false);
});
test('random-secret encoding is exact while entropy remains a runtime requirement', () => {
  for (const credential_secret of ['', 'A'.repeat(42), 'A'.repeat(44), 'A'.repeat(42) + '=', 'A'.repeat(42) + 'B', 'not a random secret']) {
    assert.equal(accepts('DeviceEnrollment', { ...enrollment(), credential_secret }), false);
  }
  const missing = enrollment(); delete missing.credential_secret;
  assert.equal(accepts('DeviceEnrollment', missing), false);
});
test('names, capabilities and protocol remain bounded and explicitly supported', () => {
  assert.equal(accepts('DeviceEnrollment', { ...enrollment(), display_name: 'నా ఫోన్' }), true);
  for (const value of [{ display_name: '   ' }, { display_name: 'x'.repeat(81) }, { capabilities: ['arbitrary.shell'] }, { capabilities: ['host.ai', 'host.ai'] }, { protocol_version: 'v2' }]) {
    assert.equal(accepts('DeviceEnrollment', { ...enrollment(), ...value }), false);
  }
});
test('owner metadata and agent identity responses cannot leak credentials or grant owner access', () => {
  assert.equal(accepts('DeviceResponse', { data: device(), request_id: requestId }), true);
  for (const field of ['credential_secret', 'credential_hash', 'access_token', 'refresh_token', 'owner_email', 'service_role_key']) {
    assert.equal(accepts('DeviceResponse', { data: { ...device(), [field]: 'unexpected' }, request_id: requestId }), false, field);
  }
  const agent = { id, credential_version: 1, protocol_version: 'v1' };
  assert.equal(accepts('AgentDeviceResponse', { data: agent, request_id: requestId }), true);
  assert.equal(accepts('AgentDeviceResponse', { data: { ...agent, owner_id: id }, request_id: requestId }), false);
});
test('active and revoked records have consistent timestamps and positive revisions', () => {
  assert.equal(accepts('Device', { ...device(), status: 'revoked', revoked_at: '2026-11-07T01:00:00Z' }), true);
  for (const patch of [{ status: 'revoked' }, { revoked_at: '2026-11-07T01:00:00Z' }, { revision: 0 }, { credential_version: 0 }, { status: 'online' }]) {
    assert.equal(accepts('Device', { ...device(), ...patch }), false);
  }
});
test('list pagination is bounded and mutation schemas reject ownership changes', () => {
  assert.equal(accepts('DeviceListResponse', { data: { devices: [device()], next_cursor: null }, request_id: requestId }), true);
  assert.equal(accepts('DeviceListResponse', { data: { devices: Array.from({ length: 51 }, device), next_cursor: null }, request_id: requestId }), false);
  assert.equal(accepts('DeviceRename', { display_name: 'Laptop' }), true);
  assert.equal(accepts('DeviceRename', { display_name: 'Laptop', owner_id: id }), false);
  assert.equal(accepts('DeviceRotation', { rotation_id: id, credential_secret: 'A'.repeat(43) }), true);
  assert.equal(accepts('DeviceRotation', { credential_secret: 'A'.repeat(43) }), false);
});
test('owner and device authority are never alternative authentication schemes', () => {
  for (const [path, operations] of Object.entries(spec.paths)) for (const op of Object.values(operations)) {
    assert.deepEqual(op.security, [{ [path === '/v1/agent/device' ? 'DeviceCredential' : 'UserSession']: [] }]);
  }
  for (const [path, method] of [['/v1/devices/{device_id}', 'patch'], ['/v1/devices/{device_id}/credentials/rotate', 'post']]) {
    assert.equal(spec.paths[path][method].parameters.find(p => p.name === 'If-Match')?.required, true);
  }
  assert.equal(spec.paths['/v1/devices/{device_id}/revoke'].post.requestBody, undefined);
  assert.equal(spec.paths['/v1/agent/device'].get.parameters, undefined);
});
