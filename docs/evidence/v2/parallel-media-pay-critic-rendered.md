# Fresh rendered-review critic — PAY proof upload surfaces (2026-10-04)

Scope: `apps/web/app/member/buy/purchase-actions.tsx`, `apps/web/app/member/buy/[requestId]/page.tsx`,
`apps/mobile/app/(member)/buy.tsx` only. Judged against `docs/design/v2/pay-bar.md` + Chalkline kit.

## Render method actually used

- Live dev server **could not boot**: pre-existing working-tree route conflict
  `apps/web/app/api/member/notifications/[id]` vs `[notificationId]`
  (`You cannot use different slug names for the same dynamic path`). Not fixed
  by this critic (other agents' files). **No live browser render happened.**
- Fell back to component-level render: temporary vitest harness (mocks copied
  from the committed `purchase-visible-proof-surface.test.tsx` patterns) dumped
  static HTML for every fixture-reachable state to `docs/evidence/v2/media/*.html`
  (11 files: detail ×8, list ×2, load-error). Harness deleted after the run;
  no source or test file edited.
- Committed screen tests re-run as critic evidence: native 4/4 pass; web surface
  3/4 (the one failure is the already-escalated test-vs-test conflict, below).

## Per-check findings

- ✅ PASS Copy truth: no "payment successful"/"bank verified" in any rendered state; upload copy names JPG/PNG/WebP + 2 MB; "Pending verification" label present (BUY-022).
- ✅ PASS Rejected proof: exact desk reason rendered + "Re-upload payment screenshot" affordance, at `owner_accepted`.
- ✅ PASS Money: exact `formatMoney`, paise-derived (₹1,999 from 199900), tabular context preserved.
- ✅ PASS Terminal states: mismatch shows quoted/received/difference + honest desk-resolution copy; recorded shows genuine receipt only; expired/cancelled/rejected keep status + reason.
- ✅ PASS Error/empty: load-error has honest alert + Retry; empty list has next actions.
- ✅ PASS Structure: `<ol aria-label="Request progress">`, `aria-label="Request detail"`, `cl-panel`/`cl-btn` Chalkline tokens only.
- ⚠ MINOR: StageList marks the current stage with `<strong>` only — pay-bar 8 wants "word plus visual mark"; past stages carry no completion mark.
- ⚠ MINOR: `cancelled` detail shows status + amount but no specific next-action copy (pay-bar 7).
- ⚠ MINOR: list page repeats "raise a request" guidance three times (intro, empty text, CTA section) — wordy, not blocking.
- ❌ CONFLICT (already escalated to owner, not resolved here): `purchase-visible-proof-surface.test.tsx:58` blanket-forbids the string "Payment recorded" at `payment_proof_uploaded`, but pay-bar criterion 3 and `purchase-wording.ts` require the ruled four-stage sequence where "Payment recorded" is a stage label, not a payment claim. Critic reading: the surface test's regex is over-broad (it catches the stepper, not a state claim); needs owner `spec:` adjudication.

## Not renderable yet (explicitly NOT passed)

- Interactive upload flow: file-picker, rejected-file, permission, in-progress,
  retry-during-failure, offline tap (web), private proof preview — need the
  Edge/DB integration plus a live session; the source implementer's
  `proofUploadUrl` wiring is untestable without a booting server.
- Visual bar items: light/dark contrast, 200% text wrap, 320/1440 overflow,
  touch-target measurement, reduced motion — static HTML carries no CSS; the
  dev-server blocker prevented viewport rendering.
- Native screen judged by code + committed test render only (no device, per
  directive): kit components, honest interim "Photo upload is not available in
  this build yet" pending the `expo-image-picker` owner decision, offline guard
  precedes any action.

## Verdict

**GO-WITH-FIXES** for the rendered-reachable surface (three minor copy/mark
findings, none money- or privacy-affecting). **Full GO is blocked**, not
refused: interactive and visual criteria are not renderable until the
pre-existing notifications route conflict is resolved and the proof transport
is live. A missing live upload/private-access-refusal demonstration still
blocks pay-bar GO regardless.
