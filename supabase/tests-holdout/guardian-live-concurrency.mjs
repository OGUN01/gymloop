/** Post-CI opt-in harness. No fixture creation, DB call or cleanup on import.
 * CLI: node supabase/tests-holdout/guardian-live-concurrency.mjs <private-adapter.mjs>
 * Adapter is operator-reviewed test-only ordinary-command setup/cleanup, never a
 * migration or production API. Credentials stay inside adapter and never print.
 * open() returns exact synthetic manifest, snapshot(), post(actor,path,body),
 * race(lockTarget, operations) and cleanup(manifest). race must hold the matching
 * row/advisory lock on a separate connection, launch independent verified sessions,
 * observe both contenders blocked, then release. It returns {overlapObserved,
 * results}. A Promise.all alone is NOT concurrency proof. snapshot reads committed
 * facts using approved ordinary CLI commands, not Supabase MCP.
 */
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const shape = {
  projectRef: 'pecxrpskmfeuyzngvewq', marker: /^GRD-HOLDOUT-[0-9a-f-]{36}$/,
  uuid: /^6991[0-9a-f]{4}-[0-9a-f]{4}-4[0-9a-f]{3}-8[0-9a-f]{3}-[0-9a-f]{12}$/,
  exact: ['projectRef', 'marker', 'syntheticOnly', 'tenantId', 'memberIds', 'ownerUserId', 'guardianUserId', 'verifiedGoogleGuardian', 'initialAttestationNull', 'cleanupExactIds'],
};
export function validateManifest(value) {
  assert(value && typeof value === 'object', 'synthetic manifest required');
  assert.deepEqual(Object.keys(value).sort(), [...shape.exact].sort(), 'manifest fields must be exact');
  assert.equal(value.projectRef, shape.projectRef, 'wrong Cloud project');
  assert.match(value.marker, shape.marker, 'fresh synthetic run marker required');
  assert.equal(value.syntheticOnly, true); assert.equal(value.initialAttestationNull, true);
  assert.equal(value.verifiedGoogleGuardian, true, 'genuine verified Google identity required; JWT invention is not live proof');
  assert(Array.isArray(value.memberIds) && value.memberIds.length === 3, 'exactly three synthetic members required');
  const ids = [value.tenantId, value.ownerUserId, value.guardianUserId, ...value.memberIds];
  assert.equal(new Set(ids).size, ids.length, 'all fixture IDs must be distinct');
  for (const id of ids) assert.match(id, shape.uuid, 'fixture ID outside exact synthetic namespace');
  assert.deepEqual([...value.cleanupExactIds].sort(), [...ids].sort(), 'cleanup must name only the exact fixture IDs');
  return value;
}
export async function runGuardianConcurrency(adapter) {
  const fixture = validateManifest(await adapter.open());
  // Adapter contract: before each command ensure verified actor claim tenant and
  // member ownership match fixture; never accept caller-controlled tenant/actor.
  const [minor, siblingA, siblingB] = fixture.memberIds;
  let finished = false;
  try {
    const initial = await adapter.snapshot(fixture);
    assert.equal(initial.attestedAt, null); assert.equal(initial.attestationAuditCount, 0);
    const attestation = await adapter.race({ kind: 'settings-row', id: fixture.tenantId }, [
      () => adapter.post('ownerA', '/api/member-guardian/legacy-attestation', {}),
      () => adapter.post('ownerB', '/api/member-guardian/legacy-attestation', {}),
    ]);
    assert.equal(attestation.overlapObserved, true, 'independent sessions must both wait on the settings row');
    const attested = attestation.results.map(result => result.data);
    assert.equal(attested.filter(row => row.changed).length, 1);
    assert.equal(attested[0].attestedAt, attested[1].attestedAt);
    const afterAttestation = await adapter.snapshot(fixture);
    assert.equal(afterAttestation.attestationAuditCount, 1); assert.equal(afterAttestation.attestedAt, attested[0].attestedAt);
    // Initially complete known minor Alia/mother. Profile switches to Bela/father.
    const consent = await adapter.race({ kind: 'member-row', id: minor }, [
      () => adapter.post('ownerA', '/api/member-guardian/consent', { memberId: minor, granted: true, source: 'Synthetic paper form' }),
      () => adapter.post('ownerB', '/api/member-guardian', { memberId: minor, dateOfBirth: '2012-01-01', guardian: { name: 'Bela Synthetic', relation: 'father', phone: '+919100006991', email: 'synthetic-guardian@example.invalid' } }),
    ]);
    assert.equal(consent.overlapObserved, true, 'consent/profile must contend on the same member row');
    for (const result of consent.results) assert.equal(result.ok, true);
    const afterConsent = await adapter.snapshot(fixture);
    assert.equal(afterConsent.minor.guardianName, 'Bela Synthetic');
    assert.equal(afterConsent.minor.consentRows.length, 1);
    const row = afterConsent.minor.consentRows[0];
    assert(['Alia Synthetic', 'Bela Synthetic'].includes(row.guardianName));
    assert.equal(row.guardianRelation, row.guardianName === 'Alia Synthetic' ? 'mother' : 'father');
    assert.equal(afterConsent.minor.scoringState, row.guardianName === 'Alia Synthetic' ? 'off_consent_stale' : 'on_consent');
    // Tokens remain wholly private in adapter, which issues them through the actual
    // owner route. Verified Google sessions share one Auth subject, independent transports.
    const redemption = await adapter.race({ kind: 'identity-advisory', id: fixture.guardianUserId }, [
      () => adapter.redeemSibling('guardianA', siblingA),
      () => adapter.redeemSibling('guardianB', siblingB),
    ]);
    assert.equal(redemption.overlapObserved, true, 'same Google subject must contend on identity advisory lock');
    assert.deepEqual(redemption.results.map(result => result.outcome).sort(), ['account_already_linked', 'linked']);
    const end = await adapter.snapshot(fixture);
    assert.equal(end.siblings.filter(member => member.userId === fixture.guardianUserId).length, 1);
    assert.equal(end.siblings.filter(member => member.guardianLinkedAt !== null).length, 1);
    assert.deepEqual(end.siblings.map(member => member.id).sort(), [siblingA, siblingB].sort());
    finished = true;
    return { attestation: true, consentProfile: true, siblingRedemption: true, genuineGoogle: true };
  } finally {
    // Adapter must verify persisted run marker and exact ownership BEFORE bounded
    // cleanup. It must not reset a live cutoff or delete by broad prefix/email.
    const cleaned = await adapter.cleanup(fixture);
    assert.equal(cleaned.exactFixtureGone, true, 'exact synthetic cleanup required');
    assert.equal(cleaned.outsideFixtureUnchanged, true, 'baseline outside exact manifest changed');
    if (!finished) assert.equal(cleaned.recoveryManifestSaved, true, 'retain red-run recovery evidence');
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  assert.equal(process.argv.length, 3, 'one reviewed private adapter path required');
  const adapter = await import(pathToFileURL(resolve(process.argv[2])).href);
  await runGuardianConcurrency(adapter);
  console.log('GRD: three real cross-session races passed; exact synthetic cleanup verified.');
}
