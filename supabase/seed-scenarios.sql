-- supabase/seed-scenarios.sql — retention-loop scenario data (Phase 3, gate 11).
--
-- Applied by .github/workflows/seed.yml, immediately after supabase/seed.sql,
-- in the same `supabase db query --linked` dispatch (ADR-034). Never part of
-- the migration stream (ADR-030). Manual dispatch only:
--   gh workflow run seed.yml -R OGUN01/gymloop
--
-- WHY THIS FILE EXISTS (openspec/changes/phase-3-core-domain/specs/
-- demo-scenarios/spec.md). supabase/seed.sql gives one gym, thirty members,
-- every one of them `active` with an `active` membership and six weeks of
-- attendance — a world with nothing to detect, because nothing in it is
-- lapsed, paused, overdue or streaky. This file adds the missing cases,
-- additively, to the same demo gym (tenant '00000001-0000-4000-8000-000000000001').
-- The existing thirty members and every row seed.sql creates are untouched.
--
-- UUID NAMESPACE. Same scheme as seed.sql (<table-namespace>-0000-4000-8000-
-- <row index>), but every row index here is >= 101 — a range that can never
-- collide with seed.sql's 1-30. Namespaces reused: 05 members, 06 memberships,
-- 08 attendance. One new namespace: 23 membership_pauses (seed.sql never
-- writes that table — Phase 1 left it empty deliberately, since pausing is an
-- action a later phase performs; this file is that later phase's demo data).
--
-- IDEMPOTENCY (gate 11, ADR-034, spec requirement "additive and idempotent").
-- Every insert keys on a deterministic uuid and upserts with `on conflict …
-- do update`; re-running converges instead of duplicating. Dates are computed
-- from `(now() at time zone 'Asia/Kolkata')::date` (`=today_ist`,
-- docs/data-model.md — current_date is wrong because every Supabase session
-- is UTC), never baked in, so a later re-run re-converges the dates rather
-- than accumulating rows. The two long-history members (112, 113) use a
-- 196-day window — exactly 28 calendar weeks — specifically so the count of
-- Sundays inside it is always 28 regardless of which weekday "today" happens
-- to fall on; a window that wasn't a whole number of weeks would make the
-- row count of a re-run one row off on the day the run crosses a week
-- boundary from where the previous run left off. Every other date grid here
-- is pure day-offset arithmetic (no real-calendar weekday dependency), so it
-- has no such wobble at all, matching seed.sql's own attendance grid.
--
-- Money is integer paise in bigint, never a decimal rupee value (MNY-001).
-- Phone numbers use the +9198766##### block — one digit off seed.sql's
-- +9198765##### block — so the two ranges can never collide (members.phone
-- is unique per gym).
--
-- ---------------------------------------------------------------------------
-- SCENARIO MEMBERS — one row per named member, so a reader (or a test) can
-- say "the member with the approved pause" instead of "member 101".
--
--   101 Deepak Rane      — member_status=paused, membership=frozen. Carries an
--                          APPROVED membership_pauses row covering today and a
--                          last visit 30 days back (past the gym's 7-day
--                          no-show threshold). Covers two member_status/
--                          membership_status enum values AND the "approved
--                          pause is not a churn candidate" trap: a no-show
--                          scan that only checks last-visit age would
--                          wrongly red-list this member.
--   102 Sunita Bhosale    — member_status=expired, membership=expired.
--   103 Imran Sheikh      — member_status=cancelled, membership=cancelled.
--   104 Kavita Naik       — member_status=blocked, membership=pending (signed
--                          up, never paid, then blocked — starts_on/ends_on
--                          both null per memberships_dated_unless_pending_chk).
--   105 Farah Contractor  — membership ends in PAY-001 window -14 (14 days
--                          before expiry: ends_on = today + 14).
--   106 Vivek Ranadive    — window -7  (ends_on = today + 7).
--   (window -3 is already occupied by the *existing* seed member IB003 /
--    Rohan Kulkarni, whose ends_on = today + 3 by seed.sql's own formula for
--    member index 3 — no new row needed; see the verification block.)
--   107 Naina Kapadia     — window 0   (ends_on = today, expiry is today).
--   108 Suresh Bhatia     — window +3  (ends_on = today - 3, 3 days overdue,
--                          still `active` — the post-expiry grace reminder).
--   116 Priyanka Rawal    — window -1  (ends_on = today + 1). This gym's own
--                          `organization_settings.renewal_reminder_days_from_
--                          expiry` is `{-7,-3,-1,3}`, not PAY-001's platform
--                          default `{-14,-7,-3,0,3}` — a reminder run reads
--                          THIS gym's array, and -1 is the one window in it
--                          that PAY-001's literal list does not cover. Without
--                          this member, the one window unique to how this gym
--                          is actually configured has nobody sitting in it.
--   109 Anjali Deshmukh   — last visit 6 days ago: one day SHORT of the
--                          7-day no-show threshold (just inside).
--   110 Ravi Chandran     — last visit 8 days ago: one day PAST the threshold
--                          (just outside). Also carries a REJECTED
--                          membership_pauses row covering today, proving a
--                          rejected pause does not exempt a member — this one
--                          SHOULD still read as a churn candidate.
--   111 Meenal Joshi      — zero attendance rows: never visited at all.
--   112 Om Prakash Yadav  — visits every day for the last 196 days except
--                          Sundays, and has Sunday configured as a rest day
--                          (rest_days = {0}) — STK-002: an unbroken streak.
--                          Also the six-month-history member (196-day span).
--   113 Geeta Subramaniam — the identical 196-day, Sundays-off visit pattern
--                          as member 112, but rest_days = {} (none
--                          configured) — the contrasting case whose streak
--                          reads differently from 112's despite identical gaps.
--   114 Salman Ansari     — daily visits with a 5-day gap (day_offset 16-20)
--                          bridged by an APPROVED membership_pauses row that
--                          exactly covers the gap — STK-002: streak unbroken.
--   115 Rekha Nair        — the identical daily-visits-with-a-5-day-gap
--                          pattern as member 114, but with no pause and no
--                          rest day covering the gap — a genuinely broken
--                          streak, the contrasting case to 114.
--
-- Requirement coverage:
--   "every member/membership status"        -> 101-104 (+ existing active/active)
--   "a member in each PAY-001 window"        -> 105-108, 116 (+ existing IB003
--                                               for -3) — covers the union of
--                                               PAY-001's defaults and this
--                                               gym's configured array, see
--                                               the verification block below.
--   "churn candidates either side of the
--    threshold, and one who never visited"   -> 109, 110, 111
--   "a paused member is not a churn
--    candidate" / "a rejected pause is not
--    a pause"                                -> 101, 110
--   "streaks: rest-day, pause-bridged and
--    genuinely broken, distinguishable"      -> 112, 113, 114, 115
--   "six months of history"                  -> 112 / 113 (196-day span)
--   "idempotent and additive"                -> whole file (on conflict do
--                                               update; nothing in seed.sql
--                                               is touched)
-- ---------------------------------------------------------------------------


-- ---------------------------------------------------------------------------
-- 1. Sixteen scenario members.
-- ---------------------------------------------------------------------------

with roster as (
  select * from (values
    (101, 'Deepak Rane',        'male'),
    (102, 'Sunita Bhosale',     'female'),
    (103, 'Imran Sheikh',       'male'),
    (104, 'Kavita Naik',        'female'),
    (105, 'Farah Contractor',   'female'),
    (106, 'Vivek Ranadive',     'male'),
    (107, 'Naina Kapadia',      'female'),
    (108, 'Suresh Bhatia',      'male'),
    (109, 'Anjali Deshmukh',    'female'),
    (110, 'Ravi Chandran',      'male'),
    (111, 'Meenal Joshi',       'female'),
    (112, 'Om Prakash Yadav',   'male'),
    (113, 'Geeta Subramaniam',  'female'),
    (114, 'Salman Ansari',      'male'),
    (115, 'Rekha Nair',         'female'),
    (116, 'Priyanka Rawal',     'female')
  ) as v(n, full_name, gender)
),
meta as (
  select * from (values
    -- n,   member_status,  joined_offset
    (101, 'paused',    -67),
    (102, 'expired',   -77),
    (103, 'cancelled', -27),
    (104, 'blocked',    -3),
    (105, 'active',    -23),
    (106, 'active',    -30),
    (107, 'active',    -37),
    (108, 'active',    -40),
    (109, 'active',    -77),
    (110, 'active',    -77),
    (111, 'active',    -77),
    (112, 'active',   -211),
    (113, 'active',   -211),
    (114, 'active',    -47),
    (115, 'active',    -47),
    (116, 'active',    -36)
  ) as v(n, member_status, joined_offset)
),
today as (select (now() at time zone 'Asia/Kolkata')::date as d)
insert into public.members (
  id, tenant_id, branch_id, member_code, full_name, phone, email, gender,
  date_of_birth, status, joined_on, weekly_goal_visits, rest_days,
  motivation_push_enabled
)
select
  ('00000005-0000-4000-8000-' || lpad(r.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  '00000002-0000-4000-8000-000000000001'::uuid,
  'IB' || r.n::text,
  r.full_name,
  '+9198766' || lpad(r.n::text, 5, '0'),
  lower(regexp_replace(r.full_name, '[^A-Za-z]+', '.', 'g')) || '@example.com',
  r.gender,
  date '1985-01-01' + ((r.n - 100) * 83),
  m.member_status::public.member_status,
  t.d + m.joined_offset,
  3::smallint,
  case when r.n = 112 then '{0}'::smallint[] else '{}'::smallint[] end,
  true
from roster r
join meta m on m.n = r.n
cross join today t
on conflict (id) do update set
  branch_id               = excluded.branch_id,
  member_code             = excluded.member_code,
  full_name               = excluded.full_name,
  phone                   = excluded.phone,
  email                   = excluded.email,
  gender                  = excluded.gender,
  date_of_birth           = excluded.date_of_birth,
  status                  = excluded.status,
  joined_on               = excluded.joined_on,
  weekly_goal_visits      = excluded.weekly_goal_visits,
  rest_days               = excluded.rest_days,
  motivation_push_enabled = excluded.motivation_push_enabled;


-- ---------------------------------------------------------------------------
-- 2. Sixteen memberships — one live (or pending/expired/cancelled) row per
--    scenario member. starts/ends offsets are chosen so ends_on - starts_on
--    equals the chosen plan's duration_days, same convention as seed.sql.
--    Plan ids: 1 Monthly (30d), 2 Quarterly (90d), 4 Annual (365d).
-- ---------------------------------------------------------------------------

with roster as (
  select * from (values
    -- n,   plan_no, status,       starts_offset, ends_offset (null = pending)
    (101, 2, 'frozen',    -60,   30),
    (102, 1, 'expired',   -70,  -40),
    (103, 1, 'cancelled', -20,   10),
    (104, 1, 'pending',  null, null),
    (105, 1, 'active',   -16,   14),
    (106, 1, 'active',   -23,    7),
    (107, 1, 'active',   -30,    0),
    (108, 1, 'active',   -33,   -3),
    (109, 2, 'active',   -70,   20),
    (110, 2, 'active',   -70,   20),
    (111, 2, 'active',   -70,   20),
    (112, 4, 'active',  -206,  159),
    (113, 4, 'active',  -206,  159),
    (114, 2, 'active',   -40,   50),
    (115, 2, 'active',   -40,   50),
    (116, 1, 'active',   -29,    1)
  ) as v(n, plan_no, status, starts_offset, ends_offset)
),
today as (select (now() at time zone 'Asia/Kolkata')::date as d)
insert into public.memberships (
  id, tenant_id, member_id, plan_id, status, starts_on, ends_on,
  price_paise, discount_paise, currency, coupon_id,
  renewal_of_membership_id, activated_at, cancelled_at, cancel_reason
)
select
  ('00000006-0000-4000-8000-' || lpad(r.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  ('00000005-0000-4000-8000-' || lpad(r.n::text, 12, '0'))::uuid,
  p.id,
  r.status::public.membership_status,
  case when r.starts_offset is null then null else t.d + r.starts_offset end,
  case when r.ends_offset   is null then null else t.d + r.ends_offset   end,
  p.price_paise,
  0,
  'INR',
  null,
  null,
  case when r.starts_offset is null then null
       else ((t.d + r.starts_offset) + time '10:00') at time zone 'Asia/Kolkata' end,
  case when r.status = 'cancelled'
       then ((t.d - 5) + time '17:00') at time zone 'Asia/Kolkata' else null end,
  case when r.status = 'cancelled' then 'Relocated to another city' else null end
from roster r
join public.plans p
  on p.id = ('00000004-0000-4000-8000-' || lpad(r.plan_no::text, 12, '0'))::uuid
cross join today t
on conflict (id) do update set
  member_id                = excluded.member_id,
  plan_id                  = excluded.plan_id,
  status                   = excluded.status,
  starts_on                = excluded.starts_on,
  ends_on                  = excluded.ends_on,
  price_paise              = excluded.price_paise,
  discount_paise           = excluded.discount_paise,
  currency                 = excluded.currency,
  coupon_id                = excluded.coupon_id,
  renewal_of_membership_id = excluded.renewal_of_membership_id,
  activated_at              = excluded.activated_at,
  cancelled_at              = excluded.cancelled_at,
  cancel_reason             = excluded.cancel_reason;


-- ---------------------------------------------------------------------------
-- 3. Three membership_pauses rows.
--      101 — approved, covers today, on member 101's frozen membership.
--      110 — rejected, would have covered today had it been approved
--            (proves NSH-002's exclusion is about *approved* pauses only).
--      114 — approved, covers exactly the 5-day attendance gap (day_offset
--            16-20) on member 114's membership — STK-002's pause-bridged
--            streak case.
--    **Front desk requests; the owner approves.** Two people, which is the
--    whole point of the rule — the approver may not be the requester, and the
--    approver must hold the gym's configured `pause_approver_role`.
--
--    This comment used to say the gym's setting was `gym_manager` with no
--    `gym_manager` staff row, calling that "a known oddity of the seeded staff
--    list, not a gap here". It was a gap. Nobody could approve a freeze in the
--    only gym that exists: the Approve button rendered for every front-office
--    viewer and always answered `not_approver`, so the rule four critic rounds
--    were spent hardening had never once been exercised through the product.
--    A blind critic found it, and it is the fifth time this phase that a
--    confident sentence stopped the next person looking. `seed.sql` now
--    configures `gym_owner`, a role this gym actually employs.
-- ---------------------------------------------------------------------------

with today as (select (now() at time zone 'Asia/Kolkata')::date as d)
insert into public.membership_pauses (
  id, tenant_id, membership_id, starts_on, ends_on, reason,
  requested_by_staff_id, approved_by_staff_id, approved_at, rejected_at
)
select
  ('00000023-0000-4000-8000-' || lpad(x.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  ('00000006-0000-4000-8000-' || lpad(x.membership_no::text, 12, '0'))::uuid,
  t.d + x.starts_offset,
  t.d + x.ends_offset,
  x.reason,
  '00000003-0000-4000-8000-000000000004'::uuid,
  -- The OWNER approves, not the front desk that asked. `enforce_pause_decision`
  -- exempts `postgres`, so the seed could write anything here -- which is
  -- exactly why it should write what the rules would have produced. Demo data
  -- that a live session could not have created is a rule nobody sees fail.
  -- An approver ONLY where there is an approval. This row used to name one on
  -- the rejected pause too, which is the exact shape the third critic round
  -- found reachable through the product -- our own demo data was carrying the
  -- defect. `membership_pauses_approver_pairs_with_approval_chk` now refuses it.
  case when x.decision = 'approved'
       then '00000003-0000-4000-8000-00000000000f'::uuid
       else null end,
  case when x.decision = 'approved'
       then ((t.d + x.starts_offset - 1) + time '11:00') at time zone 'Asia/Kolkata'
       else null end,
  case when x.decision = 'rejected'
       then ((t.d - 1) + time '11:00') at time zone 'Asia/Kolkata'
       else null end
from (values
  (101, 101, -10,  20, 'Medical',         'approved'),
  (110, 110,  -2,   5, 'Work relocation', 'rejected'),
  (114, 114, -20, -16, 'Travel',          'approved')
) as x(n, membership_no, starts_offset, ends_offset, reason, decision)
cross join today t
on conflict (id) do update set
  membership_id          = excluded.membership_id,
  starts_on               = excluded.starts_on,
  ends_on                 = excluded.ends_on,
  reason                  = excluded.reason,
  requested_by_staff_id   = excluded.requested_by_staff_id,
  approved_by_staff_id    = excluded.approved_by_staff_id,
  approved_at              = excluded.approved_at,
  rejected_at              = excluded.rejected_at;


-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- 3b. Clear this file's own attendance before rewriting it.
--
--     **Without this, a second seed run on a LATER DAY fails.** Every grid
--     below is anchored to `today` and every id encodes `member_no * 1000 +
--     day_offset`, so a run one day later slides the whole grid: the row that
--     was offset 4 yesterday is offset 5 today and carries a different id at
--     the same instant. `app.enforce_check_in()` excuses a row that duplicates
--     ITSELF (`a.id <> new.id`, which is what keeps `seed.sql` re-runnable)
--     and cannot excuse this one, so it raises `GL014` and the seed stops.
--
--     Proven rather than reasoned: for member 112 the next run's offset-5 row
--     lands on the exact instant currently held by id `...112004`, offset-6 on
--     `...112005`, offset-7 on `...112006` — a clean one-place slide, a
--     different id every time.
--
--     It had never been hit because all four previous seed runs happened to be
--     same-day pairs. `seed.yml` called this file "additive and idempotent";
--     across a day boundary it was neither, and the comment asserting a
--     capability the file did not have is this project's most repeated defect
--     shape (ADR-070, ADR-071, ADR-074, ADR-081).
--
--     Deleting is right rather than clever: this file OWNS the attendance of
--     its own sixteen members, regenerates all of it below, and a delete makes
--     the result independent of what any previous run left behind — on any day,
--     after any number of runs. Scoped by the scenario member namespace
--     (`…0000000001xx`, members 101-116), which cannot touch `seed.sql`'s
--     members 1-30.
-- ---------------------------------------------------------------------------

delete from public.attendance
 where tenant_id = '00000001-0000-4000-8000-000000000001'::uuid
   and member_id::text like '00000005-0000-4000-8000-0000000001%';


-- 4. Attendance, part A — the small fixed-offset grids (member 101's single
--    old visit, 109's and 110's few-visit history). All well over a day
--    apart, clear of ATT-004's 120-second de-dup window.
-- ---------------------------------------------------------------------------

with today as (select (now() at time zone 'Asia/Kolkata')::date as d)
insert into public.attendance (
  id, tenant_id, branch_id, member_id, membership_id,
  checked_in_at, checked_out_at, source
)
select
  ('00000008-0000-4000-8000-' || lpad((v.member_no * 1000 + v.day_offset)::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  '00000002-0000-4000-8000-000000000001'::uuid,
  ('00000005-0000-4000-8000-' || lpad(v.member_no::text, 12, '0'))::uuid,
  ('00000006-0000-4000-8000-' || lpad(v.member_no::text, 12, '0'))::uuid,
  ((t.d - v.day_offset) + time '18:30') at time zone 'Asia/Kolkata',
  ((t.d - v.day_offset) + time '19:30') at time zone 'Asia/Kolkata',
  'qr'::public.attendance_source
from (values
  (101, 30),
  (109,  6), (109, 10), (109, 14),
  (110,  8), (110, 12), (110, 16)
) as v(member_no, day_offset)
cross join today t
on conflict (id) do update set
  checked_in_at  = excluded.checked_in_at,
  checked_out_at = excluded.checked_out_at,
  source         = excluded.source;


-- ---------------------------------------------------------------------------
-- 5. Attendance, part B — members 112 and 113: the identical 196-day
--    (exactly 28 weeks), Sundays-off visit grid. 112 has Sunday configured
--    as a rest day; 113 does not — same gaps, different configuration
--    (STK-002's "rest-day case is distinguishable" scenario). Also the
--    six-month-history requirement: the span from day_offset 195 to 0 is
--    195 days.
-- ---------------------------------------------------------------------------

with today as (select (now() at time zone 'Asia/Kolkata')::date as d),
days as (
  select gs.day_offset
  from generate_series(0, 195) as gs(day_offset)
),
members as (select unnest(array[112, 113]) as member_no)
insert into public.attendance (
  id, tenant_id, branch_id, member_id, membership_id,
  checked_in_at, checked_out_at, source
)
select
  ('00000008-0000-4000-8000-' || lpad((m.member_no * 1000 + d.day_offset)::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  '00000002-0000-4000-8000-000000000001'::uuid,
  ('00000005-0000-4000-8000-' || lpad(m.member_no::text, 12, '0'))::uuid,
  ('00000006-0000-4000-8000-' || lpad(m.member_no::text, 12, '0'))::uuid,
  ((t.d - d.day_offset) + time '06:30') at time zone 'Asia/Kolkata',
  ((t.d - d.day_offset) + time '07:30') at time zone 'Asia/Kolkata',
  'qr'::public.attendance_source
from days d
cross join members m
cross join today t
where extract(dow from (t.d - d.day_offset)) <> 0   -- skip real-calendar Sundays
on conflict (id) do update set
  checked_in_at  = excluded.checked_in_at,
  checked_out_at = excluded.checked_out_at,
  source         = excluded.source;


-- ---------------------------------------------------------------------------
-- 6. Attendance, part C — members 114 and 115: identical daily visits across
--    day_offset 0-30 except a 5-day gap at day_offset 16-20. Member 114's gap
--    is exactly covered by the approved membership_pauses row above (a
--    bridged, unbroken streak); member 115 has the same gap with nothing
--    covering it (a genuinely broken streak) — STK-002's contrast pair.
-- ---------------------------------------------------------------------------

with today as (select (now() at time zone 'Asia/Kolkata')::date as d),
days as (
  select gs.day_offset
  from generate_series(0, 30) as gs(day_offset)
  where gs.day_offset not between 16 and 20
),
members as (select unnest(array[114, 115]) as member_no)
insert into public.attendance (
  id, tenant_id, branch_id, member_id, membership_id,
  checked_in_at, checked_out_at, source
)
select
  ('00000008-0000-4000-8000-' || lpad((m.member_no * 1000 + d.day_offset)::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  '00000002-0000-4000-8000-000000000001'::uuid,
  ('00000005-0000-4000-8000-' || lpad(m.member_no::text, 12, '0'))::uuid,
  ('00000006-0000-4000-8000-' || lpad(m.member_no::text, 12, '0'))::uuid,
  ((t.d - d.day_offset) + time '18:45') at time zone 'Asia/Kolkata',
  ((t.d - d.day_offset) + time '19:45') at time zone 'Asia/Kolkata',
  'qr'::public.attendance_source
from days d
cross join members m
cross join today t
on conflict (id) do update set
  checked_in_at  = excluded.checked_in_at,
  checked_out_at = excluded.checked_out_at,
  source         = excluded.source;


-- ---------------------------------------------------------------------------
-- VERIFICATION — one query per requirement. Run after applying, read-only.
-- These were run against the current database while writing this file to
-- confirm they are well-formed SQL (they returned rows consistent with only
-- the existing seed.sql data, since this file had not been applied yet).
-- ---------------------------------------------------------------------------

-- Requirement 1: every member_status and membership_status value is present.
-- select array_agg(distinct status order by status) as member_statuses
-- from public.members where tenant_id = '00000001-0000-4000-8000-000000000001';
-- -- expect: {active,paused,expired,cancelled,blocked}
--
-- select array_agg(distinct status order by status) as membership_statuses
-- from public.memberships where tenant_id = '00000001-0000-4000-8000-000000000001';
-- -- expect: {pending,active,frozen,expired,cancelled}

-- Requirement 2: a member ending in each window that matters — the UNION of
-- PAY-001's platform default (-14,-7,-3,0,+3) and this gym's own configured
-- renewal_reminder_days_from_expiry (-7,-3,-1,+3), not the PAY-001 list
-- alone. PAY-001's defaults are what a gym gets before it configures
-- anything; a reminder run reads the gym's actual array, and this demo gym
-- has overridden it. Asserting only the platform defaults would leave -1 —
-- the one window unique to this gym's configuration — untested, which is
-- exactly the code path a reminder run against this gym takes.
-- select ((now() at time zone 'Asia/Kolkata')::date - ends_on) as days_from_expiry,
--        count(*)
-- from public.memberships
-- where tenant_id = '00000001-0000-4000-8000-000000000001' and status = 'active'
-- group by 1
-- having ((now() at time zone 'Asia/Kolkata')::date - ends_on) in (-14,-7,-3,-1,0,3)
-- order by 1;
-- -- expect six rows, one per offset

-- Requirement 3: churn boundary members and a never-visited member.
-- select m.member_code, m.full_name,
--        (now() at time zone 'Asia/Kolkata')::date - max(a.checked_in_at::date) as days_since_last_visit
-- from public.members m
-- join public.attendance a on a.member_id = m.id
-- where m.tenant_id = '00000001-0000-4000-8000-000000000001'
--   and m.member_code in ('IB109', 'IB110')
-- group by m.member_code, m.full_name;
-- -- expect IB109 = 6 (one day short of the 7-day threshold), IB110 = 8 (one day past)
--
-- select member_code, full_name from public.members m
-- where tenant_id = '00000001-0000-4000-8000-000000000001' and member_code = 'IB111'
--   and not exists (select 1 from public.attendance a where a.member_id = m.id);
-- -- expect one row: Meenal Joshi, never visited

-- Requirement 4: an approved pause exempts, a rejected pause does not.
-- select mp.id, mp.starts_on, mp.ends_on, mp.approved_at, mp.rejected_at,
--        m.full_name, (now() at time zone 'Asia/Kolkata')::date - max(a.checked_in_at::date) as days_absent
-- from public.membership_pauses mp
-- join public.memberships ms on ms.id = mp.membership_id
-- join public.members m on m.id = ms.member_id
-- left join public.attendance a on a.member_id = m.id
-- where mp.tenant_id = '00000001-0000-4000-8000-000000000001' and m.member_code = 'IB101'
-- group by mp.id, mp.starts_on, mp.ends_on, mp.approved_at, mp.rejected_at, m.full_name;
-- -- expect approved_at set, rejected_at null, starts_on <= today <= ends_on, days_absent > 7
--
-- select mp.approved_at, mp.rejected_at from public.membership_pauses mp
-- join public.memberships ms on ms.id = mp.membership_id
-- join public.members m on m.id = ms.member_id
-- where m.member_code = 'IB110';
-- -- expect approved_at null, rejected_at set

-- Requirement 5: the rest-day case is distinguishable from the no-rest-day case,
-- and the pause-bridged case from the genuinely broken one.
-- select m.member_code, m.rest_days, array_agg(a.checked_in_at::date order by a.checked_in_at) as visit_dates
-- from public.members m
-- join public.attendance a on a.member_id = m.id
-- where m.member_code in ('IB112', 'IB113')
-- group by m.member_code, m.rest_days;
-- -- expect identical visit_dates for both rows, rest_days = {0} for IB112 and {} for IB113
--
-- select m.member_code,
--        exists (
--          select 1 from public.membership_pauses mp
--          join public.memberships ms on ms.id = mp.membership_id
--          where ms.member_id = m.id and mp.approved_at is not null
--        ) as has_approved_pause
-- from public.members m
-- where m.member_code in ('IB114', 'IB115');
-- -- expect true for IB114, false for IB115, with identical attendance gaps otherwise

-- Requirement 6: at least 180 days between earliest and latest attendance.
-- select max(checked_in_at::date) - min(checked_in_at::date) as span_days
-- from public.attendance where tenant_id = '00000001-0000-4000-8000-000000000001';
-- -- expect >= 180

-- Requirement 7: idempotent and additive. Not a single query — the actual
-- check is: run this file, record row counts for members/memberships/
-- membership_pauses/attendance filtered to member_code >= 'IB101', run it
-- again, and diff. The existing thirty members (IB001-IB030) and every row
-- seed.sql creates are never touched by this file (no shared uuids, no
-- update to any table outside the four above).
