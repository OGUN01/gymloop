-- PILOT-008 repair: a linked gym-owner retirement is a platform command, not
-- ordinary staff maintenance. Do not use a caller-set GUC or JWT claim as the
-- escape hatch: either can be supplied by a direct SQL caller. The command is
-- SECURITY DEFINER and owns the UPDATE as postgres; direct PostgREST writes
-- retain their authenticated/service execution identity. Cover all UPDATEs and
-- DELETEs and both active states: otherwise a trusted service role could first
-- remove the binding or owner role and deactivate in a second statement,
-- reactivate a retired owner, or remove the retained owner history outright.
create function app.enforce_linked_gym_owner_deactivation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
begin
  if old.role = 'gym_owner'::public.app_role
     and old.user_id is not null
     and current_user <> 'postgres' then
    if tg_op = 'DELETE' then
      raise exception 'Platform commercial write required'
        using errcode = 'GL049', detail = 'platform_commercial_write_required';
    end if;

    if new.user_id is distinct from old.user_id
       or new.role is distinct from old.role
       or new.is_active is distinct from old.is_active then
      raise exception 'Platform commercial write required'
        using errcode = 'GL049', detail = 'platform_commercial_write_required';
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end
$fn$;

create trigger staff_linked_gym_owner_deactivation_invariant
before update or delete on public.staff
for each row execute function app.enforce_linked_gym_owner_deactivation();

revoke all on function app.enforce_linked_gym_owner_deactivation()
  from public, anon, authenticated, service_role;

-- `service_role` inherits Supabase's default table ACLs. A row trigger cannot
-- see TRUNCATE, so remove both destructive privileges explicitly; the DELETE
-- arm above remains defense in depth if a future migration grants DELETE back.
revoke delete, truncate on public.staff from service_role;
