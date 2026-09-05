// Root ESLint flat config. Two rules here are constitutional (docs/architecture.md,
// AGENTS.md) and must never be loosened without an ADR in docs/decisions.md.
import js from '@eslint/js';
import tseslint from 'typescript-eslint';

const ENV_FILE = 'packages/shared/src/config/env.ts';
const CONSTANTS_FILE = 'packages/shared/src/config/constants.ts';

export default tseslint.config(
  {
    ignores: [
      '**/node_modules/**',
      '**/dist/**',
      '**/.next/**',
      '**/.turbo/**',
      '**/coverage/**',
      'packages/db/types/database.ts', // generated, never linted/hand-edited
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      // Constitutional rule #1 (AGENTS.md): every magic number lives in
      // packages/shared/src/config/constants.ts. Scoped narrowly so it stays
      // enforceable instead of getting neutralised by eslint-disable comments.
      'no-magic-numbers': [
        'error',
        {
          ignore: [0, 1, -1], // sentinels every codebase treats as non-magic (e.g. z.string().min(1))
          ignoreArrayIndexes: true,
          ignoreDefaultValues: true,
          ignoreEnums: true,
          detectObjects: false,
        },
      ],
      // Constitutional rule #2 (AGENTS.md): process.env is only ever read
      // inside env.ts. Everywhere else imports the validated env export.
      'no-restricted-properties': [
        'error',
        {
          object: 'process',
          property: 'env',
          message: 'Import env from packages/shared/src/config/env.ts instead of reading process.env directly.',
        },
      ],
    },
  },
  {
    // The one file allowed to read process.env directly.
    files: [ENV_FILE],
    rules: {
      'no-restricted-properties': 'off',
    },
  },
  {
    // no-magic-numbers is noise in tests, per docs/decisions.md.
    files: ['**/*.test.ts', '**/*.test.tsx', 'tests/**'],
    rules: {
      'no-magic-numbers': 'off',
    },
  },
  {
    // This file IS the named-constant definition site the rule exists to
    // force everyone else toward — it necessarily contains literal numbers.
    files: [CONSTANTS_FILE],
    rules: {
      'no-magic-numbers': 'off',
    },
  },
);
