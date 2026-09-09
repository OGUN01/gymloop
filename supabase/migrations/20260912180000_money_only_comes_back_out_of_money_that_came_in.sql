-- money_only_comes_back_out_of_money_that_came_in
--
-- Three money defects, each reproduced live by a critic, each reached by a
-- route the rule that names the harm does not cover.
--
-- **1. The `GL036` ceiling was defeated by demoting a refund to `failed`.**
-- Full refund accepted, second refused, first demoted, second accepted. The
-- asymmetry was the tell — re-completing the demoted refund is refused, so the
-- door was one-way out of the ledger.
--
-- **2. A full refund was accepted against a payment that took nothing.** The
-- ceiling read `amount_paise` and never `status`.
--
-- **3. A membership carrying granted periods was moved to another member** by
-- one front-desk UPDATE, while the paid payment still named the original member
-- and carried their receipt — verbatim the harm `GL042`'s own requirement
-- names, "the receipt names one person and the month lands on another",
-- reached by the least-privileged writer who can touch the table.
--
-- All three are ADR-089's general form: a rule keyed on something the
-- constrained party can rewrite, or evaluated on a row next to the one that
-- matters.
--
-- Codes reuse the families the rules belong to rather than inventing three:
-- `GL041` (a refund is a record) for the status freeze, `GL036` (the ceiling)
-- for money that never arrived, `GL042` (a payment extends only the membership
-- of the member who paid) for the membership move — which is the code whose own
-- requirement names this harm.

create or replace function app.enforce_refund_total()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_paid     bigint;
  v_refunded bigint;
  v_actor    uuid;
begin
  -- ---- Immutability, for every writer -------------------------------------
  if tg_op = 'UPDATE'
     and (new.payment_id is distinct from old.payment_id
       or new.amount_paise is distinct from old.amount_paise) then
    raise exception 'refund refused: which payment a refund is against, and how much it returned, are what it IS — correct it with a new row (PAY-010)'
      using errcode = 'GL041';
  end if;

  -- **A refund that completed did not fail.** The ceiling sums the refunds that
  -- are not `failed`, and nothing froze a refund's status — so a critic recorded
  -- a full refund, had a second one refused by `GL036`, demoted the first to
  -- `failed`, and the second was then accepted. Money that left the gym became
  -- an attempt that never happened.
  --
  -- ADR-089's general form, one table over: a freeze is worth exactly as much as
  -- the immutability of the thing it is keyed on.
  --
  -- **Only out of `completed`, and the narrowness is the point.** A refund at
  -- `requested` or `processing` is money the gym has handed over and the provider
  -- has not yet moved; it can genuinely fail, that is what the status is for, and
  -- refusing the transition would strand it while the ceiling ate money that
  -- never left. Both blind authors found that the same un-counting works from
  -- those statuses, and both were right — **but the invariant survives there for
  -- a different reason**, which the visible author measured: the ceiling applies
  -- on UPDATE too, so an un-counted refund can never be completed again, and at
  -- most one of the two ever reaches `completed`. The freeze protects money that
  -- has LEFT; `GL036`-on-update protects the rest.
  if tg_op = 'UPDATE'
     and old.status = 'completed'::public.refund_status
     and new.status is distinct from old.status then
    raise exception 'refund refused: this refund completed — % paise left the gym, and money that has gone does not become an attempt that never happened',
      old.amount_paise
      using errcode = 'GL041';
  end if;

  -- **Money only comes back out of money that came in — and this sits OUTSIDE
  -- the ceiling's `failed` carve-out.** A blind author put it there: the
  -- carve-out exists because a refund that itself failed took nothing, so it is
  -- neither summed nor bounded — that is a rule about HOW MUCH may go out.
  -- Whether the money ever came IN is a different question, and it has the same
  -- answer for a failed refund as for any other. Recording a failed attempt
  -- against a payment that never arrived is recording an attempt to return money
  -- the gym never had.
  --
  -- The three statuses are the ones the granting rule counts as money that
  -- ARRIVED, for the same reason it counts them: a refund does not un-arrive the
  -- money it returns.
  --
  -- A payment that cannot be read at all is left to the composite foreign key
  -- and the policy, not answered here (ADR-066) — hence the `exists` rather than
  -- a bare null test.
  if exists (select 1 from public.payments p
              where p.id = new.payment_id
                and p.tenant_id = new.tenant_id)
     and not exists (select 1 from public.payments p
                      where p.id = new.payment_id
                        and p.tenant_id = new.tenant_id
                        and p.status in ('paid'::public.payment_status,
                                         'refunded'::public.payment_status,
                                         'reversed'::public.payment_status)) then
    raise exception 'refund refused: that payment has not taken any money, so there is none to send back'
      using errcode = 'GL036';
  end if;

  -- ---- The ceiling, for every writer --------------------------------------
  --
  -- No carve-out: a provider-initiated refund arriving through the webhook as
  -- `service_role` is the path that will process refunds at scale, and a
  -- ceiling that path does not obey is not a ceiling (ADR-082).
  --
  -- **On update as well as insert**, which round one missed while quoting
  -- ADR-070 for a different rule three functions above. The ceiling passed at
  -- insert and the row was then edited past it: a Rs 1,000 payment carrying a
  -- Rs 1,00,000 refund.
  --
  -- A refund whose own status is `failed` took nothing, so it is neither summed
  -- NOR bounded. Round one excluded failed rows from the sum and then compared
  -- the new row regardless of its own status, so recording a failed retry
  -- against a fully refunded payment was impossible — the same rule
  -- disagreeing with itself, which a blind author found by reading it backward.
  if new.status <> 'failed'::public.refund_status then
    -- **Money only comes back out of money that came in.** This read
    -- `amount_paise` and never the payment's status, and `amount_paise` is not
    -- null on a `created` row — so a critic recorded a full `completed` refund
    -- against a payment that never arrived. Money out against money that never
    -- came in, and the payments screen already told the desk the database
    -- refused it: "a payment that is not paid has taken nothing … The database
    -- refuses both (`GL036`)". The second half was true and the first half was
    -- not, and the only thing enforcing it was the absence of a button.
    --
    -- The three statuses are the ones the granting rule counts as money that
    -- ARRIVED, for the same reason it counts them: a refund does not un-arrive
    -- the money it returns.
    select p.amount_paise into v_paid
      from public.payments p
     where p.id = new.payment_id
       and p.tenant_id = new.tenant_id
     for update;

    if v_paid is not null then
      select coalesce(sum(r.amount_paise), 0) into v_refunded
        from public.refunds r
       where r.payment_id = new.payment_id
         and r.tenant_id  = new.tenant_id
         and r.status <> 'failed'::public.refund_status
         and r.id <> new.id;

      if v_refunded + new.amount_paise > v_paid then
        raise exception 'refund refused: % paise already refunded against a payment of % paise, and this refund of % would exceed it',
          v_refunded, v_paid, new.amount_paise
          using errcode = 'GL036';
      end if;
    end if;
  end if;

  -- ---- Attribution, for sessions row security applies to -------------------
  --
  -- **The fifth appearance, and the first on money going OUT.** This file's own
  -- thesis in round one was that a manual payment has no provider to verify
  -- against, so attribution is the integrity — and the rule had four
  -- appearances on money coming in and none on the direction where a gym
  -- actually loses. The column was nullable, stamped by nothing, checked by
  -- nothing.
  if not pg_catalog.row_security_active('public.refunds') then
    return null;
  end if;

  v_actor := app.current_staff_id();

  if tg_op = 'UPDATE' then
    if new.initiated_by_staff_id is distinct from old.initiated_by_staff_id then
      raise exception 'refund refused: who sent money back is a recorded fact and cannot be reassigned'
        using errcode = 'GL040';
    end if;
  else
    -- The null actor as its own clause (ADR-071): after `app.stamp_refund()`
    -- has filled the column from the same absent claim, both sides are null and
    -- the comparison alone is silent exactly there.
    if v_actor is null
       or new.initiated_by_staff_id is distinct from v_actor then
      raise exception 'refund refused: money leaving the gym names the staff member who sent it, and this session records % against an actor of %',
        new.initiated_by_staff_id, coalesce(v_actor::text, 'no staff identity')
        using errcode = 'GL040';
    end if;
  end if;

  return null;
end;
$fn$;
