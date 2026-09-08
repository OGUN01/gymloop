#!/usr/bin/env node
/**
 * check-test-immutability: a commit touching test files and implementation
 * files together is rejected unless its message carries an explicit `spec:`
 * prefix, signalling a human-approved spec change (AGENTS.md hard rule #10,
 * master prompt §9/§10). Checked per-commit, not per-PR-diff, so one
 * compliant-looking PR can't hide a single bad commit inside it.
 */
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

// supabase/tests/** holds the pgTAP RLS tests — a test suite like any other.
// supabase/tests-holdout/** is the blind half, moved in from its own repo by
// ADR-060; it is a test suite by every rule that matters here.
const TEST_PATH_RE =
  /(^tests\/|^supabase\/tests\/|^supabase\/tests-holdout\/|\/__tests__\/|\.test\.(ts|tsx|js)$)/;
const IMPLEMENTATION_EXT_RE = /\.(ts|tsx|js|mjs|sql)$/;
const SHORT_SHA_LENGTH = 12;

// scripts/** is CI/build tooling — it never goes through the EARS-spec →
// tests-first → implementation pipeline this rule exists to protect (the
// concern is an implementer quietly loosening a product test derived from
// an approved spec to make their own broken code pass). A script and its
// own test are legitimately authored together in one commit. Found this
// scoping gap by actually running the rule against this repo's own
// scripts/ commit, not by reasoning about it in the abstract.
function isScriptsPath(path) {
  return path.startsWith('scripts/');
}

function isTestPath(path) {
  return !isScriptsPath(path) && TEST_PATH_RE.test(path);
}

function isImplementationPath(path) {
  return !isScriptsPath(path) && IMPLEMENTATION_EXT_RE.test(path) && !TEST_PATH_RE.test(path);
}

/** Pure, testable. */
export function evaluateCommit({ files, message }) {
  const touchesTests = files.some(isTestPath);
  const touchesImplementation = files.some(isImplementationPath);
  const hasSpecPrefix = /^spec:/i.test(message.trim());

  if (touchesTests && touchesImplementation && !hasSpecPrefix) {
    return {
      violates: true,
      reason: 'touches both test files and implementation files without a `spec:` commit-message prefix',
    };
  }
  return { violates: false };
}

/**
 * `<base>..<head>` fails when base has no common history with head — the
 * repo's very first commit (no parent) and a CI push event's `before` SHA
 * on the first push to a branch (all-zeros) both hit this. Fall back to
 * just checking `head` alone rather than crashing.
 */
function commitsInRange(range, head) {
  try {
    return execFileSync('git', ['rev-list', range], { encoding: 'utf8' }).trim().split('\n').filter(Boolean);
  } catch {
    console.warn(`check-test-immutability: range "${range}" is not resolvable, checking ${head} alone.`);
    return [head];
  }
}

function filesInCommit(sha) {
  return execFileSync('git', ['diff-tree', '--no-commit-id', '--name-only', '-r', sha], { encoding: 'utf8' })
    .trim()
    .split('\n')
    .filter(Boolean);
}

function messageOf(sha) {
  return execFileSync('git', ['log', '-1', '--format=%B', sha], { encoding: 'utf8' });
}

function main() {
  const range = process.argv[2] ?? 'HEAD^..HEAD';
  const head = range.includes('..') ? range.split('..')[1] : range;
  const shas = commitsInRange(range, head);
  const violations = [];

  for (const sha of shas) {
    const result = evaluateCommit({ files: filesInCommit(sha), message: messageOf(sha) });
    if (result.violates) {
      violations.push({ sha, reason: result.reason });
    }
  }

  if (violations.length > 0) {
    console.error('check-test-immutability: violating commits:\n');
    for (const { sha, reason } of violations) {
      console.error(`  ${sha.slice(0, SHORT_SHA_LENGTH)}  ${reason}`);
    }
    process.exit(1);
  }
  console.log(`check-test-immutability: ${shas.length} commit(s) checked, none violate.`);
}

// See registry-lint.mjs for why this isn't `file://${process.argv[1]}`.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
