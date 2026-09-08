-- a_rule_that_only_refuses_belongs_after_the_policy
--
-- `20260908210000` made the pause trigger refuse an insert whose requester is
-- not the acting staff member. It is a `before insert` trigger, so it now
-- answered FIRST -- ahead of `membership_pauses_tenant_write` -- and four
-- assertions in three suites went red, all of them asserting that row security
-- is what refuses a write it owns:
--
--     05_membership_money_rls        37  cross-tenant insert refused by with check
--     05_membership_money_rls        85  insert with no claims refused
--     13_role_matrix_write           21  a trainer may not write a pause
--     h05_membership_money_holdout   61  gate 7, cross-tenant labelling
--
-- **This is ADR-066 again, and I wrote it while quoting ADR-066.** The pair it
-- names is "a privilege boundary crossed in something that runs before the
-- boundary it was meant to respect". Every migration in this sequence has been
-- careful to keep `tenant_id` out of its comparisons for exactly this reason --
-- and then a new rule was added to the same `before` trigger without asking the
-- same question of it.
--
-- Two fixes were rejected before this one, and why matters more than the fix:
--
--   * **Gate the rule on `new.tenant_id = app.current_tenant_id()`.** Fixes 37,
--     85 and 61 and not 21: a trainer writing in their OWN gym is refused by
--     the policy on role, not on tenancy, and the trigger would still answer
--     first.
--   * **Gate it on `is_front_office() or is_platform()`.** Fixes all four and
--     is exactly what ADR-066 forbids: "the fix is never a permission check
--     inside the function -- that check is a second copy of the policy, and the
--     copy is what goes stale." It would have passed CI and been wrong.
--
-- THE FIX IS THE TRIGGER'S TIMING. `app.enforce_pause_decision()` only ever
-- RAISES; it never modifies `new`. A trigger that only refuses does not need to
-- run before the write -- and running before it means adjudicating rows the
-- policy was going to refuse anyway, in front of the mechanism that owns them.
-- As `after insert or update` it fires once row security has admitted the row,
-- so a caller the policy refuses gets `42501` from the policy, and a caller it
-- admits meets every rule here unchanged. Raising in an AFTER trigger aborts
-- the statement exactly as before.
--
--     A rule that only refuses belongs after the policy.
--     Only a rule that must modify the row needs to run before it.
--
-- That is why `attendance_enforce_check_in` stays `before insert` and is not
-- touched here: it stamps `tenant_id`, `branch_id` and `assisted_by_staff_id`
-- onto the row, so it has to run first. `app.enforce_attendance_written_once()`
-- also stays: it compares OLD to NEW and subtracts `tenant_id` from both sides,
-- which is the same discipline reached a different way -- it declines to have
-- an opinion about the column the policy owns.
--
-- The function body is unchanged. Only the trigger's timing changes, so this
-- migration is four lines of DDL and the rest is the reason.

drop trigger if exists membership_pauses_enforce_decision on public.membership_pauses;

create trigger membership_pauses_enforce_decision
  after insert or update on public.membership_pauses
  for each row execute function app.enforce_pause_decision();
