import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

test('official MCP client discovers and calls real paired Buildify tools', { timeout: 45000 }, async () => {
  const client = new Client({ name: 'buildify-mcp-smoke', version: '0.1.0' }, { capabilities: {} });
  const transport = new StdioClientTransport({ command: process.execPath,
    args: [fileURLToPath(new URL('server.mjs', import.meta.url))], stderr: 'pipe' });
  try {
    await client.connect(transport);
    const { tools } = await client.listTools();
    assert.ok(tools.length >= 30);
    assert.ok(tools.some(tool => tool.name === 'request_model_setup'));
    assert.ok(tools.some(tool => tool.name === 'start_project'));
    assert.ok(!tools.some(tool => tool.name.includes('approve')));
    const status = await client.callTool({ name: 'get_host_status', arguments: {} });
    assert.equal(status.isError, false);
    assert.equal(status.structuredContent.source, 'buildify_live_app');
    const invalid = await client.callTool({ name: 'stop_model', arguments: { approved: true } });
    assert.equal(invalid.isError, true);
    const models = await client.callTool({ name: 'list_models', arguments: {} });
    assert.equal(models.isError, false);
    assert.ok(Array.isArray(models.structuredContent.models));
    console.log(`Verified ${tools.length} real Buildify tools through official MCP stdio client.`);
  } finally { await client.close(); }
});
