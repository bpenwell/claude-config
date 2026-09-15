#!/usr/bin/env node
/**
 * Render mcp/servers.template.json from an env file and merge the result into
 * ~/.claude.json under mcpServers. Every other key in that file is preserved,
 * and a timestamped .bak-* copy is written first.
 *
 *   node mcp/merge-mcp.mjs [--env-file <path>] [--target <path>] [--dry-run]
 *
 * A server whose credentials are still blank is skipped rather than written as
 * a broken entry. A ${VAR} with no matching env key is a hard error.
 */
import { copyFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const VAR = /\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g;

function parseArgs(argv) {
  const args = { dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--env-file') args.envFile = argv[++i];
    else if (argv[i] === '--target') args.target = argv[++i];
    else if (argv[i] === '--template') args.template = argv[++i];
    else if (argv[i] === '--dry-run') args.dryRun = true;
    else {
      console.error(`unknown option: ${argv[i]}`);
      process.exit(1);
    }
  }
  args.envFile ||= process.env.CLAUDE_CONFIG_ENV || join(homedir(), '.claude-config.env');
  args.target ||= process.env.CLAUDE_JSON || join(homedir(), '.claude.json');
  args.template ||= join(HERE, 'servers.template.json');
  return args;
}

/** Parse KEY=value, honouring quotes, comments, ~ and $HOME/${VAR} expansion. */
function readEnvFile(path) {
  const env = {};
  for (const raw of readFileSync(path, 'utf8').split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#') || !line.includes('=')) continue;
    const idx = line.indexOf('=');
    const key = line.slice(0, idx).trim();
    let value = line.slice(idx + 1).trim().replace(/^["']|["']$/g, '');
    // Forward slashes throughout: valid on Windows and avoids mixed separators.
    const home = homedir().replace(/\\/g, '/');
    value = value
      .replace(/\$\{?HOME\}?|%USERPROFILE%/gi, home)
      .replace(/^~(?=[/\\]|$)/, home);
    env[key] = value;
  }
  return env;
}

function substitute(node, env, missing) {
  if (Array.isArray(node)) return node.map((v) => substitute(v, env, missing));
  if (node && typeof node === 'object') {
    return Object.fromEntries(Object.entries(node).map(([k, v]) => [k, substitute(v, env, missing)]));
  }
  if (typeof node !== 'string') return node;
  return node.replace(VAR, (match, name) => {
    if (!(name in env)) {
      missing.add(name);
      return match;
    }
    return env[name];
  });
}

/** True if any leaf is empty — i.e. a credential was left blank in the env file. */
function hasBlank(node) {
  if (Array.isArray(node)) return node.some(hasBlank);
  if (node && typeof node === 'object') return Object.values(node).some(hasBlank);
  return typeof node === 'string' && (node.trim() === '' || node.trim() === 'Bearer');
}

const args = parseArgs(process.argv.slice(2));

if (!existsSync(args.envFile)) {
  console.error(`env file not found: ${args.envFile}`);
  process.exit(1);
}

const env = readEnvFile(args.envFile);
const template = JSON.parse(readFileSync(args.template, 'utf8'));
const missing = new Set();
const rendered = substitute(template, env, missing);

if (missing.size) {
  console.error(`env file is missing these variables: ${[...missing].sort().join(', ')}`);
  process.exit(1);
}

const kept = Object.fromEntries(Object.entries(rendered).filter(([, cfg]) => !hasBlank(cfg)));
const skipped = Object.keys(rendered).filter((n) => !(n in kept));

if (args.dryRun) {
  console.log(`  [dry-run] would merge into ${args.target}: ${Object.keys(kept).join(', ') || 'none'}`);
  if (skipped.length) console.log(`  [dry-run] would skip (blank credentials): ${skipped.join(', ')}`);
  process.exit(0);
}

let config = {};
const target = resolve(args.target);
if (existsSync(target)) {
  const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 15);
  copyFileSync(target, `${target}.bak-${stamp}`);
  config = JSON.parse(readFileSync(target, 'utf8'));
}

config.mcpServers = { ...(config.mcpServers || {}), ...kept };
writeFileSync(target, `${JSON.stringify(config, null, 2)}\n`);

console.log(`  merged ${Object.keys(kept).length} mcp server(s): ${Object.keys(kept).join(', ') || 'none'}`);
if (skipped.length) console.log(`  skipped (blank credentials): ${skipped.join(', ')}`);
