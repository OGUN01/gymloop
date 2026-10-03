// LDC holdout. Frozen lead-conversion contract 2026-10-03. Implementation-blind:
// derived only from openspec/changes/lead-conversion/proposal.md, the LDC bar,
// the phase-6 leads/metrics contracts and one unrelated holdout's harness.
// No visible test, app source, registry entry or LDC test file was read.
import { beforeEach, describe, expect, it, vi } from 'vitest';

type RpcReply = { data: Record<string, unknown>[] | null; error: { code: string; message: string; details?: string; hint?: string } | null };
const h = vi.hoisted(() => ({ identity: null as Record<string, unknown> | null, rpc: vi.fn(), reply: null as RpcReply | null }));
vi.mock('../../apps/web/lib/identity-session', () => ({
  readIdentity: async () => h.identity === null ? null : ({ identity: h.identity, supabase: { rpc: h.rpc } }),
  readRequestIdentity: async () => h.identity === null ? null : ({ identity: h.identity, supabase: { rpc: h.rpc } }),
}));

const tenantId = '9dc00000-0000-4000-8000-0000000000a1';
const ownerId = '9dc00000-0000-4000-8000-0000000000a2';
const leadId = '9dc00000-0000-4000-8000-0000000000b1';
const otherLeadId = '9dc00000-0000-4000-8000-0000000000b2';
const memberId = '9dc00000-0000-4000-8000-0000000000c1';
const requestKey = '9dc00000-0000-4000-8000-0000000000d1';
const revision = '9dc00000-0000-4000-8000-0000000000e1';
const otherRevision = '9dc00000-0000-4000-8000-0000000000e2';
const privateMarker = 'PRIVATE_LDC_DIAGNOSTIC';

const createBody = { requestKey, expectedRevision: revision, mode: 'create' };
const linkBody = { requestKey, expectedRevision: revision, mode: 'link_existing', memberId };

async function post(lead: string, body: unknown) {
  const mod = await import('../../apps/web/app/api/leads/[leadId]/convert/route');
  const request = new Request('https://holdout.example/api/leads/x/convert', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
  });
  return mod.POST(request, { params: Promise.resolve({ leadId: lead }) } as never);
}
function ok(data: Record<string, unknown>): RpcReply {
  return { data, error: null } as unknown as RpcReply;
}
function err(code: string, extra: Partial<NonNullable<RpcReply['error']>> = {}): RpcReply {
  return { data: null, error: { code, message: privateMarker, details: 'desk-private@holdout.example', hint: '+919999999999', ...extra } };
}
function bodyOf(result: Response) {
  return result.json() as Promise<Record<string, unknown>>;
}
function dataOf(body: Record<string, unknown>) {
  return (body.data ?? body) as Record<string, unknown>;
}

beforeEach(() => {
  h.identity = { kind: 'staff', role: 'gym_owner', userId: ownerId, tenantId, staffId: ownerId };
  h.reply = ok({ leadId, memberId, outcome: 'created_member', revision: otherRevision, replayed: false });
  h.rpc.mockReset();
  h.rpc.mockImplementation(() => {
    const single = async () => ({ ...h.reply, data: h.reply?.data ?? null });
    return Object.assign(Promise.resolve(h.reply), { single, maybeSingle: single });
  });
});

describe('LDC-001 audience and identity boundary', () => {
  it.each([
    ['gym_owner'], ['gym_manager'], ['front_desk'],
  ])('%s reaches the sole conversion command', async role => {
    h.identity = { ...h.identity!, role };
    const result = await post(leadId, createBody);
    expect(h.rpc.mock.calls[0]?.[0]).toBe('convert_lead');
    expect([200, 201]).toContain(result.status);
  });
  it.each([
    ['trainer'], ['member'], ['impersonation'], ['preview'],
  ])('%s receives no lead facts and no target inspection', async role => {
    h.identity = role === 'member'
      ? { kind: 'member', userId: ownerId, tenantId, memberId }
      : role === 'impersonation' ? { kind: 'impersonation', userId: ownerId, tenantId }
      : role === 'preview' ? { kind: 'preview', userId: ownerId, tenantId }
      : { ...h.identity!, role };
    const incoming = new Request('https://holdout.example/api/leads/x/convert', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(createBody),
    });
    const read = vi.spyOn(incoming, 'json');
    const mod = await import('../../apps/web/app/api/leads/[leadId]/convert/route');
    const result = await mod.POST(incoming, { params: Promise.resolve({ leadId }) } as never);
    expect(result.status).toBeGreaterThanOrEqual(400);
    expect(read).not.toHaveBeenCalled();
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it('unauthenticated caller is refused before the body is read', async () => {
    h.identity = null;
    const incoming = new Request('https://holdout.example/api/leads/x/convert', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(createBody),
    });
    const read = vi.spyOn(incoming, 'json');
    const mod = await import('../../apps/web/app/api/leads/[leadId]/convert/route');
    const result = await mod.POST(incoming, { params: Promise.resolve({ leadId }) } as never);
    expect(result.status).toBe(401);
    expect(read).not.toHaveBeenCalled();
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it('a preview identity never gains conversion authority', async () => {
    h.identity = { kind: 'preview', userId: ownerId, tenantId };
    const result = await post(leadId, createBody);
    expect(h.rpc).not.toHaveBeenCalled();
    expect(result.status).toBeGreaterThanOrEqual(400);
  });
});

describe('LDC-002 one action, exact envelope', () => {
  it('create mode maps the path lead id, key, revision and mode with no member id', async () => {
    await post(leadId, createBody);
    expect(h.rpc).toHaveBeenCalledTimes(1);
    const args = h.rpc.mock.calls[0];
    expect(args[0]).toBe('convert_lead');
    expect(args[1].p_lead_id).toBe(leadId);
    expect(args[1].p_request_key).toBe(requestKey);
    expect(args[1].p_expected_revision).toBe(revision);
    expect(args[1].p_mode).toBe('create');
    expect(args[1].p_member_id ?? null).toBeNull();
  });
  it.each([
    ['supplied tenant', { tenantId }],
    ['supplied actor', { actorId: ownerId }],
    ['supplied member for create', { memberId }],
    ['supplied outcome', { outcome: 'created_member' }],
    ['unknown field', { unrelated: 'x' }],
  ])('rejects %s before any command', async (_label, extra) => {
    const result = await post(leadId, { ...createBody, ...extra });
    expect(result.status).toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it('rejects a link-mode body whose member id is missing', async () => {
    const { memberId: _drop, ...rest } = linkBody as Record<string, unknown>;
    const result = await post(leadId, rest);
    expect(result.status).toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
  });
});

describe('LDC-003/009/010 atomic creation truth and no invented attribution', () => {
  it('created_member success exposes the contract result keys and nothing attributional', async () => {
    const result = await post(leadId, createBody);
    const body = await bodyOf(result);
    expect(body.ok).toBe(true);
    const data = dataOf(body);
    expect(data.outcome).toBe('created_member');
    expect(data.replayed).toBe(false);
    expect(JSON.stringify(body)).not.toContain('source');
    expect(JSON.stringify(body)).not.toContain('member_code');
    expect(JSON.stringify(body)).not.toContain('membership');
    expect(JSON.stringify(body)).not.toContain('payment');
    expect(JSON.stringify(body)).not.toContain('notes');
  });
  it('link_existing success preserves the outcome word and member id', async () => {
    h.reply = ok({ leadId, memberId, outcome: 'linked_existing', revision: otherRevision, replayed: false });
    const result = await post(leadId, linkBody);
    const body = await bodyOf(result);
    expect(body.ok).toBe(true);
    const data = dataOf(body);
    expect(data.outcome).toBe('linked_existing');
    expect(h.rpc.mock.calls[0][1].p_mode).toBe('link_existing');
    expect(h.rpc.mock.calls[0][1].p_member_id).toBe(memberId);
  });
  it('a failed write answers failure and never a guessed success', async () => {
    h.reply = { data: null, error: { code: 'XX999', message: privateMarker } };
    const result = await post(leadId, createBody);
    expect(result.status).toBeGreaterThanOrEqual(400);
    const body = await bodyOf(result);
    expect(body.ok).toBe(false);
  });
});

describe('LDC-004 eligible duplicate and LDC-005 unavailable/foreign targets', () => {
  it('GL061 answers 409 link_required and leaks no diagnostics', async () => {
    h.reply = err('GL061', { details: `member_id=${memberId};full_name=Existing Member;phone=+919000000001;status=active` });
    const result = await post(leadId, createBody);
    expect(result.status).toBe(409);
    const body = await bodyOf(result);
    expect(body.ok).toBe(false);
    expect(body.error && (body.error as Record<string, unknown>).code).toBe('link_required');
    const text = JSON.stringify(body);
    for (const secret of [privateMarker, 'desk-private@holdout.example', '+919999999999']) expect(text).not.toContain(secret);
  });
  it('malformed duplicate facts offer no unseen member', async () => {
    h.reply = err('GL061', { details: 'not-a-fact-string' });
    const result = await post(leadId, createBody);
    expect(result.status).toBeGreaterThanOrEqual(400);
    const text = JSON.stringify(await bodyOf(result));
    expect(text).not.toContain('member_id=');
    expect(text).not.toContain('9dc00000');
  });
  it('member_unavailable discloses no profile facts', async () => {
    h.reply = err('GL061', { details: 'unavailable' });
    const result = await post(leadId, createBody);
    expect(result.status).toBe(409);
    const text = JSON.stringify(await bodyOf(result));
    expect(text).not.toContain('Existing Member');
    expect(text).not.toContain('+919000000001');
    expect(text).not.toContain('active');
  });
  it.each([
    ['unknown member', '9dc00000-0000-4000-8000-0000000000f1'],
    ['cross-gym member', '9dc00000-0000-4000-8000-0000000000f2'],
    ['wrong-phone member', '9dc00000-0000-4000-8000-0000000000f3'],
  ])('link mode targeting a %s shares one generic refusal with no profile facts', async (_label, target) => {
    h.reply = err('P0002');
    const result = await post(leadId, { ...linkBody, memberId: target });
    expect(result.status).toBe(404);
    const text = JSON.stringify(await bodyOf(result));
    expect(text).not.toContain('fullName');
    expect(text).not.toContain('phone');
    expect(text).not.toContain(privateMarker);
  });
  it('unknown and foreign member targets are indistinguishable', async () => {
    h.reply = err('P0002');
    const a = await post(leadId, { ...linkBody, memberId: '9dc00000-0000-4000-8000-0000000000f1' });
    const b = await post(leadId, { ...linkBody, memberId: '9dc00000-0000-4000-8000-0000000000f2' });
    expect(await a.text()).toBe(await b.text());
  });
});

describe('LDC-006 durable retry and LDC-007 races', () => {
  it('an exact retry sends the identical key and facts', async () => {
    await post(leadId, createBody);
    await post(leadId, createBody);
    expect(h.rpc).toHaveBeenCalledTimes(2);
    expect(h.rpc.mock.calls[1].slice(1)).toEqual(h.rpc.mock.calls[0].slice(1));
  });
  it('the replayed original result is returned read-only', async () => {
    h.reply = ok({ leadId, memberId, outcome: 'created_member', revision, replayed: true });
    const result = await post(leadId, createBody);
    const body = await bodyOf(result);
    expect(dataOf(body).replayed).toBe(true);
    expect(dataOf(body).revision).toBe(revision);
  });
  it('a key reused with changed facts answers the key conflict', async () => {
    h.reply = err('GL062');
    const result = await post(leadId, { ...createBody, expectedRevision: otherRevision });
    expect(result.status).toBe(409);
    const body = await bodyOf(result);
    expect(body.error && (body.error as Record<string, unknown>).code).toBe('idempotency_conflict');
  });
  it('a different-actor retry is refused without original outcome disclosure', async () => {
    h.reply = err('GL062');
    const result = await post(leadId, createBody);
    const text = JSON.stringify(await bodyOf(result));
    expect(text).not.toContain(privateMarker);
    expect(text).not.toContain('desk-private@holdout.example');
  });
  it('an illegal-transition refusal is a stable 409 with a distinct code and no diagnostics', async () => {
    h.reply = err('GL059');
    const result = await post(leadId, createBody);
    expect(result.status).toBe(409);
    const body = await bodyOf(result);
    const code = (body.error as Record<string, unknown> | undefined)?.code;
    expect(typeof code).toBe('string');
    expect(code).not.toBe('idempotency_conflict');
    expect(JSON.stringify(body)).not.toContain(privateMarker);
  });
  // CAS-miss → exact 409 {code:'stale_lead', currentRevision} is contract text,
  // but the raising SQLSTATE is not derivable from the frozen documents; a
  // blind author cannot simulate it without reading implementation. Flagged to
  // the orchestrator: the implementer/critic must demonstrate that exact
  // response shape for a revision-mismatch conversion.
  it('an arbitrary unique violation is never answered as a replay', async () => {
    h.reply = err('23505');
    const result = await post(leadId, createBody);
    const body = await bodyOf(result);
    expect(body.ok).toBe(false);
    expect(JSON.stringify(body)).not.toContain('"replayed":true');
  });
  it('terminal and unknown refusals keep distinct stable codes and never leak diagnostics', async () => {
    h.reply = err('GL059');
    const terminal = await post(leadId, createBody);
    expect(terminal.status).toBe(409);
    h.reply = err('ZZ001');
    const unknown = await post(leadId, createBody);
    expect(unknown.status).toBe(500);
    const text = JSON.stringify(await bodyOf(unknown));
    for (const secret of [privateMarker, 'desk-private@holdout.example', '+919999999999']) expect(text).not.toContain(secret);
  });
  it('a different lead id under the same key sends that lead id, not a cached one', async () => {
    await post(leadId, createBody);
    await post(otherLeadId, createBody);
    expect(h.rpc.mock.calls[1][1].p_lead_id).toBe(otherLeadId);
  });
});

describe('LDC-011 envelope hygiene', () => {
  it('malformed JSON fails safely with no command', async () => {
    const incoming = new Request('https://holdout.example/api/leads/x/convert', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: '{"requestKey":',
    });
    const mod = await import('../../apps/web/app/api/leads/[leadId]/convert/route');
    const result = await mod.POST(incoming, { params: Promise.resolve({ leadId }) } as never);
    expect(result.status).toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
  });
  it('an invalid lead uuid in the path never reaches the command', async () => {
    const result = await post('not-a-uuid', createBody);
    expect(result.status).toBeGreaterThanOrEqual(400);
    expect(h.rpc).not.toHaveBeenCalled();
  });
});
