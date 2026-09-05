import { describe, expect, it } from 'vitest';
import { findEscapeHatches } from '../check-escape-hatches.mjs';

describe('findEscapeHatches', () => {
  it('flags an eslint-disable comment in a source file', () => {
    const found = findEscapeHatches([
      { path: 'packages/shared/src/a.ts', content: 'const x = 1;\n// eslint-disable-next-line no-magic-numbers\nconst y = 42;\n' },
    ]);
    expect(found).toEqual([{ path: 'packages/shared/src/a.ts', line: 2, kind: 'eslint-disable' }]);
  });

  it('flags a knip ignore entry in knip.json', () => {
    const found = findEscapeHatches([
      { path: 'knip.json', content: '{\n  "ignore": ["src/legacy/**"]\n}\n' },
    ]);
    expect(found).toEqual([{ path: 'knip.json', line: 2, kind: 'knip ignore entry' }]);
  });

  it('allows legitimate knip config that is not a suppression', () => {
    const found = findEscapeHatches([
      { path: 'knip.json', content: '{\n  "workspaces": {\n    "apps/web": {}\n  }\n}\n' },
    ]);
    expect(found).toEqual([]);
  });

  it('does not flag prose that merely mentions the term mid-sentence', () => {
    const found = findEscapeHatches([
      {
        path: 'eslint.config.mjs',
        content: '// scoped so it stays enforceable rather than neutralised by eslint-disable comments\n',
      },
    ]);
    expect(found).toEqual([]);
  });

  it('flags a block-comment directive too', () => {
    const found = findEscapeHatches([
      { path: 'apps/web/app/x.ts', content: '/* eslint-disable no-undef */\n' },
    ]);
    expect(found).toEqual([{ path: 'apps/web/app/x.ts', line: 1, kind: 'eslint-disable' }]);
  });

  it('ignores non-source files and clean source', () => {
    const found = findEscapeHatches([
      { path: 'docs/decisions.md', content: 'We discussed eslint-disable and banned it.\n' },
      { path: 'packages/shared/src/b.ts', content: 'export const ok = true;\n' },
    ]);
    expect(found).toEqual([]);
  });
});
