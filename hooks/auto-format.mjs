#!/usr/bin/env node
/**
 * PostToolUse hook (Write|Edit|NotebookEdit) — format the file Claude just wrote.
 *
 * Walks up from the file for a prettier config and runs prettier only if one is
 * found, so repos that don't use prettier are left alone. Always exits 0: a
 * formatting failure must never block Claude.
 */
import { existsSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { dirname, join, parse } from 'node:path';

const FORMATTABLE = /\.(ts|tsx|js|jsx|mjs|cjs|json|css|scss|html|md)$/i;
const CONFIGS = [
  '.prettierrc', '.prettierrc.js', '.prettierrc.cjs', '.prettierrc.json',
  '.prettierrc.yaml', '.prettierrc.yml', 'prettier.config.js', 'prettier.config.cjs',
  'prettier.config.mjs',
];

function readStdin() {
  try {
    return readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function filePath() {
  // Claude Code passes the hook payload on stdin; fall back to the env var.
  const raw = readStdin();
  if (raw.trim()) {
    try {
      const data = JSON.parse(raw);
      const p = data?.tool_input?.file_path || data?.tool_input?.notebook_path;
      if (p) return p;
    } catch {
      // Not JSON — fall through to the env var.
    }
  }
  return process.env.CLAUDE_FILE_PATH || '';
}

function findConfigRoot(start) {
  let dir = start;
  const { root } = parse(dir);
  while (true) {
    if (CONFIGS.some((c) => existsSync(join(dir, c)))) return dir;
    // package.json with a "prettier" key counts as a config too.
    const pkg = join(dir, 'package.json');
    if (existsSync(pkg)) {
      try {
        if (JSON.parse(readFileSync(pkg, 'utf8')).prettier) return dir;
      } catch {
        // Unreadable package.json — keep walking.
      }
    }
    if (dir === root) return null;
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

const file = filePath();
if (!file || !existsSync(file) || !FORMATTABLE.test(file)) process.exit(0);

const root = findConfigRoot(dirname(file));
if (!root) process.exit(0);

/** Nearest node_modules/.bin/prettier at or above `start`, or null. */
function findLocalPrettier(start) {
  const bin = process.platform === 'win32' ? 'prettier.cmd' : 'prettier';
  let dir = start;
  const { root: fsRoot } = parse(dir);
  while (true) {
    const candidate = join(dir, 'node_modules', '.bin', bin);
    if (existsSync(candidate)) return candidate;
    if (dir === fsRoot) return null;
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

const local = findLocalPrettier(root);
// Prefer the project's own prettier. Fall back to npx, which is slower and
// no-ops noisily when prettier isn't installed -- hence stdio: 'ignore'.
const [cmd, args] = local
  ? [local, ['--write', file]]
  : ['npx', ['--no', 'prettier', '--write', file]];

spawnSync(cmd, args, {
  cwd: root,
  shell: process.platform === 'win32',
  stdio: 'ignore',
  timeout: 30_000,
});

process.exit(0);
