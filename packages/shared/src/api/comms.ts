import { z } from 'zod';

/**
 * Phase 6 communications/wallet cluster's platform-free wire layer
 * (`docs/planning/phase6-comms-contract.md` §1, §3-§5, §7-§8; COM-001..009,
 * PAY-001..003, GL065..069). Lives in `packages/shared` because it is the
 * canonical-decimal-string codec every bigint-crossing-JSON boundary in this
 * cluster needs (AGENTS.md rule 11: no `next/*`, `react-dom` or `node:*`
 * here), not because every shape below is reused outside `apps/web` yet.
 *
 * `consent_purpose` and `notification_channel` are already-generated Postgres
 * enums (AGENTS.md rule 5); this package cannot import `@gymloop/db`
 * (`streaks/streaks.ts` records the same constraint), so those catalogues are
 * checked against `Constants` at the `apps/web` route layer — the same split
 * `apps/web/app/api/leads/lead-input.ts` already draws for `lead_stage` and
 * `lead_source`. `message_category` becomes generated only after this
 * migration lands; until then its request value is a nonblank wire string and
 * PostgreSQL's enum is authoritative. No parallel TypeScript vocabulary is
 * maintained here.
 */

const CANONICAL_DECIMAL_INTEGER = /^(?:0|-?[1-9][0-9]*)$/;

/**
 * The §1 grammar: `0` or nonzero-leading digits, one leading minus for a
 * negative value. Byte-identical to `rupeesFromPaise`'s own guard in
 * `api/payments.ts` (`/^(?:0|-?[1-9][0-9]*)$/`) — comms credits are a second
 * bigint boundary, not a second rounding rule, so this is the same pattern
 * named again rather than a divergent copy.
 */
export function isCanonicalDecimalInteger(value: unknown): value is string {
  return typeof value === 'string' && CANONICAL_DECIMAL_INTEGER.test(value);
}

/** A canonical decimal integer that is never negative — the ledger's `balance_after_credits >= 0` CHECK (§2). */
export function isNonnegativeCanonicalDecimalInteger(value: unknown): value is string {
  return isCanonicalDecimalInteger(value) && !value.startsWith('-');
}

/** The v1 supported template locales (§2) — a plain text CHECK on `message_templates.locale`, not a generated enum. */
export const MESSAGE_TEMPLATE_LOCALES = ['en', 'hi'] as const;
export type MessageTemplateLocale = (typeof MESSAGE_TEMPLATE_LOCALES)[number];

/** The reserved system template key (§2, §8): never authorable through gym CRUD. */
export const RESERVED_RENEWAL_TEMPLATE_KEY = 'renewal_reminder';

const uuid = z.uuid();
const nonBlank = z.string().trim().min(1);
const canonicalCredits = z.string().refine(isCanonicalDecimalInteger, 'Must be a canonical decimal integer.');

/**
 * `POST /api/consents` (§3, §8). `purpose` is shape-checked here only —
 * membership in `consent_purpose` is checked at the route against
 * `Constants`, for the reason in the file header.
 */
export const recordConsentRequestSchema = z.object({
  memberId: uuid,
  purpose: nonBlank,
  granted: z.boolean(),
  version: nonBlank,
  source: nonBlank,
  requestKey: uuid,
}).strict();
export type RecordConsentRequest = z.infer<typeof recordConsentRequestSchema>;

/**
 * `POST /api/message-templates` (§2, §8). `channel` is shape-checked here
 * only — membership in `notification_channel` is checked at the route
 * against `Constants`. `templateId` present means "update this template";
 * absent means "create one" (the route never accepts an id on creation).
 */
export const messageTemplateRequestSchema = z.object({
  templateId: uuid.optional(),
  key: nonBlank,
  channel: nonBlank,
  locale: z.enum(MESSAGE_TEMPLATE_LOCALES),
  category: nonBlank,
  body: nonBlank,
  isActive: z.boolean(),
}).strict();
export type MessageTemplateRequest = z.infer<typeof messageTemplateRequestSchema>;

/** `POST /api/messaging-wallet/adjust` (§7). `deltaCredits` may be zero or negative; the RPC's CHECK owns refusing zero. */
export const walletAdjustRequestSchema = z.object({
  tenantId: uuid,
  deltaCredits: canonicalCredits,
  reason: nonBlank,
  requestKey: uuid,
}).strict();
export type WalletAdjustRequest = z.infer<typeof walletAdjustRequestSchema>;
