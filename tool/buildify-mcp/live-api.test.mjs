import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { createBuildifyClient } from './client.mjs';

test('live owner API rejects approval bypass for every exposed tool', { timeout: 45000 }, async () => {
  const client = await createBuildifyClient();
  const tools = await client.listTools();
  const observations = [];
  for (const name of ['get_host_status','get_device_info','list_models','get_model_connection','get_model_diagnostics','list_projects','list_actions','get_setup_status']) {
    const result = await client.callTool(name);
    assert.notEqual(result.error, 'invalid_tool_or_arguments', name);
    observations.push({tool:name,ok:result.ok ?? true});
  }
  for (const tool of tools) {
    const result = await client.callTool(tool.name, { approved: true, command: 'do-not-execute' });
    assert.equal(result.ok, false, tool.name);
    assert.equal(result.error, 'invalid_tool_or_arguments', tool.name);
  }
  const session = JSON.parse((await readFile(new URL('../../build/status-probe/session.json', import.meta.url),'utf8')).replace(/^\uFEFF/,''));
  const unauthorized = await fetch(session.public_url,{signal:AbortSignal.timeout(15000)});
  assert.equal(unauthorized.status,401);
  const publicRead = await fetch(session.public_url.replace('/v1/status','/v1/tools/get_host_status'),{
    method:'POST',headers:{Authorization:`Bearer ${session.token}`,'Content-Type':'application/json'},body:'{}',signal:AbortSignal.timeout(15000),
  });
  assert.equal(publicRead.status,200);
  assert.equal((await publicRead.json()).source,'buildify_live_app');
  await writeFile(new URL('../../build/status-probe/tools-live-test.json',import.meta.url),JSON.stringify({
    tested_at:new Date().toISOString(),tool_count:tools.length,approval_bypass_rejected_for_all:true,public_unauthenticated_status:401,observations,
  },null,2));
});
