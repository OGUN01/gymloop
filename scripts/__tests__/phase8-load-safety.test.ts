import { describe, expect, it } from 'vitest';

import {
  assertSafeLoadTarget,
  buildMorningCheckInWorkload,
  preflightLoadRun,
  summarizeRawResult,
} from '../phase8-load-safety.mjs';

const PRODUCTION_PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const NON_PRODUCTION_TARGET = {
  projectRef: 'phase8-load-sandbox',
  apiUrl: 'https://phase8-load-sandbox.example.test',
  supabaseUrl: 'https://phase8-load-sandbox.supabase.co',
  observedApiProjectRef: 'phase8-load-sandbox',
  observedSupabaseProjectRef: 'phase8-load-sandbox',
  confirmation: 'NON_PRODUCTION_LOAD_APPROVED',
  credentials: { kind: 'non-production', present: true, projectRef: 'phase8-load-sandbox' },
};

const makeGymFixtures = () => Array.from({ length: 100 }, (_, gymIndex) => ({
  gymId: `gym-${gymIndex}`,
  token: `token-${gymIndex}`,
  memberIds: Array.from({ length: 500 }, (_, memberIndex) => `member-${gymIndex}-${memberIndex}`),
  ownedMemberIds: Array.from({ length: 500 }, (_, memberIndex) => `member-${gymIndex}-${memberIndex}`),
}));
const FIXTURE_PATH = 'artifacts/phase8-load/fixtures.json';
const TENANT_ISOLATION = { denyCrossTenantRead: true, denyCrossTenantMutation: true };

describe('HARD-004 isolated load safety', () => {
  it('fails closed when project identity, API identity, credentials, or confirmation is incomplete', () => {
    expect(() => assertSafeLoadTarget({})).toThrow();
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, projectRef: '' })).toThrow();
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, apiUrl: '' })).toThrow();
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, credentials: undefined })).toThrow();
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, confirmation: '' })).toThrow();
  });

  it('rejects the configured production project and an API URL that resolves to it', () => {
    expect(() =>
      assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, projectRef: PRODUCTION_PROJECT_REF }),
    ).toThrow(/production/i);
    expect(() =>
      assertSafeLoadTarget({
        ...NON_PRODUCTION_TARGET,
        observedApiProjectRef: PRODUCTION_PROJECT_REF,
      }),
    ).toThrow(/production/i);
  });

  it('requires explicit non-production credentials and confirmation before allowing a run', () => {
    expect(assertSafeLoadTarget(NON_PRODUCTION_TARGET)).toMatchObject({
      projectRef: NON_PRODUCTION_TARGET.projectRef,
      nonProduction: true,
      apiUrl: NON_PRODUCTION_TARGET.apiUrl,
      supabaseUrl: NON_PRODUCTION_TARGET.supabaseUrl,
    });
    expect(() =>
      assertSafeLoadTarget({
        ...NON_PRODUCTION_TARGET,
        credentials: { kind: 'production', present: true },
      }),
    ).toThrow(/non-production/i);
  });

  it('requires configured and independently observed refs to match, with Supabase HTTPS hostname bound to that ref', () => {
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, projectRef: 'other-project' })).toThrow();
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, observedApiProjectRef: 'other-project' })).toThrow();
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, observedSupabaseProjectRef: 'other-project' })).toThrow();
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, supabaseUrl: 'http://phase8-load-sandbox.supabase.co' })).toThrow(/https/i);
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, supabaseUrl: 'https://other-project.supabase.co' })).toThrow();
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, apiUrl: 'https://user:pass@phase8-load-sandbox.example.test' })).toThrow(/origin|credential/i);
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, apiUrl: 'https://phase8-load-sandbox.example.test/api' })).toThrow(/origin|path/i);
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, supabaseUrl: 'https://phase8-load-sandbox.supabase.co?query=1' })).toThrow(/origin|query/i);
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, supabaseUrl: 'https://phase8-load-sandbox.supabase.co#fragment' })).toThrow(/origin|fragment/i);
  });

  it('encodes exactly 100 gyms, 500 members per gym, and the morning check-in spike', () => {
    expect(buildMorningCheckInWorkload({
      thresholds: { p95Ms: 750 },
      gymFixtures: makeGymFixtures(),
      tenantIsolation: TENANT_ISOLATION,
      fixturePath: FIXTURE_PATH,
    })).toMatchObject({
      gyms: 100,
      membersPerGym: 500,
      totalMembers: 50000,
      spike: expect.objectContaining({ name: expect.stringMatching(/morning/i) }),
    });
  });

  it('requires caller-supplied thresholds instead of inventing a latency budget', () => {
    expect(() => buildMorningCheckInWorkload()).toThrow(/threshold/i);
    expect(() => buildMorningCheckInWorkload({ thresholds: { p95Ms: 750 }, gymFixtures: makeGymFixtures(), tenantIsolation: TENANT_ISOLATION })).toThrow(/fixture/i);
    expect(buildMorningCheckInWorkload({ thresholds: { p95Ms: 750 }, gymFixtures: makeGymFixtures(), tenantIsolation: TENANT_ISOLATION, fixturePath: FIXTURE_PATH })).toMatchObject({
      thresholds: { p95Ms: 750 },
    });
  });

  it('requires tenant isolation, fixture path, and strict k6 fixture identity/URL inputs', () => {
    const fixtures = makeGymFixtures();
    expect(() => buildMorningCheckInWorkload({ thresholds: { p95Ms: 750 }, gymFixtures: fixtures, fixturePath: FIXTURE_PATH })).toThrow(/tenant/i);
    const blankGym = structuredClone(fixtures); blankGym[0].gymId = ' ';
    expect(() => buildMorningCheckInWorkload({ thresholds: { p95Ms: 750 }, gymFixtures: blankGym, tenantIsolation: TENANT_ISOLATION, fixturePath: FIXTURE_PATH })).toThrow(/gym/i);
    const blankToken = structuredClone(fixtures); blankToken[0].token = '';
    expect(() => buildMorningCheckInWorkload({ thresholds: { p95Ms: 750 }, gymFixtures: blankToken, tenantIsolation: TENANT_ISOLATION, fixturePath: FIXTURE_PATH })).toThrow(/token/i);
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, apiUrl: 'https://phase8-load-sandbox.example.test/' })).toThrow(/origin/i);
  });

  it('requires both cross-tenant read and mutation denial assertions', () => {
    const workload = buildMorningCheckInWorkload({
      thresholds: { p95Ms: 750 },
      gymFixtures: makeGymFixtures(),
      tenantIsolation: TENANT_ISOLATION,
      fixturePath: FIXTURE_PATH,
    });
    expect(workload.tenantIsolation).toEqual({
      denyCrossTenantRead: true,
      denyCrossTenantMutation: true,
    });
  });

  it('builds 100 distinct gym fixtures with 500 distinct owned members and rejects duplicate or cross-owned identities', () => {
    const gymFixtures = makeGymFixtures();
    const workload = buildMorningCheckInWorkload({
      thresholds: { p95Ms: 750 },
      gymFixtures,
      tenantIsolation: TENANT_ISOLATION,
      fixturePath: FIXTURE_PATH,
    });
    expect(workload.gymFixtures).toHaveLength(100);
    for (const gym of workload.gymFixtures) {
      expect(new Set(gym.memberIds).size).toBe(500);
      expect(gym.memberIds).toHaveLength(500);
      expect(gym.memberIds.every((memberId: string) => gym.ownedMemberIds.includes(memberId))).toBe(true);
    }
    const duplicateGymFixtures = structuredClone(gymFixtures); duplicateGymFixtures[1].gymId = duplicateGymFixtures[0].gymId;
    expect(() => buildMorningCheckInWorkload({ thresholds: { p95Ms: 750 }, gymFixtures: duplicateGymFixtures, tenantIsolation: TENANT_ISOLATION, fixturePath: FIXTURE_PATH })).toThrow(/duplicate/i);
    const duplicateTokenFixtures = structuredClone(gymFixtures); duplicateTokenFixtures[1].token = duplicateTokenFixtures[0].token;
    expect(() => buildMorningCheckInWorkload({ thresholds: { p95Ms: 750 }, gymFixtures: duplicateTokenFixtures, tenantIsolation: TENANT_ISOLATION, fixturePath: FIXTURE_PATH })).toThrow(/duplicate/i);
    const duplicateMemberFixtures = structuredClone(gymFixtures); duplicateMemberFixtures[1].memberIds[0] = duplicateMemberFixtures[0].memberIds[0];
    expect(() => buildMorningCheckInWorkload({ thresholds: { p95Ms: 750 }, gymFixtures: duplicateMemberFixtures, tenantIsolation: TENANT_ISOLATION, fixturePath: FIXTURE_PATH })).toThrow(/duplicate/i);
    const crossOwnedFixtures = structuredClone(gymFixtures); crossOwnedFixtures[1].ownedMemberIds[0] = crossOwnedFixtures[0].memberIds[0];
    expect(() => buildMorningCheckInWorkload({ thresholds: { p95Ms: 750 }, gymFixtures: crossOwnedFixtures, tenantIsolation: TENANT_ISOLATION, fixturePath: FIXTURE_PATH })).toThrow(/cross-owned|owned/i);
  });

  it('treats every 2xx mutation response, including 202 and 204, as a failure', () => {
    const workload = buildMorningCheckInWorkload({
      thresholds: { p95Ms: 750 },
      gymFixtures: makeGymFixtures(),
      tenantIsolation: TENANT_ISOLATION,
      fixturePath: FIXTURE_PATH,
    });
    expect(() => preflightLoadRun({ target: NON_PRODUCTION_TARGET, workload, rawResultPath: 'artifacts/phase8-load/raw.json', mutationStatuses: [200] })).toThrow(/2xx|mutation/i);
    expect(() => preflightLoadRun({ target: NON_PRODUCTION_TARGET, workload, rawResultPath: 'artifacts/phase8-load/raw.json', mutationStatuses: [202] })).toThrow(/2xx|mutation/i);
    expect(() => preflightLoadRun({ target: NON_PRODUCTION_TARGET, workload, rawResultPath: 'artifacts/phase8-load/raw.json', mutationStatuses: [204] })).toThrow(/2xx|mutation/i);
    expect(() => preflightLoadRun({ target: NON_PRODUCTION_TARGET, workload, rawResultPath: 'artifacts/phase8-load/raw.json', mutationStatuses: ['204'] })).toThrow();
    expect(() => preflightLoadRun({ target: NON_PRODUCTION_TARGET, workload, rawResultPath: 'artifacts/phase8-load/raw.json', mutationStatuses: [-1] })).toThrow();
  });

  it('returns a reviewable raw-result summary without treating a missing raw path as success', () => {
    expect(() => summarizeRawResult({})).toThrow(/raw/i);
    expect(summarizeRawResult({ rawResultPath: 'artifacts/phase8-load/raw.json', status: 'blocked' })).toMatchObject({
      rawResultPath: 'artifacts/phase8-load/raw.json',
      status: 'blocked',
    });
    expect(summarizeRawResult({
      rawResultPath: 'artifacts/phase8-load/raw.json',
      status: 'passed',
    })).not.toMatchObject({ status: 'passed' });
    expect(summarizeRawResult({
      status: 'passed',
      rawResultPath: 'artifacts/phase8-load/raw.json',
      target: NON_PRODUCTION_TARGET,
      thresholds: { p95Ms: 750 },
      fixturePath: FIXTURE_PATH,
      measured: { p95Ms: 700, completedCheckIns: 50000, tenantIsolation: TENANT_ISOLATION },
    })).toMatchObject({ status: 'passed', completedCheckIns: 50000 });
    expect(() => summarizeRawResult({ status: 'passed', rawResultPath: 'artifacts/phase8-load/raw.json', measured: { p95Ms: -1, completedCheckIns: 50000, tenantIsolation: TENANT_ISOLATION } })).toThrow();
    expect(() => summarizeRawResult({ status: 'passed', rawResultPath: 'artifacts/phase8-load/raw.json', measured: { p95Ms: Number.NaN, completedCheckIns: 50000, tenantIsolation: TENANT_ISOLATION } })).toThrow();
  });
});
