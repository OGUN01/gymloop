import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';

import { assertSafeLoadTarget } from '../phase8-load-safety.mjs';
import {
  assertSafePrelaunchFixture,
  assertSafePrelaunchQuota,
  assertSafePrelaunchTarget,
  summarizePrelaunchResult,
} from '../phase8-prelaunch-load-safety.mjs';

const PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const QUOTA_BYTES = 500_000_000;
const ABORT_BYTES = 400_000_000;
const TARGET = {
  mode: 'prelaunch-shared',
  projectRef: PROJECT_REF,
  observedApiProjectRef: PROJECT_REF,
  observedSupabaseProjectRef: PROJECT_REF,
  apiUrl: 'https://gymloop.example.test',
  supabaseUrl: `https://${PROJECT_REF}.supabase.co`,
  confirmation: 'PRELAUNCH_SHARED_LOAD_APPROVED',
  credentials: { kind: 'prelaunch-shared', present: true, projectRef: PROJECT_REF },
  noLiveCustomers: true,
};
const gymFixtures = Array.from({ length: 100 }, (_, gymIndex) => ({
  gymId: `synthetic-gym-${gymIndex}`,
  token: `private-token-${gymIndex}`,
  memberIds: Array.from({ length: 500 }, (_, memberIndex) => `synthetic-member-${gymIndex}-${memberIndex}`),
  ownedMemberIds: Array.from({ length: 500 }, (_, memberIndex) => `synthetic-member-${gymIndex}-${memberIndex}`),
}));
const FIXTURE = {
  marker: `PHASE8-LOAD-${randomUUID()}`,
  gymFixtures,
  fixturePath: 'artifacts/phase8-load/private-fixture.json',
  baselineManifestPath: 'artifacts/phase8-load/baseline.json',
  cleanupManifestPath: 'artifacts/phase8-load/cleanup.json',
};
const quota = (overrides: Record<string, unknown> = {}) => ({
  observedAt: new Date().toISOString(),
  databaseBytes: 34_000_000,
  providerQuotaBytes: QUOTA_BYTES,
  maxDatabaseBytes: ABORT_BYTES,
  ...overrides,
});
const passingInput = () => ({
  status: 'passed',
  target: TARGET,
  quota: quota(),
  fixture: FIXTURE,
  rawResultPath: 'artifacts/phase8-load/raw.json',
  thresholds: { p95Ms: 750 },
  measured: {
    p95Ms: 700,
    completedCheckIns: 50_000,
    crossTenantReadDenied: true,
    crossTenantMutationStatus: 403,
  },
  monitor: { completed: true, maxObservedDatabaseBytes: 399_999_999, maxGapSeconds: 60 },
  cleanup: {
    completed: true,
    preexistingUnchanged: true,
    syntheticRemainderCount: 0,
    authRemainderCount: 0,
  },
});
const cannotPass = (input: unknown) => {
  let result: unknown;
  try {
    result = summarizePrelaunchResult(input);
  } catch {
    return;
  }
  expect(result).not.toMatchObject({ status: 'passed' });
};

describe('HARD-004 prelaunch-shared Cloud target', () => {
  it('accepts only the explicitly approved linked project and returns no credential material', () => {
    expect(assertSafePrelaunchTarget(TARGET)).toEqual({
      mode: 'prelaunch-shared',
      projectRef: PROJECT_REF,
      apiUrl: TARGET.apiUrl,
      supabaseUrl: TARGET.supabaseUrl,
    });
    expect(assertSafePrelaunchTarget({ ...TARGET, apiUrl: `${TARGET.apiUrl}/` })).toMatchObject({
      apiUrl: TARGET.apiUrl,
    });

    for (const target of [
      { ...TARGET, mode: 'isolated' },
      { ...TARGET, projectRef: 'some-other-project' },
      { ...TARGET, observedApiProjectRef: 'some-other-project' },
      { ...TARGET, observedSupabaseProjectRef: 'some-other-project' },
      { ...TARGET, supabaseUrl: 'https://some-other-project.supabase.co' },
      { ...TARGET, confirmation: 'NON_PRODUCTION_LOAD_APPROVED' },
      { ...TARGET, noLiveCustomers: 'true' },
      { ...TARGET, noLiveCustomers: false },
      { ...TARGET, credentials: { ...TARGET.credentials, kind: 'non-production' } },
      { ...TARGET, credentials: { ...TARGET.credentials, present: 'true' } },
      { ...TARGET, credentials: { ...TARGET.credentials, projectRef: 'some-other-project' } },
      { ...TARGET, credentials: { ...TARGET.credentials, serviceRoleKey: 'private-key' } },
      { ...TARGET, unexpected: true },
    ]) {
      expect(() => assertSafePrelaunchTarget(target)).toThrow();
    }
  });

  it('rejects URL paths, credentials, queries, fragments, wrong schemes and alternate Supabase origins', () => {
    for (const apiUrl of [
      'http://gymloop.example.test',
      'https://name:password@gymloop.example.test',
      'https://gymloop.example.test/api',
      'https://gymloop.example.test?key=private',
      'https://gymloop.example.test#fragment',
    ]) {
      expect(() => assertSafePrelaunchTarget({ ...TARGET, apiUrl })).toThrow();
    }
    for (const supabaseUrl of [
      `http://${PROJECT_REF}.supabase.co`,
      `https://${PROJECT_REF}.supabase.co/rest/v1`,
      `https://${PROJECT_REF}.supabase.co?query=1`,
      `https://${PROJECT_REF}.supabase.co#fragment`,
      `https://name:password@${PROJECT_REF}.supabase.co`,
      `https://${PROJECT_REF}.supabase.co.evil.test`,
    ]) {
      expect(() => assertSafePrelaunchTarget({ ...TARGET, supabaseUrl })).toThrow();
    }
  });

  it('leaves the isolated route unable to accept this production project', () => {
    expect(() => assertSafeLoadTarget({
      ...TARGET,
      confirmation: 'NON_PRODUCTION_LOAD_APPROVED',
      credentials: { kind: 'non-production', present: true, projectRef: PROJECT_REF },
    })).toThrow();
  });
});

describe('HARD-004 prelaunch-shared size observer', () => {
  it('accepts a current CLI size below the abort ceiling', () => {
    expect(assertSafePrelaunchQuota(quota())).toMatchObject({
      databaseBytes: 34_000_000,
      providerQuotaBytes: QUOTA_BYTES,
      maxDatabaseBytes: ABORT_BYTES,
    });
    expect(assertSafePrelaunchQuota(quota({ databaseBytes: ABORT_BYTES - 1 }))).toMatchObject({
      databaseBytes: ABORT_BYTES - 1,
    });
  });

  it('fails closed at the ceiling, on missing collection, or on a changed provider quota', () => {
    for (const snapshot of [
      quota({ databaseBytes: ABORT_BYTES }),
      quota({ databaseBytes: QUOTA_BYTES }),
      quota({ databaseBytes: -1 }),
      quota({ databaseBytes: 12.5 }),
      quota({ databaseBytes: Number.NaN }),
      quota({ databaseBytes: undefined }),
      quota({ providerQuotaBytes: QUOTA_BYTES + 1 }),
      quota({ providerQuotaBytes: undefined }),
      quota({ maxDatabaseBytes: ABORT_BYTES + 1 }),
      quota({ maxDatabaseBytes: undefined }),
      quota({ secret: 'unapproved-extra-field' }),
    ]) {
      expect(() => assertSafePrelaunchQuota(snapshot)).toThrow();
    }
  });

  it('requires a canonical, current UTC observation', () => {
    for (const observedAt of [
      new Date(Date.now() - 16 * 60_000).toISOString(),
      new Date(Date.now() + 60_000).toISOString(),
      '2026-09-23T12:00:00+05:30',
      'yesterday',
      '',
      undefined,
    ]) {
      expect(() => assertSafePrelaunchQuota(quota({ observedAt }))).toThrow();
    }
  });
});

describe('HARD-004 prelaunch-shared synthetic fixture', () => {
  it('validates all 100 distinct gym sessions and 50,000 owned member identities without returning secrets', () => {
    const checked = assertSafePrelaunchFixture(FIXTURE);
    expect(checked).toMatchObject({
      marker: FIXTURE.marker,
      fixturePath: FIXTURE.fixturePath,
      baselineManifestPath: FIXTURE.baselineManifestPath,
      cleanupManifestPath: FIXTURE.cleanupManifestPath,
    });
    expect(Object.values(checked)).toEqual(expect.arrayContaining([100, 500, 50_000]));
    expect(JSON.stringify(checked)).not.toMatch(/private-token-0|synthetic-member-0-0/);
  });

  it('rejects a missing, nonlocal, or aliased recovery artifact and an invalid marker', () => {
    for (const fixture of [
      { ...FIXTURE, marker: 'PHASE8-LOAD-reused' },
      { ...FIXTURE, marker: 'other-run' },
      { ...FIXTURE, fixturePath: '' },
      { ...FIXTURE, fixturePath: 'https://example.test/fixture.json' },
      { ...FIXTURE, baselineManifestPath: '' },
      { ...FIXTURE, cleanupManifestPath: '' },
      { ...FIXTURE, cleanupManifestPath: FIXTURE.fixturePath },
      { ...FIXTURE, cleanupManifestPath: FIXTURE.baselineManifestPath },
      { ...FIXTURE, baselineManifestPath: FIXTURE.fixturePath },
      { ...FIXTURE, unapprovedExtraField: true },
    ]) {
      expect(() => assertSafePrelaunchFixture(fixture)).toThrow();
    }
  });

  it('rejects duplicate sessions, duplicate members, and cross-owned members from fixture contents', () => {
    const changed = (gymIndex: number, patch: Record<string, unknown>) => ({
      ...FIXTURE,
      gymFixtures: gymFixtures.map((gym, index) => index === gymIndex ? { ...gym, ...patch } : gym),
    });
    for (const fixture of [
      { ...FIXTURE, gymFixtures: gymFixtures.slice(1) },
      changed(1, { gymId: gymFixtures[0].gymId }),
      changed(1, { token: gymFixtures[0].token }),
      changed(1, { memberIds: [gymFixtures[0].memberIds[0], ...gymFixtures[1].memberIds.slice(1)] }),
      changed(1, { ownedMemberIds: [gymFixtures[0].memberIds[0], ...gymFixtures[1].ownedMemberIds.slice(1)] }),
      changed(1, { memberIds: [gymFixtures[1].memberIds[0], ...gymFixtures[1].memberIds.slice(0, -1)] }),
    ]) {
      expect(() => assertSafePrelaunchFixture(fixture)).toThrow();
    }
  });
});

describe('HARD-004 prelaunch-shared pass reconciliation', () => {
  it('can pass only with raw result, exact workload, both denials, live observer and exact cleanup', () => {
    const summary = summarizePrelaunchResult(passingInput());
    expect(summary).toMatchObject({ status: 'passed' });
    const printed = JSON.stringify(summary);
    expect(printed).toContain('artifacts/phase8-load/raw.json');
    expect(printed).not.toMatch(/private-token-0|synthetic-member-0-0|serviceRoleKey/);
  });

  it('cannot infer a pass from a caller status or a green k6 result without postflight', () => {
    cannotPass({ status: 'passed' });
    cannotPass({ ...passingInput(), cleanup: undefined });
    cannotPass({ ...passingInput(), monitor: undefined });
    cannotPass({ ...passingInput(), rawResultPath: '' });
    cannotPass({ ...passingInput(), target: undefined });
    cannotPass({ ...passingInput(), fixture: undefined });
    cannotPass({ ...passingInput(), quota: undefined });
    cannotPass({ ...passingInput(), unapprovedExtraField: true });
  });

  it('rejects inaccurate check-in totals, p95 failure, false read denial and every 2xx mutation', () => {
    const valid = passingInput();
    for (const measured of [
      { ...valid.measured, completedCheckIns: 49_999 },
      { ...valid.measured, completedCheckIns: 50_001 },
      { ...valid.measured, p95Ms: 751 },
      { ...valid.measured, p95Ms: Number.NaN },
      { ...valid.measured, p95Ms: Number.POSITIVE_INFINITY },
      { ...valid.measured, crossTenantReadDenied: false },
      { ...valid.measured, crossTenantMutationStatus: -1 },
      { ...valid.measured, crossTenantMutationStatus: '403' },
      ...[200, 202, 204, 299].map((crossTenantMutationStatus) => ({
        ...valid.measured,
        crossTenantMutationStatus,
      })),
    ]) {
      cannotPass({ ...valid, measured });
    }
    cannotPass({ ...valid, thresholds: { p95Ms: 0 } });
    cannotPass({ ...valid, thresholds: { p95Ms: Number.POSITIVE_INFINITY } });
  });

  it('blocks if the observer stops, exceeds the ceiling or has a gap over sixty seconds', () => {
    const valid = passingInput();
    for (const monitor of [
      { ...valid.monitor, completed: false },
      { ...valid.monitor, maxObservedDatabaseBytes: ABORT_BYTES },
      { ...valid.monitor, maxGapSeconds: 61 },
    ]) {
      cannotPass({ ...valid, monitor });
    }
  });

  it('blocks if cleanup is incomplete, pre-existing records changed, or synthetic DB/Auth identities remain', () => {
    const valid = passingInput();
    for (const cleanup of [
      { ...valid.cleanup, completed: false },
      { ...valid.cleanup, preexistingUnchanged: false },
      { ...valid.cleanup, syntheticRemainderCount: 1 },
      { ...valid.cleanup, authRemainderCount: 1 },
    ]) {
      cannotPass({ ...valid, cleanup });
    }
  });
});
