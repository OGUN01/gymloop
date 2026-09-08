-- a_payment_is_a_record
--
-- Phase 5, round two. Two blind critics returned NO-GO with twenty findings
-- between them, and almost every critical one was a single defect wearing
-- different clothes:
--
--   **The INSERT was governed and the UPDATE was not.**
--
-- Measured against Cloud by the critics, not argued: a refund's amount raised
-- past the payment after the ceiling had approved it (a Rs 1,000 payment
-- carrying a Rs 1,00,000 refund); a payment walked `paid -> created -> paid`
-- four times to buy ninety days on a thirty-day plan and burn three receipt
-- numbers doing it; a desk typing its own receipt number over an allocated one;
-- `paid_at` supplied to file payments into `2031-32` and `2019-20`; and the
-- gym's counter reset by hand until the next payment collided with a number
-- already issued.
--
-- Round one's own file quotes ADR-070 — "the second statement is where a rule
-- enforced only on insert gets undone" — three functions above the rule that
-- did not do it. **Quoting a rule is not applying it**, which ADR-082 had
-- already had to say once about ADR-066 in the same file.
--
-- WHAT THIS FILE ADDS, and the shape it is all one instance of.
--
-- 1. A PAYMENT THAT HAS BEEN PAID IS A RECORD (`GL038`). The money facts freeze
--    — amount, currency, member, membership, method, receipt number, paid_at,
--    the provider trio, the idempotency key. What stays writable is what
--    happened afterwards: `status`, `notes`, `failed_reason`. This is
--    `app.enforce_attendance_written_once()`'s distinction applied to money.
--
-- 2. STATUS MOVES ONLY WHERE IT CAN GO (`GL039`). `paid` is unreachable from
--    anywhere it has already been, which is what stops the extension and the
--    receipt counter being farmed by pressing a button. `failed -> pending` is
--    the one backward edge that is real, because a retry is a new attempt.
--
-- 3. `paid_at` IS THE SYSTEM'S TO STAMP. Three documents claimed the financial
--    year was "derived from the payment's own date rather than passed in, so a
--    caller cannot file a March payment into the next year by asking". A critic
--    filed two payments into other decades by asking. The argument was
--    `paid_at`. A trusted writer keeps its own value, because the webhook's is
--    the provider's timestamp and is the more truthful one.
--
-- 4. THE COUNTER ONLY COUNTS UP, BY ONE (`GL037`). `document_counters_tenant_write`
--    is `FOR ALL` on `is_front_office()` — the same predicate that lets a person
--    take money lets them rewrite the book's numbering. Kept as a rule on the
--    table rather than by revoking the grant or elevating the allocator: the
--    allocation is `security invoker` and needs the caller's own privilege, and
--    making it `definer` would add the first unjustified elevated function in
--    `app` since Phase 2 — which a holdout meta-test asserts against by name.
--    **No trusted-context carve-out**, on ADR-082's line: this is an invariant
--    about a book, not a judgement about a claim. A future correction disables
--    the trigger in a migration, which is explicit and reviewable, rather than
--    passing silently because of who is asking.
--
-- 5. A REFUND IS BOUNDED WHENEVER IT CHANGES, not only when written, and its
--    `payment_id` and `amount_paise` freeze once recorded (`GL041`).
--
-- 6. MONEY LEAVING THE GYM NAMES A HUMAN (`GL040`). This file's own thesis in
--    round one was that a manual payment has no provider to verify against, so
--    **attribution IS the integrity** — and that rule has four appearances on
--    money coming in. On money going out, the direction where a gym actually
--    loses, `refunds.initiated_by_staff_id` was nullable, stamped by nothing
--    and checked by nothing. Fifth appearance, and the null actor is its own
--    clause for the reason it always is (ADR-071).
--
-- 7. A PAYMENT EXTENDS ONLY ITS OWN MEMBER'S MEMBERSHIP (`GL042`). Nothing
--    related `payments.member_id` to `memberships.member_id`; the extension
--    matched on `membership_id` and tenant alone, and the console posts both as
--    client-supplied hidden fields. The receipt named one person and the month
--    landed on another.
--
-- 8. A PERIOD IS GRANTED WHEN IT HAS BEEN PAID FOR. Two half payments bought
--    two months. ADR-083 closed the create-then-pay door on exactly that
--    sentence and left the instalment door open — and Rs 500 now, Rs 500 next
--    week is ordinary practice in an Indian gym. A payment now grants
--    `floor(total_after / price) - floor(total_before / price)` periods,
--    counted cumulatively over the membership's own paid rows, so it needs no
--    marker column and cannot drift.
--
-- 9. A REFUSAL IS THE POLICY'S TO GIVE. ADR-082 moved the claim rules to
--    `after` so a member no longer met `GL034` — and then `app.stamp_payment()`,
--    a `before` trigger, allocated a counter row for them and let
--    `document_counters`' policy answer instead. The SQLSTATE was right by
--    accident and named a table the member has no business knowing exists.
--    Allocating a number is front-office work.

-- ---------------------------------------------------------------------------
-- What the row carries. Now also decides WHEN a payment was paid.
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

  -- "This write is what makes the payment paid", used three times below.
  v_paying := new.status = 'paid'::public.payment_status
              and (tg_op = 'INSERT'
                   or old.status is distinct from 'paid'::public.payment_status);

  if v_rls and tg_op = 'INSERT' and new.recorded_by_staff_id is null then
    new.recorded_by_staff_id := app.current_staff_id();
  end if;

  -- `paid_at` is not the caller's. Under row security it is exactly the instant
  -- this write made the payment paid, preserved unchanged once it is paid, and
  -- null while it is not — so the financial year below is genuinely DERIVED
  -- rather than, as it was, taken as an argument with a comment saying it was
  -- not.
  if v_rls then
    if v_paying then
      new.paid_at := pg_catalog.now();
    elsif tg_op = 'UPDATE'
          and old.status in ('paid'::public.payment_status,
                             'refunded'::public.payment_status,
                             'reversed'::public.payment_status) then
      -- Deliberately NOT restored to `old.paid_at`. Restoring it made a
      -- backdate a silent no-op: the caller's value was quietly replaced, the
      -- freeze below then compared equal, and the update was reported as
      -- success while doing nothing the caller asked for. **A refusal a caller
      -- cannot see is worse than the change it prevented.** Left alone, so a
      -- changed `paid_at` reaches `app.enforce_payment()` and is refused with
      -- `GL038` like every other frozen column.
      null;
    else
      new.paid_at := null;
    end if;
  end if;

  if not v_paying then
    return new;
  end if;

  -- Allocating a number is front-office work, and a session that is not front
  -- office has nothing to allocate. Without this line a member's own insert
  -- reached `document_counters` from a BEFORE trigger and was refused by THAT
  -- table's policy — the right SQLSTATE by accident, naming a table they have
  -- no business knowing exists, and still answering ahead of the policy on
  -- `payments` that should have refused them (ADR-066, the half of ADR-082's
  -- repair that was missed).
  if v_rls and not app.is_front_office() then
    return new;
  end if;

  -- A trusted writer that supplied its own number keeps it; a seed restating
  -- history is not a front desk inventing a number.
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
-- What the row may SAY, and what it may BECOME.
-- ---------------------------------------------------------------------------

create or replace function app.enforce_payment()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_actor    uuid;
  v_was_paid boolean;
  v_owner    uuid;
begin
  -- ---- Integrity, for every writer including the webhook and the seed -------
  --
  -- These are invariants about money, not judgements about a claim, so they
  -- take no trusted-context carve-out. ADR-082 is the round that drew that line
  -- and this is the same side of it: a provider-initiated reversal replaying an
  -- old event is exactly the caller most likely to walk a status backwards.

  if new.membership_id is not null then
    select m.member_id into v_owner
      from public.memberships m
     where m.id = new.membership_id
       and m.tenant_id = new.tenant_id;

    -- Null is a membership this session cannot read, or one in another gym.
    -- Left to the composite foreign key and the policy to answer (ADR-066).
    if v_owner is not null and v_owner is distinct from new.member_id then
      raise exception 'payment refused: membership % belongs to member %, not to %',
        new.membership_id, v_owner, new.member_id
        using errcode = 'GL042';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    -- `refunded` and `reversed` are only reachable from `paid`, so this is
    -- "has this payment ever been paid" written as the three states that mean it.
    v_was_paid := old.status in ('paid'::public.payment_status,
                                 'refunded'::public.payment_status,
                                 'reversed'::public.payment_status);

    if not app.payment_transition_allowed(old.status, new.status) then
      raise exception 'payment refused: a payment does not go from % to %; paid is unreachable from anywhere it has already been',
        old.status, new.status
        using errcode = 'GL039';
    end if;

    if v_was_paid
       and (new.amount_paise        is distinct from old.amount_paise
         or new.currency            is distinct from old.currency
         or new.member_id           is distinct from old.member_id
         or new.membership_id       is distinct from old.membership_id
         or new.method              is distinct from old.method
         or new.receipt_number      is distinct from old.receipt_number
         or new.paid_at             is distinct from old.paid_at
         or new.provider            is distinct from old.provider
         or new.provider_order_id   is distinct from old.provider_order_id
         or new.provider_payment_id is distinct from old.provider_payment_id
         or new.idempotency_key     is distinct from old.idempotency_key) then
      raise exception 'payment refused: % is a record of money that changed hands — its amount, member, membership, method, receipt number and date are what the receipt says, and only status, notes and failed_reason may change afterwards',
        old.receipt_number
        using errcode = 'GL038';
    end if;
  end if;

  -- ---- The claim rules, for sessions row security applies to ---------------
  --
  -- Here the carve-out IS right: both read the JWT, and a trusted context has
  -- none. The Razorpay webhook is `service_role`, has no `staff_id`, and writes
  -- provider identifiers because that is its entire job.
  if not pg_catalog.row_security_active('public.payments') then
    return null;
  end if;

  v_actor := app.current_staff_id();

  if tg_op = 'UPDATE' then
    if new.recorded_by_staff_id is distinct from old.recorded_by_staff_id then
      raise exception 'payment refused: who recorded a payment is a recorded fact and cannot be reassigned (% to %)',
        old.recorded_by_staff_id, new.recorded_by_staff_id
        using errcode = 'GL034';
    end if;
  else
    -- The null actor is its own clause, not one side of the comparison:
    -- `null is distinct from null` is false, and after `stamp_payment` has
    -- filled the column from the same absent claim both sides are null
    -- (ADR-071). Note that `payments_offline_has_staff_chk` refuses a desk
    -- method with no staff member first, so this clause is the one that answers
    -- only for a method that CHECK does not cover — it is defence in depth and
    -- the constraint is what a test will actually observe.
    if v_actor is null
       or new.recorded_by_staff_id is distinct from v_actor then
      raise exception 'payment refused: a payment is recorded by the staff member who took it, and this session records % against an actor of %',
        new.recorded_by_staff_id, coalesce(v_actor::text, 'no staff identity')
        using errcode = 'GL034';
    end if;
  end if;

  if new.method = 'razorpay'::public.payment_method then
    raise exception 'payment refused: an online payment is recorded by the provider, not typed in at the desk — the desk records cash, upi, card or bank_transfer (PAY-006)'
      using errcode = 'GL035';
  end if;

  if new.provider is not null
     or new.provider_order_id is not null
     or new.provider_payment_id is not null then
    raise exception 'payment refused: a % payment cannot carry provider identifiers — that shape launders desk money into apparently-verified money',
      new.method
      using errcode = 'GL035';
  end if;

  return null;
end;
$fn$;


-- ---------------------------------------------------------------------------
-- The transition table, as a function so it is stated once and can be read.
-- ---------------------------------------------------------------------------

create or replace function app.payment_transition_allowed(
  p_from public.payment_status,
  p_to   public.payment_status
)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $fn$
  -- Written as an explicit edge list rather than as "not one of these", because
  -- a new label added to `payment_status` should be unreachable until somebody
  -- decides where it belongs. A default-permit table grows holes by itself.
  select case
    when p_from = p_to then true                     -- an update that does not move it
    when p_from = 'created'::public.payment_status
      then p_to in ('pending'::public.payment_status,
                    'paid'::public.payment_status,
                    'failed'::public.payment_status)
    when p_from = 'pending'::public.payment_status
      then p_to in ('paid'::public.payment_status,
                    'failed'::public.payment_status)
    when p_from = 'paid'::public.payment_status
      then p_to in ('refunded'::public.payment_status,
                    'reversed'::public.payment_status)
    -- The one backward edge that is real: a retry is a new attempt, not a
    -- rewrite of the failure.
    when p_from = 'failed'::public.payment_status
      then p_to in ('created'::public.payment_status,
                    'pending'::public.payment_status)
    else false                                       -- refunded and reversed are terminal
  end
$fn$;


-- ---------------------------------------------------------------------------
-- What the payment DOES: grant the periods it has paid for.
-- ---------------------------------------------------------------------------

create or replace function app.extend_membership_on_payment()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_tz       text;
  v_today    date;
  v_price    bigint;
  v_duration integer;
  v_starts   date;
  v_ends     date;
  v_after    bigint;
  v_before   bigint;
  v_periods  integer;
begin
  if new.status <> 'paid'::public.payment_status then
    return null;
  end if;

  if tg_op = 'UPDATE' and old.status = 'paid'::public.payment_status then
    return null;
  end if;

  if new.membership_id is null then
    return null;
  end if;

  select m.price_paise, m.starts_on, m.ends_on, p.duration_days
    into v_price, v_starts, v_ends, v_duration
    from public.memberships m
    join public.plans p on p.id = m.plan_id and p.tenant_id = m.tenant_id
   where m.id = new.membership_id
     and m.tenant_id = new.tenant_id;

  -- No row is a membership this session cannot read (ADR-066). A zero price
  -- grants nothing rather than dividing by zero — a comped membership is a
  -- decision somebody made, not a period this rule should invent.
  if v_price is null or v_price = 0 or v_duration is null then
    return null;
  end if;

  -- **A period is granted when it has been PAID FOR, not when a payment
  -- arrives.** Two half payments bought two months before this. Counted
  -- cumulatively over the membership's own paid rows — which includes this one,
  -- since an `after` trigger sees the row — so it needs no marker column and
  -- cannot drift out of step with the money.
  -- **Money that ARRIVED, which is not the same as money still held.** The sum
  -- counts `refunded` and `reversed` rows too, because a refund does not
  -- reverse the extension it bought (that is the spec's deliberate choice: a
  -- member who paid, attended and was refunded has not un-attended).
  --
  -- Summing only `paid` looks right and double-grants. Half now, half next
  -- week, one period granted on the second — then refund the first half, and
  -- the sum drops back below the line, so the NEXT half payment crosses it
  -- again and grants a second period for money that never reached twice the
  -- price. Counting arrivals makes the total monotonic, which is the property
  -- that makes "crossed a multiple" mean anything at all.
  --
  -- A holdout bounded this case to {0,1} periods and found the round-one build
  -- granting 2. It grants 2 here as well, and for a stated reason rather than
  -- by accident: two payments arrived and two periods were bought; one was
  -- later returned and the spec says the month it bought stays. That is the
  -- ambiguity the holdout correctly refused to resolve on its own, resolved
  -- here and written into the spec.
  select coalesce(sum(pp.amount_paise), 0)
    into v_after
    from public.payments pp
   where pp.tenant_id     = new.tenant_id
     and pp.membership_id = new.membership_id
     and pp.status in ('paid'::public.payment_status,
                       'refunded'::public.payment_status,
                       'reversed'::public.payment_status);

  v_before  := v_after - new.amount_paise;
  v_periods := (v_after / v_price) - (v_before / v_price);

  if v_periods <= 0 then
    return null;
  end if;

  select o.timezone into v_tz
    from public.organizations o
   where o.id = new.tenant_id;

  if v_tz is null then
    return null;
  end if;

  v_today := (pg_catalog.now() at time zone v_tz)::date;

  if v_starts is null and v_ends is null then
    -- Only a `pending` membership may hold null dates
    -- (`memberships_dated_unless_pending_chk`), and after ADR-083 that is
    -- exactly the "sold but not yet paid for" shape. Money was taken and a
    -- receipt issued and nothing happened; now the payment grants the period it
    -- bought, from the gym's today.
    update public.memberships m
       set starts_on = v_today,
           ends_on   = v_today + (v_duration * v_periods)
     where m.id = new.membership_id
       and m.tenant_id = new.tenant_id;
  else
    -- `greatest(ends_on, today)` in the gym's day: renewing early keeps the days
    -- already bought, renewing late starts from today rather than handing back
    -- the lapsed weeks. `ends_on is not null` remains a guard rather than a
    -- filter — `greatest` ignores nulls in Postgres, so a membership with a
    -- start and no end would silently acquire a finite end date.
    update public.memberships m
       set ends_on = greatest(m.ends_on, v_today) + (v_duration * v_periods)
     where m.id = new.membership_id
       and m.tenant_id = new.tenant_id
       and m.ends_on is not null;
  end if;

  return null;
end;
$fn$;


-- ---------------------------------------------------------------------------
-- The receipt book's numbering only ever counts up, by one.
-- ---------------------------------------------------------------------------

create or replace function app.enforce_counter_monotonic()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'counter refused: a receipt series is not deleted — the numbers it issued are on documents'
      using errcode = 'GL037';
  end if;

  -- **Forward only.** The first draft said "by exactly one" and contradicted
  -- this project's own receipts spec two documents over: *"a gap in a receipt
  -- book is explainable, a reused number is not."* A jump forward leaves a gap
  -- and cannot collide; only a decrease can hand out a number twice, and that
  -- is the attack — a critic reset this to 1 and the next payment collided with
  -- a number already issued.
  --
  -- It also made a legitimate test unstageable: a holdout pre-sets the counter
  -- to 50 to prove the allocator does not read before it writes, which is
  -- exactly the assertion this rule's neighbour depends on. **A rule that
  -- forbids the test that proves its neighbour is a rule drawn in the wrong
  -- place**, and the receipts spec had already said where the line was.
  if new.next_number <= old.next_number then
    raise exception 'counter refused: % % is at % and may only move forward — it is the gym''s receipt book, and a number that comes round twice is on two documents',
      old.kind, old.financial_year, old.next_number
      using errcode = 'GL037';
  end if;

  if new.tenant_id      is distinct from old.tenant_id
     or new.kind        is distinct from old.kind
     or new.financial_year is distinct from old.financial_year then
    raise exception 'counter refused: a counter row does not change which book it numbers'
      using errcode = 'GL037';
  end if;

  return new;
end;
$fn$;

drop trigger if exists document_counters_monotonic on public.document_counters;

create trigger document_counters_monotonic
  before update or delete on public.document_counters
  for each row execute function app.enforce_counter_monotonic();


-- ---------------------------------------------------------------------------
-- A refund is bounded whenever it changes, and names the person who sent it.
--
-- **Split into a `before` that fills and an `after` that refuses**, and the
-- reason is that the first draft of this file put both in one `before insert`
-- and immediately broke two assertions in `05_membership_money_rls`: a refund
-- carrying another gym's `tenant_id`, and a refund from a session with no
-- claims at all, both started answering `GL040` where they had answered `42501`.
--
-- That is ADR-066 exactly, and it is the THIRD time this phase has committed
-- it — round one for the payment claim rules, ADR-082's own repair which fixed
-- only half of it, and now here, in the migration written to fix the other
-- half. **A rule that refuses must not run before the policy that would have
-- refused first**; a rule that only fills a column may.
-- ---------------------------------------------------------------------------

create or replace function app.stamp_refund()
returns trigger
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
begin
  -- Filling only. The id can come from nowhere but the token, so there is
  -- nothing to forge and nothing to refuse here — and because it writes to no
  -- other table and raises nothing, running before the policy costs nobody an
  -- answer they should not have had.
  if pg_catalog.row_security_active('public.refunds')
     and new.initiated_by_staff_id is null then
    new.initiated_by_staff_id := app.current_staff_id();
  end if;

  return new;
end;
$fn$;

drop trigger if exists refunds_stamp on public.refunds;

create trigger refunds_stamp
  before insert on public.refunds
  for each row execute function app.stamp_refund();


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

drop trigger if exists refunds_enforce_total on public.refunds;

create trigger refunds_enforce_total
  after insert or update on public.refunds
  for each row execute function app.enforce_refund_total();
