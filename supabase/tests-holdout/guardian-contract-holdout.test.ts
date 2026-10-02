// GRD frozen bfd2690. Implementation-blind; no visible GRD or SQL tests read.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import * as shared from '../../packages/shared/src/index';

type RpcReply = { data: Record<string, unknown>[] | null; error: { code: string; message: string; details?: string; hint?: string } | null };
const h = vi.hoisted(() => ({ identity: null as Record<string, unknown> | null, rpc: vi.fn(), reply: null as RpcReply | null }));
vi.mock('../../apps/web/lib/identity-session', () => ({
  readIdentity: async () => h.identity === null ? null : ({ identity: h.identity, supabase: { rpc: h.rpc } }),
  readRequestIdentity: async () => h.identity === null ? null : ({ identity: h.identity, supabase: { rpc: h.rpc } }),
}));
const memberId = '69910000-0000-4000-8000-000000000001';
const privateMarker = 'PRIVATE_GUARDIAN_DIAGNOSTIC';
const commands = [
  { path: 'member-guardian', rpc: 'set_member_age_guardian', body: { memberId, dateOfBirth: null, guardian: null }, roles: ['gym_owner', 'gym_manager', 'front_desk'] },
  { path: 'member-guardian/consent', rpc: 'record_guardian_consent', body: { memberId, granted: false, source: 'Paper form' }, roles: ['gym_owner', 'gym_manager', 'front_desk'] },
  { path: 'member-identity/handover', rpc: 'transition_member_to_own_account', body: { memberId, reason: 'Member confirmed' }, roles: ['gym_owner', 'gym_manager'] },
  { path: 'member-guardian/legacy-attestation', rpc: 'attest_members_without_dob_adult', body: {}, roles: ['gym_owner'] },
];
async function post(path: string, request: Request) {
  switch (path) {
    case 'member-guardian': return (await import('../../apps/web/app/api/member-guardian/route')).POST(request);
    case 'member-guardian/consent': return (await import('../../apps/web/app/api/member-guardian/consent/route')).POST(request);
    case 'member-identity/handover': return (await import('../../apps/web/app/api/member-identity/handover/route')).POST(request);
    case 'member-invites': return (await import('../../apps/web/app/api/member-invites/route')).POST(request);
    default: return (await import('../../apps/web/app/api/member-guardian/legacy-attestation/route')).POST(request);
  }
}
function request(path: string, body: unknown) {
  return new Request(`https://holdout.example/api/${path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
}
beforeEach(() => {
  h.identity = { kind: 'staff', role: 'gym_owner', tenantId: memberId, userId: memberId, staffId: memberId };
  h.reply = { data: [{ consent_id: memberId, recorded_at: '2026-10-02T12:00:00Z', changed: false, members_without_dob_attested_adult_at: '2026-10-02T12:00:00Z' }], error: null };
  h.rpc.mockReset(); h.rpc.mockImplementation(() => {
    const single = async () => ({ ...h.reply, data: h.reply?.data?.[0] ?? null });
    return Object.assign(Promise.resolve(h.reply), { single, maybeSingle: single });
  });
});

describe('GRD-014 actual INV issue refusal amendment', () => {
  it.each([
    ['GL083', 422, 'guardian_required'],
    ['42501', 404, 'member_not_found'],
    ['GL075', 409, 'member_not_invitable'],
    ['GL076', 422, 'member_email_required'],
    ['GL077', 409, 'member_already_linked'],
    ['GL078', 429, 'invite_rate_limited'],
    ['__proto__', 500, 'invite_failed'],
    ['constructor', 500, 'invite_failed'],
  ])('actual issue handler maps %s safely while preserving INV outcomes', async (code, status, expected) => {
    h.reply = { data: null, error: { code, message: privateMarker, details: 'guardian-private@holdout.example', hint: '+919999999999' } };
    const result = await post('member-invites', request('member-invites', { memberId }));
    expect(result.status).toBe(status);
    expect(result.headers.get('cache-control')).toBe('no-store');
    const body = await result.json();
    expect(body.ok).toBe(false); expect(body.error.code).toBe(expected);
    expect(h.rpc.mock.calls[0]?.[0]).toBe('issue_member_invite');
    for (const secret of [privateMarker, 'guardian-private@holdout.example', '+919999999999', code]) expect(JSON.stringify(body)).not.toContain(secret);
  });
  it.each(['trainer', 'member', 'impersonation'])('INV guardian amendment retains %s refusal before body parsing', async role => {
    h.identity = role === 'trainer' ? { kind: 'staff', role, userId: memberId, tenantId: memberId, staffId: memberId }
      : { kind: role, userId: memberId, tenantId: memberId, memberId };
    const incoming = request('member-invites', { memberId }); const read = vi.spyOn(incoming, 'json');
    const result = await post('member-invites', incoming);
    expect(result.status).toBeGreaterThanOrEqual(400);
    expect(result.headers.get('cache-control')).toBe('no-store');
    expect(read).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled();
  });
});

describe('GRD holdout actual route boundaries', () => {
  describe.each(commands)('$path', command => {
    it('refuses unauthenticated malformed input before reading the body', async () => {
      h.identity = null;
      const incoming = request(command.path, command.body);
      const read = vi.spyOn(incoming, 'json');
      const result = await post(command.path, incoming);
      expect(result.status).toBe(401); expect(read).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled();
    });
    it.each(['trainer', 'member', 'impersonation', 'gym_owner', 'gym_manager', 'front_desk'])('has exact %s audience boundary', async role => {
      h.identity = role === 'member' ? { kind: 'member', userId: memberId, tenantId: memberId, memberId }
        : role === 'impersonation' ? { kind: 'impersonation', userId: memberId, tenantId: memberId }
        : { ...h.identity, role };
      const incoming = request(command.path, command.body); const read = vi.spyOn(incoming, 'json');
      const result = await post(command.path, incoming);
      if (command.roles.includes(role)) {
        expect(result.status).toBe(200); expect(h.rpc.mock.calls[0]?.[0]).toBe(command.rpc);
      } else {
        expect(result.status).toBeGreaterThanOrEqual(400); expect(read).not.toHaveBeenCalled(); expect(h.rpc).not.toHaveBeenCalled();
      }
      expect(result.headers.get('cache-control')).toBe('no-store');
    });
    it('rejects a forged caller/tenant/timestamp/version field before RPC', async () => {
      const result = await post(command.path, request(command.path, { ...command.body, tenantId: memberId, actorId: memberId, version: 'attacker-version', attestedAt: '1990-01-01' }));
      expect(result.status).toBe(400); expect(h.rpc).not.toHaveBeenCalled();
    });
    it.each(['__proto__', 'constructor', 'PRIVATE_UNKNOWN'])('does not use inherited error-map key %s or disclose backend diagnostics', async code => {
      h.reply = { data: null, error: { code, message: privateMarker, details: 'child-private@holdout.example', hint: '+919999999999' } };
      const result = await post(command.path, request(command.path, command.body));
      expect(result.status).toBe(500); const body = await result.text();
      for (const secret of [privateMarker, 'child-private@holdout.example', '+919999999999']) expect(body).not.toContain(secret);
    });
  });
  it('copies the consent version from the server and maps repeated consent without inventing a new id', async () => {
    const result = await post('member-guardian/consent', request('member-guardian/consent', { memberId, granted: false, source: '  Phone call  ' }));
    expect(h.rpc).toHaveBeenCalledWith('record_guardian_consent', { p_member_id: memberId, p_granted: false, p_source: 'Phone call', p_version: 'guardian-absence-v1' });
    expect(await result.json()).toEqual({ ok: true, data: { consentId: memberId, recordedAt: '2026-10-02T12:00:00Z', changed: false } });
  });
  it('attestation has no client supplied cutoff and preserves the returned original timestamp', async () => {
    const result = await post('member-guardian/legacy-attestation', request('member-guardian/legacy-attestation', {}));
    expect(h.rpc.mock.calls[0]?.[0]).toBe('attest_members_without_dob_adult');
    expect(h.rpc.mock.calls[0]?.[1] ?? {}).toEqual({});
    expect(await result.json()).toEqual({ ok: true, data: { attestedAt: '2026-10-02T12:00:00Z', changed: false } });
  });
  it.each([
    ['member-guardian', '42501', 404, 'member_not_found'],
    ['member-guardian/consent', 'GL083', 409, 'guardian_required'],
    ['member-guardian/consent', 'GL084', 409, 'member_not_minor'],
    ['member-identity/handover', 'GL084', 409, 'member_not_adult'],
    ['member-identity/handover', 'GL085', 409, 'member_not_guardian_linked'],
    ['member-guardian/legacy-attestation', '42501', 403, 'not_permitted'],
  ])('maps %s %s without exposing the database message', async (path, code, status, expected) => {
    h.reply = { data: null, error: { code, message: privateMarker } };
    const command = commands.find(row => row.path === path)!;
    const result = await post(path as string, request(path as string, command.body));
    expect(result.status).toBe(status); const body = await result.json();
    expect(body.error.code).toBe(expected); expect(JSON.stringify(body)).not.toContain(privateMarker);
  });
});

describe('GRD holdout actual shared schemas and privacy copy', () => {
  it.each(['tenantId', 'guardian_linked_at', 'user_id', 'scoringEnabled'])('profile rejects unauthorized field %s', field => {
    expect(shared.guardianProfileRequestSchema.safeParse({ memberId, dateOfBirth: null, guardian: null, [field]: memberId }).success).toBe(false);
  });
  it('profile preserves unknown DOB and optional empty contact rather than inventing facts', () => {
    expect(shared.guardianProfileRequestSchema.parse({ memberId, dateOfBirth: null, guardian: { name: '  Alia Rao  ', relation: 'mother', phone: '', email: '' } })).toEqual({ memberId, dateOfBirth: null, guardian: { name: 'Alia Rao', relation: 'mother', phone: undefined, email: undefined } });
  });
  it.each(['2026-02-29', '2000-13-01', '2000-01-32', '2000-01-01T00:00:00Z'])('rejects invalid calendar DOB %s', dateOfBirth => {
    expect(shared.guardianProfileRequestSchema.safeParse({ memberId, dateOfBirth, guardian: null }).success).toBe(false);
  });
  it('accepts under-13 DOB without client age arithmetic or unsupported refusal', () => {
    expect(shared.guardianProfileRequestSchema.safeParse({ memberId, dateOfBirth: '2020-01-01', guardian: null }).success).toBe(true);
  });
  it('never permits consent snapshot or version injection', () => {
    expect(shared.guardianConsentRequestSchema.safeParse({ memberId, granted: true, source: 'Paper', version: 'evil', guardianName: 'Stranger' }).success).toBe(false);
  });
  it('share copy names first names only and binds the exact guardian Google address', () => {
    expect(shared.guardianInviteShareMessage({ guardianName: 'Alia Rao', memberName: 'Mira Rao', gymName: 'Holdout Gym', email: 'guardian@holdout.example', link: 'https://holdout.example/invite' })).toBe("Hi Alia, Holdout Gym invited Mira to join on FitCruxx. Open this link and sign in with Google using guardian@holdout.example so Mira's membership connects: https://holdout.example/invite");
  });
  it('unknown server state fails safe', () => expect(shared.guardianScoringMessage('on_attacker')).toBe('Absence follow-ups are off.'));
  it('handover coverage alone does not claim members are unscored', () => {
    expect(shared.guardianCoverageLines({ tracked: 0, noBirthDate: 0, minorNoGuardian: 0, minorConsentMissing: 0, handoverDue: 1 })).toEqual(["1 turned 18 and still signs in through a guardian's account."]);
  });
});
