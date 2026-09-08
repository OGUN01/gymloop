-- a_period_is_what_the_money_bought
--
-- Phase 5, round three. Round two's own fixes carried two critical defects, and
-- both were measured by a blind critic rather than argued.
--
-- 1. **TEN PAYMENTS IN ONE STATEMENT EACH BOUGHT A FULL MONTH.** ₹1,000 in ten
--    rows granted 300 days on a 30-day plan, from an ordinary front-desk
--    session, through one `supabase-js` call.
--
--    `AFTER … FOR EACH ROW` triggers all fire *after every row of the statement
--    is already in the table*. So each row re-derived the running total, found
--    the FINAL total, subtracted only its own amount, and concluded that it was
--    the one that crossed the multiple. Round two fixed the ten-separate-
--    statements case — `paid → created → paid`, which bought 90 days — and left
--    the one-statement case wide open, which buys 300.
--
--    The contrast that makes this a miss rather than an unknown: the refund
--    ceiling, moved to `after` in the same migration, is CORRECT under exactly
--    this shape, because it sums its siblings (`r.id <> new.id`) instead of
--    re-deriving a delta. The same author got the neighbour right.
--
--    **The fix is the trigger's granularity, not its arithmetic.** A rule about
--    "how much did this statement add" belongs in a STATEMENT-level trigger
--    with transition tables, where the statement's rows are a set that can be
--    summed once, per membership. Per-row, there is no correct answer available:
--    a row cannot see which of its siblings preceded it, because none of them
--    did.
--
-- 2. **A `receipt_number` TYPED ONTO AN UNPAID ROW JAMMED THE GYM'S BOOK FOR
--    EVER.** The overwrite only ran on the write that made a payment paid, so a
--    `created` row kept whatever number it was given. The next real payment then
--    collided on `payments_tenant_id_receipt_number_key` — and because the
--    failing insert rolls the counter's increment back with it, `next_number`
--    never advanced, so every later payment collided on the same number too.
--    `GL037` closed the counter door; this reached the same room through the
--    payment row. And `POST /api/payments` reports that collision as "already
--    recorded", which is cash taken, nothing written, and a screen saying it is
--    on file.
--
-- Three more, all measured, all folded in here:
--
-- 3. **The sum ignored currency.** A payment of 100000 USD-paise granted a full
--    period on a membership priced 100000 INR-paise (MNY-002, rule 8).
-- 4. **A dateless `pending` membership got its dates and stayed `pending`** — so
--    the member it had just been paid for was refused at the gate, because
--    `app.enforce_check_in()` requires `active` or `frozen` (ADR-084). Two
--    changes from one round contradicting each other in that round's own area.
-- 5. **The sum took no lock.** Two transactions each recording half the price
--    see only their own row, each grant nothing, and the deficit is permanent —
--    every later payment measures against the same total. Silent, and in the
--    direction the member complains about. `app.enforce_refund_total()` takes
--    `for update` for exactly this reason and says so; the extension did not.

-- ---------------------------------------------------------------------------
-- The receipt number is the counter's alone, at every status.
-- ---------------------------------------------------------------------------

create or replace function app.stamp_payment()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_rls    boolean;
  v_paying boolean;
  v_tz     text;
  v_day    date;
  v_year   integer;
  v_fy     text;
  v_seq    integer;
begin
  v_rls := pg_catalog.row_security_active('public.payments');

  v_paying := new.status = 'paid'::public.payment_status
              and (tg_op = 'INSERT'
                   or old.status is distinct from 'paid'::public.payment_status);

  if v_rls and tg_op = 'INSERT' and new.recorded_by_staff_id is null then
    new.recorded_by_staff_id := app.current_staff_id();
  end if;

  if v_rls then
    if v_paying then
      new.paid_at := pg_catalog.now();
    elsif tg_op = 'UPDATE'
          and old.status in ('paid'::public.payment_status,
                             'refunded'::public.payment_status,
                             'reversed'::public.payment_status) then
      -- Left alone so a changed value reaches the freeze and is refused
      -- VISIBLY. Restoring it made a backdate a silent no-op, and a refusal a
      -- caller cannot see is worse than the change it prevented.
      null;
    else
      new.paid_at := null;
    end if;
  end if;

  if not v_paying then
    -- **The number is not the caller's, at any status.** This line is the whole
    -- of finding 2: without it a `created` row kept a hand-typed number, the
    -- next real payment collided on the unique index, its rollback un-did the
    -- counter increment, and every payment after that collided on the same
    -- number for ever. One squatted number, and the gym can never issue another
    -- receipt.
    --
    -- A row already paid keeps what it has — the freeze in
    -- `app.enforce_payment()` refuses any change to it, and nulling it here
    -- would fight that rule rather than support it.
    if v_rls
       and not (tg_op = 'UPDATE'
                and old.status in ('paid'::public.payment_status,
                                   'refunded'::public.payment_status,
                                   'reversed'::public.payment_status)) then
      new.receipt_number := null;
    end if;
    return new;
  end if;

  -- Allocating a number is front-office work, and a session that is not front
  -- office has nothing to allocate. Without this a member's own insert reached
  -- `document_counters` from a BEFORE trigger and was refused by THAT table's
  -- policy — the right SQLSTATE by accident, naming a table they have no
  -- business knowing exists (ADR-066, ADR-082).
  if v_rls and not app.is_front_office() then
    return new;
  end if;

  -- A trusted writer that supplied its own number keeps it: a seed restating
  -- history is not a front desk inventing one.
  if not v_rls and new.receipt_number is not null then
    return new;
  end if;

  select o.timezone into v_tz
    from public.organizations o
   where o.id = new.tenant_id;

  if v_tz is null then
    return new;
  end if;

  v_day  := (coalesce(new.paid_at, new.created_at, pg_catalog.now()) at time zone v_tz)::date;
  v_year := case
              when extract(month from v_day) >= 4 then extract(year from v_day)
              else extract(year from v_day) - 1
            end;
  v_fy   := v_year::text || '-' || pg_catalog.lpad(((v_year + 1) % 100)::text, 2, '0');

  insert into public.document_counters (tenant_id, kind, financial_year, next_number)
  values (new.tenant_id, 'receipt', v_fy, 2)
  on conflict (tenant_id, kind, financial_year) do update
    set next_number = public.document_counters.next_number + 1,
        updated_at  = pg_catalog.now()
  returning public.document_counters.next_number - 1 into v_seq;

  new.receipt_number := v_fy || '/' || pg_catalog.lpad(v_seq::text, 6, '0');
  return new;
end;
$fn$;


-- ---------------------------------------------------------------------------
-- A period is what the money bought — counted once per statement.
-- ---------------------------------------------------------------------------

-- The arithmetic, in ONE place, called with the money a single statement added
-- to a single membership in a single currency. Splitting it out is what lets the
-- insert and update paths differ only in HOW they decide which rows are in
-- scope, which is the only thing that actually differs between them.
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
  v_after    bigint;
  v_before   bigint;
  v_periods  integer;
begin
  -- `for update of m` serialises two transactions paying the same membership at
  -- once. Without it each sees only its own row, each computes zero periods,
  -- and the deficit is PERMANENT — every later payment measures against the
  -- same total, so the missing month is never recovered. Silent, and in the
  -- direction the member complains about. `app.enforce_refund_total()` takes
  -- the same lock on the payment and says why; this one did not.
  select m.price_paise, m.currency, m.starts_on, m.ends_on, p.duration_days
    into v_price, v_currency, v_starts, v_ends, v_duration
    from public.memberships m
    join public.plans p on p.id = m.plan_id and p.tenant_id = m.tenant_id
   where m.id = p_membership_id
     and m.tenant_id = p_tenant_id
   for update of m;

  -- No row is a membership this session cannot read (ADR-066). A zero price
  -- grants nothing rather than dividing by zero — a comped membership is a
  -- decision somebody made, not a period this rule should invent.
  if v_price is null or v_price = 0 or v_duration is null then
    return;
  end if;

  -- Money in another currency buys nothing here. `amount_paise` summed across
  -- currencies and compared to a price in one of them granted a full month for
  -- a payment the gym does not price in (MNY-002, AGENTS.md rule 8).
  if p_currency is distinct from v_currency then
    return;
  end if;

  -- Money that ARRIVED — `paid`, `refunded`, `reversed` — because a refund does
  -- not reverse the extension it bought, so the total must not fall when one is
  -- issued. Summing only `paid` looks right and double-grants across a refund.
  select coalesce(sum(pp.amount_paise), 0)
    into v_after
    from public.payments pp
   where pp.tenant_id     = p_tenant_id
     and pp.membership_id = p_membership_id
     and pp.currency      = v_currency
     and pp.status in ('paid'::public.payment_status,
                       'refunded'::public.payment_status,
                       'reversed'::public.payment_status);

  v_before  := v_after - p_added;
  v_periods := (v_after / v_price) - (v_before / v_price);

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

  -- **Activated only if nothing else of theirs is live.**
  -- `memberships_tenant_id_member_id_live_key` permits at most one `active` or
  -- `frozen` membership per member, so activating unconditionally would make
  -- the PAYMENT fail with a `23505` on a memberships index -- and the handler
  -- would report that as "possible duplicate", which is wrong twice over. The
  -- console cannot reach this state (`POST /api/memberships` already refuses to
  -- sell a second while one is live), but a direct write can, and money must
  -- not be refused by an index nobody was told about.
  --
  -- Left `pending` in that case, with its dates granted: the member is covered
  -- by the membership that IS live, and nothing was lost. What is missing is
  -- anything that activates it later -- the same gap as nothing writing
  -- `expired`, carried as an open decision rather than solved by a trigger that
  -- would need a scheduler ADR-064 says does not exist.
  --
  -- **`status` moves to `active` otherwise**, and that is its own finding: granting
  -- the dates and leaving the row `pending` produced a membership that had been
  -- paid for and whose member was refused at the gate, because
  -- `app.enforce_check_in()` requires `active` or `frozen` (ADR-084). Two
  -- changes from one round contradicting each other in that round's own area.
  -- A membership that has been paid for admits its member.
  if v_starts is null and v_ends is null then
    -- Only a `pending` membership may hold null dates
    -- (`memberships_dated_unless_pending_chk`), and after ADR-083 that is the
    -- "sold but not yet paid for" shape.
    update public.memberships m
       set starts_on = v_today,
           ends_on   = v_today + (v_duration * v_periods),
           status    = case when m.status = 'pending'::public.membership_status
                                 and not exists (
                                   select 1 from public.memberships other
                                    where other.tenant_id = m.tenant_id
                                      and other.member_id = m.member_id
                                      and other.id <> m.id
                                      and other.status in ('active'::public.membership_status,
                                                           'frozen'::public.membership_status))
                            then 'active'::public.membership_status
                            else m.status end
     where m.id = p_membership_id
       and m.tenant_id = p_tenant_id;
  else
    -- `greatest(ends_on, today)` in the gym's day: renewing early keeps the days
    -- already bought, renewing late starts from today.
    update public.memberships m
       set ends_on = greatest(m.ends_on, v_today) + (v_duration * v_periods),
           status  = case when m.status = 'pending'::public.membership_status
                               and not exists (
                                 select 1 from public.memberships other
                                  where other.tenant_id = m.tenant_id
                                    and other.member_id = m.member_id
                                    and other.id <> m.id
                                    and other.status in ('active'::public.membership_status,
                                                         'frozen'::public.membership_status))
                          then 'active'::public.membership_status
                          else m.status end
     where m.id = p_membership_id
       and m.tenant_id = p_tenant_id
       and m.ends_on is not null;
  end if;
end;
$fn$;


create or replace function app.extend_membership_on_payment()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  r record;
begin
  -- **Statement level, with transition tables**, and that granularity IS the
  -- fix. Per row there is no correct answer available: every row of a statement
  -- is already in the table when an `AFTER … FOR EACH ROW` trigger runs, so a
  -- row asking "what did I add to the total" gets the total including all its
  -- siblings and subtracts only itself. Ten ₹1,000 rows in one statement each
  -- answered "I crossed the multiple" and bought 300 days between them.
  --
  -- A set is the right shape for a question about a set.
  --
  -- Grouped by CURRENCY as well as membership, so money in one currency is
  -- never added to a price in another.
  --
  -- The two branches reference different transition tables, and only the branch
  -- that runs is ever planned — plpgsql prepares a statement on first execution,
  -- so the insert path never plans the update path's reference to `previously`.
  if tg_op = 'INSERT' then
    for r in
      select n.tenant_id, n.membership_id, n.currency, sum(n.amount_paise)::bigint as added
        from newly_paid n
       where n.membership_id is not null
         and n.status = 'paid'::public.payment_status
       group by n.tenant_id, n.membership_id, n.currency
    loop
      perform app.grant_periods(r.tenant_id, r.membership_id, r.currency, r.added);
    end loop;
  else
    -- Rows this statement MOVED into `paid`. A row already paid before it must
    -- not count again, which the new-row set alone cannot say.
    for r in
      select n.tenant_id, n.membership_id, n.currency, sum(n.amount_paise)::bigint as added
        from newly_paid n
        join previously o on o.id = n.id
       where n.membership_id is not null
         and n.status = 'paid'::public.payment_status
         and o.status is distinct from 'paid'::public.payment_status
       group by n.tenant_id, n.membership_id, n.currency
    loop
      perform app.grant_periods(r.tenant_id, r.membership_id, r.currency, r.added);
    end loop;
  end if;

  return null;
end;
$fn$;

drop trigger if exists payments_extend_membership on public.payments;
drop trigger if exists payments_extend_membership_insert on public.payments;
drop trigger if exists payments_extend_membership_update on public.payments;

create trigger payments_extend_membership_insert
  after insert on public.payments
  referencing new table as newly_paid
  for each statement execute function app.extend_membership_on_payment();

create trigger payments_extend_membership_update
  after update on public.payments
  referencing old table as previously new table as newly_paid
  for each statement execute function app.extend_membership_on_payment();
