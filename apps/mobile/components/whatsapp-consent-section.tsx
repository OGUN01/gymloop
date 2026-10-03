import { useCallback, useEffect, useState } from 'react';
import { View } from 'react-native';

import { Body, ErrorRetry, LoadingState, Row, Status } from './ui';

/**
 * The member's WhatsApp consent section (WSP-002): channel permission for
 * service and marketing notices, per the settings projection — the masked
 * phone and recipient kind, the notice version accepted, and honest
 * unavailability when the channel is not configured. No provider call exists
 * here; writes go through `/api/member/whatsapp-consent` only.
 */

export type WhatsappSettingsProjection = {
  service: boolean;
  marketing: boolean;
  recipientKind: 'self' | 'guardian';
  maskedPhone: string;
  noticeVersion: string | null;
  available: boolean;
};

export type WhatsappConsentSectionProps = {
  loadSettings: () => Promise<WhatsappSettingsProjection | null>;
  setConsent: (purpose: 'service' | 'marketing', granted: boolean, noticeVersion: string) => Promise<{ ok: boolean; message: string }>;
};

export function WhatsappConsentSection({ loadSettings, setConsent }: WhatsappConsentSectionProps) {
  const [state, setState] = useState<'loading' | 'ready' | 'error'>('loading');
  const [settings, setSettings] = useState<WhatsappSettingsProjection | null>(null);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  const reload = useCallback(() => {
    setState('loading');
    loadSettings().then((loaded) => {
      setSettings(loaded);
      setState(loaded === null ? 'error' : 'ready');
    }).catch(() => setState('error'));
  }, [loadSettings]);

  useEffect(() => { reload(); }, [reload]);

  if (state === 'loading') return <LoadingState />;
  if (state === 'error' || settings === null) {
    return <ErrorRetry message="The WhatsApp settings could not be loaded." onRetry={reload} />;
  }

  const write = (purpose: 'service' | 'marketing', granted: boolean) => {
    if (busy || settings.noticeVersion === null) return;
    setBusy(true);
    setConsent(purpose, granted, settings.noticeVersion).then((outcome) => {
      setNotice(outcome.message);
      setBusy(false);
      reload();
    });
  };

  if (!settings.available) {
    return (
      <View>
        <Status tone="neutral">WhatsApp updates are not available yet</Status>
        <Body muted>Your gym has not turned on WhatsApp updates. You will still see every update in the app.</Body>
      </View>
    );
  }

  if (settings.noticeVersion === null) {
    return (
      <View>
        <Status tone="neutral">Consent needs the desk</Status>
        <Body muted>WhatsApp consent is recorded with the gym, for the number that actually receives the messages.</Body>
      </View>
    );
  }

  const rows: { purpose: 'service' | 'marketing'; title: string; meta: string; granted: boolean }[] = [
    { purpose: 'service', title: 'Service updates', meta: 'Renewals, class changes, receipts', granted: settings.service },
    { purpose: 'marketing', title: 'Offers and news', meta: 'Promotions from your gym', granted: settings.marketing },
  ];

  return (
    <View>
      <Status tone="neutral">
        {`Receiving on ${settings.maskedPhone} · ${settings.recipientKind === 'guardian' ? 'guardian' : 'your'} number · notice ${settings.noticeVersion}`}
      </Status>
      {rows.map((row) => (
        <Row
          key={row.purpose}
          title={row.title}
          meta={row.meta}
          value={row.granted ? 'On' : 'Off'}
          onPress={() => write(row.purpose, !row.granted)}
          accessibilityLabel={`${row.title} WhatsApp consent`}
        />
      ))}
      {notice !== null ? <Body muted>{notice}</Body> : null}
      <Body muted>Turning these off stops WhatsApp sends. Updates always stay in the app.</Body>
    </View>
  );
}
