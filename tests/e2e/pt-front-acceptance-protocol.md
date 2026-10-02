# PTF visible acceptance protocol — frozen before implementation

Status: **unexecuted, fixture dependent**. This protocol supplements the executable
`pt-front-*` suites. It is not evidence of a rendered screen, a database result,
a native-device pass or a Gauntlet win. Use only an explicitly approved test
environment. Fixtures must be provisioned by the authorised fixture owner; this
protocol neither provisions them nor mutates production. Record fixture ids
privately, screenshots, accessible trees, requests and before/after counts for
each executed case. Never record credentials, private storage metadata or member
contact details.

Use the frozen proposal, three approved PTF amendments, shared contract and PTF
bar as the oracle. Labels below describe accessible concepts, not invented exact
component props or unpublished copy. Where `ptCopy` supplies a label, select its
rendered accessible label. Do not add selectors or export factories solely for
tests. No ClassesPane is owned or created here.

## Required fixture manifest

- Complete member A and member B of tenant A; member C of another tenant;
  owner, manager, front desk, linked trainer A, linked trainer B, platform and
  read-only support-preview sessions. No invented demo manager address.
- Active listed trainer A with branch Asia/Kolkata; all-branch trainer B with
  gym fallback zone; inactive/unlisted trainer and a trainer at another branch.
- A live 10-session pack: 3 used, 2 scheduled, 5 left to book; an expired
  otherwise-identical pack: 3 used, 2 scheduled, **7 unused**, can_book=false.
  The two genuine scheduled rows remain booked and unmarked, with distinct
  historical times. The expired order remains active.
- Three nonoverlapping weekly windows, an overlap on the same weekday, a
  touching boundary, holiday, time off, occupied slot, no availability and an
  empty booking-window fixture. Session length 60, policy 24 hours/true plus
  separately controlled 0 hours/false and changed-policy fixtures.
- The ordinary four-tap booking test's first open slot stays outside the current
  cancellation window throughout execution, so its normal member cancellation
  in `finally` consumes no session. That cleanup targets only the session id
  returned by this test's successful non-replayed booking, never a pre-existing
  session. Retained cancelled history/audit is expected; no database reset or
  synthetic terminal state is permitted.
- A marked completed pack whose last session was consumed by that exact late
  cancellation; an ordinary attendance-completed pack; historical unmarked
  completed pack; active eligible waived cancellation; expired/refunded pack;
  null-validity pack; scheduled-reservation completed pack. Independently
  prepare same-tenant/payment refunds with requested, processing, completed and
  failed status, partial/full amount and alternate currency; also unrelated
  tenant/payment refunds. Do not manufacture causal provenance through UI.
- Trainer photos absent, valid currently exposed immutable asset, signer failure
  and withdrawn exposure. Public RPC fixtures have image_asset_id only.

## Browser member flow

1. Sign in member A; open `/member/classes/training`. Verify programmes are not
   selected and only offer “Show at the desk”, exact decimal-text price/currency
   and existing GST disclosure. Selecting creates no request/payment/order.
   Confirm profile, pack and session sections have independent loading/retry and
   the three frozen empty sentences. No other member's name or gym-side reason.
2. Inspect the live pack and expired pack using their distinct programme names.
   Live: purchased 10, used 3, booked 2, left to book 5. Expired: purchased 10,
   used 3, booked 2, unused 7, original validity and Expired wording. Expired pack
   has no enabled booking action. Directly opening its frozen booking route
   offers no slots. Reloading changes no count/status/attendance; compare staff
   `/training/packs` facts with the member facts. Do not recompute 7 as 5.
3. From Training, tap the live pack action, a day, an open slot, Confirm: four
   taps, zero typed fields. Before tap four, show 60-minute duration and exact
   `ptBookingConsequence` sentence with absolute branch-local cutoff. If device
   differs, name the zone. Slot accessible names include weekday/date/time;
   busy times are absent. Holiday/time-off/no-availability/window-empty fixtures
   each state a known reason and next action, without inventing a cause.
4. Open the booked session's cancellation confirmation. Before committing,
   show the exact current `ptCancellationConsequence` sentence. At cutoff, free;
   strictly after, one used only if flag true; zero-window/false remains free.
   Change the policy between booking and cancellation: re-evaluate, never reuse
   stale policy as a promise. After cancellation show dot and pinned status.
5. Capture the first booking POST body. Interrupt its **response after the test
   server accepts it**; do not simulate a proven rollback. Show no fake success,
   disable duplicate pending tap, and offer the retry sentence. Retry uses the
   exact same sessionId/orderId/startsAt. Replay returns replayed=true and the
   original booking. Fixture verifier proves exactly one session/reservation,
   one booking audit and zero new attendance/payment/refund/notice effects.
   Separate pre-send offline case sends nothing, queues nothing and never later
   submits automatically. A lost cancellation response similarly retries its
   same session id and consumes at most once.
6. Respond slot_taken to Confirm: pinned sentence and refreshed open list, no
   success. Run every pinned refusal and unknown fallback through the member
   command UI; codes/private details/ids never appear in error/log/URL.
7. Show Booked, Attended, No-show, Cancelled by you, Cancelled by your academy,
   Cancelled late - session used, each with a dot. Past unmarked booked rows
   explain the trainer must record them; no inferred attendance/completion or
   no-show consumption. Waived row is an effective nonconsuming cancellation;
   immutable provenance is not rewritten.
8. Confirm member-safe photos use generic `{assetId}` signing only. Null/failure
   renders placeholder. Withdraw exposure between read/sign: placeholder/refusal,
   never a key projection, privileged client or staff-id comparison. This app
   check does not replace SHP's publication-race and Edge parity tests.

## Browser console protocol

Run every operation for each role from the manifest. Public frozen routes are
`/training`, `/training/packs`, `/training/trainers`,
`/training/trainers/[staffId]`, `/training/policy`; verify actual configured
console prefix using rendered navigation, without inventing a route seam.

| Surface and EARS | Actions and visible expectations | Authority/no-change evidence |
| --- | --- | --- |
| Profiles PTF-001/002/003 | Owner/manager edits trimmed bio, unique specialities, listing and optional photo; save stays on page. Show exact trainer-photo consent sentence. Overlength/invalid values inline; upload pending/failure remains honest. Listing controls member bio/photo exposure; replacing/clearing uses existing MEDIA boundary. | Trainer sees own bio/specialities only; cannot list/set photo/edit another trainer. Front desk/member/platform/preview cannot submit. Reload proves refused attempts changed nothing. |
| Availability PTF-006/Q7 | Save three weekday windows without navigation; reload retains all three. Insert same-day overlapping window: offending rows name overlap **before submit**, request count stays unchanged. Touching and different-day windows remain legal. Submit a forged overlap body directly: server rejects and original windows remain. Clear all: no future slots, existing bookings unchanged. | Owner/manager any own-tenant trainer; trainer self only; all other identities refuse. Cross-tenant/unknown same generic outcome. |
| Time off PTF-007 | Add inclusive range and optional bounded reason; list affected existing bookings beside it. New slots disappear while old bookings remain. Remove twice: one effective removal, no duplicate effects. Inverted/invalid date/reason inline and server refusal. | Same bounded roles as availability; trainer cannot remove another trainer's entry. |
| Policy PTF-020/Q2 | Owner/manager sees window, consumption and duration with consequence sentences. Boundary values save; noninteger/out-of-range/off-step fails inline and server. Reload displays saved confirmation; member cancellation follows latest policy. | Front desk/trainer/member/platform/preview do not get writable controls; direct requests refuse. Preview may read allowed console surfaces only. |
| Reassign PTF-019/032 | Select source/destination and eligible packs; required trimmed 3..200 reason before Confirm. Show honest changed count from results, cancelled scheduled count and unchanged pack sold terms. Replayed unchanged packs do not inflate success. Completed and past unclosed sessions remain with old trainer; scheduled future sessions cancelled. Member receives the existing notice and sees original dates/balance. | Owner/manager only; destination must be eligible same-tenant trainer. Same trainer, invalid reason/batch and forbidden roles refuse with no changes. No claimed transfer when changed=false. |
| Gym cancel PTF-015 | Require reason; confirm marks Cancelled by your place, frees reservation, does not use a session; replay once. Future/current bounds and refusal copy match contract. | Owner/manager/front desk; trainer/member/platform/preview cannot mutate. |
| Scoped waiver PTF-016/Q4 | Exact causal completed-pack fixture: required reason; disclose one restored session usable only inside original validity. Successful response used 10→9, completed→active; cancelled session never reopened. Original validity/price/currency/payment unchanged, one effective audit/notice, no refund/charge. Retry after later expiry/completion remains replay without a second decrement. Active ordinary waiver remains unchanged. | Only owner/manager; ordinary attended completion, unmarked history, expired/refunded/null dates, reservation or **ANY same-tenant/payment refund row** (requested/processing/completed/failed, any amount/currency) refuses pack_unavailable. Unrelated tenant/payment refund does not block eligible causal fixture. Each refusal leaves counters/status/provenance/waiver/audit/notice unchanged. |
| Read scope PTF-021/022/032 | Owner/manager/front desk sees own gym; trainer own clients only, no phone/email. Foreign trainer filter is empty. Member sees only own packs/sessions. Staff expiry fixture displays 7 unused separately from 2 scheduled. | Read-only preview cannot gain mutation controls; wrong identities/foreign ids indistinguishable from unknown. Residual Phase-6 table reads are not presented as newly narrowed. |

Console and member checks run at 390/1440, both Chalkline themes, reduced motion,
200% text. No horizontal clipping, controls 44px minimum, axe clean, keyboard
focus visible and status not colour-only. Capture snapshots rather than declaring
a visual win from a test listing.

## Native acceptance protocol — public frozen seams only

Use `components/training-section.tsx` exported `TrainingSection`,
`app/training/book/[orderId].tsx`, `lib/training.ts` exports `loadTraining` and
`loadSlots`, and PTF-owned `SegmentedControl`. Central integrator mounts Training
under Classes; no invented props or alternate tab. Inspect the actual rendered
accessible tree after implementation. This protocol does not require a new
renderer/library, and cannot be marked passed by missing imports or source grep.

Executable native loader tests currently cover caller-bound reads and caller
changes. They do not execute offline command suppression, absence of a queue,
reconnect without automatic submission, pending double-tap suppression, or exact
booking/cancellation retry identity. The frozen native public functions are
`loadTraining` and `loadSlots`, both reads; commands live in the screen and
`TrainingSection` through `api.post`. Cases 5 and 6 therefore remain required
rendered/native acceptance evidence through those existing surfaces. No new
command export, injected component prop or test-only factory is implied.

1. Member-only booking screen: every nonmember identity redirects before data or
   command. Complete member loads through caller RPC projections; no private
   tables/key metadata. Photos call existing API generic `{assetId}` and
   unavailable photos use placeholder. Training exports are actually mounted.
2. On 390-equivalent narrow layout: pack → day → slot → Confirm, at most four
   taps and no typing; current pack has one clear action. Confirm contains
   duration and exact local consequence. Android targets at least 48dp (web
   44px is separately checked); no inaccessible nested touch target.
3. Run light/dark, OS text scale 200%, reduced motion and narrow/wide layouts.
   No clipping or hidden Confirm; selected Classes/Training announces its
   selected state; labelled slots contain weekday/date/time. Named trainer
   branch timezone wins; null branch uses gym fallback; device-different zone
   named. No fixed UTC/device-date grouping across midnight.
4. Render live 10/3/2/5 and expired 10/3/2/**7**, original dates and unbookable
   expiry. Status dots and all six pinned words match web. Past booked explains
   missing trainer record; no automatic attendance/no-show/completion. Programme
   price retains exact paise text and desk-only selection has no purchase side
   effect. Non-gym nouns come from businessNouns.
5. After online member A load, disconnect: last-loaded marker plus exact offline
   sentence, booking/cancel disabled, no queue/fake success. Sign out and sign in
   member B or different tenant offline: never show A's packs/trainer-photo URL,
   sessions or command key. Newly linked/revoked/changed identity similarly
   invalidates caller-owned state; reconnect does not flush a hidden command.
6. Interrupt accepted booking response and retry: exact original id/body, one
   committed session, truthful replay result; cancel consumes once maximum.
   Pending double-tap disabled; slot_taken refreshes list; per-section retry
   preserves successful sections without presenting stale pack as bookable.
7. Verify Home · Classes · Shop · Activity · You; Gym opens from Home/You,
   Classes | Training mounted coherently, superseded add-ons sections removed.
   Native stack registration uses the exact frozen booking route. Physical
   Android accessibility/48dp/tap/large-text evidence is separately required;
   iOS runtime is not claimed without its approved device validation.

## Execution record

For each numbered case/table row record: fixture manifest reference, identities,
environment/timezone/current policy, pass/fail/unexecuted, captured screen/tree,
network requests and independent before/after effect counts. Backend counter,
refund/provenance/race/rollback proof is owned by SQL acceptance; an app mock
asserting a refusal is not proof of the database boundary. Missing fixture or
device is **unverified**, never a skipped-pass or lowered bar.
