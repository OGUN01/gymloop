#!/usr/bin/env node
/**
 * check-pgtap-rollback: every pgTAP test file must be wrapped
 * BEGIN … ROLLBACK (docs/decisions.md ADR-030). The suite runs against the
 * one shared Supabase Cloud project — there is no disposable database — so a
 * test that commits is a bug, not a style issue. This is the enforcement.
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const SQL_COMMENT_RE = /--[^\n]*|\/\*[\s\S]*?\*\//g;

function statementsOf(sql) {
  return sql
    .replace(SQL_COMMENT_RE, '')
    .split(';')
    .map((s) => s.trim().toUpperCase())
    .filter(Boolean);
}

/** Pure, testable. `files` is [{ path, content }]. */
export function findNonRolledBackTests(files) {
  const found = [];
  for (const { path, content } of files) {
    const stmts = statementsOf(content);
    const first = stmts[0];
    if (first !== 'BEGIN' && first !== 'START TRANSACTION') {
      found.push({ path, reason: 'does not start with BEGIN' });
    }
    if (stmts.at(-1) !== 'ROLLBACK') {
      found.push({ path, reason: 'does not end with ROLLBACK' });
    }
    if (stmts.some((s) => s === 'COMMIT' || s === 'END')) {
      found.push({ path, reason: 'contains COMMIT' });
    }
  }
  return found;
}

function main() {
  const tracked = execFileSync('git', ['ls-files', '--', 'supabase/tests/*.sql', 'supabase/tests/**/*.sql'], {
    encoding: 'utf8',
  })
    .trim()
    .split('\n')
    .filter(Boolean);
  const found = findNonRolledBackTests(tracked.map((path) => ({ path, content: readFileSync(path, 'utf8') })));

  if (found.length > 0) {
    console.error('check-pgtap-rollback: pgTAP files that would commit against the shared Cloud database (ADR-030):\n');
    for (const { path, reason } of found) {
      console.error(`  ${path}  ${reason}`);
    }
    process.exit(1);
  }
  console.log(`check-pgtap-rollback: ${tracked.length} pgTAP file(s) checked, all rollback-wrapped.`);
}

// See registry-lint.mjs for why this isn't `file://${process.argv[1]}`.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
