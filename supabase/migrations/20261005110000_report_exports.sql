-- RPE-001…009/013 (CSV-first delivery) — the database operations behind the
-- owner report exports. Frozen authority:
-- openspec/changes/report-exports/proposal.md (RPE-001…009/013) and the frozen
-- mechanical completion in
-- openspec/changes/report-exports/sql-envelope-declaration.md. The invoice
-- half (RPE-010…012) is deferred and ships nothing here.
--
--   public.export_report_snapshot(p_dataset text, p_from date, p_through date,
--     p_branch_id uuid, p_row_cap integer) returns jsonb
--     — VOLATILE SECURITY INVOKER, empty search path, authenticated-only
--       EXECUTE. Actor validation precedes semantic validation, lookup,
--       counting and source access. One containing SQL statement per dataset:
--       the materialized ordered source projection/count under the original
--       caller's RLS, the bounded preparation INSERT from only the five input
--       columns, and the final scalar assembly from the returned derived
--       metadata. Over-cap requests return the refusal envelope with no
--       preparation/audit; a bounded result is returned only after its
--       prepared audit commits with the source operation.
--   app.report_export_preparations — metadata-only retained audit linkage:
--       five caller-supplied input columns, fourteen server-derived columns
--       with no caller defaults, filled by the STABLE invoker derive trigger
--       (which validates actor, exact inputs, zone, boundaries and the
--       complete same-snapshot count, refusing an over-cap INSERT) and
--       audited by the VOLATILE definer trigger (whose only elevation is the
--       audit_log append; it reads no report source). Column grants give
--       authenticated INSERT on the five input columns and SELECT under RLS;
--       no UPDATE/DELETE and no PUBLIC/anon grants.
--   public.append_report_export_event(p_event text, p_export_id uuid,
--     p_details jsonb) returns void
--       — VOLATILE SECURITY DEFINER, empty search path, authenticated-only
--         EXECUTE. The public invocation accepts ONLY
--         p_event = 'report_export.released'; the writer revalidates the
--         active real owner, finds exactly this actor/tenant's prepared UUID
--         (absent/foreign refused), rejects an already-released attempt, and
--         copies every prepared `after` key plus the validated
--         {byte_count, artifact_sha256} pair. The partial unique index
--         audit_log_report_export_event_unique makes a concurrent duplicate
--         release refuse atomically; every fresh download is a fresh export
--         UUID.
--
-- Refusal mapping reuses the shared precedence classes only: 42501 actor,
-- 22023 shape/zone/vocabulary/cap, 23514 allowlist/invariant. No new GL
-- number. The direct audit_log INSERT denial is the existing privilege/RLS
-- posture and is untouched here.

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
-- app.report_export_preparations — metadata-only prepared audit linkage
-- ---------------------------------------------------------------------------

create table app.report_export_preparations (
  -- The five caller-supplied input columns (the only INSERT-able ones).
  dataset text not null,
  range_from date not null,
  range_through date not null,
  branch_id uuid null,
  row_cap integer not null,

  -- The fourteen server-derived columns: no defaults, all NOT NULL, filled
  -- exclusively by the derive trigger; supplied non-null values are refused.
  export_id uuid not null primary key,
  tenant_id uuid not null,
  actor_user_id uuid not null,
  actor_role public.app_role not null,
  format text not null,
  generated_at_utc timestamptz not null,
  snapshot_at_utc timestamptz not null,
  source_cutoff_at_utc timestamptz not null,
  range_basis text not null,
  timezone text not null,
  range_start_utc timestamptz not null,
  range_end_exclusive_utc timestamptz not null,
  branch_scope text not null,
  data_row_count bigint not null
);

-- Prepared rows are immutable retained audit-linkage metadata, not an export
-- cache: no update/delete path exists at the privilege level.
revoke all on app.report_export_preparations from public;
revoke all on app.report_export_preparations from anon;
revoke all on app.report_export_preparations from service_role;
grant select on app.report_export_preparations to authenticated;
grant insert (dataset, range_from, range_through, branch_id, row_cap)
  on app.report_export_preparations to authenticated;

alter table app.report_export_preparations enable row level security;

create policy report_export_preparations_tenant_select
  on app.report_export_preparations
  for select
  to authenticated
  using (
    tenant_id = app.current_tenant_id()
    and actor_user_id = auth.uid()
    and exists (
      select 1
      from public.staff s
      where s.id = app.current_staff_id()
        and s.user_id = auth.uid()
        and s.tenant_id = app.current_tenant_id()
        and s.role = 'gym_owner'
        and s.is_active
    )
  );

create policy report_export_preparations_tenant_insert
  on app.report_export_preparations
  for insert
  to authenticated
  with check (
    tenant_id = app.current_tenant_id()
    and actor_user_id = auth.uid()
    and exists (
      select 1
      from public.staff s
      where s.id = app.current_staff_id()
        and s.user_id = auth.uid()
        and s.tenant_id = app.current_tenant_id()
        and s.role = 'gym_owner'
        and s.is_active
    )
  );

create index report_export_preparations_tenant_actor_export_idx
  on app.report_export_preparations (tenant_id, actor_user_id, export_id);

-- ---------------------------------------------------------------------------
-- app.derive_report_export_preparation — STABLE invoker BEFORE INSERT trigger.
-- The source-selector/validator: actor first, exact inputs, RLS sources,
-- validated zone/boundaries and the complete count, all within the containing
-- statement's snapshot; count > cap refuses the INSERT. It derives UUID, clock
-- stamps and attribution server-side; caller values, GUCs and calling markers
-- are never provenance. UUID generation does not change its source-read
-- snapshot (statement_timestamp is fixed for the containing statement).
-- ---------------------------------------------------------------------------

create or replace function app.derive_report_export_preparation()
returns trigger
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid := app.current_tenant_id();
  v_zone text;
  v_count bigint;
  v_from_instant timestamptz;
  v_through_instant timestamptz;
begin
  -- Derived columns are server-derived only: a caller that supplies any of
  -- them cannot forge provenance, counts or stamps.
  if new.export_id is not null
    or new.tenant_id is not null
    or new.actor_user_id is not null
    or new.actor_role is not null
    or new.format is not null
    or new.generated_at_utc is not null
    or new.snapshot_at_utc is not null
    or new.source_cutoff_at_utc is not null
    or new.range_basis is not null
    or new.timezone is not null
    or new.range_start_utc is not null
    or new.range_end_exclusive_utc is not null
    or new.branch_scope is not null
    or new.data_row_count is not null
  then
    raise invalid_parameter_value
      using message = 'export preparation derived values are server-derived only';
  end if;

  -- Actor first, exactly like the public RPC: impersonation/preview claims,
  -- missing or non-owner identity, and stale/unbound/deactivated staff rows
  -- refuse identically before any other fact is inspected.
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

  -- Exact inputs: dataset vocabulary, ordered real calendar dates, the
  -- inclusive 366-day maximum, a row cap in 1…5000, and a same-tenant branch
  -- (unknown and foreign are one indistinguishable unavailable refusal).
  if new.dataset is null
    or new.dataset not in ('payments', 'attendance', 'members')
  then
    raise invalid_parameter_value
      using message = 'dataset must be payments, attendance or members';
  end if;
  if new.range_from is null or new.range_through is null then
    raise invalid_parameter_value using message = 'both range dates are required';
  end if;
  if new.range_from > new.range_through then
    raise invalid_parameter_value using message = 'the range start must be on or before its end';
  end if;
  if new.range_through - new.range_from + 1 > 366 then
    raise invalid_parameter_value using message = 'the range must not exceed 366 calendar days';
  end if;
  if new.row_cap is null or new.row_cap < 1 or new.row_cap > 5000 then
    raise invalid_parameter_value using message = 'the row cap must be between 1 and 5000';
  end if;
  if new.branch_id is not null and not exists (
    select 1
    from public.branches b
    where b.id = new.branch_id
      and b.tenant_id = v_tenant
  ) then
    raise invalid_parameter_value using message = 'the requested branch is not available';
  end if;

  -- The gym timezone validates explicitly — an invalid configured zone
  -- refuses instead of fabricating UTC stamps or silently falling back.
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

  -- An invalid nonnull BRANCH zone refuses for the affected population
  -- exactly like the gym zone — never a fabricated stamp.
  if new.dataset = 'attendance' and exists (
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

  -- The inclusive gym-local range [from midnight, midnight after through).
  -- Offset transitions use each actual local midnight, not a fixed 24 hours.
  v_from_instant := new.range_from::timestamp at time zone v_zone;
  v_through_instant := (new.range_through + 1)::timestamp at time zone v_zone;

  -- The complete matching count under the caller's RLS, in this statement's
  -- snapshot — the same predicate as the public RPC's projection for the
  -- dataset, so the derived count equals the statement's source projection.
  v_count :=
    case new.dataset
      when 'payments' then (
        select count(*)
        from public.payments p
        left join public.members m on m.id = p.member_id
        where p.created_at >= v_from_instant
          and p.created_at < v_through_instant
          and (new.branch_id is null or m.branch_id = new.branch_id)
      )
      when 'attendance' then (
        select count(*)
        from public.attendance a
        where a.tenant_id = v_tenant
          and a.checked_in_at >= v_from_instant
          and a.checked_in_at < v_through_instant
          and (new.branch_id is null or a.branch_id = new.branch_id)
      )
      else (
        select count(*)
        from public.members m
        where m.tenant_id = v_tenant
          and m.erased_at is null
          and m.joined_on >= new.range_from
          and m.joined_on <= new.range_through
          and (new.branch_id is null or m.branch_id = new.branch_id)
      )
    end;

  -- Over-cap refuses the INSERT itself: a direct table INSERT can create only
  -- a lawful bounded same-actor prepared attempt, never an arbitrary count.
  if v_count > new.row_cap then
    raise invalid_parameter_value
      using message = 'the report export exceeds the row cap';
  end if;

  new.export_id := gen_random_uuid();
  new.tenant_id := v_tenant;
  new.actor_user_id := v_actor;
  new.actor_role := app.current_app_role()::public.app_role;
  new.format := 'csv';
  -- Generation/preparation start, authoritative source snapshot and source
  -- cutoff share the containing statement's start: one snapshot, never a
  -- route clock.
  new.generated_at_utc := statement_timestamp();
  new.snapshot_at_utc := statement_timestamp();
  new.source_cutoff_at_utc := statement_timestamp();
  new.range_basis :=
    case new.dataset
      when 'payments' then 'created_at'
      when 'attendance' then 'checked_in_at'
      else 'joined_on'
    end;
  new.timezone := v_zone;
  new.range_start_utc := v_from_instant;
  new.range_end_exclusive_utc := v_through_instant;
  new.branch_scope := coalesce(new.branch_id::text, 'all');
  new.data_row_count := v_count;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- app.audit_report_export_preparation — VOLATILE definer AFTER INSERT trigger.
-- It receives only the validated NEW metadata, appends the prepared audit, and
-- reads no report source. Its postgres-owned elevation is confined to the
-- validated audit append; it exposes no source-reading or general-writing
-- authority. No rows, names, phone, address, GSTIN, raw JSON or file content
-- enter the audit payload.
-- ---------------------------------------------------------------------------

create or replace function app.audit_report_export_preparation()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  insert into public.audit_log
    (tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after)
  values (
    new.tenant_id,
    new.actor_user_id,
    new.actor_role,
    'report_export.prepared',
    'report_export',
    new.export_id,
    null,
    jsonb_build_object(
      'export_id', new.export_id::text,
      'dataset', new.dataset,
      'format', new.format,
      'generated_at_utc', app.rpe_utc_stamp(new.generated_at_utc),
      'snapshot_at_utc', app.rpe_utc_stamp(new.snapshot_at_utc),
      'source_cutoff_at_utc', app.rpe_utc_stamp(new.source_cutoff_at_utc),
      'range_from', new.range_from::text,
      'range_through', new.range_through::text,
      'range_basis', new.range_basis,
      'timezone', new.timezone,
      'range_start_utc', app.rpe_utc_stamp(new.range_start_utc),
      'range_end_exclusive_utc', app.rpe_utc_stamp(new.range_end_exclusive_utc),
      'branch_id', new.branch_id::text,
      'branch_scope', new.branch_scope,
      'data_row_count', new.data_row_count::text
    )
  );
  return new;
end;
$$;

create trigger report_export_preparations_derive
  before insert on app.report_export_preparations
  for each row execute function app.derive_report_export_preparation();

create trigger report_export_preparations_audit
  after insert on app.report_export_preparations
  for each row execute function app.audit_report_export_preparation();

-- Trigger invocation needs no session EXECUTE grant; nothing else may call
-- the trigger functions directly.
revoke execute on function app.derive_report_export_preparation()
  from public, anon, authenticated, service_role;
revoke execute on function app.audit_report_export_preparation()
  from public, anon, authenticated, service_role;

-- At most one release per prepared attempt — and at most one prepared event
-- per export id — including concurrent calls; the conflicting INSERT refuses
-- atomically, never read-then-insert alone.
create unique index audit_log_report_export_event_unique
  on public.audit_log (record_type, record_id, action)
  where record_type = 'report_export'
    and action in ('report_export.prepared', 'report_export.released');

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
volatile
security invoker
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid := app.current_tenant_id();
  v_zone text;
  v_from_instant timestamptz;
  v_through_instant timestamptz;
  v_payload jsonb;
  v_prep_count bigint;
  v_proj_count bigint;
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
  -- dates, ordered range, the inclusive 366-day maximum, a row cap in
  -- 1…5000. Validation errors are 22023; nothing has been read yet.
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
  if p_through - p_from + 1 > 366 then
    raise invalid_parameter_value using message = 'the range must not exceed 366 calendar days';
  end if;
  if p_row_cap is null or p_row_cap < 1 or p_row_cap > 5000 then
    raise invalid_parameter_value using message = 'the row cap must be between 1 and 5000';
  end if;

  -- Unknown and foreign branches are one indistinguishable unavailable
  -- refusal, after actor validation and before any report source is read.
  if p_branch_id is not null and not exists (
    select 1
    from public.branches b
    where b.id = p_branch_id
      and b.tenant_id = v_tenant
  ) then
    raise invalid_parameter_value using message = 'the requested branch is not available';
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
  -- Offset transitions use each actual local midnight, not a fixed 24 hours.
  v_from_instant := p_from::timestamp at time zone v_zone;
  v_through_instant := (p_through + 1)::timestamp at time zone v_zone;

  if p_dataset = 'payments' then
    -- RPE-004/005: ONE containing statement — the complete ordered projection
    -- and count under the caller's RLS in one snapshot, the gated preparation
    -- INSERT from only the five inputs, and the scalar assembly from the
    -- returned derived metadata. Money crosses as canonical decimal text;
    -- attempts and terminal states both appear; a null paid time or receipt
    -- stays blank; an erased member's name and code are blank while the
    -- financial row survives; cross-currency rows keep their own currency and
    -- are never summed. The branch filter is the payment member's CURRENT
    -- branch; a missing RLS-visible branch association cannot satisfy it.
    -- Over-cap: no preparation, no audit, and the refusal envelope with the
    -- exact count. A zero-row projection still inserts one preparation.
    with proj as (
      select row_number() over (order by p.created_at, p.id) as rn,
             count(*) over () as total,
             p.id,
             p.member_id,
             case when m.erased_at is null then m.member_code end as member_code,
             case when m.erased_at is null then m.full_name end as member_name,
             p.amount_paise,
             p.currency,
             p.status,
             p.method,
             p.created_at,
             p.paid_at,
             p.receipt_number
      from public.payments p
      left join public.members m on m.id = p.member_id
      where p.created_at >= v_from_instant
        and p.created_at < v_through_instant
        and (p_branch_id is null or m.branch_id = p_branch_id)
    ),
    prep as (
      insert into app.report_export_preparations
        (dataset, range_from, range_through, branch_id, row_cap)
      select p_dataset, p_from, p_through, p_branch_id, p_row_cap
      where (select coalesce(max(total), 0) from proj) <= p_row_cap
      returning export_id::text as export_id_text,
                generated_at_utc,
                snapshot_at_utc,
                source_cutoff_at_utc,
                data_row_count
    ),
    head as (
      select statement_timestamp() as ts,
             coalesce((select max(total) from proj), 0)::bigint as total
    )
    select
      case when exists (select 1 from prep) then
        jsonb_build_object(
          'export_id', (select export_id_text from prep),
          'dataset', p_dataset,
          'format', 'csv',
          'generated_at_utc', app.rpe_utc_stamp((select generated_at_utc from prep)),
          'snapshot_at_utc', app.rpe_utc_stamp((select snapshot_at_utc from prep)),
          'source_cutoff_at_utc', app.rpe_utc_stamp((select source_cutoff_at_utc from prep)),
          'range_from', p_from::text,
          'range_through', p_through::text,
          'range_basis', 'created_at',
          'timezone', v_zone,
          'range_start_utc', app.rpe_utc_stamp(v_from_instant),
          'range_end_exclusive_utc', app.rpe_utc_stamp(v_through_instant),
          'branch_id', p_branch_id::text,
          'branch_scope', coalesce(p_branch_id::text, 'all'),
          'data_row_count', (select data_row_count::text from prep),
          'returned_row_count', (select data_row_count::text from prep),
          'row_cap', p_row_cap,
          'has_more', false,
          'rows', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'payment_id', q.id,
                'member_id', q.member_id,
                'member_code', q.member_code,
                'current_member_name', q.member_name,
                'amount_paise', q.amount_paise::text,
                'amount_display', app.rpe_money_display(q.amount_paise, q.currency),
                'currency', q.currency,
                'status', q.status::text,
                'method', q.method,
                'created_at_utc', app.rpe_utc_stamp(q.created_at),
                'paid_at_utc', app.rpe_utc_stamp(q.paid_at),
                'receipt_number', q.receipt_number
              ) order by q.rn
            ) from proj q
          ), '[]'::jsonb)
        )
      else
        jsonb_build_object(
          'export_id', gen_random_uuid()::text,
          'dataset', p_dataset,
          'format', 'csv',
          'generated_at_utc', app.rpe_utc_stamp((select ts from head)),
          'snapshot_at_utc', app.rpe_utc_stamp((select ts from head)),
          'source_cutoff_at_utc', app.rpe_utc_stamp((select ts from head)),
          'range_from', p_from::text,
          'range_through', p_through::text,
          'range_basis', 'created_at',
          'timezone', v_zone,
          'range_start_utc', app.rpe_utc_stamp(v_from_instant),
          'range_end_exclusive_utc', app.rpe_utc_stamp(v_through_instant),
          'branch_id', p_branch_id::text,
          'branch_scope', coalesce(p_branch_id::text, 'all'),
          'data_row_count', (select total::text from head),
          'returned_row_count', '0',
          'row_cap', p_row_cap,
          'has_more', true,
          'rows', '[]'::jsonb
        )
      end,
      (select data_row_count from prep),
      (select total from head)
      into v_payload, v_prep_count, v_proj_count
      from head;

  elsif p_dataset = 'attendance' then
    -- Recorded attendance events only: the stored branch, the branch's own
    -- zone (null inherits the gym zone, disclosed), ordering by
    -- (checked_in_at, id), the optional check-out and the offline/replay
    -- provenance stamps kept as recorded. Never bookings, never inferred
    -- presence, never a dwell-time computation. One containing statement,
    -- same gated preparation and refusal envelope as payments.
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

    with proj as (
      select row_number() over (order by a.checked_in_at, a.id) as rn,
             count(*) over () as total,
             a.id,
             a.member_id,
             case when m.erased_at is null then m.member_code end as member_code,
             case when m.erased_at is null then m.full_name end as member_name,
             a.branch_id,
             a.source,
             a.checked_in_at,
             a.checked_out_at,
             a.offline_recorded_at,
             a.replayed_at,
             coalesce(b.timezone, v_zone) as stamp_zone
      from public.attendance a
      left join public.members m on m.id = a.member_id
      left join public.branches b on b.id = a.branch_id
      where a.tenant_id = v_tenant
        and a.checked_in_at >= v_from_instant
        and a.checked_in_at < v_through_instant
        and (p_branch_id is null or a.branch_id = p_branch_id)
    ),
    prep as (
      insert into app.report_export_preparations
        (dataset, range_from, range_through, branch_id, row_cap)
      select p_dataset, p_from, p_through, p_branch_id, p_row_cap
      where (select coalesce(max(total), 0) from proj) <= p_row_cap
      returning export_id::text as export_id_text,
                generated_at_utc,
                snapshot_at_utc,
                source_cutoff_at_utc,
                data_row_count
    ),
    head as (
      select statement_timestamp() as ts,
             coalesce((select max(total) from proj), 0)::bigint as total
    )
    select
      case when exists (select 1 from prep) then
        jsonb_build_object(
          'export_id', (select export_id_text from prep),
          'dataset', p_dataset,
          'format', 'csv',
          'generated_at_utc', app.rpe_utc_stamp((select generated_at_utc from prep)),
          'snapshot_at_utc', app.rpe_utc_stamp((select snapshot_at_utc from prep)),
          'source_cutoff_at_utc', app.rpe_utc_stamp((select source_cutoff_at_utc from prep)),
          'range_from', p_from::text,
          'range_through', p_through::text,
          'range_basis', 'checked_in_at',
          'timezone', v_zone,
          'range_start_utc', app.rpe_utc_stamp(v_from_instant),
          'range_end_exclusive_utc', app.rpe_utc_stamp(v_through_instant),
          'branch_id', p_branch_id::text,
          'branch_scope', coalesce(p_branch_id::text, 'all'),
          'data_row_count', (select data_row_count::text from prep),
          'returned_row_count', (select data_row_count::text from prep),
          'row_cap', p_row_cap,
          'has_more', false,
          'rows', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'attendance_id', q.id,
                'member_id', q.member_id,
                'member_code', q.member_code,
                'current_member_name', q.member_name,
                'branch_id', q.branch_id,
                'source', q.source::text,
                'checked_in_at_utc', app.rpe_utc_stamp(q.checked_in_at),
                'checked_in_local', app.rpe_local_stamp(q.checked_in_at, q.stamp_zone)
                  || ' [' || q.stamp_zone || ']',
                'checked_out_at_utc', app.rpe_utc_stamp(q.checked_out_at),
                'offline_recorded_at_utc', app.rpe_utc_stamp(q.offline_recorded_at),
                'replayed_at_utc', app.rpe_utc_stamp(q.replayed_at)
              ) order by q.rn
            ) from proj q
          ), '[]'::jsonb)
        )
      else
        jsonb_build_object(
          'export_id', gen_random_uuid()::text,
          'dataset', p_dataset,
          'format', 'csv',
          'generated_at_utc', app.rpe_utc_stamp((select ts from head)),
          'snapshot_at_utc', app.rpe_utc_stamp((select ts from head)),
          'source_cutoff_at_utc', app.rpe_utc_stamp((select ts from head)),
          'range_from', p_from::text,
          'range_through', p_through::text,
          'range_basis', 'checked_in_at',
          'timezone', v_zone,
          'range_start_utc', app.rpe_utc_stamp(v_from_instant),
          'range_end_exclusive_utc', app.rpe_utc_stamp(v_through_instant),
          'branch_id', p_branch_id::text,
          'branch_scope', coalesce(p_branch_id::text, 'all'),
          'data_row_count', (select total::text from head),
          'returned_row_count', '0',
          'row_cap', p_row_cap,
          'has_more', true,
          'rows', '[]'::jsonb
        )
      end,
      (select data_row_count from prep),
      (select total from head)
      into v_payload, v_prep_count, v_proj_count
      from head;

  else
    -- members: the current non-erased joining cohort — joined_on is a direct
    -- calendar-date comparison (no instant arithmetic), the branch is the
    -- member's current one, and no DOB, guardian detail, note, consent
    -- record or account id ever enters the projection. One containing
    -- statement, same gated preparation and refusal envelope as payments.
    with proj as (
      select row_number() over (order by m.joined_on, m.id) as rn,
             count(*) over () as total,
             m.id,
             m.member_code,
             m.full_name,
             m.phone,
             m.email,
             m.branch_id,
             m.status,
             m.joined_on
      from public.members m
      where m.tenant_id = v_tenant
        and m.erased_at is null
        and m.joined_on >= p_from
        and m.joined_on <= p_through
        and (p_branch_id is null or m.branch_id = p_branch_id)
    ),
    prep as (
      insert into app.report_export_preparations
        (dataset, range_from, range_through, branch_id, row_cap)
      select p_dataset, p_from, p_through, p_branch_id, p_row_cap
      where (select coalesce(max(total), 0) from proj) <= p_row_cap
      returning export_id::text as export_id_text,
                generated_at_utc,
                snapshot_at_utc,
                source_cutoff_at_utc,
                data_row_count
    ),
    head as (
      select statement_timestamp() as ts,
             coalesce((select max(total) from proj), 0)::bigint as total
    )
    select
      case when exists (select 1 from prep) then
        jsonb_build_object(
          'export_id', (select export_id_text from prep),
          'dataset', p_dataset,
          'format', 'csv',
          'generated_at_utc', app.rpe_utc_stamp((select generated_at_utc from prep)),
          'snapshot_at_utc', app.rpe_utc_stamp((select snapshot_at_utc from prep)),
          'source_cutoff_at_utc', app.rpe_utc_stamp((select source_cutoff_at_utc from prep)),
          'range_from', p_from::text,
          'range_through', p_through::text,
          'range_basis', 'joined_on',
          'timezone', v_zone,
          'range_start_utc', app.rpe_utc_stamp(v_from_instant),
          'range_end_exclusive_utc', app.rpe_utc_stamp(v_through_instant),
          'branch_id', p_branch_id::text,
          'branch_scope', coalesce(p_branch_id::text, 'all'),
          'data_row_count', (select data_row_count::text from prep),
          'returned_row_count', (select data_row_count::text from prep),
          'row_cap', p_row_cap,
          'has_more', false,
          'rows', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'member_id', q.id,
                'member_code', q.member_code,
                'full_name', q.full_name,
                'phone', q.phone,
                'email', q.email,
                'branch_id', q.branch_id,
                'status', q.status::text,
                'joined_on', q.joined_on::text
              ) order by q.rn
            ) from proj q
          ), '[]'::jsonb)
        )
      else
        jsonb_build_object(
          'export_id', gen_random_uuid()::text,
          'dataset', p_dataset,
          'format', 'csv',
          'generated_at_utc', app.rpe_utc_stamp((select ts from head)),
          'snapshot_at_utc', app.rpe_utc_stamp((select ts from head)),
          'source_cutoff_at_utc', app.rpe_utc_stamp((select ts from head)),
          'range_from', p_from::text,
          'range_through', p_through::text,
          'range_basis', 'joined_on',
          'timezone', v_zone,
          'range_start_utc', app.rpe_utc_stamp(v_from_instant),
          'range_end_exclusive_utc', app.rpe_utc_stamp(v_through_instant),
          'branch_id', p_branch_id::text,
          'branch_scope', coalesce(p_branch_id::text, 'all'),
          'data_row_count', (select total::text from head),
          'returned_row_count', '0',
          'row_cap', p_row_cap,
          'has_more', true,
          'rows', '[]'::jsonb
        )
      end,
      (select data_row_count from prep),
      (select total from head)
      into v_payload, v_prep_count, v_proj_count
      from head;
  end if;

  -- Snapshot coherence: the derive trigger's count (the preparation's
  -- data_row_count) must equal the containing statement's source projection
  -- count before anything is returned; a mismatch rolls back the preparation
  -- and its audit. The basis and boundaries derive from the same validated
  -- inputs by construction.
  if v_prep_count is not null and v_prep_count is distinct from v_proj_count then
    raise exception
      using message = 'report export preparation does not match the source projection',
            errcode = '23514';
  end if;

  return v_payload;
end;
$$;

revoke execute on function public.export_report_snapshot(text, date, date, uuid, integer)
  from public, anon, service_role;
grant execute on function public.export_report_snapshot(text, date, date, uuid, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- append_report_export_event — the ONLY elevation: audit append. The public
-- invocation accepts ONLY 'report_export.released'; the prepared event is
-- appended by the derive/audit trigger pair, never through this RPC.
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
  v_actor uuid := auth.uid();
  v_tenant uuid := app.current_tenant_id();
  v_byte_count text;
  v_digest text;
  v_prepared app.report_export_preparations%ROWTYPE;
  v_after jsonb;
begin
  -- RPE-009: the event's actor is the CALLER's verified claims — a member
  -- identity, an anonymous request or an impersonating session appends
  -- nothing. This check runs before any argument validation, so a refused
  -- caller learns nothing about the event contract.
  if v_actor is null
    or app.current_impersonation_id() is not null
    or app.current_app_role() is distinct from 'gym_owner'
  then
    raise insufficient_privilege
      using message = 'report export audit events attribute the verified gym owner only';
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
      using message = 'report export audit events attribute the verified gym owner only';
  end if;

  -- Public invocation accepts ONLY the released event.
  if p_event is distinct from 'report_export.released' then
    raise invalid_parameter_value
      using message = 'the public audit event must be report_export.released';
  end if;
  if p_export_id is null then
    raise invalid_parameter_value using message = 'the export id is required';
  end if;
  if p_details is null then
    raise invalid_parameter_value using message = 'the audit details are required';
  end if;

  -- No arbitrary payloads: the release details are exactly
  -- {byte_count, artifact_sha256}. Exported row content can never enter the
  -- audit (RPE-009), and no caller-supplied metadata is trusted.
  if (select count(*) from jsonb_object_keys(p_details) k) <> 2
    or not p_details ? 'byte_count'
    or not p_details ? 'artifact_sha256'
  then
    raise exception
      using message = 'the release details must be exactly byte_count and artifact_sha256',
            errcode = '23514';
  end if;

  -- byte_count: a positive canonical decimal STRING (strict JSON string type)
  -- within the 8 MiB final byte bound. artifact_sha256: exactly 64 lowercase
  -- hex chars for the complete final attachment bytes including BOM. Both
  -- facts are string-typed by contract; a JSON number, boolean, array,
  -- object or null never satisfies them.
  if jsonb_typeof(p_details -> 'byte_count') is distinct from 'string'
    or jsonb_typeof(p_details -> 'artifact_sha256') is distinct from 'string'
  then
    raise invalid_parameter_value
      using message = 'the release byte count and artifact digest must be canonical strings';
  end if;
  v_byte_count := p_details ->> 'byte_count';
  v_digest := p_details ->> 'artifact_sha256';
  if v_byte_count is null
    or v_byte_count !~ '^[1-9][0-9]*$'
    or v_byte_count::numeric > 8388608
  then
    raise invalid_parameter_value
      using message = 'the release byte count must be a positive canonical decimal within the byte bound';
  end if;
  if v_digest is null or v_digest !~ '^[0-9a-f]{64}$' then
    raise invalid_parameter_value
      using message = 'the release artifact digest must be 64 lowercase hex characters';
  end if;

  -- The writer revalidates active owner/claims (above) and finds exactly this
  -- actor/tenant's prepared UUID; absent and foreign attempts are the same
  -- unavailable refusal, and an already-released attempt is refused before
  -- any second audit row can exist.
  select *
    into v_prepared
    from app.report_export_preparations r
    where r.export_id = p_export_id
      and r.tenant_id = v_tenant
      and r.actor_user_id = v_actor;
  if not found then
    raise insufficient_privilege
      using message = 'no prepared export attempt is available for this release';
  end if;
  if exists (
    select 1
    from public.audit_log a
    where a.record_type = 'report_export'
      and a.record_id = p_export_id
      and a.action = 'report_export.released'
  ) then
    raise exception
      using message = 'this export attempt has already been released',
            errcode = '23514';
  end if;

  -- Copy all prepared after keys and add the two validated release fields.
  -- The appended row attributes the caller's verified claims — nothing in
  -- p_details attributes the audit row.
  v_after := jsonb_build_object(
    'export_id', v_prepared.export_id::text,
    'dataset', v_prepared.dataset,
    'format', v_prepared.format,
    'generated_at_utc', app.rpe_utc_stamp(v_prepared.generated_at_utc),
    'snapshot_at_utc', app.rpe_utc_stamp(v_prepared.snapshot_at_utc),
    'source_cutoff_at_utc', app.rpe_utc_stamp(v_prepared.source_cutoff_at_utc),
    'range_from', v_prepared.range_from::text,
    'range_through', v_prepared.range_through::text,
    'range_basis', v_prepared.range_basis,
    'timezone', v_prepared.timezone,
    'range_start_utc', app.rpe_utc_stamp(v_prepared.range_start_utc),
    'range_end_exclusive_utc', app.rpe_utc_stamp(v_prepared.range_end_exclusive_utc),
    'branch_id', v_prepared.branch_id::text,
    'branch_scope', v_prepared.branch_scope,
    'data_row_count', v_prepared.data_row_count::text
  ) || jsonb_build_object('byte_count', v_byte_count, 'artifact_sha256', v_digest);

  insert into public.audit_log
    (tenant_id, actor_user_id, actor_role, action, record_type, record_id, before, after)
  values (
    v_tenant,
    v_actor,
    app.current_app_role()::public.app_role,
    'report_export.released',
    'report_export',
    p_export_id,
    null,
    v_after
  );
end;
$$;

revoke execute on function public.append_report_export_event(text, uuid, jsonb)
  from public, anon, service_role;
grant execute on function public.append_report_export_event(text, uuid, jsonb)
  to authenticated;
