import { describe, expect, it } from 'vitest';

const PRODUCTION_PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const LOAD_PROJECT_REF = 'phase8-load-project';
const LOAD_API_URL = 'https://load.gymloop.example.com/';
const LOAD_SUPABASE_URL = `https://${LOAD_PROJECT_REF}.supabase.co/`;
const LOAD_CONFIRMATION = 'NON_PRODUCTION_LOAD_APPROVED';
const P95_BUDGET_MS = 850;
const GYM_COUNT = 100;
const MEMBERS_PER_GYM = 500;
const TOTAL_CHECK_INS = GYM_COUNT * MEMBERS_PER_GYM;
const RAW_RESULT_PATH = 'artifacts/phase8/load-raw.json';
const FIXTURE_PATH = 'artifacts/phase8/load-fixtures.json';
const FIRST_SUCCESS_STATUS = 200;
const LAST_SUCCESS_STATUS = 299;

type GymFixture = {
  gymId: string;
  token: string;
  memberIds: string[];
  ownedMemberIds: string[];
};

type LoadTarget = {
  apiUrl: string;
  confirmation: string;
  credentials: { kind: string; present: boolean; projectRef: string };
  observedApiProjectRef: string;
  observedSupabaseProjectRef: string;
  projectRef: string;
  supabaseUrl: string;
};

type LoadSafetyModule = {
  assertSafeLoadTarget: (target: unknown) => unknown;
  buildMorningCheckInWorkload: (input: unknown) => unknown;
  preflightLoadRun: (input: unknown) => unknown;
  summarizeRawResult: (input: unknown) => unknown;
};

const safeTarget = (): LoadTarget => ({
  apiUrl: LOAD_API_URL,
  confirmation: LOAD_CONFIRMATION,
  credentials: { kind: 'non-production', present: true, projectRef: LOAD_PROJECT_REF },
  observedApiProjectRef: LOAD_PROJECT_REF,
  observedSupabaseProjectRef: LOAD_PROJECT_REF,
  projectRef: LOAD_PROJECT_REF,
  supabaseUrl: LOAD_SUPABASE_URL,
});

const gymFixtures = (): GymFixture[] => Array.from({ length: GYM_COUNT }, (_, gymIndex) => {
  const memberIds = Array.from(
    { length: MEMBERS_PER_GYM },
    (_, memberIndex) => `member-${gymIndex}-${memberIndex}`,
  );
  return {
    gymId: `gym-${gymIndex}`,
    token: `token-${gymIndex}`,
    memberIds,
    ownedMemberIds: [...memberIds],
  };
});

const validWorkloadInput = () => ({
  gymFixtures: gymFixtures(),
  tenantIsolation: { denyCrossTenantMutation: true, denyCrossTenantRead: true },
  thresholds: { p95Ms: P95_BUDGET_MS },
});

const loadModule = async () => await import('../../scripts/phase8-load-safety') as LoadSafetyModule;

describe('independent HARD-004 isolated load safety holdout', () => {
  it('normalizes only a positively verified non-production target and rejects production, mismatched observations and a mismatched Supabase hostname', async () => {
    const { assertSafeLoadTarget } = await loadModule();

    expect(assertSafeLoadTarget(safeTarget())).toEqual({
      apiUrl: LOAD_API_URL.slice(0, -1),
      nonProduction: true,
      projectRef: LOAD_PROJECT_REF,
      supabaseUrl: LOAD_SUPABASE_URL.slice(0, -1),
    });
    for (const target of [
      { ...safeTarget(), projectRef: PRODUCTION_PROJECT_REF },
      { ...safeTarget(), observedApiProjectRef: PRODUCTION_PROJECT_REF },
      { ...safeTarget(), observedSupabaseProjectRef: PRODUCTION_PROJECT_REF },
      { ...safeTarget(), observedApiProjectRef: 'another-project' },
      { ...safeTarget(), observedSupabaseProjectRef: 'another-project' },
      { ...safeTarget(), supabaseUrl: 'https://another-project.supabase.co' },
      { ...safeTarget(), confirmation: true },
      { ...safeTarget(), credentials: { ...safeTarget().credentials, kind: 'production' } },
      { ...safeTarget(), credentials: { ...safeTarget().credentials, present: false } },
      { ...safeTarget(), credentials: { ...safeTarget().credentials, projectRef: 'another-project' } },
    ]) expect(() => assertSafeLoadTarget(target)).toThrow();
  });

  it('requires finite positive p95, both independently proved denials and caller-supplied fixtures', async () => {
    const { buildMorningCheckInWorkload } = await loadModule();

    for (const thresholds of [
      { p95Ms: 0 },
      { p95Ms: -1 },
      { p95Ms: Number.NaN },
      { p95Ms: Number.POSITIVE_INFINITY },
      { p95Ms: `${P95_BUDGET_MS}` },
    ]) expect(() => buildMorningCheckInWorkload({ ...validWorkloadInput(), thresholds })).toThrow();
    for (const tenantIsolation of [
      { denyCrossTenantMutation: false, denyCrossTenantRead: true },
      { denyCrossTenantMutation: true, denyCrossTenantRead: false },
      { denyCrossTenantMutation: true, denyCrossTenantRead: 'true' },
    ]) expect(() => buildMorningCheckInWorkload({ ...validWorkloadInput(), tenantIsolation })).toThrow();
    expect(() => buildMorningCheckInWorkload({
      thresholds: { p95Ms: P95_BUDGET_MS },
      tenantIsolation: { denyCrossTenantMutation: true, denyCrossTenantRead: true },
    })).toThrow();
  });

  it('retains the supplied exact 100-gym by 500-member workload and rejects duplicate or cross-owned fixture contents', async () => {
    const { buildMorningCheckInWorkload, preflightLoadRun } = await loadModule();
    const input = validWorkloadInput();
    const workload = buildMorningCheckInWorkload(input) as {
      gymFixtures: GymFixture[];
      gyms: number;
      membersPerGym: number;
      totalMembers: number;
    };

    expect(workload.gyms).toBe(GYM_COUNT);
    expect(workload.membersPerGym).toBe(MEMBERS_PER_GYM);
    expect(workload.totalMembers).toBe(TOTAL_CHECK_INS);
    expect(workload.gymFixtures).toEqual(input.gymFixtures);

    const duplicateGym = structuredClone(input);
    duplicateGym.gymFixtures[1]!.gymId = duplicateGym.gymFixtures[0]!.gymId;
    expect(() => buildMorningCheckInWorkload(duplicateGym)).toThrow();

    const duplicateToken = structuredClone(input);
    duplicateToken.gymFixtures[1]!.token = duplicateToken.gymFixtures[0]!.token;
    expect(() => buildMorningCheckInWorkload(duplicateToken)).toThrow();

    const crossOwned = structuredClone(input);
    crossOwned.gymFixtures[1]!.memberIds[0] = crossOwned.gymFixtures[0]!.memberIds[0]!;
    crossOwned.gymFixtures[1]!.ownedMemberIds[0] = crossOwned.gymFixtures[0]!.memberIds[0]!;
    expect(() => buildMorningCheckInWorkload(crossOwned)).toThrow();

    const invalidAfterBuild = structuredClone(workload);
    invalidAfterBuild.gymFixtures[1]!.ownedMemberIds[0] = invalidAfterBuild.gymFixtures[0]!.memberIds[0]!;
    expect(() => preflightLoadRun({
      fixturePath: FIXTURE_PATH,
      rawResultPath: RAW_RESULT_PATH,
      target: safeTarget(),
      workload: invalidAfterBuild,
    })).toThrow();
  });

  it('does not report passed unless measured completion, p95, exact read denial and every non-2xx mutation status prove the approved target', async () => {
    const { summarizeRawResult } = await loadModule();
    const baseResult = {
      measured: {
        completedCheckIns: TOTAL_CHECK_INS,
        crossTenantMutationStatus: 403,
        crossTenantReadDenied: true,
        p95Ms: P95_BUDGET_MS,
      },
      rawResultPath: RAW_RESULT_PATH,
      status: 'passed',
      target: safeTarget(),
      thresholds: { p95Ms: P95_BUDGET_MS },
    };

    for (const result of [
      { ...baseResult, measured: { ...baseResult.measured, p95Ms: P95_BUDGET_MS + 1 } },
      { ...baseResult, measured: { ...baseResult.measured, completedCheckIns: TOTAL_CHECK_INS - 1 } },
      { ...baseResult, measured: { ...baseResult.measured, crossTenantReadDenied: false } },
      { ...baseResult, measured: { ...baseResult.measured, crossTenantMutationStatus: FIRST_SUCCESS_STATUS } },
      { ...baseResult, measured: { ...baseResult.measured, crossTenantMutationStatus: LAST_SUCCESS_STATUS } },
      { ...baseResult, target: { ...safeTarget(), observedApiProjectRef: 'another-project' } },
    ]) expect((summarizeRawResult(result) as { status?: string }).status).not.toBe('passed');

    const passed = summarizeRawResult(baseResult) as {
      rawResultPath?: string;
      status?: string;
      target?: unknown;
    };
    expect(passed.status).toBe('passed');
    expect(passed.rawResultPath).toBe(RAW_RESULT_PATH);
    expect(passed.target).toEqual({
      apiUrl: LOAD_API_URL.slice(0, -1),
      nonProduction: true,
      projectRef: LOAD_PROJECT_REF,
      supabaseUrl: LOAD_SUPABASE_URL.slice(0, -1),
    });
  });
});
