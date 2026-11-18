import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

test('Windows voice lifecycle isolates modes and cleans up failed starts', { skip: process.platform !== 'win32' }, () => {
  const output = execFileSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
    fileURLToPath(new URL('./voice-processes.test.ps1', import.meta.url))], { encoding: 'utf8', timeout: 15000 });
  assert.match(output, /10 lifecycle checks passed/);
});
