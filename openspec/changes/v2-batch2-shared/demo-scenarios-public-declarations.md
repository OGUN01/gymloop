# Batch-2 public demo fixture declarations

Frozen engineering fixture contract, 2026-10-03. Implements existing approved
demo requirements; creates no new commercial, identity or business-rule choice.
The consent recorded_at exception in `demo-consent-clock-declarations.md`
supersedes only this packet's historical consent clocks and defines genuine
server-time/audit preservation. All other fixture clocks and shapes remain.
The verification composition correction in `demo-proof-composition-declarations.md`
supersedes the original complete-file replay protocol below: unchanged legacy
setup precedes every exact baseline; the new packet alone executes twice.
Separate visible/holdout post-seed SQL authors precede the separate seed builder.
Their complete rollback-only verification files live at
`supabase/tests/support/v2-batch2-demo-seed-visible.fragment` and
`supabase/tests-holdout/support/v2-batch2-demo-seed-held.fragment` respectively.
The primary splices the ordinary seed and scenario files into those verification
transactions and checks exact pgTAP counters after two legal scenario executions.
CI seed-dry-run runs them after the ordinary schema pgTAP job. This arrangement
keeps seed verification independent of whether the live demo was permanently
seeded; permanent application remains the manual CI seed workflow only.

Verification splice protocol: immediately after BEGIN the primary inserts
ordinary seed.sql once. Authors then capture rollback-only TEMP baselines for
the original 30 members, their sold membership facts, and existing product
terms/money/stock (category_id and ordinary updated_at are allowed to change).
Capture any existing owned closure/version clock to prove its immutable replay.
At the literal comment `-- ROOT_INSERT_BATCH2_SCENARIOS_HERE` the primary
inserts complete seed-scenarios.sql twice. Assertions follow that marker.
No fixture deletion, persistent writes from the author, or guessed legacy prices
are required. Exact approved schema declarations are in the seven proposals
and the canonical generated packages/db/types/database.ts declarations;
authors may read those declarations, never migration/reader/seed implementations.

Public engineering packet for independent fixture tests before a separate seed builder.
This declares seed data and runtime verification separately; it is not execution,
acceptance evidence, a business-contract amendment, or a Wave C/D freeze.
Authority: the seven accepted proposals and their owner-approved amendments.

## Stable boundary and replay

- Reuse tenant `00000001-0000-4000-8000-000000000001`, default branch
  `00000002-0000-4000-8000-000000000001`, trainers Rohit/Meera/Arjun at
  `00000003-0000-4000-8000-000000000001` through `…000003`, and front desk
  Divya at `…000004`. Aarav remains member
  `00000005-0000-4000-8000-000000000001` with his existing linked account.
- Do not modify the original 30 member rows, existing scenario members 101–116,
  auth users/bindings, staff identities, account credentials, sold membership/PT
  terms, payments, GST, product price/stock/terms, attendance, check-in settings,
  or existing holiday rows. No new auth identity or guardian marker is seeded.
- New fixture IDs use `000000NN-0000-4000-8000-000000000iii`: NN=80 members,
  81 memberships, 82 services, 83 rules, 84 sessions, 85 bookings, 86 holiday,
  87 notifications, 88 categories, 89 announcements, 90 versions, 91 consents.
  These are seed namespaces, not exported constants or test namespaces.
- On the first run compute one instant R and local date T in the demo branch/gym's valid
  `Asia/Kolkata` zone. Calendar offsets below mean local dates; times mean local
  wall times resolved into instants. Never use UTC `current_date`.
- Seed once, atomically: under a transaction-scoped lock for this packet/tenant,
  either every owned row is absent and the complete graph is inserted, or the
  complete graph exists and is verified without any write. No repair of a partial
  graph. Any missing/colliding/mismatched row, ownership or foreign relation
  refuses the whole transaction. Check natural keys before inserting; do not
  steal an existing row by upsert. Existing SHP category assignments must match
  on replay; the first-run assignments are this packet's only existing-row edits.
- Recover the initial R deterministically from closure announcement NN=89 iii=1:
  R = published_at + 10 minutes; T = R's date in Asia/Kolkata. Its version-1
  created_at must equal published_at, and both announcements/versions must agree
  on that clock. Verify the full graph against this original anchor, never today's
  date. All explicit fixture clocks (including created_at and cancelled_at) derive
  from initial R; preserve them forever on replay. The initial owner identifiers
  come from the stored immutable closure/version creator and must still reference
  their original tenant binding; an ordinary later owner deactivation does not
  authorize replacing history or require a fresh publisher for a no-op replay.
- No teardown, delete, trigger disabling, forged command settings, re-dating,
  mutable sold-term changes or fabricated audits. Replays preserve exact static
  counts and every original date/history row. Runtime commands use separate
  ordinary records and real history, outside these static-count expectations.

## Shared new member cohort

Four unlinked, unerased members in the existing branch, codes B2D201–B2D204,
phones +919876720201–+919876720204; IDs NN=80, iii=201–204:

| iii / name | Member / membership | Dates | Latest marketing consent |
|---|---|---|---|
| 201 Demo Asha Grant | active / active | T−30 through T+30 | granted |
| 202 Demo Bela Withdrawn | active / active | T−30 through T+30 | grant then withdrawal |
| 203 Demo Charu Unasked | active / active | T−30 through T+30 | no marketing row |
| 204 Demo Dev Regranted | expired / expired | T−60 through T−1 | grant, withdrawal, re-grant |

Membership IDs use NN=81 and the same iii; reuse existing Monthly plan
`00000004-0000-4000-8000-000000000001` and its exact list price, currency and
duration on insertion, with discount zero and no synthetic payment/grant.
No null/different sold terms or revived expired memberships. If existing guards
prevent this static insertion shape, the builder must flag it before execution.
Initial adult DOB is T minus 25 calendar years, solely on these explicitly synthetic
members. Consent IDs NN=91, iii=1 for 201; 2–3 for 202; 4–6 for 204,
strictly ordered at R−6 through R−1 minutes; existing consent version/source
requirements and Divya's staff attribution apply. Service consent is absent:
it must not affect either in-app announcement category. Cohort expectations:
4 unerased adult fixtures, 3 live memberships, 1 lapsed, 2 latest marketing grants.
ANC's approved glossary explicitly defines good standing as active, paused or
expired with erased_at null; consequently 204 qualifies for all_members even
though its membership is not live.

## CLS — mandatory CLS-038 graph

Exactly four services NN=82 iii=1–4, sort orders 10/20/30/40, durations 60 minutes:
`Demo Yoga` (active), `Demo Strength` (active), `Demo Dance` (active),
`Demo Archived Pilates` (inactive). Default capacities 6/2/6/6.
Three active weekly rules NN=83 iii=1–3, Monday Yoga 07:00 with Rohit,
Wednesday Strength 18:00 with Meera, Friday Dance 18:00 with Arjun;
valid T through T+27. Every generated session has its rule's assigned trainer.
There are 12 candidate occurrences in this 28-day interval; materialize only
non-holiday occurrences, excluding existing holidays as well as the new one;
owned occurrence IDs NN=84 iii=101–112 are ordered by local date, then rule iii.
Keep rule/date identities consistent; no 24:00 or next-date relabelling.

Six additional one-off sessions NN=84 iii=1–6, all assigned Rohit, are:

| iii | Service / time / capacity | Bookings and observable state |
|---|---|---|
| 1 | Yoga T+1 08:00–09:00 / 6 | none; open, six spots, server pre-booking deadline |
| 2 | Strength T+1 18:00–19:00 / 2 | 201 and 202 booked; full, two holding, zero spots |
| 3 | Dance T+2 18:00–19:00 / 6 | cancelled, reason `Demo instructor unavailable`; Aarav and 201 `session_cancelled` |
| 4 | Yoga T+3 08:00–09:00 / 6 | 203 booked; holiday, closed to new bookings, retained booking |
| 5 | Yoga R+60 through R+120 minutes / 6 | Aarav booked; within default two-hour window, cannot cancel |
| 6 | Dance T−1 18:00–19:00 / 6 | 204 still booked; ended, Not marked, roster No live membership |

Exactly seven bookings NN=85 iii=1–7 in table order above (2+2+1+1+1).
Book rows identify only their specified member; no attendance/no-show/retention
rows are generated. Session 5 derives session_date from its actual local start,
including midnight crossover. Its cutoff is R−60 minutes under the existing
default; do not override a changed real gym policy silently. If policy is no
longer two hours, prepare a fresh runtime window scenario with the actual policy.

Holiday NN=86 iii=1 on T+3, `Demo class holiday`, scoped using the accepted
organization_holidays shape. Skip matching weekly occurrences on that date;
therefore rule occurrence count is 12 minus all holiday-matching occurrences.
If T+3 already has an existing holiday, reuse that row and add no duplicate;
the owned holiday count is then zero. Report the calculated count with the run.
The holiday one-off with a booking survives prune; it is not generated onto a
holiday by pretending booking guards permitted it. It represents a booking made
before that holiday was added. The runtime command sequence proves this history.

Exactly two cancellation notices NN=87 iii=1–2 for session 3, one each for Aarav
and 201: in_app, class_update, class_session_cancelled, related_type class_session,
related_id session 3, dedupe_key `class-cancelled:<session-3-id>:<member-id>`,
payload body/kind/sessionId/reason per CLS-011, sent through the ordinary legal
scheduled→sent lifecycle. Both lack any marketing/service-consent requirement.
These in-app notices have null template_id and recipient_phone; no outgoing
template or phone snapshot is part of the static fixture or accepted on replay.
201 remains unlinked and therefore contributes one to members_without_app.
Never revive cancelled session 3 on rerun. Static rows show the terminal state;
only an owner/manager cancel command proves atomic notices/audit/counters.

Within this owned graph: 4 services (3 active), 3 weekly rules, 6 one-offs,
12 minus holiday-matching weekly occurrences, 7 bookings, 0–1 added holiday,
2 notices. Limits remain the
accepted 28-day read horizon, durations 5–480 and capacities 1–500. Do not fill
limits merely to demonstrate them. Empty/loading/offline/permission failures,
marking, disable confirmations, kept-bookings edits and cutoff races require
runtime interaction, not additional fake rows. Lapsed member 204 cannot book
again; its historical booking remains visible to staff with the membership flag.

## ANC — closure, promotion and consent categories

Exactly two text-only published version-1 announcements NN=89 iii=1–2, versions
NN=90 iii=1–2, no image, no receipts, all_members audience (null segment fields):

- Transactional: `Demo closure notice`, body `The studio will be closed on the
  demo class holiday. Please check your class booking before travelling.`
- Promotional: `Demo PT offer`, body `Ask the front desk about the PT Starter
  programme. The programme price and terms are shown in Training.`

Published_at R−10 minutes; expiry T+7 23:00 local. Resolve the existing active
tenant gym_owner row whose user_id is the actual Auth identity for the documented
owner@ironbox.example.com sign-in; use that row's real staff/user identifiers
for lawful owner attribution. docs/demo-accounts.md says this row was created
outside seed.sql; neither seed file supplies its UUID. Zero/multiple matches,
unlinked/inactive/mismatched identity or unavailable Auth lookup must fail closed
before writing the packet; do not fall back to Divya, an invented actor or an
arbitrary tenant owner. Static publication is a represented state; only the
authenticated owner publish command proves actor validation and publish audit.
Do not seed a closed organization or alter opening hours to illustrate a notice.
Within the four-member cohort, closure reach is 4 and promotion reach is 2
(201/204). Both version states begin unread. Whole-gym counts also include
existing eligible members/consents and must be computed, never hardcoded to
these cohort numbers. Transactional first; latest marketing consent gates every
promotion exposure/read-marker/count. No ANC-generated notifications.
Receipt writes/version edits/take-down and permission-cache failures are runtime
scenarios. Keep caps below 10 live, 20 publishes/24h, 10 versions and 365-day
expiry; these two rows do not prove rate-limit acceptance. Live/not_live targeting
uses inclusive current gym-local dates under the approved ANC amendment.

## Other accepted features: minimal static additions and runtime obligations

- SHP: exactly two active categories NN=88 iii=1 `Demo Supplements` (sort 10),
  iii=2 `Demo Other services` (sort 20). Assign existing products
  `00000009-0000-4000-8000-000000000004` and `…000005` to Supplements,
  `…000003` diet_plan to Other services. PT products `…000001`/`…000002`
  remain Training programmes. Change category_id only; preserve prices, stock,
  GST and disclosures. No media objects, reservations, sale or stock movement:
  placeholder images are intentional. Reservation/checkout/live media are runtime.
- BIZ: leave demo type gym. Runtime platform command gym→dance→gym, with fresh
  request keys/expected values, establishes noun changes and two genuine audit
  events. No static audit or direct column flip substitutes for it.
- PLC: retain the four existing active plans and original sold terms. The accepted
  proposal explicitly uses ordinary authorized admin/API edits for current-price
  comparison, inactive held-plan and hidden-plan verification; capture/restore
  catalogue terms afterwards. Do not add an inactive fifth plan or mutate sold
  terms just to satisfy a demo screenshot.
- PTF: reuse existing PT products/orders/sessions unchanged. Owner/trainer saves
  real availability before member slot verification; there is no default window.
  Current policy is fetched per the approved read amendment; existing cancellation
  uses recorded start/end/duration. No invented pack, forfeiture, waiver, refund,
  availability or consent history is mandatory demo seed data in the proposal.
  Expired 10-total/3-used/2-scheduled example shows 7 unused and 2 scheduled;
  proving it or last-session waiver requires a separately lawful runtime sequence,
  not an inserted completed-pack marker or changed sessions_used.
- GRD: do not attest existing missing-DOB members, invent their DOB or stamp a
  guardian binding. Staff-command runtime scenarios cover known minor incomplete,
  consent absent/granted/withdrawn/stale, unknown DOB, adult and prospective
  invite routing; actual guardian redemption/handover needs an authorized spare
  Google identity. Operator-bound minor and guardian-bound adult/unknown-DOB
  copy require genuine binding provenance, never a seeded marker. Existing
  one-time attestation is owner-only and irreversible; no demo reset simulates it.

## Initial insert and current-time verification

Narrow production-guard inspection supports the initial static graph under the
existing postgres CI seed authority: CLS rule/session/booking guards are UPDATE
triggers, so valid INSERT shapes retain all table checks/FKs without rewriting
history; ANC header INSERT runs its timestamp trigger but freezes/transitions
only on UPDATE, and its version guard is UPDATE/DELETE only. Membership INSERT
requires periods_granted=0 (explicitly set here); date/term update exceptions are
unneeded. Notices must INSERT scheduled with null delivery evidence then take
the ordinary sent transition, letting existing financial/notification audit
triggers write their own events. No command audit is fabricated for represented
CLS/ANC terminal states. Static insertion does not prove command authorization,
booking eligibility at the historical moment, atomic cancellation or publishing.

CLS-038 requires the initial four-service/timetable/full/cancelled-with-notices/
holiday-with-booking/closed-window/lapsed shape declared above. No reviewed public
proposal explicitly demands immutable dates be rewritten on later calendar days.
Seed-once idempotence therefore needs no owner business exception. Later no-op
seed runs preserve initial facts; they do not refresh their current visibility.
For final runtime verification, compare the actual clock with the anchor. When
dates are stale, prepare current sessions through ordinary owner/manager commands,
book through the authorized member/desk path, add the holiday after booking,
cancel a booked session through the owner command and inspect its actual notices.
Use the current real cancel policy for a genuinely closed-window own booking.
Keep this genuine runtime history; do not reopen or replace static cancelled rows.
Current ANC cards similarly use real draft/publish commands when initial expiry
has passed. Report initial fixtures and current command verification separately.

GRD/PTF do not mandate an additive demo cohort; this packet therefore does not
invent one for them. PLC's explicit runtime-only plan edits govern its generic
optional seed-block sentence. CLS-038 cannot make every transient client state
static: a closed window becomes ended with time, and offline/permission/races
need the real caller and current clock. Real linked-member end-to-end
coverage currently belongs to Aarav; new synthetic members have no sign-in.
No identity provision, Cloud application, device exercise or business-guard
bypass is authorized by this packet. An actual initial INSERT rejection must be
reported with its exact guarded shape before implementation proceeds; no broad
administrative exemption or perpetual freshness claim is inferred.
