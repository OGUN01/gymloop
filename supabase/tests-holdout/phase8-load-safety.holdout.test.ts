import { describe, expect, it } from 'vitest';

const PRODUCTION_PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const PRODUCTION_URL = 'https://gymloop.example.com';
const STAGING_URL = 'https://staging.gymloop.example.com';
const RAW_RESULT_PATH = 'artifacts/phase8/load-raw.json';
const P95_THRESHOLD_MS = 850;
const EXPECTED_GYMS = 100;
const EXPECTED_MEMBERS_PER_GYM = 500;

type LoadSafetyModule = {
  assertSafeLoadTarget: (target: unknown) => unknown;
  buildMorningCheckInWorkload: () => unknown;
  preflightLoadRun: (input: unknown) => unknown;
  summarizeRawResult: (input: unknown) => unknown;
};

const safeTarget = () => ({
  configuredApiUrl: STAGING_URL,
  environment: { confirmation: 'non-production', kind: 'non-production' },
  projectRef: 'staging-project-ref',
  resolvedApiUrl: STAGING_URL,
});

const loadModule = async () => await import('../../scripts/phase8-load-safety') as LoadSafetyModule;

describe('independent HARD-004 isolated load safety holdout', () => {
  it('fails closed for the production project reference and direct or resolved production API URLs', async () => {
    const { assertSafeLoadTarget } = await loadModule();

    for (const unsafeTarget of [
      { ...safeTarget(), projectRef: PRODUCTION_PROJECT_REF },
      { ...safeTarget(), configuredApiUrl: PRODUCTION_URL },
      { ...safeTarget(), resolvedApiUrl: PRODUCTION_URL },
    ]) {
      expect(() => assertSafeLoadTarget(unsafeTarget)).toThrow();
    }
  });

  it('requires structured positive non-production confirmation and rejects ambiguous truthy forms', async () => {
    const { assertSafeLoadTarget } = await loadModule();

    expect(() => assertSafeLoadTarget(safeTarget())).not.toThrow();
    for (const target of [
      { ...safeTarget(), environment: 'non-production' },
      { ...safeTarget(), environment: { confirmation: 'true', kind: 'non-production' } },
      { ...safeTarget(), environment: { confirmation: true, kind: 'non-production' } },
      { ...safeTarget(), environment: { confirmation: 'non-production', kind: 'production' } },
      { ...safeTarget(), environment: { confirmation: 'non-production', kind: false } },
      { ...safeTarget(), environment: { kind: 'non-production' } },
      { configuredApiUrl: STAGING_URL, projectRef: 'staging-project-ref', resolvedApiUrl: STAGING_URL },
    ]) {
      expect(() => assertSafeLoadTarget(target)).toThrow();
    }
  });

  it('requires a finite positive explicit p95 threshold at executable preflight', async () => {
    const { preflightLoadRun } = await loadModule();

    for (const p95ThresholdMs of [undefined, 0, -1, Number.NaN, Number.POSITIVE_INFINITY, '850']) {
      expect(() => preflightLoadRun({ p95ThresholdMs, target: safeTarget() })).toThrow();
    }
    expect(() => preflightLoadRun({ p95ThresholdMs: P95_THRESHOLD_MS, target: safeTarget() })).not.toThrow();
  });

  it('builds the exact 100-gym by 500-member morning check-in workload', async () => {
    const { buildMorningCheckInWorkload } = await loadModule();
    expect(buildMorningCheckInWorkload()).toEqual(expect.objectContaining({
      gyms: EXPECTED_GYMS,
      membersPerGym: EXPECTED_MEMBERS_PER_GYM,
      phase: 'morning-check-in-spike',
    }));
  });

  it('cannot report a passing raw result unless both cross-tenant read and mutation are denied', async () => {
    const { summarizeRawResult } = await loadModule();
    const baseResult = {
      p95Ms: P95_THRESHOLD_MS - 1,
      p95ThresholdMs: P95_THRESHOLD_MS,
      rawResultPath: RAW_RESULT_PATH,
    };

    for (const tenantIsolation of [
      { mutationDenied: false, readDenied: true },
      { mutationDenied: true, readDenied: false },
      { mutationDenied: false, readDenied: false },
    ]) {
      const summary = summarizeRawResult({ ...baseResult, tenantIsolation }) as { status?: string };
      expect(summary.status).not.toBe('pass');
    }

    const passing = summarizeRawResult({
      ...baseResult,
      tenantIsolation: { mutationDenied: true, readDenied: true },
    }) as { rawResultPath?: string; status?: string };
    expect(passing.status).toBe('pass');
    expect(passing.rawResultPath).toBe(RAW_RESULT_PATH);
  });
});
