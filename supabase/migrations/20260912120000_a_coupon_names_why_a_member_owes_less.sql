-- a_coupon_names_why_a_member_owes_less
--
-- `GL046` governs `price_paise`, `currency`, `plan_id` and `discount_paise` —
-- and a critic measured the gap that leaves: **a front desk could attach a
-- 10%-off coupon while being refused the discount it implies.**
--
--     insert into public.memberships (… price_paise, coupon_id) values (… <coupon>);  -- ALLOWED
--     update public.memberships set coupon_id = <coupon> where id = …;                -- ALLOWED
--     update public.memberships set discount_paise = 10000 where id = …;              -- GL046
--
-- The row that leaves says "coupon applied, discount zero". `coupon_id` is the
-- column that names WHY a member owes less; `discount_paise` is how much less.
-- **They describe one decision, so either both belong to the gym admin or
-- neither does**, and the requirement puts them together.
--
-- Nothing reads either column in the money path today (OPEN-028), so this is a
-- coherence fix rather than money going wrong — which is exactly why it is worth
-- doing now, while it is cheap, rather than after something starts reading them.
--
-- On INSERT the test is `coupon_id is not null` rather than a comparison: a
-- membership sold at the plan's price with no coupon is ordinary front-desk
-- work, and attaching one at the point of sale is the same decision as
-- discounting at the point of sale.
--
-- The rest of the function is `20260912090000` unchanged, re-emitted because
-- PostgreSQL replaces a function whole. Its six rules and their reasoning are
-- documented there and in ADR-094; the only difference is two column lists.

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
