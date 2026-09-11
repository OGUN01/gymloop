-- Phase 6 member import: the v1 CSV/XLSX import run, its typed evidence and
-- invariant, and the prepare/commit command pair. Frozen contract:
-- docs/planning/phase6-import-contract.md (CSV-D01..CSV-D16; DB refusals
-- GL063, GL064, GL068). Registry: docs/registry.md, "Phase 6 member import
-- database functions" and "Phase 6 member import database triggers".
--
-- The design in one paragraph. member_imports already holds the Phase 1
-- legacy shape (tenant, staff uploader, filename, mapping, status, counts,
-- report); this migration adds the eight nullable v1 columns -- nullable only
-- to accommodate the rows that predate it, never to admit a partial new run.
-- prepare_member_import owns identity (verified JWT user, real active linked
-- staff, verified owner/manager role, explicit impersonation refusal), the
-- gym-local effective-day freeze, phase-A revalidation with future-date
-- errors, the full ordered duplicate classification over same-gym members and
-- the file's own keys, the database-canonical candidate digest, and exact
-- replay (GL068). commit_member_import owns the run lock, the SQL-NULL state
-- probe, terminal replay before any row work, uploader and raw-digest binding
-- (GL064), the exact row-set plus canonical SHA-256 check it hashes itself
-- (GL063), the final same-gym duplicate recheck, whitelisted member inserts,
-- counters, and a failure subtransaction that records the run failed with
-- zero imports and a code-only report. A v1 run is created and moved only by
-- these two commands: an invoker-row invariant trigger refuses every direct
-- authenticated write -- including legacy downgrade and manufactured
-- completion -- while the trusted postgres administrative path (the definers
-- themselves, seed repair) keeps its authority (ADR-098/120: trusted paths
-- state their bypass out loud -- session_replication_role = replica or a
-- named ALTER TABLE ... DISABLE TRIGGER for fixtures and the seed).

-- ---------------------------------------------------------------------------
-- 0. Preconditions
-- ---------------------------------------------------------------------------

do $migration$
begin
  -- The platform migration owns the legacy table; the identity migration owns
  -- the preview-read-only family; the leads migration owns the timezone
  -- resolver. Either missing means this file is replaying out of order.
  if not exists (
    select 1 from pg_catalog.pg_attribute
     where attrelid = 'public.member_imports'::regclass
       and attname = 'error_report'
       and not attisdropped
  ) then
    raise exception 'Phase 6 import expects the platform member_imports table';
  end if;
  if exists (
    select 1 from pg_catalog.pg_attribute
     where attrelid = 'public.member_imports'::regclass
       and attname = 'branch_id'
       and not attisdropped
  ) then
    raise exception 'Phase 6 import expects an un-migrated member_imports table';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger
     where tgrelid = 'public.member_imports'::regclass
       and tgname = 'member_imports_preview_read_only'
  ) then
    raise exception 'Phase 6 import expects the preview-read-only guard trigger';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc
     where proname = 'resolve_org_time_zone'
       and pronamespace = 'app'::regnamespace
  ) then
    raise exception 'Phase 6 import expects app.resolve_org_time_zone (leads migration)';
  end if;
end
$migration$;

-- ---------------------------------------------------------------------------
-- 1. The eight v1 columns
-- ---------------------------------------------------------------------------

alter table public.member_imports
  add column branch_id uuid,
  add column request_key uuid,
  add column file_sha256 text,
  add column parser_contract text,
  add column phone_default_country text,
  add column effective_on date,
  add column uploaded_by_user_id uuid,
  add column candidate_payload_sha256 text;

-- ---------------------------------------------------------------------------
-- 2. The same-tenant branch reference, the replay key, and typed facts
-- ---------------------------------------------------------------------------

-- ADR-052: the branch reference is same-tenant composite, so an import can
-- only target one of its own gym's branches -- a cross-gym branch id is a
-- 23503, never a silently adopted branch.
alter table public.member_imports
  add constraint member_imports_tenant_id_branch_id_fkey
    foreign key (tenant_id, branch_id)
    references public.branches (tenant_id, id);

-- Rule 2: every FK column leads an index or sits right after the tenant
-- column; the composite reference is its own leading-tenant index.
create index member_imports_tenant_id_branch_id_idx
  on public.member_imports (tenant_id, branch_id);

-- Retry identity is tenant-scoped and partial (ADR-047): a gym only clashes
-- with its own request keys, and legacy rows hold no slot at all.
create unique index member_imports_tenant_id_request_key_key
  on public.member_imports (tenant_id, request_key)
  where request_key is not null;

-- The raw-file digest is exactly what inspect returned: 64 lowercase hex
-- characters. Uppercase, short or non-hex digests are malformed evidence.
alter table public.member_imports
  add constraint member_imports_file_sha256_format_chk
    check (file_sha256 ~ '^[0-9a-f]{64}$');

-- The stored phone-country mode is typed in every v1 run: IN prefixes bare
-- ten-digit Indian mobiles, E164 requires an explicit country code. Null
-- stays a legacy-only shape.
alter table public.member_imports
  add constraint member_imports_phone_default_country_chk
    check (phone_default_country in ('IN', 'E164'));

-- ---------------------------------------------------------------------------
-- 2a. The tenant policies gain the preview exclusion NAV-003 gives every
-- other sensitive gym-side surface (leads, 20260915100005): an impersonation
-- session is not a reader or a writer, however privileged its claims are.
-- member_imports predates that migration and was never retrofitted onto its
-- own read policy (only the generic preview_read_only row trigger reached
-- it), so a support preview could still inspect a gym's import runs -- the
-- same class of fact leads' identical repair closes. The platform policies
-- (member_imports_platform_select / _write) are untouched.
-- ---------------------------------------------------------------------------

drop policy member_imports_tenant_select on public.member_imports;
drop policy member_imports_tenant_write on public.member_imports;

create policy member_imports_tenant_select on public.member_imports
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.is_gym_admin())
         and (select app.current_impersonation_id()) is null);

create policy member_imports_tenant_write on public.member_imports
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.is_gym_admin())
         and (select app.current_impersonation_id()) is null)
  with check (tenant_id = (select app.current_tenant_id())
         and (select app.is_gym_admin())
         and (select app.current_impersonation_id()) is null);

-- A preview session's UPDATE or DELETE matches no rows through the tenant
-- policy above, so the row-level member_imports_preview_read_only trigger
-- never sees it and the statement would otherwise silently affect zero rows
-- -- the same gap leads' identical sibling trigger closes (ADR-118). This
-- statement-level guard answers with the platform's read-only error before
-- any row is resolved. 04_contract_meta.sql's catalogue check already
-- admits this exact sibling shape on any table.
create trigger member_imports_preview_write_guard
  before insert or update or delete on public.member_imports
  for each statement
  execute function app.enforce_preview_read_only();

-- ---------------------------------------------------------------------------
-- 3. The v1 run invariant
-- ---------------------------------------------------------------------------

-- app.enforce_member_import_v1 holds the invariants for every writer, gated
-- on the actor only where the fact is about the actor: an authenticated
-- session -- owner or super admin alike -- can neither create a run nor move
-- one, because the two commands are the only writers of run state and they
-- run as postgres. Every other invariant below is about the data and binds
-- the trusted postgres path too, which is what keeps a BYPASSRLS repair
-- subject to the same evidence rules (ADR-120). History rows carry no v1
-- facts and stay outside the v1 rules; they can never be completed, and they
-- can never be converted into a v1 run, because every added fact is frozen
-- the moment it exists.
create function app.enforce_member_import_v1()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_is_v1 boolean;
  v_invalid integer;
begin
  -- This trigger also carries the table's updated_at maintenance (04's
  -- catalogue meta check admits exactly one row trigger named
  -- <table>_touch_updated_at, universally, and one named
  -- <table>_preview_read_only; every table's substantive invariant rides
  -- inside one of those two slots rather than a third name -- the same
  -- fusion 20260915100005_phase6_leads.sql uses for
  -- app.enforce_lead_discipline()). Stamped once here rather than at each
  -- return so every accepted path, including every legacy-row branch below,
  -- carries it identically.
  new.updated_at := statement_timestamp();

  -- A row is v1 when it carries, or carried, any v1 evidence. The OLD row's
  -- facts are what made it v1: clearing a column cannot downgrade it.
  v_is_v1 := new.request_key is not null
             or new.parser_contract is not null
             or new.uploaded_by_user_id is not null
             or new.candidate_payload_sha256 is not null
             or (tg_op = 'UPDATE'
                 and (old.request_key is not null
                      or old.parser_contract is not null
                      or old.uploaded_by_user_id is not null
                      or old.candidate_payload_sha256 is not null));

  -- Every new row, legacy-shaped or not, is administrative-only: "Every new
  -- run must be a complete v1 run created by prepare" and nullability
  -- "accommodates only rows already present before this migration; there is
  -- no backfill" -- a legacy shape is a grandfathered fact about a row that
  -- already existed, never a capability for a fresh insert. Only the
  -- trusted postgres path may still record one, e.g. for historical repair;
  -- an ordinary authenticated actor, even with legacy-shaped columns, is
  -- refused before that distinction is even evaluated.
  if tg_op = 'INSERT' and current_user = 'authenticated' then
    raise exception 'An import run is recorded only by prepare_member_import'
      using errcode = '42501';
  end if;

  if not v_is_v1 then
    -- A historical legacy run, on both sides of the write. The trusted path
    -- may repair its legacy columns, but the enum's pending value is the
    -- only state a legacy row can honestly carry, and it can never be
    -- completed or converted -- the v1 facts are frozen the moment they
    -- exist. This check runs for every writer, so an authenticated UPDATE
    -- attempting to complete a legacy row is refused here even though the
    -- actor check above only gates INSERT.
    if new.status <> 'pending' then
      raise exception 'A legacy import run stays pending history'
        using errcode = '55006';
    end if;
    return new;
  end if;

  -- The actor-keyed half for UPDATE, scoped to v1 evidence: the existing
  -- table policies admit authenticated writes -- including a super admin's
  -- -- which is exactly why this row-level gate must refuse them once the
  -- row names a v1 run. The command path is the only writer of v1 run
  -- state; a legacy row's UPDATE is governed by the check just above
  -- instead, for every writer.
  if current_user = 'authenticated' then
    raise exception 'An import run moves only through commit_member_import'
      using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    -- CSV-D16: every typed v1 fact, non-null pending counters, the versioned
    -- report, and the forced initial state. The sanitized filename, the
    -- canonical mapping and the staff uploader are NOT NULL columns already.
    if new.branch_id is null
       or new.request_key is null
       or new.file_sha256 is null
       or new.parser_contract is null or new.parser_contract = ''
       or new.phone_default_country is null
       or new.effective_on is null
       or new.uploaded_by_user_id is null
       or new.candidate_payload_sha256 is null then
      raise exception 'A v1 import run carries its complete typed evidence'
        using errcode = '23514';
    end if;
    if new.status <> 'pending' then
      raise exception 'A v1 import run starts pending'
        using errcode = '23514';
    end if;
    if new.row_count is null or new.row_count < 0
       or new.imported_count is distinct from 0
       or new.duplicate_count is null or new.duplicate_count < 0 then
      raise exception 'A pending v1 run counts rows, not imports'
        using errcode = '23514';
    end if;
    if new.error_report is null
       or jsonb_typeof(new.error_report) <> 'object'
       or new.error_report ->> 'version' <> '1'
       or new.error_report -> 'summary' is null
       or coalesce(jsonb_array_length(new.error_report -> 'rows'), -1) < 0
       or coalesce(jsonb_array_length(new.error_report -> 'previewCandidateRows'), -1) < 0
       or coalesce(jsonb_array_length(new.error_report -> 'importedRows'), -1) <> 0
       or (new.error_report ->> 'failure') is not null then
      raise exception 'A pending v1 run stores its versioned code-only report'
        using errcode = '23514';
    end if;
    -- The pending equation and the pending partition: previewCandidateRows
    -- and the report rows partition every non-blank source row exactly once.
    -- The pending equation itself (wouldImport = rows - duplicates - invalid)
    -- is a derived fact of this partition, not a stored counter, so the
    -- completed equation's imported term is not asserted here.
    -- The distinct row population of report rows and preview candidates must
    -- equal row_count exactly: every non-blank source row covered, and no
    -- array holding more row numbers than rows (an item-per-reason report
    -- names a row several times; the distinct sets partition it once).
    if (new.error_report -> 'summary' ->> 'invalid')::integer < 0
       or (select count(*) from (
             select distinct rownum from (
               select (item ->> 'rowNumber')::integer as rownum
                 from jsonb_array_elements(new.error_report -> 'rows') item(value)
               union all
               select (c.value)::integer
                 from jsonb_array_elements(new.error_report -> 'previewCandidateRows') c(value)
             ) p) q
           ) <> new.row_count
       or (select count(*) from (
             select distinct (item ->> 'rowNumber')::integer as rownum
               from jsonb_array_elements(new.error_report -> 'rows') item(value)
           ) r) + jsonb_array_length(new.error_report -> 'previewCandidateRows')
          <> new.row_count then
      raise exception 'A pending run''s report partitions its file exactly once'
        using errcode = '23514';
    end if;
    return new;
  end if;

  -- UPDATE. Terminal evidence is immutable, for every writer: a completed or
  -- failed run never changes again.
  if old.status in ('completed', 'failed') then
    raise exception 'A terminal import run is immutable'
      using errcode = '55006';
  end if;

  -- Frozen evidence: tenant, both uploader identities, filename, branch,
  -- request key, raw digest, parser contract, country, mapping, effective
  -- day, row count, candidate digest and the report's previewCandidateRows.
  if new.tenant_id is distinct from old.tenant_id
     or new.uploaded_by_staff_id is distinct from old.uploaded_by_staff_id
     or new.uploaded_by_user_id is distinct from old.uploaded_by_user_id
     or new.file_name is distinct from old.file_name
     or new.branch_id is distinct from old.branch_id
     or new.request_key is distinct from old.request_key
     or new.file_sha256 is distinct from old.file_sha256
     or new.parser_contract is distinct from old.parser_contract
     or new.phone_default_country is distinct from old.phone_default_country
     or new.column_mapping is distinct from old.column_mapping
     or new.effective_on is distinct from old.effective_on
     or new.row_count is distinct from old.row_count
     or new.candidate_payload_sha256 is distinct from old.candidate_payload_sha256
     or (new.error_report -> 'previewCandidateRows')
          is distinct from (old.error_report -> 'previewCandidateRows') then
    raise exception 'A v1 run''s recorded evidence is frozen'
      using errcode = '23514';
  end if;

  -- The command path's only edges: pending -> processing, processing ->
  -- completed|failed. Anything else is a manufactured transition.
  if not (
       (old.status = 'pending' and new.status in ('pending', 'processing'))
       or (old.status = 'processing'
           and new.status in ('processing', 'completed', 'failed'))
     ) then
    raise exception 'An import run moves only pending, processing, completed, failed, in order'
      using errcode = '55006';
  end if;

  if new.imported_count is null or new.imported_count < 0
     or new.duplicate_count is null or new.duplicate_count < 0
     or new.error_report is null
     or jsonb_typeof(new.error_report) <> 'object'
     or new.error_report ->> 'version' <> '1'
     or new.error_report -> 'summary' is null
     or (new.error_report -> 'summary' ->> 'invalid')::integer < 0
     or (new.error_report -> 'summary' ->> 'duplicate')::integer < 0 then
    raise exception 'A v1 run cannot carry a null or negative counter or report'
      using errcode = '23514';
  end if;

  if new.status in ('pending', 'processing') then
    -- Nothing imported yet: importedRows stays empty and no failure exists.
    -- The pending equation (wouldImport = rows - duplicates - invalid) is a
    -- derived fact of the pending partition asserted at INSERT, not a stored
    -- counter, so the completed equation's imported term is not asserted here.
    if new.imported_count <> 0
       or coalesce(jsonb_array_length(new.error_report -> 'importedRows'), -1) <> 0
       or (new.error_report ->> 'failure') is not null then
      raise exception 'A pending or processing run has imported nothing yet'
        using errcode = '23514';
    end if;
    return new;
  end if;

  if new.status = 'completed' then
    -- The completed equation from the persisted report, no failure, and
    -- importedRows exactly the imported dispositions, a subset of the frozen
    -- preview candidates.
    if (new.error_report ->> 'failure') is not null
       or new.imported_count + new.duplicate_count
          + (new.error_report -> 'summary' ->> 'invalid')::integer
          <> new.row_count
       or new.imported_count
          <> coalesce(jsonb_array_length(new.error_report -> 'importedRows'), -1)
       or (new.error_report -> 'summary' ->> 'duplicate')::integer
          <> new.duplicate_count then
      raise exception 'A completed run''s counts must reconcile to its file'
        using errcode = '23514';
    end if;
    if exists (
      select 1
        from jsonb_array_elements(new.error_report -> 'importedRows') c(value)
       where not exists (
         select 1
           from jsonb_array_elements(new.error_report -> 'previewCandidateRows') p(value)
          where (p.value)::integer = (c.value)::integer
       )
    ) then
      raise exception 'A completed run imports only its preview candidates'
        using errcode = '23514';
    end if;
    return new;
  end if;

  -- failed: zero imports, the preview duplicate count retained, a non-null
  -- global failure, an empty importedRows -- and the completed equation is
  -- deliberately waived (the candidates were rolled back).
  if (new.error_report ->> 'failure') is null
     or new.imported_count <> 0
     or coalesce(jsonb_array_length(new.error_report -> 'importedRows'), -1) <> 0
     or new.duplicate_count <> old.duplicate_count then
    raise exception 'A failed run records zero imports and its failure code'
      using errcode = '23514';
  end if;
  return new;
end
$fn$;

-- Reuses the touch_updated_at slot rather than adding a third row trigger
-- name (see the comment at the top of app.enforce_member_import_v1()).
drop trigger member_imports_touch_updated_at on public.member_imports;

create trigger member_imports_touch_updated_at
  before insert or update on public.member_imports
  for each row
  execute function app.enforce_member_import_v1();

revoke all on function app.enforce_member_import_v1()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Private helpers
-- ---------------------------------------------------------------------------

-- app.member_import_actor -- the real-actor gate both commands share: a
-- verified JWT user whose tenant, staff and role claims name one real,
-- active, linked same-tenant gym_owner/gym_manager row, and no impersonation
-- session. Returns the acting staff id and JWT user id. Every refusal is the
-- same 42501, so an unknown, cross-gym or mismatched identity cannot be told
-- apart from a forbidden one.
create function app.member_import_actor(
  out o_staff_id uuid,
  out o_user_id uuid
)
returns record
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_user uuid;
begin
  v_user := auth.uid();

  if v_user is null
     or app.current_tenant_id() is null
     or app.current_staff_id() is null
     or app.current_impersonation_id() is not null
     or not app.is_gym_admin() then
    raise exception 'Member import requires a real gym owner or manager session'
      using errcode = '42501';
  end if;

  select s.id, s.user_id into o_staff_id, o_user_id
    from public.staff s
   where s.tenant_id = app.current_tenant_id()
     and s.id = app.current_staff_id()
     and s.user_id = v_user
     and s.role::text = app.current_app_role()
     and s.role in ('gym_owner', 'gym_manager')
     and s.is_active
   limit 1;

  if o_staff_id is null or o_user_id is null then
    raise exception 'Member import requires a real gym owner or manager session'
      using errcode = '42501';
  end if;
end
$fn$;

revoke all on function app.member_import_actor()
  from public, anon, authenticated;

-- app.member_import_report -- the contract's exact error_report shape, built
-- by the database so no caller ever supplies counts, partitions or failure
-- text: {version:1, summary:{invalid,duplicate}, previewCandidateRows,
-- importedRows, rows:[{rowNumber,disposition,field,reasonCode}], failure}.
create function app.member_import_report(
  p_rows jsonb,
  p_invalid integer,
  p_duplicate integer,
  p_candidate_rows jsonb,
  p_imported_rows jsonb,
  p_failure jsonb
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $fn$
  select jsonb_build_object(
    'version', 1,
    'summary', jsonb_build_object('invalid', p_invalid, 'duplicate', p_duplicate),
    'previewCandidateRows', p_candidate_rows,
    'importedRows', p_imported_rows,
    'rows', p_rows,
    'failure', p_failure
  );
$fn$;

revoke all on function app.member_import_report(jsonb, integer, integer, jsonb, jsonb, jsonb)
  from public, anon, authenticated;

-- app.member_import_canonical_digest -- SHA-256 of the canonical candidate
-- payload's UTF-8 text. The canonical form is database-owned: a JSONB array
-- ordered by numeric rowNumber, each object carrying exactly rowNumber plus
-- the eight whitelisted facts, nulls included, built with jsonb_build_object
-- and hashed with core pg_catalog sha256 -- encode(digest()) would drag in
-- pgcrypto's schema placement, while sha256() is core since PG11.
create function app.member_import_canonical_digest(p_candidates jsonb)
returns text
language sql
stable
security invoker
set search_path = ''
as $fn$
  select encode(
           sha256(convert_to(
             coalesce((
               select jsonb_agg(
                        jsonb_build_object(
                          'rowNumber',     (c.value ->> 'rowNumber')::integer,
                          'full_name',     c.value -> 'full_name',
                          'phone',         c.value -> 'phone',
                          'member_code',   c.value -> 'member_code',
                          'email',         c.value -> 'email',
                          'gender',        c.value -> 'gender',
                          'date_of_birth', c.value -> 'date_of_birth',
                          'joined_on',     c.value -> 'joined_on',
                          'notes',         c.value -> 'notes'
                        )
                        order by (c.value ->> 'rowNumber')::integer
                      )
                 from jsonb_array_elements(p_candidates) c(value)
             ), '[]'::jsonb)::text,
             'UTF8'
           )),
           'hex'
         );
$fn$;

revoke all on function app.member_import_canonical_digest(jsonb)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. public.prepare_member_import -- preview: identity, freeze, classify, win
-- ---------------------------------------------------------------------------

create function public.prepare_member_import(
  p_request_key uuid,
  p_file_name text,
  p_file_sha256 text,
  p_parser_contract text,
  p_branch_id uuid,
  p_phone_default_country text,
  p_column_mapping jsonb,
  p_row_count integer,
  p_rows jsonb,
  p_preclassified_report jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_staff uuid;
  v_user uuid;
  v_timezone text;
  v_effective_on date;
  v_row jsonb;
  v_row_number integer;
  v_report_rows jsonb;
  v_candidate_rows jsonb;
  v_canonical jsonb;
  v_digest text;
  v_invalid_count integer;
  v_duplicate_count integer;
  v_would_import integer;
  v_import_id uuid;
  v_existing public.member_imports%rowtype;
  v_candidate_phones jsonb;
  v_candidate_codes jsonb;
  v_is_dup boolean;
  v_phone_dup boolean;
  v_code_dup boolean;
begin
  -- Shape first: every typed argument present and well-formed. 22023 is the
  -- contract's invalid_request refusal and never a stored state.
  if p_request_key is null
     or p_file_name is null or p_file_name = ''
     or octet_length(p_file_name) > 1020
     or p_file_sha256 is null or p_file_sha256 !~ '^[0-9a-f]{64}$'
     or p_parser_contract is null or p_parser_contract = ''
     or p_branch_id is null
     or p_phone_default_country is null
     or p_phone_default_country not in ('IN', 'E164')
     or p_column_mapping is null or jsonb_typeof(p_column_mapping) <> 'object'
     or p_row_count is null or p_row_count < 1 or p_row_count > 5000
     or p_rows is null or jsonb_typeof(p_rows) <> 'array'
     or p_preclassified_report is null
     or jsonb_typeof(p_preclassified_report) <> 'array'
     or jsonb_array_length(p_rows) > 5000
     or jsonb_array_length(p_preclassified_report) > 5000 then
    raise exception 'The preview command is malformed'
      using errcode = '22023';
  end if;

  -- The mapping binds to the exact file (CSV-D05): distinct in-range indexes
  -- for full_name and phone, and only the eight whitelisted member fields --
  -- an unknown key, a non-integer index or two fields sharing one column is
  -- as malformed as a missing required field.
  if not (p_column_mapping ? 'full_name') or not (p_column_mapping ? 'phone')
     or exists (
       select 1 from jsonb_each(p_column_mapping) m(field, idx)
        where field not in (
          'full_name', 'phone', 'member_code', 'email', 'gender',
          'date_of_birth', 'joined_on', 'notes'
        )
        or jsonb_typeof(idx) <> 'number'
        or idx::text !~ '^[0-9]+$'
     )
     or (select count(*) from jsonb_each(p_column_mapping))
        <> (select count(distinct idx) from jsonb_each(p_column_mapping) m(field, idx)) then
    raise exception 'The column mapping is malformed'
      using errcode = '22023';
  end if;

  -- Real actor first: verified JWT user, real active linked staff, verified
  -- owner/manager role, no impersonation. Impersonation is refused explicitly
  -- by the gate, never silently filtered.
  v_tenant := app.current_tenant_id();
  if v_tenant is null then
    raise exception 'Member import requires a real gym owner or manager session'
      using errcode = '42501';
  end if;
  select o_staff_id, o_user_id into v_staff, v_user
    from app.member_import_actor();

  -- Same-tenant branch (P0002 on an unknown or cross-gym id), and the gym's
  -- own validated timezone for the frozen day.
  if not exists (
    select 1 from public.branches b
     where b.tenant_id = v_tenant
       and b.id = p_branch_id
  ) then
    raise exception 'Branch not found' using errcode = 'P0002';
  end if;
  v_timezone := app.resolve_org_time_zone(v_tenant);

  -- Serialize the key before deciding: two racing previews with one key
  -- become one run, and the partial unique index answers any path the lock
  -- misses.
  perform pg_advisory_xact_lock(hashtextextended(
    'member-import-prepare:' || v_tenant::text || ':' || p_request_key::text, 0
  ));

  -- Replay resolution before any classification: an equivalent retry returns
  -- the winning stored run -- its stored day, report and counters, without
  -- another row or reclassification, across a gym-local midnight too. A
  -- different immutable fact is GL068 and never echoes a stored fact.
  select * into v_existing
    from public.member_imports mi
   where mi.tenant_id = v_tenant
     and mi.request_key = p_request_key;
  if found then
    if v_existing.uploaded_by_staff_id = v_staff
       and v_existing.uploaded_by_user_id = v_user
       and v_existing.file_name = p_file_name
       and v_existing.file_sha256 = p_file_sha256
       and v_existing.parser_contract = p_parser_contract
       and v_existing.branch_id = p_branch_id
       and v_existing.phone_default_country = p_phone_default_country
       and v_existing.column_mapping = p_column_mapping then
      return jsonb_build_object(
        'importId', v_existing.id,
        'status', v_existing.status::text,
        'replayed', true,
        'effectiveOn', v_existing.effective_on::text,
        'counts', jsonb_build_object(
          'rows', v_existing.row_count,
          'wouldImport', v_existing.row_count
            - v_existing.duplicate_count
            - (v_existing.error_report -> 'summary' ->> 'invalid')::integer,
          'duplicates', v_existing.duplicate_count,
          'invalid', v_existing.error_report -> 'summary' -> 'invalid'
        ),
        'report', v_existing.error_report
      );
    end if;
    raise exception 'This request key is bound to a different preview'
      using errcode = 'GL068', detail = 'idempotency_conflict';
  end if;

  -- The winning day: the gym-local calendar day of the accepting transaction.
  -- Replay retains the stored day, so a replay never substitutes today's.
  v_effective_on := (transaction_timestamp() at time zone v_timezone)::date;

  -- Phase-A revalidation (CSV-D06/D06a). The handler has sent every non-blank
  -- source row in source order, each with rowNumber and all eight whitelisted
  -- facts, plus every local field error. The database re-proves each row's
  -- exact shape, defaults blank joined dates without their own error, and
  -- adds future_date to every parseable date after the winning day -- even on
  -- a row that already has field errors. Errors combine before any duplicate
  -- work.
  v_report_rows := '[]'::jsonb;
  for v_row in select * from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(v_row) <> 'object'
       or (select count(*) from jsonb_object_keys(v_row)) <> 9
       or not v_row ? 'rowNumber' or not v_row ? 'full_name'
       or not v_row ? 'phone' or not v_row ? 'member_code'
       or not v_row ? 'email' or not v_row ? 'gender'
       or not v_row ? 'date_of_birth' or not v_row ? 'joined_on'
       or not v_row ? 'notes'
       or jsonb_typeof(v_row -> 'rowNumber') <> 'number'
       or (v_row ->> 'rowNumber')::integer < 2
       or (v_row ->> 'rowNumber')::integer > p_row_count + 1
       -- full_name/phone are the two required fields, but "required" is a
       -- phase-A finding, not a shape rule: a blank source cell normalizes
       -- to null with its own reason-code entry in p_preclassified_report,
       -- so both fields accept null here exactly like the six optional ones.
       or (jsonb_typeof(v_row -> 'full_name') not in ('string','null'))
       or (jsonb_typeof(v_row -> 'phone') not in ('string','null'))
       or (jsonb_typeof(v_row -> 'member_code') not in ('string','null'))
       or (jsonb_typeof(v_row -> 'email') not in ('string','null'))
       or (jsonb_typeof(v_row -> 'gender') not in ('string','null'))
       or (jsonb_typeof(v_row -> 'date_of_birth') not in ('string','null'))
       or (jsonb_typeof(v_row -> 'joined_on') not in ('string','null'))
       or (jsonb_typeof(v_row -> 'notes') not in ('string','null')) then
      raise exception 'A preview row is not the canonical row shape'
        using errcode = '22023';
    end if;
    -- A phase-A error names a field the handler already nulled (CSV-D06):
    -- an error paired with a still-populated value is inconsistent input,
    -- not a row the database can trust to revalidate honestly.
    if exists (
      select 1
        from jsonb_array_elements(p_preclassified_report) e(value)
       where (e.value ->> 'rowNumber')::integer = (v_row ->> 'rowNumber')::integer
         and (v_row -> (e.value ->> 'field')) is distinct from 'null'::jsonb
    ) then
      raise exception 'A phase-A error must pair with a null value'
        using errcode = '22023';
    end if;
    -- The inverse: full_name and phone are the two required facts, so a
    -- null value with no matching report entry is a row the handler
    -- silently dropped a finding for, not a genuinely blank optional field.
    -- Each required field is checked independently: both may be null at
    -- once, and each then needs its own report entry.
    if (v_row -> 'full_name') = 'null'::jsonb
       and not exists (
         select 1
           from jsonb_array_elements(p_preclassified_report) e(value)
          where (e.value ->> 'rowNumber')::integer = (v_row ->> 'rowNumber')::integer
            and e.value ->> 'field' = 'full_name'
       ) then
      raise exception 'A null required field must carry its phase-A error'
        using errcode = '22023';
    end if;
    if (v_row -> 'phone') = 'null'::jsonb
       and not exists (
         select 1
           from jsonb_array_elements(p_preclassified_report) e(value)
          where (e.value ->> 'rowNumber')::integer = (v_row ->> 'rowNumber')::integer
            and e.value ->> 'field' = 'phone'
       ) then
      raise exception 'A null required field must carry its phase-A error'
        using errcode = '22023';
    end if;
    if exists (
      select 1
        from jsonb_array_elements(p_rows) other(value)
       where other.value <> v_row
         and (other.value ->> 'rowNumber') = (v_row ->> 'rowNumber')
    ) then
      raise exception 'Each source row appears once in the preview'
        using errcode = '22023';
    end if;

    -- A future_date item for every parseable date after the frozen day,
    -- unless that field already carries its own invalid_date error.
    if (v_row ->> 'date_of_birth') is not null
       and (v_row ->> 'date_of_birth') > v_effective_on::text
       and not exists (
         select 1
           from jsonb_array_elements(p_preclassified_report) e(value)
          where (e.value ->> 'rowNumber')::integer = (v_row ->> 'rowNumber')::integer
            and e.value ->> 'field' = 'date_of_birth'
            and e.value ->> 'reasonCode' = 'invalid_date'
       ) then
      v_report_rows := v_report_rows || jsonb_build_object(
        'rowNumber', (v_row ->> 'rowNumber')::integer,
        'field', 'date_of_birth',
        'reasonCode', 'future_date'
      );
    end if;
    if (v_row ->> 'joined_on') is not null
       and (v_row ->> 'joined_on') > v_effective_on::text
       and not exists (
         select 1
           from jsonb_array_elements(p_preclassified_report) e(value)
          where (e.value ->> 'rowNumber')::integer = (v_row ->> 'rowNumber')::integer
            and e.value ->> 'field' = 'joined_on'
            and e.value ->> 'reasonCode' = 'invalid_date'
       ) then
      v_report_rows := v_report_rows || jsonb_build_object(
        'rowNumber', (v_row ->> 'rowNumber')::integer,
        'field', 'joined_on',
        'reasonCode', 'future_date'
      );
    end if;
  end loop;

  -- Every preclassified item joins the report with its disposition. The
  -- handler's local errors are all invalid-class; the database's future_date
  -- items already appended carry the same class.
  v_report_rows := v_report_rows || p_preclassified_report;
  v_report_rows := (
    select coalesce(jsonb_agg(
             item || jsonb_build_object(
               'disposition',
               case when (item ->> 'reasonCode') in
                      ('required','invalid_cell_type','ambiguous_phone',
                       'invalid_phone','invalid_date','future_date')
                    then 'invalid' else 'duplicate' end)
             order by
               (item ->> 'rowNumber')::integer,
               array_position(ARRAY['full_name','phone','member_code','email',
                 'gender','date_of_birth','joined_on','notes']::text[],
                 item ->> 'field'),
               item ->> 'reasonCode'
           ), '[]'::jsonb)
      from jsonb_array_elements(v_report_rows) item(value)
  );

  -- The preclassified items must name rows the file sent, with allowlisted
  -- fields and phase-A reason codes.
  if exists (
    select 1
      from jsonb_array_elements(p_preclassified_report) e(value)
     where jsonb_typeof(e.value) <> 'object'
        or (select count(*) from jsonb_object_keys(e.value)) <> 3
        or not e.value ? 'rowNumber' or not e.value ? 'field'
        or not e.value ? 'reasonCode'
        or jsonb_typeof(e.value -> 'rowNumber') <> 'number'
        or (e.value ->> 'rowNumber')::integer < 2
        or (e.value ->> 'rowNumber')::integer > p_row_count + 1
        or (e.value ->> 'field') not in
             ('full_name','phone','member_code','email','gender',
              'date_of_birth','joined_on','notes')
        or (e.value ->> 'reasonCode') not in
             ('required','invalid_cell_type','ambiguous_phone',
              'invalid_phone','invalid_date')
        or not exists (
          select 1 from jsonb_array_elements(p_rows) r(value)
           where (r.value ->> 'rowNumber')::integer
                   = (e.value ->> 'rowNumber')::integer
        )
  ) then
    raise exception 'The preview''s local errors are malformed'
      using errcode = '22023';
  end if;

  -- The invalid rows: any row with an invalid-class item never reserves a key
  -- and is counted once.
  v_invalid_count := (
    select count(distinct (item ->> 'rowNumber')::integer)
      from jsonb_array_elements(v_report_rows) item(value)
     where item ->> 'disposition' = 'invalid'
  );

  -- Duplicate classification over the otherwise-valid rows only (CSV-D07):
  -- fixed classes in fixed order, each duplicate row counted once, no
  -- cross-tenant observation. Within the file, the first row carrying a new
  -- phone and a non-null member code is the file candidate; a later row
  -- matching a candidate phone gets file_phone, a later row matching a
  -- candidate member code gets file_member_code, and a skipped row reserves
  -- neither key.
  v_candidate_phones := '[]'::jsonb;
  v_candidate_codes := '[]'::jsonb;
  v_duplicate_count := 0;
  for v_row in
    select r.value
      from jsonb_array_elements(p_rows) r(value)
     order by (r.value ->> 'rowNumber')::integer
  loop
    v_row_number := (v_row ->> 'rowNumber')::integer;
    v_is_dup := false;

    continue when exists (
      select 1
        from jsonb_array_elements(v_report_rows) item(value)
       where (item ->> 'rowNumber')::integer = v_row_number
         and item ->> 'disposition' = 'invalid'
    );

    -- Step 2: same-gym members. Exact normalized phone equality; exact,
    -- case-sensitive member-code equality. A row matching either is skipped
    -- and reserves no file key.
    -- Phone and member_code are checked independently -- a row can carry
    -- both a same-gym phone and a file-level member_code collision at once
    -- (each reported once, at its own field), so neither field's check
    -- gates the other's; only each field's own same-gym-then-file order is
    -- fixed.
    v_phone_dup := false;
    if (v_row ->> 'phone') is not null
       and exists (
         select 1 from public.members m
          where m.tenant_id = v_tenant
            and m.phone = (v_row ->> 'phone')
       ) then
      v_report_rows := v_report_rows || jsonb_build_object(
        'rowNumber', v_row_number,
        'disposition', 'duplicate',
        'field', 'phone',
        'reasonCode', 'existing_phone'
      );
      v_phone_dup := true;
    elsif (v_row ->> 'phone') is not null
       and (v_candidate_phones ? (v_row ->> 'phone')) then
      v_report_rows := v_report_rows || jsonb_build_object(
        'rowNumber', v_row_number,
        'disposition', 'duplicate',
        'field', 'phone',
        'reasonCode', 'file_phone'
      );
      v_phone_dup := true;
    end if;

    v_code_dup := false;
    if (v_row ->> 'member_code') is not null
       and exists (
         select 1 from public.members m
          where m.tenant_id = v_tenant
            and m.member_code = (v_row ->> 'member_code')
       ) then
      v_report_rows := v_report_rows || jsonb_build_object(
        'rowNumber', v_row_number,
        'disposition', 'duplicate',
        'field', 'member_code',
        'reasonCode', 'existing_member_code'
      );
      v_code_dup := true;
    elsif (v_row ->> 'member_code') is not null
       and (v_candidate_codes ? (v_row ->> 'member_code')) then
      v_report_rows := v_report_rows || jsonb_build_object(
        'rowNumber', v_row_number,
        'disposition', 'duplicate',
        'field', 'member_code',
        'reasonCode', 'file_member_code'
      );
      v_code_dup := true;
    end if;

    v_is_dup := v_phone_dup or v_code_dup;

    if v_is_dup then
      v_duplicate_count := v_duplicate_count + 1;
    else
      -- A candidate reserves its phone and, when non-null, its member code.
      if (v_row ->> 'phone') is not null then
        v_candidate_phones := v_candidate_phones || to_jsonb(v_row ->> 'phone');
      end if;
      if (v_row ->> 'member_code') is not null then
        v_candidate_codes := v_candidate_codes || to_jsonb(v_row ->> 'member_code');
      end if;
    end if;
  end loop;

  -- Re-sort the report after the duplicate appends: one item per reason,
  -- ordered by row, field order, then reason-code order -- which is exactly
  -- the fixed duplicate order across fields.
  v_report_rows := (
    select coalesce(jsonb_agg(item order by
                 (item ->> 'rowNumber')::integer,
                 array_position(ARRAY['full_name','phone','member_code','email',
                   'gender','date_of_birth','joined_on','notes']::text[],
                   item ->> 'field'),
                 item ->> 'reasonCode'),
               '[]'::jsonb)
      from jsonb_array_elements(v_report_rows) item(value)
  );

  -- The canonical candidate payload, only after the frozen date, the
  -- invalid-row rule and the duplicate rule have produced it: every remaining
  -- row, with the frozen joined_on default, no unknown or omitted keys.
  v_canonical := coalesce((
    select jsonb_agg(
             jsonb_build_object(
               'rowNumber',     (r.value ->> 'rowNumber')::integer,
               'full_name',     r.value -> 'full_name',
               'phone',         r.value -> 'phone',
               'member_code',   r.value -> 'member_code',
               'email',         r.value -> 'email',
               'gender',        r.value -> 'gender',
               'date_of_birth', r.value -> 'date_of_birth',
               'joined_on',     case when jsonb_typeof(r.value -> 'joined_on') = 'string'
                                     then r.value -> 'joined_on'
                                     else to_jsonb(v_effective_on::text) end,
               'notes',         r.value -> 'notes'
             )
             order by (r.value ->> 'rowNumber')::integer
           )
      from jsonb_array_elements(p_rows) r(value)
     where not exists (
             select 1
               from jsonb_array_elements(v_report_rows) item(value)
              where (item ->> 'rowNumber')::integer
                      = (r.value ->> 'rowNumber')::integer
           )
  ), '[]'::jsonb);

  v_candidate_rows := (
    select coalesce(jsonb_agg(rownum order by rownum), '[]'::jsonb)
      from (
        select distinct (c.value ->> 'rowNumber')::integer as rownum
          from jsonb_array_elements(v_canonical) c(value)
      ) d
  );

  -- The complete population validates (CSV-D06's full row/report population):
  -- the report rows and the preview candidates partition every non-blank
  -- source row exactly once.
  v_would_import := jsonb_array_length(v_canonical);
  -- Every non-blank source row is either a report row or a preview candidate,
  -- exactly once, and every sent row is accounted for.
  if (select count(*) from (
         select distinct rownum from (
           select (item ->> 'rowNumber')::integer as rownum
             from jsonb_array_elements(v_report_rows) item(value)
           union all
           select (c.value ->> 'rowNumber')::integer
             from jsonb_array_elements(v_canonical) c(value)
         ) u) p
       ) <> p_row_count
     or (select count(*) from (
           select distinct (r.value ->> 'rowNumber')::integer as rownum
             from jsonb_array_elements(p_rows) r(value)
         ) s) <> p_row_count then
    raise exception 'The preview''s report partitions its file exactly once'
      using errcode = '22023';
  end if;
  if v_invalid_count + v_duplicate_count + v_would_import <> p_row_count then
    raise exception 'The preview''s counters must reconcile to its file'
      using errcode = '22023';
  end if;

  v_digest := app.member_import_canonical_digest(v_canonical);

  -- One pending v1 run with complete immutable evidence. The invariant
  -- trigger's trusted path accepts the write and re-proves every fact.
  insert into public.member_imports (
    tenant_id, uploaded_by_staff_id, file_name, column_mapping, status,
    row_count, imported_count, duplicate_count, error_report,
    branch_id, request_key, file_sha256, parser_contract,
    phone_default_country, effective_on, uploaded_by_user_id,
    candidate_payload_sha256
  ) values (
    v_tenant, v_staff, p_file_name, p_column_mapping, 'pending',
    p_row_count, 0, v_duplicate_count,
    app.member_import_report(
      v_report_rows, v_invalid_count, v_duplicate_count,
      v_candidate_rows, '[]'::jsonb, null
    ),
    p_branch_id, p_request_key, p_file_sha256, p_parser_contract,
    p_phone_default_country, v_effective_on, v_user, v_digest
  )
  returning id into v_import_id;

  return jsonb_build_object(
    'importId', v_import_id,
    'status', 'pending',
    'replayed', false,
    'effectiveOn', v_effective_on::text,
    'counts', jsonb_build_object(
      'rows', p_row_count,
      'wouldImport', v_would_import,
      'duplicates', v_duplicate_count,
      'invalid', v_invalid_count
    ),
    'report', app.member_import_report(
      v_report_rows, v_invalid_count, v_duplicate_count,
      v_candidate_rows, '[]'::jsonb, null
    )
  );
end
$fn$;

revoke all on function public.prepare_member_import(
  uuid, text, text, text, uuid, text, jsonb, integer, jsonb, jsonb
) from public, anon, service_role;
grant execute on function public.prepare_member_import(
  uuid, text, text, text, uuid, text, jsonb, integer, jsonb, jsonb
) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. public.commit_member_import -- confirm: probe, bind, recheck, insert
-- ---------------------------------------------------------------------------

create function public.commit_member_import(
  p_import_id uuid,
  p_file_sha256 text,
  p_rows jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_staff uuid;
  v_user uuid;
  v_run public.member_imports%rowtype;
  v_report_rows jsonb;
  v_imported_rows jsonb;
  v_failure_rows jsonb;
  v_final_duplicates integer;
  v_row_number integer;
  v_row jsonb;
  v_is_dup boolean;
  v_item jsonb;
  v_canonical jsonb;
  v_digest text;
  v_invalid integer;
  v_imported integer;
  v_member_id uuid;
begin
  -- Shape first. SQL NULL is the state probe, distinct from JSON null or an
  -- empty array; a non-null payload must be a JSON array of at most 5,000.
  if p_import_id is null then
    raise exception 'The import id is required' using errcode = '22023';
  end if;
  if p_file_sha256 is null or p_file_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'The file digest is a lowercase hex SHA-256'
      using errcode = '22023';
  end if;
  if p_rows is not null
     and (jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 5000) then
    raise exception 'The confirmation rows are an array of at most 5,000 candidates'
      using errcode = '22023';
  end if;

  -- Real actor first, exactly as prepare requires: verified JWT user, real
  -- active linked staff, verified owner/manager role, no impersonation.
  v_tenant := app.current_tenant_id();
  if v_tenant is null then
    raise exception 'Member import requires a real gym owner or manager session'
      using errcode = '42501';
  end if;
  select o_staff_id, o_user_id into v_staff, v_user
    from app.member_import_actor();

  -- The run lock serializes every commit path on this run: racing equivalent
  -- confirmations serialize here and converge on the stored terminal result.
  perform pg_advisory_xact_lock(hashtextextended(
    'member-import-run:' || v_tenant::text || ':' || p_import_id::text, 0
  ));

  -- Tenant scoping is explicit (the definers bypass RLS, so caller RLS is not
  -- an enforcement layer here): an unknown or cross-gym run is one 42501 that
  -- discloses nothing.
  select * into v_run
    from public.member_imports mi
   where mi.tenant_id = v_tenant
     and mi.id = p_import_id;
  if not found then
    raise exception 'Import not found' using errcode = '42501';
  end if;

  -- Only the preview's uploader confirms it: both stored identities.
  if v_run.uploaded_by_staff_id is distinct from v_staff
     or v_run.uploaded_by_user_id is distinct from v_user then
    raise exception 'Only the preview''s uploader may confirm this import'
      using errcode = '42501';
  end if;

  -- The exact raw file: GL064 precedes terminal replay and every row.
  if v_run.file_sha256 is distinct from p_file_sha256 then
    raise exception 'That file is not the exact one this import was previewed with'
      using errcode = 'GL064', detail = 'preview_file_mismatch';
  end if;

  -- Terminal replay before row validation or any parser-version check or
  -- parsing (CSV-D12): a completed and a recorded failed result both replay
  -- as stored, making replay independent of an old parser deployment.
  if v_run.status in ('completed', 'failed') then
    return jsonb_build_object(
      'importId', v_run.id,
      'status', v_run.status::text,
      'replayed', true,
      'counts', jsonb_build_object(
        'rows', v_run.row_count,
        'imported', v_run.imported_count,
        'duplicates', v_run.duplicate_count,
        'invalid', (v_run.error_report -> 'summary' ->> 'invalid')::integer
      ),
      'failure', coalesce(v_run.error_report -> 'failure', 'null'::jsonb),
      'errorReportUrl', '/api/member-imports/' || v_run.id::text || '/errors'
    );
  end if;

  if v_run.status = 'processing' then
    raise exception 'That import is already being confirmed'
      using errcode = '55000', detail = 'import_not_pending';
  end if;

  -- A pending probe writes nothing and returns the stored immutable facts the
  -- route reconstructs from.
  if p_rows is null then
    return jsonb_build_object(
      'status', 'pending',
      'parserContract', v_run.parser_contract,
      'columnMapping', v_run.column_mapping,
      'branchId', v_run.branch_id,
      'phoneDefaultCountry', v_run.phone_default_country,
      'effectiveOn', v_run.effective_on::text,
      'candidateRows', v_run.error_report -> 'previewCandidateRows'
    );
  end if;

  -- A non-null payload must be exactly the persisted candidates. Unknown or
  -- omitted keys, duplicate row numbers, wrong shapes and over-5,000 sets are
  -- 22023 (checked above and here); a schema-valid changed, missing or extra
  -- row is GL063 below. These refusals precede member writes and leave the
  -- run pending.
  for v_row in select * from jsonb_array_elements(p_rows) loop
    if jsonb_typeof(v_row) <> 'object'
       or (select count(*) from jsonb_object_keys(v_row)) <> 9
       or not v_row ? 'rowNumber' or not v_row ? 'full_name'
       or not v_row ? 'phone' or not v_row ? 'member_code'
       or not v_row ? 'email' or not v_row ? 'gender'
       or not v_row ? 'date_of_birth' or not v_row ? 'joined_on'
       or not v_row ? 'notes'
       or jsonb_typeof(v_row -> 'rowNumber') <> 'number'
       or (v_row ->> 'rowNumber')::integer < 2
       or (v_row ->> 'full_name') is null
       or (v_row ->> 'phone') is null
       or (v_row ->> 'joined_on') is null
       or jsonb_typeof(v_row -> 'full_name') <> 'string'
       or jsonb_typeof(v_row -> 'phone') <> 'string'
       or jsonb_typeof(v_row -> 'joined_on') <> 'string'
       or (jsonb_typeof(v_row -> 'member_code') not in ('string','null'))
       or (jsonb_typeof(v_row -> 'email') not in ('string','null'))
       or (jsonb_typeof(v_row -> 'gender') not in ('string','null'))
       or (jsonb_typeof(v_row -> 'date_of_birth') not in ('string','null'))
       or (jsonb_typeof(v_row -> 'notes') not in ('string','null')) then
      raise exception 'A confirmation row is not the canonical candidate shape'
        using errcode = '22023';
    end if;
  end loop;

  -- Duplicate row numbers cannot both reserve keys.
  if exists (
    select 1
      from jsonb_array_elements(p_rows) r(value)
     group by (r.value ->> 'rowNumber')::integer
     having count(*) > 1
  ) then
    raise exception 'Each candidate row number appears once'
      using errcode = '22023';
  end if;

  -- The candidate row numbers must be exactly the stored preview set: the
  -- same changed-value check the digest enforces, but readable as row numbers
  -- before any hashing.
  if (
    select count(*) from jsonb_array_elements(p_rows) r(value)
     where not exists (
       select 1
         from jsonb_array_elements(v_run.error_report -> 'previewCandidateRows') c(value)
        where (c.value)::integer = (r.value ->> 'rowNumber')::integer
     )
  ) > 0
  or (
    select count(*)
      from jsonb_array_elements(v_run.error_report -> 'previewCandidateRows') c(value)
     where not exists (
       select 1 from jsonb_array_elements(p_rows) r(value)
        where (r.value ->> 'rowNumber')::integer = (c.value)::integer
     )
  ) > 0 then
    raise exception 'The confirmation rows are not exactly the preview''s candidates'
      using errcode = 'GL063', detail = 'preview_payload_mismatch';
  end if;

  -- Canonicalize in PostgreSQL and hash the UTF-8 bytes; a caller-supplied
  -- digest or merely matching row numbers proves nothing.
  v_canonical := (
    select coalesce(jsonb_agg(
             jsonb_build_object(
               'rowNumber',     (r.value ->> 'rowNumber')::integer,
               'full_name',     r.value -> 'full_name',
               'phone',         r.value -> 'phone',
               'member_code',   r.value -> 'member_code',
               'email',         r.value -> 'email',
               'gender',        r.value -> 'gender',
               'date_of_birth', r.value -> 'date_of_birth',
               'joined_on',     r.value -> 'joined_on',
               'notes',         r.value -> 'notes'
             )
             order by (r.value ->> 'rowNumber')::integer
           ), '[]'::jsonb)
      from jsonb_array_elements(p_rows) r(value)
  );
  v_digest := encode(sha256(convert_to(v_canonical::text, 'UTF8')), 'hex');
  if v_digest is distinct from v_run.candidate_payload_sha256 then
    raise exception 'The file no longer produces the rows this import promised'
      using errcode = 'GL063', detail = 'preview_payload_mismatch';
  end if;

  -- The command path advances pending -> processing inside this transaction.
  update public.member_imports
     set status = 'processing'
   where tenant_id = v_tenant
     and id = p_import_id;

  -- The validated, digest-bound candidate loop, atomically paired with the
  -- run outcome. An unexpected processing failure rolls back the contained
  -- block holding every member insert, records the same run failed with
  -- imported_count=0 and a fixed processing_failed report, and never exposes
  -- the caught exception (CSV-D11). Authorization and malformed-input
  -- failures above are re-thrown, never converted.
  v_report_rows := v_run.error_report -> 'rows';
  v_invalid := (v_run.error_report -> 'summary' ->> 'invalid')::integer;
  v_imported := 0;
  v_final_duplicates := 0;
  begin
    for v_row in
      select r.value
        from jsonb_array_elements(p_rows) r(value)
       order by (r.value ->> 'rowNumber')::integer
    loop
      v_row_number := (v_row ->> 'rowNumber')::integer;

      -- Final same-gym recheck (CSV-D10): a candidate that became a same-gym
      -- duplicate since preview is reclassified as one and skipped;
      -- confirmation imports a subset, never a superset.
      if exists (
        select 1 from public.members m
         where m.tenant_id = v_tenant
           and (m.phone = (v_row ->> 'phone')
                or ((v_row ->> 'member_code') is not null
                    and m.member_code = (v_row ->> 'member_code')))
      ) then
        v_report_rows := v_report_rows || jsonb_build_object(
          'rowNumber', v_row_number,
          'disposition', 'duplicate',
          'field', 'phone',
          'reasonCode', 'existing_phone'
        );
        v_final_duplicates := v_final_duplicates + 1;
        continue;
      end if;

      begin
        insert into public.members (
          tenant_id, branch_id, full_name, phone, member_code, email,
          gender, date_of_birth, joined_on, notes
        ) values (
          v_tenant, v_run.branch_id, v_row ->> 'full_name', v_row ->> 'phone',
          v_row ->> 'member_code', v_row ->> 'email', v_row ->> 'gender',
          (v_row ->> 'date_of_birth')::date,
          (v_row ->> 'joined_on')::date,
          v_row ->> 'notes'
        )
        returning id into v_member_id;

        v_report_rows := v_report_rows || jsonb_build_object(
          'rowNumber', v_row_number,
          'disposition', 'imported',
          'field', 'full_name',
          'reasonCode', 'required'
        );
        v_imported := v_imported + 1;
      exception
        when unique_violation then
          -- A concurrent same-gym insert between the recheck and the insert
          -- is that row's final duplicate, not an abort.
          v_report_rows := v_report_rows || jsonb_build_object(
            'rowNumber', v_row_number,
            'disposition', 'duplicate',
            'field', 'phone',
            'reasonCode', 'existing_phone'
          );
          v_final_duplicates := v_final_duplicates + 1;
      end;
    end loop;

    -- The imported rows, ascending and duplicate-free, derived from the
    -- working report (still carrying one placeholder entry per successful
    -- insert) rather than client estimates.
    v_imported_rows := coalesce((
      select jsonb_agg(rownum order by rownum)
        from (
          select distinct (item ->> 'rowNumber')::integer as rownum
            from jsonb_array_elements(v_report_rows) item(value)
           where item ->> 'disposition' = 'imported'
        ) d
    ), '[]'::jsonb);
    v_imported := coalesce(jsonb_array_length(v_imported_rows), 0);

    -- The persisted `rows` field carries only a non-imported row's disposition
    -- and reason (CSV-D13: "each non-blank row exactly one disposition" --
    -- an imported row's disposition lives in `importedRows`, not here, so an
    -- imported row's placeholder entry above is dropped before this becomes
    -- the stored report). One item per reason, ordered by row, field order,
    -- then reason-code order.
    v_report_rows := (
      select coalesce(jsonb_agg(item order by
                   (item ->> 'rowNumber')::integer,
                   array_position(ARRAY['full_name','phone','member_code','email',
                     'gender','date_of_birth','joined_on','notes']::text[],
                     item ->> 'field'),
                   item ->> 'reasonCode'),
                 '[]'::jsonb)
        from jsonb_array_elements(v_report_rows) item(value)
       where item ->> 'disposition' <> 'imported'
    );

    -- The completed run update, commit-together with its member inserts: the
    -- final duplicate count is the preview's plus the raced ones.
    update public.member_imports
       set status = 'completed',
           imported_count = v_imported,
           duplicate_count = v_run.duplicate_count + v_final_duplicates,
           error_report = app.member_import_report(
             v_report_rows,
             v_invalid,
             v_run.duplicate_count + v_final_duplicates,
             v_run.error_report -> 'previewCandidateRows',
             v_imported_rows,
             null
           )
     where tenant_id = v_tenant
       and id = p_import_id;

    return jsonb_build_object(
      'importId', p_import_id,
      'status', 'completed',
      'replayed', false,
      'counts', jsonb_build_object(
        'rows', v_run.row_count,
        'imported', v_imported,
        'duplicates', v_run.duplicate_count + v_final_duplicates,
        'invalid', v_invalid
      ),
      'failure', 'null'::jsonb,
      'errorReportUrl', '/api/member-imports/' || p_import_id::text || '/errors'
    );
  exception
    when others then
      -- The failure subtransaction: every member this run created is rolled
      -- back with the block, the run is recorded failed with zero imports and
      -- its preview duplicate count, and the report stays code-only.
      v_failure_rows := v_run.error_report -> 'rows';
      update public.member_imports
         set status = 'failed',
             imported_count = 0,
             error_report = app.member_import_report(
               v_failure_rows,
               (v_run.error_report -> 'summary' ->> 'invalid')::integer,
               v_run.duplicate_count,
               v_run.error_report -> 'previewCandidateRows',
               '[]'::jsonb,
               jsonb_build_object('code', 'processing_failed')
             )
       where tenant_id = v_tenant
         and id = p_import_id;
      return jsonb_build_object(
        'importId', p_import_id,
        'status', 'failed',
        'replayed', false,
        'counts', jsonb_build_object(
          'rows', v_run.row_count,
          'imported', 0,
          'duplicates', v_run.duplicate_count,
          'invalid', (v_run.error_report -> 'summary' ->> 'invalid')::integer
        ),
        'failure', jsonb_build_object('code', 'processing_failed'),
        'errorReportUrl', '/api/member-imports/' || p_import_id::text || '/errors'
      );
  end;
end
$fn$;

revoke all on function public.commit_member_import(uuid, text, jsonb)
  from public, anon, service_role;
grant execute on function public.commit_member_import(uuid, text, jsonb)
  to authenticated;
