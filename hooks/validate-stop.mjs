#!/usr/bin/env node
/**
 * Stop hook — validate recent changes against the requirement before letting
 * Claude finish. Blocks the stop with fix instructions when validation fails.
 *
 * Not registered by default. To enable, add to settings.json under hooks.Stop:
 *   { "type": "command", "command": "node <hooks-dir>/validate-stop.mjs" }
 *
 * The validator it shells out to is resolved in this order:
 *   1. $CLAUDE_VALIDATE_SCRIPT
 *   2. <cwd>/.claude/validate(.sh|.ps1|.cmd)
 *   3. ~/.claude/validate(.sh|.ps1|.cmd)
 * If none exists, validation is skipped and the stop is allowed.
 *
 * Fails open everywhere: any error allows the stop rather than trapping Claude.
 */
import { existsSync, readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { homedir } from 'node:os';
import { join } from 'node:path';

const ACTION_WORDS = [
  'fix', 'add', 'change', 'implement', 'make', 'update', 'create', 'remove',
  'refactor', 'move', 'rename', 'style', 'align', 'adjust', 'replace',
  'convert', 'migrate', 'build', 'write', 'edit', 'delete', 'improve',
  'optimize', 'integrate', 'connect', 'set up',
];
const SKIP_PREFIXES = ['[skip-validate]', '[no-validate]', '[skip_validate]'];
const EXTS = process.platform === 'win32' ? ['.ps1', '.cmd', '.sh', ''] : ['.sh', ''];

const allowStop = () => process.exit(0);

function readTranscript(path) {
  if (!path || !existsSync(path)) return [];
  const out = [];
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      out.push(JSON.parse(trimmed));
    } catch {
      // Partial or malformed line — skip it.
    }
  }
  return out;
}

function extractRequirement(entries) {
  for (let i = entries.length - 1; i >= 0; i--) {
    const entry = entries[i];
    const msg = entry?.role ? entry : entry?.message;
    if (!msg || typeof msg !== 'object' || msg.role !== 'user') continue;

    let content = msg.content ?? '';
    if (Array.isArray(content)) {
      content = content
        .filter((c) => c && typeof c === 'object' && c.type === 'text')
        .map((c) => c.text || '')
        .join(' ');
    }
    if (typeof content !== 'string' || !content.trim()) continue;

    const text = content.trim();
    const lower = text.toLowerCase();
    if (SKIP_PREFIXES.some((p) => lower.startsWith(p))) return null;
    if (ACTION_WORDS.some((w) => lower.includes(w))) return text;
  }
  return null;
}

function findWorkdir(entries) {
  for (const entry of entries) {
    if (entry?.type === 'session' && entry?.cwd) return entry.cwd;
  }
  return process.cwd();
}

function hasGitDiff(cwd) {
  for (const args of [['diff', 'HEAD'], ['diff', '--cached']]) {
    const r = spawnSync('git', args, { cwd, encoding: 'utf8', timeout: 10_000 });
    if ((r.stdout || '').trim()) return true;
  }
  return false;
}

function findValidator(workdir) {
  if (process.env.CLAUDE_VALIDATE_SCRIPT) {
    const p = process.env.CLAUDE_VALIDATE_SCRIPT;
    return existsSync(p) ? p : null;
  }
  for (const base of [join(workdir, '.claude', 'validate'), join(homedir(), '.claude', 'validate')]) {
    for (const ext of EXTS) {
      if (ext && existsSync(base + ext)) return base + ext;
      if (!ext && existsSync(base)) return base;
    }
  }
  return null;
}

function runValidation(script, requirement, workdir) {
  const isPs1 = script.toLowerCase().endsWith('.ps1');
  const cmd = isPs1 ? 'powershell' : script;
  const args = isPs1
    ? ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, requirement, workdir]
    : [requirement, workdir];

  const r = spawnSync(cmd, args, {
    cwd: workdir,
    encoding: 'utf8',
    timeout: 90_000,
    shell: process.platform === 'win32' && !isPs1,
  });

  if (r.error || r.signal) return { passed: true, summary: 'Validation could not run — skipping', issues: [] };

  const raw = (r.stdout || '').trim();
  try {
    const report = JSON.parse(raw);
    return {
      passed: Boolean(report.pass),
      summary: report.summary || 'Validation failed',
      issues: Array.isArray(report.issues) ? report.issues : [],
    };
  } catch {
    return {
      passed: r.status === 0,
      summary: raw ? raw.slice(0, 200) : 'Validation failed (no output)',
      issues: [],
    };
  }
}

let payload;
try {
  payload = JSON.parse(readFileSync(0, 'utf8'));
} catch {
  allowStop();
}

const entries = readTranscript(payload.transcript_path || '');
const workdir = findWorkdir(entries);
const requirement = extractRequirement(entries);
if (!requirement) allowStop();
if (!hasGitDiff(workdir)) allowStop();

const script = findValidator(workdir);
if (!script) allowStop();

const { passed, summary, issues } = runValidation(script, requirement, workdir);
if (passed) allowStop();

const issuesText = issues.length ? issues.map((i) => `- ${i}`).join('\n') : `- ${summary}`;
console.log(JSON.stringify({
  decision: 'block',
  reason: `Validation failed: ${summary}`,
  systemMessage:
    'Your implementation does not fully address the requirement.\n\n' +
    `Original requirement: ${requirement}\n\n` +
    `Issues found:\n${issuesText}\n\n` +
    'Please fix these specific issues and try again.',
}));
