import { apiFail, staffSession, PG_INSUFFICIENT_PRIVILEGE, type StaffSession } from '../../../../lib/api';
import { addDays, backToMember, dateField, formField } from '../shared';

/**
 * POST /api/memberships/pauses — request a freeze, or decide one.
 *
 * One handler for both halves because they are one flow over one row: the
 * request writes it, the decision stamps it, and a `pauseId` in the form is
 * what separates them. Splitting them would put the same `membership_pauses`
 * knowledge — who may touch it, what "already decided" means — in two files.
 *
 * The session is the caller's own throughout (`staffSession()` builds the
 * client from the request's cookies), so every write here is judged by
 * `membership_pauses_tenant_write`: `is_front_office()` inside the caller's own
 * tenant. Nothing on this path holds a `service_role` key.
 *
 * Both configurable numbers come from the gym's own `organization_settings` —
 * `pause_approver_role` and `max_freeze_days_per_year`. Neither has a default
 * in this file, deliberately: a fallback here would be a second answer to a
 * question the row already answers, and it would be the answer that applies
 * exactly when the real one failed to load.
 */
export async function POST(request: Request): Promise<Response> {
  const caller = await staffSession();
  if ('failure' in caller) return caller.failure;
  const { supabase, tenantId, staffId } = caller.session;

  const form = await request.formData();
  const memberId = formField(form, 'memberId');
  const pauseId = formField(form, 'pauseId');

  // Only ever the redirect target — never an authorisation input. Every rule
  // below is decided from the pause row and the JWT, not from this field.
  if (!memberId) {
    return apiFail('bad_request', 'member_required', 'That form did not name a member.');
  }

  return pauseId
    ? decide(request, { supabase, staffId }, memberId, pauseId, formField(form, 'decision'))
    : requestPause(request, { supabase, tenantId, staffId }, memberId, form);
}

/** A staff member asks for a freeze. It is not a freeze until somebody decides. */
async function requestPause(
  request: Request,
  caller: Pick<StaffSession, 'supabase' | 'tenantId' | 'staffId'>,
  memberId: string,
  form: FormData,
): Promise<Response> {
  const membershipId = formField(form, 'membershipId');
  const startsOn = dateField(form, 'startsOn');
  const endsOn = dateField(form, 'endsOn');
  const reason = formField(form, 'reason');

  if (!membershipId || startsOn === null || endsOn === null) {
    return backToMember(request, memberId, 'invalid');
  }
  // The table's own check is `reason <> ''`, which a single space satisfies
  // (docs/decisions.md OPEN-011). `formField` trimmed it, so this is the
  // stronger test the column cannot currently make.
  if (!reason) return backToMember(request, memberId, 'reason_required');
  if (endsOn < startsOn) return backToMember(request, memberId, 'dates_reversed');

  const { error } = await caller.supabase.from('membership_pauses').insert({
    tenant_id: caller.tenantId,
    membership_id: membershipId,
    starts_on: startsOn,
    ends_on: endsOn,
    reason,
    requested_by_staff_id: caller.staffId,
  });

  if (error === null) return backToMember(request, memberId);
  return backToMember(
    request,
    memberId,
    error.code === PG_INSUFFICIENT_PRIVILEGE ? 'not_permitted' : 'pause_failed',
  );
}

/** The approver's answer, and the gym's freeze budget applied to it. */
async function decide(
  request: Request,
  caller: Pick<StaffSession, 'supabase' | 'staffId'>,
  memberId: string,
  pauseId: string,
  decision: string,
): Promise<Response> {
  const { supabase, staffId } = caller;

  if (decision !== 'approve' && decision !== 'reject') {
    return backToMember(request, memberId, 'invalid');
  }

  const { data: settings } = await supabase
    .from('organization_settings')
    .select('pause_approver_role, max_freeze_days_per_year')
    .maybeSingle();

  if (!settings) return backToMember(request, memberId, 'no_settings');

  // The caller's role is read from `staff`, not from the JWT copy of it: the
  // row is what `pause_approver_role` was configured against, and a token
  // minted before a demotion still carries the old label until it refreshes.
  const { data: me } = await supabase
    .from('staff')
    .select('role')
    .eq('id', staffId)
    .maybeSingle();

  if (me?.role !== settings.pause_approver_role) {
    return backToMember(request, memberId, 'not_approver');
  }

  const { data: pause } = await supabase
    .from('membership_pauses')
    .select('starts_on, ends_on, approved_at, rejected_at, memberships!inner(member_id)')
    .eq('id', pauseId)
    .maybeSingle();

  if (!pause) return backToMember(request, memberId, 'pause_unknown');
  if (pause.approved_at !== null || pause.rejected_at !== null) {
    return backToMember(request, memberId, 'already_decided');
  }

  if (decision === 'approve') {
    const overBudget = await exceedsFreezeBudget(
      supabase,
      pause.memberships.member_id,
      pause.starts_on,
      pause.ends_on,
      settings.max_freeze_days_per_year,
    );
    if (overBudget) return backToMember(request, memberId, 'freeze_budget');
  }

  // `.is('approved_at', null).is('rejected_at', null)` repeats the test above
  // as part of the write, so two approvers pressing at once produce one
  // decision rather than the second overwriting the first. It is the same
  // reasoning as leaving the one-live rule to its unique index: the guard
  // belongs in the statement, not in the gap before it.
  const stamp = new Date().toISOString();
  const { error } = await supabase
    .from('membership_pauses')
    .update(
      decision === 'approve'
        ? { approved_by_staff_id: staffId, approved_at: stamp }
        : // There is no `rejected_by_staff_id` column, so a rejection records
          // when but not who. Reusing `approved_by_staff_id` for the rejecter
          // would make the column mean two opposite things.
          { rejected_at: stamp },
    )
    .eq('id', pauseId)
    .is('approved_at', null)
    .is('rejected_at', null);

  if (error === null) return backToMember(request, memberId);
  return backToMember(
    request,
    memberId,
    error.code === PG_INSUFFICIENT_PRIVILEGE ? 'not_permitted' : 'decision_failed',
  );
}

/**
 * Would approving this pause take the member past the gym's
 * `max_freeze_days_per_year`?
 *
 * Counted per member rather than per membership, because a member who renews
 * mid-year would otherwise get a fresh budget by buying a new plan — the cap is
 * on the person's year, not on a row's. The year is the calendar year of the
 * pause's start; `organization_settings.financial_year_start_month` exists and
 * governs invoice numbering, and nothing in the specs says the freeze budget
 * follows it.
 *
 * ponytail: this is a read-then-write, so two approvers deciding two different
 * pauses in the same second can both pass a budget that only admits one. The
 * only fix that closes it is a constraint trigger on `membership_pauses`, which
 * is a migration and outside this session's scope — reported rather than
 * approximated with a lock.
 */
async function exceedsFreezeBudget(
  supabase: StaffSession['supabase'],
  memberId: string,
  startsOn: string,
  endsOn: string,
  maxDaysPerYear: number,
): Promise<boolean> {
  const year = startsOn.split('-')[0] ?? '';

  const { data: approved } = await supabase
    .from('membership_pauses')
    .select('starts_on, ends_on, memberships!inner(member_id)')
    .eq('memberships.member_id', memberId)
    .not('approved_at', 'is', null)
    .gte('starts_on', `${year}-01-01`)
    .lte('starts_on', `${year}-12-31`);

  const used = (approved ?? []).reduce((total, row) => total + dayCount(row.starts_on, row.ends_on), 0);

  return used + dayCount(startsOn, endsOn) > maxDaysPerYear;
}

/**
 * Days from one calendar day to another, both ends counted — a pause that
 * starts and ends on the same day is one day of freeze, not zero.
 *
 * Stepped a day at a time rather than subtracting milliseconds, so there is no
 * `MS_PER_DAY` here for AGENTS.md rule 4 to object to, and no rounding question
 * around a DST boundary if the product ever leaves India. A year's worth of
 * pauses is a few hundred iterations.
 */
function dayCount(startsOn: string, endsOn: string): number {
  let days = 0;
  for (let day = startsOn; day <= endsOn; day = addDays(day, 1)) days += 1;
  return days;
}
