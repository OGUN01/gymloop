#!/usr/bin/env node
/**
 * check-requirement-coverage: how much of the EARS requirement set is
 * actually named in a visible test? Holdout suites are never opened —
 * independence is the property (AGENTS.md hard rule #10), and a coverage
 * number that peeked at the blind half would be a lie about evidence.
 *
 * Report mode exits 0 even when IDs are uncovered. `--strict` is the
 * opt-in gate; this is not wired into CI as a blocker.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { pathToFileURL } from 'node:url';

const REQUIREMENT_ID_RE = /\b([A-Z]{2,5}-\d{3})\b/g;
const BOLD_REQUIREMENT_ID_RE = /\*\*([A-Z]{2,5}-\d{3})\*\*/g;
/** Decision and programme ids that share the shape but are not requirements. */
const NON_REQUIREMENT_PREFIXES = new Set(['ADR', 'OPEN', 'HARD', 'PILOT']);
const HOLDOUT_MARKER = 'holdout';
const TEST_EXT_RE = /\.test\.tsx?$/;
const ARGV_SKIP = 2;

/**
 * Pure, testable. Collect every requirement id in `text` (domain-rules bold
 * markers, and openspec bare ids that are not decision/change numbers).
 */
export function extractRequirementIds(text) {
  const found = new Set();
  const consider = (id) => {
    const prefix = id.slice(0, id.indexOf('-'));
    if (!NON_REQUIREMENT_PREFIXES.has(prefix)) found.add(id);
  };
  for (const match of text.matchAll(BOLD_REQUIREMENT_ID_RE)) consider(match[1]);
  for (const match of text.matchAll(REQUIREMENT_ID_RE)) consider(match[1]);
  return [...found].sort();
}

/** Pure. Any path containing "holdout" is off-limits and must never be opened. */
export function isHoldoutPath(path) {
  return path.replaceAll(sep, '/').toLowerCase().includes(HOLDOUT_MARKER);
}

/** Pure. Visible test suites only — never implementation files, never holdout. */
export function isCoverageTestPath(path) {
  const normalized = path.replaceAll(sep, '/');
  if (isHoldoutPath(normalized)) return false;
  if (normalized.includes('/__tests__/') || normalized.startsWith('__tests__/')) return true;
  if (TEST_EXT_RE.test(normalized)) return true;
  return normalized.startsWith('tests/e2e/')
    || normalized.includes('/tests/e2e/')
    || normalized.startsWith('supabase/tests/')
    || normalized.includes('/supabase/tests/');
}

function mentionedIds(text) {
  return new Set(text.match(REQUIREMENT_ID_RE) ?? []);
}

/**
 * Pure, testable. `testFiles` is [{ path, text }]. Holdout paths and
 * non-test paths are ignored even if a caller hands them over.
 */
export function checkRequirementCoverage(requirementsText, testFiles) {
  const required = extractRequirementIds(requirementsText);
  const coveredSet = new Set();
  for (const file of testFiles) {
    if (!isCoverageTestPath(file.path)) continue;
    for (const id of mentionedIds(file.text)) {
      if (required.includes(id)) coveredSet.add(id);
    }
  }
  const coveredIds = required.filter((id) => coveredSet.has(id));
  const uncoveredIds = required.filter((id) => !coveredSet.has(id));
  return {
    total: required.length,
    covered: coveredIds.length,
    uncovered: uncoveredIds.length,
    coveredIds,
    uncoveredIds,
  };
}

const SKIP_DIRS = new Set(['.git', 'node_modules', '.next', 'dist', 'store', 'artifacts', 'tmp-android-current.png']);

function listFiles(root, dir, out) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(entry.name)) continue;
    const absolute = join(dir, entry.name);
    const relativePath = relative(root, absolute).replaceAll(sep, '/');
    if (isHoldoutPath(relativePath)) continue;
    if (entry.isDirectory()) {
      listFiles(root, absolute, out);
      continue;
    }
    if (!entry.isFile()) continue;
    out.push(relativePath);
  }
}

function readRequirements(root) {
  const sources = [join(root, 'docs', 'domain-rules.md')];
  const specsDir = join(root, 'openspec', 'specs');
  let specFiles = [];
  try {
    listFiles(root, specsDir, specFiles);
  } catch {
    specFiles = [];
  }
  for (const relativePath of specFiles) {
    if (relativePath.endsWith('spec.md') && relativePath.startsWith('openspec/specs/')) {
      sources.push(join(root, relativePath));
    }
  }
  return sources.map((sourcePath) => readFileSync(sourcePath, 'utf8')).join('\n');
}

function readVisibleTests(root) {
  const allFiles = [];
  listFiles(root, root, allFiles);
  const testFiles = [];
  for (const relativePath of allFiles) {
    if (!isCoverageTestPath(relativePath)) continue;
    testFiles.push({ path: relativePath, text: readFileSync(join(root, relativePath), 'utf8') });
  }
  return testFiles;
}

function main() {
  const args = process.argv.slice(ARGV_SKIP);
  const asJson = args.includes('--json');
  const strict = args.includes('--strict');
  const root = process.cwd();
  const result = checkRequirementCoverage(readRequirements(root), readVisibleTests(root));

  if (asJson) {
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } else {
    process.stdout.write(
      `requirement-coverage: ${result.covered}/${result.total} covered, ${result.uncovered} uncovered\n`,
    );
    if (result.uncoveredIds.length > 0) {
      process.stdout.write('Uncovered requirement IDs:\n');
      for (const id of result.uncoveredIds) process.stdout.write(`  ${id}\n`);
    }
  }
  if (strict && result.uncovered > 0) process.exitCode = 1;
}

// See registry-lint.mjs for why this isn't `file://${process.argv[1]}`.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
