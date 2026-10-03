# TRV — My clients today

**DRAFT NOT FROZEN — early public contract, 2026-10-03.** No tests, build,
deployment, schedule change or owner approval is implied. Wave D / V2-D2 remains
after Wave C. Freeze after closed-test feedback and owner approval, then commit
the spec before commissioning independent tests. Read with F12 in
`docs/planning/v2-feature-map.md`, `docs/planning/v2-campaign-goal.md`,
`docs/design/v2/trv-bar.md` and the approved PTF proposal/bar.

## Outcome and scope

An authenticated, active, linked trainer opens a daily work list, sees their own
PT sessions in time order, and sees the relevant sold pack's truthful usage,
reservation count and expiry beside each client. This is a read-only PT view.
It adds no booking, cancellation, completion, waiver, payment, identity grant,
member-contact projection, table, column, policy or RPC. Existing permitted
fulfilment remains in its existing flow; this contract adds no mutation button.
CLS remains a dependency in campaign order but class rosters are not silently
folded into a PT client list. A later combined timetable needs a separate
approved scope, its existing CLS reads, and independently specified client data.

## Reuse finding and exact public seam

**PTF already fulfills the required database read scope.** PTF-022/032 and the
registry fix the following caller-scoped, STABLE authenticated reads. They are
the only source of session/client/pack facts for TRV:

- `public.read_pt_bookings(p_from timestamptz, p_to timestamptz,
  p_trainer_staff_id uuid default null, p_status public.booking_status default
  null, p_limit integer default null, p_after_starts_at timestamptz default null,
  p_after_id uuid default null)` returns `session_id`, `order_id`, `member_id`,
  `member_name`, `member_code`, `trainer_staff_id`, `trainer_name`, `starts_at`,
  `ends_at`, `timezone`, `status`, `consumed`, `cancelled_at`, `sessions_total`,
  `sessions_used`, `sessions_remaining`.
- `public.read_pt_packs(p_trainer_staff_id uuid default null,
  p_state public.pt_pack_state default null, p_limit integer default null,
  p_after_id uuid default null)` returns `order_id`, `member_id`, `member_name`,
  `member_code`, `trainer_staff_id`, `trainer_name`, `trainer_active`,
  `programme_name`, `sessions_total`, `sessions_used`, `sessions_scheduled`,
  `sessions_remaining`, `starts_on`, `expires_on`, `state`, `timezone`.

Use the original caller's Supabase client and PTF's pagination/cursor semantics,
not service credentials. A trainer supplies no selectable trainer filter; both
calls default to own scope. Explicit other-trainer input produces zero rows per
PTF-022, not a new refusal code. Cross-tenant targeting exposes no row. Invalid
or stale binding/role/tenant/user claims retain PTF actor rejection (`42501`).
PTF's member loaders `loadMemberTraining` / `loadTraining` are member-only and
must not be called from this staff screen. The frozen public PTF console packet
now declares `loadPtBookings`, `loadPtPacks`, `loadTrainerChoices`,
`VerifiedConsoleViewer` and `PtReadSection`. Web TRV composes those existing
single-page adapters; it does not introduce a shared RPC adapter or a second
web read dialect. Read [the proposed TRV declarations](public-declarations.md)
with `../pt-front/web-console-public-declarations.md` before independent fanout.

## Consumers, types and dependencies (proposed, not registered exports)

Web consumer: trainer rendering of existing
`apps/web/app/(console)/training/page.tsx`; retain other staff's PTF rendering.
Native consumer: proposed `apps/mobile/app/(desk)/training.tsx`, reached by a
trainer-only “My clients today” entry in the existing desk navigation. That
placement remains an owner choice. Reuse `useMobile`, verified
`GymloopIdentity`, `requireAudience` / `readIdentity`, and the current
staff/trainer binding checks. Native staff routing already exists; no new role,
claim, root audience, login path or persisted capability is proposed.

Reuse PTF `StaffBooking` (including nullable `cancelled_at`), `StaffPack` and
`PtReadSection`. Native documentation aliases derive from the same generated
RPC row types, with the same nullable cancellation correction; native imports
no web runtime. Canonical status/state come from generated enums. Preserve the
RPC's snake_case shape and exact balances; no second balance model is proposed.

Web orchestration exhausts existing `loadPtBookings` / `loadPtPacks` pages.
Native needs a caller-bound host, read coordinator hook and screen declarations
because PTF's published native loaders are member-only. Their precise proposed
boundaries are in `public-declarations.md`; they are platform adapters for the
same public RPC/section contract, not new shared exports or authorization.
Existing `loadTrainerChoices` metadata supplies the own trainer's branch/gym
resolved timezone even when bookings and packs are successfully empty. Native
uses only the same published safe choices projection under caller RLS. Missing
or failed own timezone metadata prevents day reads, rather than inferring a
zone from the first session, device, or a fabricated default.

The booking and pack sections fail independently with null data and sanitized
errors. Successful bookings survive a pack failure with explicit unavailable
pack facts. Failed booking pages never become a successful empty day or a
partial complete list. Successful pack sections are joined by `order_id` only
after all pages complete. See the companion for cursor progress and freshness.

No SDK dependency, native package, money helper or runtime environment variable
is planned. Proposed host/hook/screen exports require the usual registry review. Shared remains platform-free and uses its
existing type-only `@gymloop/db` dependency. Reuse PTF `ptPackStateLabel`,
`ptBookingStatusLabel`, `ptApiError`, `PT_BOOKING_LIMITS`, existing page-size
constants, `businessNouns`, `toLocalDate`, `offsetInstantFromGymWallTime`,
`formatDateTime`, `UI_TOKENS`, web `StatusWord` and native Chalkline primitives.
Before any new export, repeat the registry/code search and record a reuse gap in
`docs/decisions.md`; register every final export and actual consumer in the build
unit. This draft authorizes no registry or decision edit.

## EARS requirements

- **TRV-001 (entry).** WHEN a verified real trainer opens Training THE SYSTEM
  SHALL show “My clients today” for their current binding only. WHEN role,
  binding, tenant or authenticated subject becomes invalid THE SYSTEM SHALL
  clear loaded client facts and use the existing session/access outcome; cached
  identity SHALL NOT grant access. Other staff keep their existing PTF surface.
- **TRV-002 (day).** WHEN the view first loads THE SYSTEM SHALL select today's
  calendar date in the trainer's branch timezone, falling back to the gym zone
  exactly as PTF does, and SHALL show the selected absolute date and zone.
  WHEN previous day, next day, Today or the date picker is used THE SYSTEM SHALL
  request that date's local-midnight inclusive / next-local-midnight exclusive
  instant range, not UTC midnight or a fixed-duration subtraction. Invalid or
  ambiguous local conversion SHALL fail honestly, never guess a zone. Session
  inclusion follows starts_at, including one ending after midnight. If device
  and trainer zones differ, the trainer zone SHALL remain visible.
- **TRV-003 (sessions).** WHEN reads succeed THE SYSTEM SHALL render every own
  session starting in that day, including terminal outcomes, ascending by
  `(starts_at, session_id)` per PTF, with member name/code, local start/end,
  canonical status word and programme/pack facts joined by `order_id`, never by
  client name. Multiple sessions/packs SHALL remain distinguishable. Status
  labels SHALL reuse PTF's effective consumed flag, including waived outcomes.
- **TRV-004 (pack truth).** WHEN showing a session's pack THE SYSTEM SHALL show
  returned `sessions_total`, `sessions_used`, `sessions_scheduled`,
  `sessions_remaining`, `starts_on`, `expires_on` and `state` distinctly. For
  non-expired packs the label is “N left to book”; for expired packs it is “N
  unused · expired” with actual scheduled count still shown. The approved
  PTF-005/018 remaining equation, late-cancel consumption, no-show zero usage,
  scoped waiver and reassignment remain exclusively PTF's facts. THE SYSTEM
  SHALL NOT recalculate, sum different packs, promise expired booking or infer
  refunds/payment values. The expired exception is not a new calculation here.
- **TRV-005 (complete reads).** WHILE a result has another PTF keyset page THE
  SYSTEM SHALL continue through every page before presenting a complete day. The default page cap SHALL NOT hide later clients.
  Pack paging SHALL complete before joining displayed orders. WHEN pack paging
  fails or a pack is absent after complete paging THE SYSTEM SHALL show “Pack details aren't
  available. Refresh to try again.” rather than zero or another client's pack.
  No count badge is required; any count SHALL describe loaded sessions, not
  distinct clients or all-day completeness unless that is proven.
- **TRV-006 (read scope).** WHEN any row is loaded THE SYSTEM SHALL use only
  `read_pt_bookings` / `read_pt_packs` under the original trainer JWT. Other
  trainer/cross-tenant rows SHALL never enter the view. The necessary rendered
  client fields are name and member code only; member/order/session identifiers
  are internal join keys. Phone, email, guardian data, health data, contact
  actions, payment amounts, raw notes and identity fields SHALL NOT be added.
  THE SYSTEM SHALL NOT query `members`, `pt_sessions` or `addon_orders` to fill
  missing facts, nor introduce an owner preview exemption to trainer entry.
- **TRV-007 (empty/error).** WHEN complete successful reads return no sessions
  THE SYSTEM SHALL show “No clients scheduled for this date.” and Today/date
  controls. WHEN loading THE SYSTEM SHALL show an announced loading state.
  WHEN a request fails THE SYSTEM SHALL show “Couldn't load your sessions.”
  with Refresh; a successful independent pack section SHALL NOT turn that
  booking failure into an empty day. Permission failure SHALL follow existing generic access copy,
  with no client existence hint. Empty SHALL never substitute for failure.
- **TRV-008 (offline/freshness).** WHEN offline THE SYSTEM SHALL show “You're
  offline. Connect to load your sessions.” and Refresh; it SHALL queue no write
  and persist no new client cache. Previously loaded in-memory rows may remain
  only for the same verified identity and date, visibly “Last loaded; refresh
  when connected.” with no claim of current balance. WHEN identity/date changes
  THE SYSTEM SHALL clear those rows. WHEN Refresh succeeds THE SYSTEM SHALL
  replace both reads; mismatched/partial reads SHALL be visibly incomplete.
- **TRV-009 (race).** WHEN a newer date/refresh request supersedes an older one
  THE SYSTEM SHALL discard the older result. WHEN a server-side completion,
  cancellation, expiry, waiver or reassignment changes a pack THE SYSTEM SHALL
  show refreshed server facts, without optimistic balance changes. Two reads
  are not claimed to be a transactionally frozen snapshot; partial/missing
  joins get TRV-005's explicit unavailable state.
- **TRV-010 (accessible Chalkline).** WHILE rendering any state THE SYSTEM SHALL
  meet every criterion in the draft TRV bar in light/dark, 390/1440px, 200% text,
  keyboard/screen reader and reduced motion. A selected date SHALL have an
  accessible full-date name; status SHALL be dot plus word; refresh/state changes
  SHALL be announced without stealing focus.
- **TRV-011 (read-only).** WHEN navigating or refreshing THE SYSTEM SHALL write
  no PT, order, payment, audit, notification or attendance fact. TRV SHALL NOT
  duplicate PTF booking locks, calendars of availability or money logic. Existing
  trainer completion authority and binding validation SHALL remain unchanged.

## Owner choices before freeze versus routine reuse

Owner approval is required for this final EARS/bar and the proposed native entry
placement after closed-test feedback. Advancing TRV across waves requires an
explicit owner build-order decision. A combined CLS/PT timetable or fulfilment
actions would change this scope and require approval, not an implementation
shortcut. Reusing PTF reads, Chalkline, generated types and verified session
checks is routine and creates no owner question.

**OPEN-015 remains a security decision, not solved by this screen.** Approved
PTF-022/032 provides own-trainer RPC projection, but pre-existing direct-table
trainer reads of `pt_sessions`, `addon_orders` and broader member fields remain.
This draft promises own-client scope for TRV, not database-wide prohibition of
every legacy trainer read. Before freeze the owner must either accept that
documented residual for this surface or commission separate narrowing of the
legacy grants/policies with full-blind authoring and all affected regressions.
No policy change or extra table is justified for this read-only view. Any later
need must be recorded as a decision before work, outside this draft's file scope.

## Tests-first and actual end-to-end acceptance plan

After approval/freeze, commission implementation-blind visible and independent
holdout authors from these public requirements/bar only. Holdout reads neither
visible tests nor implementation; implementer reads neither held suite nor its
fixtures. Commit tests red separately before build. Cover day/zone boundaries,
cursor overflow, multiple packs, absent/error joins, cancellation/waiver/expiry
parity, stale responses, offline identity clearing and every denied audience.
Reuse PTF balance/actor tests without changing them; add independent TRV consumer
tests. If OPEN-015 narrowing is chosen, isolate its full-blind policy work first;
do not fan out against a changing claim/read contract. pgTAP stays BEGIN/ROLLBACK.

Actual browser acceptance signs in as a real trainer, opens the navigation entry,
changes day, refreshes after an existing authorised PTF outcome, and compares
displayed facts to the approved RPC response. Use two same-tenant trainers plus
another tenant to verify refusal; exercise offline/error/reconnect and paging
through the actual route, not only adapter doubles. Capture both themes at
390/1440, 200% text, keyboard and accessibility tree/axe results.

Actual Android acceptance uses the installed native app and verified trainer
session, opens its entry, changes gym-local date, refreshes and disconnects/
reconnects; checks large text, TalkBack, theme and account switch clearing.
Record build identity, environment, role, selected date/zone and observed result
without member PII in shared evidence. Native mocks or mobile browser emulation
cannot stand in for that run; missing device evidence means native unverified.
This draft does not perform phone, cloud or acceptance work.

Fresh-context critic evaluates every bar item; missing evidence cannot be GO.
Three failures of one dimension escalate to the owner. After all applicable gates
pass, push coherent green units on main, archive into current specs, register
final exports/consumers and record evidence. Batch-2 verification is unaffected.
