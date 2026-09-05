#!/usr/bin/env node
/**
 * registry-lint: "if it is not in docs/registry.md, it does not exist"
 * (AGENTS.md hard rule #1).
 *
 * Heuristic, proportionate to Phase 0's tiny surface area: grep every
 * top-level named export out of packages/*\/src and non-route-convention
 * files under apps/*\/app, and fail if the symbol name doesn't appear
 * anywhere in docs/registry.md. Next.js route-convention files (page,
 * layout, route, template, loading, error, not-found, default) are
 * excluded — their named exports (metadata, generateStaticParams, ...) are
 * framework-mandated, not reusable symbols a session might reinvent, which
 * is what the registry exists to prevent duplicating.
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const EXPORT_RE = /^export\s+(?:const|function|class|type|interface|enum)\s+([A-Za-z_$][A-Za-z0-9_$]*)/gm;

const ROUTE_CONVENTION_FILES = new Set([
  'page',
  'layout',
  'route',
  'template',
  'loading',
  'error',
  'not-found',
  'default',
]);

function isRouteConventionFile(filePath) {
  const base = filePath.split('/').pop().replace(/\.(ts|tsx)$/, '');
  return ROUTE_CONVENTION_FILES.has(base);
}

function isLintableSourceFile(filePath) {
  if (!/\.(ts|tsx)$/.test(filePath)) return false;
  if (filePath.endsWith('.test.ts') || filePath.endsWith('.test.tsx')) return false;
  if (filePath.includes('/__tests__/')) return false;
  if (filePath === 'packages/db/types/database.ts') return false; // generated
  if (filePath.startsWith('apps/') && filePath.includes('/app/') && isRouteConventionFile(filePath)) return false;
  return filePath.startsWith('packages/') || filePath.startsWith('apps/');
}

/** Pure, testable: given file contents and the registry text, list unregistered exports. */
export function findUnregisteredExports(files, registryContent) {
  const missing = [];
  for (const { path, content } of files) {
    if (!isLintableSourceFile(path)) continue;
    for (const match of content.matchAll(EXPORT_RE)) {
      const name = match[1];
      if (!registryContent.includes(name)) {
        missing.push({ path, name });
      }
    }
  }
  return missing;
}

function listTrackedFiles() {
  return execFileSync('git', ['ls-files'], { encoding: 'utf8' }).trim().split('\n').filter(Boolean);
}

function main() {
  const files = listTrackedFiles()
    .filter(isLintableSourceFile)
    .map((path) => ({ path, content: readFileSync(path, 'utf8') }));
  const registryContent = readFileSync('docs/registry.md', 'utf8');
  const missing = findUnregisteredExports(files, registryContent);

  if (missing.length > 0) {
    console.error('registry-lint: exported symbols missing from docs/registry.md:\n');
    for (const { path, name } of missing) {
      console.error(`  ${name}  (${path})`);
    }
    console.error('\nRegister each in docs/registry.md, or explain why not in docs/decisions.md.');
    process.exit(1);
  }
  console.log('registry-lint: every exported symbol is registered.');
}

// Cross-platform "run as CLI vs imported as a module" check — comparing
// against `file://${process.argv[1]}` breaks on Windows (backslash paths
// don't match the file:/// URL form), which is how this was first written
// and silently no-op'd instead of erroring. Verified by actually running it.
if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
