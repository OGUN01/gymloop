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
  configuredProjectRef: 'phase8-load-sandbox',
  apiUrl: 'https://phase8-load-sandbox.example.test',
  apiProjectRef: 'phase8-load-sandbox',
  supabaseUrl: 'https://phase8-load-sandbox.supabase.co',
  supabaseProjectRef: 'phase8-load-sandbox',
  observedProjectRef: 'phase8-load-sandbox',
  observedApiProjectRef: 'phase8-load-sandbox',
  observedSupabaseProjectRef: 'phase8-load-sandbox',
  confirmation: 'NON_PRODUCTION_LOAD_APPROVED',
  credentials: { kind: 'non-production', present: true, projectRef: 'phase8-load-sandbox' },
};

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
        resolvedProjectRef: PRODUCTION_PROJECT_REF,
      }),
    ).toThrow(/production/i);
  });

  it('requires explicit non-production credentials and confirmation before allowing a run', () => {
    expect(assertSafeLoadTarget(NON_PRODUCTION_TARGET)).toMatchObject({
      projectRef: NON_PRODUCTION_TARGET.projectRef,
      nonProduction: true,
    });
    expect(() =>
      assertSafeLoadTarget({
        ...NON_PRODUCTION_TARGET,
        credentials: { kind: 'production', present: true },
      }),
    ).toThrow(/non-production/i);
  });

  it('requires configured and independently observed refs to match, with Supabase HTTPS hostname bound to that ref', () => {
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, configuredProjectRef: 'other-project', observedProjectRef: 'other-project' })).toThrow();
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, apiProjectRef: 'other-project', observedApiProjectRef: 'other-project' })).toThrow();
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, supabaseProjectRef: 'other-project', observedSupabaseProjectRef: 'other-project' })).toThrow();
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, supabaseUrl: 'http://phase8-load-sandbox.supabase.co' })).toThrow(/https/i);
    expect(() => assertSafeLoadTarget({ ...NON_PRODUCTION_TARGET, supabaseUrl: 'https://other-project.supabase.co' })).toThrow();
  });

  it('encodes exactly 100 gyms, 500 members per gym, and the morning check-in spike', () => {
    expect(buildMorningCheckInWorkload({
      thresholds: { p95Ms: 750 },
      tenantIsolation: { denyCrossTenantRead: true, denyCrossTenantMutation: true },
    })).toMatchObject({
      gyms: 100,
      membersPerGym: 500,
      totalMembers: 50000,
      spike: expect.objectContaining({ name: expect.stringMatching(/morning/i) }),
    });
  });

  it('requires caller-supplied thresholds instead of inventing a latency budget', () => {
    expect(() => buildMorningCheckInWorkload()).toThrow(/threshold/i);
    expect(buildMorningCheckInWorkload({ thresholds: { p95Ms: 750 } })).toMatchObject({
      thresholds: { p95Ms: 750 },
    });
  });

  it('requires both cross-tenant read and mutation denial assertions', () => {
    const workload = buildMorningCheckInWorkload({
      thresholds: { p95Ms: 750 },
      tenantIsolation: { denyCrossTenantRead: true, denyCrossTenantMutation: true },
    });
    expect(workload.tenantIsolation).toEqual({
      denyCrossTenantRead: true,
      denyCrossTenantMutation: true,
    });
  });

  it('builds 100 distinct gym fixtures with 500 distinct owned members and rejects duplicate or cross-owned identities', () => {
    const workload = buildMorningCheckInWorkload({
      thresholds: { p95Ms: 750 },
      tenantIsolation: { denyCrossTenantRead: true, denyCrossTenantMutation: true },
    });
    expect(workload.gymFixtures).toHaveLength(100);
    for (const gym of workload.gymFixtures) {
      expect(new Set(gym.memberIds).size).toBe(500);
      expect(gym.memberIds).toHaveLength(500);
      expect(gym.memberIds.every((memberId: string) => gym.ownedMemberIds.includes(memberId))).toBe(true);
    }
    expect(() => preflightLoadRun({ target: NON_PRODUCTION_TARGET, workload, duplicateGymIds: ['gym-1'] })).toThrow(/duplicate/i);
    expect(() => preflightLoadRun({ target: NON_PRODUCTION_TARGET, workload, duplicateTokenIds: ['token-1'] })).toThrow(/duplicate/i);
    expect(() => preflightLoadRun({ target: NON_PRODUCTION_TARGET, workload, duplicateMemberIds: ['member-1'] })).toThrow(/duplicate/i);
    expect(() => preflightLoadRun({ target: NON_PRODUCTION_TARGET, workload, crossOwnedMemberIds: ['member-1'] })).toThrow(/cross-owned/i);
  });

  it('treats every 2xx mutation response, including 202 and 204, as a failure', () => {
    const workload = buildMorningCheckInWorkload({
      thresholds: { p95Ms: 750 },
      tenantIsolation: { denyCrossTenantRead: true, denyCrossTenantMutation: true },
    });
    expect(() => preflightLoadRun({ target: NON_PRODUCTION_TARGET, workload, thresholds: { p95Ms: 750 }, rawResultPath: 'artifacts/phase8-load/raw.json', mutationResponses: [{ status: 202 }] })).toThrow(/2xx|mutation/i);
    expect(() => preflightLoadRun({ target: NON_PRODUCTION_TARGET, workload, thresholds: { p95Ms: 750 }, rawResultPath: 'artifacts/phase8-load/raw.json', mutationResponses: [{ status: 204 }] })).toThrow(/2xx|mutation/i);
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
      p95Ms: 700,
      thresholds: { p95Ms: 750 },
      completedCheckIns: 50000,
      tenantIsolation: { denyCrossTenantRead: true, denyCrossTenantMutation: true },
      measured: true,
    })).toMatchObject({ status: 'passed', completedCheckIns: 50000 });
  });
});
