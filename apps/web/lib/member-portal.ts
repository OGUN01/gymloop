import { DAYS_PER_WEEK, DEFAULT_TIMEZONE, MEMBER_PAGE_SIZE_DEFAULT, MS_PER_DAY, toLocalDate } from '@gymloop/shared';
import { requireAudience } from './identity-session';

function messageBody(payload: unknown): string {
  return payload !== null && typeof payload === 'object' && typeof (payload as { body?: unknown }).body === 'string'
    ? (payload as { body: string }).body
    : '';
}

/** The four member destinations' single caller-session, RLS-scoped fact source. */
export async function loadMemberPortal() {
  const { supabase, identity } = await requireAudience('member');
  const [memberRead, gymRead, settingsRead, branchRead, membershipRead, attendanceRead, messageRead] = await Promise.all([
    supabase.from('members').select('full_name,member_code,email,phone,weekly_goal_visits,rest_days').eq('id', identity.memberId).single(),
    supabase.from('organizations').select('name,gym_code,timezone').eq('id', identity.tenantId).single(),
    supabase.from('organization_settings').select('city,state,weekly_goal_default,week_start_day').eq('tenant_id', identity.tenantId).single(),
    supabase.from('branches').select('name,address').order('is_default', { ascending: false }).limit(1).maybeSingle(),
    supabase.from('memberships').select('status,starts_on,ends_on,plans(name)').eq('member_id', identity.memberId).order('created_at', { ascending: false }).limit(1).maybeSingle(),
    supabase.from('attendance').select('id,checked_in_at,source').eq('member_id', identity.memberId).order('checked_in_at', { ascending: false }).limit(MEMBER_PAGE_SIZE_DEFAULT),
    supabase.from('notifications').select('id,payload,sent_at,status').eq('member_id', identity.memberId).eq('channel', 'in_app').in('status', ['sent', 'delivered']).order('sent_at', { ascending: false }).limit(1).maybeSingle(),
  ]);
  const error = [memberRead, gymRead, settingsRead, branchRead, membershipRead, attendanceRead, messageRead].find((read) => read.error !== null)?.error;
  if (error || !memberRead.data || !gymRead.data || !settingsRead.data) return { errorMessage: 'Your member information could not be loaded.' } as const;

  const timezone = gymRead.data.timezone || DEFAULT_TIMEZONE;
  const today = toLocalDate(new Date(), timezone);
  const todayNumber = Date.parse(`${today}T00:00:00Z`) / MS_PER_DAY;
  const todayWeekday = new Date(`${today}T00:00:00Z`).getUTCDay();
  const weekStart = todayNumber - ((todayWeekday - settingsRead.data.week_start_day + DAYS_PER_WEEK) % DAYS_PER_WEEK);
  const visits = attendanceRead.data ?? [];
  const weekVisits = new Set(visits.map((visit) => toLocalDate(visit.checked_in_at, timezone)).filter((day) => {
    const value = Date.parse(`${day}T00:00:00Z`) / MS_PER_DAY;
    return value >= weekStart && value < weekStart + DAYS_PER_WEEK;
  })).size;
  const membership = membershipRead.data;
  const plan = membership && 'plans' in membership ? membership.plans as { name?: unknown } | null : null;
  return {
    errorMessage: null,
    member: memberRead.data,
    gym: { ...gymRead.data, city: settingsRead.data.city, state: settingsRead.data.state, branchName: branchRead.data?.name ?? 'Main branch', branchAddress: branchRead.data?.address ?? null },
    membership: membership ? { status: membership.status, startsOn: membership.starts_on, endsOn: membership.ends_on, planName: typeof plan?.name === 'string' ? plan.name : 'Membership' } : null,
    visits,
    weekVisits,
    weeklyGoal: memberRead.data.weekly_goal_visits ?? settingsRead.data.weekly_goal_default,
    latestMessage: messageRead.data ? { id: messageRead.data.id, body: messageBody(messageRead.data.payload), sentAt: messageRead.data.sent_at, status: messageRead.data.status } : null,
  } as const;
}
