-- periods_granted_is_recorded_not_derived
--
-- **Round three's own fix double-counts an upsert, and I found it the same way
-- every other defect in this phase was found: by running the shape rather than
-- reading the code.**
--
--   insert … values (a row that conflicts, now 'paid'),
--                   (a new row, 'paid')
--   on conflict (id) do update set status = excluded.status;
--
-- ₹500 + ₹500 against a ₹1,000 membership granted **60 days**, not 30.
--
-- `INSERT … ON CONFLICT DO UPDATE` fires BOTH statement triggers: the insert
-- trigger's transition table holds the rows that were inserted, the update
-- trigger's holds the rows that conflicted. Each invocation then computed
-- `before = after − its own added` — and the other invocation's rows were
-- already in `after`, because by the time either fires the whole statement has
-- landed. Both concluded they had crossed the multiple.
--
-- **This is the per-row defect of ADR-086 exactly, one level up.** Moving from
-- per-row to per-statement removed the ten-rows-in-one-statement case and left
-- the two-triggers-in-one-statement case, in the same way round two removed the
-- ten-statements case and left the one-statement case. Three rounds, one
-- mistake, each time believed fixed.
--
-- The mistake underneath all three is not the granularity. It is **deriving
-- "how much was already granted" by subtraction from a total that is not
-- stable at the moment of asking.** Subtraction needs a "before" that no
-- `AFTER` trigger has: every writer of the current statement, and every sibling
-- trigger invocation, has already committed its rows to the table you are
-- summing.
--
-- So stop deriving it. **`periods_granted` is recorded.** A payment computes how
-- many periods the money now OWES, compares that to what the membership has
-- already been granted, and grants the difference — which is idempotent, order
-- independent, and indifferent to how many triggers fire for one statement or
-- how many statements make up a transaction.
--
-- Round two's migration claimed the cumulative sum "needs no marker column and
-- cannot drift". A critic falsified the second half. This falsifies the first,
-- and the two were always the same sentence: **a running total that cannot be
-- checked against a record of what it already paid for is not a count, it is a
-- guess that happens to be right in the cases you tried.**

alter table public.memberships
  add column if not exists periods_granted integer not null default 0;

comment on column public.memberships.periods_granted is
  'How many plan-length periods this membership has been granted by payments. '
  'Recorded rather than derived: an AFTER trigger cannot see the total as it '
  'stood before its own statement, so "how much is already granted" must be a '
  'fact and not a subtraction (ADR-087).';

-- Backfill: every membership that has already been paid for is granted what its
-- money bought, so the next payment measures against the truth rather than
-- against zero. Without this, one further payment on any existing membership
-- would grant every period again.
--
-- Counted the same way the rule counts — money that ARRIVED, in the
-- membership's own currency — so the backfill and the rule cannot disagree.
update public.memberships m
   set periods_granted = greatest(
         0,
         coalesce((
           select sum(pp.amount_paise)
             from public.payments pp
            where pp.tenant_id     = m.tenant_id
              and pp.membership_id = m.id
              and pp.currency      = m.currency
              and pp.status in ('paid'::public.payment_status,
                                'refunded'::public.payment_status,
                                'reversed'::public.payment_status)
         ), 0) / nullif(m.price_paise, 0)
       )
 where m.price_paise > 0;


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
  -- `for update of m` serialises two transactions paying the same membership at
  -- once, and it is what makes the read-then-write below safe now that there IS
  -- a write: without it, two callers could read the same `periods_granted` and
  -- both grant the same period.
  select m.price_paise, m.currency, m.starts_on, m.ends_on, m.periods_granted, p.duration_days
    into v_price, v_currency, v_starts, v_ends, v_granted, v_duration
    from public.memberships m
    join public.plans p on p.id = m.plan_id and p.tenant_id = m.tenant_id
   where m.id = p_membership_id
     and m.tenant_id = p_tenant_id
   for update of m;

  -- No row is a membership this session cannot read (ADR-066). A zero price
  -- grants nothing rather than dividing by zero.
  if v_price is null or v_price = 0 or v_duration is null then
    return;
  end if;

  -- Money in another currency buys nothing here (MNY-002, AGENTS.md rule 8).
  if p_currency is distinct from v_currency then
    return;
  end if;

  -- Money that ARRIVED — `paid`, `refunded`, `reversed` — because a refund does
  -- not reverse the extension it bought, so the total must not fall when one is
  -- issued.
  --
  -- `p_added` is deliberately NOT subtracted from this. That subtraction was
  -- the defect: it assumes the total contains this statement's money and no
  -- other new money, which is false whenever a second trigger invocation, or a
  -- second statement in the same transaction, has already landed rows.
  select coalesce(sum(pp.amount_paise), 0)
    into v_total
    from public.payments pp
   where pp.tenant_id     = p_tenant_id
     and pp.membership_id = p_membership_id
     and pp.currency      = v_currency
     and pp.status in ('paid'::public.payment_status,
                       'refunded'::public.payment_status,
                       'reversed'::public.payment_status);

  -- What the money owes, against what has been given. The difference is the
  -- only thing this call grants, so calling it twice for the same money grants
  -- nothing the second time — which is precisely what an upsert firing both
  -- statement triggers does.
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

  -- Activated only if nothing else of theirs is live:
  -- `memberships_tenant_id_member_id_live_key` permits one, so activating
  -- unconditionally would make the PAYMENT fail with a `23505` on a memberships
  -- index, which the handler would report as "possible duplicate" (OPEN-023).
  if v_starts is null and v_ends is null then
    update public.memberships m
       set starts_on       = v_today,
           ends_on         = v_today + (v_duration * v_periods),
           periods_granted = v_owed,
           -- Stamped when this is what activates the row. `POST /api/memberships`
           -- stamps it on its own path, and an activation by payment left it
           -- null -- so the column meant "activated" on one path and nothing on
           -- the other. `coalesce` because a row already activated keeps the
           -- instant it actually was.
           activated_at    = case when m.status = 'pending'::public.membership_status
                                  then coalesce(m.activated_at, pg_catalog.now())
                                  else m.activated_at end,
           status          = case when m.status = 'pending'::public.membership_status
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
    update public.memberships m
       set ends_on         = greatest(m.ends_on, v_today) + (v_duration * v_periods),
           periods_granted = v_owed,
           -- Stamped when this is what activates the row. `POST /api/memberships`
           -- stamps it on its own path, and an activation by payment left it
           -- null -- so the column meant "activated" on one path and nothing on
           -- the other. `coalesce` because a row already activated keeps the
           -- instant it actually was.
           activated_at    = case when m.status = 'pending'::public.membership_status
                                  then coalesce(m.activated_at, pg_catalog.now())
                                  else m.activated_at end,
           -- `m.starts_on is not null` is not padding. A `pending` membership
           -- may hold ONE null date -- `memberships_dated_unless_pending_chk`
           -- permits any combination while pending -- and flipping such a row
           -- to `active` violates that CHECK, so an ordinary payment aborted
           -- with `23514`, which the handler does not map: the desk saw "That
           -- payment could not be saved." Cash taken, nothing written, no
           -- cause. A round-three regression -- round two had no status flip
           -- and this row simply completed.
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
                                  else m.status end
     where m.id = p_membership_id
       and m.tenant_id = p_tenant_id
       and m.ends_on is not null;
  end if;
end;
$fn$;


-- ---------------------------------------------------------------------------
-- A payment's identity is not writable, at any status.
-- ---------------------------------------------------------------------------
--
-- **The extension's UPDATE path joins `newly_paid` to `previously` on `id`, and
-- nothing stopped `id` changing.** Measured by a critic:
--
--   update payments set id = <new uuid>, status = 'paid' where id = <created row>
--
-- The row became `paid`, took a receipt number, recorded the money — and the
-- join missed, so the membership gained nothing. Money in, receipt issued,
-- period silently not granted.
--
-- Renumbering an already-PAID payment was permitted too: `GL038`'s frozen list
-- covers what a payment MEANS and omitted the key that other tables point at.
-- `refunds`, `invoices` and `addon_orders` all carry `payment_id`, and
-- `openspec/specs/check-in/spec.md` froze `attendance.id` on exactly this
-- argument — a visit could otherwise be renumbered out from under anything
-- holding it. The same argument was never applied to money, and round three
-- then made a money rule depend on that key.
--
-- Frozen at EVERY status, not only once paid: a `created` row's id is already
-- the thing a later update will be matched on.
--
-- `tenant_id` stays deliberately unfrozen and is left to the policy, on
-- ADR-068's reasoning: `payments_tenant_write`'s `with check` already refuses
-- moving a row to another gym, and a trigger raising first would answer ahead
-- of it (ADR-066).

create or replace function app.enforce_payment_identity()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if new.id is distinct from old.id then
    raise exception 'payment refused: a payment''s id is what refunds, invoices and add-on orders point at, and it does not change'
      using errcode = 'GL038';
  end if;
  return null;
end;
$fn$;

drop trigger if exists payments_identity_frozen on public.payments;

create trigger payments_identity_frozen
  after update on public.payments
  for each row execute function app.enforce_payment_identity();
