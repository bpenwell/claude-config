#!/usr/bin/env node
/**
 * Pull the live ~/.claude/settings.json back into settings/settings.template.json,
 * re-templating this machine's absolute hooks path as {{HOOKS_DIR}} so the result
 * stays portable. Run after changing preferences inside Claude Code, then commit.
 *
 *   node scripts/sync-settings.mjs [--dry-run]
 */
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const TEMPLATE = join(REPO, 'settings', 'settings.template.json');
const CLAUDE_DIR = process.env.CLAUDE_CONFIG_DIR || join(homedir(), '.claude');
const LIVE = join(CLAUDE_DIR, 'settings.json');
const dryRun = process.argv.includes('--dry-run');

if (!existsSync(LIVE)) {
  console.error(`no live settings at ${LIVE}`);
  process.exit(1);
}

const hooksDir = resolve(join(CLAUDE_DIR, 'hooks')).replace(/\\/g, '/');
const live = readFileSync(LIVE, 'utf8');
JSON.parse(live); // refuse to write a template from invalid JSON

// Match both the forward-slash form written by render-settings and any
// backslash form a hand-edit may have introduced.
const escaped = hooksDir.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const pattern = new RegExp(escaped.replace(/\//g, '[\\\\/]+'), 'g');
const templated = live.replace(pattern, '{{HOOKS_DIR}}');

if (templated.includes(hooksDir)) {
  console.error('warning: some absolute hook paths could not be templated');
}

const current = existsSync(TEMPLATE) ? readFileSync(TEMPLATE, 'utf8') : '';
if (current === templated) {
  console.log('settings template already up to date');
  process.exit(0);
}

if (dryRun) {
  console.log(`[dry-run] would update ${TEMPLATE}`);
  process.exit(0);
}

writeFileSync(TEMPLATE, templated);
console.log(`updated ${TEMPLATE} — review with 'git diff' and commit`);
