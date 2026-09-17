import { requireAudience } from './identity-session';

/**
 * The member `/member/messages` screen's reads (contract §4, and the seam's
 * "In-app delivery" rule): only the member's own in-app sent/delivered
 * messages, and a separate consent history. Neither read filters by
 * `member_id`/`tenant_id` — the client carries the caller's session, RLS
 * scopes both tables to the signed-in member, and an application-side filter
 * would return the right rows even with that policy broken, hiding exactly
 * the defect the pgTAP suite exists to catch (the same reasoning
 * `lib/leads.ts` and `lib/member-imports.ts` record).
 *
 * This loader never posts the delivered action — reading a message means the
 * member explicitly opens it (`MemberMessageAck`), never rendering the list.
 */

type MemberMessageRow = {
  id: string;
  channel: string;
  category: string;
  status: string;
  sentAt: string | null;
  deliveredAt: string | null;
  body: string;
};

type MemberConsentRow = { purpose: string; granted: boolean; recordedAt: string };

export type MemberMessagesScreen = {
  messages: MemberMessageRow[];
  consents: MemberConsentRow[];
  errorMessage: string | null;
};

type RawNotificationRow = {
  id: string; channel: string; category: string; status: string;
  sent_at: string | null; delivered_at: string | null; payload: unknown;
};
type RawConsentRow = { purpose: string; granted: boolean; recorded_at: string };

export async function loadMemberMessages(): Promise<MemberMessagesScreen> {
  const { supabase } = await requireAudience('member');

  // `notifications.category` and `consents.request_key` land with this
  // phase's migration; the generated types have not caught up yet, so the
  // reads go through the same narrow local cast `member-imports.ts` uses.
  const notificationReader = supabase as unknown as {
    from(table: 'notifications'): {
      select(columns: string): {
        eq(column: string, value: string): {
          in(column: string, values: readonly string[]): {
            order(column: string, options: { ascending: boolean }): Promise<{ data: RawNotificationRow[] | null; error: { message: string } | null }>;
          };
        };
      };
    };
  };
  const consentReader = supabase as unknown as {
    from(table: 'consents'): {
      select(columns: string): {
        order(column: string, options: { ascending: boolean }): Promise<{ data: RawConsentRow[] | null; error: { message: string } | null }>;
      };
    };
  };

  const [messages, consents] = await Promise.all([
    notificationReader.from('notifications').select('id,channel,category,status,sent_at,delivered_at,payload')
      .eq('channel', 'in_app').in('status', ['sent', 'delivered']).order('sent_at', { ascending: false }),
    consentReader.from('consents').select('purpose,granted,recorded_at').order('recorded_at', { ascending: false }),
  ]);

  if (messages.error || consents.error) {
    return { messages: [], consents: [], errorMessage: 'Your messages could not be loaded.' };
  }

  const rows: MemberMessageRow[] = (messages.data ?? [])
    .map((row) => ({
      id: row.id, channel: row.channel, category: row.category, status: row.status,
      sentAt: row.sent_at, deliveredAt: row.delivered_at,
      body: typeof row.payload === 'object' && row.payload !== null && typeof (row.payload as { body?: unknown }).body === 'string'
        ? (row.payload as { body: string }).body
        : '',
    }));

  const consentRows: MemberConsentRow[] = (consents.data ?? []).map((row) => ({
    purpose: row.purpose, granted: row.granted, recordedAt: row.recorded_at,
  }));

  return { messages: rows, consents: consentRows, errorMessage: null };
}
