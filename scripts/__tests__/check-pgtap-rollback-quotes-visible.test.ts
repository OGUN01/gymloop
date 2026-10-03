import { describe, expect, it } from 'vitest';
import { findNonRolledBackTests } from '../../scripts/check-pgtap-rollback.mjs';

describe('rollback guard quoted-content contract', () => {
  it('keeps dollar-tag decoys in ordinary literals inert', () => {
    expect(findNonRolledBackTests([{ path: 'literal.sql', content: "BEGIN; SELECT 'demo$sha256$active$location$0001'; ROLLBACK;" }])).toEqual([]);
  });

  it('preserves semicolons, comment text and doubled quotes inside literals', () => {
    expect(findNonRolledBackTests([{ path: 'punctuation.sql', content: "BEGIN; SELECT 'it''s ; -- /* COMMIT; $decoy$'; ROLLBACK;" }])).toEqual([]);
  });

  it('consumes escaped quotes in explicit E strings before structural scanning', () => {
    expect(findNonRolledBackTests([{ path: 'escape.sql', content: String.raw`BEGIN; SELECT E'can\'t ; -- /* $shadow$ COMMIT;'; ROLLBACK;` }])).toEqual([]);
  });

  it('keeps quoted identifiers and their doubled quotes inert', () => {
    expect(findNonRolledBackTests([{ path: 'identifier.sql', content: 'BEGIN; SELECT 1 AS "report""$shadow$; -- /* COMMIT;"; ROLLBACK;' }])).toEqual([]);
  });

  it('recognizes empty, numbered and non-Latin dollar tags', () => {
    expect(findNonRolledBackTests([{ path: 'tags.sql', content: 'BEGIN; DO $$ BEGIN PERFORM 1; END; $$; DO $batch2$ BEGIN PERFORM 1; END; $batch2$; DO $कार्य$ BEGIN PERFORM 1; END; $कार्य$; ROLLBACK;' }])).toEqual([]);
  });

  it('refuses real COMMIT after an ordinary quoted dollar decoy', () => {
    expect(findNonRolledBackTests([{ path: 'commit.sql', content: "BEGIN; SELECT '$shadow$'; COMMIT; SELECT '$shadow$'; ROLLBACK;" }])).toEqual([expect.objectContaining({ path: 'commit.sql', reason: expect.any(String) })]);
  });

  it('refuses real END after a quoted identifier dollar decoy', () => {
    expect(findNonRolledBackTests([{ path: 'end.sql', content: 'BEGIN; SELECT 1 AS "$shadow$"; END; SELECT 1 AS "$shadow$"; ROLLBACK;' }])).toEqual([expect.objectContaining({ path: 'end.sql', reason: expect.any(String) })]);
  });

  it('retains conservative refusal of an actual dollar-body COMMIT', () => {
    expect(findNonRolledBackTests([{ path: 'body.sql', content: 'BEGIN; DO $batch2$ BEGIN COMMIT; END; $batch2$; ROLLBACK;' }])).toEqual([expect.objectContaining({ path: 'body.sql', reason: expect.any(String) })]);
  });

  it('ignores actual line comments and nested block comments', () => {
    expect(findNonRolledBackTests([{ path: 'comments.sql', content: '/* outer /* COMMIT; $fake$ */ END; */ BEGIN; -- COMMIT; $fake$\nSELECT 1; /* ROLLBACK; /* END; */ COMMIT; */ ROLLBACK;' }])).toEqual([]);
  });

  it('fails closed on unterminated quoted or comment constructs', () => {
    for (const content of ["BEGIN; SELECT 'unfinished; ROLLBACK;", 'BEGIN; SELECT 1 AS "unfinished; ROLLBACK;', 'BEGIN; DO $batch2$ BEGIN NULL; END; $BATCH2$; ROLLBACK;', 'BEGIN; SELECT 1; /* unfinished; ROLLBACK;']) {
      expect(findNonRolledBackTests([{ path: 'unfinished.sql', content }])).toEqual([expect.objectContaining({ path: 'unfinished.sql', reason: expect.any(String) })]);
    }
  });
});
