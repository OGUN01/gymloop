-- run_no_show_scan_all
--
-- The daily scan across every gym, as one call.
--
-- **The loop is here and not in the Edge Function, and that is the point.**
-- `openspec/.../no-show-scan/spec.md` says the cron function is a caller that
-- holds no rule of its own, and "which gyms get scanned" is a rule: a loop that
-- silently skips a gym produces exactly the failure this whole capability is
-- built to prevent — a case never opened, indistinguishable from a member who
-- is fine. In SQL it is reachable by pgTAP; in TypeScript on a scheduler it is
-- reachable by nothing until a gym complains that the red list is empty.
--
-- It returns a row per gym rather than a total. A total cannot tell "forty
-- gyms, nothing to do" from "one gym scanned and thirty-nine skipped", and
-- those are the two outcomes an operator most needs to distinguish.
--
-- `security invoker`, and the grant is what makes it safe rather than the
-- volatility. Under invoker the per-gym function reads through the caller's own
-- policies, so an ordinary staff session calling this would scan its own gym
-- and see zero rows for every other — no elevation, no cross-tenant reach. The
-- execute grant is still revoked from `authenticated` below, because a member
-- of staff has no business running the nightly job by hand, and PostgREST
-- exposes every `public` function it is allowed to.

create or replace function public.run_no_show_scan_all()
returns table (tenant_id uuid, gym text, opened integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  return query
    select o.id,
           o.name,
           app.run_no_show_scan(o.id)
      from public.organizations o
     -- Ordered so a partial run is legible: an operator reading a truncated log
     -- can tell which gyms were reached and which were not.
     order by o.name;
end;
$fn$;

comment on function public.run_no_show_scan_all() is
  'Runs the no-show scan for every gym, one row per gym. Called by the scheduled Edge Function; holds the "which gyms" rule so that it is testable.';

-- Nobody but the scheduler. `authenticated` keeps its own per-gym reach through
-- `app.run_no_show_scan`, which its policies constrain; this wrapper is the
-- operator's entry point and not a member of staff's.
revoke all on function public.run_no_show_scan_all() from public;
grant execute on function public.run_no_show_scan_all() to service_role;
