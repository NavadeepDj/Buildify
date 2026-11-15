import test from 'node:test';
import assert from 'node:assert/strict';
import { buildifyMultilingualConfig, buildifyLanguages } from './bolna-languages.mjs';

const policy = 'Call confirm_model_setup only with explicit approval. Never reveal credentials. Only state sent confirms email delivery.';
const english = {
  transcriber: { provider: 'deepgram', model: 'nova-3', language: 'en' },
  synthesizer: { provider: 'elevenlabs', provider_config: { voice_id: 'existing-english-voice', model: 'eleven_turbo_v2_5' } },
};

test('all configured speech languages retain the complete current tool and approval policy', () => {
  const config = buildifyMultilingualConfig(policy, english);
  assert.deepEqual(new Set(Object.keys(config.languages)), new Set(buildifyLanguages));
  for (const language of buildifyLanguages) {
    assert.ok(config.languages[language].system_prompt.startsWith(policy));
    assert.equal(config.languages[language].agent_name, 'Buildify');
  }
  assert.match(config.languages.hi.handoff_message, /हिंदी/);
  assert.match(config.languages.te.handoff_message, /తెలుగు/);
});

test('English keeps its configured providers without mutating or sharing nested caller configuration', () => {
  const original = structuredClone(english);
  const config = buildifyMultilingualConfig(policy, english);
  assert.deepEqual(config.languages.en.transcriber, english.transcriber);
  assert.deepEqual(config.languages.en.synthesizer, english.synthesizer);
  config.languages.en.synthesizer.provider_config.voice_id = 'changed';
  assert.deepEqual(english, original);
});
