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

// The other way to silence a gate in a `strict` TypeScript repo. Rule #4's
// literal text names only eslint-disable and knip ignores, but suppressing
// the typechecker is the same act — and `strict` plus generated DB types is
// exactly the setting where someone reaches for it.
const TS_SUPPRESS_RE = /(\/\/|\/\*)\s*@ts-(ignore|expect-error|nocheck)\b/;

// Inline config comment: `/* eslint no-magic-numbers: "off" */` (also `: 0`,
// unquoted `: off`, several rules comma-separated) switches a rule off for
// the whole file without ever saying "disable". ESLint only honours block
// comments for this, and the rule name must be followed by a colon — which
// is what keeps `eslint-env`, `eslint-disable` and prose out.
const ESLINT_INLINE_CONFIG_RE = /\/\*\s*eslint\s+[\w@/-]+\s*:/;

// A nested flat config or legacy .eslintrc anywhere below the root replaces
// the root constitutional config for that subtree. Only the root file is
// legitimate.
const ESLINT_CONFIG_PATH_RE = /(^|\/)(eslint\.config\.[cm]?[jt]s|\.eslintrc(\.[a-z]+)?)$/;
const ROOT_ESLINT_CONFIG = 'eslint.config.mjs';

// Every filename knip reads config from, plus package.json's "knip" key.
const KNIP_CONFIG_FILES = new Set([
  'knip.json',
  'knip.jsonc',
  '.knip.json',
  '.knip.jsonc',
  'knip.ts',
  'knip.js',
  'knip.mjs',
  'knip.config.ts',
  'knip.config.js',
  'knip.config.mjs',
  'knip.config.cjs',
  'knip.config.json',
  'knip.config.jsonc',
  'package.json',
]);
// knip's suppression keys, as opposed to legitimate config like `entry`,
// `project`, or `workspaces`. Quoted (JSON) or bare (TS/JS object) keys.
const KNIP_IGNORE_KEY_RE =
  /["']?\b(ignore|ignoreDependencies|ignoreBinaries|ignoreWorkspaces|ignoreExportsUsedInFile|ignoreMembers)\b["']?\s*:/;

function isCheckedPath(path) {
  return SOURCE_EXT_RE.test(path) || KNIP_CONFIG_FILES.has(path) || ESLINT_CONFIG_PATH_RE.test(path);
}

const SELF_REFERENTIAL_FILES = new Set([
  'scripts/check-escape-hatches.mjs',
  'scripts/__tests__/check-escape-hatches.test.ts',
]);

/** Pure, testable. `files` is [{ path, content }]. */
export function findEscapeHatches(files) {
  const found = [];
  for (const { path, content } of files) {
    // This checker and its tests necessarily contain the very strings they
    // detect — the detector names them, and the tests use them as fixtures.
    // Excluded by exact path, NOT by a blanket "skip all tests" rule: a real
    // suppression hidden in a product test must still be caught.
    if (SELF_REFERENTIAL_FILES.has(path)) continue;
    if (ESLINT_CONFIG_PATH_RE.test(path) && path !== ROOT_ESLINT_CONFIG) {
      found.push({ path, line: 1, kind: 'nested eslint config' });
    }
    if (SOURCE_EXT_RE.test(path)) {
      for (const [index, line] of content.split('\n').entries()) {
        if (ESLINT_DISABLE_RE.test(line)) {
          found.push({ path, line: index + 1, kind: 'eslint-disable' });
        }
        if (TS_SUPPRESS_RE.test(line)) {
          found.push({ path, line: index + 1, kind: 'TypeScript suppression' });
        }
        if (ESLINT_INLINE_CONFIG_RE.test(line)) {
          found.push({ path, line: index + 1, kind: 'eslint inline config' });
        }
      }
    }
    if (KNIP_CONFIG_FILES.has(path)) {
      for (const [index, line] of content.split('\n').entries()) {
        if (KNIP_IGNORE_KEY_RE.test(line)) {
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
    .filter(isCheckedPath);

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
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
