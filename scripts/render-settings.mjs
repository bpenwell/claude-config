#!/usr/bin/env node
/**
 * Render settings.template.json into a machine-specific settings.json by
 * substituting {{HOOKS_DIR}} with this machine's absolute hooks path.
 *
 * Writes only when the result differs from what is already there, and backs up
 * the existing file first so re-running the installer doesn't pile up backups.
 *
 *   node scripts/render-settings.mjs --template <t> --hooks-dir <d> --out <o>
 *                                    [--backup-dir <d>] [--dry-run]
 *
 * Forward slashes are used even on Windows: they are valid in Windows paths and
 * avoid backslash-escaping problems inside JSON hook commands.
 */
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';

const args = { dryRun: false };
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--template') args.template = argv[++i];
  else if (argv[i] === '--hooks-dir') args.hooksDir = argv[++i];
  else if (argv[i] === '--out') args.out = argv[++i];
  else if (argv[i] === '--backup-dir') args.backupDir = argv[++i];
  else if (argv[i] === '--dry-run') args.dryRun = true;
  else {
    console.error(`unknown option: ${argv[i]}`);
    process.exit(1);
  }
}
for (const [flag, key] of [['--template', 'template'], ['--hooks-dir', 'hooksDir'], ['--out', 'out']]) {
  if (!args[key]) {
    console.error(`missing required ${flag}`);
    process.exit(1);
  }
}

const hooksDir = resolve(args.hooksDir).replace(/\\/g, '/');
const rendered = readFileSync(args.template, 'utf8').replaceAll('{{HOOKS_DIR}}', hooksDir);

JSON.parse(rendered); // fail loudly rather than write invalid settings

if (existsSync(args.out) && readFileSync(args.out, 'utf8') === rendered) {
  console.log('  settings.json already up to date');
  process.exit(0);
}

if (args.dryRun) {
  console.log(`  [dry-run] render settings.json (hooks: ${hooksDir})`);
  process.exit(0);
}

if (existsSync(args.out) && args.backupDir) {
  mkdirSync(args.backupDir, { recursive: true });
  copyFileSync(args.out, join(args.backupDir, basename(args.out)));
  console.log(`  backed up existing settings.json -> ${args.backupDir}`);
}

writeFileSync(args.out, rendered);
console.log(`  rendered settings.json (hooks: ${hooksDir})`);
