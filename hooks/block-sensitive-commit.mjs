#!/usr/bin/env node
/**
 * PreToolUse hook (Bash) — refuse git commands that would commit secrets.
 *
 * Exit 2 blocks the tool call and shows stderr to Claude. Exit 0 allows it.
 * Checks both the command text and what is already staged.
 */
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

const SENSITIVE_IN_COMMAND = /\.(env|pem|key)(\s|$)|credentials|\.secret/i;
const SENSITIVE_STAGED = /\.(env|pem|key)$|credentials|secrets/i;

let command = '';
try {
  command = JSON.parse(readFileSync(0, 'utf8'))?.tool_input?.command || '';
} catch {
  process.exit(0);
}

if (!/^\s*git\s+(commit|add)\b/.test(command)) process.exit(0);

if (SENSITIVE_IN_COMMAND.test(command)) {
  console.error('BLOCKED: Command targets sensitive files. Remove them first.');
  process.exit(2);
}

if (/git\s+commit/.test(command)) {
  const staged = spawnSync('git', ['diff', '--cached', '--name-only'], {
    encoding: 'utf8',
    timeout: 10_000,
  });
  const hits = (staged.stdout || '')
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => l && SENSITIVE_STAGED.test(l));
  if (hits.length) {
    console.error(`BLOCKED: Staged files include sensitive files: ${hits.join(', ')}`);
    process.exit(2);
  }
}

process.exit(0);
