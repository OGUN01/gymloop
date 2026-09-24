import { DEFAULT_TIMEZONE, MS_PER_DAY, RENEWAL_REMINDER_WINDOWS, membershipNetPrice } from '@gymloop/shared';
import { createServerSupabase } from './supabase/server';

/**
 * What one word under STATUS means, decided once for every console ledger —
 * Members, Check-in, Memberships — and the member page.
 *
 * It exists because the roster said "Active" (the account) one click away from
 * Memberships saying "Overdue" (the membership) about the same person, and an
 * owner who sees both distrusts both. The word is the membership's standing,
 * because that is what the desk acts on to collect a renewal, and a blocked or
 * cancelled ACCOUNT outranks it, because that is what the desk must not miss.
 *
 * Read-only and RLS-filtered like every console read: one query for exactly the
 * listed members, so the caller's own sort and cursor stay untouched, and no
 * `tenant_id` predicate for the reason `loadMemberSearch` gives. Money columns
 * are asked for only when the caller may show them — a trainer's request never
 * names a price rather than naming it and hiding the answer.
 */

/** A membership renews from the first reminder window on (PAY-001), so that is when it reads as due. */
const DUE_WITHIN_DAYS = -RENEWAL_REMINDER_WINDOWS[0].daysFromExpiry;
const RUNNING = ['active', 'frozen'];
/** Account states that outrank whatever the membership says. */
const ACCOUNT_OVERRIDES = new Set(['blocked', 'cancelled']);

type Row = {
  id: string;
  member_id: string;
  status: string;
  starts_on: string | null;
  ends_on: string | null;
  plans: { name: string } | null;
  price_paise?: number;
  discount_paise?: number;
  currency?: string;
};

type Word = { status: string; label: string };

function todayIn(timezone: string): string {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: timezone }).format(new Date());
  } catch {
    // `organizations.timezone` is free text; an unknown zone falls back rather than failing the page.
    return new Intl.DateTimeFormat('en-CA', { timeZone: DEFAULT_TIMEZONE }).format(new Date());
  }
}

/** Live on the gate's terms — status AND dates (ADR-084) — then how close the end is. */
function membershipWord(row: Row | undefined, today: string, dueBy: string): Word {
  if (row === undefined) return { status: 'none', label: 'No membership' };
  const started = row.starts_on === null || row.starts_on <= today;
  const ended = row.ends_on !== null && row.ends_on < today;
  if (row.status === 'frozen') return ended ? { status: 'overdue', label: 'Overdue' } : { status: 'paused', label: 'Paused' };
  if (row.status === 'active') {
    if (ended) return { status: 'overdue', label: 'Overdue' };
    if (!started) return { status: 'pending', label: 'Starts later' };
    return row.ends_on !== null && row.ends_on <= dueBy ? { status: 'due', label: 'Due' } : { status: 'active', label: 'Active' };
  }
  return { status: row.status, label: row.status === 'cancelled' ? 'Cancelled' : row.status === 'pending' ? 'Pending' : 'Expired' };
}

/**
 * Each member's standing, keyed by member id: `status`/`label` for the STATUS
 * column (account override applied), `membership` for the membership alone,
 * and the membership the desk means — the one running today, else the newest
 * running one, else the newest of any kind.
 */
export async function loadMembershipStanding(
  members: readonly { id: string; status: string }[],
  { money = false }: { money?: boolean } = {},
) {
  const supabase = await createServerSupabase();
  const ids = members.map((member) => member.id);
  const [memberships, organization] = await Promise.all([
    ids.length === 0
      ? Promise.resolve({ data: [] as Row[] })
      : money
        ? supabase
            .from('memberships')
            .select('id, member_id, status, starts_on, ends_on, price_paise, discount_paise, currency, plans(name)')
            .in('member_id', ids)
            .order('created_at', { ascending: false })
        : supabase
            .from('memberships')
            .select('id, member_id, status, starts_on, ends_on, plans(name)')
            .in('member_id', ids)
            .order('created_at', { ascending: false }),
    ids.length === 0 ? Promise.resolve({ data: null }) : supabase.from('organizations').select('timezone').maybeSingle(),
  ]);
  const today = todayIn(organization.data?.timezone ?? DEFAULT_TIMEZONE);
  const dueBy = new Date(Date.parse(today) + DUE_WITHIN_DAYS * MS_PER_DAY).toISOString().slice(0, today.length);
  const isLive = (row: Row) => RUNNING.includes(row.status)
    && (row.starts_on === null || row.starts_on <= today) && (row.ends_on === null || row.ends_on >= today);
  // Running today beats running, which beats anything else.
  const outranks = (row: Row, held: Row) => (isLive(row) && !isLive(held))
    || (RUNNING.includes(row.status) && !RUNNING.includes(held.status));

  // Newest first, so a later (older) row replaces the held one only by outranking it.
  const chosen = new Map<string, Row>();
  for (const row of (memberships.data ?? []) as Row[]) {
    const held = chosen.get(row.member_id);
    if (held === undefined || outranks(row, held)) chosen.set(row.member_id, row);
  }

  return new Map(members.map((member) => {
    const row = chosen.get(member.id);
    const endsOn = row?.ends_on ?? null;
    const membership = membershipWord(row, today, dueBy);
    const account = ACCOUNT_OVERRIDES.has(member.status) ? { status: member.status, label: member.status === 'blocked' ? 'Blocked' : 'Cancelled' } : null;
    return [member.id, {
      ...(account ?? membership),
      membership,
      plan: row?.plans?.name ?? null,
      startsOn: row?.starts_on ?? null,
      endsOn,
      ended: endsOn !== null && endsOn < today,
      running: row !== undefined && RUNNING.includes(row.status),
      live: row !== undefined && isLive(row),
      price: row?.price_paise === undefined || row.currency === undefined
        ? null
        : { paise: membershipNetPrice(row.price_paise, row.discount_paise ?? 0), currency: row.currency },
    }] as const;
  }));
}
