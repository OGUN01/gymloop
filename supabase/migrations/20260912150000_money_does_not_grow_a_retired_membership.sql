-- money_does_not_grow_a_retired_membership
--
-- `app.grant_periods()` read a membership's price, currency, dates, count and
-- length — **and never its status.** A critic measured what that costs on the
-- very sequence this phase prescribes as the repair for a mis-sold membership:
-- refund, cancel, sell a new one, and then name the RETIRED membership on the
-- payment.
--
--     before  ends_on 14347-04-10   periods 150000
--     after   ends_on 26667-11-08   periods 300000   status cancelled
--
-- The money is recorded and receipted, the retired row's dates move, and the
-- member stays refused at the gate because the gate reads status. Nothing
-- surfaces anywhere.
--
-- **It is reachable exactly when the product tells someone to do the repair**,
-- because that is the moment a member has two memberships and one of them is
-- retired. It is not reachable from the console — the membership page offers
-- only a live or lapsed membership to renew — but `POST /api/payments` accepts
-- any `membershipId`, and `GL042` only checks that the member matches.
--
-- The payment is still recorded, receipted, attributed, refundable and counted
-- by `GL036`'s ceiling. Refusing it instead would be a different and worse rule:
-- the money changed hands, and a receipt is the gym's record of that.
--
-- `pending` and `frozen` are deliberately not retired. A `pending` membership is
-- extended and activated by its first payment — that is how a dateless one comes
-- alive (ADR-089) — and a `frozen` one is a paused live membership whose member
-- is coming back.
--
-- The rest of the function is `20260911090000` unchanged, re-emitted because
-- PostgreSQL replaces a function whole.

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
  v_status   public.membership_status;
  v_total    bigint;
  v_owed     integer;
  v_periods  integer;
begin
  -- `duration_days` now comes off the membership, not off `plans`. The join to
  -- `plans` is gone with it: nothing in this function reads the plan any more,
  -- which is the whole point — a plan edit cannot reach money already taken.
  select m.price_paise, m.currency, m.starts_on, m.ends_on, m.periods_granted, m.duration_days, m.status
    into v_price, v_currency, v_starts, v_ends, v_granted, v_duration, v_status
    from public.memberships m
   where m.id = p_membership_id
     and m.tenant_id = p_tenant_id
   for update of m;

  -- **A retired membership does not grow.** This function read a membership's
  -- price, currency, dates, count and length and never its status, so a payment
  -- naming a `cancelled` row extended it — silently, because the check-in gate
  -- reads status and refuses the member anyway. Measured on the exact sequence
  -- this phase prescribes as the repair for a mis-sold membership: refund,
  -- cancel, sell a new one, then name the retired one on the payment.
  -- `ends_on` went to the year 26667.
  --
  -- **The repair path is precisely when this is reachable**, because it is the
  -- moment a member has two memberships and one of them is retired.
  -- `POST /api/payments` takes any `membershipId` and `GL042` only checks the
  -- member matches.
  --
  -- The payment is still recorded and receipted — the money did change hands,
  -- and refusing after the fact would leave cash in a drawer with nothing to
  -- show for it. What stops is the growing. `pending` and `frozen` are NOT
  -- retired: a pending membership is extended and activated by its first
  -- payment, which is how a dateless one comes alive, and a frozen one is a
  -- paused live membership whose member is coming back.
  if v_status in ('cancelled'::public.membership_status,
                  'expired'::public.membership_status) then
    return;
  end if;

  if v_price is null or v_price = 0 or v_duration is null then
    return;
  end if;

  if p_currency is distinct from v_currency then
    return;
  end if;

  -- Money that ARRIVED, in the membership's own currency. **Both operands are
  -- `bigint`, so this truncates** — the whole of ADR-088.
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
           -- **The same condition as `status`, deliberately duplicated.** A
           -- membership left `pending` on purpose must not be stamped as
           -- activated; editing either of these alone is the same defect in
           -- opposite directions (ADR-089's round).
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
