-- Forward-only Phase 6 communications privilege/precedence repair.
-- 20260915100007 is already in the migration stream and is intentionally not edited.

-- Claim/tenant/staff authority must fail before an RLS-hidden member lookup can
-- turn an invalid caller into a misleading not-found response.
create or replace function app.stamp_consent()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_last_recorded_at timestamptz;
  v_claim_staff uuid;
begin
  if btrim(coalesce(new.version, '')) = '' or btrim(coalesce(new.source, '')) = '' then
    raise exception 'A consent decision requires a non-blank version and source'
      using errcode = 'GL065';
  end if;

  if pg_catalog.row_security_active('public.consents') then
    if auth.uid() is null or app.is_front_office() is not true
       or app.current_tenant_id() is distinct from new.tenant_id
       or app.current_staff_id() is null or app.current_impersonation_id() is not null then
      raise exception 'A consent decision requires a real claim-stamped staff actor' using errcode = '42501';
    end if;
    select s.id into v_claim_staff from public.staff s where s.tenant_id = new.tenant_id
      and s.id = app.current_staff_id() and s.user_id = auth.uid()
      and s.role::text = app.current_app_role() and s.is_active;
    if v_claim_staff is null then
      raise exception 'A consent decision requires a real claim-stamped staff actor' using errcode = '42501';
    end if;
    if new.recorded_by_staff_id is null then
      new.recorded_by_staff_id := v_claim_staff;
    elsif new.recorded_by_staff_id is distinct from v_claim_staff then
      raise exception 'A consent decision names its own claim-stamped actor'
        using errcode = 'GL065';
    end if;
  end if;

  perform 1 from public.members m
   where m.tenant_id = new.tenant_id and m.id = new.member_id
   for update;
  if not found then
    raise exception 'Member not found' using errcode = 'P0002';
  end if;

  select c.recorded_at into v_last_recorded_at
    from public.consents c
   where c.tenant_id = new.tenant_id
     and c.member_id = new.member_id
     and c.purpose = new.purpose
   order by c.recorded_at desc, c.id desc
   limit 1;

  if v_last_recorded_at is null then
    new.recorded_at := clock_timestamp();
  else
    new.recorded_at := greatest(clock_timestamp(), v_last_recorded_at + interval '1 microsecond');
  end if;

  perform app.write_consent_audit(new);
  return new;
end
$fn$;

-- The original one-trigger topology already protects both audit writers with
-- pg_trigger_depth(). The hosted failure was ownership/EXECUTE drift: keep the
-- invariant functions invoker-scoped, make their narrow audit callees owned by
-- postgres, and explicitly admit only the roles that can reach the triggers.
alter function app.write_notification_audit(uuid,uuid,text,jsonb,jsonb,text) owner to postgres;
alter function app.write_consent_audit(public.consents) owner to postgres;
alter function app.notification_audit_shape(public.notifications) owner to postgres;

revoke all on function app.notification_audit_shape(public.notifications) from public, anon;
grant execute on function app.notification_audit_shape(public.notifications) to authenticated, service_role;
revoke all on function app.write_notification_audit(uuid,uuid,text,jsonb,jsonb,text) from public, anon;
grant execute on function app.write_notification_audit(uuid,uuid,text,jsonb,jsonb,text) to authenticated, service_role;
revoke all on function app.write_consent_audit(public.consents) from public, anon;
grant execute on function app.write_consent_audit(public.consents) to authenticated, service_role;
