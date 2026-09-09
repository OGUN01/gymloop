-- what_a_member_owes_is_gym_admin_work
--
-- `ends_on = duration_days * floor(money / price_paise)`. Round nine made
-- `duration_days` underivable by hand because it multiplies that product.
-- **`price_paise` is the other factor and it stayed freely typed.** Measured by
-- a critic, two ordinary `front_desk` statements, no privilege beyond selling
-- and taking money:
--
--     update public.memberships set price_paise = 15000 where id = …;
--     insert into public.payments (… 150000, 'INR', 'paid', 'cash' …);
--
--     ends_on = 2027-07-06   periods_granted = 10   money = 150000
--
-- **300 days for one ₹1,500 receipt**, and both audit invariants hold, so it
-- leaves exactly the "nothing to find" record that got `duration_days` closed.
-- At `price_paise = 1` it is 150,000 periods and an `ends_on` in the year 14347.
--
-- My argument in ADR-092 for treating the two factors differently was about
-- INTENT — "a negotiated number a desk legitimately mistypes" — and the effect
-- is a multiplier either way. **Intent does not bound a multiplier.** And round
-- ten made it permanent: `GL043` freezes the price once money arrives and
-- `GL045` freezes the dates, so a row built this way cannot be repaired in
-- place. A recoverable defect became unrecoverable in the round meant to be
-- closing this family.
--
-- **The control is WHO, not what**, and this codebase already made that call one
-- table over: `refunds_tenant_write` is `is_gym_admin()`, not
-- `is_front_office()` — "front_desk may record money but not refund it".
-- Deciding what a member owes is the same kind of act as deciding to give money
-- back. Deriving the price from the plan was rejected (a gym legitimately sells
-- below list and the money path does not read `discount_paise` — OPEN-028);
-- bounding the price was rejected (any threshold is invented); bounding the
-- discount instead was rejected (it renames the exploit).
--
-- **The INSERT half, and it is the third round running that creation was the
-- unpoliced door.** A blind author measured `GL046` as first written: it governs
-- a session that CHANGES those columns, so a front desk could simply CREATE the
-- membership at `price_paise = 15000` and take the ordinary ₹1,500 — the same
-- 300 days in one fewer statement than the exploit above. So creation carries
-- the same rule: a price or currency differing from the plan's, or a non-zero
-- discount, is gym-admin work. Creating at the plan's own price is the whole of
-- what a front desk does.
--
-- **This is the first CLAIM rule in this trigger, so it is the first with a
-- trusted-context carve-out**, on ADR-082's general form: a carve-out is sound
-- exactly when the rule's subject is something a trusted caller legitimately
-- lacks. `GL046`'s subject is which staff role you are, and a webhook, a
-- migration and the seed have no staff role at all. `app.enforce_payment()`
-- already draws that line in the same words, gating its claim rules behind
-- `row_security_active` while its integrity rules take none. `GL043`, `GL044`
-- and `GL045` are invariants about the data and stay role-agnostic.
--
-- It is proportionate, not absolute: a `gym_owner` or `gym_manager` can still
-- comp a membership to a paisa, **and should be able to** — that is a real thing
-- gyms do, it leaves the price on the row as evidence, and it is the same bound
-- ADR-093 accepted for OPEN-027. What it removes is the front desk doing it
-- silently, which was the measured threat model for every `GL043` finding in
-- this phase.
--
-- `after`, so it cannot answer ahead of the policy (ADR-066); it modifies
-- nothing, so nothing needs it early (ADR-072).

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
         or coalesce(new.discount_paise, 0) <> 0) then
      raise exception 'membership refused: a membership is sold at its plan''s price — % paise against a plan priced at % is a decision about what this member owes, and that belongs to the gym''s owner or manager',
        new.price_paise, v_price
        using errcode = 'GL046';
    end if;

    return null;
  end if;

  if new.price_paise    is distinct from old.price_paise
     or new.currency       is distinct from old.currency
     or new.plan_id        is distinct from old.plan_id
     or new.discount_paise is distinct from old.discount_paise then
    raise exception 'membership refused: what a member owes is the gym owner''s or manager''s to decide, the way a refund is — a front desk sells at the plan''s price and takes the money'
      using errcode = 'GL046';
  end if;

  return null;
end;
$fn$;
