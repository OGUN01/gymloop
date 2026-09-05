#!/usr/bin/env node
/**
 * registry-lint: "if it is not in docs/registry.md, it does not exist"
 * (AGENTS.md hard rule #1).
 *
 * Heuristic, proportionate to Phase 0's tiny surface area: grep every
 * top-level named export out of packages/*\/src and non-route-convention
 * files under apps/*\/app, and fail if the symbol name doesn't appear
 * anywhere in docs/registry.md. In Next.js route-convention files (page,
 * layout, route, template, loading, error, not-found, default) only the
 * framework-mandated export names (default, GET, metadata, ...) are
 * exempt — a reusable helper exported next to a Route Handler is still a
 * symbol a session might reinvent, which is what the registry prevents.
 */
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// Declaration exports. `async` sits between `export` and `function`, so it
// must be optional here — without it every `export async function` (i.e.
// every Route Handler and async util from Phase 2 on) is invisible to this
// gate. Found by a fresh-context critic auditing Phase 0.
// Anchored at `^[ \t]*`, not `^`: an indented `  export const x` is still
// an export. Group 1 says whether it is the file's default export.
const EXPORT_DECL_RE =
  /^[ \t]*export\s+(default\s+)?(?:async\s+)?(?:const|let|var|function\*?|class|type|interface|enum)\s+([A-Za-z_$][A-Za-z0-9_$]*)/gm;

// Braced exports: `export { a, b as c }`, `export type { T }`, `export { x } from './y'`.
const EXPORT_BRACE_RE = /^[ \t]*export\s*(?:type\s+)?\{([^}]*)\}/gm;

// Namespace re-export: `export * as ns from './d'`.
const EXPORT_NAMESPACE_RE = /^[ \t]*export\s+\*\s+as\s+([A-Za-z_$][A-Za-z0-9_$]*)/gm;

// Destructured declaration: `export const { a, b: c } = obj`, `export let [x, y] = arr`.
const EXPORT_DESTRUCTURE_RE = /^[ \t]*export\s+(?:const|let|var)\s+([{[][\s\S]*?[}\]])\s*=/gm;

const IDENTIFIER_RE = /^[A-Za-z_$][A-Za-z0-9_$]*$/;

// Export names Next.js itself defines in route-convention files. Anything
// else exported from such a file is an ordinary reusable symbol.
const NEXT_ROUTE_EXPORTS = new Set([
  'default',
  'GET',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'HEAD',
  'OPTIONS',
  'metadata',
  'generateMetadata',
  'generateStaticParams',
  'generateViewport',
  'viewport',
  'dynamic',
  'revalidate',
  'fetchCache',
  'runtime',
  'preferredRegion',
  'maxDuration',
  'dynamicParams',
  'config',
]);
const NO_EXEMPT_EXPORTS = new Set();

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
  if (!filePath.startsWith('apps/') || !filePath.includes('/app/')) return false;
  const base = filePath.split('/').pop().replace(/\.(ts|tsx)$/, '');
  return ROUTE_CONVENTION_FILES.has(base);
}

function isLintableSourceFile(filePath) {
  if (!/\.(ts|tsx)$/.test(filePath)) return false;
  if (filePath.endsWith('.test.ts') || filePath.endsWith('.test.tsx')) return false;
  if (filePath.includes('/__tests__/')) return false;
  if (filePath === 'packages/db/types/database.ts') return false; // generated
  // supabase/functions/** is included deliberately: ADR-012 puts the Razorpay
  // webhooks and cron jobs there from Phase 5, which is the highest-risk code
  // in the product. It was invisible to every gate until a verification pass
  // pointed out that the prefix check only covered packages/ and apps/.
  return (
    filePath.startsWith('packages/') ||
    filePath.startsWith('apps/') ||
    filePath.startsWith('supabase/functions/')
  );
}

/**
 * Registered means the name appears as a backticked cell in a registry
 * table (`| \`NAME\` | ... |`), NOT merely as a substring of the file. A
 * bare `registryContent.includes(name)` passes any export called `Role`,
 * `env`, or `TRIAL` purely because those letters already occur somewhere in
 * the prose — a false-negative machine for a rule whose whole point is
 * "if it is not in the registry, it does not exist".
 */
function isRegistered(name, registryContent) {
  return new RegExp('`' + name.replace(/[$]/g, '\\$&') + '`').test(registryContent);
}

/**
 * Every export in one file as { name, exportedAs }: `name` is what must be
 * registered (the declared identifier), `exportedAs` is the module-level
 * export name (`default` for a default declaration) — the thing a framework
 * convention can legitimately claim.
 */
function exportedNames(content) {
  const names = [];
  for (const match of content.matchAll(EXPORT_DECL_RE)) {
    names.push({ name: match[2], exportedAs: match[1] ? 'default' : match[2] });
  }
  for (const match of content.matchAll(EXPORT_NAMESPACE_RE)) {
    names.push({ name: match[1], exportedAs: match[1] });
  }
  for (const match of content.matchAll(EXPORT_BRACE_RE)) {
    for (const clause of match[1].split(',')) {
      // `a`, `a as b`, `default as b` — the exported name is what follows
      // `as`, otherwise the bare identifier.
      const parts = clause.trim().split(/\s+as\s+/);
      const name = (parts[parts.length - 1] ?? '').trim();
      if (IDENTIFIER_RE.test(name) && name !== 'default') {
        names.push({ name, exportedAs: name });
      }
    }
  }
  for (const match of content.matchAll(EXPORT_DESTRUCTURE_RE)) {
    for (const clause of match[1].split(',')) {
      // `a`, `a: b`, `a = 1`, `...rest` — the bound name is what follows the
      // colon (if any), before any default. Brackets and dots are pattern
      // syntax, not part of the name.
      // ponytail: one level deep; nested `{ a: { b } }` still yields `b`, but
      // a nested default value containing `}` or `,` is not parsed.
      const name = clause.split('=')[0].split(':').pop().replace(/[{}[\]\s.]/g, '');
      if (IDENTIFIER_RE.test(name)) {
        names.push({ name, exportedAs: name });
      }
    }
  }
  return names;
}

/** Pure, testable: given file contents and the registry text, list unregistered exports. */
export function findUnregisteredExports(files, registryContent) {
  const missing = [];
  for (const { path, content } of files) {
    if (!isLintableSourceFile(path)) continue;
    const exempt = isRouteConventionFile(path) ? NEXT_ROUTE_EXPORTS : NO_EXEMPT_EXPORTS;
    for (const { name, exportedAs } of exportedNames(content)) {
      if (exempt.has(exportedAs)) continue;
      if (!isRegistered(name, registryContent)) {
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
// `process.argv[1]` is undefined under `node --input-type=module -e`, and
// pathToFileURL(undefined) throws at import time — hence the guard.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
