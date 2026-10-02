import { describe, expect, it, vi } from 'vitest';
import { loadMemberGuardian, loadGuardianCoverage, loadGuardianAttention } from '../guardian';

const MEMBER = '69000000-0000-4000-8000-000000000020';
function client(data: unknown, error: unknown = null) {
  const result = { data, error };
  const single = async () => ({ data: Array.isArray(data) ? data[0] ?? null : data, error });
  return { rpc: vi.fn((...args: unknown[]) => { void args; return { then: (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve), single, maybeSingle: single }; }) };
}
describe('GRD-019 caller-scoped read adapters', () => {
  it('preserves the database unknown-age legacy decision without inventing age or contacts', async () => {
    const rpc = client([{ age_state: 'unknown', date_of_birth: null, adult_on: null, gym_today: '2026-10-02',
      guardian_name: null, guardian_relation: null, guardian_phone: null, guardian_email: null,
      guardian_complete: false, link_email: 'member@example.com', link_email_in_use: false,
      consent_state: 'none', consent_recorded_at: null, consent_version: null,
      scoring_state: 'on_adult', guardian_linked_at: null, handover_due: false, legacy_attested_adult: true }]);
    expect(await loadMemberGuardian(rpc as never, MEMBER)).toEqual({ ageState: 'unknown', dateOfBirth: null,
      adultOn: null, gymToday: '2026-10-02', guardianName: null, guardianRelation: null, guardianPhone: null,
      guardianEmail: null, guardianComplete: false, linkEmail: 'member@example.com', linkEmailInUse: false,
      consentState: 'none', consentRecordedAt: null, consentVersion: null, scoringState: 'on_adult',
      guardianLinkedAt: null, handoverDue: false, legacyAttestedAdult: true });
    expect(rpc.rpc).toHaveBeenCalledWith('read_member_guardian', { p_member_id: MEMBER });
  });
  it('preserves zero counts and attestation cutoff so zero never suppresses the pre-attestation disclosure', async () => {
    const rpc = client([{ tracked: 0, no_birth_date: 0, minor_no_guardian: 0, minor_consent_missing: 0,
      handover_due: 0, members_without_dob_attested_adult_at: null }]);
    expect(await loadGuardianCoverage(rpc as never)).toEqual({ tracked: 0, noBirthDate: 0, minorNoGuardian: 0,
      minorConsentMissing: 0, handoverDue: 0, membersWithoutDobAttestedAdultAt: null });
    expect(rpc.rpc.mock.calls[0]?.[0]).toBe('read_guardian_coverage');
  });
  it.each(['no_birth_date', 'minor_no_guardian', 'minor_consent_missing', 'handover_due'])('reads attention reason %s through the scoped RPC', async (reason) => {
    const rpc = client([{ member_id: MEMBER, member_name: 'Asha', member_phone: '+919876543210', scoring_state: 'off_no_consent' }]);
    expect(await loadGuardianAttention(rpc as never, reason)).toEqual([{ memberId: MEMBER, memberName: 'Asha', memberPhone: '+919876543210', scoringState: 'off_no_consent' }]);
    expect(rpc.rpc).toHaveBeenCalledWith('list_guardian_attention', { p_reason: reason });
  });
  it.each(['all', '__proto__', 'constructor', '', 'minor_no_guardian&tenant=other'])('invalid attention reason %s reads nothing', async (reason) => {
    const rpc = client([]); expect(await loadGuardianAttention(rpc as never, reason)).toBeNull(); expect(rpc.rpc).not.toHaveBeenCalled();
  });
  it.each(['42501', 'XX000'])('collapses denied and failed reads %s to null', async (code) => {
    const rpc = client(null, { code, message: 'private guardian details mira@example.com' });
    expect(await loadMemberGuardian(rpc as never, MEMBER)).toBeNull();
    expect(await loadGuardianCoverage(rpc as never)).toBeNull();
    expect(await loadGuardianAttention(rpc as never, 'no_birth_date')).toBeNull();
  });
  it('empty RPC rows yield unavailable member and coverage but an empty attention ledger', async () => {
    const rpc = client([]);
    expect(await loadMemberGuardian(rpc as never, MEMBER)).toBeNull();
    expect(await loadGuardianCoverage(rpc as never)).toBeNull();
    expect(await loadGuardianAttention(rpc as never, 'no_birth_date')).toEqual([]);
  });
});
