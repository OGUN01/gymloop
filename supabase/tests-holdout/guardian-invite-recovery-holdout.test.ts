// GRD frozen bfd2690. Implementation-blind; no visible GRD or SQL tests read.
import { beforeEach, expect, it, vi } from 'vitest';
import type { GymloopIdentity } from '../../packages/shared/src/api/identity';

type RpcReply = { data: Record<string, unknown>[] | null; error: { code: string; message: string; details?: string; hint?: string } | null };
const h = vi.hoisted(() => ({ identity: null as GymloopIdentity | null, rpc: vi.fn(), reply: null as RpcReply | null }));
vi.mock('../../apps/web/lib/identity-session', () => ({
  readIdentity: async () => h.identity === null ? null : ({ identity: h.identity, supabase: { rpc: h.rpc } }),
  readRequestIdentity: async () => h.identity === null ? null : ({ identity: h.identity, supabase: { rpc: h.rpc } }),
}));
const memberId = '69910000-0000-4000-8000-000000000001';
const privateMarker = 'PRIVATE_GUARDIAN_DIAGNOSTIC';
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


it('GRD-014/025: GL083 recovery names guardian email as well as required guardian record', async () => {
  h.reply = { data: null, error: { code: 'GL083', message: privateMarker } };
  const result = await post('member-invites', request('member-invites', { memberId }));
  expect(result.status).toBe(422);
  expect(result.headers.get('cache-control')).toBe('no-store');
  const body = await result.json();
  expect(body).toMatchObject({ ok: false, error: { code: 'guardian_required' } });
  expect(body.error.message).toMatch(/guardian/i);
  expect(body.error.message).toMatch(/email/i);
  expect(JSON.stringify(body)).not.toContain(privateMarker);
});
