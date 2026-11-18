import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { ListToolsRequestSchema, CallToolRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { createBuildifyClient } from './client.mjs';

const client = await createBuildifyClient();
const server = new Server({ name: 'buildify-owner-tools', version: '0.1.0' }, { capabilities: { tools: {} } });
server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: await client.listTools() }));
server.setRequestHandler(CallToolRequestSchema, async ({ params }) => {
  try {
    const result = await client.callTool(params.name, params.arguments ?? {});
    return { content: [{ type: 'text', text: JSON.stringify(result) }], structuredContent: result, isError: result.ok === false };
  } catch (_) {
    return { content: [{ type: 'text', text: 'Buildify is unavailable. Keep the paired app open and check the local session.' }], isError: true };
  }
});
await server.connect(new StdioServerTransport());
