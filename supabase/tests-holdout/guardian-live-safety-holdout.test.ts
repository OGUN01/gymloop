import { expect, it, vi } from 'vitest';
import { validateManifest, runGuardianConcurrency } from './guardian-live-concurrency.mjs';
const ids = ['000001', '000002', '000003', '000004', '000005', '000006'].map(suffix => `69910000-0000-4000-8000-000000${suffix}`);
const manifest = () => ({ projectRef: 'pecxrpskmfeuyzngvewq', marker: 'GRD-HOLDOUT-69910000-0000-4000-8000-000000000001', syntheticOnly: true, tenantId: ids[0], memberIds: ids.slice(3), ownerUserId: ids[1], guardianUserId: ids[2], verifiedGoogleGuardian: true, initialAttestationNull: true, cleanupExactIds: ids });
it('accepts only the exact six-ID bounded synthetic manifest', () => expect(validateManifest(manifest())).toEqual(manifest()));
it.each([
  { projectRef: 'other-project' }, { syntheticOnly: false }, { verifiedGoogleGuardian: false },
  { initialAttestationNull: false }, { tenantId: 'real-demo-tenant' }, { cleanupExactIds: ['all-members'] },
  { memberIds: ids }, { extra: 'broad cleanup' },
])('refuses unsafe fixture %j before race commands', async delta => {
  const post = vi.fn();
  await expect(runGuardianConcurrency({ open: async () => ({ ...manifest(), ...delta }), post })).rejects.toThrow();
  expect(post).not.toHaveBeenCalled();
});
it('rejects a Promise.all result without measured overlapping sessions and cleans the exact fixture', async () => {
  const cleanup = vi.fn(async () => ({ exactFixtureGone: true, outsideFixtureUnchanged: true, recoveryManifestSaved: true }));
  await expect(runGuardianConcurrency({ open: async () => manifest(), snapshot: async () => ({ attestedAt: null, attestationAuditCount: 0 }), race: async () => ({ overlapObserved: false, results: [] }), cleanup })).rejects.toThrow(/independent sessions/);
  expect(cleanup).toHaveBeenCalledWith(manifest());
});
