import { identityHome, type GymloopIdentity } from './identity';
import { requireAudience } from './identity-session';
import { FRONT_OFFICE_ROLES } from './leads';
import { loadMemberSearch } from './members';
import { redirect } from 'next/navigation';

/**
 * The staff `/messages` screen's one read (contract §4): `list_notifications`
 * returns rows and their drill-down `statusCounts` from one snapshot, in
 * `list_leads`'s tradition — a second query for counts could disagree with
 * the rows a filter actually produced. The admin wallet decimal is in that
 * same RPC snapshot; template reads are skipped for front desk.
 */

/** Front office may view the screen; a support preview may too, the same exception `(console)/layout.tsx` already carries. */
export function canViewMessages(identity: GymloopIdentity): boolean {
  return identity.kind === 'impersonation' ||
    (identity.kind === 'staff' && (FRONT_OFFICE_ROLES as readonly string[]).includes(identity.role));
}

/** Only gym admin — owner or manager, or a preview of one — sees the template and wallet sections. */
const MESSAGE_ADMIN_ROLES = ['gym_owner', 'gym_manager'] as const;
function isMessagesAdmin(identity: GymloopIdentity): boolean {
  return identity.kind === 'impersonation' ||
    (identity.kind === 'staff' && (MESSAGE_ADMIN_ROLES as readonly string[]).includes(identity.role));
}

export type MessageListRow = {
  id: string;
  memberId: string;
  memberName: string;
  channel: string;
  category: string;
  status: string;
  scheduledFor: string;
  sentAt: string | null;
  deliveredAt: string | null;
  failedAt: string | null;
  failedReason: string | null;
  optedOutAt: string | null;
  optedOutReason: string | null;
  sourceNotificationId: string | null;
};

export type MessageStatusCounts = {
  scheduled: string; sent: string; delivered: string; failed: string; opted_out: string;
};

const EMPTY_STATUS_COUNTS: MessageStatusCounts = {
  scheduled: '0', sent: '0', delivered: '0', failed: '0', opted_out: '0',
};

type MessageTemplateRow = {
  id: string; key: string; channel: string; locale: string; category: string; body: string; isActive: boolean;
};

export type MemberChoice = { id: string; name: string };

export type MessagesScreen = {
  rows: MessageListRow[];
  statusCounts: MessageStatusCounts;
  asOf: string | null;
  isAdmin: boolean;
  isPreview: boolean;
  tenantId: string;
  members: MemberChoice[];
  memberNextCursor: string | null;
  memberSearchError: string | null;
  templates: MessageTemplateRow[];
  walletBalanceCredits: string | null;
  errorMessage: string | null;
};

type ListNotificationsResult = {
  rows: MessageListRow[];
  statusCounts: Partial<MessageStatusCounts>;
  asOf: string;
  walletBalanceCredits: string | null;
};

export async function loadMessages(
  searchParams: Promise<{ channel?: string; q?: string; memberCursor?: string }>,
): Promise<MessagesScreen> {
  const params = await searchParams;
  const { supabase, identity } = await requireAudience('console');
  // A trainer, a member or platform support never reaches this screen; the
  // refusal happens BEFORE any read, so it never depends on what a query
  // would have returned.
  if (!canViewMessages(identity)) redirect(identityHome(identity));

  const isAdmin = isMessagesAdmin(identity);
  const tenantId = identity.tenantId;
  const channel = params.channel && params.channel !== '' ? params.channel : null;

  // `list_notifications` is not in the generated types yet — the migration
  // lands with this phase and `supabase gen types` follows it. Until then it
  // is called through the same narrow local cast the leads loader uses for
  // not-yet-generated RPCs; the wire payload comes from the frozen contract.
  const reader = supabase as unknown as {
    rpc(name: 'list_notifications', args: { p_channel: string | null }):
      Promise<{ data: ListNotificationsResult | null; error: { message: string } | null }>;
  };
  // `message_templates.category` and `.is_active` alias exist on the table
  // already, but the generated types have not caught up with this phase's
  // migration; the narrow cast matches the one `member-imports.ts` uses.
  const templateReader = supabase as unknown as {
    from(table: 'message_templates'): {
      select(columns: string): {
        order(column: string): Promise<{
          data: Array<{ id: string; key: string; channel: string; locale: string; category: string; body: string; is_active: boolean }> | null;
          error: { message: string } | null;
        }>;
      };
    };
  };

  const [page, templates, memberSearch] = await Promise.all([
    reader.rpc('list_notifications', { p_channel: channel }),
    isAdmin
      ? templateReader.from('message_templates').select('id,key,channel,locale,category,body,is_active').order('key')
      : Promise.resolve({ data: [], error: null }),
    loadMemberSearch(Promise.resolve({
      ...(params.q ? { q: params.q } : {}),
      ...(params.memberCursor ? { cursor: params.memberCursor } : {}),
    })),
  ]);

  const unusable: MessagesScreen = {
    rows: [], statusCounts: EMPTY_STATUS_COUNTS, asOf: null, isAdmin,
    isPreview: identity.kind === 'impersonation', tenantId, members: [],
    memberNextCursor: null, memberSearchError: memberSearch.errorMessage,
    templates: [], walletBalanceCredits: null, errorMessage: 'The messages list could not be loaded.',
  };
  if (page.error || page.data === null || !Array.isArray(page.data.rows)) return unusable;

  const rows = page.data.rows;

  const templateRows: MessageTemplateRow[] = (templates.data ?? []).map((row) => ({
    id: row.id, key: row.key, channel: row.channel, locale: row.locale,
    category: row.category, body: row.body, isActive: Boolean(row.is_active),
  }));

  return {
    rows,
    statusCounts: { ...EMPTY_STATUS_COUNTS, ...page.data.statusCounts },
    asOf: typeof page.data.asOf === 'string' && page.data.asOf !== '' ? page.data.asOf : null,
    isAdmin,
    isPreview: identity.kind === 'impersonation',
    tenantId,
    members: memberSearch.members.map((member) => ({ id: member.id, name: member.full_name })),
    memberNextCursor: memberSearch.nextCursor,
    memberSearchError: memberSearch.errorMessage,
    templates: templateRows,
    walletBalanceCredits: typeof page.data.walletBalanceCredits === 'string' ? page.data.walletBalanceCredits : null,
    errorMessage: null,
  };
}
