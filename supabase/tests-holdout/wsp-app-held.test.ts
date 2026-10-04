// Independent WSP app-layer holdout, authored from the frozen transport
// contract only (openspec/changes/whatsapp-channel/proposal.md,
// provider-wallet-amendment.md, wave-c serial declarations). No
// public application packet wave-c-app-verification-declarations.md fixes
// mechanical module, loader, cursor, row and envelope spellings. Behavior
// assertions retain the original independent holdout requirements; this
// suite is never adapted from implementation observations.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// Module paths the frozen contract implies; intentionally resolved at
// runtime so a missing implementation is a clean per-test RED, never a
// compile-time escape hatch.
const targets = {
  lib: '../../apps/web/lib/whatsapp',
  operations: '../../apps/web/lib/whatsapp-operations',
  memberSettingsPage: '../../apps/web/app/member/whatsapp-consent/page',
  memberConsent: '../../apps/web/app/api/member/whatsapp-consent/route',
  staffConsent: '../../apps/web/app/api/members/[memberId]/whatsapp-consent/route',
  dispatch: '../../apps/web/app/api/notifications/[id]/whatsapp-dispatch/route',
} as const;

type MemberWhatsappSettings = {
  service: boolean; marketing: boolean; recipientKind: string;
  maskedPhone: string; noticeVersion: string; available: boolean;
};
type WhatsappConsentResult = {
  consentId: string; purpose: string; granted: boolean;
  noticeVersion: string; recordedAt: string;
};
type WhatsappOperationRow = {
  notificationId: string; memberId: string; memberName: string; recipientKind: string; templateName: string;
  status: string; scheduledFor: string; sentAt: string | null;
  deliveredAt: string | null; failedAt: string | null; failedReason: string | null;
  optedOutAt: string | null; optedOutReason: string | null;
  providerReadAt: string | null; outcomeUnknown: boolean;
  maskedPhone: string | null; refusal: string | null;
};
type WhatsappOperationsScreen = {
  operations: WhatsappOperationRow[];
  nextAfter: string | null; nextAfterId: string | null;
  wallet: { balancePaise: string; currency: string } | null;
  chargedTotalPaise: string | null;
  errorMessage: string | null;
};
type LibExports = {
  whatsappConsentWriteResult(data: unknown): WhatsappConsentResult | null;
  memberWhatsappSettings(data: unknown): MemberWhatsappSettings | null;
};
type MemberRoute = { POST(request: Request): Promise<Response> };
type StaffConsentRoute = { POST(request: Request, context: { params: Promise<{ memberId: string }> }): Promise<Response> };
type DispatchRoute = { POST(request: Request, context: { params: Promise<{ id: string }> }): Promise<Response> };

const tas = <T,>(value: unknown): T => value as T;
const json = (body: unknown): Request =>
  new Request('https://gymloop.test/wsp-held', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
  });

const ids = {
  tenant: '80800000-0000-4000-8000-000000000001',
  user: '80800000-0000-4000-8000-000000000002',
  member: '80800000-0000-4000-8000-000000000003',
  staff: '80800000-0000-4000-8000-000000000004',
  trainer: '80800000-0000-4000-8000-000000000005',
  notification: '80800000-0000-4000-8000-000000000006',
  consent: '80800000-0000-4000-8000-000000000007',
  requestKey: '80800000-0000-4000-8000-000000000008',
  cursorAt: '2026-10-03T09:00:00.000Z',
  cursorId: '80800000-0000-4000-8000-000000000009',
};

// ─── Settings validator and member loader ────────────────────────────────────

// Observe the real page's original validator result and rendered error text.
async function observeMemberWhatsappSettingsPage() {
  const lib = tas<LibExports>(await import(targets.lib));
  // spyOn calls through to the original validator; no replacement implementation.
  const validator = vi.spyOn(lib, 'memberWhatsappSettings');
  let tree: unknown;
  let settings: MemberWhatsappSettings | null = null;
  try {
    const page = tas<{ default(): Promise<unknown> }>(await import(targets.memberSettingsPage));
    tree = await page.default();
    const result = validator.mock.results.at(-1);
    if (result?.type === 'return') settings = result.value;
  } finally {
    validator.mockRestore();
  }
  const renderedText: string[] = [];
  const walk = (node: unknown): void => {
    if (typeof node === 'string') { renderedText.push(node); return; }
    if (Array.isArray(node)) { node.forEach(walk); return; }
    if (node === null || typeof node !== 'object') return;
    const record = tas<Record<string, unknown>>(node);
    // Observe actual props/children, without invoking components or inventing data.
    for (const [key, value] of Object.entries(record)) {
      if (key !== 'type' && key !== '_owner' && key !== '_store') walk(value);
    }
  };
  walk(tree);
  const errorMessage = renderedText.find(value =>
    /unavailable|could not|unable|error|not available|failed/i.test(value)) ?? null;
  return { settings, errorMessage };
}

describe('held member WhatsApp settings boundary', () => {
  it.each([
    '+91 80955 50001',
    '+91 (80955)-50001',
    '•• +91 80955 50001',
    '+91 80•955•50•001',
  ])('concealment rejects all visible phone digits together: %s', async maskedPhone => {
    const lib = tas<LibExports>(await import(targets.lib));
    expect(lib.memberWhatsappSettings({ service: true, marketing: false,
      recipientKind: 'self', maskedPhone, noticeVersion: 'wsp-v1', available: true })).toBeNull();
  }, 20_000);

  it.each(['+91 •••• 417', '+91 **** 862'])('legitimate settings concealment survives unchanged: %s', async maskedPhone => {
    const lib = tas<LibExports>(await import(targets.lib));
    const data = { service: false, marketing: false, recipientKind: 'guardian',
      maskedPhone, noticeVersion: 'wsp-v1', available: true };
    expect(lib.memberWhatsappSettings(data)).toEqual(data);
  }, 20_000);
  it('accepts the exact safe projection', async () => {
    const lib = tas<LibExports>(await import(targets.lib));
    const value: MemberWhatsappSettings = {
      service: true, marketing: false, recipientKind: 'self',
      maskedPhone: '+91 •••• 001', noticeVersion: 'wsp-v1', available: true,
    };
    expect(lib.memberWhatsappSettings(value)).toEqual(value);
  }, 20_000);

  it.each([
    ['extra raw phone', { service: true, marketing: false, recipientKind: 'self', maskedPhone: '+91 •••• 001', noticeVersion: 'wsp-v1', available: true, phone: '+918095550001' }],
    ['consent history smuggled', { service: true, marketing: false, recipientKind: 'self', maskedPhone: 'x', noticeVersion: 'wsp-v1', available: true, consents: [{ purpose: 'marketing', granted: true, recordedAt: '2026-10-01T00:00:00Z' }] }],
    ['missing notice version', { service: true, marketing: false, recipientKind: 'self', maskedPhone: 'x', available: true }],
    ['full number in mask', { service: true, marketing: false, recipientKind: 'self', maskedPhone: '+918095550001', noticeVersion: 'wsp-v1', available: true }],
    ['numeric mask', { service: true, marketing: false, recipientKind: 'self', maskedPhone: 91, noticeVersion: 'wsp-v1', available: true }],
    ['wrong recipient kind', { service: true, marketing: false, recipientKind: 'guardian_raw', maskedPhone: 'x', noticeVersion: 'wsp-v1', available: true }],
  ])('refuses %s', async (_label, data) => {
    const lib = tas<LibExports>(await import(targets.lib));
    expect(lib.memberWhatsappSettings(data)).toBeNull();
  }, 20_000);

  it('member loader reads through requireAudience and never fabricates availability', async () => {
    const rpc = vi.fn();
    const requireAudience = vi.fn().mockResolvedValue({
      supabase: { rpc }, identity: { kind: 'member', userId: ids.user, tenantId: ids.tenant, memberId: ids.member },
    });
    vi.doMock('../../apps/web/lib/identity-session', () => ({ requireAudience }));
    const ok: MemberWhatsappSettings = { service: false, marketing: false, recipientKind: 'guardian', maskedPhone: '+91 •••• 002', noticeVersion: 'wsp-v1', available: true };
    rpc.mockResolvedValueOnce({ data: ok, error: null });
    await expect(observeMemberWhatsappSettingsPage()).resolves.toEqual({ settings: ok, errorMessage: null });
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc.mock.calls[0]?.[0]).toBe('read_member_whatsapp_settings');
    rpc.mockResolvedValueOnce({ data: null, error: { code: '42501', message: 'Held denial' } });
    const failed = await observeMemberWhatsappSettingsPage();
    expect(failed.settings).toBeNull();
    expect(failed.errorMessage).not.toBeNull();
    expect(failed).not.toMatchObject({ settings: { available: true } });
    vi.doUnmock('../../apps/web/lib/identity-session');
  }, 20_000);
});

// ─── Desk operations reader: role split, privacy, honest facts ───────────────

const opRow = (overrides: Partial<WhatsappOperationRow> = {}): WhatsappOperationRow => ({
  notificationId: ids.notification, memberId: ids.member, memberName: 'Held Member', recipientKind: 'self', templateName: 'renewal',
  status: 'sent', scheduledFor: ids.cursorAt, sentAt: ids.cursorAt, deliveredAt: null, failedAt: null,
  failedReason: null, optedOutAt: null, optedOutReason: null, providerReadAt: null,
  outcomeUnknown: false, maskedPhone: '+91 •••• 001', refusal: null, ...overrides,
});
const opPayload = (wallet: WhatsappOperationsScreen['wallet'], rows: WhatsappOperationRow[] = [opRow()], extra: Record<string, unknown> = {}) => ({
  operations: rows, nextAfter: null, nextAfterId: null, wallet,
  statusCounts: { accepted: '1', delivered: '0', read: '0', unknown: '1' },
  templateBlockers: [], chargedTotals: wallet === null ? null : { chargedPaise: '0' }, ...extra,
});

describe('held WhatsApp operations reader', () => {
  let rpc: ReturnType<typeof vi.fn>;
  let requireAudience: ReturnType<typeof vi.fn>;
  const load = async (params: Record<string, string> = {}) => {
    const lib = tas<{ loadWhatsappOperations(params: { cursor?: string }): Promise<{
      view: (Omit<WhatsappOperationsScreen, 'chargedTotalPaise' | 'errorMessage'> & {
        chargedTotals: { chargedPaise: string } | null;
      }) | null; errorMessage: string | null; isPreview: boolean;
    }> }>(await import(targets.operations));
    const result = await lib.loadWhatsappOperations(params);
    // Mechanical projection of the public loader wrapper for the original
    // assertions; no validation, truth repair or currency conversion here.
    return {
      ...result.view,
      operations: result.view?.operations ?? [],
      nextAfter: result.view?.nextAfter ?? null,
      nextAfterId: result.view?.nextAfterId ?? null,
      wallet: result.view?.wallet ?? null,
      chargedTotalPaise: result.view?.chargedTotals?.chargedPaise ?? null,
      errorMessage: result.errorMessage,
    };
  };
  beforeEach(() => {
    vi.resetModules();
    rpc = vi.fn();
    requireAudience = vi.fn().mockResolvedValue({
      supabase: { rpc }, identity: { kind: 'staff', userId: ids.user, tenantId: ids.tenant, staffId: ids.staff, role: 'gym_owner' },
    });
    vi.doMock('../../apps/web/lib/identity-session', () => ({ requireAudience }));
  });
  afterEach(() => { vi.doUnmock('../../apps/web/lib/identity-session'); });

  it.each([
    '+91 80955 50001',
    '+91 (80955)-50001',
    '•• +91 80955 50001',
    '+91 80•955•50•001',
  ])('operations concealment refuses grouped or decorated full phone: %s', async maskedPhone => {
    rpc.mockResolvedValue({ data: opPayload(null, [opRow({ maskedPhone })]), error: null });
    const lib = tas<{ loadWhatsappOperations(params: { cursor?: string }): Promise<unknown> }>(await import(targets.operations));
    await expect(lib.loadWhatsappOperations({})).resolves.toEqual({
      view: null, errorMessage: 'The WhatsApp operations list could not be loaded.', isPreview: false,
    });
    expect(rpc).toHaveBeenCalledTimes(1);
  }, 20_000);

  it.each(['+91 •••• 417', '+91 **** 862'])('legitimate operations concealment survives unchanged: %s', async maskedPhone => {
    rpc.mockResolvedValue({ data: opPayload(null, [opRow({ maskedPhone })]), error: null });
    const screen = await load();
    expect(screen.errorMessage).toBeNull();
    expect(screen.operations).toEqual([opRow({ maskedPhone })]);
  }, 20_000);

  it.each([
    ['bare date', '2026-10-03'],
    ['numeric date', '42'],
    ['missing timezone', '2026-10-03T09:00:00'],
    ['non-leap February', '2026-02-29T09:00:00Z'],
    ['April overflow', '2026-04-31T09:00:00+05:30'],
    ['zero month', '2026-00-03T09:00:00Z'],
    ['month overflow', '2026-13-03T09:00:00Z'],
    ['zero day', '2026-10-00T09:00:00Z'],
    ['hour overflow', '2026-10-03T25:00:00Z'],
    ['minute overflow', '2026-10-03T09:60:00Z'],
    ['offset overflow', '2026-10-03T09:00:00+25:00'],
    ['trailing text', '2026-10-03T09:00:00Z extra'],
  ])('malformed calendar cursor %s refuses before RPC without restarting', async (_label, timestamp) => {
    rpc.mockResolvedValue({ data: opPayload(null), error: null });
    const lib = tas<{ loadWhatsappOperations(params: { cursor: string }): Promise<unknown> }>(await import(targets.operations));
    await expect(lib.loadWhatsappOperations({ cursor: `${timestamp}|${ids.cursorId}` })).resolves.toEqual({
      view: null, errorMessage: 'The WhatsApp operations list could not be loaded.', isPreview: false,
    });
    expect(rpc).not.toHaveBeenCalled();
  }, 20_000);

  it.each(['2024-02-29T23:45:12.123+05:30', '2026-10-03T04:15:00-04:00'])('valid timezone cursor is preserved verbatim: %s', async timestamp => {
    rpc.mockResolvedValue({ data: opPayload(null), error: null });
    const screen = await load({ cursor: `${timestamp}|${ids.cursorId}` });
    expect(screen.errorMessage).toBeNull();
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc.mock.calls[0]).toEqual(['read_whatsapp_operations', {
      p_after_created_at: timestamp, p_after_id: ids.cursorId, p_limit: 100,
    }]);
  }, 20_000);

  it('owner projection surfaces the wallet amounts and cursor envelope', async () => {
    rpc.mockResolvedValue({ data: opPayload({ balancePaise: '450000', currency: 'INR' }), error: null });
    await expect(load()).resolves.toMatchObject({
      operations: [opRow()], nextAfter: null, nextAfterId: null,
      wallet: { balancePaise: '450000', currency: 'INR' }, chargedTotalPaise: '0', errorMessage: null,
    });
    expect(rpc.mock.calls[0]?.[0]).toBe('read_whatsapp_operations');
  }, 20_000);

  it('desk identity must not receive wallet amounts even when the read leaks them', async () => {
    requireAudience.mockResolvedValue({
      supabase: { rpc }, identity: { kind: 'staff', userId: ids.user, tenantId: ids.tenant, staffId: ids.staff, role: 'front_desk' },
    });
    rpc.mockResolvedValue({ data: opPayload({ balancePaise: '450000', currency: 'INR' }), error: null });
    const screen = await load();
    expect(screen.wallet).toBeNull();
    expect(screen.chargedTotalPaise).toBeNull();
    expect(JSON.stringify(screen)).not.toContain('450000');
  }, 20_000);

  it('trainer identity is refused before any read', async () => {
    requireAudience.mockResolvedValue({
      supabase: { rpc }, identity: { kind: 'staff', userId: ids.user, tenantId: ids.tenant, staffId: ids.trainer, role: 'trainer' },
    });
    const screen = await load();
    expect(rpc).not.toHaveBeenCalled();
    expect(screen.errorMessage).not.toBeNull();
    expect(screen.operations).toEqual([]);
  }, 20_000);

  const breachRows: Array<[string, unknown]> = [
    ['raw phone in row', opPayload(null, [opRow({ maskedPhone: '+918095550001' })])],
    ['provider message id in row', opPayload(null, [{ ...opRow(), providerMessageId: 'wamid.HELD' } as WhatsappOperationRow])],
    ['dispatch ticket in row', { ...opPayload(null), ticket: 'ticket-hex' }],
    ['whatsapp read posing as clicked_at', { ...opPayload(null, [opRow({ status: 'delivered', deliveredAt: ids.cursorAt })]), clickedAt: ids.cursorAt }],
  ];
  it.each(breachRows)('%s refuses the whole screen', async (_label, data) => {
    rpc.mockResolvedValue({ data, error: null });
    const screen = await load();
    expect(screen.errorMessage).not.toBeNull();
    expect(screen.operations).toEqual([]);
    expect(JSON.stringify(screen)).not.toContain('+918095550001');
  }, 20_000);

  it('delivered status without delivered evidence is refused, never rendered as truth', async () => {
    rpc.mockResolvedValue({ data: opPayload(null, [opRow({ status: 'delivered', deliveredAt: null })]), error: null });
    const screen = await load();
    expect(screen.errorMessage).not.toBeNull();
  }, 20_000);

  it('sent status stays unknown, not delivered or read', async () => {
    rpc.mockResolvedValue({ data: opPayload(null, [opRow({ status: 'sent', deliveredAt: null, providerReadAt: null })]), error: null });
    const screen = await load();
    expect(screen.errorMessage).toBeNull();
    expect(screen.operations[0]).toMatchObject({ status: 'sent', deliveredAt: null, providerReadAt: null });
    expect(JSON.stringify(screen)).not.toMatch(/"delivered"\s*:\s*true|"read"\s*:\s*true/);
  }, 20_000);

  it.each([
    ['default within bound', {}, null, null],
    ['explicit cursor', { cursor: `${ids.cursorAt}|${ids.cursorId}` }, ids.cursorAt, ids.cursorId],
  ])('%s produces one exact keyset call', async (_label, params, after, afterId) => {
    rpc.mockResolvedValue({ data: opPayload(null), error: null });
    await load(params);
    expect(rpc).toHaveBeenCalledTimes(1);
    const args = tas<{ p_after_created_at: string | null; p_after_id: string | null; p_limit: number }>(rpc.mock.calls[0]?.[1]);
    expect(args.p_after_created_at).toBe(after);
    expect(args.p_after_id).toBe(afterId);
    expect(args.p_limit).toBeLessThanOrEqual(100);
  }, 20_000);

  it('oversized page request cannot exceed the bound', async () => {
    rpc.mockResolvedValue({ data: opPayload(null), error: null });
    await load({ limit: '500' });
    const args = tas<{ p_limit: number }>(rpc.mock.calls[0]?.[1]);
    expect(args.p_limit).toBeLessThanOrEqual(100);
  }, 20_000);

  it('half a cursor is refused before the read rather than restarting the page', async () => {
    const lib = tas<{ loadWhatsappOperations(params: { cursor: string }): Promise<unknown> }>(await import(targets.operations));
    await expect(lib.loadWhatsappOperations({ cursor: ids.cursorAt })).resolves.toEqual({
      view: null, errorMessage: 'The WhatsApp operations list could not be loaded.', isPreview: false,
    });
    expect(rpc).not.toHaveBeenCalled();
  }, 20_000);

  it('cursor id without a timestamp is refused too', async () => {
    const lib = tas<{ loadWhatsappOperations(params: { cursor: string }): Promise<unknown> }>(await import(targets.operations));
    await expect(lib.loadWhatsappOperations({ cursor: `|${ids.cursorId}` })).resolves.toEqual({
      view: null, errorMessage: 'The WhatsApp operations list could not be loaded.', isPreview: false,
    });
    expect(rpc).not.toHaveBeenCalled();
  }, 20_000);

  it('failed or empty reads never fabricate rows, counts or money', async () => {
    rpc.mockResolvedValue({ data: null, error: { code: '42501', message: 'Held denial' } });
    const screen = await load();
    expect(screen.errorMessage).not.toBeNull();
    expect(screen.operations).toEqual([]);
    expect(screen.wallet).toBeNull();
  }, 20_000);

  it.each([
    ['numeric count', opPayload(null, [opRow({ status: 'sent' })]), { chargedTotals: { chargedPaise: 100 } }],
    ['fractional total', opPayload({ balancePaise: '1', currency: 'INR' }), { chargedTotals: { chargedPaise: '10.5' } }],
    ['credit-labelled wallet', opPayload(null), { wallet: { balanceCredits: '4500', currency: 'INR' } }],
    ['unknown currency', opPayload({ balancePaise: '1', currency: 'USD' }), { chargedTotals: { chargedPaise: '10' } }],
  ])('money field abuse %s is refused, never rendered', async (_label, base, extra) => {
    rpc.mockResolvedValue({ data: { ...opPayload(null), ...base, ...extra }, error: null });
    const screen = await load();
    if (screen.errorMessage === null) {
      expect(JSON.stringify(screen)).not.toContain('balanceCredits');
      expect(screen.chargedTotalPaise).not.toMatch(/^10\.5$/);
    } else {
      expect(screen.operations).toEqual([]);
    }
  }, 20_000);

  it('the loader performs no mutation rpc at all', async () => {
    rpc.mockResolvedValue({ data: opPayload(null), error: null });
    await load();
    for (const call of rpc.mock.calls) expect(call[0]).toBe('read_whatsapp_operations');
  }, 20_000);
});

// ─── Member consent route ────────────────────────────────────────────────────

describe('held member WhatsApp consent route', () => {
  let memberSession: ReturnType<typeof vi.fn>;
  const post = async (body: unknown) => {
    const route = tas<MemberRoute>(await import(targets.memberConsent));
    return route.POST(json(body));
  };
  beforeEach(() => {
    vi.resetModules();
    memberSession = vi.fn().mockResolvedValue({
      session: { supabase: { rpc: vi.fn() }, userId: ids.user, tenantId: ids.tenant, memberId: ids.member },
    });
    vi.doMock('../../apps/web/lib/api', async () => ({
      ...await vi.importActual<Record<string, unknown>>('../../apps/web/lib/api'),
      memberSession,
    }));
  });
  afterEach(() => { vi.doUnmock('../../apps/web/lib/api'); });
  const rpcOfMember = (): ReturnType<typeof vi.fn> =>
    tas<{ session?: { supabase: { rpc: ReturnType<typeof vi.fn> } } } | undefined>(memberSession.mock.results[0]?.value)?.session?.supabase.rpc ?? vi.fn();
  const valid = { purpose: 'service', granted: true, noticeVersion: 'wsp-v1' };

  it('member grant reaches set_member_whatsapp_consent with exact args', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { consentId: ids.consent, purpose: 'service', granted: true, noticeVersion: 'wsp-v1', recordedAt: ids.cursorAt }, error: null,
    });
    memberSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user, tenantId: ids.tenant, memberId: ids.member } });
    const reply = await post(valid);
    expect(reply.status).toBeGreaterThanOrEqual(200);
    expect(reply.status).toBeLessThan(300);
    expect(await reply.json()).toMatchObject({ ok: true });
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc.mock.calls[0]?.[0]).toBe('set_member_whatsapp_consent');
    expect(rpc.mock.calls[0]?.[1]).toEqual({ p_purpose: 'service', p_granted: true, p_notice_version: 'wsp-v1' });
  }, 20_000);

  const bodyRows: Array<[string, Record<string, unknown>]> = [
    ['missing notice version', { purpose: 'service', granted: true }],
    ['missing granted decision', { purpose: 'service', noticeVersion: 'wsp-v1' }],
    ['string granted', { ...valid, granted: 'yes' }],
    ['unknown purpose', { ...valid, purpose: 'whatsapp' }],
    ['staff provenance field', { ...valid, source: 'desk' }],
    ['extra request key', { ...valid, requestKey: ids.requestKey }],
  ];
  it.each(bodyRows)('forged or incomplete body %s is refused before the command', async (_label, body) => {
    const reply = await post(body);
    expect(reply.status).toBeGreaterThanOrEqual(400);
    expect(reply.status).toBeLessThan(500);
    expect(await reply.json()).toMatchObject({ ok: false });
    expect(rpcOfMember()).not.toHaveBeenCalled();
  }, 20_000);

  it('marketing purpose is a member-settable channel permission', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { consentId: ids.consent, purpose: 'marketing', granted: false, noticeVersion: 'wsp-v1', recordedAt: ids.cursorAt }, error: null,
    });
    memberSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user, tenantId: ids.tenant, memberId: ids.member } });
    const reply = await post({ purpose: 'marketing', granted: false, noticeVersion: 'wsp-v1' });
    expect(reply.status).toBeLessThan(300);
    expect(rpc.mock.calls[0]?.[1]).toMatchObject({ p_purpose: 'marketing', p_granted: false });
  }, 20_000);

  it('signed-out refusal passes through untouched', async () => {
    memberSession.mockResolvedValue({ failure: new Response(JSON.stringify({ ok: false, error: { code: 'not_signed_in', message: 'x' } }), { status: 401 }) });
    const reply = await post(valid);
    expect(reply.status).toBe(401);
    expect(rpcOfMember()).not.toHaveBeenCalled();
  }, 20_000);

  it('replay conflict maps to the idempotency refusal, not a fabricated second grant', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: 'GL068', message: 'Held replay' } });
    memberSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user, tenantId: ids.tenant, memberId: ids.member } });
    const reply = await post(valid);
    expect(reply.status).toBe(409);
    expect(await reply.json()).toMatchObject({ ok: false, error: { code: 'idempotency_conflict' } });
  }, 20_000);

  const badConsentResults: Array<[string, Record<string, unknown>]> = [
    ['missing recordedAt', { consentId: ids.consent, purpose: 'service', granted: true, noticeVersion: 'wsp-v1' }],
    ['provider id echoed', { consentId: ids.consent, purpose: 'service', granted: true, noticeVersion: 'wsp-v1', recordedAt: ids.cursorAt, providerMessageId: 'wamid.HELD' }],
    ['purpose echo mismatch', { consentId: ids.consent, purpose: 'marketing', granted: true, noticeVersion: 'wsp-v1', recordedAt: ids.cursorAt }],
  ];
  it.each(badConsentResults)('malformed RPC result %s is refused, never normalized', async (_label, data) => {
    const rpc = vi.fn().mockResolvedValue({ data, error: null });
    memberSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user, tenantId: ids.tenant, memberId: ids.member } });
    const reply = await post(valid);
    expect(reply.status).toBeGreaterThanOrEqual(400);
    expect(await reply.json()).toMatchObject({ ok: false });
  }, 20_000);
});

// ─── Staff consent recorder and dispatch routes ──────────────────────────────

describe('held front-office WhatsApp routes', () => {
  let staffSession: ReturnType<typeof vi.fn>;
  beforeEach(() => {
    vi.resetModules();
    staffSession = vi.fn().mockResolvedValue({
      session: { supabase: { rpc: vi.fn() }, userId: ids.user, tenantId: ids.tenant, staffId: ids.staff, role: 'gym_manager' },
    });
    vi.doMock('../../apps/web/lib/api', async () => ({
      ...await vi.importActual<Record<string, unknown>>('../../apps/web/lib/api'),
      staffSession,
    }));
  });
  afterEach(() => { vi.doUnmock('../../apps/web/lib/api'); });
  const rpcOfSession = (): ReturnType<typeof vi.fn> =>
    tas<{ session?: { supabase: { rpc: ReturnType<typeof vi.fn> } } } | undefined>(staffSession.mock.results[0]?.value)?.session?.supabase.rpc ?? vi.fn();
  const dispatchValid = { requestKey: ids.requestKey };
  const consentValid = { memberId: ids.member, purpose: 'service', granted: true, noticeVersion: 'wsp-v1', source: 'desk-call', requestKey: ids.requestKey };

  it.each([
    ['short hex', 'abcd'],
    ['compact hex', '80800000000040008000000000000003'],
    ['oversized tail', '80800000-0000-4000-8000-000000000003aa'],
    ['shifted separator', '8080000-00000-4000-8000-000000000003'],
    ['extra separator', '80800000--0000-4000-8000-000000000003'],
  ])('recorder canonical member UUID rejects %s before RPC', async (_label, memberId) => {
    const rpc = vi.fn().mockResolvedValue({ data: {
      consentId: ids.consent, purpose: 'service', granted: true,
      noticeVersion: 'wsp-v1', recordedAt: ids.cursorAt,
    }, error: null });
    staffSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user,
      tenantId: ids.tenant, staffId: ids.staff, role: 'front_desk' } });
    const route = tas<StaffConsentRoute>(await import(targets.staffConsent));
    const reply = await route.POST(json({ ...consentValid, memberId }), { params: Promise.resolve({ memberId }) });
    expect.soft(reply.status).toBe(400);
    expect.soft(await reply.json()).toMatchObject({ ok: false, error: { code: 'invalid_request' } });
    expect(rpc).not.toHaveBeenCalled();
  }, 20_000);

  it.each([
    ['short hex', 'feed'],
    ['compact hex', '80800000000040008000000000000008'],
    ['oversized tail', '80800000-0000-4000-8000-000000000008ab'],
    ['shifted separator', '808000000-000-4000-8000-000000000008'],
    ['extra separator', '80800000-0000--4000-8000-000000000008'],
  ])('recorder canonical request UUID rejects %s before RPC', async (_label, requestKey) => {
    const rpc = vi.fn().mockResolvedValue({ data: {
      consentId: ids.consent, purpose: 'service', granted: true,
      noticeVersion: 'wsp-v1', recordedAt: ids.cursorAt,
    }, error: null });
    staffSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user,
      tenantId: ids.tenant, staffId: ids.staff, role: 'front_desk' } });
    const route = tas<StaffConsentRoute>(await import(targets.staffConsent));
    const reply = await route.POST(json({ ...consentValid, requestKey }), { params: Promise.resolve({ memberId: ids.member }) });
    expect.soft(reply.status).toBe(400);
    expect.soft(await reply.json()).toMatchObject({ ok: false, error: { code: 'invalid_request' } });
    expect(rpc).not.toHaveBeenCalled();
  }, 20_000);

  it.each([
    ['short hex', 'cafe'],
    ['compact hex', '80800000000040008000000000000008'],
    ['oversized tail', '80800000-0000-4000-8000-000000000008cd'],
    ['shifted separator', '80800000-0000-400-08000-000000000008'],
    ['extra separator', '80800000-0000-4000--8000-000000000008'],
  ])('dispatch canonical request UUID rejects %s before RPC', async (_label, requestKey) => {
    const rpc = vi.fn().mockResolvedValue({ data: {
      notificationId: ids.notification, queued: false, reason: 'communication_opted_out',
    }, error: null });
    staffSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user,
      tenantId: ids.tenant, staffId: ids.staff, role: 'front_desk' } });
    const route = tas<DispatchRoute>(await import(targets.dispatch));
    const reply = await route.POST(json({ requestKey }), { params: Promise.resolve({ id: ids.notification }) });
    expect.soft(reply.status).toBe(400);
    expect.soft(await reply.json()).toMatchObject({ ok: false, error: { code: 'invalid_request' } });
    expect(rpc).not.toHaveBeenCalled();
  }, 20_000);

  it('desk recorder admits only front-office roles and sends the exact command', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { consentId: ids.consent, purpose: 'service', granted: true, noticeVersion: 'wsp-v1', recordedAt: ids.cursorAt }, error: null,
    });
    staffSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user, tenantId: ids.tenant, staffId: ids.staff, role: 'front_desk' } });
    const route = tas<StaffConsentRoute>(await import(targets.staffConsent));
    const reply = await route.POST(json(consentValid), { params: Promise.resolve({ memberId: ids.member }) });
    expect(reply.status).toBeLessThan(300);
    expect(staffSession.mock.calls[0]?.[0]).toEqual(expect.not.arrayContaining(['trainer']));
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc.mock.calls[0]).toEqual(['record_whatsapp_consent', {
      p_member_id: ids.member, p_purpose: 'service', p_granted: true,
      p_notice_version: 'wsp-v1', p_source: 'desk-call', p_request_key: ids.requestKey,
    }]);
  }, 20_000);

  const recorderBadRows: Array<[string, Record<string, unknown>]> = [
    ['missing request key', { memberId: ids.member, purpose: 'service', granted: true, noticeVersion: 'wsp-v1', source: 'desk' }],
    ['missing notice version', { memberId: ids.member, purpose: 'service', granted: true, source: 'desk', requestKey: ids.requestKey }],
    ['default-on attempt', { memberId: ids.member, purpose: 'service', noticeVersion: 'wsp-v1', source: 'desk', requestKey: ids.requestKey }],
    ['unset granted decision', { ...consentValid, granted: undefined }],
  ];
  it.each(recorderBadRows)('recorder refuses %s, never defaulting a grant', async (_label, body) => {
    const route = tas<StaffConsentRoute>(await import(targets.staffConsent));
    const reply = await route.POST(json(body), { params: Promise.resolve({ memberId: ids.member }) });
    expect(reply.status).toBeGreaterThanOrEqual(400);
    expect(reply.status).toBeLessThan(500);
    expect(rpcOfSession()).not.toHaveBeenCalled();
  }, 20_000);

  it('recorder refuses an erased provenance-free withdrawal shape', async () => {
    await staffRecordWith({ memberId: ids.member, purpose: 'marketing', granted: false, noticeVersion: 'wsp-v1', requestKey: ids.requestKey });
  }, 20_000);
  async function staffRecordWith(body: Record<string, unknown>) {
    const route = tas<StaffConsentRoute>(await import(targets.staffConsent));
    const reply = await route.POST(json(body), { params: Promise.resolve({ memberId: ids.member }) });
    expect(reply.status).toBeGreaterThanOrEqual(400);
    expect(rpcOfSession()).not.toHaveBeenCalled();
  }

  it('recorder marks the write impersonation-hostile', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { consentId: ids.consent, purpose: 'service', granted: true,
        noticeVersion: 'wsp-v1', recordedAt: ids.cursorAt }, error: null,
    });
    staffSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user,
      tenantId: ids.tenant, staffId: ids.staff, role: 'gym_manager' } });
    staffSession.mockClear();
    const route = tas<StaffConsentRoute>(await import(targets.staffConsent));
    await route.POST(json(consentValid), { params: Promise.resolve({ memberId: ids.member }) });
    const options = tas<{ completeWrongAudience?: string } | undefined>(staffSession.mock.calls[0]?.[1]);
    expect(options?.completeWrongAudience).toBe('forbidden');
  }, 20_000);

  it('non-uuid member path is refused before the command', async () => {
    const route = tas<StaffConsentRoute>(await import(targets.staffConsent));
    const reply = await route.POST(json(consentValid), { params: Promise.resolve({ memberId: 'not-a-uuid' }) });
    expect(reply.status).toBeGreaterThanOrEqual(400);
    expect(rpcOfSession()).not.toHaveBeenCalled();
  }, 20_000);

  it('dispatch admits only front-office staff and posts id plus key only', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { notificationId: ids.notification, queued: true, reason: null }, error: null,
    });
    staffSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user, tenantId: ids.tenant, staffId: ids.staff, role: 'front_desk' } });
    const route = tas<DispatchRoute>(await import(targets.dispatch));
    const reply = await route.POST(json(dispatchValid), { params: Promise.resolve({ id: ids.notification }) });
    expect(reply.status).toBeLessThan(300);
    expect(staffSession.mock.calls[0]?.[0]).toEqual(expect.not.arrayContaining(['trainer']));
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc.mock.calls[0]?.[0]).toBe('request_whatsapp_dispatch');
    expect(rpc.mock.calls[0]?.[1]).toEqual({ p_notification_id: ids.notification, p_request_key: ids.requestKey });
  }, 20_000);

  it('dispatch refusal is an honest queued:false envelope, not an error or a lie', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { notificationId: ids.notification, queued: false, reason: 'communication_opted_out' }, error: null,
    });
    staffSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user, tenantId: ids.tenant, staffId: ids.staff, role: 'front_desk' } });
    const route = tas<DispatchRoute>(await import(targets.dispatch));
    const reply = await route.POST(json(dispatchValid), { params: Promise.resolve({ id: ids.notification }) });
    expect(reply.status).toBeLessThan(300);
    expect(await reply.json()).toMatchObject({ ok: true, data: { queued: false } });
  }, 20_000);

  it('a wallet-funds error never becomes a fake queued send', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: null, error: { code: 'GL067', message: 'Held funds' } });
    staffSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user, tenantId: ids.tenant, staffId: ids.staff, role: 'front_desk' } });
    const route = tas<DispatchRoute>(await import(targets.dispatch));
    const reply = await route.POST(json(dispatchValid), { params: Promise.resolve({ id: ids.notification }) });
    expect(reply.status).toBeGreaterThanOrEqual(400);
    const body = tas<{ data?: { queued?: boolean } }>(await reply.json());
    expect(body.data?.queued).toBeUndefined();
  }, 20_000);

  const dispatchBadRows: Array<[string, Record<string, unknown>]> = [
    ['missing request key', {}],
    ['client cost', { ...dispatchValid, cost: '350' }],
    ['client recipient', { ...dispatchValid, recipient: '+918095550001' }],
    ['client provider id', { ...dispatchValid, providerMessageId: 'wamid.HELD' }],
  ];
  it.each(dispatchBadRows)('dispatch body abuse %s is refused before the command', async (_label, body) => {
    const route = tas<DispatchRoute>(await import(targets.dispatch));
    const reply = await route.POST(json(body), { params: Promise.resolve({ id: ids.notification }) });
    expect(reply.status).toBeGreaterThanOrEqual(400);
    expect(reply.status).toBeLessThan(500);
    expect(rpcOfSession()).not.toHaveBeenCalled();
  }, 20_000);

  const dispatchLeakRows: Array<[string, Record<string, unknown>]> = [
    ['accepted cost echoed', { notificationId: ids.notification, queued: true, reason: null, cost: '350' }],
    ['ticket echoed', { notificationId: ids.notification, queued: true, reason: null, ticket: 'ticket-hex' }],
  ];
  it.each(dispatchLeakRows)('dispatch result leaking %s is refused, never forwarded', async (_label, data) => {
    const rpc = vi.fn().mockResolvedValue({ data, error: null });
    staffSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user, tenantId: ids.tenant, staffId: ids.staff, role: 'front_desk' } });
    const route = tas<DispatchRoute>(await import(targets.dispatch));
    const reply = await route.POST(json(dispatchValid), { params: Promise.resolve({ id: ids.notification }) });
    expect(reply.status).toBeGreaterThanOrEqual(400);
  }, 20_000);

  it('a repeated dispatch replays the honest command twice, never suppressing the audit trail', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { notificationId: ids.notification, queued: true, reason: null }, error: null,
    });
    staffSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user, tenantId: ids.tenant, staffId: ids.staff, role: 'front_desk' } });
    const route = tas<DispatchRoute>(await import(targets.dispatch));
    await route.POST(json(dispatchValid), { params: Promise.resolve({ id: ids.notification }) });
    await route.POST(json(dispatchValid), { params: Promise.resolve({ id: ids.notification }) });
    expect(rpc).toHaveBeenCalledTimes(2);
  }, 20_000);

  it('the dispatch route never mints the manual WhatsApp action', async () => {
    const rpc = vi.fn().mockResolvedValue({
      data: { notificationId: ids.notification, queued: true, reason: null }, error: null,
    });
    staffSession.mockResolvedValue({ session: { supabase: { rpc }, userId: ids.user, tenantId: ids.tenant, staffId: ids.staff, role: 'front_desk' } });
    const route = tas<DispatchRoute>(await import(targets.dispatch));
    await route.POST(json(dispatchValid), { params: Promise.resolve({ id: ids.notification }) });
    for (const call of rpc.mock.calls) expect(call[0]).toBe('request_whatsapp_dispatch');
  }, 20_000);
});
