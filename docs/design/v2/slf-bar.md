# SLF quality bar

**FROZEN 2026-10-03.** Companion to
`openspec/changes/member-self-service/proposal.md`; the owner approved the bar
with the allowance contract frozen as today's source behavior (SLF-012) and
OPEN-016 recorded as a residual. No implementation or acceptance evidence is
claimed.

Primary official references opened 2026-10-03:

- [Microsoft Teams approvals](https://learn.microsoft.com/en-us/power-automate/teams/manage-approvals-app): sent/received request history, approve/reject decision and cancellation while an approval is in progress supply the request-versus-outcome clarity bar. FitCruxx's staff sponsorship and configured-role control are its own requirements.
- [Apple purchase history](https://support.apple.com/en-us/118212): account-scoped purchase history reachable on web/device supplies the history/discoverability bar for existing receipts. This is a reference for navigation clarity, not a claim that Apple provides FitCruxx's freeze or manual renewal behavior.

The official Glofox and Momence freeze guides were also fetched to establish
comparable membership tasks. They have materially different billing/date and
cancellation semantics and are not the quality bar or authority for FitCruxx
rules. No reference screenshot was captured, no third-party login used and no
unobserved pixel comparison is claimed. Existing owner-approved Chalkline is
the visual reference; the following are our scored structural criteria.

## Scored criteria [own]

1. Existing member membership/Gym and You destinations disclose held plan,
   recorded sold net price/currency and actual dates before any action. Active
   catalogue prices are labelled current; no invented freeze allowance or
   implied future date extension. Central five tabs remain Home, Classes,
   Shop, Activity, You. Receipts and PAY renewal remain their existing linked
   destinations, not duplicate screens or machinery.
2. Request freeze is reachable within three actions from held-plan detail.
   One Sheet shows exact start/end dates, inclusive duration only when returned
   by the server, reason and “This is a request. Your [business noun] must
   approve it.” Confirmation shows the unchanged membership expiry and the
   requested interval. No new date, guaranteed eligibility or successful pause
   appears before the actual server decision.
3. Pending membership retains readable plan/history and shows a specific desk
   path with freeze/SLF renewal actions unavailable. Request pending is visibly
   distinct from membership pending. No member `pending` enum is invented.
   Blocked/unlinked actors receive the existing access/refusal journey without
   another member's cached data.
4. Request detail separates awaiting desk adoption, awaiting approval,
   approved scheduled, currently paused and completed interval. Cancellation
   is “Cancel request”, reachable only before approval; it never says cancel
   membership or resume an approved pause. Cancelled/rejected/expired history
   retains requested dates and decision time/reason where present, with an
   appropriate new-request/desk action rather than reopen.
5. Desk queue shows the original member request and reason, unchanged source
   facts and the two distinct actions Adopt request / Approve freeze. A staff
   adopter cannot approve their own source request. The configured-role boundary
   is readable; a solo owner or changed configuration gets a truthful next
   step, no silently enabled Approve button. Rejection clearly labels its
   reason shown to the member. Stale detail closes confirmation and refreshes.
6. Inclusive overlap, unavailable plan/membership, elapsed start, allowance,
   stale revision and concurrent decision conflicts explain what the member
   can do next without leaking foreign rows. No form quietly adjusts dates,
   clamps allowance or replays changed facts. A timeout keeps an uncertain
   state and offers reconciliation/retry with the same logical request.
7. Loading, empty, pending membership, requested, awaiting approval, scheduled,
   covering/elapsed approval, cancelled, rejected, expired, validation,
   unavailable, permission, retryable error and offline have deliberately
   different copy/actions. Offline is last-good identity-scoped in-memory truth
   with fetched time; create/cancel/approve are unavailable and nothing queues.
   Reconnect and late-response handling never show another identity's result.
8. Renew opens PAY's existing current-plan request with its frozen disclosures;
   external payment/proof remains pending verification until ledger recording.
   Receipt links show exact genuine number/date/amount, and actual resulting
   dates, not an uploaded screenshot or SLF-created entitlement. Unavailable
   PAY and plan changes have a desk path.
9. Existing Sheet/StateMessage/StatusWord/tokens/formatters only; English and
   BIZ noun, word-plus-mark states, tabular money, accessible labels/focus,
   44px web/48dp native targets, light/dark, 200% text and reduced motion without
   clipping. Verify mobile 390-width and web 1440-width with reproducible own,
   foreign, pending, adopter and configured-approver fixtures and axe-clean web.
   Notifications disclose no reason or sensitive membership facts on lockscreen.

## GO evidence [own]

Fresh critic receives the frozen public contract, fetched references and
role-labelled reproducible flows/screenshots, not build narration. Every
criterion must be demonstrated; source authorization, date/allowance truth,
cancel-versus-approve race, genuine receipt reuse and identity-cache isolation
cannot be passed by static mockups. Annual PAUSE source precision, reviewed
source linkage/guards and Wave C readiness precede freeze/tests. Live runtime
evidence and owner-approved scope remain required; fetched prose is not Android
acceptance. Three rejections of one dimension escalate under the campaign loop,
never lower the bar.
