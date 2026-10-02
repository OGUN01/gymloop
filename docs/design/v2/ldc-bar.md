# LDC quality bar — convert a lead without retyping

**DRAFT NOT FROZEN — 2026-10-03.** Companion to
`openspec/changes/lead-conversion/proposal.md`, F13 / V2-D3. Wave C remains before
Wave D. No implementation, visible/holdout tests or private evidence was inspected;
no browser/device/cloud acceptance was performed. Freeze after owner approval and
closed-test feedback. Applicable requirements: LDC-001…011 and LEAD-001…005.

## Fetchable comparable references and evidence limits

R1: [Salesforce Trailhead — Create and Convert Leads as Potential Customers](https://trailhead.salesforce.com/content/learn/modules/leads_opportunities_lightning_experience/create-and-convert-leads-lightning),
official public body fetched 2026-10-03. Its conversion walkthrough carries
stored lead information into the resulting records and explicitly chooses an
existing contact where appropriate. It also publishes a conversion-screen image.
This supplies the interaction comparator: reuse the captured person and make an
existing-record choice explicit. Salesforce's account/opportunity fields, stage
graph and multi-step form are not Gymloop requirements. The published image was
not captured or scored in this draft.

R2: [Stripe API — Idempotent requests](https://docs.stripe.com/api/idempotent_requests),
official public body fetched 2026-10-03. It supplies the backend ergonomics
comparator: uncertain requests can be retried with the same key, and changed
parameters under that key are refused. Gymloop's durable actor-bound evidence,
authorization-before-replay and race results remain its own approved LEAD
contract; Stripe's retention window and cached-error rules are not imported.

R3: Owner-selected Chalkline direction in `docs/design/phase9/direction.md`
and its named boards; existing web kit and `UI_TOKENS`. These fix Archivo,
ruled-ledger hierarchy, semantic colors, control spacing and dot-plus-word
statuses. Concept-board content is illustrative, not live product data.

No authenticated third-party inspection, copied screenshot, visual win or
measured tap-time claim is made. The fresh critic must fetch public comparable
visual evidence and capture the real Gymloop screen; unavailable visual evidence
is marked unverified rather than manufactured.

## Observable acceptance criteria

| ID | Pass condition | Required evidence |
|---|---|---|
| LDC-Q1 | Existing `/leads` shows **Convert to member** for `trial_done` only. One activation sends create mode with the loaded revision, without retyping or a blank member form. Pending state belongs to that lead. | Real front-office interaction recording, request envelope and LDC-001/002 assertions |
| LDC-Q2 | Accepted create shows **Member created** and **Open member**; resulting branch/name/phone/email and gym-local joined date match the lead. No membership, payment, attendance, consent, Auth binding or member code is implied or created. Partial failure leaves no profile or conversion. | Independent atomicity/effect evidence plus real before/after UI; LDC-003/011 |
| LDC-Q3 | Exact same-gym eligible phone requires explicit **Link this member** using only id/name/phone/status. Dismissal does nothing, there is no create-anyway action, malformed duplicate facts offer no link. Paused/expired members remain linkable. | Real dialog/dismiss/accept captures and independent eligibility matrix; LDC-004/005 |
| LDC-Q4 | Unavailable duplicates disclose no profile. Cross-gym ownership behaves like no local match; wrong-phone/unknown/cross-gym/unavailable link targets share generic 404. Identity denial precedes target inspection. | Independent two-tenant/role/target matrix and refusal captures with PII redacted; LDC-001/005 |
| LDC-Q5 | Lost retains its reason and no convert action; earlier stages retain their approved next action; converted offers member open. Direct command attempts cannot bypass terminal/edge discipline or relink. | Real stage-state captures and independent RPC/direct-write evidence; LDC-008 |
| LDC-Q6 | Lost response retry reuses key and exact facts and returns the original outcome without another write; changed actor/facts yields key conflict. Duplicate-link choice uses a fresh key because the decision changed. Unknown result never appears successful. | Network-interruption interaction recording plus independent durable-replay evidence; LDC-006/011 |
| LDC-Q7 | Same-lead create/create and create/link races have one winner; exact loser replays, changed loser is stale. Different leads or another creator racing on one tenant phone leave one member owner and require explicit linking by the loser. A stale edited lead is reviewed before a fresh decision. | Independent concurrent/unique-key/CAS evidence, real stale-state capture; LDC-007 |
| LDC-Q8 | Source and original lead/creator evidence survive create and link; conversion member/time/evidence freeze. Multiple leads for one member retain their own sources. No single member acquisition source or fabricated source dashboard appears. | Independent persisted-fact comparison and existing source-filter acceptance; LDC-009 |
| LDC-Q9 | Owner acquisition metric stays the created-at cohort with current converted-stage numerator, counts both link and create, preserves exact decimal counts and no-cohort behavior. Conversion alone changes neither cash nor visits; refreshed list counts reconcile with active filters. | Independent MET parity and same-snapshot count evidence, real owner/list captures; LDC-010 |
| LDC-Q10 | Offline, pending, uncertain, refused and accepted-with-refresh-failure are distinct. No offline conversion queue or new-key retry after uncertain success. Active filters persist, and switched/denied identity removes stale lead and duplicate facts. | Real network/session state recording and independent request-order/session assertions; LDC-001/006/011 |
| LDC-Q11 | At 390px and 1440px, light/dark ledger identifies name, phone, source and stage without overwhelming the action. Duplicate dialog and outcomes fit at 200% text, remain keyboard/screen-reader operable, use existing tokens and at least 44px web targets, and require no motion. | Real viewport/theme/large-text captures, axe and keyboard/accessibility-tree run, registry reuse review; LDC-011 |

Every applicable row must pass. Documentation alone does not satisfy acceptance.
Evidence identifies build, environment, verified role and observed state, redacts
member PII, and distinguishes independent invariant proof from actual rendered
interaction. Existing registered flow that already passes should be reused, not
rewritten to create a code delta. Fresh critic records missing evidence as
unverified and issues GO only after the applicable checks and repository gates.
Three rejections of one dimension require owner clarification; the bar is not
silently lowered. No native lead screen is claimed by this web-only contract.
