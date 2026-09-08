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
const DOLLAR_TAG_RE = /\$[A-Za-z_]*\$/y;
const COMMIT_IN_BODY_RE = /\bCOMMIT\b/;

/**
 * Split on top-level semicolons only. A `;` inside a $tag$ … $tag$ body is not
 * a statement boundary — without this, the `end;` closing an ordinary plpgsql
 * DO block became a top-level statement reading exactly END, which the COMMIT
 * check below treats as a synonym for COMMIT, and correctly rollback-wrapped
 * files were rejected with a message that said the opposite of the truth.
 *
 * Returns { statements, bodies } so the caller can hold the two to different
 * rules: structure is a property of the top-level statements, but a COMMIT is a
 * bug wherever it appears — since Postgres 11 a plpgsql block can genuinely
 * commit, so ignoring bodies would trade a false alarm for a silent hole.
 */
function partsOf(sql) {
  const src = sql.replace(SQL_COMMENT_RE, '');
  const statements = [];
  const bodies = [];
  let buf = '';
  let i = 0;
  while (i < src.length) {
    DOLLAR_TAG_RE.lastIndex = i;
    const tag = DOLLAR_TAG_RE.exec(src);
    if (tag) {
      const close = src.indexOf(tag[0], i + tag[0].length);
      const end = close === -1 ? src.length : close + tag[0].length;
      bodies.push(src.slice(i + tag[0].length, close === -1 ? src.length : close).toUpperCase());
      buf += src.slice(i, end);
      i = end;
      continue;
    }
    if (src[i] === ';') {
      statements.push(buf.trim().toUpperCase());
      buf = '';
      i += 1;
      continue;
    }
    buf += src[i];
    i += 1;
  }
  if (buf.trim()) statements.push(buf.trim().toUpperCase());
  return { statements: statements.filter(Boolean), bodies };
}

/** Pure, testable. `files` is [{ path, content }]. */
export function findNonRolledBackTests(files) {
  const found = [];
  for (const { path, content } of files) {
    const { statements: stmts, bodies } = partsOf(content);
    const first = stmts[0];
    if (first !== 'BEGIN' && first !== 'START TRANSACTION') {
      found.push({ path, reason: 'does not start with BEGIN' });
    }
    if (stmts.at(-1) !== 'ROLLBACK') {
      found.push({ path, reason: 'does not end with ROLLBACK' });
    }
    // `END` is a synonym for COMMIT only as a top-level statement; inside a
    // plpgsql body it closes the block and means nothing of the sort.
    const commits =
      stmts.some((s) => s === 'COMMIT' || s === 'END') || bodies.some((b) => COMMIT_IN_BODY_RE.test(b));
    if (commits) {
      found.push({ path, reason: 'contains COMMIT' });
    }
  }
  return found;
}

function main() {
  const tracked = execFileSync(
    'git',
    ['ls-files', '--', 'supabase/tests/*.sql', 'supabase/tests/**/*.sql', 'supabase/tests-holdout/*.sql'],
    {
      encoding: 'utf8',
    },
  )
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
