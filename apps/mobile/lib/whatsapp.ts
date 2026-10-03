import type { ApiClient } from '@gymloop/api-client';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';

/**
 * Native WSP surfaces: the member's own channel-consent settings only. There
 * is no desk surface on mobile (WSP-001's operations belong to the web
 * console). Consent is read and written through the same commands the web
 * uses — no provider call exists anywhere on the client (WSP-011; delivery
 * facts arrive from the server, never from the device).
 */

export type MemberWhatsappSettingsState = {
  service: boolean;
  marketing: boolean;
  recipientKind: 'self' | 'guardian';
  maskedPhone: string;
  noticeVersion: string | null;
  available: boolean;
};

/** `read_member_whatsapp_settings` is not in the generated types yet; the narrow cast matches `training.ts`'s pattern. */
export async function loadWhatsappSettings(client: SupabaseClient<Database>): Promise<MemberWhatsappSettingsState | null> {
  const reader = client as unknown as {
    rpc(name: 'read_member_whatsapp_settings', args: Record<string, never>):
      Promise<{ data: MemberWhatsappSettingsState | null; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await reader.rpc('read_member_whatsapp_settings', {});
  if (error) return null;
  const settings = data;
  if (settings === null) return null;
  if (typeof settings.service !== 'boolean' || typeof settings.marketing !== 'boolean' || typeof settings.available !== 'boolean') return null;
  if (settings.recipientKind !== 'self' && settings.recipientKind !== 'guardian') return null;
  if (typeof settings.maskedPhone !== 'string' || settings.maskedPhone === '') return null;
  if (settings.noticeVersion !== null && typeof settings.noticeVersion !== 'string') return null;
  return settings;
}

export type WhatsappConsentWriteOutcome = { ok: boolean; message: string };

const CONSENT_FAILURES: Record<string, string> = {
  consent_withdrawn: 'That consent could not be recorded right now.',
  invalid_request: 'Check the consent details, then try again.',
  idempotency_conflict: 'This consent was already recorded differently. Reload and try again.',
};

export async function setWhatsappConsent(
  api: ApiClient,
  purpose: 'service' | 'marketing',
  granted: boolean,
  noticeVersion: string,
): Promise<WhatsappConsentWriteOutcome> {
  const result = await api.post<{ consentId: string; purpose: string; granted: boolean; noticeVersion: string | null; recordedAt: string }>(
    '/api/member/whatsapp-consent',
    { purpose, granted, noticeVersion },
  );
  if (result.ok) {
    return {
      ok: true,
      message: granted
        ? (purpose === 'service' ? 'WhatsApp service updates are on.' : 'WhatsApp offers and news are on.')
        : (purpose === 'service' ? 'WhatsApp service updates are off.' : 'WhatsApp offers and news are off.'),
    };
  }
  return { ok: false, message: CONSENT_FAILURES[result.error.code] ?? 'The WhatsApp consent could not be recorded. Nothing was written.' };
}
