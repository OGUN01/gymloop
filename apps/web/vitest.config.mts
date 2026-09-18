import { defineConfig } from 'vitest/config';

export default defineConfig({
  oxc: { jsx: { runtime: 'automatic' } },
  test: {
    include: ['**/*.{test,spec}.{ts,tsx}'],
    maxWorkers: 4,
    minWorkers: 1,
    testTimeout: 10_000,
  },
});
