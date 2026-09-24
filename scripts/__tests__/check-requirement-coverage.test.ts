import { describe, expect, it } from 'vitest';
import {
  checkRequirementCoverage,
  extractRequirementIds,
  isCoverageTestPath,
  isHoldoutPath,
} from '../check-requirement-coverage.mjs';

const DOMAIN_RULES = `
# Domain rules

## Attendance
- **ATT-001** WHEN a member presents a QR code THE SYSTEM SHALL verify it.
- **ATT-002** IF the QR session is invalid THEN THE SYSTEM SHALL reject the check-in.

## Money
- **MNY-001** THE SYSTEM SHALL store every money amount as integer paise.
- **PAY-006** WHEN a payment uses the razorpay method THE SYSTEM SHALL treat Razorpay as truth.
`;

const OPENSPEC = `
### Requirement: Owner metrics enforce identity
MET-001 SHALL expose owner_metrics only to a real same-gym owner.
MET-002 SHALL accept neither dates or both inclusive local dates.

### Requirement: Decision references are not requirement IDs
ADR-016 records a stack decision.
OPEN-013 is an in-flight change number.
HARD-005 is a hardening goal id.
`;

describe('extractRequirementIds', () => {
  it('reads the bold EARS id format from docs/domain-rules.md', () => {
    expect(extractRequirementIds(DOMAIN_RULES)).toEqual([
      'ATT-001',
      'ATT-002',
      'MNY-001',
      'PAY-006',
    ]);
  });

  it('collects openspec requirement ids and skips decision and change ids', () => {
    expect(extractRequirementIds(OPENSPEC)).toEqual(['MET-001', 'MET-002']);
  });

  it('skips decision and change ids even when they are bold markers', () => {
    expect(extractRequirementIds('**OPEN-029** **ADR-016** **ATT-001**')).toEqual(['ATT-001']);
  });

  it('unions overlapping ids from both sources once', () => {
    const combined = `${DOMAIN_RULES}\nATT-001 SHALL also appear in openspec.\nMET-001 referenced here.`;
    expect(extractRequirementIds(combined)).toEqual([
      'ATT-001',
      'ATT-002',
      'MET-001',
      'MNY-001',
      'PAY-006',
    ]);
  });
});

describe('visible test path filters', () => {
  it('treats any holdout path as off-limits', () => {
    expect(isHoldoutPath('supabase/tests-holdout/h01_attendance_holdout.sql')).toBe(true);
    expect(isHoldoutPath('tests/e2e-holdout/payments.spec.ts')).toBe(true);
    expect(isHoldoutPath('apps/web/__tests__/HoldoutHelper.test.ts')).toBe(true);
    expect(isHoldoutPath('apps/web/__tests__/attendance.test.ts')).toBe(false);
  });

  it('accepts only visible test suites', () => {
    expect(isCoverageTestPath('apps/web/__tests__/attendance.test.ts')).toBe(true);
    expect(isCoverageTestPath('packages/shared/src/config/__tests__/env.test.ts')).toBe(true);
    expect(isCoverageTestPath('apps/web/lib/membership-state.test.ts')).toBe(true);
    expect(isCoverageTestPath('apps/web/lib/membership-state.test.tsx')).toBe(true);
    expect(isCoverageTestPath('tests/e2e/payments.spec.ts')).toBe(true);
    expect(isCoverageTestPath('supabase/tests/22_payment_record.sql')).toBe(true);
    expect(isCoverageTestPath('apps/web/lib/membership-state.ts')).toBe(false);
    expect(isCoverageTestPath('docs/domain-rules.md')).toBe(false);
    expect(isCoverageTestPath('supabase/tests-holdout/h01_attendance_holdout.sql')).toBe(false);
    expect(isCoverageTestPath('tests/e2e-holdout/payments.spec.ts')).toBe(false);
  });
});

describe('checkRequirementCoverage', () => {
  it('counts total, covered and uncovered requirement ids', () => {
    const result = checkRequirementCoverage(DOMAIN_RULES, [
      { path: 'apps/web/__tests__/attendance.test.ts', text: 'covers ATT-001 and ATT-002' },
      { path: 'supabase/tests/01_money.sql', text: 'MNY-001 paise invariant' },
    ]);

    expect(result).toEqual({
      total: 4,
      covered: 3,
      uncovered: 1,
      coveredIds: ['ATT-001', 'ATT-002', 'MNY-001'],
      uncoveredIds: ['PAY-006'],
    });
  });

  it('reports covered and uncovered id lists in sorted order', () => {
    const result = checkRequirementCoverage(DOMAIN_RULES, [
      { path: 'tests/e2e/payments.spec.ts', text: 'PAY-006 desk rejection' },
    ]);

    expect(result.total).toBe(4);
    expect(result.covered).toBe(1);
    expect(result.uncovered).toBe(3);
    expect(result.coveredIds).toEqual(['PAY-006']);
    expect(result.uncoveredIds).toEqual(['ATT-001', 'ATT-002', 'MNY-001']);
  });

  it('never counts holdout files toward coverage even if they are passed in', () => {
    const result = checkRequirementCoverage(DOMAIN_RULES, [
      {
        path: 'supabase/tests-holdout/h01_attendance_holdout.sql',
        text: 'ATT-001 ATT-002 MNY-001 PAY-006',
      },
      {
        path: 'tests/e2e-holdout/payments.spec.ts',
        text: 'ATT-001 ATT-002 MNY-001 PAY-006',
      },
    ]);

    expect(result).toEqual({
      total: 4,
      covered: 0,
      uncovered: 4,
      coveredIds: [],
      uncoveredIds: ['ATT-001', 'ATT-002', 'MNY-001', 'PAY-006'],
    });
  });

  it('ignores non-test source files that merely mention an id', () => {
    const result = checkRequirementCoverage(DOMAIN_RULES, [
      { path: 'apps/web/lib/attendance.ts', text: 'ATT-001 implementation' },
      { path: 'scripts/check-requirement-coverage.mjs', text: 'PAY-006' },
    ]);

    expect(result.covered).toBe(0);
    expect(result.uncoveredIds).toEqual(['ATT-001', 'ATT-002', 'MNY-001', 'PAY-006']);
  });

  it('matches ids on word boundaries only', () => {
    const result = checkRequirementCoverage('**ATT-001** one id', [
      { path: 'apps/web/__tests__/x.test.ts', text: 'ATT-0012 is a different token' },
    ]);

    expect(result.uncoveredIds).toEqual(['ATT-001']);
  });

  it('covers an id when any visible suite mentions it', () => {
    const result = checkRequirementCoverage(DOMAIN_RULES, [
      { path: 'apps/web/__tests__/a.test.ts', text: 'ATT-001' },
      { path: 'supabase/tests/b.sql', text: 'ATT-002' },
      { path: 'tests/e2e/c.spec.ts', text: 'MNY-001' },
      { path: 'packages/shared/src/config/__tests__/d.test.ts', text: 'PAY-006' },
    ]);

    expect(result).toMatchObject({
      total: 4,
      covered: 4,
      uncovered: 0,
      uncoveredIds: [],
      coveredIds: ['ATT-001', 'ATT-002', 'MNY-001', 'PAY-006'],
    });
  });
});
