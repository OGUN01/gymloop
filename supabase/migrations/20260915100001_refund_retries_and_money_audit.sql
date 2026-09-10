-- Refund request identity, named money refusal order and INT-003 financial audit.
-- Frozen contract: openspec/changes/refund-retries-and-money-audit/ and
-- docs/planning/refund-contract-detail.md. CI-only apply; no historical backfill.
-- Existing enforcement clauses are moved from their authoritative definitions,
-- preserving native constraint timing and the trusted-context boundaries.

alter table public.refunds add column idempotency_key text;
create unique index refunds_tenant_id_idempotency_key_key
  on public.refunds (tenant_id, idempotency_key)
  where idempotency_key is not null;

create or replace function app.enforce_payment()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_actor    uuid;
  v_was_paid boolean;
  v_owner    uuid;
begin
  -- GL038 precedes the other named payment rules. Native constraints retain their timing.
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id then
      raise exception 'payment refused: a payment''s id is what refunds, invoices and add-on orders point at, and it does not change'
        using errcode = 'GL038';
    end if;
    -- `refunded` and `reversed` are only reachable from `paid`, so this is
    -- "has this payment ever been paid" written as the three states that mean it.
    v_was_paid := old.status in ('paid'::public.payment_status,
                                 'refunded'::public.payment_status,
                                 'reversed'::public.payment_status);

    if v_was_paid
       and (new.amount_paise        is distinct from old.amount_paise
         or new.currency            is distinct from old.currency
         or new.member_id           is distinct from old.member_id
         or new.membership_id       is distinct from old.membership_id
         or new.method              is distinct from old.method
         or new.receipt_number      is distinct from old.receipt_number
         or new.paid_at             is distinct from old.paid_at
         or new.provider            is distinct from old.provider
         or new.provider_order_id   is distinct from old.provider_order_id
         or new.provider_payment_id is distinct from old.provider_payment_id
         or new.idempotency_key     is distinct from old.idempotency_key) then
      raise exception 'payment refused: % is a record of money that changed hands — its amount, member, membership, method, receipt number and date are what the receipt says, and only status, notes and failed_reason may change afterwards',
        old.receipt_number
        using errcode = 'GL038';
    end if;
  end if;


  if new.membership_id is not null then
    select m.member_id into v_owner
      from public.memberships m
     where m.id = new.membership_id
       and m.tenant_id = new.tenant_id;

    -- Null is a membership this session cannot read, or one in another gym.
    -- Left to the composite foreign key and the policy to answer (ADR-066).
    if v_owner is not null and v_owner is distinct from new.member_id then
      raise exception 'payment refused: membership % belongs to member %, not to %',
        new.membership_id, v_owner, new.member_id
        using errcode = 'GL042';
    end if;
  end if;

  -- GL039 follows identity and precedes attribution/provider separation.
  if tg_op = 'UPDATE' then
    if not app.payment_transition_allowed(old.status, new.status) then
      raise exception 'payment refused: a payment does not go from % to %; paid is unreachable from anywhere it has already been',
        old.status, new.status
        using errcode = 'GL039';
    end if;

  else
    if new.status in ('refunded'::public.payment_status,
                      'reversed'::public.payment_status) then
      raise exception 'payment refused: a payment is recorded and then refunded — it does not arrive already %',
        new.status
        using errcode = 'GL039';
    end if;

  end if;

  -- ---- The claim rules, for sessions row security applies to ---------------
  --
  -- Here the carve-out IS right: both read the JWT, and a trusted context has
  -- none. The Razorpay webhook is `service_role`, has no `staff_id`, and writes
  -- provider identifiers because that is its entire job.
  if not pg_catalog.row_security_active('public.payments') then
    return null;
  end if;

  v_actor := app.current_staff_id();

  if tg_op = 'UPDATE' then
    if new.recorded_by_staff_id is distinct from old.recorded_by_staff_id then
      raise exception 'payment refused: who recorded a payment is a recorded fact and cannot be reassigned (% to %)',
        old.recorded_by_staff_id, new.recorded_by_staff_id
        using errcode = 'GL034';
    end if;
  else
    -- The null actor is its own clause, not one side of the comparison:
    -- `null is distinct from null` is false, and after `stamp_payment` has
    -- filled the column from the same absent claim both sides are null
    -- (ADR-071). Note that `payments_offline_has_staff_chk` refuses a desk
    -- method with no staff member first, so this clause is the one that answers
    -- only for a method that CHECK does not cover — it is defence in depth and
    -- the constraint is what a test will actually observe.
    if v_actor is null
       or new.recorded_by_staff_id is distinct from v_actor then
      raise exception 'payment refused: a payment is recorded by the staff member who took it, and this session records % against an actor of %',
        new.recorded_by_staff_id, coalesce(v_actor::text, 'no staff identity')
        using errcode = 'GL034';
    end if;
  end if;

  if new.method = 'razorpay'::public.payment_method then
    raise exception 'payment refused: an online payment is recorded by the provider, not typed in at the desk — the desk records cash, upi, card or bank_transfer (PAY-006)'
      using errcode = 'GL035';
  end if;

  if new.provider is not null
     or new.provider_order_id is not null
     or new.provider_payment_id is not null then
    raise exception 'payment refused: a % payment cannot carry provider identifiers — that shape launders desk money into apparently-verified money',
      new.method
      using errcode = 'GL035';
  end if;

  return null;
end;
$fn$;

create or replace function app.enforce_refund_total()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_paid     bigint;
  v_refunded bigint;
  v_actor    uuid;
begin
  -- ---- Immutability, for every writer -------------------------------------
  if tg_op = 'UPDATE'
     and (new.id is distinct from old.id
       or new.idempotency_key is distinct from old.idempotency_key
       or new.currency is distinct from old.currency
       or new.kind is distinct from old.kind
       or new.payment_id is distinct from old.payment_id
       or new.amount_paise is distinct from old.amount_paise) then
    raise exception 'refund refused: which payment a refund is against, and how much it returned, are what it IS — correct it with a new row (PAY-010)'
      using errcode = 'GL041';
  end if;

  -- **A refund that completed did not fail.** The ceiling sums the refunds that
  -- are not `failed`, and nothing froze a refund's status — so a critic recorded
  -- a full refund, had a second one refused by `GL036`, demoted the first to
  -- `failed`, and the second was then accepted. Money that left the gym became
  -- an attempt that never happened.
  --
  -- ADR-089's general form, one table over: a freeze is worth exactly as much as
  -- the immutability of the thing it is keyed on.
  --
  -- **Only out of `completed`, and the narrowness is the point.** A refund at
  -- `requested` or `processing` is money the gym has handed over and the provider
  -- has not yet moved; it can genuinely fail, that is what the status is for, and
  -- refusing the transition would strand it while the ceiling ate money that
  -- never left. Both blind authors found that the same un-counting works from
  -- those statuses, and both were right — **but the invariant survives there for
  -- a different reason**, which the visible author measured: the ceiling applies
  -- on UPDATE too, so an un-counted refund can never be completed again, and at
  -- most one of the two ever reaches `completed`. The freeze protects money that
  -- has LEFT; `GL036`-on-update protects the rest.
  if tg_op = 'UPDATE'
     and old.status = 'completed'::public.refund_status
     and new.status is distinct from old.status then
    raise exception 'refund refused: this refund completed — % paise left the gym, and money that has gone does not become an attempt that never happened',
      old.amount_paise
      using errcode = 'GL041';
  end if;

  -- ---- Attribution, for sessions row security applies to -------------------
  --
  -- **The fifth appearance, and the first on money going OUT.** This file's own
  -- thesis in round one was that a manual payment has no provider to verify
  -- against, so attribution is the integrity — and the rule had four
  -- appearances on money coming in and none on the direction where a gym
  -- actually loses. The column was nullable, stamped by nothing, checked by
  -- nothing.
  if pg_catalog.row_security_active('public.refunds') then

    v_actor := app.current_staff_id();

    if tg_op = 'UPDATE' then
      if new.initiated_by_staff_id is distinct from old.initiated_by_staff_id then
        raise exception 'refund refused: who sent money back is a recorded fact and cannot be reassigned'
          using errcode = 'GL040';
      end if;
    else
      -- The null actor as its own clause (ADR-071): after `app.stamp_refund()`
      -- has filled the column from the same absent claim, both sides are null and
      -- the comparison alone is silent exactly there.
      if v_actor is null
         or new.initiated_by_staff_id is distinct from v_actor then
        raise exception 'refund refused: money leaving the gym names the staff member who sent it, and this session records % against an actor of %',
          new.initiated_by_staff_id, coalesce(v_actor::text, 'no staff identity')
          using errcode = 'GL040';
      end if;
    end if;

  end if;

  -- **Money only comes back out of money that came in — and this sits OUTSIDE
  -- the ceiling's `failed` carve-out.** A blind author put it there: the
  -- carve-out exists because a refund that itself failed took nothing, so it is
  -- neither summed nor bounded — that is a rule about HOW MUCH may go out.
  -- Whether the money ever came IN is a different question, and it has the same
  -- answer for a failed refund as for any other. Recording a failed attempt
  -- against a payment that never arrived is recording an attempt to return money
  -- the gym never had.
  --
  -- The three statuses are the ones the granting rule counts as money that
  -- ARRIVED, for the same reason it counts them: a refund does not un-arrive the
  -- money it returns.
  --
  -- A payment that cannot be read at all is left to the composite foreign key
  -- and the policy, not answered here (ADR-066) — hence the `exists` rather than
  -- a bare null test.
  if exists (select 1 from public.payments p
              where p.id = new.payment_id
                and p.tenant_id = new.tenant_id)
     and not exists (select 1 from public.payments p
                      where p.id = new.payment_id
                        and p.tenant_id = new.tenant_id
                        and p.status in ('paid'::public.payment_status,
                                         'refunded'::public.payment_status,
                                         'reversed'::public.payment_status)) then
    raise exception 'refund refused: that payment has not taken any money, so there is none to send back'
      using errcode = 'GL036';
  end if;

  -- ---- The ceiling, for every writer --------------------------------------
  --
  -- No carve-out: a provider-initiated refund arriving through the webhook as
  -- `service_role` is the path that will process refunds at scale, and a
  -- ceiling that path does not obey is not a ceiling (ADR-082).
  --
  -- **On update as well as insert**, which round one missed while quoting
  -- ADR-070 for a different rule three functions above. The ceiling passed at
  -- insert and the row was then edited past it: a Rs 1,000 payment carrying a
  -- Rs 1,00,000 refund.
  --
  -- A refund whose own status is `failed` took nothing, so it is neither summed
  -- NOR bounded. Round one excluded failed rows from the sum and then compared
  -- the new row regardless of its own status, so recording a failed retry
  -- against a fully refunded payment was impossible — the same rule
  -- disagreeing with itself, which a blind author found by reading it backward.
  if new.status <> 'failed'::public.refund_status then
    -- **Money only comes back out of money that came in.** This read
    -- `amount_paise` and never the payment's status, and `amount_paise` is not
    -- null on a `created` row — so a critic recorded a full `completed` refund
    -- against a payment that never arrived. Money out against money that never
    -- came in, and the payments screen already told the desk the database
    -- refused it: "a payment that is not paid has taken nothing … The database
    -- refuses both (`GL036`)". The second half was true and the first half was
    -- not, and the only thing enforcing it was the absence of a button.
    --
    -- The three statuses are the ones the granting rule counts as money that
    -- ARRIVED, for the same reason it counts them: a refund does not un-arrive
    -- the money it returns.
    select p.amount_paise into v_paid
      from public.payments p
     where p.id = new.payment_id
       and p.tenant_id = new.tenant_id
     for update;

    if v_paid is not null then
      select coalesce(sum(r.amount_paise), 0) into v_refunded
        from public.refunds r
       where r.payment_id = new.payment_id
         and r.tenant_id  = new.tenant_id
         and r.status <> 'failed'::public.refund_status
         and r.id <> new.id;

      if v_refunded + new.amount_paise > v_paid then
        raise exception 'refund refused: % paise already refunded against a payment of % paise, and this refund of % would exceed it',
          v_refunded, v_paid, new.amount_paise
          using errcode = 'GL036';
      end if;
    end if;
  end if;

  return null;
end;
$fn$;

drop trigger payments_identity_frozen on public.payments;
drop function app.enforce_payment_identity();
drop trigger payments_arrival_status on public.payments;
drop function app.enforce_payment_arrival_status();

-- A conflicting insert waits for the first transaction at the unique index.
-- The following statement in this volatile function gets a fresh snapshot and
-- can then compare the committed winner under the caller's own RLS.
create function public.record_refund(
  p_payment_id uuid,
  p_amount_paise bigint,
  p_currency text,
  p_kind public.refund_kind,
  p_reason text,
  p_idempotency_key uuid
)
returns table (refund_id uuid, replayed boolean)
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tenant uuid;
  v_staff uuid;
  v_id uuid;
  v_existing public.refunds%rowtype;
begin
  if not app.is_gym_admin() then
    raise exception 'A refund requires an owner or manager staff session' using errcode = '42501';
  end if;
  v_tenant := app.current_tenant_id();
  v_staff := app.current_staff_id();
  if v_tenant is null or v_staff is null then
    raise exception 'A refund requires a gym and real staff identity' using errcode = '42501';
  end if;
  if p_idempotency_key is null then
    raise exception 'A refund request requires a UUID key' using errcode = '22023';
  end if;

  insert into public.refunds (
    tenant_id, payment_id, amount_paise, currency, kind, reason,
    initiated_by_staff_id, status, idempotency_key
  ) values (
    v_tenant, p_payment_id, p_amount_paise, p_currency, p_kind, p_reason,
    v_staff, 'requested'::public.refund_status, p_idempotency_key::text
  )
  on conflict (tenant_id, idempotency_key) where idempotency_key is not null
    do nothing
  returning id into v_id;

  if v_id is not null then
    return query select v_id, false;
    return;
  end if;

  select r.* into v_existing from public.refunds r
   where r.tenant_id = v_tenant and r.idempotency_key = p_idempotency_key::text;
  if not found then
    raise exception 'The existing refund result could not be read' using errcode = 'P0002';
  end if;
  if v_existing.payment_id is not distinct from p_payment_id
     and v_existing.amount_paise is not distinct from p_amount_paise
     and v_existing.currency is not distinct from p_currency
     and v_existing.kind is not distinct from p_kind
     and v_existing.reason is not distinct from p_reason then
    return query select v_existing.id, true;
    return;
  end if;
  raise exception 'This request key already names different refund facts' using errcode = 'GL048';
end;
$fn$;

revoke all on function public.record_refund(uuid, bigint, text, public.refund_kind, text, uuid)
  from public, anon;
grant execute on function public.record_refund(uuid, bigint, text, public.refund_kind, text, uuid)
  to authenticated;

-- The caller cannot insert audit rows directly. This narrowly elevated trigger
-- only appends the frozen financial summary and has no user-callable path.
create function app.audit_money_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_columns text[];
  v_record_type text;
  v_before jsonb;
  v_after jsonb;
  v_actor uuid;
  v_role public.app_role;
  v_impersonation uuid;
begin
  if tg_table_name = 'payments' then
    v_record_type := 'payment';
    v_columns := array[
      'member_id', 'membership_id', 'mandate_id', 'coupon_id', 'amount_paise',
      'currency', 'status', 'method', 'provider', 'provider_order_id',
      'provider_payment_id', 'receipt_number', 'recorded_by_staff_id',
      'idempotency_key', 'paid_at', 'failed_reason', 'notes'
    ];
  elsif tg_table_name = 'refunds' then
    v_record_type := 'refund';
    v_columns := array[
      'payment_id', 'kind', 'amount_paise', 'currency', 'status',
      'provider_refund_id', 'reason', 'initiated_by_staff_id', 'processed_at',
      'idempotency_key'
    ];
  else
    raise exception 'Unsupported financial audit table';
  end if;

  select pg_catalog.jsonb_object_agg(j.key, j.value) into v_after
    from pg_catalog.jsonb_each(pg_catalog.to_jsonb(new)) j
   where j.key = any(v_columns);
  if tg_op = 'UPDATE' then
    select pg_catalog.jsonb_object_agg(j.key, j.value) into v_before
      from pg_catalog.jsonb_each(pg_catalog.to_jsonb(old)) j
     where j.key = any(v_columns);
  end if;

  -- A verified end-user subject is retained even when its role label cannot be
  -- resolved. No subject means an explicitly unattributed trusted write.
  v_actor := auth.uid();
  if v_actor is not null then
    select e.enumlabel::text::public.app_role into v_role
      from pg_catalog.pg_enum e
     where e.enumtypid = 'public.app_role'::pg_catalog.regtype
       and e.enumlabel = app.current_app_role();
    v_impersonation := app.current_impersonation_id();
  end if;

  insert into public.audit_log (
    tenant_id, actor_user_id, actor_role, impersonation_session_id,
    action, record_type, record_id, before, after, reason
  ) values (
    new.tenant_id, v_actor, v_role, v_impersonation,
    v_record_type || case when tg_op = 'INSERT' then '.created' else '.updated' end,
    v_record_type, new.id, v_before, v_after,
    case when v_record_type = 'refund' then v_after ->> 'reason' else null end
  );
  return null;
end;
$fn$;

revoke all on function app.audit_money_change() from public, anon, authenticated;

create trigger payments_money_audit
  after insert or update on public.payments
  for each row execute function app.audit_money_change();
create trigger refunds_money_audit
  after insert or update on public.refunds
  for each row execute function app.audit_money_change();
