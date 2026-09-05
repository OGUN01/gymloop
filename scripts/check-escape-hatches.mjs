#!/usr/bin/env node
/**
 * check-escape-hatches: AGENTS.md hard rule #4's second half says no
 * `eslint-disable` comments and no `knip` ignore entries, anywhere, without
 * sign-off recorded in docs/decisions.md. That was honour-system until a
 * fresh-context critic pointed out it was presented as constitutional while
 * being enforced by nothing. This is the enforcement.
 *
 * A rule that can be silently bypassed is not a rule — it is a preference.
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const SOURCE_EXT_RE = /\.(ts|tsx|js|jsx|mjs|cjs)$/;

// An actual directive: `eslint-disable` must immediately follow the comment
// opener. Prose that merely mentions the term mid-sentence (as the rule's
// own explanatory comments do) is not a suppression — matching on the bare
// word flags the documentation that explains the ban.
const ESLINT_DISABLE_RE = /(\/\/|\/\*)\s*eslint-disable(-next-line|-line)?\b/;

/** Pure, testable. `files` is [{ path, content }]. */
export function findEscapeHatches(files) {
  const found = [];
  for (const { path, content } of files) {
    if (path === 'scripts/check-escape-hatches.mjs') continue; // this file names them to detect them
    if (SOURCE_EXT_RE.test(path)) {
      for (const [index, line] of content.split('\n').entries()) {
        if (ESLINT_DISABLE_RE.test(line)) {
          found.push({ path, line: index + 1, kind: 'eslint-disable' });
        }
      }
    }
    if (path === 'knip.json') {
      // knip's suppression keys, as opposed to legitimate config like
      // `entry`, `project`, or `workspaces`.
      for (const [index, line] of content.split('\n').entries()) {
        if (/"(ignore|ignoreDependencies|ignoreBinaries|ignoreWorkspaces|ignoreExportsUsedInFile|ignoreMembers)"/.test(line)) {
          found.push({ path, line: index + 1, kind: 'knip ignore entry' });
        }
      }
    }
  }
  return found;
}

function main() {
  const tracked = execFileSync('git', ['ls-files'], { encoding: 'utf8' })
    .trim()
    .split('\n')
    .filter(Boolean)
    .filter((p) => SOURCE_EXT_RE.test(p) || p === 'knip.json');

  const files = tracked.map((path) => ({ path, content: readFileSync(path, 'utf8') }));
  const found = findEscapeHatches(files);

  if (found.length > 0) {
    console.error('check-escape-hatches: suppression directives found (AGENTS.md hard rule #4):\n');
    for (const { path, line, kind } of found) {
      console.error(`  ${path}:${line}  ${kind}`);
    }
    console.error('\nFix the code or re-scope the rule. If one is genuinely warranted,');
    console.error('record the sign-off as an ADR in docs/decisions.md and add it here explicitly.');
    process.exit(1);
  }
  console.log(`check-escape-hatches: ${files.length} file(s) checked, no suppression directives.`);
}

// See registry-lint.mjs for why this isn't `file://${process.argv[1]}`.
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
