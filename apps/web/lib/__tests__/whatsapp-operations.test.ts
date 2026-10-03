import { describe, expect, it } from 'vitest';

/**
 * WSP WhatsApp surfaces' wire layer, authored from the frozen contract before
 * `apps/web/lib/whatsapp.ts` exists. Sources:
 * `openspec/changes/whatsapp-channel/proposal.md` (WSP-001..011, the RPC
 * table), the approved `provider-wallet-amendment.md`, and the frozen
 * mechanical declarations in `wave-c-delivery-declarations-draft.md` and
 * `wave-c-serial-freeze-declarations.md` (reader envelopes, role matrix,
 * bounds). The desk/owner field split mirrors `apps/web/lib/messages.ts`'s
 * already-converted wallet contract (`{balancePaise,currency}` — that
 * conversion is the primary's committed work and is not re-tested here).
 *
 * `lib/whatsapp.ts` is expected to export:
 *
 * - `memberWhatsappSettings(data: unknown): MemberWhatsappSettings | null` —
 *   `read_member_whatsapp_settings`' exact six keys: `service, marketing`
 *   (booleans expressing CHANNEL permission, not generic consent),
 *   `recipientKind` ('self' | 'guardian'), `maskedPhone` (string with the
 *   full number masked — never a bare E.164 phone), `noticeVersion`
 *   (string | null), `available` (boolean). No consent history, no full
 *   phone, no sibling data (WSP-001/010).
 * - `whatsappConsentWriteResult(data: unknown): WhatsappConsentWriteResult |
 *   null` — `set_member_whatsapp_consent` / `record_whatsapp_consent`'s
 *   exact five keys: `consentId, purpose, granted, noticeVersion,
 *   recordedAt`.
 * - `whatsappDispatchResult(data: unknown): WhatsappDispatchResult | null` —
 *   `request_whatsapp_dispatch`'s exact three keys: `notificationId, queued,
 *   reason` (reason explicitly nullable; never a provider id or cost).
 * - `readWhatsappOperationsPage(data: unknown): WhatsappOperationsPage |
 *   null` — the frozen envelope `{operations, nextAfter, nextAfterId,
 *   statusCounts, templateBlockers, wallet, chargedTotals}`. `statusCounts`
 *   separates accepted/delivered/read/unknown as canonical decimal strings.
 *   Row shape pinned below (WSP_ROW_KEYS): no provider ids, tickets, raw
 *   receipts, template bodies or recipient phones — the masked phone is the
 *   only recipient-identifying field and it must not be an unmasked
 *   E.164-style digit run.
 * - `whatsappOperationsView(identity, data)` — the ROLE SPLIT in one place
 *   (the messages.ts pattern): front office may call it; front_desk gets
 *   `wallet: null, chargedTotals: null` even when the page carries them;
 *   owner/manager (and a preview of one) get the exact amounts; trainers and
 *   members get `null` (denied before any projection).
 * - `whatsappOutcome(row)` — the one honest outcome per attempt-fact set:
 *   providerRead ⇒ read; deliveredAt ⇒ delivered; sentAt ⇒ accepted;
 *   outcomeUnknown ⇒ unknown; failure ⇒ failed; opted-out ⇒ opted_out;
 *   missing evidence ⇒ unknown, never 'unread' and never 'delivered'
 *   without delivery evidence (WSP-008).
 *
 * All validators refuse rather than pass through: an RPC answering a shape
 * the contract does not describe must not become a success screen acts on.
 */

const TENANT = '11111111-1111-4111-8111-111111111111';
const MEMBER = '33333333-3333-4333-8333-333333333333';
const NOTIFICATION = '55555555-5555-4555-8555-555555555555';
const OWNER = { kind: 'staff', role: 'gym_owner', tenantId: TENANT, staffId: '22222222-2222-4222-8222-222222222222' } as const;
const DESK = { ...OWNER, role: 'front_desk' } as const;
const TRAINER = { ...OWNER, role: 'trainer' } as const;
const PREVIEW_ADMIN = { kind: 'impersonation' } as unknown as Record<string, unknown>;

const whatsapp = () => import('../whatsapp');

type Fields = Record<string, unknown>;
const withoutKey = (object: Fields, key: string): Fields => {
  const copy: Fields = { ...object };
  delete copy[key];
  return copy;
};

describe('memberWhatsappSettings — exact six keys, channel permission not generic consent', () => {
  const adultAvailable: Fields = {
    service: true, marketing: false, recipientKind: 'self',
    maskedPhone: '+91 ••••• 810', noticeVersion: '2026-10-wsp-1', available: true,
  };
  const guardianLinked: Fields = { ...adultAvailable, recipientKind: 'guardian', noticeVersion: null, available: false };
  const unavailable: Fields = { ...adultAvailable, service: false, marketing: false, available: false };

  it.each([
    ['adult self recipient, service granted', adultAvailable],
    ['guardian-linked minor, no notice version yet, unavailable', guardianLinked],
    ['provider unconfigured, both false', unavailable],
  ])('accepts: %s', async (_name, fixture) => {
    const { memberWhatsappSettings } = await whatsapp();
    expect(memberWhatsappSettings(fixture)).toEqual(fixture);
  });

  it.each(Object.keys(adultAvailable))('refuses a result missing %s', async (key) => {
    const { memberWhatsappSettings } = await whatsapp();
    expect(memberWhatsappSettings(withoutKey(adultAvailable, key))).toBeNull();
  });

  it('refuses an extra key (no hidden consent history projection)', async () => {
    const { memberWhatsappSettings } = await whatsapp();
    expect(memberWhatsappSettings({ ...adultAvailable, consentHistory: [] })).toBeNull();
  });

  it('refuses a maskedPhone that is actually a full E.164 number', async () => {
    const { memberWhatsappSettings } = await whatsapp();
    expect(memberWhatsappSettings({ ...adultAvailable, maskedPhone: '+918095555810' })).toBeNull();
    expect(memberWhatsappSettings({ ...adultAvailable, maskedPhone: '8095555810' })).toBeNull();
  });

  it('refuses a recipientKind outside self|guardian', async () => {
    const { memberWhatsappSettings } = await whatsapp();
    expect(memberWhatsappSettings({ ...adultAvailable, recipientKind: 'sibling' })).toBeNull();
  });

  it.each(['80955 55810', '80955-55810', '+91 80955 55810 •', '•8095555810', '80955-55810*'])(
    'refuses complete phone digits despite grouping or mask decoration: %s', async (maskedPhone) => {
      const { memberWhatsappSettings } = await whatsapp();
      expect(memberWhatsappSettings({ ...adultAvailable, maskedPhone })).toBeNull();
    },
  );

  it.each(['+91 ••••• 810', '•••••••810', '*******810'])(
    'preserves genuinely concealed phone output: %s', async (maskedPhone) => {
      const { memberWhatsappSettings } = await whatsapp();
      expect(memberWhatsappSettings({ ...adultAvailable, maskedPhone })).toEqual({ ...adultAvailable, maskedPhone });
    },
  );

  it('refuses non-boolean service/marketing (they are channel permission, nothing else)', async () => {
    const { memberWhatsappSettings } = await whatsapp();
    expect(memberWhatsappSettings({ ...adultAvailable, service: 'granted' })).toBeNull();
    expect(memberWhatsappSettings({ ...adultAvailable, marketing: 1 })).toBeNull();
  });
});

describe('whatsappConsentWriteResult — exact five keys', () => {
  const granted: Fields = {
    consentId: '77777777-7777-4777-8777-777777777777', purpose: 'service',
    granted: true, noticeVersion: '2026-10-wsp-1', recordedAt: '2026-10-03T09:15:00+05:30',
  };

  it('accepts the exact five-key consent result', async () => {
    const { whatsappConsentWriteResult } = await whatsapp();
    expect(whatsappConsentWriteResult(granted)).toEqual(granted);
  });

  it.each(Object.keys(granted))('refuses a result missing %s', async (key) => {
    const { whatsappConsentWriteResult } = await whatsapp();
    expect(whatsappConsentWriteResult(withoutKey(granted, key))).toBeNull();
  });

  it('accepts both consent_purpose values', async () => {
    const { whatsappConsentWriteResult } = await whatsapp();
    expect(whatsappConsentWriteResult({ ...granted, purpose: 'service' })?.purpose).toBe('service');
    expect(whatsappConsentWriteResult({ ...granted, purpose: 'marketing' })?.purpose).toBe('marketing');
  });

  it('refuses a purpose outside the vocabulary', async () => {
    const { whatsappConsentWriteResult } = await whatsapp();
    expect(whatsappConsentWriteResult({ ...granted, purpose: 'whatsapp' })).toBeNull();
  });

  it('refuses an extra key (no generic consent mutation echoed back)', async () => {
    const { whatsappConsentWriteResult } = await whatsapp();
    expect(whatsappConsentWriteResult({ ...granted, source: 'call' })).toBeNull();
  });
});

describe('whatsappDispatchResult — exact three keys, no cost and no recipient', () => {
  const queued: Fields = { notificationId: NOTIFICATION, queued: true, reason: null };
  const refused: Fields = { notificationId: NOTIFICATION, queued: false, reason: 'WhatsApp not sent — wallet needs funds' };

  it.each([
    ['queued without reason', queued],
    ['refused with the funds refusal', refused],
  ])('accepts: %s', async (_name, fixture) => {
    const { whatsappDispatchResult } = await whatsapp();
    expect(whatsappDispatchResult(fixture)).toEqual(fixture);
  });

  it('refuses an attempt to carry a provider message id through the client', async () => {
    const { whatsappDispatchResult } = await whatsapp();
    expect(whatsappDispatchResult({ ...queued, providerMessageId: 'wamid.XXX' })).toBeNull();
  });

  it('refuses a non-null queued or numeric cost field', async () => {
    const { whatsappDispatchResult } = await whatsapp();
    expect(whatsappDispatchResult({ ...queued, queued: 'yes' })).toBeNull();
    expect(whatsappDispatchResult({ ...queued, costPaise: '350' })).toBeNull();
  });
});

describe('readWhatsappOperationsPage — frozen envelope, no secrets in any row', () => {
  const baseRow: Fields = {
    notificationId: NOTIFICATION, memberId: MEMBER, memberName: 'Asha K', status: 'sent',
    maskedPhone: '+91 ••••• 810', recipientKind: 'self', templateName: 'renewal_reminder',
    refusal: null, scheduledFor: '2026-10-03T09:00:00+05:30',
    sentAt: '2026-10-03T09:01:00+05:30', deliveredAt: null, providerReadAt: null,
    failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null,
    outcomeUnknown: false,
  };
  const page: Fields = {
    operations: [baseRow],
    nextAfter: '2026-10-03T09:00:00+05:30',
    nextAfterId: NOTIFICATION,
    statusCounts: { accepted: '2', delivered: '1', read: '0', unknown: '0' },
    templateBlockers: [{ templateId: '88888888-8888-4888-8888-888888888888', name: 'absence_followup', reason: 'template_paused' }],
    wallet: null,
    chargedTotals: null,
  };

  it('accepts the full envelope with explicit nulls', async () => {
    const { readWhatsappOperationsPage } = await whatsapp();
    expect(readWhatsappOperationsPage(page)).toEqual(page);
  });

  it.each(['operations', 'nextAfter', 'nextAfterId', 'statusCounts', 'templateBlockers', 'wallet', 'chargedTotals'])(
    'refuses the envelope missing %s', async (key) => {
      const { readWhatsappOperationsPage } = await whatsapp();
      expect(readWhatsappOperationsPage(withoutKey(page, key))).toBeNull();
    },
  );

  it.each(Object.keys(baseRow))('refuses a row missing %s', async (key) => {
    const { readWhatsappOperationsPage } = await whatsapp();
    const rows = [{ ...baseRow }];
    delete (rows[0] as Fields)[key];
    expect(readWhatsappOperationsPage({ ...page, operations: rows })).toBeNull();
  });

  it('refuses statusCounts that are not canonical decimal strings', async () => {
    const { readWhatsappOperationsPage } = await whatsapp();
    expect(readWhatsappOperationsPage({ ...page, statusCounts: { accepted: 2, delivered: '1', read: '0', unknown: '0' } })).toBeNull();
  });

  it('refuses a row carrying a raw phone, provider id, ticket or template body', async () => {
    const { readWhatsappOperationsPage } = await whatsapp();
    expect(readWhatsappOperationsPage({ ...page, operations: [{ ...baseRow, maskedPhone: '+918095555810' }] })).toBeNull();
    expect(readWhatsappOperationsPage({ ...page, operations: [{ ...baseRow, providerMessageId: 'wamid.XXX' }] })).toBeNull();
    expect(readWhatsappOperationsPage({ ...page, operations: [{ ...baseRow, ticket: 'abc' }] })).toBeNull();
    expect(readWhatsappOperationsPage({ ...page, operations: [{ ...baseRow, templateBody: 'Hi {{1}}' }] })).toBeNull();
  });

  it('refuses an unbounded page (the limit is enforced at the route; the reader still refuses >100 rows)', async () => {
    const { readWhatsappOperationsPage } = await whatsapp();
    const rows = Array.from({ length: 101 }, () => baseRow);
    expect(readWhatsappOperationsPage({ ...page, operations: rows })).toBeNull();
  });

  it.each(['80955 55810', '80955-55810', '+91 80955 55810 •', '•8095555810', '80955-55810*'])(
    'refuses operations containing complete phone digits despite grouping or decoration: %s', async (maskedPhone) => {
      const { readWhatsappOperationsPage, whatsappOperationsView } = await whatsapp();
      const unsafePage = { ...page, operations: [{ ...baseRow, maskedPhone }] };
      expect.soft(readWhatsappOperationsPage(unsafePage)).toBeNull();
      expect.soft(whatsappOperationsView(OWNER, unsafePage)).toBeNull();
      expect.soft(whatsappOperationsView(DESK, unsafePage)).toBeNull();
    },
  );

  it.each(['+91 ••••• 810', '•••••••810', '*******810'])(
    'preserves operations with concealed phone output: %s', async (maskedPhone) => {
      const { readWhatsappOperationsPage } = await whatsapp();
      const safePage = { ...page, operations: [{ ...baseRow, maskedPhone }] };
      expect(readWhatsappOperationsPage(safePage)).toEqual(safePage);
    },
  );

  it.each(['phone', 'recipientPhone', 'providerReadReceipt', 'rawReceipt', 'leaseTicket'])(
    'refuses undeclared operations row key %s', async (key) => {
      const { readWhatsappOperationsPage } = await whatsapp();
      expect(readWhatsappOperationsPage({ ...page, operations: [{ ...baseRow, [key]: 'private-value' }] })).toBeNull();
    },
  );
});

describe('whatsappOperationsView — the role split in one place', () => {
  const page: Fields = {
    operations: [{
      notificationId: NOTIFICATION, memberId: MEMBER, memberName: 'Asha K', status: 'delivered',
      maskedPhone: '+91 ••••• 810', recipientKind: 'self', templateName: 'renewal_reminder',
      refusal: null, scheduledFor: '2026-10-03T09:00:00+05:30', sentAt: '2026-10-03T09:01:00+05:30',
      deliveredAt: '2026-10-03T09:04:00+05:30', providerReadAt: null, failedAt: null, failedReason: null,
      optedOutAt: null, optedOutReason: null, outcomeUnknown: false,
    }],
    nextAfter: null,
    nextAfterId: null,
    statusCounts: { accepted: '1', delivered: '1', read: '0', unknown: '0' },
    templateBlockers: [],
    wallet: { balancePaise: '450000', currency: 'INR' },
    chargedTotals: { chargedPaise: '3500' },
  };

  it('gives owner/manager (and a preview of one) the exact wallet amounts and charged totals', async () => {
    const { whatsappOperationsView } = await whatsapp();
    const view = whatsappOperationsView(PREVIEW_ADMIN, page);
    expect(view).not.toBeNull();
    expect(view?.wallet).toEqual({ balancePaise: '450000', currency: 'INR' });
    expect(view?.chargedTotals).toEqual({ chargedPaise: '3500' });
  });

  it('gives front desk readiness and refusal only — wallet and charged totals nulled, nothing else changed', async () => {
    const { whatsappOperationsView } = await whatsapp();
    const view = whatsappOperationsView(DESK as unknown as Record<string, unknown>, page);
    expect(view).not.toBeNull();
    expect(view?.wallet).toBeNull();
    expect(view?.chargedTotals).toBeNull();
    expect(view?.operations).toEqual(page.operations);
    expect(view?.statusCounts).toEqual(page.statusCounts);
    expect(view?.templateBlockers).toEqual(page.templateBlockers);
  });

  it('gives trainers null — no communications access', async () => {
    const { whatsappOperationsView } = await whatsapp();
    expect(whatsappOperationsView(TRAINER as unknown as Record<string, unknown>, page)).toBeNull();
  });

  it('refuses to project a page whose shape the contract does not describe, for any role', async () => {
    const { whatsappOperationsView } = await whatsapp();
    expect(whatsappOperationsView(PREVIEW_ADMIN, { ...page, wallet: { balanceCredits: '4500' } })).toBeNull();
  });
});

describe('whatsappOutcome — one honest outcome, never invented delivery', () => {
  const row = (overrides: Fields): Fields => ({
    notificationId: NOTIFICATION, memberId: MEMBER, memberName: 'Asha K', status: 'sent',
    maskedPhone: '+91 ••••• 810', recipientKind: 'self', templateName: 'renewal_reminder',
    refusal: null, scheduledFor: '2026-10-03T09:00:00+05:30', sentAt: '2026-10-03T09:01:00+05:30',
    deliveredAt: null, providerReadAt: null, failedAt: null, failedReason: null,
    optedOutAt: null, optedOutReason: null, outcomeUnknown: false, ...overrides,
  });

  it.each([
    ['read on providerReadAt', { status: 'delivered', deliveredAt: 'd', providerReadAt: 'r' }, 'read'],
    ['delivered on deliveredAt alone', { status: 'delivered', deliveredAt: 'd' }, 'delivered'],
    ['accepted on sentAt alone', { status: 'sent' }, 'accepted'],
    ['unknown on outcomeUnknown even with sentAt', { status: 'sent', outcomeUnknown: true }, 'unknown'],
    ['failed with its reason', { status: 'failed', failedAt: 'f', failedReason: 'provider_rejected' }, 'failed'],
    ['opted out with its reason', { status: 'opted_out', optedOutAt: 'o', optedOutReason: 'consent_withdrawn' }, 'opted_out'],
    ['queued before any send', { status: 'scheduled', sentAt: null }, 'queued'],
    ['unknown when nothing is known', { status: 'scheduled', sentAt: null, outcomeUnknown: true }, 'unknown'],
  ])('%s', async (_name, overrides, expected) => {
    const { whatsappOutcome } = await whatsapp();
    expect(whatsappOutcome(row(overrides))).toBe(expected);
  });

  it('never answers delivered or read without the matching timestamp evidence', async () => {
    const { whatsappOutcome } = await whatsapp();
    expect(whatsappOutcome(row({ status: 'delivered' }))).not.toBe('delivered');
    expect(whatsappOutcome(row({ status: 'delivered', deliveredAt: 'd' }))).not.toBe('read');
  });

  it.each(['delivered', 'clicked', 'converted'])(
    'status %s alone cannot certify provider delivery or read', async (status) => {
      const { whatsappOutcome } = await whatsapp();
      const result = whatsappOutcome(row({ status, sentAt: null, deliveredAt: null, providerReadAt: null }));
      expect(result).not.toBe('delivered');
      expect(result).not.toBe('read');
    },
  );
});
