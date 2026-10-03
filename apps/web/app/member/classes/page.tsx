import { CLASS_LIMITS, classDayStrip, toLocalDate, humanize } from '@gymloop/shared';
import { requireAudience } from '../../../lib/identity-session';
import { requireOriginalMember } from '../../../lib/member-action-caller';
import { loadBusinessOrganization, loadBusinessNouns } from '../../../lib/business-type';
import { loadMemberClassSchedule } from '../../../lib/classes';
import { MemberClassesView } from './member-classes-view';
import { ClassesSegments } from './segments';
import '../../styles/classes.css';
export default async function MemberClassesPage() {
  const { supabase, identity } = await requireAudience('member');
  const [gym, nouns, member] = await Promise.all([loadBusinessOrganization(supabase, identity.tenantId), loadBusinessNouns(supabase, identity.tenantId), supabase.from('members').select('branch_id').eq('id', identity.memberId).maybeSingle()]);
  const branch = member.data?.branch_id ? await supabase.from('branches').select('timezone').eq('id', member.data.branch_id).maybeSingle() : null;
  let zone = 'UTC';
  for (const value of [branch?.data?.timezone, gym.data?.timezone]) { if (value) { try { new Intl.DateTimeFormat('en', { timeZone: value }); zone = value; break; } catch { /* SQL uses the same fallback chain. */ } } }
  const today = toLocalDate(new Date(), zone);
  const days = classDayStrip(today, CLASS_LIMITS.horizonDays);
  const window = { from: today, to: days[days.length - 1]! };
  const sessions = await loadMemberClassSchedule(supabase, window);
  const original = { userId: identity.userId, tenantId: identity.tenantId, memberId: identity.memberId };
  const scopeKey = `${original.userId}:${original.tenantId}:${original.memberId}`;
  async function refreshSessions() {
    'use server';
    try {
      const current = await requireOriginalMember(original);
      if (current === null) return null;
      return await loadMemberClassSchedule(current.supabase, window);
    } catch { return null; }
  }
  return <main className="member-route member-portal"><header><p className="cl-eyebrow">{gym.data?.name ?? `Your ${nouns.place}`}</p><h1 className="member-title">{humanize(nouns.classes)}</h1><p>Choose your next {nouns.class}. Included with your current membership.</p></header><ClassesSegments current="classes" /><MemberClassesView key={`${identity.userId}:${identity.tenantId}:${identity.memberId}`} sessions={sessions} today={today} nouns={nouns} scopeKey={scopeKey} refreshSessions={refreshSessions} /></main>;
}
