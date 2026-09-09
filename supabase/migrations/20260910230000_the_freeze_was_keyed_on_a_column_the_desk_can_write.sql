-- the_freeze_was_keyed_on_a_column_the_desk_can_write
--
-- Round six froze a membership's `price_paise` and `currency` once
-- `periods_granted > 0` (`GL043`). A round-six critic took the same exploit
-- through four other doors, one ordinary front-desk statement each, and every
-- one of them worked. ADR-089.
--
--   * `plan_id` was never frozen. A period's LENGTH is `plans.duration_days`,
--     read fresh on every payment, so repointing a 30-day membership at a
--     365-day plan and paying one further ₹1,000 moved `ends_on` **395 days**.
--     Three inputs decide what money buys — price, currency, and the plan whose
--     duration measures a period — and round six froze two of them.
--
--   * The gate on the freeze is itself front-desk writable. `old.periods_granted
--     > 0` is the whole condition and `check (periods_granted >= 0)` permits
--     `0`. `set periods_granted = 0`, then cut the price, then pay **one
--     paisa**: 75 days for ₹1,000.01. The one-statement form is correctly
--     refused — the trigger does read `old` — so the freeze is not wrong, it is
--     **gated on a value the attacker chooses**.
--
--   * No price edit is needed at all: `set periods_granted = 0` and a 1-paisa
--     payment is thirty days of gym for ₹0.01.
--
--   * Set it upward and it silently eats a real payment. `set periods_granted =
--     500`, then an ordinary ₹1,000: money receipted, `ends_on` unmoved, zero
--     days granted, no error anywhere. **That is ADR-088's own named harm** —
--     "she pays ₹12,000 for zero days, silently" — reached by hand instead of by
--     rounding, one round after it was declared closed.
--
-- **A freeze is worth exactly as much as the immutability of the thing it is
-- keyed on.** Round six keyed a rule about recorded facts to a column the front
-- desk rewrites at will, which is ADR-087's mistake in another costume: trusting
-- a value chosen by the party the rule constrains.
--
-- So `periods_granted` is written by the granting rule and by nothing else
-- (`GL044`), and with that true, `old.periods_granted > 0` finally means what it
-- says and `plan_id` joins the other two terms under `GL043`.
--
-- **How "by the rule and by nothing else" is decided: trigger depth.**
-- `app.grant_periods()` is reached only from the statement trigger on
-- `payments`, so its UPDATE on `memberships` fires this trigger at
-- `pg_trigger_depth() = 2`. Every hand-written `update memberships` fires it at
-- `1`. Depth cannot be forged from a top-level statement, unlike a session GUC —
-- which the very session being constrained could set, and which is why this is
-- not a `current_setting()` flag. Calling `app.grant_periods()` directly from
-- SQL lands at depth 1 and is refused, which is correct: it is a trigger's
-- helper, not an API.
--
-- **No carve-out for trusted callers**, on ADR-082's general form: a carve-out is
-- sound exactly when the rule's subject is something a trusted caller
-- legitimately lacks, and the subject here is an invariant about the data, which
-- a trusted caller needs MORE because no policy stands behind it. A future
-- migration that must correct this column — as ADR-088's backfill did — is a
-- deliberate act and says so, by disabling this trigger for the length of that
-- one statement. It does not get to happen by accident.
--
-- `after`, not `before`, so no rule here can answer ahead of the policy that
-- would have refused the row anyway (ADR-066, violated three times in this
-- phase). All three modify nothing, so nothing needs them early (ADR-072). The
-- INSERT rule matters most for this: `memberships_tenant_write`'s `with check`
-- is what should answer a session writing into a gym that is not theirs, and a
-- trigger raising `GL044` first would name a column instead of a permission.

drop trigger if exists memberships_price_frozen on public.memberships;
drop function if exists app.enforce_membership_price_frozen();


create or replace function app.enforce_membership_terms_frozen()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  -- A membership is created having been granted nothing.
  --
  -- Everything this migration was designed against is update-shaped, and so was
  -- the first draft of the rule. A holdout author measured the other way in: a
  -- front-desk session CREATES a membership carrying `periods_granted = 5`,
  -- then takes ₹1,000 — `ends_on` unmoved, receipt issued, no error. The third
  -- exploit above, with no UPDATE anywhere in it.
  --
  -- No depth test here: the granting rule only ever updates, so there is no
  -- legitimate insert of a non-zero count to let through. The console's create
  -- path does not write this column and neither does the seed.
  if tg_op = 'INSERT' then
    if new.periods_granted <> 0 then
      raise exception 'membership refused: a membership is created having been granted nothing — periods are granted by the payments that buy them, not typed in at the desk'
        using errcode = 'GL044';
    end if;
    return null;
  end if;

  -- How many periods have been granted is the granting rule's to write.
  --
  -- Checked FIRST and unconditionally, because it is what makes the freeze
  -- below trustworthy: gating the terms on a count anyone can retype is the
  -- defect this migration exists to close, not a rule that can be checked after
  -- it.
  if new.periods_granted is distinct from old.periods_granted
     and pg_catalog.pg_trigger_depth() < 2 then
    raise exception 'membership refused: how many periods have been granted is recorded by the rule that grants them — it moves when a payment moves it, and % is not something the desk types',
      new.periods_granted
      using errcode = 'GL044';
  end if;

  if old.periods_granted > 0 then
    -- The price. Every payment re-scores ALL the money on record against it, so
    -- a cut retroactively makes past payments buy more and the next payment of
    -- any size at all releases it — and it compounds: halving a price against
    -- which four periods' worth of money has arrived is four periods, not one.
    if new.price_paise is distinct from old.price_paise then
      raise exception 'membership refused: % periods have already been granted against a price of % paise, and re-pricing them would hand back or take away months that were paid for — refund and sell a new membership instead',
        old.periods_granted, old.price_paise
        using errcode = 'GL043';
    end if;

    -- The currency is half of what a price MEANS (MNY-002), and the rule sums
    -- money in the membership's own currency. Changing it re-scores every
    -- payment against a different set of rows.
    if new.currency is distinct from old.currency then
      raise exception 'membership refused: its price is in % and % periods have been granted against it',
        old.currency, old.periods_granted
        using errcode = 'GL043';
    end if;

    -- The plan, because a period's LENGTH is `plans.duration_days` and it is
    -- read fresh on every payment. This is the door round six left open, and it
    -- was the widest of the four: one statement, nothing else touched.
    if new.plan_id is distinct from old.plan_id then
      raise exception 'membership refused: % periods have already been granted at this membership''s plan length, and moving it to another plan would re-measure months that were paid for',
        old.periods_granted
        using errcode = 'GL043';
    end if;
  end if;

  return null;
end;
$fn$;

drop trigger if exists memberships_terms_frozen on public.memberships;

create trigger memberships_terms_frozen
  after insert or update on public.memberships
  for each row execute function app.enforce_membership_terms_frozen();
