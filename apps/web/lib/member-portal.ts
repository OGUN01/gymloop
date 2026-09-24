import { DAYS_PER_WEEK, DEFAULT_TIMEZONE, MEMBER_PAGE_SIZE_DEFAULT, MS_PER_DAY, memberStreak, toLocalDate } from '@gymloop/shared';
import { requireAudience } from './identity-session';

type MemberPortalSettings = {
  city: string | null;
  state: string | null;
  weekly_goal_default: number;
  week_start_day: number;
  streak_rule_type: string;
};

type MemberPortalSettingsQuery = PromiseLike<{ data: MemberPortalSettings[] | null; error: { message: string } | null }>;

function memberPortalSettings(client: Awaited<ReturnType<typeof requireAudience>>['supabase']): MemberPortalSettingsQuery {
  return (client as unknown as { rpc(name: 'read_member_portal_settings'): MemberPortalSettingsQuery }).rpc('read_member_portal_settings');
}

type MemberMoneyRead = { receipts?: Record<string, unknown>[]; addOns?: Record<string, unknown>[] };
type MemberMoneyQuery = PromiseLike<{ data: MemberMoneyRead | null; error: { message: string } | null }>;

function memberMoney(client: Awaited<ReturnType<typeof requireAudience>>['supabase']): MemberMoneyQuery {
  return (client as unknown as { rpc(name: 'read_member_mobile_money'): MemberMoneyQuery }).rpc('read_member_mobile_money');
}

function text(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function messageBody(payload: unknown): string {
  return payload !== null && typeof payload === 'object' && typeof (payload as { body?: unknown }).body === 'string'
    ? (payload as { body: string }).body
    : '';
}

/** The four member destinations' single caller-session, RLS-scoped fact source. */
export async function loadMemberPortal() {
  const { supabase, identity } = await requireAudience('member');
  const [memberRead, gymRead, settingsRead, branchRead, membershipRead, attendanceRead, messageRead, pausesRead, holidaysRead, moneyRead] = await Promise.all([
    supabase.from('members').select('full_name,member_code,email,phone,weekly_goal_visits,rest_days').eq('id', identity.memberId).single(),
    supabase.from('organizations').select('name,gym_code,timezone').eq('id', identity.tenantId).single(),
    memberPortalSettings(supabase),
    supabase.from('branches').select('name,address').order('is_default', { ascending: false }).limit(1).maybeSingle(),
    supabase.from('memberships').select('status,starts_on,ends_on,plans(name)').eq('member_id', identity.memberId).order('created_at', { ascending: false }).limit(1).maybeSingle(),
    supabase.from('attendance').select('id,checked_in_at,source').eq('member_id', identity.memberId).order('checked_in_at', { ascending: false }).limit(MEMBER_PAGE_SIZE_DEFAULT),
    supabase.from('notifications').select('id,payload,sent_at,status').eq('member_id', identity.memberId).eq('channel', 'in_app').in('status', ['sent', 'delivered']).order('sent_at', { ascending: false }).limit(1).maybeSingle(),
    supabase.from('membership_pauses').select('starts_on,ends_on,approved_at,rejected_at,memberships!inner(member_id)').eq('memberships.member_id', identity.memberId),
    supabase.from('organization_holidays').select('holiday_on'),
    memberMoney(supabase),
  ]);
  const error = [memberRead, gymRead, settingsRead, branchRead, membershipRead, attendanceRead, messageRead, pausesRead, holidaysRead].find((read) => read.error !== null)?.error;
  const settings = settingsRead.data?.[0] ?? null;
  if (error || !memberRead.data || !gymRead.data || !settings) return { errorMessage: 'Your member information could not be loaded.' } as const;

  const timezone = gymRead.data.timezone || DEFAULT_TIMEZONE;
  const today = toLocalDate(new Date(), timezone);
  const todayNumber = Date.parse(`${today}T00:00:00Z`) / MS_PER_DAY;
  const todayWeekday = new Date(`${today}T00:00:00Z`).getUTCDay();
  const weekStart = todayNumber - ((todayWeekday - settings.week_start_day + DAYS_PER_WEEK) % DAYS_PER_WEEK);
  const visits = attendanceRead.data ?? [];
  const weekVisits = new Set(visits.map((visit) => toLocalDate(visit.checked_in_at, timezone)).filter((day) => {
    const value = Date.parse(`${day}T00:00:00Z`) / MS_PER_DAY;
    return value >= weekStart && value < weekStart + DAYS_PER_WEEK;
  })).size;
  const weeklyGoal = memberRead.data.weekly_goal_visits ?? settings.weekly_goal_default;
  const streakRule = settings.streak_rule_type === 'weekly_goal' ? 'weekly_goal' as const : 'visit' as const;
  const streak = memberStreak({
    rule: streakRule, visits: visits.map((visit) => visit.checked_in_at), asOf: new Date(), timeZone: timezone, restDays: memberRead.data.rest_days,
    pauses: pausesRead.data ?? [], holidays: holidaysRead.data ?? [], goal: weeklyGoal, weekStartDay: settings.week_start_day,
  });
  const money = moneyRead.error ? null : moneyRead.data;
  const membership = membershipRead.data;
  const plan = membership && 'plans' in membership ? membership.plans as { name?: unknown } | null : null;
  return {
    errorMessage: null,
    member: memberRead.data,
    gym: { ...gymRead.data, city: settings.city, state: settings.state, branchName: branchRead.data?.name ?? 'Main branch', branchAddress: branchRead.data?.address ?? null },
    membership: membership ? { status: membership.status, startsOn: membership.starts_on, endsOn: membership.ends_on, planName: typeof plan?.name === 'string' ? plan.name : 'Membership' } : null,
    visits,
    weekVisits,
    weekStart: new Date(weekStart * MS_PER_DAY).toISOString().slice(0, 'YYYY-MM-DD'.length),
    weeklyGoal,
    streak: { current: streak.current, unit: streak.unit, rule: streakRule },
    receipts: money ? (money.receipts ?? []).map((row) => ({ id: text(row.id) ?? '', amountPaise: text(row.amountPaise) ?? '0', currency: text(row.currency) ?? 'INR', paidAt: text(row.paidAt), receiptNumber: text(row.receiptNumber), status: text(row.status) ?? '' })) : null,
    addOns: money ? (money.addOns ?? []).map((row) => ({ name: text(row.name) ?? 'Add-on', status: text(row.status) ?? '', sessionsUsed: typeof row.sessionsUsed === 'number' ? row.sessionsUsed : 0, sessionsTotal: typeof row.sessionsTotal === 'number' ? row.sessionsTotal : null })) : null,
    latestMessage: messageRead.data ? { id: messageRead.data.id, body: messageBody(messageRead.data.payload), sentAt: messageRead.data.sent_at, status: messageRead.data.status } : null,
  } as const;
}
