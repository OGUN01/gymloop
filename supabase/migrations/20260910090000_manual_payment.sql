-- manual_payment
--
-- Phase 5's first half: money taken at the desk. PAY-011 promises a gym with
-- no gateway connected is fully functional -- staff attribution, a receipt, and
-- a working renewal pipeline -- and this is that promise in the only place an
-- `authenticated` session cannot route around, because `payments` grants
-- `insert` to `authenticated` and a rule living in a Route Handler has a
-- supported way past it.
--
-- **A manual payment has no provider to verify against, so attribution IS the
-- integrity.** Online, Razorpay's signature says the money moved. Here nothing
-- does except the name of the person who says they took it -- which is why the
-- attribution rule, on its fourth appearance (`GL016` attendance, `GL026`
-- pauses, `GL030` follow-ups, `GL034` here), is load-bearing in a way it was
-- not on the first three.
--
-- FOUR TRIGGERS, AND THE SPLIT BETWEEN THEM IS THE POINT.
--
-- The first draft put all five rules in one `before insert or update` trigger
-- with one `row_security_active()` carve-out across the lot. A holdout suite
-- took ten assertions off it in one run, and every one of them came back to the
-- same mistake: **the carve-out belongs to the rules that adjudicate a CLAIM,
-- not to the rules that keep the books.**
--
--   * Attribution and the provider rule read the JWT. A trusted context has no
--     `staff_id` claim and legitimately writes provider identifiers -- the
--     Razorpay webhook is `service_role` and its whole job is to record what
--     the provider said. Carving those out is correct.
--   * A receipt number and a refund ceiling are not about who is asking. A
--     receipt book with a hole in it for every online payment is not a receipt
--     book, and a refund limit that the one path which will actually process
--     refunds at scale does not obey is not a limit. **They apply to every
--     writer, including the webhook, including a backfill.**
--
-- And the refusals moved from `before` to `after`, on ADR-072's rule: they
-- modify nothing, so nothing needs them early -- and running early made them
-- adjudicate rows row security was about to refuse, so a member inserting a
-- payment directly got this file's `GL034` instead of the policy's `42501`.
-- That is the same defect ADR-066 names, committed in a file whose own comments
-- quote ADR-066.
--
-- THE RULES.
--
-- 1. THE PAYMENT NAMES THE STAFF MEMBER WHO TOOK IT (`GL034`). The null actor
--    is its own clause and not one side of a comparison, because `null is
--    distinct from null` is false -- the shape ADR-071 is named after, and the
--    reason `enforce_pause_decision` had to be written twice. A null
--    `recorded_by_staff_id` is FILLED from the claim rather than refused: the
--    value can only come from the token, so there is nothing to forge, and the
--    client need not send an id it does not own. A *supplied* one that is not
--    the acting staff member is refused, which is exactly the distinction
--    ATT-005 drew when defaulting-when-null turned out not to be a control.
--
--    **On UPDATE the rule is different, and that is deliberate.** Who took the
--    money is a recorded fact, so it may not change at all -- not to a
--    colleague, and not to the person doing the editing. Re-running the INSERT
--    rule on UPDATE would instead refuse a manager amending a note on a
--    front-desk colleague's payment, which is ordinary work. Same reasoning as
--    `app.enforce_attendance_written_once()`: freeze what the row MEANT, leave
--    writable what happened afterwards.
--
-- 2. A DESK PAYMENT CANNOT CLAIM A PROVIDER (`GL035`). Two shapes, one rule.
--    A `cash` payment carrying `provider_payment_id` launders desk money into
--    apparently-verified money; and a `razorpay`-method payment typed in
--    through the desk asserts an online state only the provider may report
--    (PAY-006, PAY-007). Enforced on insert AND on update, because the second
--    statement is where a rule enforced only on insert gets undone (ADR-070).
--
--    So the Razorpay half of Phase 5 creates its order rows from a trusted
--    context, not from the browser's session. That is not a workaround: a
--    process holding the gateway's secret key is already trusted, and letting
--    a front-desk token author provider state would make this rule
--    unenforceable by construction.
--
-- 3. A RECEIPT NUMBER IS ALLOCATED ATOMICALLY, per gym, per Indian financial
--    year. `insert ... on conflict ... do update ... returning next_number - 1`:
--    **the row that hands out the number is the row that records it was handed
--    out**, in one statement, so there is no read for a second transaction to
--    race. A read-then-write here produces two receipts bearing one number,
--    which is precisely the state that makes a book unauditable -- and it is
--    silent until an auditor asks.
--
--    The number is `2026-27/000001`: the year is IN the string, and it has to
--    be. `payments_tenant_id_receipt_number_key` is UNIQUE (tenant_id,
--    receipt_number), so a bare restarting ordinal would collide with last
--    year's on the first payment of every April. A blind test author found
--    that by writing an assertion that could not be satisfied and asking why,
--    rather than weakening it.
--
--    Inside row security a caller-supplied `receipt_number` is OVERWRITTEN:
--    the gym's book is the counter's to number, and a desk session choosing
--    its own number is the same defect as choosing its own receipt. A trusted
--    writer that supplies one keeps it, because a seed or a migration
--    restating history is not a desk.
--
-- 4. A PAID PAYMENT EXTENDS THE MEMBERSHIP IT NAMES, from
--    `greatest(ends_on, today)` in the GYM'S day. Never `current_date`: every
--    Supabase connection is UTC, which is ADR-039, which Phase 4 shipped
--    anyway and paid for in ADR-078's round. A member renewing three days
--    early must not lose three days; one renewing three weeks late must not be
--    handed three weeks. Both are wrong in a direction somebody notices, and
--    only one of them complains.
--
-- 5. REFUNDS MAY NOT EXCEED WHAT WAS PAID (`GL036`), summed across every
--    refund and reversal against that payment, and the payment row is never
--    touched (PAY-010). The sum is taken under `for update` on the payment, so
--    two partial refunds cannot both pass a check neither has written yet.
--
-- WHAT IS DELIBERATELY NOT HERE.
--
-- A refund does not reverse the extension. A member who paid, attended and was
-- refunded has not un-attended, and what happens to their membership is a
-- decision a human makes -- stated in the spec, repeated here because the
-- absence of code is not self-documenting.
--
-- Idempotency needs nothing new: `payments_tenant_id_idempotency_key_key` is a
-- partial unique index on (tenant_id, idempotency_key), so a replay carrying
-- one key is refused before any trigger runs, and the membership is extended
-- once because the second row never exists. A replay carrying NO key is a
-- different payment by definition and this file does not pretend otherwise.
--
-- All four functions are `security invoker`. Measured, not assumed (ADR-066):
-- `document_counters` write is `is_front_office()` and `payments` write is
-- `is_front_office()`, so every session that may record a payment may already
-- allocate its number; `memberships` write is `is_front_office()` too, so the
-- extension needs no elevation either; `refunds` write is the narrower
-- `is_gym_admin()`, and `payments` select is `is_front_office()`, which
-- `is_gym_admin()` is a subset of. Nothing here would work better as definer,
-- and definer rights would turn each refusal into an oracle about rows the
-- caller may not read.

-- ---------------------------------------------------------------------------
-- What the row carries: the acting staff member, and the receipt number.
-- `before`, because both of these WRITE to the row (ADR-072).
-- ---------------------------------------------------------------------------

create or replace function app.stamp_payment()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_rls   boolean;
  v_tz    text;
  v_day   date;
  v_year  integer;
  v_fy    text;
  v_seq   integer;
begin
  -- "Does any policy apply to this session" -- false for the table owner and
  -- for any `BYPASSRLS` role, and it names no role at all (ADR-068).
  v_rls := pg_catalog.row_security_active('public.payments');

  -- Filled, not refused: the id comes from the token, so there is nothing a
  -- caller could gain by omitting it. Only on insert -- on update the column is
  -- frozen, and `app.enforce_payment()` says so.
  if v_rls and tg_op = 'INSERT' and new.recorded_by_staff_id is null then
    new.recorded_by_staff_id := app.current_staff_id();
  end if;

  -- Allocate when this write is what makes the payment paid, and only then: a
  -- receipt is for money received, and an intention to pay is not a payment
  -- (PAY-008). On UPDATE that means the created-to-paid transition and not a
  -- later edit of an already-paid row, which would burn a second number and
  -- leave the first one attached to nothing.
  --
  -- **No trusted-context carve-out.** The Razorpay webhook runs as
  -- `service_role` and its payments need receipt numbers exactly as the desk's
  -- do; a book with a hole in it for every online payment is not a book. What
  -- the trusted context keeps is the right to supply its OWN number -- a seed
  -- or a backfill restating history is not a front desk inventing one.
  if new.status = 'paid'::public.payment_status
     and (tg_op = 'INSERT' or old.status is distinct from 'paid'::public.payment_status)
     and (v_rls or new.receipt_number is null) then

    select o.timezone into v_tz
      from public.organizations o
     where o.id = new.tenant_id;

    -- Null means this session cannot read that gym -- a row
    -- `payments_tenant_write`'s `with check` is about to refuse. Left to the
    -- policy to answer rather than raising here (ADR-066); a `before` trigger
    -- that answers first tells a caller something about a gym they may not see.
    if v_tz is null then
      return new;
    end if;

    -- The payment's own date, in the gym's own day (MNY-004). `paid_at` first
    -- because that is when the money moved; `created_at` when the caller left
    -- it null, which it may. Not `now()` alone -- a payment backdated to March
    -- belongs in March's book, and deriving the year from the payment rather
    -- than taking it as an argument is what stops a caller filing it into the
    -- next one by asking.
    v_day  := (coalesce(new.paid_at, new.created_at, pg_catalog.now()) at time zone v_tz)::date;
    v_year := case
                when extract(month from v_day) >= 4 then extract(year from v_day)
                else extract(year from v_day) - 1
              end;
    v_fy   := v_year::text || '-' || pg_catalog.lpad(((v_year + 1) % 100)::text, 2, '0');

    -- ONE statement. `next_number` means "the number the NEXT payment gets",
    -- so a fresh row is born at 2 having just handed out 1, and both branches
    -- return the value consumed as `next_number - 1`. A concurrent transaction
    -- blocks on the row or on the unique index and then reads the incremented
    -- value -- there is no window in which two callers hold the same number,
    -- because neither ever reads before writing. A counter somebody else has
    -- already advanced to 50 hands out 50 and leaves 51; nothing here
    -- remembers what it thought the number was before it asked.
    insert into public.document_counters (tenant_id, kind, financial_year, next_number)
    values (new.tenant_id, 'receipt', v_fy, 2)
    on conflict (tenant_id, kind, financial_year) do update
      set next_number = public.document_counters.next_number + 1,
          updated_at  = pg_catalog.now()
    returning public.document_counters.next_number - 1 into v_seq;

    -- The financial year is IN the number, because the counter restarts every
    -- April and `payments_tenant_id_receipt_number_key` is unique per gym.
    new.receipt_number := v_fy || '/' || pg_catalog.lpad(v_seq::text, 6, '0');
  end if;

  return new;
end;
$fn$;

drop trigger if exists payments_stamp on public.payments;

create trigger payments_stamp
  before insert or update on public.payments
  for each row execute function app.stamp_payment();


-- ---------------------------------------------------------------------------
-- What the row may SAY: who took the money, and whose money it was.
-- `after`, because neither of these writes anything, and a `before` refusal
-- answers ahead of the policy (ADR-066, ADR-072).
-- ---------------------------------------------------------------------------

create or replace function app.enforce_payment()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_actor uuid;
begin
  -- Here the carve-out IS right: both rules below adjudicate a JWT claim, and
  -- a trusted context has none. The Razorpay webhook runs as `service_role`,
  -- has no `staff_id`, and writes provider identifiers because that is its
  -- entire job.
  if not pg_catalog.row_security_active('public.payments') then
    return null;
  end if;

  v_actor := app.current_staff_id();

  if tg_op = 'UPDATE' then
    -- Who took the money is a recorded fact. Not "may only be changed to
    -- yourself" -- changed at all.
    if new.recorded_by_staff_id is distinct from old.recorded_by_staff_id then
      raise exception 'payment refused: who recorded a payment is a recorded fact and cannot be reassigned (% to %)',
        old.recorded_by_staff_id, new.recorded_by_staff_id
        using errcode = 'GL034';
    end if;
  else
    -- Two conditions, and the first is not redundant. A session inside row
    -- security with no `staff_id` claim -- an impersonating platform admin, a
    -- plain `super_admin` -- has nobody to record, and after
    -- `app.stamp_payment()` has filled the column from that same absent claim,
    -- `new.recorded_by_staff_id is distinct from v_actor` is FALSE because
    -- both are null. The comparison alone is silent exactly there (ADR-071).
    if v_actor is null
       or new.recorded_by_staff_id is distinct from v_actor then
      raise exception 'payment refused: a payment is recorded by the staff member who took it, and this session records % against an actor of %',
        new.recorded_by_staff_id, coalesce(v_actor::text, 'no staff identity')
        using errcode = 'GL034';
    end if;
  end if;

  if new.method = 'razorpay'::public.payment_method then
    raise exception 'payment refused: an online payment is recorded by the provider, not typed in at the desk -- the desk records cash, upi, card or bank_transfer (PAY-006)'
      using errcode = 'GL035';
  end if;

  if new.provider is not null
     or new.provider_order_id is not null
     or new.provider_payment_id is not null then
    raise exception 'payment refused: a % payment cannot carry provider identifiers -- that shape launders desk money into apparently-verified money',
      new.method
      using errcode = 'GL035';
  end if;

  return null;
end;
$fn$;

drop trigger if exists payments_enforce on public.payments;

create trigger payments_enforce
  after insert or update on public.payments
  for each row execute function app.enforce_payment();


-- ---------------------------------------------------------------------------
-- What the payment DOES: extend the membership it names.
-- ---------------------------------------------------------------------------

create or replace function app.extend_membership_on_payment()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tz    text;
  v_today date;
begin
  -- No carve-out, for the same reason the receipt number has none: this is
  -- what the product DOES when money arrives, and it has to happen on every
  -- path money can arrive by -- including the Razorpay webhook, which would
  -- otherwise take payment and extend nothing.
  if new.status <> 'paid'::public.payment_status then
    return null;
  end if;

  -- Already paid before this statement: extended when it became paid, and a
  -- redundant replay UPDATE must not hand out a second month. This is the whole
  -- of "exactly once however many times the payment is recorded, retried or
  -- replayed" for the update path; the insert path is held by
  -- `payments_tenant_id_idempotency_key_key`.
  if tg_op = 'UPDATE' and old.status = 'paid'::public.payment_status then
    return null;
  end if;

  -- A gym may take money for a personal-training pack, a T-shirt or a joining
  -- fee. Money that names no membership extends no membership.
  if new.membership_id is null then
    return null;
  end if;

  select o.timezone into v_tz
    from public.organizations o
   where o.id = new.tenant_id;

  if v_tz is null then
    return null;
  end if;

  v_today := (pg_catalog.now() at time zone v_tz)::date;

  -- `greatest(ends_on, today)`, and the gym's today. Renewing early keeps the
  -- days already paid for; renewing late starts from today rather than handing
  -- back the lapsed weeks.
  --
  -- `m.ends_on is not null` is a guard, not a filter: `greatest` in Postgres
  -- IGNORES nulls, so an open-ended membership would silently acquire a finite
  -- end date thirty days out -- a downgrade dressed as a renewal. An
  -- open-ended membership has nothing to extend.
  update public.memberships m
     set ends_on = greatest(m.ends_on, v_today) + p.duration_days
    from public.plans p
   where m.id        = new.membership_id
     and m.tenant_id = new.tenant_id
     and p.id        = m.plan_id
     and p.tenant_id = m.tenant_id
     and m.ends_on is not null;

  return null;
end;
$fn$;

drop trigger if exists payments_extend_membership on public.payments;

create trigger payments_extend_membership
  after insert or update on public.payments
  for each row execute function app.extend_membership_on_payment();


-- ---------------------------------------------------------------------------
-- A refund cannot exceed the payment it refunds.
-- ---------------------------------------------------------------------------

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
begin
  -- No carve-out. This is an invariant about money, not a judgement about a
  -- claim: a provider-initiated refund arriving through the webhook as
  -- `service_role` is exactly the path that will process refunds at scale, and
  -- a ceiling that path does not obey is not a ceiling.

  -- `for update` and not a plain read. Two staff refunding halves of one
  -- payment both pass a check neither has written yet -- the read-then-write
  -- race Phase 3 spent a day removing from check-in, on a table where the
  -- symptom is money leaving the gym twice. Locking the PAYMENT serialises
  -- every refund against it, whatever order they arrive in.
  select p.amount_paise into v_paid
    from public.payments p
   where p.id = new.payment_id
     and p.tenant_id = new.tenant_id
   for update;

  -- No row is a payment in another gym, or one this session may not read.
  -- The composite foreign key and the policy answer that (ADR-066).
  if v_paid is null then
    return new;
  end if;

  -- Every kind counts -- a reversal is money going back exactly as a refund is.
  -- A `failed` refund does not: it took nothing, and letting it hold headroom
  -- would block the retry that is the whole point of recording the failure.
  select coalesce(sum(r.amount_paise), 0) into v_refunded
    from public.refunds r
   where r.payment_id = new.payment_id
     and r.tenant_id  = new.tenant_id
     and r.status <> 'failed'::public.refund_status;

  if v_refunded + new.amount_paise > v_paid then
    raise exception 'refund refused: % paise already refunded against a payment of % paise, and this refund of % would exceed it',
      v_refunded, v_paid, new.amount_paise
      using errcode = 'GL036';
  end if;

  return new;
end;
$fn$;

drop trigger if exists refunds_enforce_total on public.refunds;

create trigger refunds_enforce_total
  before insert on public.refunds
  for each row execute function app.enforce_refund_total();
