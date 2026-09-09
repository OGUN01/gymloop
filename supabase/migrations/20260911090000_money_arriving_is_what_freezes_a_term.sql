-- money_arriving_is_what_freezes_a_term
--
-- Round seven made `periods_granted` unforgeable so that `old.periods_granted >
-- 0` could be trusted as the gate on a membership's terms. **It never asked
-- whether the gate says the right thing, and it does not** — ADR-090.
--
-- A membership that has taken real money but has not yet crossed one whole
-- multiple of its price sits at `periods_granted = 0`, and every one of its
-- terms is open. That is not a contrived state. It is a **part payment**,
-- ordinary practice in an Indian gym, and the console renders it as product
-- copy: "A full ₹X buys one period; part of it is recorded and receipted and
-- buys none until the balance is paid."
--
-- Measured by a critic against a REAL ROW of the live demo gym — Sneha Joshi's
-- Annual, ADR-088's own worked example, ₹10,800 arrived against a ₹12,000 price:
--
--     update memberships set price_paise = 100000 where id = …;  -- ALLOWED
--     insert into payments … values (1, 'cash', 'paid', …);      -- one paisa
--
--     before | ends_on=2026-09-12  price=1200000  periods_granted=0
--     after  | ends_on=2036-09-09                 periods_granted=10
--
-- **Ten years of an Annual membership for one paisa.** No error, no audit trail.
-- The plan and the currency were equally open in that window: a member who
-- agreed to ₹1,000 for a month and paid it in two halves could be given a year,
-- with two ordinary ₹500 receipts in the ledger.
--
-- The gate is wrong because "granted" is not when scoring starts. `v_total`
-- counts every paisa that has ARRIVED, crossed a multiple or not, so the money
-- is scored against the terms from the first payment — and that is the moment to
-- freeze them.
--
-- **The spec said so and the scenario did not.** ADR-089's requirement read
-- "correcting a mistyped price or a wrong plan BEFORE ANY MONEY HAS ARRIVED
-- stays free", while its scenario three lines below said "a membership that has
-- been granted nothing". The implementation was built to the scenario, so the
-- gate looked correct against its own test and **both blind suites asserted the
-- weaker sentence and went green**. A requirement that contradicts itself
-- defeats the blind arrangement, because nothing in the loop compares a
-- requirement to itself.
--
-- ---------------------------------------------------------------------------
-- The second half: a period's LENGTH was still read live from `plans`.
-- ---------------------------------------------------------------------------
--
-- `plan_id` was frozen; `plans.duration_days` was not, and `plans_tenant_write`
-- is `FOR ALL` on `is_gym_admin()`. One manager statement setting
-- `duration_days = 3650`, then one ordinary ₹1,000 renewal, moved `ends_on`
-- **3650 days** — and it does that to EVERY membership on that plan, silently,
-- whenever a gym legitimately edits it.
--
-- **The membership already records the price and the currency it was sold at.
-- The duration was the one term still read from somewhere else, and that
-- asymmetry is the defect.** So it is recorded too: filled from the plan by a
-- `before insert` trigger (ADR-072 — filling belongs early, refusing does not),
-- and frozen with the other three. Editing a plan now changes what the NEXT
-- membership is sold at and nothing about one already sold, which is what
-- editing a plan should mean.
--
-- Rejected: freezing `plans.duration_days` while any membership references the
-- plan. It punishes the legitimate act to prevent the illegitimate one, and
-- leaves the identical defect for `plans.price_paise` the day anything scores
-- against it.

-- ---------------------------------------------------------------------------
-- 1. The duration a period is measured in, recorded on the membership.
-- ---------------------------------------------------------------------------

alter table public.memberships
  add column if not exists duration_days integer;

comment on column public.memberships.duration_days is
  'How long one period of this membership is, in days, as sold. Recorded rather '
  'than read from plans.duration_days when money arrives: a plan may be '
  're-lengthened for future sales, and doing so must not re-measure months '
  'already paid for (ADR-090).';

-- Backfill from the plan each membership was sold on. This is the best
-- available truth for rows created before the column existed, and it is exactly
-- what the rule read a moment ago, so no membership changes length here.
update public.memberships m
   set duration_days = p.duration_days
  from public.plans p
 where p.id = m.plan_id
   and p.tenant_id = m.tenant_id
   and m.duration_days is null;

create or replace function app.stamp_membership()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_duration integer;
begin
  -- **Taken from the plan, not accepted from the caller.** The first draft of
  -- this filled the column only `if new.duration_days is null`, and a blind
  -- holdout author measured what that leaves open: a front-desk session CREATES
  -- a membership naming `duration_days = 3650`, pays the ordinary price, and
  -- gets ten years. Recording a term does nothing if the desk gets to type it —
  -- the identical door a holdout author found on `periods_granted` one round
  -- ago, in the identical place. A term is what the plan says at the moment of
  -- sale; there is no legitimate caller that knows better.
  --
  -- Filled and never refused, so this may run `before` (ADR-072). When the plan
  -- cannot be read — another gym's, or none — the row is left exactly as it
  -- came so the composite foreign key answers it, rather than this trigger
  -- turning a foreign-key violation into a not-null one (ADR-066).
  -- On UPDATE the recorded length follows the plan ONLY when the plan itself
  -- changes. Two things fall out of that, and both were measured:
  --
  --   * Correcting a membership's plan before any money has arrived must carry
  --     the length with it. A blind author asserted the permitted side — "the
  --     corrected terms are what the money is scored against" — and caught this
  --     version granting one period of the OLD plan's length after the plan had
  --     been corrected to a 365-day one. Recording a term is not enough; it has
  --     to be recorded from the right place at the right moment.
  --
  --   * Re-deriving on every update instead would refuse ordinary edits. A gym
  --     legitimately re-lengthens a plan for future sales; every membership
  --     already sold on it would then have its recorded length rewritten by the
  --     next unrelated edit, and `GL043` would refuse that edit — a false
  --     refusal on a row nobody was attacking.
  --
  --   * A length the caller corrects EXPLICITLY is left alone, and judged by
  --     `GL043` like any other term. At creation the plan defines the length
  --     and a caller-supplied one is ignored; afterwards, correcting it is the
  --     same act as correcting the price, free until money arrives and refused
  --     once it has. Carrying the old value forward instead — an earlier draft
  --     of this — made a hand-edited length silently vanish rather than be
  --     refused, which is the "shipped a silent no-op" failure this codebase
  --     asserts against; both suites caught it in the same run, from opposite
  --     directions.
  if tg_op = 'UPDATE' then
    if new.duration_days is distinct from old.duration_days
       or new.plan_id is not distinct from old.plan_id then
      return new;
    end if;
  end if;

  select p.duration_days
    into v_duration
    from public.plans p
   where p.id = new.plan_id
     and p.tenant_id = new.tenant_id;

  if v_duration is not null then
    new.duration_days := v_duration;
  end if;

  return new;
end;
$fn$;

drop trigger if exists memberships_stamp on public.memberships;

create trigger memberships_stamp
  before insert or update on public.memberships
  for each row execute function app.stamp_membership();

alter table public.memberships
  alter column duration_days set not null;

alter table public.memberships
  drop constraint if exists memberships_duration_days_chk;

alter table public.memberships
  add constraint memberships_duration_days_chk check (duration_days > 0);


-- ---------------------------------------------------------------------------
-- 2. The rule measures a period by what the membership was sold at.
-- ---------------------------------------------------------------------------

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
  v_total    bigint;
  v_owed     integer;
  v_periods  integer;
begin
  -- `duration_days` now comes off the membership, not off `plans`. The join to
  -- `plans` is gone with it: nothing in this function reads the plan any more,
  -- which is the whole point — a plan edit cannot reach money already taken.
  select m.price_paise, m.currency, m.starts_on, m.ends_on, m.periods_granted, m.duration_days
    into v_price, v_currency, v_starts, v_ends, v_granted, v_duration
    from public.memberships m
   where m.id = p_membership_id
     and m.tenant_id = p_tenant_id
   for update of m;

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
       set ends_on         = greatest(m.ends_on, v_today) + (v_duration * v_periods),
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


-- ---------------------------------------------------------------------------
-- 3. Money arriving is what freezes a term.
-- ---------------------------------------------------------------------------

create or replace function app.enforce_membership_terms_frozen()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_paid boolean;
begin
  -- A membership is created having been granted nothing (ADR-089).
  if tg_op = 'INSERT' then
    if new.periods_granted <> 0 then
      raise exception 'membership refused: a membership is created having been granted nothing — periods are granted by the payments that buy them, not typed in at the desk'
        using errcode = 'GL044';
    end if;
    return null;
  end if;

  -- How many periods have been granted is the granting rule's to write, at
  -- `pg_trigger_depth() >= 2` where its own UPDATE runs. Depth cannot be forged
  -- from a top-level statement, unlike a session GUC (ADR-089).
  if new.periods_granted is distinct from old.periods_granted
     and pg_catalog.pg_trigger_depth() < 2 then
    raise exception 'membership refused: how many periods have been granted is recorded by the rule that grants them — it moves when a payment moves it, and % is not something the desk types',
      new.periods_granted
      using errcode = 'GL044';
  end if;

  -- The terms. Evaluated only when one of them actually changes, so the
  -- `exists` costs nothing on an ordinary edit.
  if new.price_paise   is distinct from old.price_paise
     or new.currency      is distinct from old.currency
     or new.plan_id       is distinct from old.plan_id
     or new.duration_days is distinct from old.duration_days then

    -- **Money that ARRIVED, counted exactly as the granting rule counts it** —
    -- `paid`, `refunded`, `reversed` — and in ANY currency, which the rule does
    -- not do. That difference is deliberate: money in a currency the membership
    -- is not priced in buys nothing *today*, and re-denominating the membership
    -- is precisely what would make it buy something. A freeze that ignored it
    -- would leave the currency door open on exactly the rows where changing the
    -- currency pays.
    --
    -- A refunded payment still counts, here as in the rule. A refund does not
    -- reverse the extension it bought, so the money it represents is still
    -- scored — and thawing the terms on refund would hand back the re-pricing
    -- door for the cost of a refund and a re-payment.
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
      raise exception 'membership refused: money has already been taken against this membership at its current terms, and re-pricing, re-denominating or re-lengthening it would change what that money bought — refund and sell a new membership instead'
        using errcode = 'GL043';
    end if;
  end if;

  return null;
end;
$fn$;


-- ---------------------------------------------------------------------------
-- 4. A payment does not arrive already refunded.
-- ---------------------------------------------------------------------------
--
-- `app.extend_membership_on_payment()` acts only on `paid`, while
-- `app.grant_periods()` sums `paid`, `refunded` and `reversed`. A payment
-- INSERTED straight at `refunded` therefore counts toward the total, extends
-- nothing at the time, and takes no receipt number — measured: a ₹3,000
-- `refunded` payment inserted directly moved nothing, and then **one paisa**
-- granted three periods. Grant credit sitting on the books that no receipt
-- names, waiting for any later payment to cash it in.
--
-- Both statuses presuppose an earlier one: `app.payment_transition_allowed()`
-- already refuses reaching them from anywhere but `paid` on UPDATE, and the
-- INSERT was the way in around it. A payment is recorded and then refunded.
--
-- Its own trigger rather than a branch inside `app.enforce_payment()`: it is a
-- distinct requirement, and re-emitting a hundred-line function by hand to add
-- four lines is how this phase has introduced defects before. `after`, because
-- it modifies nothing and must not answer ahead of the policy (ADR-066,
-- ADR-072).

create or replace function app.enforce_payment_arrival_status()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if new.status in ('refunded'::public.payment_status,
                    'reversed'::public.payment_status) then
    raise exception 'payment refused: a payment is recorded and then refunded — it does not arrive already %',
      new.status
      using errcode = 'GL039';
  end if;

  return null;
end;
$fn$;

drop trigger if exists payments_arrival_status on public.payments;

create trigger payments_arrival_status
  after insert on public.payments
  for each row execute function app.enforce_payment_arrival_status();
