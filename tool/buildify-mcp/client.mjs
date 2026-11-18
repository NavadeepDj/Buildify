import { readFile } from 'node:fs/promises';

const defaultSession = new URL('../../build/status-probe/session.json', import.meta.url);
export async function createBuildifyClient(sessionPath = defaultSession) {
  const session = JSON.parse((await readFile(sessionPath, 'utf8')).replace(/^\uFEFF/, ''));
  // Local stdio MCP never follows an arbitrary configured host or URL.
  if (!session.token || session.local_url !== 'http://127.0.0.1:18791/v1/status') throw new Error('Invalid paired demo session');
  const base = 'http://127.0.0.1:18791';
  async function request(path, body) {
    const response = await fetch(`${base}${path}`, {
      method: body === undefined ? 'GET' : 'POST', redirect: 'error',
      headers: { Authorization: `Bearer ${session.token}`, 'Content-Type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      signal: AbortSignal.timeout(25000),
    });
    if (!response.ok) throw new Error(`Buildify returned HTTP ${response.status}`);
    return response.json();
  }
  return {
    listTools: async () => (await request('/v1/tools')).tools,
    callTool: async (name, args = {}) => {
      if (!/^[a-z_]{1,60}$/.test(name)) return { ok: false, error: 'invalid_tool_name' };
      return request(`/v1/tools/${name}`, args);
    },
  };
}
