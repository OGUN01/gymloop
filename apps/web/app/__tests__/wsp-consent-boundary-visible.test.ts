import { beforeEach, describe, expect, it, vi } from 'vitest';

/** Independent visible author: frozen WSP-002/008 and the public role/privacy
 * contract (proposal + provider amendment + serial/app verification packets).
 * No production source, migrations, holdouts or other test suites were read.
 */
const boundary = vi.hoisted(() => ({
  rpc: vi.fn(), requireAudience: vi.fn(), readRequestIdentity: vi.fn(),
  memberSession: vi.fn(), staffSession: vi.fn(),
}));
vi.mock('../../lib/api', async (importOriginal) => {
  const actual = await importOriginal<typeof import('../../lib/api')>();
  return { ...actual, memberSession: boundary.memberSession, staffSession: boundary.staffSession };
});
vi.mock('../../lib/identity-session', () => ({
  requireAudience: boundary.requireAudience,
  readRequestIdentity: boundary.readRequestIdentity,
}));

const tenantId = '11111111-1111-4111-8111-111111111111';
const userId = '22222222-2222-4222-8222-222222222222';
const memberId = '33333333-3333-4333-8333-333333333333';
const staffId = '44444444-4444-4444-8444-444444444444';
const requestKey = '55555555-5555-4555-8555-555555555555';
const owner = { kind: 'staff', role: 'gym_owner', userId, tenantId, staffId };
const member = { kind: 'member', role: 'member', userId, tenantId, memberId };
const emptyPage = {
  operations: [], nextAfter: null, nextAfterId: null,
  statusCounts: { accepted: '0', delivered: '0', read: '0', unknown: '0' },
  templateBlockers: [], wallet: null, chargedTotals: null,
};
const decision = {
  consentId: '66666666-6666-4666-8666-666666666666', purpose: 'service',
  granted: true, noticeVersion: '2026-10-wsp-1', recordedAt: '2026-10-03T09:00:00Z',
};

beforeEach(() => {
  vi.clearAllMocks();
  boundary.rpc.mockResolvedValue({ data: emptyPage, error: null });
  boundary.requireAudience.mockResolvedValue({ identity: owner, supabase: { rpc: boundary.rpc } });
  boundary.readRequestIdentity.mockResolvedValue({ identity: member, supabase: { rpc: boundary.rpc } });
  boundary.memberSession.mockResolvedValue({ session: { userId, tenantId, memberId, supabase: { rpc: boundary.rpc } } });
  boundary.staffSession.mockResolvedValue({ session: { userId, tenantId, staffId, role: 'gym_owner', supabase: { rpc: boundary.rpc } } });
});

describe('WSP operations role and paired keyset boundary', () => {
  it.each([{ ...owner, role: 'trainer' }, member])('denies $kind/$role before RPC', async (identity) => {
    boundary.requireAudience.mockResolvedValue({ identity, supabase: { rpc: boundary.rpc } });
    const { loadWhatsappOperations } = await import('../../lib/whatsapp-operations');
    const result = await loadWhatsappOperations({});
    expect(result.view).toBeNull();
    expect(boundary.rpc).not.toHaveBeenCalled();
  });

  it('initial page passes both null cursor halves with the frozen bound', async () => {
    const { loadWhatsappOperations } = await import('../../lib/whatsapp-operations');
    expect((await loadWhatsappOperations({})).view).toEqual(emptyPage);
    expect(boundary.requireAudience).toHaveBeenCalledWith('console');
    expect(boundary.rpc).toHaveBeenCalledWith('read_whatsapp_operations', {
      p_after_created_at: null, p_after_id: null, p_limit: 100,
    });
  });

  it('preserves both valid cursor halves', async () => {
    const { loadWhatsappOperations } = await import('../../lib/whatsapp-operations');
    await loadWhatsappOperations({ cursor: `2026-10-03T09:00:00Z|${requestKey}` });
    expect(boundary.rpc).toHaveBeenCalledWith('read_whatsapp_operations', {
      p_after_created_at: '2026-10-03T09:00:00Z', p_after_id: requestKey, p_limit: 100,
    });
  });

  it.each(['2026-10-03T09:00:00Z', `|${requestKey}`, '2026-10-03T09:00:00Z|',
    `invalid-date|${requestKey}`, '2026-10-03T09:00:00Z|invalid-id',
    `2026-10-03T09:00:00Z|${requestKey}|extra`])('does not restart the first page for malformed cursor %s', async (cursor) => {
    const { loadWhatsappOperations } = await import('../../lib/whatsapp-operations');
    const result = await loadWhatsappOperations({ cursor });
    expect(result.view).toBeNull();
    expect(result.errorMessage).toBeTruthy();
    expect(boundary.rpc).not.toHaveBeenCalled();
  });

  it.each([
    { ...emptyPage, nextAfter: '2026-10-03T09:00:00Z' },
    { ...emptyPage, nextAfterId: requestKey },
    emptyPage,
  ])('never emits a half cursor', async (page) => {
    const { whatsappOperationsCursor } = await import('../../lib/whatsapp-operations');
    expect(whatsappOperationsCursor(page)).toBeNull();
  });

  it.each(['0', '2026-10-03', '2026-10-03T09:00:00', '2026-02-30T09:00:00Z',
    '2026-04-31T09:00:00+05:30', '2026-13-03T09:00:00Z'])(
    'returns the safe refusal envelope before RPC for incomplete or impossible timestamp %s', async (timestamp) => {
      const { loadWhatsappOperations } = await import('../../lib/whatsapp-operations');
      const result = await loadWhatsappOperations({ cursor: `${timestamp}|${requestKey}` });
      expect.soft(result).toEqual({
        view: null, errorMessage: 'The WhatsApp operations list could not be loaded.', isPreview: false,
      });
      expect(boundary.rpc).not.toHaveBeenCalled();
    },
  );

  it.each(['2026-10-03T09:00:00Z', '2026-10-03T09:00:00.123+05:30', '2024-02-29T23:59:59-04:00'])(
    'preserves the complete calendar-valid timestamp and id verbatim: %s', async (timestamp) => {
      const { loadWhatsappOperations } = await import('../../lib/whatsapp-operations');
      const result = await loadWhatsappOperations({ cursor: `${timestamp}|${requestKey}` });
      expect(result).toEqual({ view: emptyPage, errorMessage: null, isPreview: false });
      expect(boundary.rpc).toHaveBeenCalledExactlyOnceWith('read_whatsapp_operations', {
        p_after_created_at: timestamp, p_after_id: requestKey, p_limit: 100,
      });
    },
  );

  it('emits the complete paired cursor for a continuing page', async () => {
    const { whatsappOperationsCursor } = await import('../../lib/whatsapp-operations');
    expect(whatsappOperationsCursor({ ...emptyPage, nextAfter: '2026-10-03T09:00:00Z', nextAfterId: requestKey }))
      .toBe(`2026-10-03T09:00:00Z|${requestKey}`);
  });
});

describe('WSP-002 consent acknowledgement corresponds to the submitted decision', () => {
  it.each(['memberId', 'requestKey'] as const)(
    'refuses malformed UUID %s before RPC', async (field) => {
      const route = await import('../api/members/[memberId]/whatsapp-consent/route');
      for (const malformed of [
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        '55555555-5555-4555-8555-55555555555',
        '555555555-555-4555-8555-555555555555',
      ]) {
        boundary.rpc.mockClear();
        boundary.rpc.mockResolvedValue({ data: decision, error: null });
        const body = {
          memberId, purpose: 'service', granted: true, noticeVersion: decision.noticeVersion,
          source: 'recipient_verified', requestKey, [field]: malformed,
        };
        const request = new Request('https://gymloop.test/api/whatsapp-consent', {
          method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
        });
        const response = await route.POST(request, {
          params: Promise.resolve({ memberId: field === 'memberId' ? malformed : memberId }),
        });
        expect.soft(response.status).toBe(400);
        expect.soft(await response.json()).toMatchObject({ ok: false, error: { code: 'invalid_request' } });
        expect.soft(boundary.rpc).not.toHaveBeenCalled();
      }
    },
  );

  it.each(['member', 'staff'] as const)('%s confirms a matching successful RPC decision', async (audience) => {
    boundary.rpc.mockResolvedValue({ data: decision, error: null });
    boundary.readRequestIdentity.mockResolvedValue({ identity: audience === 'member' ? member : owner, supabase: { rpc: boundary.rpc } });
    const body = audience === 'member'
      ? { purpose: 'service', granted: true, noticeVersion: decision.noticeVersion }
      : { memberId, purpose: 'service', granted: true, noticeVersion: decision.noticeVersion, source: 'recipient_verified', requestKey };
    const request = new Request('https://gymloop.test/api/whatsapp-consent', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    const route = audience === 'member'
      ? await import('../api/member/whatsapp-consent/route')
      : await import('../api/members/[memberId]/whatsapp-consent/route');
    const response = await route.POST(request, { params: Promise.resolve({ memberId }) });
    expect((await response.json()).ok).toBe(true);
    expect(boundary.rpc).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['member', { purpose: 'marketing' }], ['member', { granted: false }],
    ['staff', { purpose: 'marketing' }], ['staff', { granted: false }],
  ] as const)('%s cannot confirm a different purpose/grant decision: %j', async (audience, mismatch) => {
    boundary.rpc.mockResolvedValue({ data: { ...decision, ...mismatch }, error: null });
    boundary.readRequestIdentity.mockResolvedValue({ identity: audience === 'member' ? member : owner, supabase: { rpc: boundary.rpc } });
    const body = audience === 'member'
      ? { purpose: 'service', granted: true, noticeVersion: decision.noticeVersion }
      : { memberId, purpose: 'service', granted: true, noticeVersion: decision.noticeVersion, source: 'recipient_verified', requestKey };
    const request = new Request('https://gymloop.test/api/whatsapp-consent', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
    const route = audience === 'member'
      ? await import('../api/member/whatsapp-consent/route')
      : await import('../api/members/[memberId]/whatsapp-consent/route');
    const response = await route.POST(request, { params: Promise.resolve({ memberId }) });
    expect(boundary.rpc).toHaveBeenCalledTimes(1);
    expect((await response.json()).ok).toBe(false);
    expect(response.status).toBeGreaterThanOrEqual(400);
  });
});
