-- Membership periods cost their agreed net price (OPEN-028, ADR-111).
-- Forward-only; CI applies this migration. Function bodies retain all prior
-- guards/order; only the divisor input and GL043 discount term are changed.
alter table public.memberships drop constraint memberships_discount_paise_chk;
alter table public.memberships add constraint memberships_discount_paise_chk
  check (discount_paise >= 0 and discount_paise <= price_paise);

create or replace function app.grant_periods(
  p_tenant_id     uuid,
  p_membership_id uuid,
  p_currency      text,
  p_added         bigint
)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tz       text;
  v_today    date;
  v_price    bigint;
  v_currency text;
  v_duration integer;
  v_starts   date;
  v_ends     date;
  v_granted  integer;
  v_status   public.membership_status;
  v_total    bigint;
  v_owed     integer;
  v_periods  integer;
begin
  -- `duration_days` now comes off the membership, not off `plans`. The join to
  -- `plans` is gone with it: nothing in this function reads the plan any more,
  -- which is the whole point — a plan edit cannot reach money already taken.
  select m.price_paise - m.discount_paise, m.currency, m.starts_on, m.ends_on, m.periods_granted, m.duration_days, m.status
    into v_price, v_currency, v_starts, v_ends, v_granted, v_duration, v_status
    from public.memberships m
   where m.id = p_membership_id
     and m.tenant_id = p_tenant_id
   for update of m;

  -- **A retired membership does not grow.** This function read a membership's
  -- price, currency, dates, count and length and never its status, so a payment
  -- naming a `cancelled` row extended it — silently, because the check-in gate
  -- reads status and refuses the member anyway. Measured on the exact sequence
  -- this phase prescribes as the repair for a mis-sold membership: refund,
  -- cancel, sell a new one, then name the retired one on the payment.
  -- `ends_on` went to the year 26667.
  --
  -- **The repair path is precisely when this is reachable**, because it is the
  -- moment a member has two memberships and one of them is retired.
  -- `POST /api/payments` takes any `membershipId` and `GL042` only checks the
  -- member matches.
  --
  -- The payment is still recorded and receipted — the money did change hands,
  -- and refusing after the fact would leave cash in a drawer with nothing to
  -- show for it. What stops is the growing. `pending` and `frozen` are NOT
  -- retired: a pending membership is extended and activated by its first
  -- payment, which is how a dateless one comes alive, and a frozen one is a
  -- paused live membership whose member is coming back.
  if v_status in ('cancelled'::public.membership_status,
                  'expired'::public.membership_status) then
    return;
  end if;

  if v_price is null or v_price = 0 or v_duration is null then
    return;
  end if;

  if p_currency is distinct from v_currency then
    return;
  end if;

  -- Money that ARRIVED, in the membership's own currency. **Both operands are
  -- `bigint`, so this truncates** — the whole of ADR-088.
  select coalesce(sum(pp.amount_paise), 0)
    into v_total
    from public.payments pp
   where pp.tenant_id     = p_tenant_id
     and pp.membership_id = p_membership_id
     and pp.currency      = v_currency
     and pp.status in ('paid'::public.payment_status,
                       'refunded'::public.payment_status,
                       'reversed'::public.payment_status);

  v_owed    := v_total / v_price;
  v_periods := v_owed - v_granted;

  if v_periods <= 0 then
    return;
  end if;

  select o.timezone into v_tz
    from public.organizations o
   where o.id = p_tenant_id;

  if v_tz is null then
    return;
  end if;

  v_today := (pg_catalog.now() at time zone v_tz)::date;

  if v_starts is null and v_ends is null then
    update public.memberships m
       set starts_on       = v_today,
           ends_on         = v_today + (v_duration * v_periods),
           periods_granted = v_owed,
           status          = case when m.status = 'pending'::public.membership_status
                                       and not exists (
                                         select 1 from public.memberships other
                                          where other.tenant_id = m.tenant_id
                                            and other.member_id = m.member_id
                                            and other.id <> m.id
                                            and other.status in ('active'::public.membership_status,
                                                                 'frozen'::public.membership_status))
                                  then 'active'::public.membership_status
                                  else m.status end,
           -- **The same condition as `status`, deliberately duplicated.** A
           -- membership left `pending` on purpose must not be stamped as
           -- activated; editing either of these alone is the same defect in
           -- opposite directions (ADR-089's round).
           activated_at    = case when m.status = 'pending'::public.membership_status
                                       and not exists (
                                         select 1 from public.memberships other
                                          where other.tenant_id = m.tenant_id
                                            and other.member_id = m.member_id
                                            and other.id <> m.id
                                            and other.status in ('active'::public.membership_status,
                                                                 'frozen'::public.membership_status))
                                  then coalesce(m.activated_at, pg_catalog.now())
                                  else m.activated_at end
     where m.id = p_membership_id
       and m.tenant_id = p_tenant_id;
  else
    update public.memberships m
       -- First grants buy exactly the recorded duration times the new periods.
       -- Preserve a future start; restart an unpaid elapsed span at gym-local today.
       -- Renewals and ends-only rows retain their previous behavior (OPEN-026).
       set starts_on       = case when v_granted = 0 and m.starts_on is not null
                                  then greatest(m.starts_on, v_today)
                                  else m.starts_on end,
           ends_on         = case when v_granted = 0 and m.starts_on is not null
                                  then greatest(m.starts_on, v_today)
                                  else greatest(m.ends_on, v_today)
                             end + (v_duration * v_periods),
           periods_granted = v_owed,
           status          = case when m.status = 'pending'::public.membership_status
                                       and m.starts_on is not null
                                       and not exists (
                                         select 1 from public.memberships other
                                          where other.tenant_id = m.tenant_id
                                            and other.member_id = m.member_id
                                            and other.id <> m.id
                                            and other.status in ('active'::public.membership_status,
                                                                 'frozen'::public.membership_status))
                                  then 'active'::public.membership_status
                                  else m.status end,
           activated_at    = case when m.status = 'pending'::public.membership_status
                                       and m.starts_on is not null
                                       and not exists (
                                         select 1 from public.memberships other
                                          where other.tenant_id = m.tenant_id
                                            and other.member_id = m.member_id
                                            and other.id <> m.id
                                            and other.status in ('active'::public.membership_status,
                                                                 'frozen'::public.membership_status))
                                  then coalesce(m.activated_at, pg_catalog.now())
                                  else m.activated_at end
     where m.id = p_membership_id
       and m.tenant_id = p_tenant_id
       and m.ends_on is not null;
  end if;
end;
$fn$;

create or replace function app.enforce_membership_terms_frozen()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_paid     boolean;
  v_price    bigint;
  v_currency text;
begin
  -- ---- Invariants about the data, for every writer including the seed -------
  --
  -- No carve-out: these are facts about what the money bought, and a trusted
  -- caller needs them MORE because no policy stands behind it (ADR-082).

  if tg_op = 'INSERT' then
    -- A membership is created having been granted nothing (ADR-089).
    if new.periods_granted <> 0 then
      raise exception 'membership refused: a membership is created having been granted nothing — periods are granted by the payments that buy them, not typed in at the desk'
        using errcode = 'GL044';
    end if;
  else
    -- **A membership belongs to the member it was sold to.** `GL042` is
    -- evaluated on the PAYMENT row, and `member_id` here was frozen by
    -- nothing — not this rule, whose column list is closed and excluded it, and
    -- not the stamp. A critic moved a membership carrying a granted period to
    -- another member from a FRONT-DESK session in one statement, while the paid
    -- payment still named the original member and carried their receipt number:
    -- verbatim the harm `GL042`'s own requirement names, reached by the
    -- least-privileged writer who can reach the table.
    --
    -- No trusted-context carve-out, on ADR-082's general form: the subject is
    -- which member a membership was sold to, and a webhook has as much of that
    -- as anybody. Only `GL046` in this trigger is a claim rule.
    --
    -- Correcting who a membership was sold to is not an edit — it is a refund, a
    -- cancellation and a new sale, which is the answer this phase gives for
    -- every other recorded fact.
    if new.member_id is distinct from old.member_id then
      raise exception 'membership refused: a membership belongs to the member it was sold to — the receipt names one person and the month would land on another; refund, cancel and sell a new one'
        using errcode = 'GL042';
    end if;

    -- How many periods have been granted is the granting rule's to write
    -- (ADR-089), and so are the dates it bought (ADR-093) — both at
    -- `pg_trigger_depth() >= 2`, where `app.grant_periods()`' own UPDATE runs
    -- and where no hand-written statement can reach.
    if new.periods_granted is distinct from old.periods_granted
       and pg_catalog.pg_trigger_depth() < 2 then
      raise exception 'membership refused: how many periods have been granted is recorded by the rule that grants them — it moves when a payment moves it, and % is not something the desk types',
        new.periods_granted
        using errcode = 'GL044';
    end if;

    if (new.starts_on is distinct from old.starts_on
        or new.ends_on is distinct from old.ends_on)
       and pg_catalog.pg_trigger_depth() < 2 then
      raise exception 'membership refused: when a membership runs from and until is what its payments bought — % to % is not something the desk types; take the money and the dates follow',
        new.starts_on, new.ends_on
        using errcode = 'GL045';
    end if;

    -- A period's length is derived, never typed (ADR-092).
    if new.duration_days is distinct from old.duration_days
       and new.plan_id is not distinct from old.plan_id then
      raise exception 'membership refused: how long a period is is what the plan says, not something the desk types — % days was written directly; change the plan instead',
        new.duration_days
        using errcode = 'GL043';
    end if;

    -- The terms money is scored against, frozen once any of it has arrived
    -- (ADR-090). **Checked before GL046** — it is an absolute, while GL046 is a
    -- permission, and answering the permission first would imply a gym admin
    -- could do this. It also matters mechanically: every existing GL043
    -- assertion is made by a front-desk session against a membership that has
    -- money, so GL046 answering first would mask the whole battery from the
    -- only role that exercises it.
    if new.price_paise is distinct from old.price_paise
       or new.discount_paise is distinct from old.discount_paise
       or new.currency  is distinct from old.currency
       or new.plan_id   is distinct from old.plan_id then

      select exists (
        select 1
          from public.payments pp
         where pp.tenant_id     = old.tenant_id
           and pp.membership_id = old.id
           and pp.status in ('paid'::public.payment_status,
                             'refunded'::public.payment_status,
                             'reversed'::public.payment_status)
      ) into v_paid;

      if v_paid then
        raise exception 'membership refused: money has already been taken against this membership at its current terms, and re-pricing, re-denominating or moving it to another plan would change what that money bought — refund and sell a new membership instead'
          using errcode = 'GL043';
      end if;
    end if;
  end if;

  -- ---- The claim rule, for sessions row security applies to -----------------
  --
  -- A trusted context has no staff role, which is exactly what this rule is
  -- about, so the carve-out is the sound kind (ADR-082). The seed writes prices
  -- and a discount with no claim at all.
  if not pg_catalog.row_security_active('public.memberships') then
    return null;
  end if;

  if app.is_gym_admin() then
    return null;
  end if;

  if tg_op = 'INSERT' then
    -- Creating at the plan's own price is the whole of what a front desk does.
    -- Anything else is a decision about what this member owes.
    select p.price_paise, p.currency
      into v_price, v_currency
      from public.plans p
     where p.id = new.plan_id
       and p.tenant_id = new.tenant_id;

    -- A plan that cannot be read is answered by the composite foreign key, not
    -- by this rule (ADR-066).
    if v_price is not null
       and (new.price_paise    is distinct from v_price
         or new.currency       is distinct from v_currency
         or coalesce(new.discount_paise, 0) <> 0
         or new.coupon_id      is not null) then
      raise exception 'membership refused: a membership is sold at its plan''s price — % paise against a plan priced at % is a decision about what this member owes, and that belongs to the gym''s owner or manager',
        new.price_paise, v_price
        using errcode = 'GL046';
    end if;

    return null;
  end if;

  if new.price_paise    is distinct from old.price_paise
     or new.currency       is distinct from old.currency
     or new.plan_id        is distinct from old.plan_id
     or new.discount_paise is distinct from old.discount_paise
     or new.coupon_id      is distinct from old.coupon_id then
    raise exception 'membership refused: what a member owes is the gym owner''s or manager''s to decide, the way a refund is — a front desk sells at the plan''s price and takes the money'
      using errcode = 'GL046';
  end if;

  return null;
end;
$fn$;

-- Reconcile the one inspected historical discounted year. Do not invoke the
-- current-day granting rule: this paid year already has its historical dates.
do $reconcile$
declare
  v_membership public.memberships%rowtype;
  v_total bigint;
begin
  if exists (select 1 from public.memberships
              where discount_paise <> 0
                and id <> '00000006-0000-4000-8000-000000000004'::uuid) then
    raise exception 'Uninspected discounted membership history; reconcile before applying net pricing';
  end if;
  select * into v_membership from public.memberships
   where id = '00000006-0000-4000-8000-000000000004'::uuid for update;
  if not found then return; end if;
  select coalesce(sum(amount_paise), 0) into v_total from public.payments
   where tenant_id=v_membership.tenant_id and membership_id=v_membership.id
     and currency=v_membership.currency and status in ('paid','refunded','reversed');
  if v_membership.tenant_id <> '00000001-0000-4000-8000-000000000001'::uuid
     or v_membership.member_id <> '00000005-0000-4000-8000-000000000004'::uuid
     or v_membership.currency <> 'INR' or v_membership.price_paise <> 1200000
     or v_membership.discount_paise <> 120000 or v_membership.duration_days <> 365
     or v_membership.starts_on is distinct from date '2025-09-12'
     or v_membership.ends_on is distinct from date '2026-09-12'
     or v_membership.status <> 'active' or v_membership.periods_granted not in (0,1)
     or v_total <> 1080000 then
    raise exception 'Discounted demo history changed; reconcile before applying net pricing';
  end if;
  if v_membership.periods_granted = 0 then
    alter table public.memberships disable trigger memberships_terms_frozen;
    update public.memberships set periods_granted=1
     where id=v_membership.id and tenant_id=v_membership.tenant_id;
    alter table public.memberships enable trigger memberships_terms_frozen;
  end if;
end;
$reconcile$;
