/**
 * Layer boundaries for the monorepo (docs/architecture.md, "Boundaries").
 * Two invariants:
 *   1. packages/* never import from apps/* (packages are consumed by apps,
 *      never the reverse).
 *   2. packages/shared stays platform-free: no Node core builtin, and no
 *      npm package it doesn't itself list as a dependency (which next and
 *      react-dom, deliberately, never will be) — it's consumed by web,
 *      mobile, and Edge Functions.
 *
 * The second invariant is enforced via `couldNotResolve`, not a path match
 * on specific package names (e.g. `node_modules/next/`). Verified this
 * matters: under pnpm's strict per-package node_modules, `next` and
 * `react-dom` are NOT resolvable from packages/shared (it never lists them
 * as dependencies) — a path-match rule against their resolved node_modules
 * location silently never fires, because there's no resolved path to match.
 * `couldNotResolve` catches exactly that unresolvable case, and is more
 * general besides: it forbids ANY platform-specific package sneaking in via
 * a dependency someone adds to packages/shared later, not just the two named
 * here today.
 */
export default {
  forbidden: [
    {
      name: 'packages-not-to-apps',
      comment: 'packages/* must not depend on apps/* — packages are consumed by apps, never the reverse.',
      severity: 'error',
      from: { path: '^packages' },
      to: { path: '^apps' },
    },
    {
      name: 'shared-not-to-node-core',
      comment: 'packages/shared must stay platform-free — no Node core builtins (fs, path, node:*, ...).',
      severity: 'error',
      from: { path: '^packages/shared' },
      to: { dependencyTypes: ['core'] },
    },
    {
      name: 'shared-not-to-unresolvable',
      comment:
        'packages/shared importing a package it does not itself depend on (next, react-dom, ...) is unresolvable under pnpm\'s strict per-package node_modules — that unresolvability IS the portability guard.',
      severity: 'error',
      from: { path: '^packages/shared' },
      to: { couldNotResolve: true },
    },
  ],
  options: {
    tsPreCompilationDeps: true,
    tsConfig: {
      fileName: 'tsconfig.base.json',
    },
    doNotFollow: {
      path: 'node_modules',
    },
    exclude: {
      path: '(^|/)(dist|\\.next|\\.turbo|coverage|node_modules)(/|$)',
    },
  },
};
