# Gymloop Phase 7 — execution prompt

2026-09-18 · Use with the experience PRD, not as a replacement for domain rules.

## Copy-ready orchestrator prompt

You are completing Gymloop Phase 6 closeout and Phase 7 under the owner's
Sol/Terra/Luna policy. Deliver equally excellent member and gym-owner interfaces,
a fast front desk, matching light/dark appearances and the real native workflows.
The accepted direction is calm, contemporary, Apple-inspired minimalism:
porcelain/ink surfaces, emerald/mint accents, clear gym identity, Inter with Noto
Sans Devanagari, considered curves and restrained motion. Iron Pulse is historical.
Do not claim an AI bitmap's font is an identified font or copy its sample data.

Read `AGENTS.md`, `docs/planning/current-campaign-goal.md`,
`docs/planning/phase7-experience-prd.md`, `docs/roadmap.md`, relevant registry
entries and the area's frozen OpenSpec/domain contracts before acting. Inspect
the working tree; preserve existing work and finish one coherent slice at a
time on `main`. Never read holdout contents as orchestrator/implementer.

Read the approved member reference and proposed owner adaptation:

- `docs/design/phase7/member-minimal-light-dark-v2.png`
- `docs/design/phase7/owner-minimal-light-dark-v2.png`

Use their paired documentation and PRD to distinguish appearance from business
behaviour. Extend the system to other screens; do not generate one image per tab.
Capture relevant public comparison bars once, then reuse those captures.

### Authority and budget

Use Sol medium for orchestration; Sol high for security, money, architectural
arbitration and final visual judgment. Terra medium owns bounded architectural
and native seams. Luna low/medium owns small, contract-complete screen work.
No GPT-6 Astra unless the owner explicitly changes that restriction. Do not
silently substitute a disallowed model if a requested one is unavailable.

At most two workers concurrently, except the required separate blind test
authors. Reuse workers for bounded corrections. A critic is a fresh Sol context
that sees the frozen spec, artifacts and evidence, never implementer reasoning.
For identity, RLS, money and offline concurrency, separate visible-test author,
holdout author, implementer and critic. Holdout authors see neither visible
tests nor implementation; they report pass/fail and requirement dimensions,
not suite contents. Critics still inspect the resulting implementation.

Check actual weekly usage at start and after every completed micro-batch. Phase
6 closed at 76% used. The campaign ceiling is now 79% used under the later owner
continuation (ADR-126); there is no task-to-quota guarantee. At the ceiling stop
new work, preserve partial work and report the last green
commit plus exact remaining requirements. Never bypass a gate to fit the cap.
If the same critic dimension fails three times, ask the owner to resolve the
under-specified contract; do not increase model size or lower acceptance.

### Contract-first dispatch

Before each batch, publish a bounded assignment with all of:

1. Exact requirement IDs and the frozen spec revision.
2. Exact owned files, including allowed new paths; no shared-file co-ownership.
3. Existing inputs/outputs, response schemas, role boundary and error states.
4. Acceptance test/journey and the existing passing evidence being reused.
5. Forbidden scope: tests for implementers; holdouts for root; unrelated routes,
   auth/SQL/business-rule edits for visual workers; dependency upgrades by default.

Workers may identify gaps but may not revise requirements. Stop affected fan-out,
arbitrate the contract, document it, then redispatch. Paths below are planned
boundaries, not permission to create an unused component or API.

### Ordered micro-batches

**0 — Phase 6 evidence closeout (complete 2026-09-18).** Requirements: COM-001–009, MET-001–008,
OPS-001–004, ONB-001–005 and NAV-006/008. Include the comms contract's referenced
PAY/INT/DPD/STK IDs when their behavior is exercised. Own only the applicable
evidence, registry and OpenSpec archive files unless a real failure demands a
separate repair. Perform outstanding owner/fleet reconciliation and super-admin
journeys, with exact demo cleanup. Do not rerun the already-green DB suite
without an affected change. Do not mark Phase 6 done just because CI passed.

**1 — Visual foundation.** Requirements: UX7-003–007, UX7-013–014.
Terra owns `packages/shared/src/config/constants.ts`, its existing export barrel,
`apps/web/app/globals.css`, `apps/web/app/layout.tsx`, and proposed
`apps/web/app/theme-provider.tsx`, `apps/web/app/ui/` and `apps/web/app/fonts/`.
Freeze the smallest token/provider/primitive interface first. Reuse the existing
Field/AccountFrame API. Root alone coordinates registry/manifest/lockfile edits
and licenses. A separate test author owns focused theme and accessibility
behaviour tests; commit new behaviour tests red before implementation.
Acceptance: both themes on sign-in and one real owner screen, preference reload,
keyboard focus, Hindi sample, reduced effects, no layout/hydration error.
Forbidden: new auth semantics, new domain APIs, unconsumed primitives, generators.

**2 — Web core-loop route groups.** Requirements: UX7-002–007, UX7-012–014 and
each group's existing ATT/NSH/PAY/MNY/ADD/COM requirements. Dispatch one group
per worker; list exact IDs from its contract before starting. Luna changes
rendering only, preserving existing props, server/client boundaries and actions:

| Group | Owned existing route subtree/files | Acceptance |
|---|---|---|
| Check-in | `apps/web/app/(console)/console/` | Search → assisted/QR result; refusal/pending remain honest |
| Follow-ups | `apps/web/app/(console)/red-list/` | Real case → contact outcome → next action |
| Renewal/payment | `apps/web/app/(console)/memberships/`, `apps/web/app/(console)/payments/` | Exact paise, refusal/conflict, receipt; independent money review |
| Add-ons | `apps/web/app/(console)/add-ons/`, `apps/web/app/member/add-ons/` | Offer terms → permitted action → truthful order/receipt |
| Messages | `apps/web/app/(console)/messages/`, `apps/web/app/member/messages/` | Consent, queued/refused state and role isolation unchanged |
| Owner/platform | `apps/web/app/(console)/dashboard/`, `apps/web/app/platform/` | Exact snapshot disclosure; preview remains refused for owner RPC |
| Supporting | `apps/web/app/(console)/leads/`, `apps/web/app/(console)/imports/`, `apps/web/app/(console)/members/` | Existing writes, validation and import preview preserved |

Root serially owns `apps/web/app/account-frame.tsx`, console/member layouts,
Field/Alert and shared UI changes. A Terra correction batch may own a complex
interaction after its state contract is frozen. Route workers cannot edit those
shared files or `apps/web/lib/`, `apps/web/app/api/`, SQL or test files. Any new
member home/activity/membership route waits for batch 3's authorized read and
navigation contracts; a pretty shell with fictitious data is not delivery.

**3 — Native and member contract seams.** Requirements: UX7-001, UX7-008–012,
ATT-001–008, NAV-001–008, plus the existing role/RLS rules in `docs/security.md`.
Sol/Terra first
freeze detailed EARS amendments for self-check-in, verified joining/switching,
NAV-002 member home, cookie-or-bearer precedence/refusal, token refresh/storage,
member-scoped reads and offline evidence/expiry. PRD prose is not a substitute
for request/response schemas, authorization, atomicity and error tables.
Independent authors own visible tests and `supabase/tests-holdout/` respectively.
Their output is committed before implementation; implementers cannot amend it.

Then Terra owns the minimal planned `packages/api-client/`, `apps/mobile/`
foundation, `apps/web/lib/identity-session.ts` and the specific Supabase server
adapter/API routes listed by the frozen seam. A migration gets its own explicit
path. Do not give a worker broad authority over every API route. Shared schemas,
env additions and registry updates are serially coordinated by root. Preserve
the existing `{ok:true,data}` / `{ok:false,error}` envelopes and decimal strings.
No service-role key on a device, no UI-only tenant switching, no insecure token
fallback. SDK 57 packages resolve together; web React is not mobile React.

Acceptance includes UX7-011's separately frozen joining/switching amendment;
existing NAV IDs alone do not specify that new flow. Also verify the
member/desk/platform/preview credential matrix; sign-in/refresh/
restart/sign-out; invalid/mixed credentials; cross-gym and revoked access;
verified gym association; real native development builds on Android AND iOS.
No paid build, external account purchase or store publication is implied.

**4 — Native screens and replay, split into small batches.** Requirements:
UX7-001, UX7-003–014 and each screen's named domain requirements. After batch 3
interfaces freeze, Luna owns the assigned exact files under proposed
`apps/mobile/app/(member)/` or `apps/mobile/app/(desk)/`; not both in one batch.
Terra alone owns proposed `apps/mobile/src/offline/` and
`apps/mobile/src/session/`. They consume registered shared tokens and API-client
interfaces. Add member web counterparts only over the same authorized contracts.
Freeze stack/route destinations, read models and state matrices before dispatch.

Member batches: Home/check-in → Activity/streak → My gym/membership/receipts →
messages/consent/add-ons → You/appearance/language. Desk batches: search/assisted
attendance → directory → follow-ups → lead capture. Do not hide unimplemented
deliverables behind disabled decorative controls and then call the phase done.

Replay acceptance: airplane mode, app termination, reconnect, timeout after
server commit, simultaneous drain attempts, expired token/membership, conflict,
account/gym change and sign-out. Preserve original event key and actor/tenant.
Only a server-confirmed record is success. Full blind arrangement applies.

### Build and verify efficiently

Use the PRD's exact typography, token and motion specifications. Install only a
dependency used in the current batch, pin it, verify peers and SDK compatibility,
and retain font licenses. No new scripts, abstraction layers or styling kits
without a demonstrated necessity. Search the registry and code before every new
export and register each actual addition. All numerical design values belong
in the existing shared constants file, consumed through platform adapters.

During development, run only affected tests plus the affected package's lint
and typecheck. Do not rerun a passing suite if its inputs did not change. Pure
styling does not need class-name snapshots; preserve existing functional tests
and use rendered evidence. Run full repository gates once per completed slice.
Push coherent green units to `main`, tests-first then implementation. Test
corrections require independent contract review and a separate legitimate
`spec:` commit, never an implementer editing the oracle to pass.

CI alone applies forward migrations. Wait for the DB workflow before another
migration push; regenerate DB types with the Supabase CLI after apply. Never
hand-edit generated types or use Supabase MCP. No test is allowed to commit
Cloud database state; demo journeys require exact, documented cleanup.

For each visual slice, capture actual rendered light/dark screens at the PRD
viewports, with representative content and failure/empty states. A fresh Sol
critic receives the frozen brief, reference captures and render artifacts,
uses crops, and checks hierarchy, typography, geometry, contrast, accessibility
and truthful action states. A failed dimension gets only its cited correction
and narrow regression. Keep native performance/accessibility evidence distinct
from web evidence. Bundling on Windows is not an iOS development build.

### Completion report

Report the last green commit, completed requirement IDs, actual journeys/builds,
critic verdicts, current weekly usage and any precise access/credential blocker.
Synchronize registry/spec/evidence and archive only a completed OpenSpec change.
Keep Phase 8 and blocked Razorpay integration explicitly outside this campaign.
Never report “perfect,” “production-ready,” or “Phase 7 complete” from a mockup
or passing unit suite. Use the PRD definition of done.
