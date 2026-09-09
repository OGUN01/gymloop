-- a_length_is_derived_not_typed
--
-- ADR-090 recorded that a requirement contradicting itself defeats the blind
-- arrangement. **The requirement written to record that lesson did it again, in
-- the same paragraph.** It named the harm — "create a membership naming
-- `duration_days = 3650`, pay the ordinary price, get ten years" — and three
-- lines later mandated the identical outcome by another route:
--
--     #### Scenario: Correcting the length before any money arrives
--     THEN it SHALL be allowed and SHALL land, and a payment SHALL be scored
--     against the corrected length.
--
-- Measured by a critic: sell a 30-day membership at ₹1,500, then
--
--     update public.memberships set duration_days = 3650 where id = …;
--     insert into public.payments … values (…, 150000, 'cash', 'paid', …);
--
--     duration_days=3650  periods_granted=1  ends_on = starts_on + 3650
--
-- **3,650 days for one month's fee**, from one `.update({duration_days})` in any
-- front-desk browser session — `authenticated` holds UPDATE on `memberships`
-- with no column restriction. Also reproduced through `MERGE` and
-- `UPDATE … FROM`.
--
-- **And unlike every other exploit in this phase, it leaves nothing to find.** A
-- desk can already push `ends_on` directly, but that leaves `ends_on -
-- starts_on` disagreeing with `duration_days × periods_granted`. This route
-- leaves a perfectly consistent record: one ₹1,500 receipt, one period granted,
-- `ends_on` exactly one recorded period, and `periods_granted =
-- floor(money / price)` holding. An audit over all 47 demo memberships finds
-- zero disagreements — and a row built this way would also find zero, because a
-- membership whose length differs from its plan's is *by design* legitimate
-- after a plan has been re-lengthened. **It launders a hand-edit into an
-- apparently-verified grant.**
--
-- Both blind suites certified it, because the scenario told them to. The
-- authors were not wrong; the contract was.
--
-- The resolution is the previous migration's own sentence, applied where it was
-- already true: *"a term is what the plan says at the moment of sale; there is
-- no legitimate caller that knows better."* If that holds at INSERT it holds at
-- UPDATE. **`price_paise` is a negotiated number a desk legitimately mistypes;
-- `duration_days` is not.** A wrong length is a wrong plan, and the instrument
-- for that is changing the plan — which carries the length with it. The
-- permitted door was all attack surface and no use.
--
-- So the length may change only as part of a plan change, and only to what that
-- plan says, at any time and whatever the money. **Refused, not ignored** —
-- silently discarding a write is the failure this codebase asserts against, and
-- the round-eight draft that carried the old value forward was caught by both
-- suites for exactly that.
--
-- ---------------------------------------------------------------------------
-- The second half: a plan correction carried the length and not the price.
-- ---------------------------------------------------------------------------
--
-- `app.stamp_membership()` re-derived `duration_days` from the new plan and
-- nothing re-derived `price_paise`, which `POST /api/memberships` had copied
-- from the ORIGINAL plan. Correct a mis-sold Monthly to an Annual, take one
-- ₹12,000 Annual fee: the price is still ₹1,500, so `floor(1200000 / 150000)`
-- is **eight periods of 365 days — 2,920 days** for one year's money.
--
-- It predates round eight, which rewrote that branch and preserved it, and the
-- spec's scenario for the case would have passed with the rule deleted
-- (ADR-078): it asserted only that the correction was *allowed*, never what the
-- following payment bought. Every permitted-side assertion in both suites
-- corrects price and plan TOGETHER — the plan-only correction, which is what a
-- desk actually does when it has sold the wrong plan, was tested nowhere.
--
-- Price and length now come from the same plan or from neither, unless the
-- correction names a price of its own, which is how a negotiated price stays
-- possible.
--
-- **The currency travels with the price**, because it is half of what a price
-- MEANS (MNY-002) and the granting rule sums money in the membership's own
-- currency: taking a plan's price without its currency would score the new
-- number against the old denomination. Naming a price keeps both.

create or replace function app.stamp_membership()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_duration integer;
  v_price    bigint;
  v_currency text;
begin
  -- At creation the plan decides the length, whatever the caller said. The
  -- price is NOT forced here: a desk legitimately sells at a discount or a
  -- negotiated number, and `POST /api/memberships` sets it deliberately.
  if tg_op = 'INSERT' then
    select p.duration_days into v_duration
      from public.plans p
     where p.id = new.plan_id
       and p.tenant_id = new.tenant_id;

    -- A plan that cannot be read leaves the row exactly as it came, so the
    -- composite foreign key answers it rather than this trigger turning a
    -- foreign-key violation into something about a column the caller never
    -- named (ADR-066).
    if v_duration is not null then
      new.duration_days := v_duration;
    end if;

    return new;
  end if;

  -- On UPDATE the length follows the plan, and ONLY the plan. A length written
  -- any other way is left exactly as the caller wrote it so that
  -- `app.enforce_membership_terms_frozen()` can REFUSE it — putting the old
  -- value back here would make the write vanish silently, which is the failure
  -- both suites caught in round eight.
  if new.plan_id is distinct from old.plan_id then
    select p.duration_days, p.price_paise, p.currency
      into v_duration, v_price, v_currency
      from public.plans p
     where p.id = new.plan_id
       and p.tenant_id = new.tenant_id;

    if v_duration is not null then
      new.duration_days := v_duration;

      -- The price and its currency follow the plan too, unless this same
      -- statement names one — which is what a negotiated correction looks like.
      -- Leaving them behind is the 2,920-day defect: a membership pointing at an
      -- Annual plan while priced as a Monthly turns one year's money into eight.
      if new.price_paise is not distinct from old.price_paise
         and new.currency is not distinct from old.currency then
        new.price_paise := v_price;
        new.currency    := v_currency;
      end if;
    end if;
  end if;

  return new;
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

  -- **A period's length is derived, never typed** (ADR-092). It is frozen harder
  -- than the terms below and by a different question: not "has money arrived"
  -- but "did the plan change". `app.stamp_membership()` has already replaced it
  -- with the plan's length on any statement that changed the plan, so anything
  -- still different here was written by hand.
  if new.duration_days is distinct from old.duration_days
     and new.plan_id is not distinct from old.plan_id then
    raise exception 'membership refused: how long a period is is what the plan says, not something the desk types — % days was written directly; change the plan instead',
      new.duration_days
      using errcode = 'GL043';
  end if;

  -- The terms money is scored against. Evaluated only when one of them actually
  -- changes, so the `exists` costs nothing on an ordinary edit.
  if new.price_paise is distinct from old.price_paise
     or new.currency  is distinct from old.currency
     or new.plan_id   is distinct from old.plan_id then

    -- Money that ARRIVED, counted exactly as the granting rule counts it —
    -- `paid`, `refunded`, `reversed` — and in ANY currency, which the rule does
    -- not do. That difference is deliberate: money in a currency the membership
    -- is not priced in buys nothing today, and re-denominating the membership is
    -- precisely what would make it buy something.
    --
    -- A refunded payment still counts, here as in the rule: a refund does not
    -- reverse the extension it bought, and thawing the terms on refund would
    -- sell the re-pricing door for the price of a refund and a re-payment.
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

  return null;
end;
$fn$;
