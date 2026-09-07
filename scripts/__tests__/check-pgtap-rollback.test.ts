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

  // The gate split on every `;` without knowing what a dollar-quoted body is,
  // so the `end;` closing a plpgsql block became a top-level statement reading
  // exactly END — which the gate treats as a synonym for COMMIT. Four holdout
  // files that were correctly rollback-wrapped were failed for it.
  const DO_BLOCK = `begin;
select plan(1);
do $$
begin
  perform 1;
end;
$$;
select ok(true, 'x');
select * from finish();
rollback;
`;

  it('accepts a DO block whose body ends with `end;` inside dollar quotes', () => {
    expect(findNonRolledBackTests([{ path: 'supabase/tests/e.sql', content: DO_BLOCK }])).toEqual([]);
  });

  const DOLLAR_QUOTED_QUERY = `begin;
select plan(1);
select is_empty($q$select 1 where 'a' = 'b'; $q$, 'a semicolon inside a query');
rollback;
`;

  it('accepts a dollar-quoted query containing a semicolon', () => {
    expect(
      findNonRolledBackTests([{ path: 'supabase/tests/f.sql', content: DOLLAR_QUOTED_QUERY }]),
    ).toEqual([]);
  });

  // The other half of the same blindness, and the half that matters: since
  // Postgres 11 a plpgsql block can genuinely COMMIT, so skipping dollar-quoted
  // bodies wholesale would trade a false alarm for a silent hole.
  const COMMITTING_DO_BLOCK = `begin;
select plan(1);
do $$
begin
  insert into t values (1);
  commit;
end;
$$;
rollback;
`;

  it('still flags a real COMMIT inside a DO block', () => {
    expect(
      findNonRolledBackTests([{ path: 'supabase/tests/g.sql', content: COMMITTING_DO_BLOCK }]),
    ).toEqual([{ path: 'supabase/tests/g.sql', reason: 'contains COMMIT' }]);
  });
});
