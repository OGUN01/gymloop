-- activated_at_means_activated
--
-- Round five stamped `activated_at` whenever the membership was `pending`,
-- **independent of whether the status flip actually fired.** Both guards on the
-- flip — "nothing else of this member is live" and `starts_on is not null` —
-- were missing from the `activated_at` case expression.
--
-- Measured by a critic on the exact path `app.grant_periods()`'s own comment
-- block spends a paragraph defending: a member with one live membership and a
-- second dateless `pending` one, paid in full, came out
--
--   status=pending  periods_granted=1  starts=today  ends=today+30  activated_at=SET
--
-- The row stayed `pending` on purpose. `activated_at` then means "the first
-- payment landed", not "activated" — **which is exactly the divergence round
-- five's fix was written to close, running the other way.** The fix for a
-- column meaning two things gave it a third.
--
-- The two expressions are now literally the same condition, written out twice
-- because SQL has nowhere to put it once. If either is ever edited, both must
-- be: a `status` that flips without an `activated_at`, or an `activated_at`
-- without a flip, are the same defect in opposite directions.
--
-- Also: `periods_granted` may not go negative. `memberships` grants UPDATE to
-- `authenticated` through `memberships_tenant_write` with no column
-- restriction, and a critic set the column to `-11`, took one ordinary ₹1,500
-- payment, and moved `ends_on` a full year — a free year attributed in the
-- ledger to a legitimate month's payment. That session could already write
-- `ends_on` directly, so this is not new privilege; it is the number that
-- decides what money buys, and it should not be able to hold a value the rule
-- that maintains it can never produce.

alter table public.memberships
  drop constraint if exists memberships_periods_granted_chk;

alter table public.memberships
  add constraint memberships_periods_granted_chk check (periods_granted >= 0);


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
  select m.price_paise, m.currency, m.starts_on, m.ends_on, m.periods_granted, p.duration_days
    into v_price, v_currency, v_starts, v_ends, v_granted, v_duration
    from public.memberships m
    join public.plans p on p.id = m.plan_id and p.tenant_id = m.tenant_id
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
  -- `bigint`, so this truncates** — the whole of ADR-088, whose backfill let the
  -- same expression stay `numeric` and rounded 0.9 up to a month nobody paid
  -- for.
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
           -- **The same condition as `status`, deliberately duplicated.** Round
           -- five stamped this whenever the row was `pending`, so a membership
           -- that was left `pending` on purpose got an `activated_at` anyway.
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
           -- Same condition again, `starts_on` guard included. A membership left
           -- `pending` because it is half-dated must not be stamped as though it
           -- had been activated.
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
-- A membership's price is frozen once its money has bought anything.
-- ---------------------------------------------------------------------------
--
-- **Cutting the price after a period was bought hands out a free month for one
-- paisa.** Found by a blind test author told to go past its checklist, and
-- measured: a membership priced 100000 with one period granted, price edited to
-- 50000, then a **1-paisa** payment — `periods_granted` 1 → 2 and `ends_on`
-- another 30 days.
--
-- The arithmetic is doing what it was told. `v_owed := v_total / v_price`
-- re-scores ALL the money against whatever the price is now, so cutting the
-- price retroactively makes past payments buy more, and the next payment of any
-- size at all is what releases it. `memberships_tenant_write` is `FOR ALL` on
-- `is_front_office()`, so the same session can do both halves.
--
-- A round-four critic saw the same recompute and called it "ill-defined either
-- way; monotonic, so not exploitable". Monotonic it is — but a free month for a
-- paisa is exploitable, and "ill-defined" was the part worth acting on.
--
-- **The price a membership was sold at is a recorded fact**, like a payment's
-- amount and for the same reason: it is what the member agreed to, and every
-- period already granted was granted against it. Correcting a mistyped price
-- before any money arrives stays free; after, the honest instrument is a refund
-- and a new membership, which this phase now has.
--
-- `after update` and not `before`, so it cannot answer ahead of the policy that
-- would have refused the row anyway — ADR-066, which this phase has violated
-- three times and is not going to a fourth.

create or replace function app.enforce_membership_price_frozen()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if old.periods_granted > 0
     and new.price_paise is distinct from old.price_paise then
    raise exception 'membership refused: % periods have already been granted against a price of % paise, and re-pricing them would hand back or take away months that were paid for — refund and sell a new membership instead',
      old.periods_granted, old.price_paise
      using errcode = 'GL043';
  end if;

  -- The currency is half of what a price MEANS (MNY-002), and the rule sums
  -- money in the membership's own currency. Changing it re-scores every payment
  -- against a different set of rows.
  if old.periods_granted > 0
     and new.currency is distinct from old.currency then
    raise exception 'membership refused: its price is in % and % periods have been granted against it',
      old.currency, old.periods_granted
      using errcode = 'GL043';
  end if;

  return null;
end;
$fn$;

drop trigger if exists memberships_price_frozen on public.memberships;

create trigger memberships_price_frozen
  after update on public.memberships
  for each row execute function app.enforce_membership_price_frozen();
