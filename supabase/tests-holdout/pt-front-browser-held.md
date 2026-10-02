# Independent PTF live acceptance protocol

This is required acceptance evidence, not a passed test report. Static rendering
cannot prove live events, native controls, actual RLS, persistence or races.
Only a reviewer/orchestrator may run this protocol; the implementer never reads
holdout artifacts. Use authorised demo fixtures, never a production mutation.

1. At 390px, select Training, a live pack, day, open time and Confirm. Record
   the four taps from Training, duration, trainer branch timezone, exact current
   booking consequence and dot-plus-word Booked. Accessible names include
   weekday/date/time. No unavailable time is selectable. Capture a no-availability,
   time-off and booking-window-empty case with known reason and next action.
2. Withhold a booking response, double-click, restore connection and retry.
   Observe one sheet session UUID reused for every retry and one booking; no
   optimistic success or queued command while offline. Cause a slot_taken
   conflict using a separate actor and observe pinned refusal plus refreshed
   slots, then a successful new choice. Repeat cancellation offline.
3. Set command clock at the cutoff and one millisecond after. At the cutoff
   cancellation is free; after it consumes exactly one under true policy and
   zero under false. Change policy after booking; cancel confirmation uses current
   policy. Compare rendered consequence to SQL cancellation output and stored
   frozen provenance. No-show uses zero; past unmarked Booked explains waiting
   for trainer rather than inventing a seventh status.
4. Expired active pack: ten purchased, three used, two genuine unclosed scheduled
   sessions, seven unused. Member and owner show two booked separately and no
   booking action. Forced booking refuses with no row/count/audit/notice change.
   Equivalent live fixture shows five left to book. Expiry never implies attendance.
5. Late cancel the tenth session of a nine-used pack. Owner/manager waiver with
   reason returns used to nine and completed to active within original validity;
   cancelled session stays cancelled, immutable consumed/completed_order remain,
   member shows Cancelled by you and one new bookable session. Explain original
   validity in confirmation. Replay after later expiry and after completion again
   returns current count without restoring twice or replacing reason.
6. Repeat completed-pack waiver with each same-tenant/payment refund lifecycle:
   requested, processing, completed partial/full and failed, arbitrary amount and
   currency. Every record blocks GL055 and all writes; unrelated tenant/payment
   does not. Ordinary attendance completion, expired/null-validity, missing causal
   marker and outstanding reservations remain unavailable. Ordinary active-pack
   waiver retains its existing rules. Front desk, trainer, member, platform and
   support preview cannot obtain waiver/policy/reassign controls or mutation.
7. Reassign source trainer's active packs to a same-branch active trainer. Before
   confirmation show the actual cancelled-session count. Future and past unclosed
   scheduled sessions cancel without consumption, completed history retains old
   trainer, sold totals/price/validity do not change. Unknown/foreign/not-PT or
   wrong-branch item rolls back the entire batch; already-target item is unchanged.
8. Save three weekly windows on the same screen; touching windows legal and
   overlap named next to offending rows before submit. DB also rejects overlap.
   Time-off lists impacted existing bookings and never pretends they auto-cancel.
   Trainer own profile excludes photo/listing controls. Owner photo consent text
   is visible; a withdrawn trainer image becomes placeholder on fresh read. Member
   asset-id-only read and original-JWT Edge exposure recheck must be traced by
   media acceptance; no private staff UUID/key/MIME/ETag projection appears.
9. Capture Chalkline light/dark at 390/1440, 200% text and reduced motion. Verify
   44px web/48dp Android targets, keyboard focus and axe. Run actual Android/iOS
   Training and booking screens; same counters/status/consequences, online-only
   commands and retained session UUID. Device timezone different from trainer
   explicitly names trainer timezone. Static Vitest is not native evidence.
10. Verify final Home/Classes/Shop/Activity/You navigation, Classes|Training mount
    and Gym screen. Superseded add-ons PT sections absent; both feature panes
    are usable. Compare captured operational clarity to fetched PTF bar reference.

DB concurrency, midnight lock wait, waiver-vs-refund/completion, notice/audit
rollback, immutable causal marker and exact direct-DML guard belong to independent
SQL acceptance. This app protocol does not claim them from mocked RPCs.
