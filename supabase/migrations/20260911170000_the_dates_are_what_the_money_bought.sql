-- the_dates_are_what_the_money_bought
--
-- Nine rounds governed what a period costs (`GL043`), how long it is (the
-- derived length), and how many have been granted (`GL044`). **All of it
-- computes a date that anyone could simply type.** Measured from an ordinary
-- front-desk session, with no privilege beyond recording a payment:
--
--     update public.memberships set ends_on   = starts_on + 3650 where id = …;
--     update public.memberships set starts_on = starts_on - 3650 where id = …;
--
-- Both ALLOWED. Ten years, one statement, no refusal, no receipt, nothing
-- raised. **The whole `GL043` family protects the inputs to an arithmetic whose
-- output was writable by hand the entire time.**
--
-- And `starts_on` is not only a ledger concern: `app.enforce_check_in()` judges
-- liveness from these dates (ADR-084), so pulling `starts_on` backwards is a day
-- at the turnstile as well as a month on the books.
--
-- **Why it went unexamined for two rounds is the part worth keeping.** ADR-092
-- ranked this door below `duration_days` on the grounds that a hand-written
-- `ends_on` leaves a trace — `ends_on - starts_on` disagreeing with
-- `duration_days × periods_granted`. That premise was mine and it was false: the
-- invariant already fails for **17 of 46** dated memberships on the demo gym
-- before any fraud, because the number behind it had been borrowed from a
-- different audit (`periods_granted = floor(money / price)`, which does hold at
-- zero). A 37% false-positive rate is not a detector. **A wrong reason for a
-- priority is worse than no reason, because it stops the question being asked
-- again** — and ADR-084's rule then applies: a decision defended by a premise
-- that turns out false has to be re-decided.
--
-- So the dates join `periods_granted` under the rule that already works for it
-- (ADR-089): they may change only at `pg_trigger_depth() >= 2`, which is where
-- `app.grant_periods()`' own UPDATE runs and where no hand-written statement can
-- reach. Depth cannot be forged from a top-level statement.
--
-- **`is distinct from`, so a date written back unchanged is allowed.** The
-- requirement above settles this for `periods_granted` in as many words — a rule
-- that refuses a write which cannot do harm buys nothing and breaks ordinary
-- column-listing updates — and a blind author caught the first draft of the new
-- requirement contradicting its own sibling on exactly that edge.
--
-- **What this does not close**, both measured by blind authors and recorded
-- rather than left for a critic to find:
--
--   * **OPEN-029.** Creation is unpoliced: one INSERT of an `active` membership
--     dated `today … today + 3650` with no payment anywhere is allowed, and
--     there is no UPDATE for this rule to refuse. Closing it means "a membership
--     is created with no span it has not been paid for", which `supabase/seed.sql`
--     and fixtures in both suites contradict — a contract change, and contract
--     changes made in the same breath as a fix produced two of the last three
--     rounds. It also leaves a whole membership row as evidence, which the
--     UPDATE route did not.
--   * **OPEN-027.** A gym admin may re-length a plan, point a membership at it
--     and back, and restore the plan, keeping a length no plan now carries.
--   * A `pending` membership with `starts_on` set and a null `ends_on` can no
--     longer acquire an end date by any route. Same malformed shape as OPEN-026,
--     and it belongs with it.
--
-- `after`, so it cannot answer ahead of the policy that would have refused the
-- row anyway (ADR-066); it modifies nothing, so nothing needs it early
-- (ADR-072).

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
  -- `pg_trigger_depth() >= 2` where its own UPDATE runs (ADR-089).
  if new.periods_granted is distinct from old.periods_granted
     and pg_catalog.pg_trigger_depth() < 2 then
    raise exception 'membership refused: how many periods have been granted is recorded by the rule that grants them — it moves when a payment moves it, and % is not something the desk types',
      new.periods_granted
      using errcode = 'GL044';
  end if;

  -- **The dates are what the money bought** (ADR-093), by the same depth test
  -- and for the same reason. Checked before the terms below, because those
  -- protect the arithmetic and this protects its result: a rule that guards the
  -- inputs while the output stays writable guards nothing.
  -- **Filling a null date is a change like any other**, and it is refused.
  --
  -- I briefly exempted it, because a holdout assertion from an earlier round
  -- asserts that giving a half-dated `pending` row its missing date must work —
  -- OPEN-026's only repair. Both round-ten authors, blind to each other,
  -- asserted the opposite, and they were writing to this requirement, which
  -- accepts the cost in as many words. **The exemption would have been the
  -- contract losing to the first assertion that disagreed with it**, which is
  -- how a rule acquires an edge nobody decided. The older assertion belongs to
  -- the contract as it stood before this round and its author is updating it.
  --
  -- What that costs is real and is recorded rather than argued away: four
  -- malformed shapes — a `pending` row missing either date, a zero-price
  -- membership, and a currency-mismatched one — can no longer be repaired in
  -- place. Nothing in the product creates them, and repairing them needs a
  -- product flow rather than a desk typing into the money path.
  if (new.starts_on is distinct from old.starts_on
      or new.ends_on is distinct from old.ends_on)
     and pg_catalog.pg_trigger_depth() < 2 then
    raise exception 'membership refused: when a membership runs from and until is what its payments bought — % to % is not something the desk types; take the money and the dates follow',
      new.starts_on, new.ends_on
      using errcode = 'GL045';
  end if;

  -- A period's length is derived, never typed (ADR-092).
  -- `app.stamp_membership()` has already replaced it with the plan's length on
  -- any statement that changed the plan, so anything still different here was
  -- written by hand.
  if new.duration_days is distinct from old.duration_days
     and new.plan_id is not distinct from old.plan_id then
    raise exception 'membership refused: how long a period is is what the plan says, not something the desk types — % days was written directly; change the plan instead',
      new.duration_days
      using errcode = 'GL043';
  end if;

  -- The terms money is scored against (ADR-090). Evaluated only when one of them
  -- actually changes, so the `exists` costs nothing on an ordinary edit.
  if new.price_paise is distinct from old.price_paise
     or new.currency  is distinct from old.currency
     or new.plan_id   is distinct from old.plan_id then

    -- Money that ARRIVED, counted exactly as the granting rule counts it, and in
    -- ANY currency — re-denominating is precisely what would make foreign money
    -- start scoring. A refunded payment still counts: a refund does not reverse
    -- the extension it bought, and thawing on refund would sell the re-pricing
    -- door for the price of a refund and a re-payment.
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
