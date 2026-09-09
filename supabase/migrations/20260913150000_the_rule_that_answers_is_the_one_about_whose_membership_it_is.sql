-- the_rule_that_answers_is_the_one_about_whose_membership_it_is
--
-- **A holdout author read a sentence I wrote as written, and the implementation
-- disagreed with it.** `payment-record`'s "A membership belongs to the member it
-- was sold to" says: *"it SHALL be this rule that answers, not another one the
-- same statement also violates."* I wrote that with the LENGTH rule in view,
-- illustrated it with the length rule, and left the claim unqualified. An author
-- who had seen neither the implementation nor the visible suite asserted the
-- general form and measured two counter-examples:
--
--     set member_id = <other>, periods_granted = 3   -->  GL044, not GL042
--     set member_id = <other>, ends_on = <other>     -->  GL045, not GL042
--
-- Both refusals are correct; both name the wrong harm. Ownership was checked
-- third, after the two depth-gated invariants, for no reason anybody decided —
-- it is simply the order the clauses were typed in, one migration at a time.
--
-- **The contract now decides the order rather than inheriting it**: `GL042`,
-- then `GL044`, then `GL045`, then `GL043`, with `GL046` last as before.
-- `GL042` is first because it is the only one of the four about WHOSE
-- membership this is; the other three are about what may be typed onto a
-- membership already agreed to be yours. The repair differs, which is what makes
-- the message matter: `GL044` and `GL045` are answered by taking a payment,
-- `GL042` only by a refund, a cancellation and a new sale. Telling somebody
-- moving a membership to a different person to "take the money and the dates
-- follow" is advice for a different problem.
--
-- The order among `GL044`, `GL045` and `GL043` is deliberately NOT decided:
-- no scenario needs it, and deciding it would be answering a question nobody
-- asked.
--
-- **Built by moving the block, not by retyping the function** — the rule
-- ADR-099 wrote one migration ago, applied to the very next migration. The
-- `GL042` clause and its comments were lifted verbatim from
-- `20260913120000` and re-inserted at the top of the UPDATE branch; the
-- multiset of non-blank lines in this body is identical to that one's, which was
-- asserted mechanically rather than reviewed by eye. Nothing else changed.
--
-- `after`, so no rule answers ahead of the policy (ADR-066); it modifies
-- nothing, so it needs nothing early (ADR-072).

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
