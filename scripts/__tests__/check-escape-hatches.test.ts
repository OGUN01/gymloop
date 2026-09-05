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

  it('flags TypeScript suppressions — the other way to silence a gate in a strict repo', () => {
    const found = findEscapeHatches([
      { path: 'packages/shared/src/a.ts', content: 'const x = 1;\n// @ts-' + 'ignore\nconst y: number = "s";\n' },
    ]);
    expect(found).toEqual([
      { path: 'packages/shared/src/a.ts', line: 2, kind: 'TypeScript suppression' },
    ]);
  });

  it('flags a knip ignore hidden in package.json, not just knip.json', () => {
    const found = findEscapeHatches([
      { path: 'package.json', content: '{\n  "knip": {\n    "ignore": ["scripts/**"]\n  }\n}\n' },
    ]);
    expect(found).toEqual([{ path: 'package.json', line: 3, kind: 'knip ignore entry' }]);
  });

  it('skips its own fixtures but not other test files', () => {
    const directive = '// ' + 'eslint-disable-next-line no-undef\n';
    expect(
      findEscapeHatches([{ path: 'scripts/__tests__/check-escape-hatches.test.ts', content: directive }]),
    ).toEqual([]);
    // A suppression hidden in a *product* test is still a violation.
    expect(
      findEscapeHatches([{ path: 'packages/shared/src/config/__tests__/env.test.ts', content: directive }]),
    ).toEqual([
      { path: 'packages/shared/src/config/__tests__/env.test.ts', line: 1, kind: 'eslint-disable' },
    ]);
  });

  it('flags an inline ESLint config comment that switches a rule off, in every spelling', () => {
    const files = [
      { path: 'packages/shared/src/a.ts', content: '/* eslint no-magic-numbers: "off" */\nconst y = 42;\n' },
      { path: 'packages/shared/src/b.ts', content: '/* eslint no-magic-numbers: 0 */\n' },
      { path: 'packages/shared/src/c.ts', content: '/* eslint no-magic-numbers: off, no-restricted-properties: off */\n' },
      { path: 'packages/shared/src/d.ts', content: '/*eslint @typescript-eslint/no-unused-vars:0*/\n' },
    ];
    expect(findEscapeHatches(files)).toEqual([
      { path: 'packages/shared/src/a.ts', line: 1, kind: 'eslint inline config' },
      { path: 'packages/shared/src/b.ts', line: 1, kind: 'eslint inline config' },
      { path: 'packages/shared/src/c.ts', line: 1, kind: 'eslint inline config' },
      { path: 'packages/shared/src/d.ts', line: 1, kind: 'eslint inline config' },
    ]);
    // Not inline config: eslint-env, and prose mentioning eslint.
    expect(
      findEscapeHatches([
        { path: 'packages/shared/src/e.ts', content: '/* eslint-env node */\n/* the eslint rule set is constitutional */\n' },
      ]),
    ).toEqual([]);
  });

  it('flags a nested ESLint config file anywhere except the root eslint.config.mjs', () => {
    const files = [
      { path: 'eslint.config.mjs', content: 'export default [];\n' },
      { path: 'packages/shared/eslint.config.mjs', content: 'export default [];\n' },
      { path: 'apps/web/eslint.config.ts', content: 'export default [];\n' },
      { path: 'apps/web/.eslintrc.json', content: '{}\n' },
      { path: 'packages/db/.eslintrc', content: '{}\n' },
    ];
    expect(findEscapeHatches(files)).toEqual([
      { path: 'packages/shared/eslint.config.mjs', line: 1, kind: 'nested eslint config' },
      { path: 'apps/web/eslint.config.ts', line: 1, kind: 'nested eslint config' },
      { path: 'apps/web/.eslintrc.json', line: 1, kind: 'nested eslint config' },
      { path: 'packages/db/.eslintrc', line: 1, kind: 'nested eslint config' },
    ]);
  });

  it('flags a knip ignore in every config filename knip honours, quoted or bare keys', () => {
    const files = [
      { path: 'knip.jsonc', content: '{\n  "ignore": ["a"]\n}\n' },
      { path: '.knip.json', content: '{\n  "ignoreDependencies": ["a"]\n}\n' },
      { path: '.knip.jsonc', content: '{\n  "ignoreBinaries": ["a"]\n}\n' },
      { path: 'knip.ts', content: 'export default {\n  ignore: ["a"],\n};\n' },
      { path: 'knip.js', content: 'module.exports = {\n  ignoreWorkspaces: ["a"],\n};\n' },
      { path: 'knip.mjs', content: 'export default {\n  ignoreMembers: ["a"],\n};\n' },
      { path: 'knip.config.mjs', content: 'export default {\n  ignore: ["a"],\n};\n' },
      { path: 'knip.config.cjs', content: 'module.exports = {\n  ignore: ["a"],\n};\n' },
      { path: 'knip.config.json', content: '{\n  "ignore": ["a"]\n}\n' },
      { path: 'knip.config.jsonc', content: '{\n  "ignoreExportsUsedInFile": true\n}\n' },
    ];
    expect(findEscapeHatches(files)).toEqual(
      files.map(({ path }) => ({ path, line: 2, kind: 'knip ignore entry' })),
    );
  });

  it('ignores non-source files and clean source', () => {
    const found = findEscapeHatches([
      { path: 'docs/decisions.md', content: 'We discussed eslint-disable and banned it.\n' },
      { path: 'packages/shared/src/b.ts', content: 'export const ok = true;\n' },
    ]);
    expect(found).toEqual([]);
  });
});
