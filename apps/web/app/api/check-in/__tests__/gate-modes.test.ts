import { beforeEach, describe, expect, it, vi } from 'vitest';
import { POSTER_CODE_SECRET_MIN_BYTES } from '@gymloop/shared';
import { hashGateCode, posterGateCode } from '../../../../lib/gate-code';

type Result = { data: unknown; error: { code: string } | null };
const state: { role: string; results: Result[]; rpcResults: Result[]; calls: Array<{ table: string; action: string; args: unknown[] }>; rpcCalls: Array<{ name: string; args: unknown }> } = {
  role: 'gym_owner', results: [], rpcResults: [], calls: [], rpcCalls: [],
};
const ok = (data: unknown): Result => ({ data, error: null });
const fail = (code: string): Result => ({ data: null, error: { code } });
const uid = '66000000-0000-4000-8000-000000000901';
const tenantId = '66000000-0000-4000-8000-000000000001';
const staffId = '66000000-0000-4000-8000-000000000021';
const branchId = '66000000-0000-4000-8000-000000000011';
vi.mock('../../../../lib/supabase/server', () => ({
  createServerSupabase: () => Promise.resolve({
    auth: { getClaims: () => Promise.resolve({ data: { claims: {
      sub: uid, role: 'authenticated', tenant_id: tenantId, staff_id: staffId, app_role: state.role,
    } } }) },
    from: (table: string) => {
      const result = state.results.shift() ?? ok(null);
      const chain: Record<string, unknown> = { then: (done: (v: unknown) => unknown) => Promise.resolve(result).then(done) };
      for (const action of ['select', 'insert', 'eq', 'is', 'filter', 'order', 'limit', 'maybeSingle', 'single', 'update']) {
        chain[action] = (...args: unknown[]) => { state.calls.push({ table, action, args }); return chain; };
      }
      return chain;
    },
    rpc: (name: string, args: unknown) => {
      state.rpcCalls.push({ name, args });
      const queued = state.rpcResults.shift() ?? ok(null);
      const result = queued.data === '<request-session-id>' && name === 'replace_checkin_poster'
        ? ok((args as { p_session_id: string }).p_session_id) : queued;
      const chain: Record<string, unknown> = { then: (done: (v: unknown) => unknown) => Promise.resolve(result).then(done) };
      chain.single = () => chain;
      return chain;
    },
  }),
}));

const { GET: currentGate, POST: issueGate } = await import('../../gate-code/route');
const { POST: replacePoster } = await import('../../gate-code/poster/route');
const { POST: changeMode } = await import('../../gate-code/mode/route');
const { POST: checkIn } = await import('../route');
const request = (url: string, body: unknown) => new Request(`https://example.test${url}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
const body = async (response: Response) => await response.json() as { ok: boolean; data?: Record<string, unknown>; error?: { code: string; message: string } };

beforeEach(() => {
  state.role = 'gym_owner'; state.results = []; state.rpcResults = []; state.calls = []; state.rpcCalls = [];
  vi.stubEnv('POSTER_CODE_SECRET', Buffer.alloc(POSTER_CODE_SECRET_MIN_BYTES, 7).toString('base64url'));
});

describe('poster gate management', () => {
  it('refuses issuance of a rotating code when gym uses printed posters', async () => {
    state.results = [ok({ id: branchId }), ok({ checkin_gate_mode: 'printed_poster' })];
    const response = await issueGate();
    expect(response.status).toBe(409);
    expect((await body(response)).error?.code).toBe('poster_mode_active');
    expect(state.calls.some((c) => c.table === 'qr_sessions' && c.action === 'insert')).toBe(false);
  });

  it('returns current poster across requests, re-derived without writing a new session', async () => {
    const posterId = '66000000-0000-4000-8000-000000000061';
    state.results = [ok({ checkin_gate_mode: 'printed_poster' }), ok({ id: branchId }),
      ok({ id: posterId, token_hash: hashGateCode(posterGateCode(posterId)) })];
    const response = await currentGate();
    expect((await body(response)).data).toMatchObject({ mode: 'printed_poster', branchId });
    expect(state.calls.some((c) => c.table === 'qr_sessions' && c.action === 'is'
      && c.args[0] === 'revoked_at' && c.args[1] === null)).toBe(true);
    expect(state.calls.some((c) => c.action === 'insert')).toBe(false);
  });

  it('refuses to redisplay a poster derived under a different server secret', async () => {
    state.results = [ok({ checkin_gate_mode: 'printed_poster' }), ok({ id: branchId }),
      ok({ id: '66000000-0000-4000-8000-000000000061', token_hash: 'f'.repeat(64) })];
    const response = await currentGate();
    expect(response.status).toBe(409);
    const payload = await body(response);
    expect(payload.error?.code).toBe('poster_secret_changed');
    expect(payload.error?.message).toMatch(/replace poster/i);
    expect(state.calls.some((c) => c.action === 'insert')).toBe(false);
  });

  it('owner replacement writes only a hash through the atomic command', async () => {
    state.results = [ok({ id: branchId })];
    state.rpcResults = [ok('<request-session-id>')];
    const response = await replacePoster(request('/api/gate-code/poster', { confirmed: true }));
    expect(response.status).toBe(200);
    expect(state.rpcCalls[0]?.name).toBe('replace_checkin_poster');
    const responseBody = await body(response);
    expect(responseBody.data?.mode).toBe('printed_poster');
    expect(JSON.stringify(state.rpcCalls)).not.toContain(responseBody.data?.code as string);
  });

  it('rejects unconfirmed or front-desk replacement without a database mutation', async () => {
    const unconfirmed = await replacePoster(request('/api/gate-code/poster', { confirmed: false }));
    expect(unconfirmed.status).toBe(400);
    state.role = 'front_desk';
    const forbidden = await replacePoster(request('/api/gate-code/poster', { confirmed: true }));
    expect(forbidden.status).toBe(403);
    expect(state.rpcCalls).toHaveLength(0);
  });

  it('changes mode only for gym admins and never accepts tenant in body', async () => {
    state.rpcResults = [ok('rotating_screen')];
    const response = await changeMode(request('/api/gate-code/mode', { mode: 'rotating_screen' }));
    expect(response.status).toBe(200);
    expect(state.rpcCalls[0]?.name).toBe('set_checkin_gate_mode');
    const invalid = await changeMode(request('/api/gate-code/mode', { mode: 'printed_poster', tenantId }));
    expect(invalid.status).toBe(400);
    state.role = 'front_desk';
    const forbidden = await changeMode(request('/api/gate-code/mode', { mode: 'printed_poster' }));
    expect(forbidden.status).toBe(403);
  });
});

describe('database poster refusals', () => {
  it.each([['GL070','mode'],['GL071','branch'],['GL072','closed'],['GL073','already']])('maps %s to a useful refusal about %s', async (code, subject) => {
    state.results = [ok({ id: '66000000-0000-4000-8000-000000000031', full_name: 'A Member', branch_id: branchId }), ok({ id: '66000000-0000-4000-8000-000000000061', branch_id: branchId }), fail(code)];
    const response = await checkIn(request('/api/check-in', { memberId: '66000000-0000-4000-8000-000000000031', token: 'ABCD' }));
    const payload = await body(response);
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(payload.error?.code).toBe(code);
    expect(payload.error?.message.toLowerCase()).toContain(subject);
  });
});
