-- pause_decision_on_insert_and_stays_decided
--
-- Two reds from the blind pgTAP suite for the pause-decision spec
-- (`supabase/tests/17_pause_decision.sql`, written from the spec by a session
-- that never read `20260908090000_*`). Both are the same defect the previous
-- migration was written to close, in the two places it did not look.
--
-- 1. THE TRIGGER WAS `before update` ONLY, so a pause could be INSERTED already
--    approved and meet no rule at all. Every check lived on the transition from
--    pending to approved, and an insert has no transition -- it arrives at the
--    destination. `membership_pauses` grants `insert` to `authenticated` and its
--    write policy is `is_front_office()`, so this was reachable by any front
--    desk with `supabase-js`: one statement, self-requested, self-approved,
--    wrong role, accepted. Measured: assertion 27 inserted exactly that row and
--    the trigger never fired.
--
-- 2. AN ALREADY-DECIDED PAUSE COULD BE RE-DECIDED. The old guard read
--
--        if new.approved_at is null or old.approved_at is not null then
--          return new;
--
--    and the second half of that condition is backwards. It was written from
--    the spec sentence "apply the approval rules only to a pause that has not
--    already been decided" and it does exactly that -- it stops applying the
--    rules, and then *allows the write*. The scenario under that sentence says
--    "nothing SHALL change and the original approver SHALL still be recorded".
--    So a second, equally-qualified manager could overwrite who granted the
--    freeze, and the record of who authorised money the gym would not collect
--    became the record of whoever wrote last. "Not governed by this rule" was
--    read as "permitted", which is the same reading error as leaving a rule in
--    a caller: the absence of a check is not a decision to allow.
--
-- Forward-only (hard rule 7): `20260908090000_*` is applied, so the function is
-- replaced here rather than edited there. The trigger IS re-created, because
-- its event list changes and `create or replace function` cannot do that.
--
-- `security invoker` unchanged, and for the reason ADR-066 gives: every role
-- that may write a pause can already read `organization_settings` and `staff`
-- (`is_staff()`), so elevation would buy nothing and cost the isolation.

create or replace function app.enforce_pause_decision()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  v_actor_staff_id uuid;
  v_actor_role     public.app_role;
  v_required_role  public.app_role;
  v_was_decided    boolean := false;
begin
  v_actor_staff_id := app.current_staff_id();

  -- No acting staff session: `postgres` (the seed, every pgTAP fixture) and
  -- `service_role`. Both bypass row security by design and are trusted
  -- contexts; imposing the rule on them would break the fixtures without
  -- protecting anything a policy is not already protecting.
  if v_actor_staff_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    v_was_decided := old.approved_at is not null or old.rejected_at is not null;
  end if;

  -- A decision already made is not re-openable. Refused rather than ignored:
  -- silently discarding the columns would tell the caller their approval was
  -- recorded when the row still names someone else. Other columns are left to
  -- the write policy, so correcting a typo in the reason still works.
  if v_was_decided then
    if new.approved_at        is distinct from old.approved_at
    or new.approved_by_staff_id is distinct from old.approved_by_staff_id
    or new.rejected_at        is distinct from old.rejected_at then
      raise exception 'pause decision refused: this pause was already decided, and the decision cannot be rewritten'
        using errcode = 'GL024';
    end if;
    return new;
  end if;

  -- Only recording an approval is governed. A rejection needs no configured
  -- role and no second person -- refusing a freeze is not the commercial act
  -- granting one is -- and on an update every other column is already governed
  -- by the write policy.
  if new.approved_at is null then
    return new;
  end if;

  if new.approved_by_staff_id is distinct from v_actor_staff_id then
    raise exception 'pause approval refused: the approver recorded (%) is not the acting staff member (%)',
      new.approved_by_staff_id, v_actor_staff_id
      using errcode = 'GL020';
  end if;

  if new.approved_by_staff_id is not distinct from new.requested_by_staff_id then
    raise exception 'pause approval refused: staff member % requested this pause and cannot also approve it',
      v_actor_staff_id
      using errcode = 'GL021';
  end if;

  select s.pause_approver_role into v_required_role
    from public.organization_settings s
   where s.tenant_id = new.tenant_id;

  if v_required_role is null then
    raise exception 'pause approval refused: gym % has no organization_settings row, so no approver role is configured', new.tenant_id
      using errcode = 'GL022';
  end if;

  select st.role into v_actor_role
    from public.staff st
   where st.id = v_actor_staff_id
     and st.tenant_id = new.tenant_id;

  if v_actor_role is distinct from v_required_role then
    raise exception 'pause approval refused: this gym requires % to approve a pause, and the acting staff member is %',
      v_required_role, coalesce(v_actor_role::text, 'not a member of this gym')
      using errcode = 'GL023';
  end if;

  return new;
end;
$$;

drop trigger if exists membership_pauses_enforce_decision on public.membership_pauses;

create trigger membership_pauses_enforce_decision
  before insert or update on public.membership_pauses
  for each row execute function app.enforce_pause_decision();
