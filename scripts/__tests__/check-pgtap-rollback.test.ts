import { describe, expect, it } from 'vitest';
import { findNonRolledBackTests } from '../check-pgtap-rollback.mjs';

const GOOD = `-- cross-tenant leak test (ADR-030: rollback-wrapped)
BEGIN;
SELECT plan(2);
/* a block comment mentioning COMMIT is fine */
SELECT is(current_setting('request.jwt.claims', true), NULL, 'no claim');
SELECT * FROM finish();
ROLLBACK;
`;

describe('findNonRolledBackTests', () => {
  it('accepts a BEGIN … ROLLBACK file, ignoring comments', () => {
    expect(findNonRolledBackTests([{ path: 'supabase/tests/a.sql', content: GOOD }])).toEqual([]);
  });

  it('flags a file that does not start with BEGIN', () => {
    const content = 'SELECT plan(1);\nSELECT ok(true);\nROLLBACK;\n';
    expect(findNonRolledBackTests([{ path: 'supabase/tests/b.sql', content }])).toEqual([
      { path: 'supabase/tests/b.sql', reason: 'does not start with BEGIN' },
    ]);
  });

  it('flags a file that ends with COMMIT instead of ROLLBACK', () => {
    const content = 'begin;\nselect plan(1);\nselect ok(true);\ncommit;\n';
    expect(findNonRolledBackTests([{ path: 'supabase/tests/c.sql', content }])).toEqual([
      { path: 'supabase/tests/c.sql', reason: 'does not end with ROLLBACK' },
      { path: 'supabase/tests/c.sql', reason: 'contains COMMIT' },
    ]);
  });

  it('flags a COMMIT hidden in the middle even when the file ends with ROLLBACK', () => {
    const content = 'BEGIN;\nINSERT INTO t VALUES (1);\nCOMMIT;\nBEGIN;\nSELECT ok(true);\nROLLBACK;\n';
    expect(findNonRolledBackTests([{ path: 'supabase/tests/d.sql', content }])).toEqual([
      { path: 'supabase/tests/d.sql', reason: 'contains COMMIT' },
    ]);
  });
});
