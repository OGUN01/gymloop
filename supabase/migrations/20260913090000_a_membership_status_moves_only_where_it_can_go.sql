-- a_membership_status_moves_only_where_it_can_go
--
-- **`payments` has had a state machine since Phase 5 round three and
-- `memberships` has never had one.** `app.payment_transition_allowed()` decides
-- which payment status may follow which and `GL039` enforces it; the equivalent
-- for memberships did not exist, so a critic moved a retired membership back to
-- life from an ordinary front-desk session in one statement:
--
--     update public.memberships set status = 'active' where id = <cancelled>;
--
-- `docs/data-model.md` has listed the legal transitions since Phase 1 and called
-- `expired` and `cancelled` terminal. **The gap was never a missing contract —
-- it is that nothing enforced the one that existed**, and a routing-table
-- document asserted a rule the database did not keep. OPEN-030, closed here.
--
-- **Retiring a membership early is not what this refuses.** Ending one before
-- its dates run out is what cancellation IS — half of the repair this codebase
-- prescribes for every mis-sold membership, and `expired` is the same act under
-- a different word. What must never happen is coming back OUT of a terminal
-- state, and that was as available as the moves that must work.
--
-- **`expired` is legal to write and the product never writes it.** ADR-064/075
-- say liveness is derived from dates and nothing in this product writes that
-- status; `supabase/seed-scenarios.sql` writes it to build the lapsed fixture
-- the whole retention loop is demonstrated on. Both are true at once: the
-- transition is legal, the product does not use it, and no rule reads `expired`
-- as the DEFINITION of lapsed — dates remain that (ADR-084).
--
-- **No trusted-context carve-out**, on ADR-082's general form: the subject is
-- which state may follow which, which a webhook or a migration does not
-- legitimately lack. The seed reaches `expired` and `cancelled` at INSERT, where
-- there is no transition to judge, and a re-run writes the same value back,
-- which is permitted.
--
-- **It gets a trigger of its own, and that is the whole of the design.** The
-- obvious place is beside the other rules in
-- `app.enforce_membership_terms_frozen()`, and a blind author caught what that
-- would cost: **`supabase/seed.sql` and `seed-scenarios.sql` disable that
-- trigger around their own statements.** The window is deliberate and narrow and
-- was argued for DATES — the seed builds months of history in one pass and a
-- payment can only ever move `ends_on` forward. It was never argued for
-- transitions. Folding this rule in there would leave it silently off for the
-- whole seed, and would pass every other assertion anyone wrote.
--
-- So `memberships_status_transitions` is separate, stays on while the terms
-- trigger is disabled, and the seed does not need it off: on a project where the
-- seed has already run, its `on conflict do update set status = excluded.status`
-- writes the same value back, which is a self-write and permitted; on a fresh
-- project the same statement is an INSERT, where there is no transition to
-- judge. Verified both ways before this was written.
--
-- `after`, so it cannot answer ahead of the policy (ADR-066); it modifies
-- nothing, so it needs nothing early (ADR-072).

create or replace function app.membership_transition_allowed(
  p_from public.membership_status,
  p_to   public.membership_status
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $fn$
  -- An explicit edge list rather than "not one of these", for the reason
  -- `app.payment_transition_allowed()` gives: a label added to
  -- `membership_status` later should be unreachable until somebody decides
  -- where it belongs. A default-permit table grows holes by itself.
  select case
    when p_from = p_to then true                        -- a write that does not move it
    when p_from = 'pending'::public.membership_status
      then p_to in ('active'::public.membership_status,
                    'cancelled'::public.membership_status)
    when p_from = 'active'::public.membership_status
      then p_to in ('frozen'::public.membership_status,
                    'cancelled'::public.membership_status,
                    'expired'::public.membership_status)
    when p_from = 'frozen'::public.membership_status
      then p_to in ('active'::public.membership_status,
                    'cancelled'::public.membership_status,
                    'expired'::public.membership_status)
    else false                                          -- expired and cancelled are terminal
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

  if tg_op = 'INSERT' then
    if new.periods_granted <> 0 then
      raise exception 'membership refused: a membership is created having been granted nothing — periods are granted by the payments that buy them, not typed in at the desk'
        using errcode = 'GL044';
    end if;
  else
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

    if new.duration_days is distinct from old.duration_days
       and new.plan_id is not distinct from old.plan_id then
      raise exception 'membership refused: how long a period is is what the plan says, not something the desk types — % days was written directly; change the plan instead',
        new.duration_days
        using errcode = 'GL043';
    end if;

    if new.member_id is distinct from old.member_id then
      raise exception 'membership refused: a membership belongs to the member it was sold to — the receipt names one person and the month would land on another; refund, cancel and sell a new one'
        using errcode = 'GL042';
    end if;

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

  if not pg_catalog.row_security_active('public.memberships') then
    return null;
  end if;

  if app.is_gym_admin() then
    return null;
  end if;

  if tg_op = 'INSERT' then
    select p.price_paise, p.currency
      into v_price, v_currency
      from public.plans p
     where p.id = new.plan_id
       and p.tenant_id = new.tenant_id;

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


create or replace function app.enforce_membership_status_transition()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if new.status is distinct from old.status
     and not app.membership_transition_allowed(old.status, new.status) then
    raise exception 'membership refused: a membership does not go from % to %; expired and cancelled are where a membership ends, and a new one is how a member starts again',
      old.status, new.status
      using errcode = 'GL047';
  end if;

  return null;
end;
$fn$;

drop trigger if exists memberships_status_transitions on public.memberships;

create trigger memberships_status_transitions
  after update on public.memberships
  for each row execute function app.enforce_membership_status_transition();
