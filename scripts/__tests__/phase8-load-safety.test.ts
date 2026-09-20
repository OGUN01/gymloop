import { describe, expect, it } from 'vitest';

import {
  assertSafeLoadTarget,
  buildMorningCheckInWorkload,
  summarizeRawResult,
} from '../phase8-load-safety.mjs';

const PRODUCTION_PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const NON_PRODUCTION_TARGET = {
  projectRef: 'phase8-load-sandbox',
  apiUrl: 'https://phase8-load-sandbox.example.test',
  confirmation: 'NON_PRODUCTION_LOAD_APPROVED',
  credentials: { kind: 'non-production', present: true },
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

  it('returns a reviewable raw-result summary without treating a missing raw path as success', () => {
    expect(() => summarizeRawResult({})).toThrow(/raw/i);
    expect(summarizeRawResult({ rawResultPath: 'artifacts/phase8-load/raw.json', status: 'blocked' })).toMatchObject({
      rawResultPath: 'artifacts/phase8-load/raw.json',
      status: 'blocked',
    });
  });
});
