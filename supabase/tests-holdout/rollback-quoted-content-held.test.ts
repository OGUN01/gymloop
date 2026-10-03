import { describe, expect, it } from 'vitest';

import { findNonRolledBackTests } from '../../scripts/check-pgtap-rollback.mjs';

describe('rollback guard quoted-content holdout', () => {
  it('refuses completion variants after quoted decoys and intervening comments', () => {
    for (const command of [
      'COMMIT WORK',
      'END TRANSACTION',
      'commit /* separation */ transaction AND NO CHAIN',
      'end -- separation\n WORK AND CHAIN',
      'COMMIT AND CHAIN',
      'END AND NO CHAIN',
    ]) {
      expect(findNonRolledBackTests([{
        path: 'completion-variant.sql',
        content: `BEGIN; SELECT '$hidden$; COMMIT WORK', 1 AS "END TRANSACTION"; ${command}; ROLLBACK;`,
      }])).toEqual([
        expect.objectContaining({ path: 'completion-variant.sql', reason: expect.any(String) }),
      ]);
    }
  });

  it('leaves completion variant text and identifier substrings inert', () => {
    expect(findNonRolledBackTests([{
      path: 'completion-variant-decoys.sql',
      content: 'BEGIN; SELECT \'COMMIT TRANSACTION AND CHAIN; END WORK AND NO CHAIN\' AS "COMMIT WORK", 1 AS weekend_transaction, 1 AS commit_workflow; ROLLBACK;',
    }])).toEqual([]);
  });

  it('keeps initial escape semantics through a chain of newline and comment separators', () => {
    for (const separator of ['\n', ' /* join\n/* nested */ tail */ ', ' -- join\n']) {
      expect(findNonRolledBackTests([{
        path: 'continued-decoys.sql',
        content: String.raw`BEGIN; SELECT E'head'${separator}'mid\'; COMMIT; -- $phantom$'${separator}'tail\'; END; /* $other$'; ROLLBACK;`,
      }])).toEqual([]);
    }
  });

  it('sees real completion after the closing quote of a continued escape chain', () => {
    for (const command of ['COMMIT', 'END']) {
      expect(findNonRolledBackTests([{
        path: 'continued-completion.sql',
        content: String.raw`BEGIN; SELECT E'head'
'body\'; -- false boundary $decoy$'
'last\' /* quoted */'; ${command}; ROLLBACK;`,
      }])).toEqual([
        expect.objectContaining({ path: 'continued-completion.sql', reason: expect.any(String) }),
      ]);
    }
  });

  it('resets escape semantics after a substantive token or statement boundary', () => {
    for (const content of [
      String.raw`BEGIN; SELECT E'head',
'\'; ROLLBACK;`,
      String.raw`BEGIN; SELECT E'head'; SELECT
'\'; ROLLBACK;`,
    ]) {
      expect(findNonRolledBackTests([{ path: 'escape-reset.sql', content }])).toEqual([]);
    }
  });

  it('treats synthetic tags and doubled quotes inside literals as inert', () => {
    expect(findNonRolledBackTests([{
      path: 'quoted-label.sql',
      content: "BEGIN; SELECT 'owner''s $fake$COMMIT; -- /* $fake$'; ROLLBACK;",
    }])).toEqual([]);
  });

  it('consumes escaped quotes in explicit escape strings before looking for tags', () => {
    expect(findNonRolledBackTests([{
      path: 'escape-label.sql',
      content: String.raw`START TRANSACTION; SELECT E'can\'t $trap$; -- /* $trap$'; ROLLBACK;`,
    }])).toEqual([]);
  });

  it('preserves comment lookalikes inside doubled quoted identifiers', () => {
    expect(findNonRolledBackTests([{
      path: 'identifier.sql',
      content: 'BEGIN; SELECT 1 AS "a""$phantom$; -- /* $phantom$"; ROLLBACK;',
    }])).toEqual([]);
  });

  it('recognizes numeric suffix and non-Latin dollar tags with exact case closure', () => {
    expect(findNonRolledBackTests([{
      path: 'tag-cases.sql',
      content: "BEGIN; DO $Round7$ BEGIN PERFORM '$round7$'; END; $Round7$; DO $नाम2$ BEGIN PERFORM 'ok'; END; $नाम2$; ROLLBACK;",
    }])).toEqual([]);
  });

  it('refuses actual top-level transaction completion behind quoted decoys', () => {
    for (const command of ['COMMIT', 'END']) {
      expect(findNonRolledBackTests([{
        path: 'completion.sql',
        content: `BEGIN; SELECT '$mask$; -- /*'; SELECT 1 AS "$veil$"; ${command}; ROLLBACK;`,
      }])).toEqual([expect.objectContaining({ path: 'completion.sql', reason: expect.any(String) })]);
    }
  });

  it('retains refusal of a real commit inside a recognized body', () => {
    expect(findNonRolledBackTests([{
      path: 'body-commit.sql',
      content: "BEGIN; SELECT '$notbody$'; DO $कार्य8$ BEGIN COMMIT; END; $कार्य8$; ROLLBACK;",
    }])).toEqual([expect.objectContaining({ path: 'body-commit.sql', reason: expect.any(String) })]);
  });

  it('ignores nested comments without inventing a commit from them', () => {
    expect(findNonRolledBackTests([{
      path: 'nested-comment.sql',
      content: "BEGIN; /* outer ' $x$ /* inner COMMIT; */ END; */ SELECT '/* ; -- */'; -- COMMIT;\nROLLBACK;",
    }])).toEqual([]);
  });

  it('fails closed for unterminated quotes, comments and mismatched dollar tag case', () => {
    for (const content of [
      "BEGIN; SELECT 'unfinished; ROLLBACK;",
      'BEGIN; SELECT "unfinished; ROLLBACK;',
      'BEGIN; /* unfinished ROLLBACK;',
      'BEGIN; DO $Upper9$ BEGIN NULL; END; $upper9$; ROLLBACK;',
    ]) {
      expect(findNonRolledBackTests([{ path: 'unterminated.sql', content }])).toEqual([
        expect.objectContaining({ path: 'unterminated.sql', reason: expect.any(String) }),
      ]);
    }
  });
});
