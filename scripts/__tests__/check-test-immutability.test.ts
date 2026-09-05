import { describe, expect, it } from 'vitest';
import { evaluateCommit } from '../check-test-immutability.mjs';

describe('evaluateCommit', () => {
  it('violates when a commit touches a test file and an implementation file with no spec: prefix', () => {
    const result = evaluateCommit({
      files: ['packages/shared/src/config/__tests__/env.test.ts', 'packages/shared/src/config/env.ts'],
      message: 'tweak env validation',
    });
    expect(result.violates).toBe(true);
  });

  it('allows the same change with a spec: prefix', () => {
    const result = evaluateCommit({
      files: ['packages/shared/src/config/__tests__/env.test.ts', 'packages/shared/src/config/env.ts'],
      message: 'spec: widen env schema per approved change',
    });
    expect(result.violates).toBe(false);
  });

  it('allows a commit touching only implementation files', () => {
    const result = evaluateCommit({
      files: ['packages/shared/src/config/env.ts'],
      message: 'fix a typo',
    });
    expect(result.violates).toBe(false);
  });

  it('allows a commit touching only test files', () => {
    const result = evaluateCommit({
      files: ['packages/shared/src/config/__tests__/env.test.ts'],
      message: 'add a test case',
    });
    expect(result.violates).toBe(false);
  });

  it('allows a commit touching docs and implementation together (docs are not tests)', () => {
    const result = evaluateCommit({
      files: ['docs/registry.md', 'packages/shared/src/config/env.ts'],
      message: 'register a new export',
    });
    expect(result.violates).toBe(false);
  });
});
