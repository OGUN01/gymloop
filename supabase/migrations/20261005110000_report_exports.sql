-- RPE-001…009/013 (CSV-first delivery) — the two database operations behind the
-- owner report exports. Frozen authority:
-- openspec/changes/report-exports/proposal.md, § "Narrow proposed architecture":
-- one bounded invoker data operation per artifact, and a definer that elevates
-- ONLY audit append. The invoice half (RPE-010…012) is deferred and ships
-- nothing here.
--
--   public.export_report_snapshot(p_dataset text, p_from date, p_through date,
--     p_branch_id uuid, p_row_cap integer) returns jsonb
--     — security INVOKER: every source row is read under the calling owner's
--       RLS context; there is no bypass role, no materialized copy. One
--       statement per dataset population, ordered by the dataset's frozen
--       basis, capped at p_row_cap + 1 rows so the caller can disclose
--       has_more and refuse an oversize export whole.
--   public.append_report_export_event(p_event text, p_export_id uuid,
--     p_details jsonb) returns void
--     — security DEFINER whose single elevation is the audit_log append:
--       event vocabulary and the details allowlist are enforced, the actor,
--       role and tenant are taken from the caller's verified claims (never
--       from p_details), and a repeated event for the same export id is a
--       read-only no-op so an uncertain network retry cannot double-write.
--
-- Refusal mapping reuses the shared precedence classes only: 42501 actor,
-- 22023 shape/zone/vocabulary, 23514 allowlist invariant. No new GL number.
-- The direct audit_log INSERT denial (suite H1) is the existing
-- privilege/RLS posture and is untouched here.

-- ---------------------------------------------------------------------------
-- Private pure formatters (no data access, no elevation). They exist so the
-- projection's stamps are written once and identically for every row.
-- ---------------------------------------------------------------------------

create or replace function app.rpe_zone_offset(p_instant timestamptz, p_zone text)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  -- The offset of p_zone at p_instant, rendered as +HH:MM / -HH:MM. The wall
  -- clock is reinterpreted as UTC and differenced against the true instant.
  select
    case
      when (p_instant at time zone p_zone) at time zone 'UTC' < p_instant then '-'
      else '+'
    end
    || lpad(
      extract(hour from (
        case
          when (p_instant at time zone p_zone) at time zone 'UTC' < p_instant
            then p_instant - ((p_instant at time zone p_zone) at time zone 'UTC')
            else ((p_instant at time zone p_zone) at time zone 'UTC') - p_instant
        end
      ))::int::text, 2, '0')
    || ':' ||
    lpad(
      extract(minute from (
        case
          when (p_instant at time zone p_zone) at time zone 'UTC' < p_instant
            then p_instant - ((p_instant at time zone p_zone) at time zone 'UTC')
            else ((p_instant at time zone p_zone) at time zone 'UTC') - p_instant
        end
      ))::int::text, 2, '0')
$$;

create or replace function app.rpe_local_stamp(p_instant timestamptz, p_zone text)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  -- The wall-clock stamp in p_zone with its own offset, RPE-008's local form.
  select to_char(p_instant at time zone p_zone, 'YYYY-MM-DD"T"HH24:MI:SS')
    || app.rpe_zone_offset(p_instant, p_zone)
$$;

create or replace function app.rpe_utc_stamp(p_instant timestamptz)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  -- ISO-8601 UTC with the Z suffix; a null instant stays null, never inferred.
  select to_char(p_instant at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
$$;

create or replace function app.rpe_money_display(p_amount_paise bigint, p_currency text)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  -- The presentation form of the same paise: exact integer-paise arithmetic
  -- only (no float), currency carried explicitly for non-INR rows. This is a
  -- presentation column; the canonical value is amount_paise text beside it.
  select case when p_amount_paise < 0 then '-' else '' end
    || (case when p_currency = 'INR' then '₹' else p_currency || ' ' end)
    || (abs(p_amount_paise) / 100)::text
    || '.'
    || lpad((abs(p_amount_paise) % 100)::text, 2, '0')
$$;

-- ---------------------------------------------------------------------------
-- export_report_snapshot — the one bounded invoker data operation per artifact
-- ---------------------------------------------------------------------------

create or replace function public.export_report_snapshot(
  p_dataset text,
  p_from date,
  p_through date,
  p_branch_id uuid,
  p_row_cap integer
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid := app.current_tenant_id();
  v_zone text;
  v_from_instant timestamptz;
  v_through_instant timestamptz;
  v_rows jsonb;
  v_more boolean;
begin
  -- RPE-001: the actor revalidates FIRST — before any parameter, target or
  -- source fact is inspected. An impersonation/preview claim, a missing or
  -- non-owner identity, and a stale/unbound/deactivated staff row all refuse
  -- identically, so a refused caller learns nothing about the request.
  if app.current_impersonation_id() is not null
    or v_actor is null
    or app.current_app_role() is distinct from 'gym_owner'
  then
    raise insufficient_privilege
      using message = 'report exports are available to the gym owner only';
  end if;

  if not exists (
    select 1
    from public.staff s
    where s.id = app.current_staff_id()
      and s.user_id = v_actor
      and s.tenant_id = v_tenant
      and s.role = 'gym_owner'
      and s.is_active
  ) then
    raise insufficient_privilege
      using message = 'report exports are available to the gym owner only';
  end if;

  -- RPE-003: the bounded exact request — dataset vocabulary, real calendar
  -- dates, ordered range, a positive row cap. Validation errors are 22023;
  -- nothing has been read yet.
  if p_dataset is null or p_dataset not in ('payments', 'attendance', 'members') then
    raise invalid_parameter_value
      using message = 'dataset must be payments, attendance or members';
  end if;
  if p_from is null or p_through is null then
    raise invalid_parameter_value using message = 'both range dates are required';
  end if;
  if p_from > p_through then
    raise invalid_parameter_value using message = 'the range start must be on or before its end';
  end if;
  if p_row_cap is null or p_row_cap < 1 then
    raise invalid_parameter_value using message = 'the row cap must be a positive count';
  end if;

  -- RPE-003: the gym timezone validates explicitly — an invalid configured
  -- zone refuses (22023) instead of fabricating UTC analytics or silently
  -- falling back. The effective zone is disclosed in the payload.
  select o.timezone
    into v_zone
    from public.organizations o
    where o.id = v_tenant;
  if v_zone is null
    or not exists (select 1 from pg_catalog.pg_timezone_names z where z.name = v_zone)
  then
    raise invalid_parameter_value
      using message = 'the gym timezone is not a valid IANA zone';
  end if;

  -- The inclusive gym-local range [from midnight, midnight after through).
  v_from_instant := p_from::timestamp at time zone v_zone;
  v_through_instant := (p_through + 1)::timestamp at time zone v_zone;

  if p_dataset = 'payments' then
    -- RPE-004/005: one statement, one snapshot, ordered (created_at, id),
    -- capped at cap+1 so has_more is honest. Money crosses as canonical
    -- decimal text; attempts and terminal states both appear; a null paid
    -- time or receipt stays blank; an erased member's name and code are
    -- blank while the financial row survives; cross-currency rows keep
    -- their own currency and are never summed. The branch filter is the
    -- payment member's CURRENT branch (labelled as such by the caller); a
    -- missing RLS-visible branch association cannot satisfy it, and an
    -- unknown or foreign branch is the same empty scope as any other miss.
    select coalesce(max(q.rn) > p_row_cap, false),
           coalesce(
             jsonb_agg(q.row_json order by q.created_at, q.id) filter (where q.rn <= p_row_cap),
             '[]'::jsonb
           )
      into v_more, v_rows
      from (
        select row_number() over (order by p.created_at, p.id) as rn,
               p.created_at,
               p.id,
               jsonb_build_object(
                 'payment_id', p.id,
                 'member_id', p.member_id,
                 'member_code', case when m.erased_at is null then m.member_code end,
                 'current_member_name', case when m.erased_at is null then m.full_name end,
                 'amount_paise', p.amount_paise::text,
                 'amount_display', app.rpe_money_display(p.amount_paise, p.currency),
                 'currency', p.currency,
                 'status', p.status::text,
                 'method', p.method,
                 'created_at_utc', app.rpe_utc_stamp(p.created_at),
                 'paid_at_utc', app.rpe_utc_stamp(p.paid_at),
                 'receipt_number', p.receipt_number
               ) as row_json
        from (
          select p2.*
          from public.payments p2
          left join public.members m2 on m2.id = p2.member_id
          where p2.created_at >= v_from_instant
            and p2.created_at < v_through_instant
            and (p_branch_id is null or m2.branch_id = p_branch_id)
          order by p2.created_at, p2.id
          limit p_row_cap + 1
        ) p
        left join public.members m on m.id = p.member_id
      ) q;

  elsif p_dataset = 'attendance' then
    -- An invalid nonnull BRANCH zone refuses for the affected population
    -- (RPE-003), exactly like the gym zone — never a fabricated stamp.
    if exists (
      select 1
      from public.branches b
      where b.tenant_id = v_tenant
        and b.timezone is not null
        and not exists (
          select 1 from pg_catalog.pg_timezone_names z where z.name = b.timezone
        )
    ) then
      raise invalid_parameter_value
        using message = 'a branch timezone is not a valid IANA zone';
    end if;

    -- Recorded attendance events only: the stored branch, the branch's own
    -- zone (null inherits the gym zone, disclosed), ordering by
    -- (checked_in_at, id), the optional check-out and the offline/replay
    -- provenance stamps kept as recorded. Never bookings, never inferred
    -- presence, never a dwell-time computation.
    select coalesce(max(q.rn) > p_row_cap, false),
           coalesce(
             jsonb_agg(q.row_json order by q.checked_in_at, q.id) filter (where q.rn <= p_row_cap),
             '[]'::jsonb
           )
      into v_more, v_rows
      from (
        select row_number() over (order by a.checked_in_at, a.id) as rn,
               a.checked_in_at,
               a.id,
               jsonb_build_object(
                 'attendance_id', a.id,
                 'member_id', a.member_id,
                 'member_code', case when m.erased_at is null then m.member_code end,
                 'current_member_name', case when m.erased_at is null then m.full_name end,
                 'branch_id', a.branch_id,
                 'source', a.source::text,
                 'checked_in_at_utc', app.rpe_utc_stamp(a.checked_in_at),
                 'checked_in_local', app.rpe_local_stamp(a.checked_in_at, coalesce(b.timezone, v_zone)),
                 'checked_out_at_utc', app.rpe_utc_stamp(a.checked_out_at),
                 'offline_recorded_at_utc', app.rpe_utc_stamp(a.offline_recorded_at),
                 'replayed_at_utc', app.rpe_utc_stamp(a.replayed_at)
               ) as row_json
        from (
          select a2.*
          from public.attendance a2
          where a2.tenant_id = v_tenant
            and a2.checked_in_at >= v_from_instant
            and a2.checked_in_at < v_through_instant
            and (p_branch_id is null or a2.branch_id = p_branch_id)
          order by a2.checked_in_at, a2.id
          limit p_row_cap + 1
        ) a
        left join public.members m on m.id = a.member_id
        left join public.branches b on b.id = a.branch_id
      ) q;

  else
    -- members: the current non-erased joining cohort — joined_on is a direct
    -- calendar-date comparison (no instant arithmetic), the branch is the
    -- member's current one, and no DOB, guardian detail, note, consent
    -- record or account id ever enters the projection.
    select coalesce(max(q.rn) > p_row_cap, false),
           coalesce(
             jsonb_agg(q.row_json order by q.joined_on, q.id) filter (where q.rn <= p_row_cap),
             '[]'::jsonb
           )
      into v_more, v_rows
      from (
        select row_number() over (order by m.joined_on, m.id) as rn,
               m.joined_on,
               m.id,
               jsonb_build_object(
                 'member_id', m.id,
                 'member_code', m.member_code,
                 'full_name', m.full_name,
                 'phone', m.phone,
                 'email', m.email,
                 'branch_id', m.branch_id,
                 'status', m.status::text,
                 'joined_on', m.joined_on::text
               ) as row_json
        from (
          select m2.*
          from public.members m2
          where m2.tenant_id = v_tenant
            and m2.erased_at is null
            and m2.joined_on >= p_from
            and m2.joined_on <= p_through
            and (p_branch_id is null or m2.branch_id = p_branch_id)
          order by m2.joined_on, m2.id
          limit p_row_cap + 1
        ) m
      ) q;
  end if;

  -- RPE-002/008: one payload — the capped rows, the honest has_more, and the
  -- validated gym zone the caller stamps into every record and the audit.
  return jsonb_build_object('rows', v_rows, 'has_more', v_more, 'timezone', v_zone);
end;
$$;

revoke execute on function public.export_report_snapshot(text, date, date, uuid, integer)
  from public, anon, service_role;
grant execute on function public.export_report_snapshot(text, date, date, uuid, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- append_report_export_event — the ONLY elevation: audit append
-- ---------------------------------------------------------------------------

create or replace function public.append_report_export_event(
  p_event text,
  p_export_id uuid,
  p_details jsonb
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_base_keys text[] := array[
    'tenant_id', 'actor_user_id', 'actor_role', 'dataset', 'range_from',
    'range_through', 'range_basis', 'timezone', 'branch_scope', 'row_count'
  ];
  v_release_keys text[] := array['byte_count', 'artifact_sha256'];
  v_key text;
  v_allowed text[];
  v_actor uuid := auth.uid();
begin
  -- RPE-009: the event's actor is the CALLER's verified claims — a member
  -- identity, an anonymous request or an impersonating session appends
  -- nothing. This check runs before any argument validation, so a refused
  -- caller learns nothing about the event contract.
  if v_actor is null
    or app.current_impersonation_id() is not null
    or app.current_app_role() is distinct from 'gym_owner'
    or app.current_staff_id() is null
  then
    raise insufficient_privilege
      using message = 'report export audit events attribute the verified gym owner only';
  end if;

  if p_event is null
    or p_event not in ('report_export.prepared', 'report_export.released')
  then
    raise invalid_parameter_value
      using message = 'the audit event must be report_export.prepared or report_export.released';
  end if;
  if p_export_id is null then
    raise invalid_parameter_value using message = 'the export id is required';
  end if;
  if p_details is null then
    raise invalid_parameter_value using message = 'the audit details are required';
  end if;

  -- No arbitrary payloads: the details allowlist is the route's exact key set,
  -- plus the release digest facts on the released event only. Exported row
  -- content can never enter the audit (RPE-009).
  v_allowed := case
    when p_event = 'report_export.released' then v_base_keys || v_release_keys
    else v_base_keys
  end;
  for v_key in select jsonb_object_keys(p_details) loop
    if not (v_key = any (v_allowed)) then
      raise exception
        using message = format('the audit detail key %L is not part of the export contract', v_key),
              errcode = '23514';
    end if;
  end loop;

  -- Idempotent on (export id, event): an uncertain network retry of the same
  -- event is a read-only no-op, never a second audit row.
  if exists (
    select 1
    from public.audit_log a
    where a.record_type = 'report_export'
      and a.record_id = p_export_id
      and a.action = p_event
  ) then
    return;
  end if;

  -- The appended row attributes the caller's claims — a spoofed actor inside
  -- the details never attributes the audit row.
  insert into public.audit_log (tenant_id, actor_user_id, actor_role, action, record_type, record_id, after)
  values (
    app.current_tenant_id(),
    v_actor,
    app.current_app_role()::public.app_role,
    p_event,
    'report_export',
    p_export_id,
    p_details
  );
end;
$$;

revoke execute on function public.append_report_export_event(text, uuid, jsonb)
  from public, anon, service_role;
grant execute on function public.append_report_export_event(text, uuid, jsonb)
  to authenticated;
