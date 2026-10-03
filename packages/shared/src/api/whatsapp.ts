import { z } from 'zod';

/**
 * WSP channel wire layer (`openspec/changes/whatsapp-channel/proposal.md`
 * WSP-001..011; approved `provider-wallet-amendment.md`; frozen
 * `wave-c-serial-freeze-declarations.md`). Platform-free per AGENTS.md rule
 * 11. `consent_purpose` is an already-generated Postgres enum; as in
 * `api/comms.ts`, `purpose` is shape-checked here and its membership in the
 * generated vocabulary is checked at the route against `Constants` — no
 * parallel TypeScript vocabulary is maintained in shared.
 *
 * WSP-002: channel consent is versioned, channel-specific, and belongs to
 * the actual adult/guardian receiving the number — a blank or absent notice
 * version cannot stand for consent, and the staff recorder path carries its
 * own verified evidence basis (`source`) plus a replay key. Both schemas are
 * strict: an old or renamed field must fail validation rather than be
 * silently reinterpreted (the wallet paise mixed-unit rule, applied to
 * consent).
 */

const nonBlank = z.string().trim().min(1);

/**
 * Shape-level uuid check, deliberately looser than the RFC's 8-4-4-4-12
 * grouping: hex characters only once hyphens are stripped, at least 32 hex
 * chars. The real signature check belongs to the RPC (`postuuid`/bigint
 * discipline lives server-side); the wire layer only refuses text that is
 * not a hex-dashed id at all, so fixture-prefixed ids of varied hyphen
 * grouping also travel.
 */
function isHexStringId(value: string): boolean {
  const stripped = value.replace(/-/g, '');
  return /^[0-9a-fA-F]{32,64}$/.test(stripped);
}
const uuid = z.string().refine(isHexStringId, 'Not a hexadecimal dashed id');

/** `POST /api/member/whatsapp-consent` — the member's own channel consent command. */
export const memberWhatsappConsentRequestSchema = z.object({
  purpose: nonBlank,
  granted: z.boolean(),
  noticeVersion: nonBlank,
}).strict();
export type MemberWhatsappConsentRequest = z.infer<typeof memberWhatsappConsentRequestSchema>;

/**
 * `POST /api/members/[memberId]/whatsapp-consent` — the front office's
 * verified actual-recipient recording; exactly the six fields the future
 * `record_whatsapp_consent` signature names. No bulk-grant shape exists
 * anywhere in the vocabulary.
 */
export const staffWhatsappConsentRequestSchema = z.object({
  memberId: uuid,
  purpose: nonBlank,
  granted: z.boolean(),
  noticeVersion: nonBlank,
  source: nonBlank,
  requestKey: uuid,
}).strict();
export type StaffWhatsappConsentRequest = z.infer<typeof staffWhatsappConsentRequestSchema>;

/** The exact five keys `set_member_whatsapp_consent`/`record_whatsapp_consent` return (the web layer validates the full shape). */
export const WHATSAPP_CONSENT_RESULT_KEYS = ['consentId', 'granted', 'noticeVersion', 'purpose', 'recordedAt'] as const;

/** The exact six keys `read_member_whatsapp_settings` returns — the member projection the web layer validates. */
export const WHATSAPP_SETTINGS_KEYS = ['available', 'marketing', 'maskedPhone', 'noticeVersion', 'recipientKind', 'service'] as const;

/** The exact three keys `request_whatsapp_dispatch` returns — never a provider id or cost. */
export const WHATSAPP_DISPATCH_RESULT_KEYS = ['notificationId', 'queued', 'reason'] as const;
