// Phase 6 member-import shared mapping and normalization unit tests.
//
// Written implementation-blind from the frozen contract
// docs/planning/phase6-import-contract.md (CSV-D05 mapping, CSV-D06
// normalization, "Shared header rule", "Stable file/API error codes") and the
// frozen module layout in openspec/changes/phase6-import/plan.md. No
// implementation existed when these tests were written; they are red until
// packages/shared/src/api/member-imports.ts is created and re-exported from
// the '@gymloop/shared' barrel (packages/shared/src/index.ts).
//
// Required exports of packages/shared/src/api/member-imports.ts (the shapes
// below are what these tests drive; keep them minimal and contract-shaped):
//
//   export type MemberImportField =
//     | 'full_name' | 'phone' | 'member_code' | 'email'
//     | 'gender' | 'date_of_birth' | 'joined_on' | 'notes';
//   export type MemberImportPhoneCountry = 'IN' | 'E164';
//   // Union discriminated by `kind`. `number` carries the exact non-date
//   // numeric source text (parseNumber: source => source). `date` carries the
//   // Gymloop-converted ISO day from retained XLSX source metadata, or null
//   // when the source scalar violates a calendar rule (row invalid_date).
//   export type MemberImportCell =
//     | { kind: 'empty' }
//     | { kind: 'text'; text: string }
//     | { kind: 'number'; source: string }
//     | { kind: 'boolean'; value: boolean }
//     | { kind: 'date'; isoDay: string | null };
//   export type MemberImportReasonCode =
//     | 'required' | 'invalid_cell_type' | 'ambiguous_phone'
//     | 'invalid_phone' | 'invalid_date';
//   export type MemberImportRowError = {
//     field: MemberImportField;
//     code: MemberImportReasonCode;
//   };
//   export function normalizeMemberImportRow(
//     cells: Partial<Record<MemberImportField, MemberImportCell>>,
//     phoneDefaultCountry: MemberImportPhoneCountry,
//   ): {
//     normalized: Partial<Record<MemberImportField, string | null>>;
//     reasonCodes: MemberImportRowError[];
//   };
//   export function validateMemberImportMapping(
//     input: unknown,
//     headerCount: number,
//   ): { mapping: Partial<Record<MemberImportField, number>> } | { error: 'invalid_mapping' };
//
// Semantics pinned by these tests:
// - `normalized` carries exactly the mapped fields. A successfully normalized
//   value is preserved; a blank or unparseable value is null, and its
//   reasonCodes entry distinguishes invalid input from a valid blank
//   ("Each object carries `rowNumber` and every whitelisted field:
//   successfully normalized values are preserved; a blank or unparseable value
//   is null and its corresponding phase-A error distinguishes invalid input
//   from a valid blank.").
// - reasonCodes collects every field error and is sorted by the contract's
//   field order (full_name, phone, member_code, email, gender, date_of_birth,
//   joined_on, notes) and then by code ("All row errors are collected; a row is
//   not stopped at its first field error. The reason-code array is sorted by
//   target-field order above and then by code so the same file always produces
//   the same report.").
// - Row-level codes produced outside this normalizer (extra_column) and the
//   later phase-B codes (future_date, the duplicate classes) are not part of
//   MemberImportReasonCode.
// - `packages/shared` stays platform-free (AGENTS.md hard rule 11): these
//   functions use no Node or DOM APIs.

import { describe, expect, it } from 'vitest';
import {
  normalizeMemberImportRow,
  validateMemberImportMapping,
} from '../member-imports';
import type { MemberImportCell } from '../member-imports';

const emptyCell = (): MemberImportCell => ({ kind: 'empty' });
const textCell = (text: string): MemberImportCell => ({ kind: 'text', text });
const numberCell = (source: string): MemberImportCell => ({ kind: 'number', source });
const booleanCell = (value: boolean): MemberImportCell => ({ kind: 'boolean', value });
const dateCell = (isoDay: string | null): MemberImportCell => ({ kind: 'date', isoDay });

type NormalizerCells = Parameters<typeof normalizeMemberImportRow>[0];

describe('validateMemberImportMapping (CSV-D05)', () => {
  it('accepts the minimal required mapping with zero-based indexes', () => {
    expect(validateMemberImportMapping({ full_name: 0, phone: 1 }, 2)).toEqual({
      mapping: { full_name: 0, phone: 1 },
    });
  });

  it('accepts the full whitelisted mapping', () => {
    const mapping = {
      full_name: 0,
      phone: 1,
      member_code: 2,
      email: 3,
      gender: 4,
      date_of_birth: 5,
      joined_on: 6,
      notes: 7,
    };
    expect(validateMemberImportMapping(mapping, 8)).toEqual({ mapping });
  });

  it('accepts index 63 against a 64-column header and refuses index 64', () => {
    // "columns 64" limit; each source index must be in the header.
    expect(validateMemberImportMapping({ full_name: 63, phone: 62 }, 64)).toEqual({
      mapping: { full_name: 63, phone: 62 },
    });
    expect(validateMemberImportMapping({ full_name: 64, phone: 62 }, 64)).toEqual({
      error: 'invalid_mapping',
    });
  });

  it.each([
    ['empty object', {}, 2],
    ['missing full_name', { phone: 1 }, 2],
    ['missing phone', { full_name: 0 }, 1],
    ['unknown member field "status"', { full_name: 0, phone: 1, status: 2 }, 3],
    ['unknown member field "tenant_id"', { full_name: 0, phone: 1, tenant_id: 1 }, 2],
    ['unknown member field "membership_id"', { full_name: 0, phone: 1, membership_id: 1 }, 2],
    ['index equal to the header count', { full_name: 0, phone: 2 }, 2],
    ['index above the header count', { full_name: 0, phone: 3 }, 2],
    ['negative index', { full_name: -1, phone: 1 }, 2],
    ['fractional index', { full_name: 1.5, phone: 1 }, 2],
    ['string index', { full_name: '0', phone: 1 }, 2],
    ['boolean index', { full_name: true, phone: 1 }, 2],
    ['null input', null, 2],
    ['array input', [{ full_name: 0, phone: 1 }], 2],
  ])('refuses %s with invalid_mapping', (_label, input, headerCount) => {
    expect(validateMemberImportMapping(input, headerCount)).toEqual({
      error: 'invalid_mapping',
    });
  });

  it('refuses one source column feeding two required targets', () => {
    expect(validateMemberImportMapping({ full_name: 0, phone: 0 }, 1)).toEqual({
      error: 'invalid_mapping',
    });
  });

  it('refuses one source column feeding a required and an optional target', () => {
    expect(validateMemberImportMapping({ full_name: 0, phone: 1, email: 0 }, 2)).toEqual({
      error: 'invalid_mapping',
    });
  });
});

describe('normalizeMemberImportRow (CSV-D06)', () => {
  describe('full_name', () => {
    it('trims and collapses whitespace runs to one ASCII space', () => {
      const r = normalizeMemberImportRow({ full_name: textCell('  Asha   Rao ') }, 'IN');
      expect(r.normalized).toEqual({ full_name: 'Asha Rao' });
      expect(r.reasonCodes).toEqual([]);
    });

    it('applies NFKC before trimming (fullwidth letters, NBSP, ideographic space)', () => {
      // "For `full_name` and `gender`, apply NFKC, trim Unicode whitespace and
      // collapse each remaining whitespace run to one ASCII space."
      const r = normalizeMemberImportRow(
        { full_name: textCell('Ａｓｈａ 　Rao') },
        'IN',
      );
      expect(r.normalized).toEqual({ full_name: 'Asha Rao' });
    });

    it('blank full_name is required', () => {
      const r = normalizeMemberImportRow({ full_name: textCell('  \t ') }, 'IN');
      expect(r.normalized).toEqual({ full_name: null });
      expect(r.reasonCodes).toEqual([{ field: 'full_name', code: 'required' }]);
    });

    it('empty full_name cell is required', () => {
      const r = normalizeMemberImportRow({ full_name: emptyCell() }, 'IN');
      expect(r.normalized).toEqual({ full_name: null });
      expect(r.reasonCodes).toEqual([{ field: 'full_name', code: 'required' }]);
    });

    it('number cells render as their exact source text', () => {
      const r = normalizeMemberImportRow({ full_name: numberCell('123') }, 'IN');
      expect(r.normalized).toEqual({ full_name: '123' });
      expect(r.reasonCodes).toEqual([]);
    });
  });

  describe('phone', () => {
    it('converts a ten-digit 6-9 bare value to +91 only in IN mode', () => {
      // "A bare value is converted to `+91` only when `phoneDefaultCountry` is
      // `IN` and it is exactly ten ASCII digits beginning with 6, 7, 8 or 9."
      const inResult = normalizeMemberImportRow({ phone: textCell('9876543210') }, 'IN');
      expect(inResult.normalized).toEqual({ phone: '+919876543210' });
      expect(inResult.reasonCodes).toEqual([]);
      const e164Result = normalizeMemberImportRow({ phone: textCell('9876543210') }, 'E164');
      expect(e164Result.normalized).toEqual({ phone: null });
      expect(e164Result.reasonCodes).toEqual([{ field: 'phone', code: 'ambiguous_phone' }]);
    });

    it('keeps an already-international value unchanged in both modes', () => {
      expect(normalizeMemberImportRow({ phone: textCell('+919876543210') }, 'E164').normalized).toEqual({
        phone: '+919876543210',
      });
      expect(normalizeMemberImportRow({ phone: textCell('+919876543210') }, 'IN').normalized).toEqual({
        phone: '+919876543210',
      });
    });

    it('removes display separators and Unicode whitespace before validation', () => {
      // "apply NFKC, trim, and remove Unicode whitespace plus the display
      // separators `-`, `(` and `)`"
      expect(normalizeMemberImportRow({ phone: textCell('+91 98765-43210') }, 'E164').normalized).toEqual({
        phone: '+919876543210',
      });
      expect(
        normalizeMemberImportRow({ phone: textCell('(+91) 98765　43210') }, 'E164').normalized,
      ).toEqual({ phone: '+919876543210' });
      expect(normalizeMemberImportRow({ phone: textCell(' 98765-43210 ') }, 'IN').normalized).toEqual({
        phone: '+919876543210',
      });
    });

    it('applies NFKC before the digit checks (fullwidth digits)', () => {
      const r = normalizeMemberImportRow({ phone: textCell('９８７６５４３２１０') }, 'IN');
      // Fullwidth digits 9876543210 normalize to ASCII, then convert.
      expect(r.normalized).toEqual({ phone: '+919876543210' });
    });

    it.each([
      ['ten digits beginning with 1', '1234567890'],
      ['nine digits', '987654321'],
      ['eleven digits', '98765432101'],
      ['eleven digits with a trunk zero', '09876543210'],
    ])('classifies %s as ambiguous_phone in IN mode', (_label, value) => {
      // "Another all-digit bare value is `ambiguous_phone`; The importer does
      // not infer `00`, a trunk `0`, a country code or digits lost by Excel."
      const r = normalizeMemberImportRow({ phone: textCell(value) }, 'IN');
      expect(r.normalized).toEqual({ phone: null });
      expect(r.reasonCodes).toEqual([{ field: 'phone', code: 'ambiguous_phone' }]);
    });

    it.each([
      ['too short after the plus', '+9198765'],
      ['too long after the plus', '+9112345678901234'],
      ['letters', 'abc'],
      ['plus then letters', '+91abc'],
      ['plus in the middle of a bare value', '91+9876543210'],
    ])('classifies %s as invalid_phone', (_label, value) => {
      // "A value beginning with `+` must then match the existing member
      // constraint `^\\+[1-9][0-9]{7,14}$. ... any remaining shape is
      // `invalid_phone`."
      const r = normalizeMemberImportRow({ phone: textCell(value) }, 'IN');
      expect(r.normalized).toEqual({ phone: null });
      expect(r.reasonCodes).toEqual([{ field: 'phone', code: 'invalid_phone' }]);
    });

    it('preserves numeric phone source text exactly (no JavaScript number)', () => {
      const r = normalizeMemberImportRow({ phone: numberCell('9876543210') }, 'IN');
      expect(r.normalized).toEqual({ phone: '+919876543210' });
      expect(r.reasonCodes).toEqual([]);
    });

    it('blank phone is required', () => {
      const emptyResult = normalizeMemberImportRow({ phone: emptyCell() }, 'IN');
      expect(emptyResult.normalized).toEqual({ phone: null });
      expect(emptyResult.reasonCodes).toEqual([{ field: 'phone', code: 'required' }]);
      const blankResult = normalizeMemberImportRow({ phone: textCell('  ') }, 'IN');
      expect(blankResult.reasonCodes).toEqual([{ field: 'phone', code: 'required' }]);
    });
  });

  describe('member_code and email', () => {
    it('trims only outer whitespace and preserves internal spacing and case', () => {
      // "For `member_code` and `email`, apply NFKC and trim outer Unicode
      // whitespace while preserving internal characters and case."
      const r = normalizeMemberImportRow(
        { member_code: textCell('  Mc 01 '), email: textCell('  a@b.com ') },
        'IN',
      );
      expect(r.normalized).toEqual({ member_code: 'Mc 01', email: 'a@b.com' });
      expect(r.reasonCodes).toEqual([]);
    });

    it('does not collapse internal whitespace runs (unlike full_name)', () => {
      const r = normalizeMemberImportRow({ member_code: textCell('  a  b  ') }, 'IN');
      // NFKC turns the NBSPs into spaces, but the run is not collapsed.
      expect(r.normalized).toEqual({ member_code: 'a  b' });
    });

    it('applies NFKC (fullwidth characters normalize) while preserving case', () => {
      const r = normalizeMemberImportRow(
        {
          member_code: textCell('Ｍｃ００１'),
          email: textCell('ａｂ＠ｅｘａｍｐｌｅ．ｃｏｍ'),
        },
        'IN',
      );
      expect(r.normalized).toEqual({ member_code: 'Mc001', email: 'ab@example.com' });
    });

    it('blank member_code or email is null without an error', () => {
      const r = normalizeMemberImportRow({ member_code: emptyCell(), email: textCell('  ') }, 'IN');
      expect(r.normalized).toEqual({ member_code: null, email: null });
      expect(r.reasonCodes).toEqual([]);
    });

    it('keeps a 17-digit numeric source exact', () => {
      // "Numeric phones therefore do not lose precision inside JavaScript."
      const r = normalizeMemberImportRow({ member_code: numberCell('12345678901234567') }, 'IN');
      expect(r.normalized).toEqual({ member_code: '12345678901234567' });
    });
  });

  describe('notes', () => {
    it('normalizes CRLF and CR to LF and trims only outer whitespace', () => {
      // "For `notes`, normalize CRLF/CR to LF and trim only outer whitespace."
      const r = normalizeMemberImportRow({ notes: textCell('  a\r\nb\rc\nd  ') }, 'IN');
      expect(r.normalized).toEqual({ notes: 'a\nb\nc\nd' });
      expect(r.reasonCodes).toEqual([]);
    });

    it('keeps internal line breaks and spacing', () => {
      const r = normalizeMemberImportRow({ notes: textCell('a\n\nb  c') }, 'IN');
      expect(r.normalized).toEqual({ notes: 'a\n\nb  c' });
    });

    it('does not apply NFKC to notes', () => {
      const r = normalizeMemberImportRow({ notes: textCell('a b') }, 'IN');
      expect(r.normalized).toEqual({ notes: 'a b' });
    });

    it('blank notes are null without an error', () => {
      const r = normalizeMemberImportRow({ notes: textCell('  ') }, 'IN');
      expect(r.normalized).toEqual({ notes: null });
      expect(r.reasonCodes).toEqual([]);
    });
  });

  describe('gender', () => {
    it('trims and collapses whitespace runs like full_name', () => {
      const r = normalizeMemberImportRow({ gender: textCell('  Male   Rao ') }, 'IN');
      expect(r.normalized).toEqual({ gender: 'Male Rao' });
      expect(r.reasonCodes).toEqual([]);
    });

    it('blank gender is null without an error', () => {
      // "Empty optional `gender` is null."
      const r = normalizeMemberImportRow({ gender: emptyCell() }, 'IN');
      expect(r.normalized).toEqual({ gender: null });
      expect(r.reasonCodes).toEqual([]);
    });
  });

  describe('boolean rendering', () => {
    it('renders TRUE or FALSE for text targets', () => {
      // "A boolean is rendered as `TRUE` or `FALSE` for a text target."
      const r = normalizeMemberImportRow(
        { full_name: booleanCell(true), notes: booleanCell(false), gender: booleanCell(true) },
        'IN',
      );
      expect(r.normalized).toEqual({ full_name: 'TRUE', notes: 'FALSE', gender: 'TRUE' });
      expect(r.reasonCodes).toEqual([]);
    });
  });

  describe('dates', () => {
    it.each([
      ['ISO text', '2026-09-10', '2026-09-10'],
      ['DD/MM/YYYY text', '10/09/2026', '2026-09-10'],
      ['DD/MM/YYYY with day 01 and month 02', '01/02/2026', '2026-02-01'],
      ['leap-day text', '29/02/2024', '2024-02-29'],
    ])('accepts %s', (_label, input, expected) => {
      const r = normalizeMemberImportRow({ date_of_birth: textCell(input) }, 'IN');
      expect(r.normalized).toEqual({ date_of_birth: expected });
      expect(r.reasonCodes).toEqual([]);
    });

    it.each([
      ['29 February in a non-leap year', '29/02/2026'],
      ['31 April', '31/04/2026'],
      ['MM/DD-only shape (13 cannot be a month)', '10/13/2026'],
      ['unpadded ISO text', '2026-9-1'],
      ['timestamp', '2026-09-10T00:00:00Z'],
      ['leading space (date text must match exactly)', ' 2026-09-10'],
      ['words', 'yesterday'],
    ])('reports %s as invalid_date', (_label, input) => {
      // "For dates, accept a source-validated XLSX date, text exactly
      // `YYYY-MM-DD`, or text exactly `DD/MM/YYYY`. Validate the Gregorian date
      // without JavaScript rollover and output an ISO date string or null for
      // blank. Timestamps, words, `MM/DD/YYYY`, unformatted Excel serials and
      // impossible dates are `invalid_date`."
      const r = normalizeMemberImportRow({ date_of_birth: textCell(input) }, 'IN');
      expect(r.normalized).toEqual({ date_of_birth: null });
      expect(r.reasonCodes).toEqual([{ field: 'date_of_birth', code: 'invalid_date' }]);
    });

    it('accepts a source-validated XLSX date cell for both date targets', () => {
      expect(normalizeMemberImportRow({ date_of_birth: dateCell('1900-01-01') }, 'IN').normalized).toEqual({
        date_of_birth: '1900-01-01',
      });
      expect(normalizeMemberImportRow({ joined_on: dateCell('2026-09-10') }, 'IN').normalized).toEqual({
        joined_on: '2026-09-10',
      });
    });

    it('a calendar-invalid source date cell is invalid_date', () => {
      const r = normalizeMemberImportRow({ date_of_birth: dateCell(null) }, 'IN');
      expect(r.normalized).toEqual({ date_of_birth: null });
      expect(r.reasonCodes).toEqual([{ field: 'date_of_birth', code: 'invalid_date' }]);
    });

    it('unformatted numeric serials are invalid_date, never guessed as dates', () => {
      const r = normalizeMemberImportRow({ date_of_birth: numberCell('45000') }, 'IN');
      expect(r.normalized).toEqual({ date_of_birth: null });
      expect(r.reasonCodes).toEqual([{ field: 'date_of_birth', code: 'invalid_date' }]);
    });

    it('a boolean cell for a date target is invalid_date', () => {
      // Interpretation: the date rule accepts only a source-validated XLSX
      // date cell, exact YYYY-MM-DD text or exact DD/MM/YYYY text. A boolean
      // is none of those, so like an unformatted serial it is invalid_date.
      const r = normalizeMemberImportRow({ date_of_birth: booleanCell(true) }, 'IN');
      expect(r.normalized).toEqual({ date_of_birth: null });
      expect(r.reasonCodes).toEqual([{ field: 'date_of_birth', code: 'invalid_date' }]);
    });

    it('blank dates are null without an error (joined_on defaulting happens in prepare)', () => {
      // "The Route Handler does not default blank `joined_on`".
      const r = normalizeMemberImportRow({ joined_on: emptyCell() }, 'IN');
      expect(r.normalized).toEqual({ joined_on: null });
      expect(r.reasonCodes).toEqual([]);
    });

    it('a date cell mapped to a non-date target is invalid_cell_type', () => {
      // "A source date cell is accepted only by `date_of_birth` or
      // `joined_on`; mapping one to another field is `invalid_cell_type`."
      const r = normalizeMemberImportRow({ full_name: dateCell('2026-09-10') }, 'IN');
      expect(r.normalized).toEqual({ full_name: null });
      expect(r.reasonCodes).toEqual([{ field: 'full_name', code: 'invalid_cell_type' }]);
    });

    it('a date cell mapped to phone is invalid_cell_type', () => {
      const r = normalizeMemberImportRow({ phone: dateCell('2026-09-10') }, 'IN');
      expect(r.normalized).toEqual({ phone: null });
      expect(r.reasonCodes).toEqual([{ field: 'phone', code: 'invalid_cell_type' }]);
    });
  });

  describe('error collection and ordering', () => {
    it('collects every field error instead of stopping at the first', () => {
      const r = normalizeMemberImportRow(
        {
          full_name: emptyCell(),
          phone: textCell('abc'),
          date_of_birth: textCell('31/04/2026'),
        } as NormalizerCells,
        'IN',
      );
      expect(r.normalized).toEqual({ full_name: null, phone: null, date_of_birth: null });
      expect(r.reasonCodes).toEqual([
        { field: 'full_name', code: 'required' },
        { field: 'phone', code: 'invalid_phone' },
        { field: 'date_of_birth', code: 'invalid_date' },
      ]);
    });

    it('sorts by the contract field order regardless of mapping order', () => {
      const r = normalizeMemberImportRow(
        {
          joined_on: numberCell('45000'),
          full_name: textCell('   '),
          phone: textCell('1234567890'),
        } as NormalizerCells,
        'IN',
      );
      expect(r.reasonCodes).toEqual([
        { field: 'full_name', code: 'required' },
        { field: 'phone', code: 'ambiguous_phone' },
        { field: 'joined_on', code: 'invalid_date' },
      ]);
    });

    it('normalized contains exactly the mapped fields', () => {
      const r = normalizeMemberImportRow(
        { full_name: textCell('Asha Rao'), phone: textCell('+919876543210') },
        'E164',
      );
      expect(Object.keys(r.normalized).sort()).toEqual(['full_name', 'phone']);
      expect(r.reasonCodes).toEqual([]);
    });

    it('leaves a fully valid row with no reason codes', () => {
      const r = normalizeMemberImportRow(
        {
          full_name: textCell('Asha Rao'),
          phone: textCell('+919876543210'),
          member_code: textCell('MC001'),
          email: textCell('asha@example.com'),
          gender: textCell('Female'),
          date_of_birth: textCell('10/09/1990'),
          joined_on: textCell('2026-09-10'),
          notes: textCell('Prefers evenings'),
        } as NormalizerCells,
        'IN',
      );
      expect(r.reasonCodes).toEqual([]);
      expect(r.normalized).toEqual({
        full_name: 'Asha Rao',
        phone: '+919876543210',
        member_code: 'MC001',
        email: 'asha@example.com',
        gender: 'Female',
        date_of_birth: '1990-09-10',
        joined_on: '2026-09-10',
        notes: 'Prefers evenings',
      });
    });
  });
});
