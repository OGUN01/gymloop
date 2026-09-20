import { describe, expect, it, vi } from 'vitest';

const PRODUCTION_PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const PRODUCTION_URL = 'https://gymloop.example.com';
const LOAD_ARTIFACT = 'artifacts/phase8/load-summary.json';
const P95_THRESHOLD_MS = 850;
const EXPECTED_GYMS = 100;
const EXPECTED_MEMBERS_PER_GYM = 500;
const SOURCE_TENANT = 'tenant-a';
const TARGET_TENANT = 'tenant-b';

type TargetIdentity = {
  apiUrl: string;
  environment: { kind: 'non-production' };
  projectRef: string;
};

type LoadSafetyHarness = {
  run: (input: { artifactPath: string; p95ThresholdMs?: number }) => Promise<{ artifactPath: string; summary: unknown }>;
};

type LoadSafetyModule = {
  createLoadSafetyHarness: (adapters: {
    inspectTarget: () => Promise<unknown>;
    runLoad: (workload: unknown) => Promise<unknown>;
    verifyTenantIsolation: (tenants: { sourceTenantId: string; targetTenantId: string }) => Promise<unknown>;
    writeSummary: (artifactPath: string, summary: unknown) => Promise<void>;
  }) => LoadSafetyHarness;
};

const safeTarget = (): TargetIdentity => ({
  apiUrl: 'https://staging.gymloop.example.com',
  environment: { kind: 'non-production' },
  projectRef: 'staging-project-ref',
});

const createHarness = async (target: unknown = safeTarget()) => {
  const load = vi.fn(async () => ({ p95Ms: P95_THRESHOLD_MS - 1 }));
  const isolation = vi.fn(async () => ({ readDenied: true, mutationDenied: true }));
  const write = vi.fn(async () => undefined);
  const { createLoadSafetyHarness } = await import('../../scripts/phase8-load-safety') as LoadSafetyModule;
  const harness = createLoadSafetyHarness({
    inspectTarget: async () => target,
    runLoad: load,
    verifyTenantIsolation: isolation,
    writeSummary: write,
  });

  return { harness, isolation, load, write };
};

describe('independent HARD-004 isolated load safety holdout', () => {
  it('fails closed before any load work for the production project or production URL', async () => {
    const productionProject = await createHarness({ ...safeTarget(), projectRef: PRODUCTION_PROJECT_REF });
    await expect(productionProject.harness.run({ artifactPath: LOAD_ARTIFACT, p95ThresholdMs: P95_THRESHOLD_MS })).rejects.toThrow();
    expect(productionProject.load).not.toHaveBeenCalled();
    expect(productionProject.isolation).not.toHaveBeenCalled();
    expect(productionProject.write).not.toHaveBeenCalled();

    const productionUrl = await createHarness({ ...safeTarget(), apiUrl: PRODUCTION_URL });
    await expect(productionUrl.harness.run({ artifactPath: LOAD_ARTIFACT, p95ThresholdMs: P95_THRESHOLD_MS })).rejects.toThrow();
    expect(productionUrl.load).not.toHaveBeenCalled();
  });

  it('accepts only a positive structured non-production identity, never truthy flags or missing identity', async () => {
    for (const target of [
      { ...safeTarget(), environment: { kind: 'production' } },
      { ...safeTarget(), environment: 'non-production' },
      { ...safeTarget(), environment: { kind: 'false' } },
      { ...safeTarget(), environment: { kind: false } },
      { ...safeTarget(), environment: { kind: 'non-production', verified: 'true' } },
      { apiUrl: safeTarget().apiUrl, projectRef: safeTarget().projectRef },
    ]) {
      const candidate = await createHarness(target);
      await expect(candidate.harness.run({ artifactPath: LOAD_ARTIFACT, p95ThresholdMs: P95_THRESHOLD_MS })).rejects.toThrow();
      expect(candidate.load).not.toHaveBeenCalled();
      expect(candidate.write).not.toHaveBeenCalled();
    }
  });

  it('requires an explicit finite p95 target instead of silently inventing one', async () => {
    const { harness, load, write } = await createHarness();
    await expect(harness.run({ artifactPath: LOAD_ARTIFACT })).rejects.toThrow();
    expect(load).not.toHaveBeenCalled();
    expect(write).not.toHaveBeenCalled();
  });

  it('executes exactly the required morning spike and verifies both cross-tenant denial paths', async () => {
    const { harness, isolation, load, write } = await createHarness();
    const result = await harness.run({ artifactPath: LOAD_ARTIFACT, p95ThresholdMs: P95_THRESHOLD_MS });

    expect(load).toHaveBeenCalledWith(expect.objectContaining({
      gyms: EXPECTED_GYMS,
      membersPerGym: EXPECTED_MEMBERS_PER_GYM,
      phase: 'morning-check-in-spike',
    }));
    expect(isolation).toHaveBeenCalledWith({ sourceTenantId: SOURCE_TENANT, targetTenantId: TARGET_TENANT });
    expect(write).toHaveBeenCalledWith(LOAD_ARTIFACT, expect.any(Object));
    expect(result.artifactPath).toBe(LOAD_ARTIFACT);
  });

  it('does not report success when a cross-tenant read or mutation is allowed', async () => {
    for (const isolationResult of [
      { readDenied: false, mutationDenied: true },
      { readDenied: true, mutationDenied: false },
    ]) {
      const { harness, write } = await createHarness(safeTarget());
      const { createLoadSafetyHarness } = await import('../../scripts/phase8-load-safety') as LoadSafetyModule;
      const unsafeHarness = createLoadSafetyHarness({
        inspectTarget: async () => safeTarget(),
        runLoad: async () => ({ p95Ms: P95_THRESHOLD_MS - 1 }),
        verifyTenantIsolation: async () => isolationResult,
        writeSummary: write,
      });

      await expect(unsafeHarness.run({ artifactPath: LOAD_ARTIFACT, p95ThresholdMs: P95_THRESHOLD_MS })).rejects.toThrow();
      expect(write).not.toHaveBeenCalled();
      void harness;
    }
  });
});
