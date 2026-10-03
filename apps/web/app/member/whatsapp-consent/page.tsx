import { requireAudience } from '../../../lib/identity-session';
import { memberWhatsappSettings } from '../../../lib/whatsapp';
import { WhatsappConsentControls } from './consent-controls';

/**
 * The member's WhatsApp consent page (WSP-002). The settings projection is
 * the single source of what is on and where the channel messages arrive —
 * masked phone, recipient kind, the notice version accepted. Unavailability
 * is honest: when the gym has not configured the channel or no notice version
 * is on file, the page says so instead of showing controls that would fake a
 * grant. Consent can always be recorded with the desk instead.
 */
export default async function MemberWhatsappConsentPage() {
  const { supabase } = await requireAudience('member');

  const reader = supabase as unknown as {
    rpc(name: 'read_member_whatsapp_settings', args: Record<string, never>):
      Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await reader.rpc('read_member_whatsapp_settings', {});
  const settings = error ? null : memberWhatsappSettings(data);

  if (settings === null) {
    return (
      <section>
        <h1>WhatsApp</h1>
        <p>The WhatsApp settings could not be loaded. Check the connection and try again.</p>
      </section>
    );
  }

  if (!settings.available) {
    return (
      <section>
        <h1>WhatsApp</h1>
        <p>Your gym has not turned on WhatsApp updates yet. Every update still reaches you in the app.</p>
      </section>
    );
  }

  if (settings.noticeVersion === null) {
    return (
      <section>
        <h1>WhatsApp</h1>
        <p>
          Messages would arrive on {settings.maskedPhone}
          {settings.recipientKind === 'guardian' ? ' (the guardian’s number)' : ''}, but consent
          needs a versioned notice first. Ask the gym desk to record your WhatsApp consent.
        </p>
      </section>
    );
  }

  return (
    <section>
      <h1>WhatsApp</h1>
      <p>
        Messages arrive on {settings.maskedPhone}
        {settings.recipientKind === 'guardian' ? ' — the guardian’s number' : ''}.
      </p>
      <WhatsappConsentControls
        noticeVersion={settings.noticeVersion}
        current={{ service: settings.service, marketing: settings.marketing }}
      />
    </section>
  );
}
