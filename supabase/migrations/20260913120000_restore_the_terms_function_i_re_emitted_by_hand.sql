-- restore_the_terms_function_i_re_emitted_by_hand
--
-- **`20260913090000` silently re-emitted `app.enforce_membership_terms_frozen()`
-- and the re-emission was not behaviour-preserving.** Nothing needed it: the
-- whole design of that migration is that the new transition rule gets a trigger
-- of its own. I had first written the check inside the terms function, then
-- moved it out on a blind author's finding, and left the re-emission behind —
-- retyped from the previous migration rather than copied from it.
--
-- A critic measured two consequences. Neither is a money or security hole,
-- because every path involved still refuses; both are silent changes to a
-- money-path function.
--
--   * **About sixty lines of recorded reasoning vanished from the live body.**
--     `pg_proc.prosrc` no longer carried "A membership belongs to the member it
--     was sold to", the absolute-beats-permission note on why `GL043` is checked
--     before `GL046`, or the ADR-082/089/090/092/093 citations — the reasoning
--     that exists precisely so the next person to edit this function knows why
--     each clause is where it is.
--   * **`GL042` moved from before the `GL043` duration check to after it.**
--     Measured, ordinary front desk, money-free membership:
--     `set member_id = <other>, duration_days = 3650` answered `GL043` where it
--     had answered `GL042`. Single-column writes still answer correctly, which
--     is exactly why nothing caught it.
--
-- **This repo names the hazard verbatim**, in `app.enforce_payment_arrival_status()`'s
-- own registry cell: "re-emitting a hundred-line function by hand to add four
-- lines is how this phase has introduced defects before." I read that sentence
-- while writing that cell and then did it anyway, one change later.
--
-- Restored byte-for-byte from `20260912210000`, the last migration that
-- legitimately defined this function. Forward-only, so this is a new migration
-- rather than an edit; the transition rule and its own trigger from
-- `20260913090000` are untouched.
--
-- The general form, and the reason this is worth a migration rather than a
-- shrug: **a function this project replaces whole should be copied from its
-- previous definition, never retyped**, and a migration that replaces a function
-- it does not need to touch should not exist at all.

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
