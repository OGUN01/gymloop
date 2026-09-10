-- supabase/seed.sql — the demo gym (Gate 11).
--
-- One command:  gh workflow run seed.yml -R OGUN01/gymloop
-- Applied by .github/workflows/seed.yml as `supabase db query --linked -f`,
-- manual dispatch only (ADR-034). Never part of the migration stream (ADR-030).
--
-- Shape, from docs/data-model.md § What Phase 1 must produce and
-- openspec/changes/0001-data-model/specs/demo-seed/spec.md:
--   one Tier-2 neighbourhood gym · one default branch · 4 active plan tiers ·
--   3 trainers + 1 front-desk staff · 30 members · 6 members absent 10–20 days
--   while holding a live membership · 5 active memberships expiring within 7 days ·
--   PT / diet / supplement add-ons with an add-on order on a verified payment ·
--   leads at 6 distinct stages · attendance dense enough that a 21-day streak and
--   six retention cases are both visible.
--
-- Two rules the whole file is built around:
--
-- 1. IDEMPOTENCY. Every row is anchored on a deterministic uuid of the form
--    <table-namespace>-0000-4000-8000-<row index>, and every insert is
--    `on conflict (…) do update`. Re-running converges on the same demo gym; it
--    never duplicates it and never trips a unique constraint. The namespaces:
--      01 organizations   02 branches       03 staff          04 plans
--      05 members         06 memberships    07 payments       08 attendance
--      09 addon_products  10 addon_orders   11 pt_sessions    12 leads
--      13 no_show_cases   14 follow_ups     15 coupons        16 consents
--      17 member_devices  18 notifications  19 message_templates
--      20 qr_sessions     21 organization_holidays  22 messaging_wallet_ledger
--
-- 2. TODAY IS COMPUTED, NOT BAKED IN. Every date that is meaningful relative to
--    now is `(now() at time zone 'Asia/Kolkata')::date + <offset>` — the same
--    expression the schema's own `=today_ist` defaults use (ADR-039; `current_date`
--    is wrong because every Supabase session is UTC). The offsets are fixed, so a
--    re-run a month later re-converges the dates rather than accumulating rows.
--    Where an offset-shifted value sits under a unique or exclusion constraint,
--    the row carries a second discriminator that never shifts, so a re-run can
--    never collide row A's new value with row B's old one: the five demo PT
--    sessions are at five different hours of the day, and the two holidays are
--    fixed calendar dates within the current year rather than day offsets.
--
-- The seed runs as the CLI's `postgres` session, which bypasses RLS. That is
-- exactly why every row below sets `tenant_id` explicitly rather than relying on
-- a policy to supply it.
--
-- Money is integer paise in bigint, never a decimal rupee value (MNY-001).
-- Deliberately NOT seeded, and why:
--   auth.users, staff.user_id, members.user_id, platform_users,
--   impersonation_sessions — a seed cannot create Supabase Auth identities.
--   razorpay_accounts, razorpay_mandates — the key columns hold Supabase Vault
--     secret ids; inventing uuids for secrets that do not exist would be a lie.
--   webhook_events, invoices, document_counters, refunds,
--   membership_pauses, attendance_corrections, member_imports — Phase 1 owns
--     shape, not behaviour; these tables are written by the phase that performs
--     the action, and an empty table is their correct Phase-1 state.
-- Audit rows are not inserted manually here. Financial INSERT/UPDATE triggers
-- now record accepted seed payment writes; ON CONFLICT DO NOTHING replays add
-- neither payment rows nor financial audit events.


-- ---------------------------------------------------------------------------
-- 1. The organisation — one Tier-2 neighbourhood gym.
-- ---------------------------------------------------------------------------

insert into public.organizations
  (id, name, gym_code, status, tier, activated_at, timezone, currency)
values (
  '00000001-0000-4000-8000-000000000001',
  'Iron Box Fitness — Vijay Nagar',
  'IRNBX1',
  'active',
  'tier_2',
  now() - interval '18 months',
  'Asia/Kolkata',
  'INR'
)
on conflict (id) do update set
  name         = excluded.name,
  gym_code     = excluded.gym_code,
  status       = excluded.status,
  tier         = excluded.tier,
  activated_at = excluded.activated_at,
  timezone     = excluded.timezone,
  currency     = excluded.currency;


-- ---------------------------------------------------------------------------
-- 2. The per-gym template (docs/data-model.md § Per-gym configuration).
-- ---------------------------------------------------------------------------

insert into public.organization_settings (
  tenant_id, preset, brand_accent,
  address_line1, address_line2, city, state, pincode, gstin,
  invoice_prefix, receipt_prefix, financial_year_start_month, week_start_day,
  opening_hours, no_show_threshold_days, checkin_dedupe_seconds,
  streak_rule_type, weekly_goal_default, renewal_reminder_days_from_expiry,
  grace_period_days, pause_reasons, pause_approver_role,
  max_freeze_days_per_year, trainer_member_cap
)
values (
  '00000001-0000-4000-8000-000000000001',
  'neighbourhood_gym',
  '#0f766e',
  '2nd Floor, Shanti Plaza',
  'Scheme 54, Vijay Nagar',
  'Indore',
  'Madhya Pradesh',
  '452010',
  '23ABCDE1234F1Z5',
  'INV',
  'RCPT',
  4,   -- Indian financial year starts in April
  1,   -- weeks start on Monday
  jsonb_build_object(
    'mon', jsonb_build_array('05:30-11:00', '16:00-22:00'),
    'tue', jsonb_build_array('05:30-11:00', '16:00-22:00'),
    'wed', jsonb_build_array('05:30-11:00', '16:00-22:00'),
    'thu', jsonb_build_array('05:30-11:00', '16:00-22:00'),
    'fri', jsonb_build_array('05:30-11:00', '16:00-22:00'),
    'sat', jsonb_build_array('06:00-11:00', '16:00-21:00'),
    'sun', jsonb_build_array('07:00-11:00')
  ),
  7,    -- a member absent 7 days opens a no-show case
  120,  -- ATT-004 de-duplication window, seconds
  'visit_streak',
  3,
  '{-7,-3,-1,3}'::smallint[],  -- PAY-001 axis: negative before expiry, positive after
  5,
  array['Medical', 'Travel', 'Work relocation', 'Exam preparation']::text[],
  -- `gym_owner`, not the column's `gym_manager` default, and the reason is
  -- worth the four lines. This gym has no `gym_manager` staff row -- a
  -- neighbourhood gym in Indore genuinely does not have one -- so configuring
  -- that role left the demo with **nobody able to approve a freeze**. The
  -- Approve button rendered for every front-office viewer and always answered
  -- `not_approver`, and the pause decision is the rule four critic rounds were
  -- spent hardening. A setting naming a role the gym does not employ is a
  -- silent misconfiguration ADR-065 narrowed the constraint to catch, and this
  -- is the same mistake one level up: legal by the constraint, useless in fact.
  --
  -- Front desk requests, the owner approves: two people, which is the whole
  -- point of the rule, and now exercisable through the product.
  'gym_owner',
  30,
  40
)
on conflict (tenant_id) do update set
  preset                            = excluded.preset,
  brand_accent                      = excluded.brand_accent,
  address_line1                     = excluded.address_line1,
  address_line2                     = excluded.address_line2,
  city                              = excluded.city,
  state                             = excluded.state,
  pincode                           = excluded.pincode,
  gstin                             = excluded.gstin,
  invoice_prefix                    = excluded.invoice_prefix,
  receipt_prefix                    = excluded.receipt_prefix,
  financial_year_start_month        = excluded.financial_year_start_month,
  week_start_day                    = excluded.week_start_day,
  opening_hours                     = excluded.opening_hours,
  no_show_threshold_days            = excluded.no_show_threshold_days,
  checkin_dedupe_seconds            = excluded.checkin_dedupe_seconds,
  streak_rule_type                  = excluded.streak_rule_type,
  weekly_goal_default               = excluded.weekly_goal_default,
  renewal_reminder_days_from_expiry = excluded.renewal_reminder_days_from_expiry,
  grace_period_days                 = excluded.grace_period_days,
  pause_reasons                     = excluded.pause_reasons,
  pause_approver_role               = excluded.pause_approver_role,
  max_freeze_days_per_year          = excluded.max_freeze_days_per_year,
  trainer_member_cap                = excluded.trainer_member_cap;


-- ---------------------------------------------------------------------------
-- 3. The one default branch.
-- ---------------------------------------------------------------------------

insert into public.branches (id, tenant_id, name, address, timezone, is_default)
values (
  '00000002-0000-4000-8000-000000000001',
  '00000001-0000-4000-8000-000000000001',
  'Vijay Nagar',
  '2nd Floor, Shanti Plaza, Scheme 54, Vijay Nagar, Indore 452010',
  null,
  true
)
on conflict (id) do update set
  name       = excluded.name,
  address    = excluded.address,
  timezone   = excluded.timezone,
  is_default = excluded.is_default;


-- ---------------------------------------------------------------------------
-- 4. Staff — three trainers and one front-desk user (four rows, exactly).
--    user_id stays null: a seed cannot create Supabase Auth identities.
-- ---------------------------------------------------------------------------

insert into public.staff (
  id, tenant_id, branch_id, role, full_name, phone, email,
  is_active, qualification, max_active_clients
)
select
  ('00000003-0000-4000-8000-' || lpad(s.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  '00000002-0000-4000-8000-000000000001'::uuid,
  s.role::public.app_role,
  s.full_name,
  s.phone,
  s.email,
  true,
  s.qualification,
  s.max_active_clients
from (values
  (1, 'trainer',    'Rohit Sharma',  '+919876511001', 'rohit@ironbox.example.com',
      'ACSM-CPT · 8 years · strength and rehab', 25::smallint),
  (2, 'trainer',    'Meera Iyer',    '+919876511002', 'meera@ironbox.example.com',
      'K11 Level 2 · Sports Nutrition Diploma', 25::smallint),
  (3, 'trainer',    'Arjun Patil',   '+919876511003', 'arjun@ironbox.example.com',
      'ACE-CPT · Strength and Conditioning', 20::smallint),
  (4, 'front_desk', 'Divya Menon',   '+919876511004', 'divya@ironbox.example.com',
      null, null::smallint)
) as s(n, role, full_name, phone, email, qualification, max_active_clients)
on conflict (id) do update set
  branch_id          = excluded.branch_id,
  role               = excluded.role,
  full_name          = excluded.full_name,
  phone              = excluded.phone,
  email              = excluded.email,
  is_active          = excluded.is_active,
  qualification      = excluded.qualification,
  max_active_clients = excluded.max_active_clients;


-- ---------------------------------------------------------------------------
-- 5. Four active plan tiers. Prices are integer paise: 1500 / 4000 / 7000 /
--    12000 rupees. GST 18% is 1800 basis points.
-- ---------------------------------------------------------------------------

insert into public.plans (
  id, tenant_id, name, description, duration_days, price_paise, currency,
  gst_rate_bp, max_freeze_days, is_active, sort_order
)
select
  ('00000004-0000-4000-8000-' || lpad(p.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  p.name,
  p.description,
  p.duration_days,
  p.price_paise,
  'INR',
  1800::smallint,
  p.max_freeze_days,
  true,
  p.n::smallint
from (values
  (1, 'Monthly',     'Gym floor + cardio, month to month.',              30,   150000::bigint,  0::smallint),
  (2, 'Quarterly',   'Three months, one free week of freeze.',           90,   400000::bigint,  7::smallint),
  (3, 'Half-Yearly', 'Six months, includes a quarterly body check.',     180,  700000::bigint, 15::smallint),
  (4, 'Annual',      'Twelve months, best value, one month of freeze.',  365, 1200000::bigint, 30::smallint)
) as p(n, name, description, duration_days, price_paise, max_freeze_days)
on conflict (id) do update set
  name            = excluded.name,
  description     = excluded.description,
  duration_days   = excluded.duration_days,
  price_paise     = excluded.price_paise,
  currency        = excluded.currency,
  gst_rate_bp     = excluded.gst_rate_bp,
  max_freeze_days = excluded.max_freeze_days,
  is_active       = excluded.is_active,
  sort_order      = excluded.sort_order;


-- ---------------------------------------------------------------------------
-- 6. One coupon — carries exactly one kind of discount (percent, not flat).
-- ---------------------------------------------------------------------------

insert into public.coupons (
  id, tenant_id, code, percent_bp, flat_paise, currency,
  valid_from, valid_until, max_redemptions, redeemed_count,
  applies_to_plans, applies_to_addons, is_active
)
select
  '00000015-0000-4000-8000-000000000001'::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  'NEWYEAR10',
  1000,   -- 10% in basis points
  null,
  'INR',
  ((t.d - 60) + time '00:00') at time zone 'Asia/Kolkata',
  ((t.d + 120) + time '23:59') at time zone 'Asia/Kolkata',
  50,
  1,
  true,
  false,
  true
from (select (now() at time zone 'Asia/Kolkata')::date as d) t
on conflict (id) do update set
  code              = excluded.code,
  percent_bp        = excluded.percent_bp,
  flat_paise        = excluded.flat_paise,
  currency          = excluded.currency,
  valid_from        = excluded.valid_from,
  valid_until       = excluded.valid_until,
  max_redemptions   = excluded.max_redemptions,
  redeemed_count    = excluded.redeemed_count,
  applies_to_plans  = excluded.applies_to_plans,
  applies_to_addons = excluded.applies_to_addons,
  is_active         = excluded.is_active;


-- ---------------------------------------------------------------------------
-- 7. The add-on catalogue — PT packages, a diet plan and two products.
--    ADD-002: a pt_package must carry session_count, a product must carry
--    stock_quantity, a diet_plan needs neither. Stock is never negative (DQA-004).
-- ---------------------------------------------------------------------------

insert into public.addon_products (
  id, tenant_id, kind, name, description, price_paise, currency, gst_rate_bp,
  validity_days, session_count, trainer_staff_id, stock_quantity,
  cancellation_terms, is_active, sort_order
)
select
  ('00000009-0000-4000-8000-' || lpad(a.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  a.kind::public.addon_kind,
  a.name,
  a.description,
  a.price_paise,
  'INR',
  1800::smallint,
  a.validity_days,
  a.session_count,
  case when a.trainer_no is null then null
       else ('00000003-0000-4000-8000-' || lpad(a.trainer_no::text, 12, '0'))::uuid
  end,
  a.stock_quantity,
  a.cancellation_terms,
  true,
  a.n::smallint
from (values
  (1, 'pt_package', 'PT Starter — 12 Sessions',
      'Twelve one-hour personal training sessions with Rohit.',
      800000::bigint, 90, 12, 1, null::integer,
      'Unused sessions lapse at expiry. Cancel 12 hours ahead or the session is consumed.'),
  (2, 'pt_package', 'PT Transform — 24 Sessions',
      'Twenty-four sessions with Meera, includes a nutrition review every month.',
      1500000::bigint, 180, 24, 2, null::integer,
      'Unused sessions lapse at expiry. Cancel 12 hours ahead or the session is consumed.'),
  (3, 'diet_plan', 'Fat-Loss Diet Plan — 8 Weeks',
      'Eight-week Indian-kitchen meal plan with a fortnightly review call.',
      250000::bigint, 56, null::integer, 2, null::integer,
      'Non-refundable once the first plan has been shared.'),
  (4, 'product', 'Whey Protein 1 kg — Chocolate',
      'Imported whey concentrate, 1 kg tub.',
      240000::bigint, null::integer, null::integer, null::integer, 24,
      'Sealed tubs only, within 7 days of purchase.'),
  (5, 'product', 'BCAA 300 g — Lemon',
      'Intra-workout BCAA, 300 g.',
      130000::bigint, null::integer, null::integer, null::integer, 15,
      'Sealed tubs only, within 7 days of purchase.')
) as a(n, kind, name, description, price_paise, validity_days, session_count,
       trainer_no, stock_quantity, cancellation_terms)
on conflict (id) do update set
  kind               = excluded.kind,
  name               = excluded.name,
  description        = excluded.description,
  price_paise        = excluded.price_paise,
  currency           = excluded.currency,
  gst_rate_bp        = excluded.gst_rate_bp,
  validity_days      = excluded.validity_days,
  session_count      = excluded.session_count,
  trainer_staff_id   = excluded.trainer_staff_id,
  stock_quantity     = excluded.stock_quantity,
  cancellation_terms = excluded.cancellation_terms,
  is_active          = excluded.is_active,
  sort_order         = excluded.sort_order;


-- ---------------------------------------------------------------------------
-- 8. Message templates for the two loops the demo has to show.
-- ---------------------------------------------------------------------------

insert into public.message_templates (id, tenant_id, key, channel, locale, body, is_active)
select
  ('00000019-0000-4000-8000-' || lpad(m.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  m.key,
  m.channel::public.notification_channel,
  'en',
  m.body,
  true
from (values
  (1, 'renewal_due', 'push',
      'Hi {{name}}, your {{plan}} at Iron Box ends on {{ends_on}}. Renew today and keep your streak going.'),
  (2, 'winback_absent', 'push',
      'We have missed you at Iron Box, {{name}} — it has been {{absent_days}} days. Shall we book you in this week?'),
  (3, 'streak_milestone', 'push',
      '{{name}}, that is {{streak}} days in a row. Outstanding.')
) as m(n, key, channel, body)
on conflict (id) do update set
  key       = excluded.key,
  channel   = excluded.channel,
  locale    = excluded.locale,
  body      = excluded.body,
  is_active = excluded.is_active;


-- ---------------------------------------------------------------------------
-- 9. The messaging credit wallet and its ledger. balance_credits is a credit
--    count, not money — no currency column exists here. The two ledger rows
--    sum to the balance.
-- ---------------------------------------------------------------------------

insert into public.messaging_wallets (tenant_id, balance_credits)
values ('00000001-0000-4000-8000-000000000001', 4500)
on conflict (tenant_id) do update set balance_credits = excluded.balance_credits;

insert into public.messaging_wallet_ledger (id, tenant_id, delta_credits, reason)
select
  ('00000022-0000-4000-8000-' || lpad(l.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  l.delta_credits,
  l.reason
from (values
  (1,  5000::bigint, 'Opening credit purchase'),
  (2,  -500::bigint, 'Renewal and win-back pushes sent')
) as l(n, delta_credits, reason)
on conflict (id) do update set
  delta_credits = excluded.delta_credits,
  reason        = excluded.reason;


-- ---------------------------------------------------------------------------
-- 10. Holiday calendar (STK-002). Fixed calendar dates in the current year, not
--     offsets from today — a day offset would shift on every re-run and could
--     land one holiday on the other's previous date, breaking
--     organization_holidays_tenant_id_holiday_on_key mid-statement.
-- ---------------------------------------------------------------------------

insert into public.organization_holidays (id, tenant_id, holiday_on, name)
select
  ('00000021-0000-4000-8000-' || lpad(h.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  make_date(extract(year from t.d)::integer, h.month, h.day),
  h.name
from (values
  (1, 8,  15, 'Independence Day — gym closed'),
  (2, 10, 20, 'Diwali — gym closed')
) as h(n, month, day, name)
cross join (select (now() at time zone 'Asia/Kolkata')::date as d) t
on conflict (id) do update set
  holiday_on = excluded.holiday_on,
  name       = excluded.name;


-- ---------------------------------------------------------------------------
-- 11. Two QR check-in sessions: one live, one expired. ATT-003 — only the hash
--     of the token is ever stored; there is no column for a raw token.
-- ---------------------------------------------------------------------------

insert into public.qr_sessions (
  id, tenant_id, branch_id, token_hash, issued_at, expires_at, revoked_at,
  created_by_staff_id
)
select
  ('00000020-0000-4000-8000-' || lpad(q.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  '00000002-0000-4000-8000-000000000001'::uuid,
  q.token_hash,
  now() + q.issued_offset,
  now() + q.issued_offset + interval '15 minutes',
  null,
  '00000003-0000-4000-8000-000000000004'::uuid
from (values
  (1, 'seed$sha256$live$vijaynagar$0001',    - interval '2 minutes'),
  (2, 'seed$sha256$expired$vijaynagar$0002', - interval '2 days')
) as q(n, token_hash, issued_offset)
on conflict (id) do update set
  branch_id           = excluded.branch_id,
  token_hash          = excluded.token_hash,
  issued_at           = excluded.issued_at,
  expires_at          = excluded.expires_at,
  revoked_at          = excluded.revoked_at,
  created_by_staff_id = excluded.created_by_staff_id;


-- ---------------------------------------------------------------------------
-- 12. Thirty members.
--
--     The roster CTE below is the spine of the whole demo and reappears,
--     identically, in every statement that needs a member's cohort. It fixes
--     two things per member index:
--
--       days_to_expiry — how far today the member's membership ends.
--           idx  1– 5 → 1..5 days   the five renewals due this week
--           idx  6–11 → 66..71 days the six silent-churn members (comfortably
--                                   live, so their absence is the only signal)
--           idx 12–30 → 12..84 days everyone else, well outside the 7-day window
--
--       plan_no — chosen so that duration_days >= days_to_expiry for every
--           member, which is what keeps starts_on (= ends_on - duration) in the
--           past. All four tiers are used.
-- ---------------------------------------------------------------------------

--     **The seed states history, and the product now grants membership time
--     from payments (ADR-083).** `app.extend_membership_on_payment()` fires on
--     every one of the thirty rows below and moves `ends_on` forward by the
--     plan's duration — correct for a payment being taken at a desk today, and
--     wrong for a row asserting what a membership already ran. Left alone, every
--     seeded membership would come out a month longer than the scenario means,
--     and the retention fixtures — a member whose membership lapsed on a named
--     day, the case that outlives it — would quietly stop being about anything.
--
--     So the dates are taken before and put back after. NOT a carve-out in the
--     trigger: the trigger is right, and a seed is the one caller whose job is
--     to say what already happened rather than to make something happen.

with roster as (
  select
    n as idx,
    ('00000005-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid as member_id,
    case
      when n <= 5  then n
      when n <= 11 then 60 + n
      else 12 + (n - 12) * 4
    end as days_to_expiry,
    case
      when n <= 5  then ((n - 1) % 4) + 1
      when n <= 11 then case when n % 2 = 1 then 3 else 4 end
      else 2 + (n % 3)
    end as plan_no
  from generate_series(1, 30) as n
),
names as (
  select * from (values
    ( 1, 'Aarav Deshpande',  'male'),   ( 2, 'Priya Nair',        'female'),
    ( 3, 'Rohan Kulkarni',   'male'),   ( 4, 'Sneha Joshi',       'female'),
    ( 5, 'Vikram Reddy',     'male'),   ( 6, 'Ananya Bhatt',      'female'),
    ( 7, 'Karthik Menon',    'male'),   ( 8, 'Ishita Agarwal',    'female'),
    ( 9, 'Siddharth Rao',    'male'),   (10, 'Neha Chauhan',      'female'),
    (11, 'Manish Gupta',     'male'),   (12, 'Pooja Shetty',      'female'),
    (13, 'Aditya Verma',     'male'),   (14, 'Ritika Saxena',     'female'),
    (15, 'Harsh Malhotra',   'male'),   (16, 'Kavya Pillai',      'female'),
    (17, 'Nikhil Bansal',    'male'),   (18, 'Shruti Kadam',      'female'),
    (19, 'Rahul Thakur',     'male'),   (20, 'Divya Ramesh',      'female'),
    (21, 'Aman Chopra',      'male'),   (22, 'Tanvi Mehta',       'female'),
    (23, 'Gaurav Sinha',     'male'),   (24, 'Megha Dutta',       'female'),
    (25, 'Yash Pandey',      'male'),   (26, 'Swati Kulkarni',    'female'),
    (27, 'Varun Nambiar',    'male'),   (28, 'Aishwarya Rane',    'female'),
    (29, 'Sameer Qureshi',   'male'),   (30, 'Lakshmi Iyengar',   'female')
  ) as v(idx, full_name, gender)
),
today as (select (now() at time zone 'Asia/Kolkata')::date as d)
insert into public.members (
  id, tenant_id, branch_id, member_code, full_name, phone, email, gender,
  date_of_birth, status, joined_on, weekly_goal_visits, rest_days,
  motivation_push_enabled
)
select
  r.member_id,
  '00000001-0000-4000-8000-000000000001'::uuid,
  '00000002-0000-4000-8000-000000000001'::uuid,
  'IB' || lpad(r.idx::text, 3, '0'),
  nm.full_name,
  '+9198765' || lpad(r.idx::text, 5, '0'),
  lower(regexp_replace(nm.full_name, '[^A-Za-z]+', '.', 'g')) || '@example.com',
  nm.gender,
  date '1988-02-14' + (r.idx * 97),
  'active',
  -- joined a few days before the membership they are on started
  (t.d + r.days_to_expiry - p.duration_days) - (5 + r.idx),
  (3 + (r.idx % 2))::smallint,
  '{0}'::smallint[],   -- STK-002: Sunday is a rest day, 0 = Sunday
  true
from roster r
join names nm on nm.idx = r.idx
join public.plans p
  on p.id = ('00000004-0000-4000-8000-' || lpad(r.plan_no::text, 12, '0'))::uuid
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
-- 13. Consent, both purposes, per member (DPD-002/003/004). Append-only in
--     production — the seed anchors on a fixed id so a re-run rewrites the same
--     row instead of stacking a second grant.
--     Row index is idx*10 + purpose (1 = service, 2 = marketing).
-- ---------------------------------------------------------------------------

insert into public.consents (
  id, tenant_id, member_id, purpose, granted, version, source,
  recorded_at, recorded_by_staff_id
)
select
  ('00000016-0000-4000-8000-' || lpad((n * 10 + pr.purpose_no)::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  ('00000005-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  pr.purpose::public.consent_purpose,
  case when pr.purpose = 'service' then true else (n % 2 = 0) end,
  'v1',
  'front_desk_signup',
  (m.joined_on + time '11:00') at time zone 'Asia/Kolkata',
  '00000003-0000-4000-8000-000000000004'::uuid
from generate_series(1, 30) as n
cross join (values (1, 'service'), (2, 'marketing')) as pr(purpose_no, purpose)
join public.members m
  on m.id = ('00000005-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
on conflict (id) do update set
  purpose              = excluded.purpose,
  granted              = excluded.granted,
  version              = excluded.version,
  source               = excluded.source,
  recorded_at          = excluded.recorded_at,
  recorded_by_staff_id = excluded.recorded_by_staff_id;


-- ---------------------------------------------------------------------------
-- 14. Five registered devices, so push has somewhere to go (ADR-016).
-- ---------------------------------------------------------------------------

insert into public.member_devices (
  id, tenant_id, member_id, platform, push_token, last_seen_at, is_active
)
select
  ('00000017-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  ('00000005-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  case when n % 2 = 0 then 'android' else 'ios' end,
  'ExponentPushToken[seed-ironbox-' || lpad(n::text, 3, '0') || ']',
  now() - (n * interval '3 hours'),
  true
from generate_series(1, 5) as n
on conflict (id) do update set
  platform     = excluded.platform,
  push_token   = excluded.push_token,
  last_seen_at = excluded.last_seen_at,
  is_active    = excluded.is_active;

-- `memberships_terms_frozen` is disabled for exactly this statement and re-enabled
-- immediately after it. `GL045` (ADR-093) makes a membership's dates the granting
-- rule's to write, and the seed cannot reach them that way: it constructs months of
-- history in one pass, and a payment can only ever move `ends_on` forward from
-- today. **This is the deliberate, visible act that rule's own migration
-- prescribes** — "a deliberate act and says so, by disabling this trigger for the
-- length of that one statement. It does not get to happen by accident." Saying it
-- in four lines beats a carve-out inside the rule that every future reader has to
-- reason about.
--
-- The `alter` goes at the STATEMENT boundary, not next to the `insert`: this one is
-- preceded by a `with … as (…)` and splitting a CTE from its INSERT is a syntax
-- error that reaches CI looking like a seed bug.
alter table public.memberships disable trigger memberships_terms_frozen;



-- ---------------------------------------------------------------------------
-- 15. One live membership per member — thirty rows, all `active`, so each one
--     satisfies memberships_dated_unless_pending_chk with a real starts_on and
--     ends_on, and the "at most one live membership per member" partial unique
--     index holds trivially.
--
--     Member 4 is on the coupon: 10% of 12000 rupees is exactly 120000 paise,
--     integer arithmetic throughout.
-- ---------------------------------------------------------------------------

with roster as (
  select
    n as idx,
    ('00000005-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid as member_id,
    ('00000006-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid as membership_id,
    case
      when n <= 5  then n
      when n <= 11 then 60 + n
      else 12 + (n - 12) * 4
    end as days_to_expiry,
    case
      when n <= 5  then ((n - 1) % 4) + 1
      when n <= 11 then case when n % 2 = 1 then 3 else 4 end
      else 2 + (n % 3)
    end as plan_no
  from generate_series(1, 30) as n
),
today as (select (now() at time zone 'Asia/Kolkata')::date as d)
insert into public.memberships (
  id, tenant_id, member_id, plan_id, status, starts_on, ends_on,
  price_paise, discount_paise, currency, coupon_id,
  renewal_of_membership_id, activated_at
)
select
  r.membership_id,
  '00000001-0000-4000-8000-000000000001'::uuid,
  r.member_id,
  p.id,
  'active',
  t.d + r.days_to_expiry - p.duration_days,
  t.d + r.days_to_expiry,
  p.price_paise,
  case when r.idx = 4 then p.price_paise / 10 else 0 end,
  'INR',
  case when r.idx = 4 then '00000015-0000-4000-8000-000000000001'::uuid else null end,
  null,
  ((t.d + r.days_to_expiry - p.duration_days) + time '10:00') at time zone 'Asia/Kolkata'
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
  activated_at             = excluded.activated_at;

alter table public.memberships enable trigger memberships_terms_frozen;

-- **The snapshot is taken AFTER the upsert above, and that ordering is the whole
-- point.** It sat before it for eleven rounds and nobody saw it, because
-- `seed-dry-run` only checks that the seed RUNS. Taken early it captures the
-- PREVIOUS run's `ends_on` and puts that back, so `starts_on` re-anchors to
-- today and `ends_on` does not: every span came out short by the number of days
-- since the last seed, accumulating, and a re-run reproduced the same wrong
-- answer, so "idempotent" held and hid it. On a genuinely fresh database the
-- table would be empty here and the restore would do nothing at all, leaving
-- every membership a full plan-duration too long — precisely what the block
-- above says it exists to prevent.
drop table if exists seed_membership_period;
create temp table seed_membership_period as
  select id, starts_on, ends_on
    from public.memberships
   where tenant_id = '00000001-0000-4000-8000-000000000001'::uuid;





-- ---------------------------------------------------------------------------
-- 16. The payment that bought each membership — thirty `paid` rows.
--
--     Every one satisfies all three multi-column payment checks:
--       payments_paid_has_reference_chk  a razorpay row carries
--         provider_payment_id, an offline row carries receipt_number.
--       payments_offline_has_staff_chk   cash and UPI name the front-desk
--         staff member who took the money (PAY-011).
--       payments_razorpay_has_order_chk  a razorpay row carries an order id.
--
--     The financial year in the receipt number is derived from today, so the
--     seed is honest whenever it runs; receipt numbers stay unique because they
--     are anchored to the member index and the FY string changes wholesale.
-- ---------------------------------------------------------------------------

with roster as (
  select
    n as idx,
    ('00000005-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid as member_id,
    ('00000006-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid as membership_id,
    case n % 3 when 0 then 'razorpay' when 1 then 'cash' else 'upi' end as method
  from generate_series(1, 30) as n
),
today as (
  select
    (now() at time zone 'Asia/Kolkata')::date as d,
    case
      when extract(month from (now() at time zone 'Asia/Kolkata')::date) >= 4
        then to_char((now() at time zone 'Asia/Kolkata')::date, 'YYYY') || '-' ||
             to_char((now() at time zone 'Asia/Kolkata')::date + interval '1 year', 'YY')
      else to_char((now() at time zone 'Asia/Kolkata')::date - interval '1 year', 'YYYY') || '-' ||
           to_char((now() at time zone 'Asia/Kolkata')::date, 'YY')
    end as fy
)
-- **A payment is a record, so this seed does not rewrite one.**
--
-- These rows used to `on conflict (id) do update`, and once
-- `app.enforce_payment()` froze a paid payment's money facts (ADR-085) a second
-- seed run was refused with `GL038`: the membership dates are anchored to
-- `today` and slide, so `paid_at` — derived from `starts_on` — slid with them,
-- and the freeze correctly refused to move the date on an already-receipted
-- payment.
--
-- **Carving the freeze out for trusted writers would have been the easy fix and
-- the wrong one.** The one Cloud project this seed runs against is the one that
-- will later hold a real gym's rows (OPEN-006), and a carve-out is precisely a
-- door through which a seed, a migration or a webhook bug rewrites recorded
-- money. `do nothing` needs no door: the first run creates these payments and
-- every later run leaves them exactly as they were, which is what "a record of
-- money that changed hands" means when it is taken seriously.
--
-- The cost, stated rather than discovered: a re-seeded demo gym keeps its
-- original payment dates while its membership dates move on, so the two drift
-- apart over successive runs. That is cosmetic in a demo, and the more honest
-- of the two — the payment did happen when it happened.
insert into public.payments (
  id, tenant_id, member_id, membership_id, mandate_id, coupon_id,
  amount_paise, currency, status, method, provider, provider_order_id,
  provider_payment_id, receipt_number, recorded_by_staff_id, idempotency_key,
  paid_at, notes
)
select
  ('00000007-0000-4000-8000-' || lpad(r.idx::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  r.member_id,
  r.membership_id,
  null,
  ms.coupon_id,
  ms.price_paise - ms.discount_paise,
  'INR',
  'paid',
  r.method::public.payment_method,
  case when r.method = 'razorpay' then 'razorpay' else null end,
  case when r.method = 'razorpay'
       then 'order_SEEDMSHIP' || lpad(r.idx::text, 4, '0') else null end,
  case when r.method = 'razorpay'
       then 'pay_SEEDMSHIP' || lpad(r.idx::text, 4, '0') else null end,
  -- **Every payment gets a receipt number, online ones included.** ADR-082:
  -- "a receipt book with a hole in it for every online payment is not a receipt
  -- book". This wrote `null` for razorpay rows on the reasoning that an online
  -- row carries `provider_payment_id` instead — the exact split that ADR
  -- rejected, sitting in the one gym every screen renders.
  --
  -- Format is the rule's own (`FY/NNNNNN`) rather than the `RCPT/FY/NNNN` this
  -- used to write, so the demo book holds one grammar; and the year comes from
  -- the payment's OWN day, not today's, which is the reason ADR-082 gives for
  -- putting a year in the number at all.
  (((case when extract(month from ms.starts_on) >= 4 then extract(year from ms.starts_on) else extract(year from ms.starts_on) - 1 end)::int::text || '-' || lpad(((((case when extract(month from ms.starts_on) >= 4 then extract(year from ms.starts_on) else extract(year from ms.starts_on) - 1 end)::int) + 1) % 100)::text, 2, '0')) || '/' || lpad(r.idx::text, 6, '0')),
  case when r.method = 'razorpay'
       then null else '00000003-0000-4000-8000-000000000004'::uuid end,
  'seed:membership:' || lpad(r.idx::text, 4, '0'),
  (ms.starts_on + time '10:00') at time zone 'Asia/Kolkata',
  case when r.method = 'razorpay' then 'Paid online via Razorpay.'
       when r.method = 'cash'     then 'Collected at the front desk.'
       else 'UPI to the gym QR, confirmed at the front desk.' end
from roster r
join public.memberships ms on ms.id = r.membership_id
cross join today t
on conflict (id) do nothing;

-- `memberships_terms_frozen` is disabled for exactly this statement and re-enabled
-- immediately after it. `GL045` (ADR-093) makes a membership's dates the granting
-- rule's to write, and the seed cannot reach them that way: it constructs months of
-- history in one pass, and a payment can only ever move `ends_on` forward from
-- today. **This is the deliberate, visible act that rule's own migration
-- prescribes** — "a deliberate act and says so, by disabling this trigger for the
-- length of that one statement. It does not get to happen by accident." Saying it
-- in four lines beats a carve-out inside the rule that every future reader has to
-- reason about.
--
-- The `alter` goes at the STATEMENT boundary, not next to the `insert`: this one is
-- preceded by a `with … as (…)` and splitting a CTE from its INSERT is a syntax
-- error that reaches CI looking like a seed bug.
alter table public.memberships disable trigger memberships_terms_frozen;



-- ---------------------------------------------------------------------------
-- 16b. Put the membership dates back.
--
--     The thirty payments above each extended the membership they name. That is
--     the product working; this restores what the scenario says those
--     memberships ran, and the `is distinct from` means a re-run of the seed
--     touches nothing once the dates already agree.
-- ---------------------------------------------------------------------------

-- First paid grants set both dates. Restore both historical endpoints after
-- constructing the seed's paid period, including its discounted annual row.
update public.memberships m
   set starts_on = p.starts_on,
       ends_on = p.ends_on
  from seed_membership_period p
 where m.id = p.id
   and (m.starts_on is distinct from p.starts_on
        or m.ends_on is distinct from p.ends_on);

alter table public.memberships enable trigger memberships_terms_frozen;

drop table seed_membership_period;


-- ---------------------------------------------------------------------------
-- 17. Attendance — the six weeks of history that make the retention loop and
--     the streak visible.
--
--     The visit grid is a pure function of (member index, day offset), so it is
--     identical on every run; only the dates it is anchored to move.
--
--       members  6–11  visit every second day starting 11/13/15/16/18/20 days
--                      ago and nothing since — their last visit is 11..20 days
--                      back, which is the six silent-churn cases, and is
--                      strictly more than ten days so "no attendance in the
--                      last ten days" is true under either reading of the bound.
--       member   12    visits every single day of the last 21 — the streak.
--       everyone else  visits every second day across the last six weeks, always
--                      including day 0 or day 1, so nobody else is ever silent
--                      for ten days.
--
--     ATT-005/006: one visit in nine is a front-desk assisted check-in, which
--     must carry both the acting staff member and a non-empty reason; the QR
--     rows carry neither, satisfying attendance_assisted_pair_chk.
--     ATT-008: check-out is optional — one visit in seven has none.
-- ---------------------------------------------------------------------------

with roster as (
  select
    n as idx,
    ('00000005-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid as member_id,
    ('00000006-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid as membership_id,
    case n when 6 then 11 when 7 then 13 when 8 then 15
           when 9 then 16 when 10 then 18 when 11 then 20 end as absent_days
  from generate_series(1, 30) as n
),
visits as (
  select r.idx, r.member_id, r.membership_id, g.day_offset
  from roster r
  cross join lateral (
    select gs.day_offset
    from generate_series(0, 41) as gs(day_offset)
    where case
            when r.absent_days is not null
              then gs.day_offset >= r.absent_days
                   and (gs.day_offset - r.absent_days) % 2 = 0
            when r.idx = 12 then gs.day_offset <= 20
            else (gs.day_offset + r.idx) % 2 = 0
          end
  ) g
),
today as (select (now() at time zone 'Asia/Kolkata')::date as d)
insert into public.attendance (
  id, tenant_id, branch_id, member_id, membership_id,
  checked_in_at, checked_out_at, source, qr_session_id,
  assisted_by_staff_id, assist_reason
)
select
  ('00000008-0000-4000-8000-' || lpad((v.idx * 1000 + v.day_offset)::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  '00000002-0000-4000-8000-000000000001'::uuid,
  v.member_id,
  v.membership_id,
  ((t.d - v.day_offset) + time '18:30' + ((v.idx % 5) * interval '7 minutes'))
    at time zone 'Asia/Kolkata',
  case when v.day_offset % 7 = 0 then null
       else ((t.d - v.day_offset) + time '18:30'
             + ((v.idx % 5) * interval '7 minutes') + interval '65 minutes')
              at time zone 'Asia/Kolkata'
  end,
  case when v.day_offset % 9 = 0 then 'front_desk' else 'qr' end::public.attendance_source,
  null,
  case when v.day_offset % 9 = 0
       then '00000003-0000-4000-8000-000000000004'::uuid else null end,
  case when v.day_offset % 9 = 0
       then 'Phone battery dead — checked in at the desk' else null end
from visits v
cross join today t
on conflict (id) do update set
  branch_id            = excluded.branch_id,
  member_id            = excluded.member_id,
  membership_id        = excluded.membership_id,
  checked_in_at        = excluded.checked_in_at,
  checked_out_at       = excluded.checked_out_at,
  source               = excluded.source,
  qr_session_id        = excluded.qr_session_id,
  assisted_by_staff_id = excluded.assisted_by_staff_id,
  assist_reason        = excluded.assist_reason;


-- ---------------------------------------------------------------------------
-- 18. Add-on payments. Row 101 is the verified gateway payment the PT order
--     hangs off; 102 and 103 are offline, so they name the staff member and
--     carry a receipt number.
-- ---------------------------------------------------------------------------

with today as (
  select
    (now() at time zone 'Asia/Kolkata')::date as d,
    case
      when extract(month from (now() at time zone 'Asia/Kolkata')::date) >= 4
        then to_char((now() at time zone 'Asia/Kolkata')::date, 'YYYY') || '-' ||
             to_char((now() at time zone 'Asia/Kolkata')::date + interval '1 year', 'YY')
      else to_char((now() at time zone 'Asia/Kolkata')::date - interval '1 year', 'YYYY') || '-' ||
           to_char((now() at time zone 'Asia/Kolkata')::date, 'YY')
    end as fy
)
-- **A payment is a record, so this seed does not rewrite one.**
--
-- These rows used to `on conflict (id) do update`, and once
-- `app.enforce_payment()` froze a paid payment's money facts (ADR-085) a second
-- seed run was refused with `GL038`: the membership dates are anchored to
-- `today` and slide, so `paid_at` — derived from `starts_on` — slid with them,
-- and the freeze correctly refused to move the date on an already-receipted
-- payment.
--
-- **Carving the freeze out for trusted writers would have been the easy fix and
-- the wrong one.** The one Cloud project this seed runs against is the one that
-- will later hold a real gym's rows (OPEN-006), and a carve-out is precisely a
-- door through which a seed, a migration or a webhook bug rewrites recorded
-- money. `do nothing` needs no door: the first run creates these payments and
-- every later run leaves them exactly as they were, which is what "a record of
-- money that changed hands" means when it is taken seriously.
--
-- The cost, stated rather than discovered: a re-seeded demo gym keeps its
-- original payment dates while its membership dates move on, so the two drift
-- apart over successive runs. That is cosmetic in a demo, and the more honest
-- of the two — the payment did happen when it happened.
insert into public.payments (
  id, tenant_id, member_id, membership_id, mandate_id, coupon_id,
  amount_paise, currency, status, method, provider, provider_order_id,
  provider_payment_id, receipt_number, recorded_by_staff_id, idempotency_key,
  paid_at, notes
)
select
  ('00000007-0000-4000-8000-' || lpad(a.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  ('00000005-0000-4000-8000-' || lpad(a.member_no::text, 12, '0'))::uuid,
  null,
  null,
  null,
  a.amount_paise,
  'INR',
  'paid',
  a.method::public.payment_method,
  case when a.method = 'razorpay' then 'razorpay' else null end,
  case when a.method = 'razorpay'
       then 'order_SEEDADDON' || lpad(a.n::text, 4, '0') else null end,
  case when a.method = 'razorpay'
       then 'pay_SEEDADDON' || lpad(a.n::text, 4, '0') else null end,
  -- Same for add-on payments. Numbers start at 1000 so they cannot collide with
  -- the membership payments above, which are numbered by roster index.
  (((case when extract(month from (t.d + a.paid_day_offset)) >= 4 then extract(year from (t.d + a.paid_day_offset)) else extract(year from (t.d + a.paid_day_offset)) - 1 end)::int::text || '-' || lpad(((((case when extract(month from (t.d + a.paid_day_offset)) >= 4 then extract(year from (t.d + a.paid_day_offset)) else extract(year from (t.d + a.paid_day_offset)) - 1 end)::int) + 1) % 100)::text, 2, '0')) || '/' || lpad((1000 + a.n)::text, 6, '0')),
  case when a.method = 'razorpay'
       then null else '00000003-0000-4000-8000-000000000004'::uuid end,
  'seed:addon:' || lpad(a.n::text, 4, '0'),
  ((t.d + a.paid_day_offset) + time '12:00') at time zone 'Asia/Kolkata',
  a.notes
from (values
  (101, 2,  800000::bigint, 'razorpay', -18, 'PT Starter package, paid online.'),
  (102, 7,  250000::bigint, 'upi',       -5, 'Diet plan, UPI at the desk.'),
  (103, 15, 240000::bigint, 'cash',     -12, 'Whey protein tub, cash at the desk.')
) as a(n, member_no, amount_paise, method, paid_day_offset, notes)
cross join today t
on conflict (id) do nothing;


-- ---------------------------------------------------------------------------
-- 19. Three add-on orders, one of each kind. Every one is past `pending`, so
--     addon_orders_paid_has_payment_chk requires the payment — and each names
--     the paid row above. ADD-004: sessions_used never exceeds sessions_total.
-- ---------------------------------------------------------------------------

with today as (select (now() at time zone 'Asia/Kolkata')::date as d)
insert into public.addon_orders (
  id, tenant_id, member_id, addon_product_id, payment_id, status,
  quantity, unit_price_paise, total_paise, currency, trainer_staff_id,
  sessions_total, sessions_used, starts_on, expires_on
)
select
  ('00000010-0000-4000-8000-' || lpad(o.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  ('00000005-0000-4000-8000-' || lpad(o.member_no::text, 12, '0'))::uuid,
  ('00000009-0000-4000-8000-' || lpad(o.product_no::text, 12, '0'))::uuid,
  ('00000007-0000-4000-8000-' || lpad(o.payment_no::text, 12, '0'))::uuid,
  o.status::public.addon_order_status,
  o.quantity,
  o.unit_price_paise,
  o.total_paise,
  'INR',
  case when o.trainer_no is null then null
       else ('00000003-0000-4000-8000-' || lpad(o.trainer_no::text, 12, '0'))::uuid
  end,
  o.sessions_total,
  o.sessions_used,
  t.d + o.starts_day_offset,
  case when o.expires_day_offset is null then null
       else t.d + o.expires_day_offset end
from (values
  -- PT: 12 sessions bought, 3 delivered, still running
  (1,  2, 1, 101, 'active',     1,  800000::bigint,  800000::bigint, 1,
       12, 3, -18, 72),
  -- diet plan: paid, 8 weeks of validity
  (2,  7, 3, 102, 'paid',       1,  250000::bigint,  250000::bigint, 2,
       null::integer, 0, -5, 51),
  -- supplement: handed over the counter, done
  (3, 15, 4, 103, 'completed',  1,  240000::bigint,  240000::bigint, null::integer,
       null::integer, 0, -12, null::integer)
) as o(n, member_no, product_no, payment_no, status, quantity,
       unit_price_paise, total_paise, trainer_no, sessions_total,
       sessions_used, starts_day_offset, expires_day_offset)
cross join today t
on conflict (id) do update set
  member_id        = excluded.member_id,
  addon_product_id = excluded.addon_product_id,
  payment_id       = excluded.payment_id,
  status           = excluded.status,
  quantity         = excluded.quantity,
  unit_price_paise = excluded.unit_price_paise,
  total_paise      = excluded.total_paise,
  currency         = excluded.currency,
  trainer_staff_id = excluded.trainer_staff_id,
  sessions_total   = excluded.sessions_total,
  sessions_used    = excluded.sessions_used,
  starts_on        = excluded.starts_on,
  expires_on       = excluded.expires_on;


-- ---------------------------------------------------------------------------
-- 20. Five PT sessions on the open package: three delivered, two booked.
--
--     Each session sits at a different hour of the day (06:00 … 10:00). That is
--     deliberate, not decoration: all five belong to the same trainer, and
--     pt_sessions_trainer_overlap_excl (DQA-005) is checked row by row as the
--     upsert walks the set. If two sessions differed only by day offset, a
--     re-run whose day shift equalled the gap between them would move one onto
--     the other's not-yet-updated slot and raise 23P01. Distinct hours make an
--     overlap impossible whatever the shift.
-- ---------------------------------------------------------------------------

with today as (select (now() at time zone 'Asia/Kolkata')::date as d)
insert into public.pt_sessions (
  id, tenant_id, addon_order_id, trainer_staff_id, member_id,
  starts_at, ends_at, status, notes
)
select
  ('00000011-0000-4000-8000-' || lpad(s.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  '00000010-0000-4000-8000-000000000001'::uuid,
  '00000003-0000-4000-8000-000000000001'::uuid,
  '00000005-0000-4000-8000-000000000002'::uuid,
  ((t.d + s.day_offset) + s.hour_of_day) at time zone 'Asia/Kolkata',
  ((t.d + s.day_offset) + s.hour_of_day + interval '1 hour') at time zone 'Asia/Kolkata',
  s.status::public.pt_session_status,
  s.notes
from (values
  (1, -18, time '06:00', 'completed', 'Assessment, movement screen, lower body.'),
  (2, -14, time '07:00', 'completed', 'Squat pattern, posterior chain.'),
  (3,  -9, time '08:00', 'completed', 'Upper body push/pull, core.'),
  (4,   1, time '09:00', 'scheduled', null),
  (5,   4, time '10:00', 'scheduled', null)
) as s(n, day_offset, hour_of_day, status, notes)
cross join today t
on conflict (id) do update set
  addon_order_id   = excluded.addon_order_id,
  trainer_staff_id = excluded.trainer_staff_id,
  member_id        = excluded.member_id,
  starts_at        = excluded.starts_at,
  ends_at          = excluded.ends_at,
  status           = excluded.status,
  notes            = excluded.notes;


-- ---------------------------------------------------------------------------
-- 21. Six retention cases — one per silent-churn member, at three stages.
--
--     Every case was opened when the member's absence reached 8 days, one day
--     past the gym's 7-day threshold; absent_days_at_open and threshold_days are
--     snapshots of that moment and do not move if the setting later changes.
--     The partial unique index (tenant_id, member_id) where status is live is
--     satisfied because there is exactly one case per member.
-- ---------------------------------------------------------------------------

with cases as (
  select * from (values
    ( 6, 11, 'open',           1),
    ( 7, 13, 'open',           2),
    ( 8, 15, 'contacted',      3),
    ( 9, 16, 'contacted',      1),
    (10, 18, 'follow_up_due',  2),
    (11, 20, 'follow_up_due',  3)
  ) as v(member_no, absent_days, status, trainer_no)
),
today as (select (now() at time zone 'Asia/Kolkata')::date as d)
insert into public.no_show_cases (
  id, tenant_id, member_id, status, opened_on, last_attended_on,
  absent_days_at_open, threshold_days, assigned_to_staff_id,
  contacted_at, next_follow_up_at, returned_at, closed_at
)
select
  ('00000013-0000-4000-8000-' || lpad(c.member_no::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  ('00000005-0000-4000-8000-' || lpad(c.member_no::text, 12, '0'))::uuid,
  c.status::public.no_show_case_status,
  t.d - (c.absent_days - 8),   -- opened when absence hit 8 days
  t.d - c.absent_days,
  8,
  7,
  ('00000003-0000-4000-8000-' || lpad(c.trainer_no::text, 12, '0'))::uuid,
  case when c.status in ('contacted', 'follow_up_due')
       then ((t.d - (c.absent_days - 9)) + time '17:00') at time zone 'Asia/Kolkata'
       else null end,
  case when c.status = 'follow_up_due'
       then ((t.d + 1) + time '11:00') at time zone 'Asia/Kolkata'
       else null end,
  null,
  null
from cases c
cross join today t
on conflict (id) do update set
  member_id            = excluded.member_id,
  status               = excluded.status,
  opened_on            = excluded.opened_on,
  last_attended_on     = excluded.last_attended_on,
  absent_days_at_open  = excluded.absent_days_at_open,
  threshold_days       = excluded.threshold_days,
  assigned_to_staff_id = excluded.assigned_to_staff_id,
  contacted_at         = excluded.contacted_at,
  next_follow_up_at    = excluded.next_follow_up_at,
  returned_at          = excluded.returned_at,
  closed_at            = excluded.closed_at;


-- ---------------------------------------------------------------------------
-- 22. The contact log on the four cases somebody has already worked (NSH-007).
-- ---------------------------------------------------------------------------

with today as (select (now() at time zone 'Asia/Kolkata')::date as d)
insert into public.follow_ups (
  id, tenant_id, case_id, staff_id, channel, outcome, notes, next_action,
  next_follow_up_at, corrects_follow_up_id
)
select
  ('00000014-0000-4000-8000-' || lpad(f.member_no::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  ('00000013-0000-4000-8000-' || lpad(f.member_no::text, 12, '0'))::uuid,
  ('00000003-0000-4000-8000-' || lpad(f.staff_no::text, 12, '0'))::uuid,
  f.channel::public.contact_channel,
  f.outcome::public.follow_up_outcome,
  f.notes,
  f.next_action,
  case when f.next_follow_up_day_offset is null then null
       else ((t.d + f.next_follow_up_day_offset) + time '11:00') at time zone 'Asia/Kolkata'
  end,
  null
from (values
  ( 8, 4, 'call',     'travelling',
       'Away in Pune for work until the weekend.', 'Call again once he is back', null::integer),
  ( 9, 3, 'whatsapp', 'injured',
       'Knee niggle, physio cleared her for light lower body.', 'Offer a rehab-friendly plan', null::integer),
  (10, 2, 'call',     'timing_issue',
       'New shift means she cannot make the evening slot.', 'Pitch the 06:00 batch', 1),
  (11, 4, 'whatsapp', 'no_response',
       'Two messages, no reply.', 'One more call, then hand to the owner', 1)
) as f(member_no, staff_no, channel, outcome, notes, next_action, next_follow_up_day_offset)
cross join today t
on conflict (id) do update set
  case_id               = excluded.case_id,
  staff_id              = excluded.staff_id,
  channel               = excluded.channel,
  outcome               = excluded.outcome,
  notes                 = excluded.notes,
  next_action           = excluded.next_action,
  next_follow_up_at     = excluded.next_follow_up_at,
  corrects_follow_up_id = excluded.corrects_follow_up_id;


-- ---------------------------------------------------------------------------
-- 23. Eight leads across six distinct stages. The converted one names the
--     member it became (leads_converted_has_member_chk).
-- ---------------------------------------------------------------------------

with today as (select (now() at time zone 'Asia/Kolkata')::date as d)
insert into public.leads (
  id, tenant_id, branch_id, full_name, phone, email, source, stage,
  assigned_to_staff_id, trial_at, converted_member_id, converted_at,
  lost_reason, notes
)
select
  ('00000012-0000-4000-8000-' || lpad(l.n::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  '00000002-0000-4000-8000-000000000001'::uuid,
  l.full_name,
  '+9198110' || lpad(l.n::text, 5, '0'),
  l.email,
  l.source::public.lead_source,
  l.stage::public.lead_stage,
  case when l.staff_no is null then null
       else ('00000003-0000-4000-8000-' || lpad(l.staff_no::text, 12, '0'))::uuid
  end,
  case when l.trial_day_offset is null then null
       else ((t.d + l.trial_day_offset) + time '07:00') at time zone 'Asia/Kolkata'
  end,
  case when l.converted_member_no is null then null
       else ('00000005-0000-4000-8000-' || lpad(l.converted_member_no::text, 12, '0'))::uuid
  end,
  case when l.converted_day_offset is null then null
       else ((t.d + l.converted_day_offset) + time '18:00') at time zone 'Asia/Kolkata'
  end,
  l.lost_reason,
  l.notes
from (values
  (1, 'Rakesh Tiwari',   'rakesh.tiwari@example.com',   'walk_in',   'new',
      null::integer, null::integer, null::integer, null::integer, null::text,
      'Walked in on Saturday, asked about the annual plan.'),
  (2, 'Nandini Sethi',   'nandini.sethi@example.com',   'instagram', 'new',
      null::integer, null::integer, null::integer, null::integer, null::text,
      'DM from the reel about the 06:00 batch.'),
  (3, 'Prakash Jadhav',  'prakash.jadhav@example.com',  'referral',  'contacted',
      4, null::integer, null::integer, null::integer, null::text,
      'Referred by Aarav Deshpande. Wants an evening slot.'),
  (4, 'Farhan Shaikh',   'farhan.shaikh@example.com',   'phone',     'contacted',
      4, null::integer, null::integer, null::integer, null::text,
      'Called about PT pricing, sent the package details.'),
  (5, 'Anita Chowdhury', 'anita.chowdhury@example.com', 'google',    'trial_scheduled',
      1, 2, null::integer, null::integer, null::text,
      'Free trial booked for the morning batch.'),
  (6, 'Dev Kapoor',      'dev.kapoor@example.com',      'website',   'trial_done',
      2, -3, null::integer, null::integer, null::text,
      'Trial done, deciding between quarterly and half-yearly.'),
  (7, 'Lakshmi Iyengar', 'lakshmi.iyengar@example.com', 'referral',  'converted',
      -- -41 is member 30's joined_on: (today + 84 - 90) - (5 + 30). The lead and
      -- the member it became have to agree about when that happened.
      3, -45, 30, -41, null::text,
      'Converted onto the quarterly plan after the trial.'),
  (8, 'Sunil Barot',     'sunil.barot@example.com',     'other',     'lost',
      4, null::integer, null::integer, null::integer,
      'Joined a gym closer to home',
      'Price was fine, distance was not.')
) as l(n, full_name, email, source, stage, staff_no, trial_day_offset,
       converted_member_no, converted_day_offset, lost_reason, notes)
cross join today t
on conflict (id) do update set
  branch_id            = excluded.branch_id,
  full_name            = excluded.full_name,
  phone                = excluded.phone,
  email                = excluded.email,
  source               = excluded.source,
  stage                = excluded.stage,
  assigned_to_staff_id = excluded.assigned_to_staff_id,
  trial_at             = excluded.trial_at,
  converted_member_id  = excluded.converted_member_id,
  converted_at         = excluded.converted_at,
  lost_reason          = excluded.lost_reason,
  notes                = excluded.notes;


-- ---------------------------------------------------------------------------
-- 24. Eleven notifications: the renewal nudge on each of the five memberships
--     expiring this week, and the win-back push on each of the six retention
--     cases. dedupe_key is index-derived and never shifts, so PAY-002's partial
--     unique index holds across re-runs.
-- ---------------------------------------------------------------------------

with roster as (
  select
    n as idx,
    case when n <= 5 then 'renewal_due' else 'winback_absent' end as template_key,
    case when n <= 5 then n else 60 + n end as days_to_expiry,
    case n when 6 then 11 when 7 then 13 when 8 then 15
           when 9 then 16 when 10 then 18 when 11 then 20 end as absent_days
  from generate_series(1, 11) as n
),
today as (select (now() at time zone 'Asia/Kolkata')::date as d)
insert into public.notifications (
  id, tenant_id, member_id, channel, template_key, status, dedupe_key,
  scheduled_for, sent_at, delivered_at, related_type, related_id, payload
)
select
  ('00000018-0000-4000-8000-' || lpad(r.idx::text, 12, '0'))::uuid,
  '00000001-0000-4000-8000-000000000001'::uuid,
  ('00000005-0000-4000-8000-' || lpad(r.idx::text, 12, '0'))::uuid,
  'push',
  r.template_key,
  case when r.idx <= 5 then 'sent' else 'delivered' end::public.notification_status,
  'seed:' || r.template_key || ':' || lpad(r.idx::text, 4, '0'),
  case when r.idx <= 5
       then ((t.d + r.days_to_expiry - 7) + time '10:00') at time zone 'Asia/Kolkata'
       else ((t.d - (r.absent_days - 8)) + time '10:00') at time zone 'Asia/Kolkata'
  end,
  case when r.idx <= 5
       then ((t.d + r.days_to_expiry - 7) + time '10:00') at time zone 'Asia/Kolkata'
       else ((t.d - (r.absent_days - 8)) + time '10:00') at time zone 'Asia/Kolkata'
  end,
  case when r.idx <= 5 then null
       else ((t.d - (r.absent_days - 8)) + time '10:01') at time zone 'Asia/Kolkata'
  end,
  case when r.idx <= 5 then 'membership' else 'no_show_case' end,
  case when r.idx <= 5
       then ('00000006-0000-4000-8000-' || lpad(r.idx::text, 12, '0'))::uuid
       else ('00000013-0000-4000-8000-' || lpad(r.idx::text, 12, '0'))::uuid
  end,
  case when r.idx <= 5
       then jsonb_build_object('days_from_expiry', -7)
       else jsonb_build_object('absent_days', r.absent_days)
  end
from roster r
cross join today t
on conflict (id) do update set
  member_id     = excluded.member_id,
  channel       = excluded.channel,
  template_key  = excluded.template_key,
  status        = excluded.status,
  dedupe_key    = excluded.dedupe_key,
  scheduled_for = excluded.scheduled_for,
  sent_at       = excluded.sent_at,
  delivered_at  = excluded.delivered_at,
  related_type  = excluded.related_type,
  related_id    = excluded.related_id,
  payload       = excluded.payload;


-- ---------------------------------------------------------------------------
-- The receipt book knows what the seed issued.
-- ---------------------------------------------------------------------------
--
-- **The seed issues receipt numbers, so the counter has to know.** It writes
-- them through `app.stamp_payment()`'s trusted-writer path, which keeps a
-- supplied number and — correctly, for a webhook — does not advance
-- `document_counters`. The moment the seeded numbers moved into the allocator's
-- own `FY/NNNNNN` grammar, that left a freshly seeded gym holding
-- `2026-27/000001` with no counter row at all, so the first payment taken at the
-- desk allocated `000001`, collided on
-- `payments_tenant_id_receipt_number_key`, and **the failing insert rolled the
-- counter's own increment back with it** — so the next attempt collided on the
-- same number, for ever. Cash taken, nothing written, and a retry that can never
-- succeed. That is the exact harm `payment-record/spec.md` names under "A
-- receipt number is the counter's alone", reached by the one writer the
-- requirement's own subject line puts outside itself.
--
-- The instrument is the one that requirement already sanctions — "Staging a
-- counter forward … SHALL succeed, leaving a gap".
--
-- **The `where` clause is the whole rule and `greatest` was the wrong tool.**
-- `greatest` does not keep a write forward-only; it guarantees an EQUAL write
-- once the counter has caught up, and `app.enforce_counter_monotonic()` refuses
-- `new.next_number <= old.next_number` — so the second seed run raised `GL037`,
-- and so would the first push after anyone took a payment at the desk. The
-- `where` makes the conflicting row simply not update, which is what "a re-run
-- moves nothing" has to mean.
--
-- **And the measurement that passed it was a no-op.** "Seed clean, run twice"
-- held only because every receipt number already on the live project still uses
-- the abandoned `RCPT/` grammar, so this block selected zero rows and did
-- nothing at all — the identical blind spot this comment block diagnoses two
-- paragraphs above, in the code written to fix it. A seed check has to run
-- against a gym where the seed's own rows do not already exist.
insert into public.document_counters (tenant_id, kind, financial_year, next_number)
select p.tenant_id,
       'receipt',
       split_part(p.receipt_number, '/', 1),
       max(split_part(p.receipt_number, '/', 2)::int) + 1
  from public.payments p
 where p.tenant_id = '00000001-0000-4000-8000-000000000001'::uuid
   and p.receipt_number is not null
   and p.receipt_number ~ '^[0-9]{4}-[0-9]{2}/[0-9]+$'
 group by p.tenant_id, split_part(p.receipt_number, '/', 1)
on conflict (tenant_id, kind, financial_year) do update
  set next_number = excluded.next_number,
      updated_at  = now()
  where excluded.next_number > public.document_counters.next_number;
