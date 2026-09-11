-- Phase 6 leads: enquiry capture with durable evidence, the enquiry stage
-- graph under CAS, lead conversion with duplicate-member resolution, and the
-- /leads list snapshot. Frozen contract: docs/planning/phase6-leads-contract.md
-- (LEAD-001..LEAD-005, GL059..GL062). Registry: docs/registry.md, "Phase 6
-- leads database functions" and "Phase 6 leads database triggers".
--
-- The design in one paragraph. A lead is written by the front office only, and
-- every mutation derives tenant and actor from claims, never parameters. New
-- authenticated creation is evidenced: the request key, the normalized request
-- facts and the real acting staff id are frozen on the row, a key/facts pair
-- is always both null or both present, and an exact same-actor retry replays
-- the original stable lead id while a reused key with different facts or actor
-- is GL062. The stage graph (new -> contacted -> trial_scheduled ->
-- trial_done -> converted, any nonterminal -> lost) is enforced twice: by
-- transition_lead and by a BEFORE INSERT OR UPDATE discipline guard, so an
-- authorized direct writer cannot skip a stage, reopen a terminal row or
-- fabricate evidence either. revision is database-owned: rotated only on
-- accepted material changes, never by the client, and a missed CAS is a
-- returned {staleLead, currentRevision} conflict rather than an error.
-- Conversion is convert_lead's alone: it resolves the exact replay before any
-- revision or stage check, locks the lead and the exact-phone member space,
-- and creates or links the member in the same transaction as the one-time
-- conversion write. list_leads is the single STABLE snapshot the /leads loader
-- calls under RLS, because a plain count after the cursor would count only the
-- remaining tail.
--
-- Ordering note: the evidence columns and their constraints land before the
-- discipline trigger is recreated, so the revision backfill runs under the old
-- BEFORE UPDATE stamp and no guard fires on historical rows.

-- ---------------------------------------------------------------------------
-- 0. Preconditions
-- ---------------------------------------------------------------------------

do $migration$
begin
  -- The Phase 6 discipline guard replaces the platform stamp trigger by name,
  -- so it must find it; and the evidence migration must find an un-migrated
  -- leads table, or this file would be replaying on top of itself.
  if not exists (
    select 1 from pg_catalog.pg_trigger
     where tgrelid = 'public.leads'::regclass
       and tgname = 'leads_touch_updated_at'
  ) then
    raise exception 'Phase 6 leads expects the platform leads stamp trigger';
  end if;
  if exists (
    select 1 from pg_catalog.pg_attribute
     where attrelid = 'public.leads'::regclass
       and attname = 'revision'
  ) then
    raise exception 'Phase 6 leads expects an un-migrated leads table';
  end if;
end
$migration$;

-- ---------------------------------------------------------------------------
-- 1. Evidence columns, the database-owned revision, and pair coherence
-- ---------------------------------------------------------------------------

-- Creation and conversion evidence is durable history: nullable on purpose,
-- because rows written before Phase 6 (and the direct-writer conversion path)
-- carry none, while every new authenticated creation and RPC conversion must.
-- revision is the CAS token -- nonnull and populated for every row, including
-- history, but only ever rotated by the discipline guard.
alter table public.leads
  add column created_by_staff_id uuid,
  add column creation_request_key uuid,
  add column creation_request_facts jsonb,
  add column conversion_request_key uuid,
  add column conversion_request_facts jsonb,
  add column revision uuid;

update public.leads
   set revision = gen_random_uuid()
 where revision is null;

alter table public.leads
  alter column revision set not null,
  alter column revision set default gen_random_uuid();

-- A key/facts pair is either both null or both nonnull (GL060's wire shape is
-- enforced here as a table invariant so no writer can store half an envelope).
alter table public.leads
  add constraint leads_creation_evidence_pair_chk
    check ((creation_request_key is null) = (creation_request_facts is null)),
  add constraint leads_conversion_evidence_pair_chk
    check ((conversion_request_key is null) = (conversion_request_facts is null));

-- ---------------------------------------------------------------------------
-- 2. The composite creator reference and its indexes
-- ---------------------------------------------------------------------------

-- ADR-052: branch, assignee and converted-member references are already
-- tenant-composite on leads; the creator is the one this cluster adds.
alter table public.leads
  add constraint leads_tenant_id_created_by_staff_id_fkey
    foreign key (tenant_id, created_by_staff_id)
    references public.staff (tenant_id, id);

-- Rule 2: every FK column leads an index or sits right after the tenant
-- column. The creator reference is its own leading-tenant index.
create index leads_created_by_staff_id_idx
  on public.leads (tenant_id, created_by_staff_id);

-- Retry identity is tenant-scoped and partial (ADR-047): a gym can only clash
-- with its own keys, and rows without evidence hold no slot at all.
create unique index leads_tenant_id_creation_request_key_key
  on public.leads (tenant_id, creation_request_key)
  where creation_request_key is not null;

create unique index leads_tenant_id_conversion_request_key_key
  on public.leads (tenant_id, conversion_request_key)
  where conversion_request_key is not null;

-- The keyset cursor (updated_at desc, id desc) is the list's only traversal
-- order; the leading tenant column keeps it inside one policy predicate.
create index leads_tenant_id_updated_at_id_idx
  on public.leads (tenant_id, updated_at desc, id desc);

-- ---------------------------------------------------------------------------
-- 3. RLS: preview identities never read or write leads
-- ---------------------------------------------------------------------------

-- The tenant policies keep their names and their role shape (04_contract_meta
-- pins both) and gain exactly one term: an impersonation session is not a
-- reader or a writer, however privileged its claims are. A policy filters
-- rather than raises, which is what makes the preview identity's SELECT empty;
-- its writes are refused with the platform's 42501 read-only error by the
-- statement-level leads_preview_write_guard below, because a filtered write
-- would fire no row trigger at all. The platform policies
-- (leads_platform_select / leads_platform_write) are untouched -- cross-gym
-- support reads and super-admin direct writes keep existing authority.
drop policy leads_tenant_select on public.leads;
drop policy leads_tenant_write on public.leads;

create policy leads_tenant_select on public.leads
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.is_front_office())
         and (select app.current_impersonation_id()) is null);

create policy leads_tenant_write on public.leads
  for all to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.is_front_office())
         and (select app.current_impersonation_id()) is null)
  with check (tenant_id = (select app.current_tenant_id())
         and (select app.is_front_office())
         and (select app.current_impersonation_id()) is null);

-- ---------------------------------------------------------------------------
-- 4. Private helpers
-- --------------------------------------------------------------------

-- app.normalize_lead_text -- the canonical-text helper the mutation RPCs
-- share with the routes' parsers: collapse whitespace runs, trim, and turn a
-- blank optional field into null rather than the empty string, so a stored
-- fact never differs from the fact the caller sent and replay equality is a
-- plain jsonb comparison.
create function app.normalize_lead_text(p_text text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select nullif(
           btrim(
             regexp_replace(coalesce(p_text, ''), '[[:space:]]+', ' ', 'g')
           ),
           ''
         );
$fn$;

revoke all on function app.normalize_lead_text(text)
  from public, anon;
grant execute on function app.normalize_lead_text(text)
  to authenticated;

-- app.lead_detail_json -- the contract's exact LeadDetail: the list row plus
-- email, notes, convertedAt and createdAt. Both mutation RPCs return the same
-- envelope through this renderer, so no handler assembles it by hand. The
-- staff and branch name lookups run under the caller's own read authority.
create function app.lead_detail_json(p_lead public.leads)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $fn$
  select jsonb_build_object(
    'assignedToName', (select s.full_name
                         from public.staff s
                        where s.tenant_id = p_lead.tenant_id
                          and s.id = p_lead.assigned_to_staff_id),
    'assignedToStaffId', p_lead.assigned_to_staff_id,
    'branchId', p_lead.branch_id,
    'branchName', (select b.name
                     from public.branches b
                    where b.tenant_id = p_lead.tenant_id
                      and b.id = p_lead.branch_id),
    'convertedAt', p_lead.converted_at,
    'convertedMemberId', p_lead.converted_member_id,
    'createdAt', p_lead.created_at,
    'email', p_lead.email,
    'fullName', p_lead.full_name,
    'id', p_lead.id,
    'lostReason', p_lead.lost_reason,
    'notes', p_lead.notes,
    'phone', p_lead.phone,
    'revision', p_lead.revision,
    'source', p_lead.source,
    'stage', p_lead.stage,
    'trialAt', p_lead.trial_at,
    'updatedAt', p_lead.updated_at
  );
$fn$;

revoke all on function app.lead_detail_json(public.leads)
  from public, anon;
grant execute on function app.lead_detail_json(public.leads)
  to authenticated;

-- app.assert_lead_writer -- the front-office gate every lead mutation calls
-- before it looks up any target: an authenticated, non-impersonating
-- gym_owner, gym_manager or front_desk whose staff claim names a real active
-- same-tenant staff row. It returns the acting staff id. A permission refusal
-- and an unknown or cross-gym id cannot be told apart from the outside,
-- because the gate answers before any lookup runs.
create function app.assert_lead_writer()
returns uuid
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_staff uuid;
begin
  if auth.uid() is null
     or app.is_front_office() is not true
     or app.current_tenant_id() is null
     or app.current_staff_id() is null
     or app.current_impersonation_id() is not null then
    raise exception 'A lead write requires a real front-office session'
      using errcode = '42501';
  end if;

  select s.id into v_staff
    from public.staff s
   where s.tenant_id = app.current_tenant_id()
     and s.id = app.current_staff_id()
     and s.is_active;
  if v_staff is null then
    raise exception 'A lead write requires a real front-office session'
      using errcode = '42501';
  end if;

  return v_staff;
end
$fn$;

revoke all on function app.assert_lead_writer()
  from public, anon;
grant execute on function app.assert_lead_writer()
  to authenticated;

-- app.resolve_org_time_zone -- the organization's validated timezone: the one
-- zone the conversion's gym-local joined_on is computed in, never the
-- server's. A gym whose zone cannot be read under the caller's policies is
-- indistinguishable from one that cannot be converted, so every unreadable,
-- missing or unknown zone answers the same generic not-found.
create function app.resolve_org_time_zone(p_tenant uuid)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_zone text;
begin
  select o.timezone into v_zone
    from public.organizations o
   where o.id = p_tenant;

  if v_zone is null
     or not exists (
       select 1 from pg_catalog.pg_timezone_names n
        where n.name = v_zone
     ) then
    raise exception 'Organization not found'
      using errcode = 'P0002';
  end if;

  return v_zone;
end
$fn$;

revoke all on function app.resolve_org_time_zone(uuid)
  from public, anon;
grant execute on function app.resolve_org_time_zone(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The direct-row discipline guard and the recreated stamp trigger
-- ---------------------------------------------------------------------------

-- app.enforce_lead_discipline holds the invariants the RPCs also enforce, so
-- an authorized direct writer -- the platform roles the write policies admit,
-- or an operator with BYPASSRLS repairing a row -- meets the same graph, the
-- same stage facts, the same evidence freeze and the same stamping rules.
--
-- Both halves hold the data invariants for every writer. The INSERT half was
-- first written gated on row_security_active(), on the theory that the table
-- owner and BYPASSRLS roles are trusted with history; the leads security
-- review rejected that carve-out (ADR-082: where the rule's subject is an
-- invariant about the data, the trusted caller needs it more) because
-- service_role cannot disable triggers and a service-key insert could
-- fabricate a converted row with invented evidence, silently. History rows
-- now enter only through an explicit bypass the writer must state out loud:
-- session_replication_role = replica for the pgTAP fixtures, and a named
-- ALTER TABLE ... DISABLE TRIGGER for the demo seed (ADR-098's pattern, the
-- one memberships, addon_orders and pt_sessions already use).
--
--   INSERT discipline is claim-keyed only where the fact is about the actor:
--   an authenticated writer with a staff claim must stamp itself as the
--   creator and carry creation evidence, and a claimless owner insert -- the
--   tenancy suite's control case -- stays a policy question rather than an
--   evidence one. Every other INSERT invariant -- the fresh-enquiry graph
--   position, the stage facts, the evidence coherence, the assignee -- and
--   the server-stamped times of record apply to every writer including
--   postgres.
--
--   UPDATE discipline is ungated: immutability, the graph, stage facts, the
--   terminal freeze and stamping apply to every writer including postgres.
--   The graph check runs before the row-facts check, because an illegal edge
--   is the contract's GL059 and a legal edge with wrong facts its GL060.
--
-- Stamping: statement_timestamp() is the server clock of the accepted write
-- (now() would not advance between statements inside one transaction, and the
-- updated_at ordering the list cursor sorts by is per-write state). revision
-- rotates only on an accepted material change; a no-op write restores both it
-- and updated_at from the old row, which is also what makes a client-supplied
-- revision never the stored one.
create function app.enforce_lead_discipline()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_actor uuid;
  v_conversion_edge boolean;
  v_material boolean;
begin
  v_actor := app.current_staff_id();

  if tg_op = 'INSERT' then
    -- A creation is a fresh enquiry for every writer; see the gating note in
    -- the block comment above.
    if new.stage <> 'new' then
      raise exception 'A lead is created only at the new stage'
        using errcode = 'GL060';
    end if;
    if new.trial_at is not null
       or new.lost_reason is not null
       or new.converted_member_id is not null
       or new.converted_at is not null then
      raise exception 'A new lead carries no trial, conversion or loss facts'
        using errcode = 'GL060';
    end if;
    if (new.creation_request_key is null) <> (new.creation_request_facts is null)
       or (new.conversion_request_key is null) <> (new.conversion_request_facts is null) then
      raise exception 'Evidence is a request key and its facts together'
        using errcode = 'GL060';
    end if;
    if new.conversion_request_key is not null then
      raise exception 'Conversion evidence is written by the conversion, not the creation'
        using errcode = 'GL060';
    end if;
    -- New authenticated creation stamps the real acting staff id. The check
    -- is keyed on the claim, not the session, so a claimless write stays a
    -- policy refusal and a claimed one cannot create evidence for someone
    -- else.
    if v_actor is not null then
      if new.created_by_staff_id is distinct from v_actor then
        raise exception 'The creating actor is the authenticated staff member'
          using errcode = '42501';
      end if;
      if new.creation_request_key is null then
        raise exception 'An authenticated creation stores its request evidence'
          using errcode = 'GL060';
      end if;
    end if;
    -- The assignee fact, validated wherever it can first appear.
    if new.assigned_to_staff_id is not null
       and not exists (
         select 1 from public.staff s
          where s.tenant_id = new.tenant_id
            and s.id = new.assigned_to_staff_id
            and s.is_active
            and s.role in ('gym_owner', 'gym_manager', 'front_desk')
       ) then
      raise exception 'The assignee must be active front office'
        using errcode = 'GL060';
    end if;
    -- A fresh row always carries a server-owned revision and server-stamped
    -- times of record: the RPC surface never supplies either, and a direct
    -- writer cannot backdate a creation or pin a row to the top of the
    -- keyset list with a far-future updated_at.
    new.revision := gen_random_uuid();
    new.created_at := statement_timestamp();
    new.updated_at := statement_timestamp();
    return new;
  end if;

  -- UPDATE ---------------------------------------------------------------

  -- 1. Identity and creation evidence are immutable, for every writer.
  if new.id is distinct from old.id
     or new.tenant_id is distinct from old.tenant_id
     or new.created_at is distinct from old.created_at
     or new.created_by_staff_id is distinct from old.created_by_staff_id
     or new.creation_request_key is distinct from old.creation_request_key
     or new.creation_request_facts is distinct from old.creation_request_facts then
    raise exception 'Lead identity and creation evidence are immutable'
      using errcode = '42501';
  end if;

  -- 2. Conversion evidence is written exactly once, on the conversion edge.
  v_conversion_edge := old.stage <> 'converted' and new.stage = 'converted';
  if old.conversion_request_key is not null then
    if new.conversion_request_key is distinct from old.conversion_request_key
       or new.conversion_request_facts is distinct from old.conversion_request_facts then
      raise exception 'Conversion evidence is frozen once written'
        using errcode = '42501';
    end if;
  elsif new.conversion_request_key is not null then
    if not v_conversion_edge then
      raise exception 'Conversion evidence appears only at the conversion'
        using errcode = '42501';
    end if;
    if new.conversion_request_facts is null then
      raise exception 'Evidence is a request key and its facts together'
        using errcode = 'GL060';
    end if;
  end if;

  -- 3. The graph, only on an actual stage change. lost is reachable from
  --    every nonterminal stage; converted is reachable only from trial_done
  --    and only through convert_lead's one-time write.
  if new.stage is distinct from old.stage then
    if not (
         (old.stage = 'new'             and new.stage in ('contacted', 'lost'))
      or (old.stage = 'contacted'       and new.stage in ('trial_scheduled', 'lost'))
      or (old.stage = 'trial_scheduled' and new.stage in ('trial_done', 'lost'))
      or (old.stage = 'trial_done'      and new.stage in ('converted', 'lost'))
    ) then
      raise exception 'That stage move is not an edge of the enquiry graph'
        using errcode = 'GL059';
    end if;
  end if;

  -- 4. A terminal row's business facts are frozen. Notes stay editable: the
  --    terminal freeze is about the facts the stage verdict was reached on,
  --    and an operator note on a closed lead is still an accepted write that
  --    rotates the revision.
  if old.stage in ('lost', 'converted') then
    if new.stage is distinct from old.stage
       or new.full_name is distinct from old.full_name
       or new.phone is distinct from old.phone
       or new.email is distinct from old.email
       or new.source is distinct from old.source
       or new.branch_id is distinct from old.branch_id
       or new.assigned_to_staff_id is distinct from old.assigned_to_staff_id
       or new.trial_at is distinct from old.trial_at
       or new.lost_reason is distinct from old.lost_reason
       or new.converted_member_id is distinct from old.converted_member_id
       or new.converted_at is distinct from old.converted_at then
      raise exception 'A terminal lead is frozen'
        using errcode = 'GL059';
    end if;
  end if;

  -- 5. Row facts per stage. trial_at is kept when it was already earned
  --    (lost and converted retain the trial instant); the earlier stages
  --    forbid it.
  if new.stage in ('new', 'contacted') then
    if new.trial_at is not null
       or new.lost_reason is not null
       or new.converted_member_id is not null
       or new.converted_at is not null then
      raise exception 'An early-stage lead carries no trial, conversion or loss facts'
        using errcode = 'GL060';
    end if;
  elsif new.stage in ('trial_scheduled', 'trial_done') then
    if new.trial_at is null
       or new.lost_reason is not null
       or new.converted_member_id is not null
       or new.converted_at is not null then
      raise exception 'A trial stage requires its trial instant and nothing else'
        using errcode = 'GL060';
    end if;
  elsif new.stage = 'lost' then
    if nullif(btrim(coalesce(new.lost_reason, '')), '') is null
       or new.converted_member_id is not null
       or new.converted_at is not null then
      raise exception 'A lost lead requires a trimmed nonempty reason and no conversion facts'
        using errcode = 'GL060';
    end if;
  elsif new.stage = 'converted' then
    if new.converted_member_id is null
       or new.converted_at is null
       or new.lost_reason is not null then
      raise exception 'A converted lead names its member and its conversion time'
        using errcode = 'GL060';
    end if;
  end if;

  -- 6. The assignee fact, checked when it is being set -- an unchanged
  --    assignee whose staff row has since gone inactive must not brick every
  --    later notes edit on the same lead.
  if new.assigned_to_staff_id is not null
     and new.assigned_to_staff_id is distinct from old.assigned_to_staff_id
     and not exists (
       select 1 from public.staff s
        where s.tenant_id = new.tenant_id
          and s.id = new.assigned_to_staff_id
          and s.is_active
          and s.role in ('gym_owner', 'gym_manager', 'front_desk')
     ) then
    raise exception 'The assignee must be active front office'
      using errcode = 'GL060';
  end if;

  -- 7. The one-time conversion write locks the target member and requires
  --    same tenant, the lead's exact phone and an eligible status before it
  --    is accepted.
  if v_conversion_edge then
    perform pg_advisory_xact_lock(hashtextextended(
      'lead-member-id:' || new.tenant_id::text || ':' || new.converted_member_id::text, 0
    ));
    if not exists (
      select 1 from public.members m
       where m.tenant_id = new.tenant_id
         and m.id = new.converted_member_id
         and m.phone = new.phone
         and m.status not in ('cancelled', 'blocked')
         and m.erased_at is null
    ) then
      raise exception 'The conversion names a same-gym eligible member with the lead''s exact phone'
        using errcode = 'GL060';
    end if;
  end if;

  -- 8. Stamping. The material set is the editable business facts plus the
  --    stage and its payloads; evidence, identity and timestamps of record
  --    are never "material" because they are never writable here.
  v_material :=
       new.full_name is distinct from old.full_name
    or new.phone is distinct from old.phone
    or new.email is distinct from old.email
    or new.source is distinct from old.source
    or new.branch_id is distinct from old.branch_id
    or new.assigned_to_staff_id is distinct from old.assigned_to_staff_id
    or new.stage is distinct from old.stage
    or new.trial_at is distinct from old.trial_at
    or new.converted_member_id is distinct from old.converted_member_id
    or new.converted_at is distinct from old.converted_at
    or new.lost_reason is distinct from old.lost_reason
    or new.notes is distinct from old.notes;
  if v_material then
    new.revision := gen_random_uuid();
    new.updated_at := statement_timestamp();
  else
    -- A no-op write touches neither, and a client-supplied revision never
    -- becomes the stored revision.
    new.revision := old.revision;
    new.updated_at := old.updated_at;
  end if;

  return new;
end
$fn$;

-- The platform migration created leads_touch_updated_at as a plain BEFORE
-- UPDATE stamp running app.touch_updated_at(). Phase 6 recreates it under the
-- same name -- the tenancy suite pins the name -- as the BEFORE INSERT OR
-- UPDATE discipline guard. Preview writes are refused one level earlier: the
-- tenant policies filter an impersonation session's rows away, so the
-- row-level leads_preview_read_only would never fire for one, and the
-- statement-level leads_preview_write_guard answers instead, before any row
-- resolution.
drop trigger leads_touch_updated_at on public.leads;

create trigger leads_touch_updated_at
  before insert or update on public.leads
  for each row
  execute function app.enforce_lead_discipline();

-- A preview session's UPDATE or DELETE matches no rows through the tenant
-- policies, so no row-level trigger ever sees it, and its INSERT would fail
-- the policies' WITH CHECK instead. The statement-level guard refuses all
-- three the way the rest of the authenticated-writable surface does, with the
-- platform's read-only error, before any row is resolved. It reuses
-- app.enforce_preview_read_only(), whose row_security_active gate keeps
-- database authority untouched.
create trigger leads_preview_write_guard
  before insert or update or delete on public.leads
  for each statement
  execute function app.enforce_preview_read_only();

revoke all on function app.enforce_lead_discipline()
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. public.create_lead -- enquiry capture with durable evidence
-- ---------------------------------------------------------------------------

create function public.create_lead(
  p_request_key uuid,
  p_branch_id uuid,
  p_full_name text,
  p_phone text,
  p_email text,
  p_source public.lead_source,
  p_assigned_to_staff_id uuid,
  p_notes text
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_staff uuid;
  v_existing public.leads%rowtype;
  v_full_name text;
  v_phone text;
  v_email text;
  v_notes text;
  v_facts jsonb;
  v_id uuid;
  v_revision uuid;
begin
  v_staff := app.assert_lead_writer();
  v_tenant := app.current_tenant_id();

  if p_request_key is null then
    raise exception 'A creation requires its request key'
      using errcode = '22023';
  end if;

  -- Canonical text first: the same normalization decides replay equality and
  -- the stored facts, so an unnormalized retry still matches the committed
  -- creation.
  v_full_name := app.normalize_lead_text(p_full_name);
  v_phone := nullif(btrim(coalesce(p_phone, '')), '');
  v_email := app.normalize_lead_text(p_email);
  v_notes := app.normalize_lead_text(p_notes);

  -- Serialize the key before deciding: two racing desks with one key become
  -- one lead, and the partial unique index answers any path the lock misses.
  perform pg_advisory_xact_lock(hashtextextended(
    'lead-create:' || v_tenant::text || ':' || p_request_key::text, 0
  ));

  select l.* into v_existing
    from public.leads l
   where l.tenant_id = v_tenant
     and l.creation_request_key = p_request_key;
  if found then
    if v_existing.creation_request_facts = jsonb_build_object(
         'actorStaffId', v_staff,
         'branchId', p_branch_id,
         'fullName', v_full_name,
         'phone', v_phone,
         'email', v_email,
         'source', p_source,
         'assignedToStaffId', p_assigned_to_staff_id,
         'notes', v_notes
       ) then
      -- Replay returns the original stable lead id with its CURRENT revision,
      -- not a snapshot of the first response.
      return jsonb_build_object(
        'leadId', v_existing.id,
        'revision', v_existing.revision,
        'replayed', true
      );
    end if;
    raise exception 'This creation request key is bound to different facts'
      using errcode = 'GL062', detail = 'idempotency_conflict';
  end if;

  -- Request facts become row facts; validate them as such.
  if v_full_name is null then
    raise exception 'A lead requires a name'
      using errcode = 'GL060';
  end if;
  if v_phone is null or v_phone !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception 'A lead requires an E.164 phone'
      using errcode = 'GL060';
  end if;
  if p_branch_id is null
     or not exists (
       select 1 from public.branches b
        where b.tenant_id = v_tenant
          and b.id = p_branch_id
     ) then
    raise exception 'Branch not found'
      using errcode = 'P0002';
  end if;
  if p_assigned_to_staff_id is not null then
    if not exists (
      select 1 from public.staff s
       where s.tenant_id = v_tenant
         and s.id = p_assigned_to_staff_id
    ) then
      raise exception 'Staff not found'
        using errcode = 'P0002';
    end if;
    if not exists (
      select 1 from public.staff s
       where s.tenant_id = v_tenant
         and s.id = p_assigned_to_staff_id
         and s.is_active
         and s.role in ('gym_owner', 'gym_manager', 'front_desk')
    ) then
      raise exception 'The assignee must be active front office'
        using errcode = 'GL060';
    end if;
  end if;

  v_facts := jsonb_build_object(
    'actorStaffId', v_staff,
    'branchId', p_branch_id,
    'fullName', v_full_name,
    'phone', v_phone,
    'email', v_email,
    'source', p_source,
    'assignedToStaffId', p_assigned_to_staff_id,
    'notes', v_notes
  );

  insert into public.leads (
    tenant_id, branch_id, full_name, phone, email, source, stage,
    assigned_to_staff_id, notes,
    created_by_staff_id, creation_request_key, creation_request_facts
  ) values (
    v_tenant, p_branch_id, v_full_name, v_phone, v_email, p_source, 'new',
    p_assigned_to_staff_id, v_notes,
    v_staff, p_request_key, v_facts
  )
  returning id, revision into v_id, v_revision;

  return jsonb_build_object(
    'leadId', v_id,
    'revision', v_revision,
    'replayed', false
  );
end
$fn$;

revoke all on function public.create_lead(
  uuid, uuid, text, text, text, public.lead_source, uuid, text
) from public, anon;
grant execute on function public.create_lead(
  uuid, uuid, text, text, text, public.lead_source, uuid, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. public.update_lead -- same-stage detail edit under CAS
-- ---------------------------------------------------------------------------

create function public.update_lead(
  p_lead_id uuid,
  p_expected_revision uuid,
  p_branch_id uuid,
  p_full_name text,
  p_phone text,
  p_email text,
  p_source public.lead_source,
  p_assigned_to_staff_id uuid,
  p_notes text
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_staff uuid;
  v_row public.leads%rowtype;
  v_updated public.leads%rowtype;
  v_full_name text;
  v_phone text;
  v_email text;
  v_notes text;
begin
  v_staff := app.assert_lead_writer();
  v_tenant := app.current_tenant_id();

  perform pg_advisory_xact_lock(hashtextextended(
    'lead:' || v_tenant::text || ':' || p_lead_id::text, 0
  ));

  select l.* into v_row
    from public.leads l
   where l.tenant_id = v_tenant
     and l.id = p_lead_id;
  if not found then
    raise exception 'Lead not found'
      using errcode = 'P0002';
  end if;

  if v_row.revision is distinct from p_expected_revision then
    return jsonb_build_object('staleLead', true, 'currentRevision', v_row.revision);
  end if;

  -- The same rule set create_lead validates, minus the evidence: a detail
  -- edit re-proves the facts it is rewriting.
  v_full_name := app.normalize_lead_text(p_full_name);
  v_phone := nullif(btrim(coalesce(p_phone, '')), '');
  v_email := app.normalize_lead_text(p_email);
  v_notes := app.normalize_lead_text(p_notes);

  if v_full_name is null then
    raise exception 'A lead requires a name'
      using errcode = 'GL060';
  end if;
  if v_phone is null or v_phone !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception 'A lead requires an E.164 phone'
      using errcode = 'GL060';
  end if;
  if p_branch_id is null
     or not exists (
       select 1 from public.branches b
        where b.tenant_id = v_tenant
          and b.id = p_branch_id
     ) then
    raise exception 'Branch not found'
      using errcode = 'P0002';
  end if;
  if p_assigned_to_staff_id is not null then
    if not exists (
      select 1 from public.staff s
       where s.tenant_id = v_tenant
         and s.id = p_assigned_to_staff_id
    ) then
      raise exception 'Staff not found'
        using errcode = 'P0002';
    end if;
    if not exists (
      select 1 from public.staff s
       where s.tenant_id = v_tenant
         and s.id = p_assigned_to_staff_id
         and s.is_active
         and s.role in ('gym_owner', 'gym_manager', 'front_desk')
    ) then
      raise exception 'The assignee must be active front office'
        using errcode = 'GL060';
    end if;
  end if;

  -- The stage is never written here. A terminal row's frozen business facts
  -- are the discipline guard's GL059 to answer.
  update public.leads
     set branch_id = p_branch_id,
         full_name = v_full_name,
         phone = v_phone,
         email = v_email,
         source = p_source,
         assigned_to_staff_id = p_assigned_to_staff_id,
         notes = v_notes
   where tenant_id = v_tenant
     and id = p_lead_id
   returning * into v_updated;

  return jsonb_build_object('lead', app.lead_detail_json(v_updated));
end
$fn$;

revoke all on function public.update_lead(
  uuid, uuid, uuid, text, text, text, public.lead_source, uuid, text
) from public, anon;
grant execute on function public.update_lead(
  uuid, uuid, uuid, text, text, text, public.lead_source, uuid, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. public.transition_lead -- the stage graph under CAS
-- ---------------------------------------------------------------------------

create function public.transition_lead(
  p_lead_id uuid,
  p_expected_revision uuid,
  p_target public.lead_stage,
  p_trial_at timestamptz,
  p_lost_reason text
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_staff uuid;
  v_row public.leads%rowtype;
  v_updated public.leads%rowtype;
  v_trial_at timestamptz;
  v_reason text;
begin
  v_staff := app.assert_lead_writer();
  v_tenant := app.current_tenant_id();

  -- Conversion is convert_lead's alone: it carries the member write, and a
  -- stage move that skipped it would be a conversion with no member.
  if p_target is null or p_target = 'converted' then
    raise exception 'Conversion belongs to the conversion command'
      using errcode = 'GL059';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'lead:' || v_tenant::text || ':' || p_lead_id::text, 0
  ));

  select l.* into v_row
    from public.leads l
   where l.tenant_id = v_tenant
     and l.id = p_lead_id;
  if not found then
    raise exception 'Lead not found'
      using errcode = 'P0002';
  end if;

  -- The CAS miss is answered before the graph, like update_lead orders it: a
  -- writer acting on an out-of-date row gets the contract's exact stale_lead
  -- envelope with the retry revision, even when its target has also stopped
  -- being an edge since -- a graph refusal there would read as a different
  -- problem and hand the desk no revision to retry against.
  if v_row.revision is distinct from p_expected_revision then
    return jsonb_build_object('staleLead', true, 'currentRevision', v_row.revision);
  end if;

  -- The graph applies only to actual stage changes: a self-transition is
  -- refused even when its facts would be legal.
  if p_target = v_row.stage then
    raise exception 'A lead cannot transition to its own stage'
      using errcode = 'GL059';
  end if;

  if not (
       (v_row.stage = 'new'             and p_target in ('contacted', 'lost'))
    or (v_row.stage = 'contacted'       and p_target in ('trial_scheduled', 'lost'))
    or (v_row.stage = 'trial_scheduled' and p_target in ('trial_done', 'lost'))
    or (v_row.stage = 'trial_done'      and p_target = 'lost')
  ) then
    raise exception 'That stage move is not an edge of the enquiry graph'
      using errcode = 'GL059';
  end if;

  -- An earlier-stage target owns no trial instant: one that arrives anyway
  -- is an invalid stage fact -- the same rule that makes trial_scheduled and
  -- trial_done require it -- not a silently dropped payload.
  if p_trial_at is not null and p_target in ('new', 'contacted') then
    raise exception 'A non-trial stage forbids a trial instant'
      using errcode = 'GL060';
  end if;

  -- The payload the target stage owns. Trial stages take the supplied
  -- instant as-is (no coalescing: a missing instant is a GL060 fact the
  -- guard answers); lost keeps the instant it already earned; every other
  -- target carries none. The loss reason passes through normalized for every
  -- target -- a non-lost target that arrives with one is GL060, not silently
  -- dropped.
  v_trial_at := case p_target
                  when 'trial_scheduled' then p_trial_at
                  when 'trial_done' then p_trial_at
                  when 'lost' then v_row.trial_at
                  else null
                end;
  v_reason := app.normalize_lead_text(p_lost_reason);

  update public.leads
     set stage = p_target,
         trial_at = v_trial_at,
         lost_reason = v_reason
   where tenant_id = v_tenant
     and id = p_lead_id
   returning * into v_updated;

  return jsonb_build_object('lead', app.lead_detail_json(v_updated));
end
$fn$;

revoke all on function public.transition_lead(
  uuid, uuid, public.lead_stage, timestamptz, text
) from public, anon;
grant execute on function public.transition_lead(
  uuid, uuid, public.lead_stage, timestamptz, text
) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. public.convert_lead -- atomic member creation or link, with replay
-- ---------------------------------------------------------------------------

create function public.convert_lead(
  p_lead_id uuid,
  p_request_key uuid,
  p_expected_revision uuid,
  p_mode text,
  p_member_id uuid default null
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_staff uuid;
  v_lead public.leads%rowtype;
  v_dup public.members%rowtype;
  v_member_id uuid;
  v_timezone text;
  v_outcome text;
  v_facts jsonb;
  v_new_revision uuid;
begin
  v_staff := app.assert_lead_writer();
  v_tenant := app.current_tenant_id();

  if p_request_key is null then
    raise exception 'A conversion requires its request key'
      using errcode = '22023';
  end if;

  -- The lead lock serializes every conversion path on this lead; the member
  -- lock (taken below, on the phone space) serializes the duplicate decision.
  perform pg_advisory_xact_lock(hashtextextended(
    'lead:' || v_tenant::text || ':' || p_lead_id::text, 0
  ));

  select l.* into v_lead
    from public.leads l
   where l.tenant_id = v_tenant
     and l.id = p_lead_id;
  if not found then
    raise exception 'Lead not found'
      using errcode = 'P0002';
  end if;

  -- Retry resolution, after authorization and target visibility and before
  -- any revision or stage check: an exact retry replays the original
  -- immutable outcome even though the row has since moved on.
  if v_lead.conversion_request_key = p_request_key then
    if v_lead.conversion_request_facts = jsonb_build_object(
         'actorStaffId', v_staff,
         'leadId', v_lead.id,
         'expectedRevision', p_expected_revision,
         'mode', p_mode,
         'memberId', p_member_id
       ) then
      return jsonb_build_object(
        'leadId', v_lead.id,
        'memberId', v_lead.converted_member_id,
        'outcome', case v_lead.conversion_request_facts ->> 'mode'
                     when 'create' then 'created_member'
                     when 'link_existing' then 'linked_existing'
                     else 'converted'
                   end,
        'revision', v_lead.revision,
        'replayed', true
      );
    end if;
    raise exception 'This conversion request key is bound to different facts'
      using errcode = 'GL062', detail = 'idempotency_conflict';
  end if;

  -- The key's scope is the gym, not the lead (the unique index is
  -- tenant-wide): the same key arriving for a DIFFERENT lead of this gym is
  -- the key-conflict case the contract names, and without this check it
  -- would surface as a raw 23505 from the index instead of GL062's honest
  -- 409 idempotency_conflict.
  if exists (
    select 1 from public.leads o
     where o.tenant_id = v_tenant
       and o.conversion_request_key = p_request_key
       and o.id <> v_lead.id
  ) then
    raise exception 'This conversion request key is bound to different facts'
      using errcode = 'GL062', detail = 'idempotency_conflict';
  end if;

  -- A converted lead never converts again: a fresh key on one is the stale
  -- conflict, indistinguishable from any other lost race.
  if v_lead.stage = 'converted' then
    return jsonb_build_object('staleLead', true, 'currentRevision', v_lead.revision);
  end if;

  if v_lead.stage <> 'trial_done' then
    raise exception 'Only a trial_done lead converts'
      using errcode = 'GL059';
  end if;

  if v_lead.revision is distinct from p_expected_revision then
    return jsonb_build_object('staleLead', true, 'currentRevision', v_lead.revision);
  end if;

  if p_mode = 'create' then
    -- Lock the exact-phone member space before deciding: one desk converting
    -- while another registers the same phone is the race this whole mode
    -- exists to resolve.
    perform pg_advisory_xact_lock(hashtextextended(
      'lead-member:' || v_tenant::text || ':' || v_lead.phone, 0
    ));

    select m.* into v_dup
      from public.members m
     where m.tenant_id = v_tenant
       and m.phone = v_lead.phone;
    if found then
      if v_dup.status not in ('cancelled', 'blocked') and v_dup.erased_at is null then
        -- An eligible duplicate is an explicit choice: disclose exactly the
        -- four facts the desk needs to make it, and nothing else.
        raise exception 'An eligible member with this phone already exists'
          using errcode = 'GL061',
                detail = jsonb_build_object(
                  'fullName', v_dup.full_name,
                  'memberId', v_dup.id,
                  'phone', v_dup.phone,
                  'status', v_dup.status
                )::text;
      end if;
      -- Cancelled, blocked or erased: a conflict that discloses nothing.
      return jsonb_build_object('memberUnavailable', true);
    end if;

    -- No same-gym member: create the profile in the gym's own zone. The
    -- branch, name, phone and email are the lead's; nothing else is invented
    -- -- no member code, no auth user, no membership, no payment.
    v_timezone := app.resolve_org_time_zone(v_tenant);
    begin
      insert into public.members (
        tenant_id, branch_id, full_name, phone, email, status, joined_on
      ) values (
        v_tenant, v_lead.branch_id, v_lead.full_name, v_lead.phone, v_lead.email,
        'active',
        (transaction_timestamp() at time zone v_timezone)::date
      )
      returning id into v_member_id;
    exception
      when unique_violation then
        -- Another path created the member between the scan and the insert.
        -- Re-read under the lock and make the same explicit choice; a phone
        -- that now exists is never replayed as a creation.
        select m.* into v_dup
          from public.members m
         where m.tenant_id = v_tenant
           and m.phone = v_lead.phone;
        if not found then
          raise exception 'Member not found'
            using errcode = 'P0002';
        end if;
        if v_dup.status not in ('cancelled', 'blocked') and v_dup.erased_at is null then
          raise exception 'An eligible member with this phone already exists'
            using errcode = 'GL061',
                  detail = jsonb_build_object(
                    'fullName', v_dup.full_name,
                    'memberId', v_dup.id,
                    'phone', v_dup.phone,
                    'status', v_dup.status
                  )::text;
        end if;
        return jsonb_build_object('memberUnavailable', true);
    end;
    v_outcome := 'created_member';

  elsif p_mode = 'link_existing' then
    perform pg_advisory_xact_lock(hashtextextended(
      'lead-member:' || v_tenant::text || ':' || v_lead.phone, 0
    ));

    -- The named member must be same-tenant, exact-phone and eligible; a
    -- wrong-phone, unavailable, cross-gym or unknown target is one generic
    -- refusal, indistinguishable from each other.
    select m.id into v_member_id
      from public.members m
     where m.tenant_id = v_tenant
       and m.id = p_member_id
       and m.phone = v_lead.phone
       and m.status not in ('cancelled', 'blocked')
       and m.erased_at is null;
    if v_member_id is null then
      raise exception 'Member not found'
        using errcode = 'P0002';
    end if;
    v_outcome := 'linked_existing';

  else
    raise exception 'The conversion mode is unknown'
      using errcode = '22023';
  end if;

  -- The evidence binds the request as the caller made it: memberId is the
  -- parameter, not the resolved member, so a create-mode retry (which names
  -- no member) compares equal to its own stored facts, and the outcome is
  -- recoverable from the stored mode.
  v_facts := jsonb_build_object(
    'actorStaffId', v_staff,
    'leadId', v_lead.id,
    'expectedRevision', p_expected_revision,
    'mode', p_mode,
    'memberId', p_member_id
  );

  -- The one-time conversion write. The discipline guard locks the member and
  -- re-proves tenant, phone and eligibility on the edge; the evidence pair is
  -- written here and frozen from here on.
  update public.leads
     set stage = 'converted',
         converted_member_id = v_member_id,
         converted_at = transaction_timestamp(),
         conversion_request_key = p_request_key,
         conversion_request_facts = v_facts
   where tenant_id = v_tenant
     and id = p_lead_id
   returning revision into v_new_revision;

  if v_new_revision is null then
    raise exception 'Lead not found'
      using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'leadId', v_lead.id,
    'memberId', v_member_id,
    'outcome', v_outcome,
    'revision', v_new_revision,
    'replayed', false
  );
end
$fn$;

revoke all on function public.convert_lead(
  uuid, uuid, uuid, text, uuid
) from public, anon;
grant execute on function public.convert_lead(
  uuid, uuid, uuid, text, uuid
) to authenticated;

-- ---------------------------------------------------------------------------
-- 10. public.list_leads -- the /leads snapshot
-- ---------------------------------------------------------------------------

-- STABLE, called directly under RLS by the loader: there is no GET /api/leads
-- to keep honest. It requires the complete front-office identity before
-- reading (the gate is inlined here -- the registry binds
-- app.assert_lead_writer() to the four mutation RPCs), then produces the
-- filtered population and its page from one SQL statement, so asOf, the
-- counts and the rows can never disagree. totalMatchingCount and
-- filteredStageCounts are computed over the whole filtered population -- a
-- plain exact count after the cursor would count only the remaining tail.
create function public.list_leads(
  p_stage public.lead_stage default null,
  p_source public.lead_source default null,
  p_assignee text default null,
  p_branch_id uuid default null,
  p_query text default null,
  p_after_updated_at timestamptz default null,
  p_after_id uuid default null,
  p_limit integer default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_assignee uuid;
  v_assignee_unassigned boolean;
  v_query text;
  v_limit integer;
begin
  if auth.uid() is null
     or app.is_front_office() is not true
     or app.current_tenant_id() is null
     or app.current_staff_id() is null
     or app.current_impersonation_id() is not null
     or not exists (
       select 1 from public.staff s
        where s.tenant_id = app.current_tenant_id()
          and s.id = app.current_staff_id()
          and s.is_active
     ) then
    raise exception 'The lead list requires a real front-office session'
      using errcode = '42501';
  end if;
  v_tenant := app.current_tenant_id();

  -- The assignee filter is the one text parameter that is not free text:
  -- null is no filter, 'unassigned' is the null-assignee filter, and anything
  -- else must be a UUID.
  if p_assignee is not null and p_assignee <> 'unassigned' then
    begin
      v_assignee := p_assignee::uuid;
    exception
      when invalid_text_representation then
        raise exception 'The assignee filter is neither unassigned nor a UUID'
          using errcode = 'GL060';
    end;
  end if;
  v_assignee_unassigned := p_assignee = 'unassigned';

  -- An unusable cursor starts page one: the parts arrive together or the
  -- whole cursor is ignored, never a distinct error branch.
  if (p_after_updated_at is null) <> (p_after_id is null) then
    p_after_updated_at := null;
    p_after_id := null;
  end if;

  v_query := nullif(btrim(coalesce(p_query, '')), '');
  -- ILIKE's default escape is the backslash: a query containing % or _ must
  -- match those characters literally, not widen into a wildcard the desk
  -- never typed.
  if v_query is not null then
    v_query := replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_');
  end if;
  v_limit := greatest(least(coalesce(p_limit, 50), 200), 1);

  return (
    with filtered as (
      select l.id, l.tenant_id, l.branch_id, l.full_name, l.phone, l.source, l.stage,
             l.assigned_to_staff_id, l.trial_at, l.converted_member_id,
             l.lost_reason, l.revision, l.updated_at
        from public.leads l
       where l.tenant_id = v_tenant
         and (p_stage is null or l.stage = p_stage)
         and (p_source is null or l.source = p_source)
         and (p_branch_id is null or l.branch_id = p_branch_id)
         and (p_assignee is null
              or (v_assignee_unassigned and l.assigned_to_staff_id is null)
              or l.assigned_to_staff_id = v_assignee)
         and (v_query is null
              or l.full_name ilike '%' || v_query || '%'
              or l.phone ilike '%' || v_query || '%')
    ),
    page as (
      -- One row past the page decides has_more without a second count.
      select f.*, s.full_name as assigned_to_name, b.name as branch_name
        from filtered f
        left join public.staff s
          on s.tenant_id = f.tenant_id and s.id = f.assigned_to_staff_id
        left join public.branches b
          on b.tenant_id = f.tenant_id and b.id = f.branch_id
       where p_after_updated_at is null
          or (f.updated_at, f.id) < (p_after_updated_at, p_after_id)
       order by f.updated_at desc, f.id desc
       limit v_limit + 1
    ),
    trimmed as (
      select * from page order by updated_at desc, id desc limit v_limit
    ),
    tail as (
      select * from page offset v_limit
    )
    select jsonb_build_object(
      'asOf', statement_timestamp(),
      'rows', (
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'assignedToName', t.assigned_to_name,
              'assignedToStaffId', t.assigned_to_staff_id,
              'branchId', t.branch_id,
              'branchName', t.branch_name,
              'convertedMemberId', t.converted_member_id,
              'fullName', t.full_name,
              'id', t.id,
              'lostReason', t.lost_reason,
              'phone', t.phone,
              'revision', t.revision,
              'source', t.source,
              'stage', t.stage,
              'trialAt', t.trial_at,
              'updatedAt', t.updated_at
            ) order by t.updated_at desc, t.id desc
          ),
          '[]'::jsonb
        )
          from trimmed t
      ),
      'nextAfter', case
        when (select count(*) from tail) > 0 then jsonb_build_object(
          'id', (select id from trimmed order by updated_at asc, id asc limit 1),
          'updatedAt', (select updated_at from trimmed order by updated_at asc, id asc limit 1)
        )
        else 'null'::jsonb
      end,
      'pageResultCount', (select count(*)::text from trimmed),
      'totalMatchingCount', (select count(*)::text from filtered),
      'filteredStageCounts', (
        select jsonb_build_object(
          'new', (count(*) filter (where f.stage = 'new'))::text,
          'contacted', (count(*) filter (where f.stage = 'contacted'))::text,
          'trial_scheduled', (count(*) filter (where f.stage = 'trial_scheduled'))::text,
          'trial_done', (count(*) filter (where f.stage = 'trial_done'))::text,
          'converted', (count(*) filter (where f.stage = 'converted'))::text,
          'lost', (count(*) filter (where f.stage = 'lost'))::text
        )
          from filtered f
      )
    )
  );
end
$fn$;

-- list_leads is the one leads RPC the service role gets no hold of either:
-- the gym snapshot is a front-office read, and a server-side caller that
-- needs lead data goes through the same identity rules as the desk.
revoke all on function public.list_leads(
  public.lead_stage, public.lead_source, text, uuid, text, timestamptz, uuid, integer
) from public, anon, service_role;
grant execute on function public.list_leads(
  public.lead_stage, public.lead_source, text, uuid, text, timestamptz, uuid, integer
) to authenticated;
