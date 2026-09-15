#!/usr/bin/env node
/**
 * Exit 0 if two files or directory trees have identical contents, 1 otherwise.
 * Lets the installers skip a backup-and-copy cycle when nothing changed, so a
 * re-run after an unchanged `git pull` doesn't pile up redundant backups.
 *
 *   node scripts/same-tree.mjs <a> <b>
 */
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

function hash(path, hasher = createHash('sha256')) {
  const st = statSync(path);
  if (st.isDirectory()) {
    for (const name of readdirSync(path).sort()) {
      hasher.update(name);
      hash(join(path, name), hasher);
    }
  } else {
    hasher.update(readFileSync(path));
  }
  return hasher;
}

const [a, b] = process.argv.slice(2);
if (!a || !b || !existsSync(a) || !existsSync(b)) process.exit(1);

try {
  process.exit(hash(a).digest('hex') === hash(b).digest('hex') ? 0 : 1);
} catch {
  process.exit(1); // unreadable -- treat as different and let the install proceed
}
