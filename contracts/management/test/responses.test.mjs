import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';

const spec = JSON.parse(readFileSync(new URL('../openapi.json', import.meta.url)));
const definitions = JSON.parse(
  JSON.stringify(spec.components.schemas).replaceAll('#/components/schemas/', '#/$defs/'),
);
const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats(ajv);
const validate = (name, value) => ajv.compile({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $defs: definitions,
  $ref: `#/$defs/${name}`,
})(value);

// The Dart consumer test reads this same fixture; schema drift must fail here.
const canonicalAccount = JSON.parse(readFileSync(new URL('../examples/account.json', import.meta.url)));
const requestId = canonicalAccount.request_id;
const account = () => structuredClone(canonicalAccount);

test('account response accepts a synthetic confirmed-account representation', () => {
  assert.equal(validate('AccountResponse', account()), true);
});

test('wire-shape drift is rejected instead of accepting renamed or missing fields', () => {
  const renamed = account();
  renamed.data.displayName = renamed.data.display_name;
  delete renamed.data.display_name;
  assert.equal(validate('AccountResponse', renamed), false);
  const missingId = account();
  delete missingId.data.id;
  assert.equal(validate('AccountResponse', missingId), false);
});

test('account schema rejects malformed identities and blank/oversized display names', () => {
  for (const data of [
    { id: 'not-a-uuid', display_name: 'Example' },
    { id: account().data.id, display_name: '   ' },
    { id: account().data.id, display_name: 'x'.repeat(81) },
  ]) assert.equal(validate('AccountResponse', { data, request_id: requestId }), false);
  assert.equal(validate('AccountResponse', {
    data: { id: account().data.id, display_name: 'సుజిత్ & Harita' }, request_id: requestId,
  }), true);
});

test('credentials and invented privileged fields are not part of account responses', () => {
  for (const field of ['access_token', 'refresh_token', 'service_role_key', 'is_admin', 'is_pro']) {
    const response = account();
    response.data[field] = 'synthetic-unexpected-field';
    assert.equal(validate('AccountResponse', response), false);
  }
});

test('health reports service liveness, not model or device readiness', () => {
  assert.equal(validate('HealthResponse', {
    data: { status: 'ok', api_version: 'v1' }, request_id: requestId,
  }), true);
  assert.equal(validate('HealthResponse', {
    data: { status: 'ok', api_version: 'v1', model_running: true }, request_id: requestId,
  }), false);
});

test('errors require a known code and correlation ID and reject debug payloads', () => {
  const response = {
    error: { code: 'invalid_token', message: 'Sign in again.' }, request_id: requestId,
  };
  assert.equal(validate('ErrorResponse', response), true);
  assert.equal(validate('ErrorResponse', { ...response, stack: 'synthetic stack' }), false);
  assert.equal(validate('ErrorResponse', { ...response, request_id: 'client supplied text' }), false);
  assert.equal(validate('ErrorResponse', {
    ...response, error: { code: 'unknown_failure', message: 'Retry.' },
  }), false);
});

test('account route requires a user session and defines no caller-supplied owner selector', () => {
  const operation = spec.paths['/v1/account'].get;
  assert.deepEqual(operation.security, [{ UserSession: [] }]);
  assert.equal(operation.requestBody, undefined);
  assert.equal(operation.parameters, undefined);
  assert.deepEqual(spec.paths['/v1/health'].get.security, []);
});
