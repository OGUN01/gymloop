import type { Database } from '@gymloop/db';
import { DAYS_PER_WEEK, DEFAULT_TIMEZONE, MEMBER_PAGE_SIZE_DEFAULT, MS_PER_DAY, memberStreak, toLocalDate } from '@gymloop/shared';
import type { SupabaseClient } from '@supabase/supabase-js';

type DbClient = SupabaseClient<Database>;
type MemberIdentity = { memberId: string; tenantId: string };

export type MemberSnapshot = {
  member: { fullName: string; memberCode: string | null; email: string | null; phone: string; goal: number; restDays: number[] };
  /** `displayName` is the organisation name without its " — {branch}" suffix, for lines that name the branch beside it. */
  gym: { name: string; displayName: string; code: string; timezone: string; city: string | null; state: string | null; branchName: string; branchAddress: string | null };
  membership: { status: string; startsOn: string | null; endsOn: string | null; planName: string } | null;
  visits: { id: string; checkedInAt: string; source: string }[];
  weekVisits: number;
  weekStart: string;
  streak: { current: number; unit: 'day' | 'week'; missed: readonly string[] };
  receipts: { id: string; amountPaise: string; currency: string; paidAt: string | null; receiptNumber: string | null; status: string }[];
  messages: { id: string; body: string; sentAt: string | null; status: string }[];
  consents: { purpose: string; granted: boolean; recordedAt: string }[];
  addOns: { id: string; name: string; status: string; totalPaise: string; currency: string; sessionsUsed: number; sessionsTotal: number | null }[];
};

type MobileMoneyRead = { receipts?: Record<string, unknown>[]; addOns?: Record<string, unknown>[] };
type MobileMoneyQuery = PromiseLike<{ data: MobileMoneyRead | null; error: { message: string } | null }>;
type MemberPortalSettings = { city: string | null; state: string | null; weekly_goal_default: number; week_start_day: number; streak_rule_type: string };
type MemberPortalSettingsQuery = PromiseLike<{ data: MemberPortalSettings[] | null; error: { message: string } | null }>;

function memberMoney(client: DbClient): MobileMoneyQuery {
  return (client as unknown as { rpc(name: 'read_member_mobile_money'): MobileMoneyQuery }).rpc('read_member_mobile_money');
}

function memberPortalSettings(client: DbClient): MemberPortalSettingsQuery {
  return (client as unknown as { rpc(name: 'read_member_portal_settings'): MemberPortalSettingsQuery }).rpc('read_member_portal_settings');
}

function text(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function number(value: unknown): number {
  return typeof value === 'number' ? value : 0;
}

function payloadBody(value: unknown): string {
  return value !== null && typeof value === 'object' && typeof (value as { body?: unknown }).body === 'string'
    ? (value as { body: string }).body
    : '';
}

export async function loadMemberSnapshot(client: DbClient, identity: MemberIdentity): Promise<MemberSnapshot> {
  const [memberRead, gymRead, settingsRead, branchRead, membershipRead, attendanceRead, moneyRead, messagesRead, consentsRead, pausesRead, holidaysRead] = await Promise.all([
    client.from('members').select('full_name,member_code,email,phone,weekly_goal_visits,rest_days,branch_id').eq('id', identity.memberId).eq('tenant_id', identity.tenantId).single(),
    client.from('organizations').select('name,gym_code,timezone').eq('id', identity.tenantId).single(),
    memberPortalSettings(client),
    client.from('branches').select('name,address').eq('tenant_id', identity.tenantId).order('is_default', { ascending: false }).limit(1).maybeSingle(),
    client.from('memberships').select('status,starts_on,ends_on,plans(name)').eq('member_id', identity.memberId).order('created_at', { ascending: false }).limit(1).maybeSingle(),
    client.from('attendance').select('id,checked_in_at,source').eq('member_id', identity.memberId).order('checked_in_at', { ascending: false }).limit(MEMBER_PAGE_SIZE_DEFAULT),
    memberMoney(client),
    client.from('notifications').select('id,payload,sent_at,status').eq('member_id', identity.memberId).eq('channel', 'in_app').in('status', ['sent', 'delivered']).order('sent_at', { ascending: false }).limit(MEMBER_PAGE_SIZE_DEFAULT),
    client.from('consents').select('purpose,granted,recorded_at').eq('member_id', identity.memberId).order('recorded_at', { ascending: false }).limit(MEMBER_PAGE_SIZE_DEFAULT),
    client.from('membership_pauses').select('starts_on,ends_on,approved_at,rejected_at,memberships!inner(member_id)').eq('memberships.member_id', identity.memberId),
    client.from('organization_holidays').select('holiday_on').eq('tenant_id', identity.tenantId),
  ]);

  const firstError = [memberRead, gymRead, settingsRead, branchRead, membershipRead, attendanceRead, moneyRead, messagesRead, consentsRead, pausesRead, holidaysRead]
    .find((result) => result.error !== null)?.error;
  if (firstError) throw new Error(firstError.message);
  const settings = settingsRead.data?.[0] ?? null;
  if (!memberRead.data || !gymRead.data || !settings) throw new Error('Your gym profile is not available.');

  const timezone = gymRead.data.timezone || DEFAULT_TIMEZONE;
  const goal = memberRead.data.weekly_goal_visits ?? settings.weekly_goal_default;
  const visitInstants = (attendanceRead.data ?? []).map((row) => row.checked_in_at);
  const today = toLocalDate(new Date(), timezone);
  const todayNumber = Date.parse(`${today}T00:00:00Z`) / MS_PER_DAY;
  const todayWeekday = new Date(`${today}T00:00:00Z`).getUTCDay();
  const weekStartNumber = todayNumber - ((todayWeekday - settings.week_start_day + DAYS_PER_WEEK) % DAYS_PER_WEEK);
  const weekVisits = new Set(visitInstants.map((instant) => toLocalDate(instant, timezone)).filter((day) => {
    const value = Date.parse(`${day}T00:00:00Z`) / MS_PER_DAY;
    return value >= weekStartNumber && value < weekStartNumber + DAYS_PER_WEEK;
  })).size;
  const streak = memberStreak({
    rule: settings.streak_rule_type, visits: visitInstants, asOf: new Date(), timeZone: timezone, restDays: memberRead.data.rest_days,
    pauses: pausesRead.data ?? [], holidays: holidaysRead.data ?? [], goal, weekStartDay: settings.week_start_day,
  });

  const branchName = branchRead.data?.name ?? 'Main branch';
  const branchSuffix = ` — ${branchName}`;
  const membership = membershipRead.data;
  const planRelation = membership && 'plans' in membership ? membership.plans as { name?: unknown } | null : null;
  return {
    member: { fullName: memberRead.data.full_name, memberCode: memberRead.data.member_code, email: memberRead.data.email, phone: memberRead.data.phone, goal, restDays: memberRead.data.rest_days },
    gym: { name: gymRead.data.name, displayName: gymRead.data.name.endsWith(branchSuffix) ? gymRead.data.name.slice(0, -branchSuffix.length) : gymRead.data.name, code: gymRead.data.gym_code, timezone, city: settings.city, state: settings.state, branchName, branchAddress: branchRead.data?.address ?? null },
    membership: membership ? { status: membership.status, startsOn: membership.starts_on, endsOn: membership.ends_on, planName: text(planRelation?.name, 'Membership') } : null,
    visits: (attendanceRead.data ?? []).map((row) => ({ id: row.id, checkedInAt: row.checked_in_at, source: row.source })),
    weekVisits,
    weekStart: new Date(weekStartNumber * MS_PER_DAY).toISOString().slice(0, 'YYYY-MM-DD'.length),
    streak: { current: streak.current, unit: streak.unit, missed: streak.missed },
    receipts: (moneyRead.data?.receipts ?? []).map((row) => ({ id: text(row.id), amountPaise: text(row.amountPaise), currency: text(row.currency), paidAt: typeof row.paidAt === 'string' ? row.paidAt : null, receiptNumber: typeof row.receiptNumber === 'string' ? row.receiptNumber : null, status: text(row.status) })),
    messages: (messagesRead.data ?? []).map((row) => ({ id: row.id, body: payloadBody(row.payload), sentAt: row.sent_at, status: row.status })),
    consents: (consentsRead.data ?? []).map((row) => ({ purpose: row.purpose, granted: row.granted, recordedAt: row.recorded_at })),
    addOns: (moneyRead.data?.addOns ?? []).map((row) => ({ id: text(row.id), name: text(row.name, 'Add-on'), status: text(row.status), totalPaise: text(row.totalPaise), currency: text(row.currency, 'INR'), sessionsUsed: number(row.sessionsUsed), sessionsTotal: typeof row.sessionsTotal === 'number' ? row.sessionsTotal : null })),
  };
}

export type DeskMember = { id: string; fullName: string; phone: string; status: string; memberCode: string | null };
export async function loadDeskMembers(client: DbClient, query: string): Promise<DeskMember[]> {
  const request = client.from('members').select('id,full_name,phone,status,member_code').order('full_name').limit(MEMBER_PAGE_SIZE_DEFAULT);
  const normalized = query.trim();
  const { data, error } = await request;
  if (error) throw new Error(error.message);
  return (data ?? []).filter((row) => normalized === '' || row.full_name.toLocaleLowerCase().includes(normalized.toLocaleLowerCase()) || row.phone.includes(normalized)).map((row) => ({ id: row.id, fullName: row.full_name, phone: row.phone, status: row.status, memberCode: row.member_code }));
}

export type DeskFollowUp = { id: string; memberId: string; memberName: string; memberPhone: string; daysAbsent: number; nextFollowUpAt: string | null; status: string; openedOn: string | null; lastAttendedOn: string | null; lastFollowUpAt: string | null; lastFollowUpOutcome: string | null };
export async function loadDeskFollowUps(client: DbClient): Promise<DeskFollowUp[]> {
  const { data, error } = await client.from('red_list_cases').select('id,member_id,member_name,member_phone,days_absent,next_follow_up_at,status,opened_on,last_attended_on,last_follow_up_at,last_follow_up_outcome').order('days_absent', { ascending: false }).limit(MEMBER_PAGE_SIZE_DEFAULT);
  if (error) throw new Error(error.message);
  return (data ?? []).flatMap((row) => row.id && row.member_id && row.member_name && row.member_phone && row.status ? [{ id: row.id, memberId: row.member_id, memberName: row.member_name, memberPhone: row.member_phone, daysAbsent: row.days_absent ?? 0, nextFollowUpAt: row.next_follow_up_at, status: row.status, openedOn: row.opened_on, lastAttendedOn: row.last_attended_on, lastFollowUpAt: row.last_follow_up_at, lastFollowUpOutcome: row.last_follow_up_outcome }] : []);
}

export async function loadDefaultBranch(client: DbClient): Promise<{ id: string; name: string } | null> {
  const { data, error } = await client.from('branches').select('id,name').order('is_default', { ascending: false }).limit(1).maybeSingle();
  if (error) throw new Error(error.message);
  return data;
}

/** The seven days of the week the "N of goal" count uses, with visited, future and today flags. */
export function rhythmFor(snapshot: Pick<MemberSnapshot, 'visits' | 'weekStart'> & { gym: { timezone: string } }) {
  const today = toLocalDate(new Date(), snapshot.gym.timezone);
  const visited = new Set(snapshot.visits.map((visit) => toLocalDate(visit.checkedInAt, snapshot.gym.timezone)));
  return Array.from({ length: DAYS_PER_WEEK }, (_, index) => {
    const day = new Date(`${snapshot.weekStart}T12:00:00Z`);
    day.setUTCDate(day.getUTCDate() + index);
    const key = day.toISOString().slice(0, 'YYYY-MM-DD'.length);
    return { key, label: day.toLocaleDateString('en-GB', { weekday: 'short', timeZone: 'UTC' }).slice(0, 1), name: day.toLocaleDateString('en-GB', { weekday: 'long', timeZone: 'UTC' }), visited: visited.has(key), future: key > today, today: key === today };
  });
}
