/**
 * Layer boundaries for the monorepo (docs/architecture.md, "Boundaries").
 * Two invariants:
 *   1. packages/* never import from apps/* (packages are consumed by apps,
 *      never the reverse).
 *   2. packages/shared stays platform-free: no next/*, react-dom, or any
 *      Node core builtin — it's consumed by web, mobile, and Edge Functions.
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
      name: 'shared-not-to-next',
      comment: 'packages/shared must stay platform-free — it is consumed by web, mobile, and Edge Functions.',
      severity: 'error',
      from: { path: '^packages/shared' },
      to: { path: 'node_modules/next/' },
    },
    {
      name: 'shared-not-to-react-dom',
      comment: 'packages/shared must stay platform-free — react-dom is web-only.',
      severity: 'error',
      from: { path: '^packages/shared' },
      to: { path: 'node_modules/react-dom/' },
    },
    {
      name: 'shared-not-to-node-core',
      comment: 'packages/shared must stay platform-free — no Node core builtins (fs, path, node:*, ...).',
      severity: 'error',
      from: { path: '^packages/shared' },
      to: { dependencyTypes: ['core'] },
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
