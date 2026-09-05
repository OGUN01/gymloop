import { execFileSync } from 'node:child_process';
import { describe, expect, it } from 'vitest';
import { evaluateCommit } from '../check-test-immutability.mjs';

describe('evaluateCommit', () => {
  it('treats supabase/tests/** (pgTAP) as test files — a pgTAP test plus a migration in one commit violates', () => {
    const result = evaluateCommit({
      files: ['supabase/tests/rls_members.sql', 'supabase/migrations/20260901000000_members.sql'],
      message: 'add members table and its RLS test',
    });
    expect(result.violates).toBe(true);
  });

  it('can be imported when process.argv[1] is undefined (node --input-type=module -e)', () => {
    const scripts = ['check-test-immutability', 'registry-lint', 'check-escape-hatches'].map(
      (name) => new URL(`../${name}.mjs`, import.meta.url).href,
    );
    const source = scripts.map((href) => `await import(${JSON.stringify(href)});`).join('\n');
    expect(() => execFileSync(process.execPath, ['--input-type=module', '-e', source], { stdio: 'pipe' })).not.toThrow();
  });

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

  it('exempts scripts/** entirely — CI tooling is not EARS-spec-derived product code', () => {
    const result = evaluateCommit({
      files: ['scripts/registry-lint.mjs', 'scripts/__tests__/registry-lint.test.ts'],
      message: 'add a registry-lint check',
    });
    expect(result.violates).toBe(false);
  });

  it('still flags a scripts/** change mixed with a real product test+implementation pair', () => {
    const result = evaluateCommit({
      files: ['scripts/registry-lint.mjs', 'packages/shared/src/config/__tests__/env.test.ts', 'packages/shared/src/config/env.ts'],
      message: 'unrelated changes bundled together',
    });
    expect(result.violates).toBe(true);
  });

  it('allows a commit touching docs and implementation together (docs are not tests)', () => {
    const result = evaluateCommit({
      files: ['docs/registry.md', 'packages/shared/src/config/env.ts'],
      message: 'register a new export',
    });
    expect(result.violates).toBe(false);
  });
});
