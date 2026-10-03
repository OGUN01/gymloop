import { describe, expect, it } from 'vitest';

/**
 * WSP channel consent request schemas (platform-free wire layer), authored
 * from the frozen contract before `packages/shared/src/api/whatsapp.ts`
 * exists. Sources: `openspec/changes/whatsapp-channel/proposal.md` (WSP-002,
 * channel-specific versioned consent), the approved
 * `provider-wallet-amendment.md`, and the frozen
 * `wave-c-serial-freeze-declarations.md`. No production source was consulted.
 *
 * `whatsapp.ts` is expected to export, mirroring `api/comms.ts`:
 *
 * - `memberWhatsappConsentRequestSchema` — the member's own channel consent
 *   command: `{ purpose, granted, noticeVersion }`. `purpose` is
 *   shape-checked here only; membership in `consent_purpose` is checked at
 *   the route against `Constants` (the header reason already recorded in
 *   `api/comms.ts`). `noticeVersion` is the shown versioned notice the
 *   member actually accepted — WSP-002 requires the actual adult/guardian
 *   recipient's independent opt-in, so a blank or absent notice version
 *   cannot stand for consent.
 * - `staffWhatsappConsentRequestSchema` — the front office's verified
 *   actual-recipient recording: `{ memberId, purpose, granted, noticeVersion,
 *   source, requestKey }`, exactly the six fields its RPC signature names
 *   (`p_member_id, p_purpose, p_granted, p_notice_version, p_source,
 *   p_request_key`). `source` is the staff-recorded evidence basis text;
 *   there is no default-on bulk checkbox anywhere in the shape.
 *
 * Both are `.strict()`: an old or renamed field must fail validation rather
 * than be silently reinterpreted (the wallet paise conversion's mixed-unit
 * rule, applied to consent).
 */

import {
  memberWhatsappConsentRequestSchema,
  staffWhatsappConsentRequestSchema,
  type MemberWhatsappConsentRequest,
  type StaffWhatsappConsentRequest,
} from '../whatsapp';

const UUID = (n: string) => `${n}0000000-1111-4111-8111-000000000001`;

describe('memberWhatsappConsentRequestSchema', () => {
  const valid = { purpose: 'service', granted: true, noticeVersion: '2026-10-wsp-1' };

  it('accepts the exact three-field member consent body', () => {
    const parsed = memberWhatsappConsentRequestSchema.parse(valid);
    expect(parsed.granted).toBe(true);
    expect(parsed.noticeVersion).toBe('2026-10-wsp-1');
  });

  it('accepts a false grant (an explicit opt-out is a command too)', () => {
    expect(memberWhatsappConsentRequestSchema.parse({ ...valid, granted: false }).granted).toBe(false);
  });

  it.each(['marketing', 'service'])('accepts every consent_purpose value as a wire string: %s', (purpose) => {
    expect(memberWhatsappConsentRequestSchema.parse({ ...valid, purpose }).purpose).toBe(purpose);
  });

  it('rejects a blank or whitespace-only notice version', () => {
    expect(memberWhatsappConsentRequestSchema.safeParse({ ...valid, noticeVersion: '   ' }).success).toBe(false);
    expect(memberWhatsappConsentRequestSchema.safeParse({ ...valid, noticeVersion: '' }).success).toBe(false);
  });

  it('rejects a missing notice version — consent without the accepted notice is not consent', () => {
    const { noticeVersion: _dropped, ...withoutNotice } = valid;
    expect(memberWhatsappConsentRequestSchema.safeParse(withoutNotice).success).toBe(false);
  });

  it.each([
    ['notice_version snake_case', { purpose: 'service', granted: true, notice_version: 'v1' }],
    ['granted as string', { purpose: 'service', granted: 'true', noticeVersion: 'v1' }],
    ['unknown extra field (mixed-unit style)', { ...valid, deltaCredits: 5 }],
    ['purpose as number', { purpose: 1, granted: true, noticeVersion: 'v1' }],
  ])('rejects %s', (_name, body) => {
    expect(memberWhatsappConsentRequestSchema.safeParse(body).success).toBe(false);
  });

  it('types the parsed result without notice_version drift', () => {
    const parsed: MemberWhatsappConsentRequest = memberWhatsappConsentRequestSchema.parse(valid);
    expect(Object.keys(parsed).sort()).toEqual(['granted', 'noticeVersion', 'purpose']);
  });
});

describe('staffWhatsappConsentRequestSchema', () => {
  const valid = {
    memberId: UUID('22'),
    purpose: 'service',
    granted: true,
    noticeVersion: '2026-10-wsp-1',
    source: 'guardian confirmed on call 2026-10-03 14:05 IST',
    requestKey: UUID('66'),
  };

  it('accepts the exact six-field staff recorder body', () => {
    const parsed: StaffWhatsappConsentRequest = staffWhatsappConsentRequestSchema.parse(valid);
    expect(parsed.memberId).toBe(valid.memberId);
    expect(parsed.source).toContain('guardian');
    expect(parsed.requestKey).toBe(valid.requestKey);
  });

  it('rejects a member id that is not a uuid', () => {
    expect(staffWhatsappConsentRequestSchema.safeParse({ ...valid, memberId: 'not-a-uuid' }).success).toBe(false);
  });

  it('rejects a missing request key — the recorder is replay-guarded like every command', () => {
    const { requestKey: _dropped, ...withoutKey } = valid;
    expect(staffWhatsappConsentRequestSchema.safeParse(withoutKey).success).toBe(false);
  });

  it('rejects a blank source: the evidence basis is the point of the staff path', () => {
    expect(staffWhatsappConsentRequestSchema.safeParse({ ...valid, source: '  ' }).success).toBe(false);
  });

  it('rejects extra fields (no bulk grant via an undeclared memberIds array)', () => {
    expect(staffWhatsappConsentRequestSchema.safeParse({ ...valid, memberIds: [UUID('23')] }).success).toBe(false);
  });

  it('rejects an old generic-consent shape (version instead of noticeVersion)', () => {
    const { noticeVersion: _dropped, ...generic } = valid;
    expect(staffWhatsappConsentRequestSchema.safeParse({ ...generic, version: 'v1' }).success).toBe(false);
  });
});
