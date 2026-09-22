# Current owner-authorized campaign goal

## 2026-09-22 password sequencing for five-gym pilot

The owner asks us to finish every safe, independent five-gym preparation task
before asking them to rotate the Supabase database password. Do not change or
retry rotating that credential during this preparatory work. This is a
**sequence**, not a waiver: the current password is disclosed/not accepted by
the pooler, DB CI is red, and no real gym may be invited until rotation,
local/CI synchronization, old-value rejection and green database gates have
actually been verified. Keep testing rollback-only or exact scoped synthetic
fixtures on the existing project, with no false release-readiness claim.

## 2026-09-22 five-gym pilot target

The owner asks for market readiness for an initial five gyms on this one
Supabase database, not a per-gym database or an unmeasured thousands-of-gyms
claim. `docs/planning/five-gym-pilot-release.md` freezes the bounded pilot
acceptance and separates rollback-only tenant proof from deployed two-gym
journeys, actual first-customer operations and the owner's visual work. Work
toward those conditions; do not announce pilot GO while required evidence is
missing.

## 2026-09-22 same-project test directive

The owner directs Phase 8 development and bounded synthetic testing on the
existing linked Gymloop Supabase project, which is the intended multi-tenant
database for every gym. Do not propose a database per gym or create another
project as a routine answer. The completed 10-gym × 50-member rollback-only
simulation is valid evidence of that narrow database/tenant boundary. Pursue
small, exact-ID, recoverable functional and concurrency tests here once the
database connection is healthy; never assume their traffic can be undone by
deleting the resulting attendance, money, receipt or audit history.

This owner directive does not make 10 × 50 equivalent to the frozen HARD-004
100 × 500 API spike or prove public capacity for hundreds or thousands of
gyms. Record the smaller result as a pilot-scale rehearsal and keep full-load
capacity unverified until a safe execution/restore method and scale-matched
evidence exist. A future plan upgrade is not itself a measured load result.
The 2026-09-22 session-pooler CLI connection timed out even though the project
reported healthy and the pooler TCP port was reachable. The separate
passwordless `db query --linked` path succeeded: 201 focused tenant/index/money
assertions passed, all 71 tracked migrations were applied, and generated types
matched. This does not clear the failed password/pooler migration workflow;
diagnose that path before any new migration or durable bulk fixture creation.
No destructive reset is authorized by this testing directive.

## 2026-09-21 non-visual closeout sequencing override

The owner asks for every safely completable Phase 8 non-visual row to be closed,
including repeatable two-gym acceptance, isolated load, privacy operations,
recovery and monitoring. The exact Play-installed production Android bundle
and physical-device release smoke are deferred to the final prelaunch step;
HARD-008 remains Partial until that step actually passes. The owner will handle
the separate UI/UX redesign. This sequencing does not relax HARD-003 through
HARD-007, the manual-payment integrity gate or the final customer-launch GO
decision. An unsafe load target, missing legal approval, unperformed restore,
or absent monitoring receipt remains visibly unpassed rather than simulated.

The 2026-09-21 database workflow failed before applying migrations when its
stored database credential could not connect. A local read-only CLI connection
also failed, while the project health, network restriction and ban checks were
normal. A 2026-09-22 local retry timed out rather than returning a specific
password-authentication code, so investigate pooler/CLI connectivity as well
as protected local/GitHub credential consistency; do not assume a reset is the
only remedy or post any value in chat. Rerun the DB workflow before any
migration slice. No migration is to be applied by hand.

## Phase 8 GO campaign — owner continuation (2026-09-21)

**Payment-scope override (ADR-146):** the initial release records only money
collected outside Gymloop by the gym. Razorpay charge initiation, callbacks,
provider-signed proof and gateway onboarding are deferred, not launch gates
for this manual-only scope. PAY-011, exact money, actor, receipt, renewal,
refund, audit, idempotency and tenant gates remain mandatory. No inactive
provider schema is to be presented as an enabled payment path. The older
provider-completion steps below remain history for a future online-payment
release, superseded for the current GO campaign. All unrelated HARD gates
remain unchanged.

The owner directs autonomous continuation until the Phase 8 release verdict can
truthfully change from NO-GO to GO, including decisions within the existing
Gymloop accounts and environment. Use at most two bounded parallel workers;
reuse completed workers where sensible. Preserve the separate owner-led visual
work, all existing synthetic identifiers and evidence, and the current linked
Supabase project. Run safe functional scenarios across two to four gym tenants
on that project with exact-ID cleanup; an upgrade to a paid Supabase plan is a
future owner option, not evidence that a backup, PITR, or load gate has passed.

Close the existing HARD-003–009 gaps in small test-first slices: mutation-complete
two-gym A–D journeys; privacy export, erasure and retention; recoverability;
monitoring; isolated load; manual-payment integrity and edge evidence; and exact-AAB
Android/Play acceptance. Reconcile HARD-001/002 and the owner-led HARD-010
visual gate before any customer-launch GO. Never equate a rollback simulation,
preview APK, local alert sink, unsigned provider mock, or legal draft with the
required production proof. Do not create a new Supabase project or paid service
merely to change a status label. If an external gate truly cannot be completed
with the current accounts and authority, exhaust safe in-scope alternatives,
record the missing artifact and exact dependency, and keep the verdict NO-GO.
The owner does not want routine clarification requests; make bounded product
decisions, but do not self-certify legal review or a provider's actions.

The desktop goal record remains an older blocked objective that cannot be
edited in place; this versioned goal is the current owner instruction.

## Active continuation — finish every verifiable Phase 8 lane (2026-09-21)

**Temporary credential use authorized; prelaunch rotation required:** a 2026-09-21 Supabase
CLI dry-run printed the then-current database password in task tool output.
The owner reports resetting it in Supabase Database Settings and replaced the
gitignored `.env.local` value. The GitHub `SUPABASE_DB_PASSWORD` Actions secret
was updated at 16:07 UTC and `supabase link` with the new local value succeeded
against the exact project. At 16:12 UTC, inspection found that same value had
also been entered into tracked `.env.example`; it was never committed or
pushed and was immediately scrubbed back to an empty example key. The
inspection itself printed it into task tool output. The owner explicitly
accepts using this current credential for bounded synthetic testing while
there are no customers, and will reset it before customer launch (ADR-145).
Only `.env.local` and the GitHub Actions secret may hold the value; never print
it or copy it into a command, artifact, or tracked example. The disclosed
credential remains a security debt, not a production-ready secret. An
old-value rejection was not independently tested; do not claim it was. Never
copy either value into a prompt, log or commit. The separate account-wide
Supabase access-token rotation remains a release item.

The owner has explicitly asked Sol to continue, own the remaining non-visual
work, and use safe simulations where a provider or recovery target is missing.
The previous two-point usage checkpoint is not a completion claim or a reason
to abandon the campaign. Work in small, measured batches; preserve the owner’s
separate UI/UX work and never relabel a simulation as production proof.

The next execution slices and their exit evidence are:

1. **HARD-003, two-gym isolation:** use the existing controlled identities and
   exact fixture IDs for reciprocal authenticated read and mutation refusal.
   The bounded reverse-direction live API refusal now passed; still require a
   repeatable checked-in two-owner browser fixture and complete journeys.
   Add the missing checked-in Playwright A–D journey with independent visible
   and holdout authors for identity/RLS assertions. Use rollback-only database
   probes and bounded API requests in the shared project; record which layer
   each proves. Under ADR-147, the one controlled browser write run retains
   its named synthetic QA financial/audit history and deactivates its distinct
   test owner afterward; do not delete immutable records for cosmetic cleanup.
   A is member check-in through verified renewal, B is silent churn through
   contact/return recovery, C is add-on purchase through visible usage, and D
   is assisted check-in through confirmation and actor audit. A manual payment
   journey may prove its own branch but never a provider-signed Razorpay branch.
2. **HARD-006, privacy operations:** freeze a versioned, field-level export,
   erasure, hold and retention contract from ADR-144 and the actual schema.
   Independently write tests, then implement the request ledger, portable
   export, idempotent erasure and dry-run/real retention runner with CI-only
   migrations. Exercise synthetic requests without erasing existing QA users.
   Obtain qualified legal/DPA review before claiming statutory readiness.
3. **HARD-007, recoverability:** inventory Auth, database and Storage recovery;
   create a protected logical backup if the available tooling can do so
   without exposing personal data, then restore into a disposable local or
   otherwise isolated target and verify row/schema checks. Do not reset the
   linked project. This can prove an operator-run logical recovery path but
   cannot substitute for unavailable provider PITR or cloud restore evidence.
4. **HARD-004, load:** run deterministic fixture and k6 preflight simulations
   without a 50,000-row persistent write to the linked project. A bounded
   same-project functional spike may test correctness only after exact
   cleanup/recovery is verified; it cannot establish the frozen 100 × 500
   performance threshold. Keep that gate Partial until a distinct recoverable
   non-production target and measured run exist.
5. **HARD-005/008 and provider gates:** finish all local log/redaction and
   Android/device checks; exercise a local alert-sink and mock provider
   failure/retry path as simulations. Real monitoring receipt, signed Razorpay
   payload, Cloudflare rule proof, truthful Play declarations, exact-AAB
   internal-track install, and final visual acceptance remain separately
   required. Rotate the prelaunch database password and account-wide Supabase
   access token noted in `docs/security.md` without breaking CI, then verify
   the old credentials are revoked. Reconcile HARD-001/009 and archive only
   when their real evidence exists.

After each slice, record command, identity, environment, result and artifact
in `docs/evidence/phase8/ledger.md`; run only affected checks during repairs.
The desktop goal API cannot edit the objective of its older blocked record;
this versioned repository goal is the current execution record, not a claim
that the stale desktop objective changed.

## Owner-delegated privacy decision and safe verification — 2026-09-21 (ADR-144)

Gymloop does not sell member data or use it for independent advertising.
Retain personal data only to deliver the gym's service or for a documented
financial, audit or case-specific legal obligation; provide a portable export
and erase unnecessary personal data on a verified request. Freeze the exact
field dispositions, retention clocks, request authorization and hold scope
before independent tests and implementation. The existing duration matrix is
an engineering default, not legal sign-off. Qualified legal review and the
gym-facing DPA remain launch gates.

The owner requested the 100 × 500 load run on the existing linked project.
Its free-plan backup inspection found no available backup and PITR disabled,
so the accepted HARD-004 preflight still refuses this production reference.
Continue bounded synthetic scenarios and rollback-wrapped tests in the same
project; do not run persistent stress or a restore drill there. Provision a
distinct disposable target and a verified recovery path for those gates.

## Phase 8 non-visual completion ownership — current, 2026-09-21 (ADR-143)

Sol owns execution, integration, evidence and truthful release recommendations
for every non-visual Phase 8 requirement through completion. The owner retains
the separate UI/UX redesign. “Ownership” means pursuing all safe in-scope
implementation and verification, coordinating required external steps, and
refusing to mark a gate passed without its real evidence; it does not make Sol
a legal signatory, Play account-holder certifier, payment provider, or backup
operator by assertion. The earlier percentage stop is withdrawn. Preserve
Phase 6/7 and the shared production-configured project's identifiable QA data.

Execute the remaining non-visual work in this order, with the authoritative
per-gate evidence and blockers in `docs/evidence/phase8/ledger.md`:

1. Finish HARD-003's checked-in Playwright journeys A–D with independently
   signed-in gym sessions, reciprocal direct read and write denial, axe,
   Light/Dark and English-only checks. The bounded two-gym live smoke now
   proves reciprocal member reads and one-direction check-in refusal, not this
   full gate. Do not repeatedly mutate the shared project from CI without a
   controlled fixture and exact cleanup/recovery procedure.
2. Finish HARD-004 on a positively verified distinct non-production target;
   never run its 100 × 500 workload against the linked production reference.
3. Finish HARD-005–007 with real monitoring delivery, a frozen privacy/export/
   erasure contract and qualified legal review, then a protected backup and
   disposable-target restore drill. Implement only after those decisions and
   recovery boundaries are real.
4. Finish HARD-008 and related payment/edge gates with real provider-signed
   evidence, truthful Play declarations, an internal-track upload and install
   of the exact AAB, and physical Android acceptance. A signed bundle or
   connected phone alone does not pass these gates.
5. Reconcile HARD-001/009 and all production gates, remove or safely recover
   the identifiable synthetic state, then archive Phase 8 only after every
   required non-visual gate passes. HARD-010 remains a separate visual NO-GO
   until the owner's design work receives its own acceptance.

If a prerequisite is genuinely outside the available accounts, authority or
free-plan controls, keep the gate explicitly blocked/external with its exact
next action; do not relabel it complete to satisfy a deadline.

## Phase 8 prelaunch closeout — prior direction, 2026-09-21 (ADR-141/142)

The owner withdrew earlier weekly-usage stops, confirmed there are no live
customers, and authorized extensive synthetic functional checks in the existing
linked Gymloop project. Finish every safely executable non-visual Android/web
check and fix, preserving independent identity/RLS/money verification; the
owner will handle the remaining visual redesign. Keep exact QA identities and
rows in the Phase 8 evidence ledger. Run narrow tests for new behavior, then
the required gates once per completed slice. Do not claim a partial journey as
the frozen HARD-003 A–D acceptance.

The same project is production-configured and has no listed backup/PITR point.
Its seed cannot recreate the five demo Auth sign-ins. Therefore no linked
reset, bulk 100 × 500 load or synthetic cleanup by guesswork: require verified
recovery and Auth recreation before any destructive reset, and the distinct
non-production target required by HARD-004 for load. External monitoring,
legal/privacy decisions, cloud restore, provider-signed payment evidence and
truthful Play declarations/exact-artifact install remain separately open.
Do not archive Phase 8 or declare customer-launch readiness while these or
HARD-010's visual NO-GO remain. The older percentage ceilings and closeout
instructions below are historical, not active constraints.

## Phase 8 non-visual closeout — 2026-09-21 (ADR-139)

The owner will handle the remaining visual redesign. Sol owns the non-visual
Phase 8 closeout, with two additional weekly-usage points from the last 22%
reading and **24% used as the stop for new work**. Ductx is the confirmed Google
Play developer account for Gymloop. HARD-010 remains NO-GO and cannot be called
customer-launch ready merely because its work is owner-deferred. HARD-003–008
retain their real external prerequisites: a separate non-production project,
monitoring destination, approved privacy/export/erasure contract and legal
review, disposable-target restore, and truthful Play declarations followed by
an exact-artifact internal-track install. Do not synthesize any of those gates.

## Phase 8 Android/web production closeout — 2026-09-21 (ADR-138)

The owner authorized one additional weekly-usage point from the measured 19%
position, making **20% used the stop for new work**. Finish the cited HARD-010
profile-identity visual defect, verify the live web and physical Android result,
produce a signed AAB from the intended commit, and pursue the Play internal-test
path. Keep iOS and the separate broad UI redesign deferred. Use one bounded
Luna/Terra worker at a time alongside Sol; repeat only affected checks. The
remaining HARD rows stay visibly Partial/External until their actual evidence
exists. A signed bundle, preview APK, or available Play account cannot be
reported as an uploaded, installed, policy-approved, or published product.

Closeout at the 20% marker: the current-source signed AAB and preview APK were
built, and live web/physical Android profile checks passed. The fresh visual
critic still returned NO-GO for HARD-010's hierarchy/account surface; HARD-003
through HARD-008 retain the unresolved evidence in the Phase 8 ledger. Stop
new implementation and release actions at the owner-authorized ceiling. Phase 8
is not complete or archived, and Gymloop is not customer-launch ready.

Gymloop is not yet an app in the signed-in Play developer account. Its creation
requires the account holder's truthful Google Play policy and U.S. export-law
certifications; the orchestrator may prepare and inspect the form but must not
assert those declarations without the owner's review. This is the active goal;
older percentage markers below are historical.

## Phase 8 member experience and Google sign-in override — 2026-09-20

The active first slice of Phase 8 is a reference-matched refinement of the
member experience on web and Android. The Phase 7 archive remains truthful for
the functional Android-first boundary, but its visual result is not accepted as
the final product bar. Use the approved member v2 board as the literal geometry,
hierarchy and light/dark reference, extended by the Phase 8 auth/profile board.
Authentication, Home, Activity, My gym, You, and the four-tab shell must feel
like one calm, compact product; raw UUIDs, giant generic cards, decorative
dashboard clutter, and Hindi/localization controls are forbidden.

Google sign-in is an alternative entry method for existing pre-linked Gymloop
identities. It does not create app privileges, memberships, staff links, or
tenant claims. A provider-authenticated account without a complete verified
Gymloop identity is routed to the existing not-linked/no-access state. Password
sign-in remains available. Web is implemented and verified first; Android uses
the same claim boundary in a separate micro-batch. OAuth secrets and provider
configuration are external actions and cannot be represented as complete until
the real Google/Supabase configuration and a controlled-account journey exist.

Sol owns the frozen contract and final visual/identity review. Terra owns the
identity seam, callback/deep-link implementation and browser/device diagnostics.
Luna owns bounded screen refinements and repetitive visual corrections. At most
two workers run concurrently. Usage started at 9%; the owner extended the
campaign on 2026-09-20 and **12% used is now the absolute stop for new work**.
Run only tests for changed behavior plus the affected
package checks, then one real journey per completed slice.

Current review artifact: `../design/phase8/member-hig-auth-core-v4.png`, with
rationale in `../design/phase8/member-hig-auth-core-v4.md`. It supersedes the v3
candidate by adding strict HIG safe-area, thumb-zone, tab, semantic-type and
iPhone provider-order rules. The owner approved this artifact for implementation.

## Owner Android-first Phase 8 override — 2026-09-20

This supersedes the older Phase-7-only scope and percentage markers below.
The active objective is to finish Android and web through Phase 8 while iOS is
explicitly deferred. Phase 7 is green and archived with v1 recorded as a single
verified gym association and no public-code join/switch control. Complete the
applicable hardening gates and Android release-readiness evidence. Browser journeys may use multiple demo gyms
to prove tenant isolation; they may not manufacture a second member association
that the product does not support.

Sol remains orchestrator and security/money arbitrator. Terra owns bounded
architecture, security, load and release tasks; Luna owns narrow tests, UI
repairs and device/browser verification. At most two workers run concurrently.
No Astra, duplicated exploration, broad reruns after a passing result, invented
provider success or weakened gate is authorized. Weekly usage was 6% at this
continuation and ADR-135's two-point allowance makes **8% used the absolute
stop for new work**. External actions requiring provider credentials, legal
sign-off, a paid store account or a platform backup control must be reported as
external blockers rather than simulated.

Updated 2026-09-18 (owner continuation 5). This is the repository's current execution objective; older
prompt text is historical where it conflicts with this owner override.

Phase 7 is now green and archived under this boundary. Phase 8 is the active
objective; the historical Phase 7 execution detail below remains the evidence
trail rather than outstanding work.

## Objective

Phase 6 and the Android-first Phase 7 boundary are closed. Owner/fleet metrics,
super-admin/support/preview journeys, the reference-matched web experience and
the real Android member/front-desk application passed their required evidence
and archive boundaries. The current objective is Phase 8 hardening and Android
release readiness without rebuilding those completed phases.
Give members AND gym owners a polished, user-centric minimalist interface with
equal light/dark quality, visible gym identity/code, accessible typography,
comfortable curves and responsive, restrained motion. Preserve the attendance
→ follow-up → return → renewal → add-on → evidence loop and every security,
money, identity and constitutional gate.

The approved member/owner v2 boards are the conformance bar for every Phase 7
user, owner and front-desk route. Matching them means the same typography,
whitespace, continuous geometry, quiet chrome, hierarchy and equal-theme finish
with truthful route content—not merely applying their colours to a Phase 6 layout.

The owner approved both the member v2 visual direction and its gym-owner
adaptation as literal end-state references. Platform super-admin uses the same
fundamentals with lower bespoke-polish priority. Iron Pulse is superseded.

## Governing artifacts

- [Experience PRD](phase7-experience-prd.md): scope, fonts, tokens, libraries,
  interactions, requirements and measurable acceptance.
- [Implementation prompt](phase7-implementation-prompt.md): bounded assignments,
  model hierarchy, sequence and verification rules.
- [Member direction](../design/phase7/member-minimal-light-dark-v2.md).
- [Owner direction](../design/phase7/owner-minimal-light-dark-v2.md).
- `docs/roadmap.md`, ADR-121/124/125, existing domain and OpenSpec contracts.

## Current evidence and remaining work

- Phase 6 backend/CI is green at `3e5120b`; latest recorded pgTAP evidence is
  81 files / 6812 assertions. All final browser journeys and exact cleanup are
  recorded in the communications, metrics and platform evidence files.
- Communications, metrics and platform are archived at
  `openspec/changes/archive/2026-09-18-phase6-{comms,metrics,platform}/`.
- Phase 7's shared web visual foundation is implemented: platform-neutral
  tokens, pinned local Inter fonts, persistent System/Light/Dark,
  accessible focus/targets, reduced-effect fallbacks, polished sign-in and the
  authenticated account shell. Final Sol visual review and repository gates
  passed; evidence is `docs/evidence/2026-09-18-phase7-visual-foundation.md`.
- The staff check-in route is the first board-conformant core-loop redesign. Its
  initial tokenized 768px pass was rejected; the corrected 1440px roster/gate
  composition and two-row mobile header passed fresh Sol review. Evidence is
  `docs/evidence/2026-09-18-phase7-check-in-surface.md`.
- The owner follow-up queue is the second board-conformant core-loop redesign.
  It preserves the real per-row mutation contract inside the owner-board list
  hierarchy. A first critic rejected clipped enum/note text and 24px member
  links; the tested repair measured full text, 44px links and zero overflow at
  1024px before a replacement fresh critic returned GO. Evidence is
  `docs/evidence/2026-09-18-phase7-follow-up-surface.md`.
- The gym-console owner shell now carries the approved board's slim rail,
  truthful gym context, permission-filtered navigation and responsive top-shell
  form across every console route. A fresh Sol rejection caught the tall-route
  footer and 390px identity defects; an independent regression and bounded CSS
  repair closed both. Evidence is
  `docs/evidence/2026-09-18-phase7-owner-shell.md`.
- The owner overview is now the next board-conformant core-loop route. It uses
  the existing one-snapshot metrics authority for its four-card band, compact
  follow-up/renewal/recovery workspace and humanized local disclosures. Two
  Sol comparisons rejected density and the intermediate navigation box before
  the final blocker-only verdict returned GO. Evidence is
  `docs/evidence/2026-09-18-phase7-owner-overview.md`.
- The remaining owner/member/platform web interiors and the real Expo
  member/front-desk application are implemented under frozen contracts. The
  final web critic returned GO after focused repairs restored the visible owner
  navigation, dominant member check-in hierarchy and compact 1024px rail.
  Security-focused visible and holdout files pass individually against Cloud;
  final Cloud workflow `35371043539` also passes migration, rollback, schema
  drift and all 87 visible/holdout files / 6,886 assertions.
- Phase 7 is complete under ADR-134. Physical Android proved the ARM64 build,
  member/desk authentication, all eight tabs, Light/Dark, sign-out, maximum
  text, Remove animations, real airplane-mode QR capture, cold restart,
  reconnect replay and duplicate-restart stability. Canonical spec:
  `openspec/specs/mobile/spec.md`; archive:
  `openspec/changes/archive/2026-09-20-phase7-mobile-foundation/`.
- Physical iOS runtime is deferred and not claimed. The owner selected one
  verified gym association for v1, so no public-code join/switch control is a
  deliberate authorization boundary rather than unfinished Phase 7 work.

## Budget and delegation

Latest measured usage at this continuation's start: 75% weekly consumed.
Owner-authorized Phase 6 checkpoint: **77% consumed**. If and only if Phase 6 is
fully closed below that checkpoint, continue Phase 7 under the approved PRD.
The active completion budget for this combined continuation is now **88% consumed**
(ADR-133: 86% measured restart plus the owner's final two-point allowance). Check after every micro-batch; do
not promise work fits a percentage. At the applicable cap, stop new work and
report the last green commit and preserved outstanding work. Phase 8 follows
Phase 7 as a separately verified stage; this allowance does not waive or skip
either phase's completion boundary.

Measured after the completed Phase 7 visual-foundation micro-batch: **77% used**.
Measured again after the completed check-in surface: **77% used**. These completed
slices are green and archived; the 80% absolute ceiling remains in force for any
next bounded Phase 7 slice.

Measured after the completed owner-shell surface and its green cloud workflows:
**78% used**. The owner authorized two further points to finish the reference-
matched Phase 7 UI/UX. Do not begin a slice that cannot reasonably close before
the active hard stop; preserve the last green commit if the ceiling is reached.

Measured after the completed owner-overview surface and its green cloud
workflows: **80% used**. Owner continuation 4 replaces the intervening one-point
allowance with two points, so **82% used is the current absolute hard stop**.
The work remains Phase 7 only; no Phase 8 scope or quality exception is added.

Measured at owner continuation 5: **82% used**. The owner authorized three to
four further points and selected Sol xhigh for implementation, with Terra/Luna
reserved for bounded visual and UI verification work. This makes **86% used the
current absolute hard stop**. The extra allowance changes neither the frozen
security/mobile contract nor the requirement to finish, verify and archive
Phase 7 before any Phase 8 work.

Measured after the English-only correction, final visual pass and first full
gate attempt: **86% used**. Owner continuation 6 adds two points, to **88% used**,
for the frozen Phase 7 security repair, rendered verification, green gates and
archive. Optimize for completing those outcomes rather than spending the
allowance. Sol is escalation-only; Terra implements bounded security or visual
repairs and Luna owns independent tests and visual inspection. Phase 8 may
start only if Phase 7 is green and archived with allowance remaining.

Sol orchestrates/reviews; Terra owns bounded architecture/security/native work;
Luna is the default small-scope implementer. Maximum two simultaneous workers,
except independent visible/holdout authors. No Astra without explicit owner
authorization. Full blind arrangements, immutable tests and CI-only migration
application remain mandatory. No quota workaround or relaxed gate is authorized.

## Completion boundary

Phase 6 and the ADR-134 Android-first Phase 7 boundary are archived with real
browser/device journeys. Phase 7 covers the PRD's member, owner and desk
surfaces; accessible English-only Light/Dark states; real Android builds;
role-isolated authentication; honest offline capture and exactly-once replay;
cropped visual criticism; current registry/spec/evidence and archive. Physical
iOS runtime is deferred, never simulated. Phase 8 operational hardening is now
active; credential-blocked Razorpay provider integration remains outside this
campaign unless its real external evidence becomes available.

## Owner language override

The 2026-09-18 owner instruction supersedes ADR-011 for product UI: Gymloop is
English-only. Phase 7 must expose no Hindi mode, language selector, locale
preference, Hindi sample copy or Devanagari font payload. Stored communication
template locale values remain a Phase 6 delivery contract and are not an app
language mode; changing that data contract is outside this presentation-only
override.

## Desktop goal-record limitation

The current desktop goal record still contains the older Iron Pulse direction
and 75% cutoff and is marked blocked. A 2026-09-18 replacement attempt after
this continuation was rejected because the unfinished blocked record still
owns the thread. The available goal tools can
read/create a goal or mark its status complete/blocked; they cannot rewrite an
unfinished objective or resume its status. This file records the owner's update
without falsely completing/replacing the unfinished campaign. Synchronize the
desktop goal text through a supported UI/control when available; this note is
not a claim that its stored objective has changed.
