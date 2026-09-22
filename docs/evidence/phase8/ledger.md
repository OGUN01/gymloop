# Phase 8 evidence ledger

Updated 2026-09-22. Status meanings: **Passed** has fetchable evidence for the
full stated requirement; **Partial** has real evidence but an acceptance part is
missing; **Blocked** cannot proceed safely until the named prerequisite exists;
**External** requires a real owner/provider/legal/cloud/store action. A local
mock or synthetic provider response never changes External to Passed.

**ADR-146 initial-release payment scope:** only staff-recorded payments
collected outside Gymloop are in scope. Razorpay provider evidence in this
ledger is a deferred online-feature dependency, not a blocker for a manual-only
release, provided the product exposes no gateway route and the manual money
path passes its own tests. This does not change the status of any other HARD
gate or certify an online transaction.

**2026-09-21 closeout checkpoint:** CI, Holdout and Test immutability passed
for `42ef6d4`, but DB workflow `35633578490` failed at `supabase db push`
before a connection was established. It did not apply a migration. A local
read-only CLI attempt failed with the same connection message; the Gymloop
project reported `ACTIVE_HEALTHY`, the pooler TCP port was reachable, network
restrictions allowed traffic and the ban list was empty. A 2026-09-22 local
retry timed out without a specific password-authentication code; diagnose
pooler/CLI connectivity and credential consistency before the next DB run.
This is not a manual-payment defect, but it blocks migration-based Phase 8 work.
The owner deferred exact Play-installed Android acceptance to the final
prelaunch step, not to Passed.

| Requirement | Status | Commit/build, environment and time | Command or procedure and fetchable evidence | Blocker, owner, required evidence and next safe step |
|---|---|---|---|---|
| HARD-001 | **Partial** | Phase 7 closeout `d1888c6`; Phase 8 contract `c768dff`; repository, 2026-09-20 | Procedure: review each HARD row for status, identity, time, result, artifact and dependency. This ledger is the current artifact. | Owner: Phase 8 orchestrator. Complete only after every row links exact executed commands/procedures and results; keep skipped/blocked/external visible. |
| HARD-002 | **Passed** | Original contract/config `cdd99fb`/`674255e`; least-permission contract/config `94f058f`/`2252bdc`; version contract/config `d894ad5`/`7a31384`; CI `35530050420`; EAS build `146221dd-dab2-4ef1-a99b-61dc14be4675`, 2026-09-20 | Focused HARD-002 checks passed 5/5 and mobile typecheck passed; CI, holdout and test immutability were green. The production `STORE` build from `7a31384` is a managed-credential signed AAB for `in.gymloop.mobile` version `1.0.0` (`2`). Artifact, certificate and merged-permission evidence: `docs/evidence/2026-09-20-phase8-production-release.md`; AAB SHA-256 `129C5339A629C3AB2BFE937C7C304D44E4A3BEBEB1ED3CFCEB393F34A674C239`. | HARD-002's reviewable configuration, unique release version, test integration, least-privilege manifest and signed-AAB readiness proof are satisfied. Physical-device install and Play publication remain separately Partial/External under HARD-008. |
| HARD-003 | **Partial** | Earlier role/consent fixes through `e7a5883`; role/contrast/test commits `37f9c16`/`3bb641d`/`73def13`; member, desk and owner route tests `deb3e74`/`dc3e8b1`/`b24cfe3`; production auth-wait correction `6cf458b`; CI `35597428131`/`35597828557`/`35598747383`/`35599835395`; production deployment `dpl_DeQTPPHhisD8erdRe4GGg6YFCmEU`, 2026-09-21 | Five-role landings and forbidden routes passed locally and on the production alias; CI/holdout/immutability passed after the cold-runner test split. Six member, four desk and four owner secondary routes passed Light/Dark axe/English/overflow checks locally and in CI. A production-only test race was found on immediate post-sign-in navigation and repaired with explicit home waits in `6cf458b`; production reruns then passed member 12/12 and desk/owner 16/16. CI, holdout and test immutability passed for the correction. Synthetic UI journeys and distinct gym-owner sessions proved reciprocal foreign-member 404s, a foreign payment 404, an Iron-owner → QA check-in refusal, and tenant-scoped positive visit counts. A later QA-owner → Iron rollback-only database probe and Iron-front-desk → QA live API POST both refused foreign check-ins with zero side effects; exact IDs below. | Full Playwright-automated mutation-complete A–D journeys and complete two-gym browser acceptance remain open. The QA owner used Google OAuth in the in-app browser while Iron Box used a separate Playwright context, not two independently signed-in owners in the same checked-in run. Controlled second-gym credentials and disposable fixtures are needed for repeatable CI mutations. Owner: web acceptance/infrastructure owner. |
| HARD-004 | **Partial / External execution** | Red visible/blind contracts from `552313a` and `47ad1f7`, frozen interface through `20e2fff`, final implementation `ee0bc4d`; repository, 2026-09-20 | `pnpm exec vitest run scripts/__tests__/phase8-load-safety.test.ts supabase/tests-holdout/phase8-load-safety.holdout.test.ts` passed 16/16. Fresh Sol critic returned GO after direct-k6 parity review. `scripts/phase8-load-safety.mjs`, `tests/load/phase8-morning-checkin.js`, and `docs/runbooks/load-testing.md` provide the fail-closed preflight, exact 100 × 500 morning spike, approved p95 threshold, unique event keys, real read/mutation denial probes and credential-free evidence boundary. No k6/network/database command was run. | Owner: infrastructure owner. Provision and positively verify a separate non-production Supabase project, deployed API and synthetic 100 × 500 fixture, then execute the runbook and attach raw-result checksum and measured evidence. Production remains refused. |
| HARD-005 | **Partial / External destination** | Interface `6edba6d`; visible/holdout red tests `c114182`/`6797571`; contract corrections `cf5afc9`/`154a4c8`; implementation `12beeca`; production-call-site tests `658525f` and implementation `bdfc81d`; repository, 2026-09-20/21 | Adapter checks passed 7/7. The API 500 path now emits one minimal event; independent visible/holdout call-site checks passed 3/3 each, and web typecheck/lint passed. `docs/runbooks/operational-monitoring.md` names proposed thresholds, role ownership, escalation and retention, explicitly unconfigured. No production provider delivery was observed. | Owner: production owner. Configure a real monitoring destination and alert route. Evidence still required: provider event id, alert receipt, actual rules/retention and named escalation owner. Until provider proof exists, external monitoring remains External. |
| HARD-006 | **Blocked / External legal** | Read-only implementation audit completed 2026-09-20; no runner or execution evidence attached | Governing durations and broad blank/delete/hold categories are in `docs/security.md`, but the contract does not classify personal columns, define clocks for several retention rows, cover `razorpay_mandates`, define export wire content, or distinguish category-wide retention from case-specific legal holds. `members.full_name` and `phone` are also non-null today, so truthful erasure cannot be added without a schema/product decision. No destructive command was run. | Owner: product/privacy owner freezes those decisions; production owner obtains qualified legal review. Then independent visible/holdout authors specify the member-derived export/erasure RPCs and service-only retention runner before CI-only migration work starts. Local tests cannot satisfy legal sign-off. |
| HARD-007 | **Partial / External restore** | Runbooks committed in `055e83c` on 2026-09-20; no cloud operation id | Procedures: `docs/runbooks/incident-and-breach.md` and `docs/runbooks/backup-and-restore.md`. They define roles, checkpoints, evidence, safe read-only review and the destructive approval boundary. No tabletop or Supabase cloud PITR restore was performed. | Owner: production owner/platform administrator; Privacy Lead for legal notification confirmation. Evidence: role/contact roster, tabletop record, current legal/DPA decision, backup-control capture and disposable-target cloud restore operation with validation/cleanup. Gate 29 remains external/unperformed. |
| HARD-008 | **Partial / External exact-artifact device and Play** | Current-source production EAS build `7d603487-57a7-4f71-9413-3b60b6ca6302` from `acd7b44d04044db11019f2552b66a15414cbf422`, completed 2026-09-21 07:04:46 UTC; prior v2 build/evidence in `docs/evidence/2026-09-20-phase8-production-release.md` | Public HTTPS web/API and EAS production public-variable names are configured. Managed-credential `STORE` AAB for `in.gymloop.mobile` version `1.0.0` (`5`) downloaded to `dist/releases/gymloop-1.0.0-5-production-acd7b44.aab` (95,189,796 bytes), SHA-256 `46F4C1F45D3F98A29051C1F6F3C3911E5991E9CEF07DB0A1445FC1D8D12C8AB9`; `jarsigner -verify` said `jar verified`, and upload certificate SHA-256 is `AA:92:3C:58:3E:2A:9D:E0:B2:54:46:DA:19:17:E6:40:19:8E:66:46:87:EE:DF:2B:38:75:0D:B1:33:33:C8:63`. CI, holdout and immutability for source commit passed. Baseline debug-device journey remains `docs/evidence/2026-09-20-phase7-android-device.md`. | No exact-AAB physical smoke or Play upload occurred. Gymloop has no Play app record yet; account-holder policy/export declarations, Play App Signing and internal-track install precede the checklist. A matching preview APK may verify product behavior, not discharge exact-AAB/Play proof. Owner: Play account holder and release tester. |
| HARD-009 | **Passed — dependency tracking only** | External dependency index in this ledger, updated in `26e1237` and reviewed against the frozen contract on 2026-09-21; repository/current project | Each external row below names the dependency, HARD/gate link, current status, owner/action, needed evidence and next safe step. Razorpay and Cloudflare gaps are separate rows. A fresh Sol critic confirmed that traceability may pass while the external work remains unresolved. No provider, legal, store, backup, monitoring or device success is synthesized. | Owner: Phase 8 orchestrator keeps the index current. Passing this ledger requirement does **not** pass the listed HARD/gate dependencies; attach their real evidence before changing their own statuses. |
| HARD-010 | **NO-GO / Partial** | Frozen contract `2e8d313`; profile test `65c0533`, repair `acd7b44`, live browser test `f4ad425`; CI/holdout/immutability `35569948931`/`35569948871`/`35569948866`; EAS preview `9f2bc7bb-d7d0-43bb-b080-4f450d234244` from `acd7b44`, 2026-09-21 | The previously cited absent gym identity is fixed in Android/web You. Focused HIG test 12/12, mobile/web typecheck and lint passed. Production web profile at 390×844 showed `Iron Box Fitness — Vijay Nagar · IRNBX1` without horizontal overflow; targeted Playwright 1/1 passed in light/dark. Physical OnePlus DN2101 Android 13 received matching preview APK `dist/releases/gymloop-1.0.0-5-preview-acd7b44.apk` (140,681,548 bytes; SHA-256 `D2E384BDECAC8C3E9C1D7F0D0FC45D35D8BF6968057267EB36266318CAA51AF8`) via `adb install -r`, preserving app data; `dumpsys package` confirmed version code 5. Real demo-member sign-in reached You and rendered gym name/code in both modes. Screens: `docs/evidence/screens/2026-09-21-phase8-web-you-verified-gym{,-dark}.png` (SHA-256 light `93F9B486E0F8C5121701CE564F33A8D102A31E7A68DF84134AC84E9E04C85990`, dark `3EFEAF7EE93633B07F0BAF8CEC6F3FAB6F152FCED11D0843448CF8484D9D83CF`) and `docs/evidence/screens/2026-09-21-phase8-android-you-verified-gym-{light,dark}.png` (light `7FDD6B85FAA26363A9260E400D8E38549C4D9A12720F2C9A6BCDD5CE2D99F71B`, dark `A72F22BBEB808911EF9DD4D6B2C4B7620B34D4811ADE712E37D83404F37D0279`). | Fresh Sol critic: GO for immediate gym name/code, but NO-GO overall because Android's oversized/sparse profile puts identity below a wrapped email and both platforms lack explicit verified state and the approved grouped account destinations. Fix that cited hierarchy/account-surface dimension and rerun narrow visual review when usage permits. Owner acceptance remains separate. Preview proof does not substitute for exact production-AAB Play install under HARD-008. |
| HARD-011 | **Passed** | Visible/holdout contracts `2e8d313`/`71b6f0c`; implementation `4dc787f`; origin-boundary contracts `90a6a2d`/`27df988`; repair `5e4b534`; production deployment `9h745WmLGeD3YeMBtMkgCrb54qdm`, 2026-09-21 | Independent tests cover the fixed callback, every linked-role home, unlinked/no-access result, failure handling, redirect refusal and no identity mutation. A controlled real Google account completed production OAuth and reached `/not-linked` with the generic “no complete active gym or platform identity” state; no Gymloop role, tenant, member, membership or claim was created, and the session was signed out. Email/password remains available. | Requirement passed. Real linked-role routing is independently test-proven; the provider journey intentionally used an unlinked controlled account to prove authentication alone grants no Gymloop identity. |
| HARD-012 | **Passed** | Config `5d88237`; credential-scope contracts `167d24f`, `2da5f2e`, `f7a4b2f`, `b0e6592`; scoped implementation `88335cf`; origin-boundary contracts/repair `90a6a2d`, `27df988`, `5e4b534`; auth workflow `35533772247`; deployment `9h745WmLGeD3YeMBtMkgCrb54qdm`, 2026-09-20/21 | Google Cloud project `gymloop-auth-prod-2026` has web client `Gymloop Supabase production` and exact callback `https://pecxrpskmfeuyzngvewq.supabase.co/auth/v1/callback`. The workflow returned HTTP 200 with the access-token hook enabled, `site_url=https://gymloop-phi.vercel.app`, the exact production/local/mobile allow-list, and Google client id/secret presence booleans. Public Auth settings then reported Google and email enabled. `webAppEnv()` isolates the fixed server-owned origin from unrelated secrets; Android uses PKCE and `gymloop://auth/callback`. Credential-scope tests passed and fresh Sol critics returned GO. No secret value is stored in source, browser bundles or evidence. | Requirement passed. Physical installation of the exact AAB and Play distribution remain separately External under HARD-008; they are not OAuth credential-boundary requirements. |

## 2026-09-21 bounded live browser check

At 08:55 UTC, source `91fe8ee` ran
`$env:PLAYWRIGHT_BASE_URL='https://gymloop-phi.vercel.app'; node --env-file=.env.local node_modules/@playwright/test/cli.js test tests/e2e/phase8-accessibility.spec.ts --workers=1 --reporter=line`
against the public Vercel site and linked Gymloop Supabase project. Result:
**4 passed in 33.8 seconds**. The run signed in with the existing demo member,
front-desk and owner identities, checked their role homes and navigation,
verified the member's gym name/code at mobile width, and ran light/dark axe,
English-only and overflow checks. The suite made no product-data mutation; Auth
sessions were created. This is evidence only for the named read-only journeys.
It does not supply journey D, a second gym, cross-tenant mutation denial, the
100 × 500 load run, or exact cleanup evidence, and HARD-003/004 remain Partial.

At 09:07 UTC, a second read-only production smoke signed in as the existing
trainer and super-admin demo identities. Trainer landed on `/console`, saw
Check-in, Follow-ups, Members and Add-ons, and was redirected from `/dashboard`
back to `/console`. Super-admin landed on `/platform`, saw Gyms, Onboard, status,
tier, preview and owner-link controls, and was redirected from both `/console`
and `/dashboard` back to `/platform`. These were separate authentication
sessions; no gym-record action was invoked. This extends role-landing and
forbidden-route evidence, not the mutation-complete or two-gym proof. The most
recent database workflow `35534256559` also passed migration, pgTAP rollback,
schema drift, pgTAP and seed dry-run against the linked project; those passing
unchanged suites were not rerun for this smoke.

At 09:16 UTC, a one-off in-memory Playwright smoke used five fresh browser
contexts and the existing demo credentials against the same production URL.
It made GET navigations only and observed the expected path, HTTP 200 and no
fatal page for all **23 primary destinations**: member Home/Activity/My gym/You
(4); front desk Check-in/Follow-ups/Members/Add-ons/Leads (5); trainer
Members/Check-in/Follow-ups/Add-ons (4); owner Overview/Check-in/Follow-ups/
Members/Payments/Messages/Add-ons/Leads/Imports (9); super-admin Platform (1).
No form was submitted or gym record intentionally mutated; Auth sessions were
created. This is route-health evidence, not assertion of a completed payment,
check-in, message, import, second-gym isolation or HARD-003 acceptance.

At 09:48:25 UTC, the read-only linked-project query
`supabase db query --linked "select (select count(*)::int from public.organizations) as organization_count, (select count(*)::int from public.organizations where status in ('active','trial')) as eligible_organization_count, (select count(*)::int from public.staff where user_id is not null) as linked_staff_accounts, (select count(*)::int from public.members where user_id is not null) as linked_member_accounts;"`
returned one organization, one active/trial organization, three linked staff
accounts and one linked member account. There is no existing second-gym browser
fixture. Creating one in production would append platform audit and change Auth
state, with no supported exact cleanup path, so no onboarding or cross-tenant
mutation was attempted. The frozen HARD-003 two-gym journey remains Partial;
the owner-deferred staging environment was still needed for that proof at
09:48. The 11:30 two-owner bounded check below supersedes this fixture gap,
not the full A–D automation gate.

## 2026-09-21 production control inspection

At 09:39 UTC, `supabase backups list --project-ref pecxrpskmfeuyzngvewq
--output-format json` returned `backups: []` and `pitr_enabled: false` for the
linked Gymloop project in `ap-south-1`. A read-only database-size query returned
30 MB. This proves the cloud control currently lists no recovery point; it is
not a backup or restore result. No dump or restore was attempted. HARD-007 and
gate 29 remain Partial/External. A manual logical backup needs a protected,
off-site destination and a recovery/retention procedure before it can count as
an operational control.

The authenticated Vercel CLI identified `ogun01s-projects/gymloop`; its
production environment list contained only `WEB_APP_URL`,
`NEXT_PUBLIC_SUPABASE_ANON_KEY`, and `NEXT_PUBLIC_SUPABASE_URL`. No monitoring
destination or alert route is configured there. The repository's
`createOperationalLogger` is an adapter contract with tests, but no production
caller or provider credential was found in tracked source/config. No provider
event or alert was emitted. HARD-005 remains Partial/External, not Passed.

At approximately 09:52 UTC, a new local production-call-site slice committed
red visible/independent holdout tests in `658525f`, then implemented the minimal
`apiFail('server_error', ...)` event in `bdfc81d`. The focused visible and blind
tests each passed 3/3; `pnpm --filter @gymloop/web typecheck` and
`pnpm --filter @gymloop/web lint` passed. The event carries only its stable name,
level and timestamp—never the response code, free-text message or arbitrary
details. This supersedes the earlier **no caller** source finding after
deployment; it does not establish a provider destination, alert delivery or
live production event. No artificial 500 was sent to production.
For source `cd8745d`, CI `35585734586`, holdout `35585734611` and
test-immutability `35585734597` completed successfully. Vercel production
deployment `dpl_D3DP5xXqwY4GVxrqEB4RybisrtSG` was Ready and assigned
`https://gymloop-phi.vercel.app`; readiness is not an alert-delivery test.
The logger's omission of response fields does not sanitize the response itself:
`apiFail` still accepts arbitrary caller-supplied `details` and `message`.
Callers must continue to pass only safe user-facing values; this slice does
not assert end-to-end 500-body secret filtering.

## 2026-09-21 synthetic-test baseline and reset boundary

At 10:14:52 UTC, a read-only `supabase db query --linked` count across
`auth.users`, the public demo tables and `storage.objects` returned one gym,
46 members, 981 attendance rows, 34 payments, eight leads, three add-on
orders, 16 notifications, six Auth users, zero webhook events and zero Storage
objects. The owner confirms this is prelaunch and authorizes synthetic
functional testing in the same project. A second read-only status count found
active, paused, expired, cancelled and blocked member scenarios plus active,
pending, frozen, expired and cancelled memberships. This is already a broad
synthetic seed, not an empty database awaiting bulk population.

`supabase db reset --linked` was inspected with `--help` but **not executed**.
The demo seed does not recreate Auth sign-ins (`docs/demo-accounts.md`), and
the project currently has no listed backup/PITR recovery point. A future
reset therefore needs a verified recovery and Auth-recreation procedure; the
owner's testing authorization is not evidence that one exists. The existing
rollback-wrapped SQL suites remain the safe way to exercise large scenario
matrices without permanent rows. HARD-003/004 and the restore gate remain open.

At 10:27:57 UTC, the front-desk demo identity completed a bounded production
UI journey for fictional lead `QA-20260921-LEAD-A7K3` (lead
`2805f753-9b05-4c6f-9d1e-4d91affd8ca4`): new → contacted →
trial_scheduled → trial_done → converted. The screen showed the converted
member link, and a read-only linked-project query confirmed stage `converted`
and active member `3041d7d8-4254-4e33-8764-1a1c2e5cee87`. No outbound
contact or payment occurred. These two IDs are the exact synthetic cleanup
scope; no reset or cleanup has yet been performed. This proves the one-gym
lead flow only, not the two-gym HARD-003 journey.

At 10:32:10 UTC, the owner UI processed a three-row fictional member import
(`dcdee930-6d8a-47ad-a5ec-f4fab5bd7d59`). Its preview and committed result
reported one accepted row, one duplicate phone within the file (`file_phone`),
and one invalid phone (`invalid_phone`). A read-only linked-project query
confirmed `status=completed`, `row_count=3`, `imported_count=1`,
`duplicate_count=1` and the exact error-report dispositions. The imported
active member is `743600fe-79d2-4013-bb53-3c0e34c6c71e`, named
`QA-20260921-IMPORT-A7K3`; the other two rows created no member. No replay
control was exposed in this completed UI flow, so idempotency was not claimed
from the browser journey; the existing rollback-wrapped contract tests cover
it separately. No contact or payment occurred. These IDs remain in the exact
synthetic cleanup scope.

At 10:29–10:30 UTC, a separate front-desk UI session created member
`QA-20260921-CORE-R7K3` (`bf4d2076-2501-4217-b7ed-4e1b8f10c74f`), recorded
one assisted visit (`f916b0e2-3643-4fed-bdf6-2181d41e10ea`, source
`front_desk`), then sold a 30-day membership
(`6ecce1b3-2795-47f8-932c-d47bc86091d8`, 2026-09-21 through 2026-10-21)
for INR 150000 paise cash (`29640260-100f-418c-b776-b14cd12cabbd`, receipt
`2026-27/000011`). The member history, receipt and owner dashboard rendered
the visit and collection; read-only linked-project queries independently
confirmed the visit, active membership and paid payment facts. The receipt
number is immutable and remains spent even if synthetic rows are later
cleaned up. This was a real one-gym core-loop browser journey, not HARD-003's
complete A–D or second-gym proof.

The same journey first exposed stale live demo-catalogue data: the only
UI-selectable active diet-plan offer returned `catalogue_incomplete`; the
other displayed offers were disabled as incomplete. The source seed had
already corrected these fields in `e7f7902`, but the deployed demo rows were
older. The first refusal created no order or payment. At 10:38:48 UTC, the
owner UI saved only diet offer `00000009-0000-4000-8000-000000000003` with
its commercial terms unchanged. A read-only query confirmed the stale trainer
reference cleared and quote version rotated from
`ab8d650b-f383-496b-a318-45f1f8c2fc81` to
`c888b693-6a5e-49cb-b9ab-8afb742d5b30`; historical order
`00000010-0000-4000-8000-000000000002` remained untouched. No broad seed
rerun or SQL mutation was used. The remaining incomplete legacy demo offers
still need their missing disclosures completed before they can be sold.

At 10:40:01 UTC, the front-desk UI sold that now-valid diet plan to the QA
member: add-on order `f9bcca06-6360-4d6b-b077-c2f008a5d29f`, cash payment
`0d9f08bb-322f-4059-9ab4-d4aade30d348`, INR 250000 paise, receipt
`2026-27/000012`. One UI fulfilment action made the order `completed` at
10:40:02 UTC; it is valid from 2026-09-21 through 2026-11-15. Read-only
queries independently confirmed the member/offer/payment links, terminal
order status and paid receipt. The UI showed no second sale, and no refund
was attempted.

At 11:02:54 UTC, the owner UI corrected only the canonical seven-day
validity on seeded Whey Protein offer
`00000009-0000-4000-8000-000000000004` (other terms, INR 240000-paise
price and starting stock 24 unchanged); its quote version rotated from
`7e886c5c-4522-4ab1-83c9-2eb8bd8a2744` to
`586eef33-ec32-4d7b-87ad-a640136b345f`. The front-desk UI then sold one
unit for cash to the same QA member: order
`c664f636-992e-4b78-8408-d15c2b49f294`, payment
`d338dd14-b515-48b0-9307-927a59e2d09d`, receipt
`2026-27/000013`. Products complete on handover at sale, so no separate
delivery action was available or claimed. Read-only database queries
confirmed `completed`, paid INR 240000 paise and stock `24 → 23` exactly
once. The historical completed order
`00000010-0000-4000-8000-000000000003` was left unchanged.

At 11:06:09 UTC, the owner UI completed only the missing canonical `ACE-CPT`
qualification on PT Starter offer
`00000009-0000-4000-8000-000000000001`; trainer, INR 800000-paise price,
90-day validity, twelve sessions and other terms were preserved. Quote
version rotated from `d6bfcf94-fd6a-435e-ad49-82accbe78711` to
`1ea56982-226f-49d7-b6be-f1a28ec9f9d0`; historical active order
`00000010-0000-4000-8000-000000000001` was not changed. The front-desk UI
sold one PT package to the QA member for cash: order
`7a2614d0-2962-4c5a-9cc6-b7f0ade5eb23`, payment
`c2d32764-1c2b-4bca-91c4-e75ea30f2708`, receipt
`2026-27/000014`. Read-only queries confirmed a paid INR 800000-paise
payment, active twelve-session entitlement with zero used, and one required
initial booking `6fd29232-7642-4757-8a6f-ff50f1bd3a2a` for 2026-09-22
15:30–16:30 UTC. The future session was not completed or consumed. Owner and
front desk correctly lacked a cancellation control; the assigned trainer UI
then cancelled exactly that synthetic booking once. At 11:15:46 UTC a
read-only query confirmed `cancelled`, zero other sessions on the order,
active twelve-session entitlement and zero used. The trainer slot is free.

At 10:33:57 UTC, the platform UI onboarded exactly one synthetic gym,
`QA-20260921-TENANT-A7K3` (`7eb2f564-0c3b-49b6-8104-1902241a5955`,
code `177141`). Read-only linked-project queries confirmed one settings row,
one default branch (`b3331474-91d3-4925-92c5-041c7e744117`), one
zero-credit messaging wallet and one active unlinked owner
(`fc1df639-18fc-45ae-bf16-73c26702a9b7`). It remains `trial`, with
`activated_at` null and a 2026-10-04 18:30 UTC trial boundary. One activation
attempt was refused with `Readiness incomplete: owner_access`, leaving those
facts unchanged. No Auth user was created or linked, and this does **not**
prove a second gym's authenticated browser isolation; that still needs a
distinct tenant identity and separate session. The 11:30 owner link and
two-session check below later changed this fixture state.

At 11:06:54 UTC, the super-admin began one reasoned, time-limited preview of
the synthetic trial gym (`d45a9eaa-dd5c-46f3-8356-71795989519a`). The
preview banner showed that gym and code `177141`, its roster showed no
members, and a direct detail route for known Iron Box member
`bf4d2076-2501-4217-b7ed-4e1b8f10c74f` returned 404. The exact preview
ended through the UI at 11:07:48 UTC; a read-only linked-project query
confirmed `ended_at` and the intended tenant/reason. Audit events
`3e2b436a-4a75-4a3d-9c82-49f792a2a6a3` (start) and
`17b03c95-3dcb-4ee6-ac2e-4558a278939a` (end) remain. This supports
preview-scope read isolation only; it is not a separate gym-owner credential
or a cross-tenant mutation test.

At 10:41 UTC, a bounded staff messaging attempt for that QA member exposed
that `/messages` populated its consent selector only from prior notification
rows. The implementation-blind visible test was committed red in `c9aef0b`,
its off-gym mock was corrected to respect the RLS boundary in separate
`spec:` commit `7dbeb59`, and `e7a5883` reused the existing RLS-bound,
cursor-paged phone search. Focused tests passed 26/26, web typecheck/lint and
registry-lint passed, CI `35590795690`, holdout `35590795621` and
test-immutability `35590795573` passed, production deployment was Ready, and
an independent narrow review returned GO. At 10:59:18 UTC, a real front-desk
session searched phone suffix `0124`, selected that previously unmessaged QA
member and recorded one withheld marketing decision
(`3f9f930d-125d-4efd-b30d-b44e211c4da0`, version `2026-09-01`, source
`phase8_prelaunch_qa`); the API returned 201. Read-only linked-project
queries confirmed the exact member/purpose/actor and `granted=false`, zero
notifications for that member and the demo wallet unchanged at 4,500 credits.
No message or external delivery occurred. This proves consent capture only,
not the full paid/outbound communications lifecycle.

At 11:01:47 UTC, a fresh front-desk session inspected the red list for the
seeded fictional case `ad3840a8-c912-4e75-b3e8-68e02e3994ad` (member
`00000005-0000-4000-8000-000000000111`). The UI showed 83 days away, no
visits and no contact; read-only linked-project state showed the case open,
zero follow-up rows and no contact or next-follow-up timestamp. The available
actions all represented real outreach (`call`, `whatsapp`, `in_person`,
`sms`), so no action was submitted or falsely recorded. This is a truthful
read-only risk-list check, not evidence that a contact/follow-up journey passed.

At 11:13:37 UTC, the owner receipt UI submitted exactly one INR 50000-paise
partial cash-refund request against the QA membership payment
`29640260-100f-418c-b776-b14cd12cabbd` (receipt `2026-27/000011`): refund
`a079c59c-69e3-42a9-8e52-272d022a6f58`, reason `Phase 8 prelaunch
synthetic QA`. The UI showed INR 50000 pending and INR 100000 still available;
a read-only query confirmed status `requested`, `processed_at` null, payment
still paid and the 30-day membership unchanged. No cash was handed to a real
member, so the refund was **not** marked completed or counted as money
returned. No generic membership-refund cancellation control was available in
the UI. This exact synthetic pending request must be resolved through an
approved product workflow or removed as part of a verified future reset before
launch; do not misreport it as a completed refund.

At the 11:16 UTC read-only reconciliation, the linked project had six Auth
users (unchanged from baseline), two gyms (+1), 49 members (+3), 982
attendance rows (+1), 38 payments (+4), one requested refund (+1), nine
leads (+1), six add-on orders (+3), 16 notifications (unchanged) and 61
consents (+1). The QA PT session is included among six `pt_sessions` rows
but is cancelled and consumes no entitlement. Two `member_imports` rows
exist for the same QA CSV: completed run
`dcdee930-6d8a-47ad-a5ec-f4fab5bd7d59` and earlier pending, zero-import
run `2b05cf12-f75b-4fef-b8bb-8f3172580bd4`. The tester observed an
abandoned first preview followed by re-upload, which most likely explains
the two runs; no commit/replay of the first was observed. Both IDs belong
to the synthetic cleanup scope.

## 2026-09-21 two independently signed-in gyms

At 11:30:18 UTC, the super-admin's production platform UI linked the existing,
previously owner-authorized Google Auth account to the synthetic gym's sole
active owner staff row `fc1df639-18fc-45ae-bf16-73c26702a9b7`. Before the
link, a read-only query confirmed that Auth user had zero staff, member and
platform links, and its Google sign-in reached `/not-linked`. The owner-link
command created audit event `3232b789-6ed2-4449-a0fe-8483c853ebab`; a
read-only query confirmed its `user_id` and tenant. After signing out and
signing in again with Google, a separate in-app browser session landed on
`/dashboard` with synthetic gym code `177141` and zero initial visits. The
Iron Box owner signed in independently in a fresh Playwright browser context.
No new Auth user, credential, platform role or Iron Box identity was created
or changed. The QA owner link is durable synthetic state with no supported
exact unlink workflow; it belongs to the future verified cleanup scope.

In the QA-owner session, direct Iron Box member
`bf4d2076-2501-4217-b7ed-4e1b8f10c74f` and membership detail routes both
rendered 404. Its direct Iron Box payment receipt
`29640260-100f-418c-b776-b14cd12cabbd` rendered 404, and check-in search
for that member's phone suffix `0124` returned “No member of this gym matched.”
Through the QA owner UI, one fictional active member
`QA-20260921-TENANT-B-MEMBER` was then created in the QA default branch:
`6211481a-30fc-4f7c-891b-c02d06e95c74`, phone `+12025550126`.
The separately authenticated Iron Box owner received HTTP 404 and the same
404 page for this QA member's detail and membership routes. An Iron Box owner
POST to `/api/check-in` with that foreign member id, a reason and unique
client event id `1eb146c2-8cb7-431d-a679-55df021e59d9` returned HTTP 404
`member_unknown`; a read-only linked-project query found zero attendance rows
for that event id and zero visits for the QA member immediately afterwards.

The QA owner then recorded exactly one legitimate assisted visit for its own
member through the UI, reason “Phase 8 synthetic two-gym isolation check”:
attendance `ff4fdcaf-6490-4079-bcdc-080eff4c7496`, source `front_desk`,
tenant `7eb2f564-0c3b-49b6-8104-1902241a5955`, at 11:34:36 UTC. A
read-only query confirmed the tenant/member/reason; both separate owner
dashboards showed one visit today, not a combined total. At 11:35 UTC the
linked project had six Auth users, two gyms, 50 members, 983 attendance rows,
38 payments and one requested refund. These sessions prove a bounded real
two-gym read boundary and one-direction direct mutation refusal, not the
frozen mutation-complete A–D Playwright suite or every reverse-direction
mutation. No reset or synthetic cleanup was performed.

### 2026-09-21 five-role browser acceptance increment

The independent browser-test author expanded `tests/e2e/phase8-accessibility.spec.ts`
to sign in all five seeded roles in separate browser contexts, check role-correct
landings, reject forbidden route access, scan each landing page with axe in both
Light and Dark, and check English-only/390px/1440px behavior. The red test
exposed trainer-console Dark-mode table/link contrast of 2.4:1; the web
adapter now maps those elements to the semantic secondary-text token.
The test-only commit is `37f9c16` and the implementation commit is `3bb641d`.
Focused local browser checks passed 4/4, web lint and typecheck passed, and
the production alias `https://gymloop-phi.vercel.app` resolved to Ready
deployment `dpl_DeQTPPHhisD8erdRe4GGg6YFCmEU`. The same four focused
browser checks passed against that production alias. Holdout and test
immutability workflows passed for `3bb641d`; full CI run `35596865110`
failed only the combined five-role test's 30-second cold-runner timeout
(3/4 tests passed), not an accessibility or route assertion. The independent
test author split the unchanged assertions into five per-role test cases in
`73def13`; the focused local role run passed 5/5. CI `35597428131`, holdout
`35597428162` and test immutability `35597428204` then passed. The separate
six-route member expansion `deb3e74` passed 12/12 focused local Light/Dark
axe/English/390px/1440px checks; CI `35597828557`, holdout `35597828601`
and test immutability `35597828459` passed. The four front-desk routes in
`dc3e8b1` passed 8/8 focused local checks. The four owner routes in
`b24cfe3` passed 8/8; the test initially flagged template `Locale` controls
on owner Messages as a product-language selector, but ADR-132 explicitly
preserves Phase 6 delivery metadata. The corrected assertion permits only
the exact `Locale` controls inside the message-template section and still
forbids any product-language control; owner Messages narrow rerun passed
2/2. No application data mutation occurs in these scans. CI `35598747383`,
holdout `35598747332` and test immutability `35598747306` passed for the
desk/owner increments. The first production-targeted desk/owner attempt hit
a harness race: secondary-route tests navigated before sign-in completed and
redirected to `/sign-in`. The independent test author added home-route waits
for all secondary-route loops in `6cf458b`; the narrow production repro
passed, followed by the entire production member 12/12 and desk/owner 16/16
route scans. CI `35599835395`, holdout `35599835317` and test immutability
`35599835419` passed for the harness correction.

This adds role/appearance/route evidence, not mutation-complete A–D or a
repeatable two-gym CI fixture. The five password demo identities belong to
Iron Box; the QA gym owner is Google-authenticated with no controlled
Playwright password or pre-authenticated fixture. Safe repeatable foreign
mutation tests need independent second-gym credentials and disposable
fixture/cleanup control. They must not turn CI into uncontrolled permanent
writes on the linked production-configured project.

## 2026-09-21 QA-owner cross-surface isolation follow-up

At 14:14–14:16 UTC, the existing Google-authenticated owner of synthetic gym
`7eb2f564-0c3b-49b6-8104-1902241a5955` (code `177141`) used the live
production alias in its separate in-app browser session. This was read-only:
no form submission, payment, consent change, message or database write was
made. The `/console` phone search for Iron Box's fictional member suffix
`0124` returned “No member of this gym has that phone number”; the unfiltered
roster contained only QA member `6211481a-30fc-4f7c-891b-c02d06e95c74`.
On `/add-ons`, searching that foreign suffix returned “No members found”,
while the positive control `0126` returned that QA member. On `/messages`,
the consent member selector likewise had no member for `0124` and returned
the QA member for `0126`. `/payments` showed no payments and `/red-list`
showed no follow-ups for this gym. These checks extend the earlier direct
route and check-in refusal evidence across three additional selection/read
surfaces; they do not prove reverse-direction direct mutation denial or the
frozen mutation-complete A–D Playwright suite. HARD-003 remains Partial.

## 2026-09-21 privacy delegation and backup/load boundary

The owner delegated Gymloop's product privacy policy: no sale of member data;
service-purpose retention; portable export and erasure on a verified request,
subject to documented financial, audit and case-specific legal obligations.
ADR-144 records this direction, not statutory sign-off or a completed runner.
The schema inventory found no request/hold/operation ledger, no executable
field-level disposition map, several ambiguous retention clocks and non-null
member name/phone constraints. The owner-delegated draft at
`docs/planning/privacy-operations-contract.md` now records safe product choices
and explicit unknowns; it is not a frozen field map or a working runner.
HARD-006 remains Blocked pending a frozen
technical contract, independent tests, implementation and qualified legal
review. No export or erasure was run.

The owner also requested HARD-004's 100 × 500 workload on the linked project.
Read-only `supabase projects list` and backup inspection identified the same
`pecxrpskmfeuyzngvewq` Gymloop project as `ACTIVE_HEALTHY`; the backup result
reported `pitr_enabled=false`, no listed backups and no physical backup data.
`supabase db dump --linked` is available for a logical export, but no dump or
restore was created. The accepted HARD-004 preflight excludes this production
reference, and a same-project restore would replace its data. Therefore no
load, provider restore, reset or SQL mutation was run. HARD-004 and HARD-007
remain Partial/External; a manual dump alone would not prove a restore drill.

## 2026-09-21 rollback-only reverse-direction database isolation probe

At 15:10 UTC, from repository `74eea1d`, the linked Supabase CLI identified
project `pecxrpskmfeuyzngvewq`. A one-submission `BEGIN; SELECT
txid_current_if_assigned(), current_user; ROLLBACK;` confirmed transaction
handling under the administrative query role. Read-only preflight confirmed
the active QA owner staff `fc1df639-18fc-45ae-bf16-73c26702a9b7`, the
distinct Iron Box member `bf4d2076-2501-4217-b7ed-4e1b8f10c74f`, an
unused event key `540c9d37-e01e-4121-96d5-4778afcc8616`, and the actual
access-token hook's QA tenant/role/staff claims. No credentials were recorded.

The operator submitted one `BEGIN … ROLLBACK` SQL transaction through
`supabase db query --linked --output-format json`. It set local JWT claims
from that live hook result, switched to local `authenticated` role, asserted
active member RLS and the expected claim accessors, and found the Iron member
invisible. Inside a caught PL/pgSQL subtransaction it attempted an attendance
insert with QA tenant plus the foreign Iron member/branch and the fresh event
key. The result was `DENIED:23503` (cross-tenant foreign-key relationship),
with `no_visible_probe_row_before_rollback=true`; the explicit outer rollback
completed. A separate read-only query, `select count(*) from
public.attendance where client_event_id =
'540c9d37-e01e-4121-96d5-4778afcc8616'::uuid`, returned **0**. An
earlier PowerShell SQL-delimiter parse attempt failed before any DML.

This proves live-hook-derived database claim/RLS read isolation and direct
cross-tenant relationship rejection in the QA-owner → Iron direction with no
persistent probe row. It does **not** prove an OAuth-issued browser token, an
API-route denial, or the mutation-complete Playwright A–D journeys; HARD-003
remains Partial.

## 2026-09-21 database-credential exposure and mitigation

At approximately 15:18 UTC, a Supabase CLI `db dump --linked --dry-run`
diagnostic printed the linked project's database password into this task's
tool output. The command was dry-run only: it created no dump or database
mutation. No credential value was committed to the repository or copied into
this ledger. An attempted automated Management API rotation was rejected by
execution policy **before any process ran**. The owner subsequently reported
resetting the password in Supabase Database Settings. The gitignored
`.env.local` key had one entry and a new modification time of 16:06:55 UTC;
the GitHub Actions `SUPABASE_DB_PASSWORD` secret metadata updated at 16:07:55
UTC. `supabase link --project-ref pecxrpskmfeuyzngvewq --password <redacted>`
returned success with that new local value; no password value was printed.
An invalid-password `supabase db query --linked` negative control also
returned success, showing that query path is not password-verification
evidence. The old credential's direct rejection was **not** independently
observed; do not claim it. At approximately 16:12 UTC, workspace inspection
found the replacement value had also been entered in tracked `.env.example`.
The diff output exposed it to this task, although the file had never been
committed or pushed. A constrained local scrub restored the example key to
empty, and `git diff --quiet -- .env.example` confirmed it matches HEAD.
This second exposure requires another owner-submitted Supabase reset and
local/CI resynchronization before database work resumes. Do not inspect or
print the secret-bearing diff again. The separate account-wide Supabase
access-token rotation already named in `docs/security.md` remains a release
item.

Owner override later on 2026-09-21 (ADR-145): the owner accepts temporary use
of the current disclosed password for bounded synthetic verification while
there are no live customers, and commits to reset it before launch. The
immediate testing pause is lifted, but the credential is still disclosed and
**must not be treated as a production-ready secret**. Rotation of both the DB
password and account-wide token, synchronization of the local/CI copies, and
actual rejection verification remain open. This changes no HARD-004/007 load,
backup or restore boundary and authorizes no linked reset.

## 2026-09-21 reverse-direction live API refusal

After ADR-145, an ephemeral password-authenticated session for existing Iron
Box front-desk identity `divya@ironbox.example.com` submitted one POST to the
production `/api/check-in` endpoint, targeting existing QA-gym-only member
`6211481a-30fc-4f7c-891b-c02d06e95c74` with a stated assisted-check-in
reason and fresh event key `4da1dbb0-a82c-4c47-9f76-4b07be1665ee`. The
API returned HTTP **404**, `member_unknown`; the test signed out that session.
A separate read-only `supabase db query --linked --output-format json` count
for that exact event key returned **0 attendance rows**. The test printed only
status, error code and event key, never the password or bearer token. This
adds reverse-direction authenticated API mutation refusal to the previous
QA-owner → Iron database probe and Iron-owner → QA API refusal. It does not
prove browser OAuth, membership/payment/provider workflows or the complete
automated A–D acceptance; HARD-003 stays Partial. The CLI read-only query is
not independent verification of the disclosed database password.

The same Iron Box front-desk identity then retried its already-recorded own-gym
assisted event `50625596-e967-4f94-8a91-10df5241c9f6` for member
`bf4d2076-2501-4217-b7ed-4e1b8f10c74f` through the live API. The result
was HTTP **200**, `replay=true`, and the original attendance id
`f916b0e2-3643-4fed-bdf6-2181d41e10ea`; the session was signed out.
A read-only linked-project count for that tenant/event key remained **1**.
This proves one real idempotent staff retry, not simultaneous replay or a
member-device offline conflict. No new attendance fixture was created.

In a third ephemeral session, the existing Iron Box demo member authenticated
with a real Supabase token and queried `members` through the public client.
The user's own linked profile returned exactly one visible row; a direct query
for QA member `6211481a-30fc-4f7c-891b-c02d06e95c74` returned zero rows,
both without query errors. The session was signed out and no product row was
changed. This is a live member-role RLS read-isolation positive/negative pair,
not proof of every member-readable table or of a second-gym member session.

The same member-role positive/negative pattern was repeated for the financial
read path in a fresh ephemeral session: the member saw **2** own payments and
zero rows for known Iron Box payment
`29640260-100f-418c-b776-b14cd12cabbd` belonging to another member in the
same gym. Neither query errored, the session was signed out, and no payment
was written. This demonstrates live intra-tenant member-payment isolation for
that row, not a provider-signed payment, refund completion or all money tables.

## 2026-09-21 reversible 10 × 50 database simulation

**2026-09-22 owner direction:** continue bounded Phase 8 functional testing on
this same multi-tenant project, not a new per-gym database. The owner proposes
10 gyms × 50 members as a small-scale rehearsal. This section's completed
rollback run already covers the database insert/tenant-read part; it is not a
live API stress result. The full HARD-004 100 × 500 p95/cross-tenant load
claim remains unmeasured. A fresh read-only CLI connection attempt timed out
on 2026-09-22, so no durable bulk fixture or stress traffic was launched.

At the owner's request, the linked project ran a **single-transaction,
rollback-only** smaller-scale scenario, not the HARD-004 k6 workload. A
read-only preflight found zero `PX` simulation gyms and zero prefixed members.
The administrative transaction inserted 10 synthetic `pending_approval` gyms,
one branch each, and 50 synthetic members per gym (500 total) using distinct
gym codes, phones and member codes. It recorded counts before changing to a
local `authenticated` role with one synthetic gym-owner tenant claim. The
returned row was `fixture_gyms=10`, `fixture_members=500`,
`own_visible_members=50`, `foreign_visible_members=0` for a named second
gym. The transaction explicitly ended with `ROLLBACK`.

A separate read-only postflight returned zero simulation gyms and members,
and the original totals of **2 gyms / 50 members**. A first identical
transaction returned only its last scalar through the CLI; its postflight
also confirmed zero residue, so the second run combined the four assertions
into one returned row. No migration, persistent fixture, Auth user, API
request, payment, message, provider call or external load was created by
this simulation. It proves a 10 × 50 database insert/tenant-read boundary
under rollback, **not** a web/mobile end-to-end journey, measured latency,
50,000 check-ins or a recoverable load environment. HARD-003/004 remain
Partial; the canonical HARD-004 preflight still refuses this project.

## 2026-09-21 synthetic recovery journey (B backend path)

The existing fictional Iron Box case
`ad3840a8-c912-4e75-b3e8-68e02e3994ad` began `open` with zero follow-ups
and no visit today. A real front-desk password session, using its own claim,
inserted follow-up `65a7c0aa-b87b-49d2-9ce7-558e8b4df1c0`, channel
`in_person`, outcome `will_return`, with an explicit note that **no real
contact occurred**. The case became `contacted` and acquired `contacted_at`.
The same role called the production `POST /api/check-in` with fictional member
`00000005-0000-4000-8000-000000000111`, a reason explicitly saying **no
physical visit occurred**, and event key
`f3e03727-c2b4-484e-b52f-fb63a1637499`. It returned HTTP 200 and
attendance `caf6e9c7-0730-4230-8e36-a4137c41d077`; the case became
`closed` with both `returned_at` and `closed_at` set. Every test session was
signed out.

The Iron Box gym-owner session then called the actual `owner_metrics` RPC:
the exact case appeared in `components.recoveries`, with `recovered=2` and
`visitsToday=2` in that snapshot. The separate Google-authenticated QA-gym
owner's live browser dashboard still displayed one visit and zero recoveries;
its roster still had only its own one member. A fresh-context read-only
postflight independently verified tenant/member alignment, matching
front-desk actor ids on follow-up and assisted attendance, one row for the
event key, both closure timestamps, and zero notifications for this member
since the case opened. A further signed-in attempt to log a follow-up after
closure returned `GL031`; the case's follow-up count stayed one.

This is **synthetic product behavior**, not a claim that anyone was contacted
or entered a gym. The follow-up and attendance are durable QA rows, not
rollback artifacts; their exact ids above are in the future verified cleanup
scope. This closes one live backend/API recovery scenario and demonstrates
owner/tenant read separation, but it is not the checked-in Playwright A–D
suite, real outreach delivery, or customer-launch acceptance. HARD-003
remains Partial.

## 2026-09-21 assisted check-in to linked-member read (D partial)

Preflight found the fictional, app-linked Iron Box member
`00000005-0000-4000-8000-000000000001` active with no visit today and no
open no-show case. A real front-desk session called production
`POST /api/check-in` with a new event key
`80f6698b-291e-426f-85fa-bfa3e88ff569` and an explicit reason that no
physical visit occurred. The API returned HTTP 200 and attendance
`78da1e81-8e69-4978-bf93-1e2743eec93f`. After the desk session signed
out, an independent demo-member password session read that exact row through
the same Supabase `attendance` path used by native member Activity. It was
visible as `front_desk` with a non-null assisted-by actor. Read-only database
postflight found exactly one event row, the expected member, actor
`00000003-0000-4000-8000-000000000004`, source and synthetic reason.
The member session also signed out. This checks an authenticated
desk-write → member-read handoff and attribution, not a user tapping a
confirmation control, an actual physical entry, or the full checked-in
Playwright journey D. The attendance id is in the exact future QA cleanup
scope.

The connected OnePlus preview build was inspected afterward: it was at the
English sign-in screen, not in a member session. Therefore no current
physical-device Activity confirmation was claimed. The prior Phase 7 device
journeys remain separate evidence, and this preview APK cannot satisfy
HARD-008's exact production-AAB Play install.

## 2026-09-21 GO-campaign feasibility recheck

The Google-authenticated QA-gym owner searched the production check-in screen
for a known fictional Iron Box member's phone. The screen returned **“No
member of this gym matched.”** This is a live cross-gym UI read refusal, not
the reverse-direction direct API mutation proof or the checked-in A–D suite.
No visit was submitted from that search.

A read-only fixture audit found why mutation-complete A–D cannot currently be
made repeatable and exactly cleaned up on the linked shared project. The
second gym's owner signs in through Google; there is no checked-in Playwright
credential or safe storage-state fixture. More importantly, attendance,
follow-up, payment and add-on journeys create immutable audit/financial history
with tenant foreign keys. Browser requests cannot share a rollback transaction,
and deleting that history would violate INT-001/003. A second permanent
controlled fixture with explicitly retained audit rows would require a new
contract decision; it would not meet the current exact-cleanup contract.
HARD-003 remains Partial despite the bounded live positive/negative checks.

The restore preflight found `supabase` CLI available, but no local
`pg_dump`, `pg_restore`, `initdb`, `psql` or running PostgreSQL server. Docker's
engine was unavailable. The current free Cloud project has no listed backups
and PITR is off. No dump, local restore, cloud restore or mutation was attempted.
A future protected logical backup would still not prove Auth configuration,
external R2 objects or the required disposable-target cloud/PITR restore.
HARD-007 remains Partial/External.

Read-only inspection of the authenticated Google Play Console account
`7649203845150858113` showed exactly three existing apps—FitAi, FitAi: AI
Workout & Diet Plan, and Flirt Genie—and no Gymloop app record. No app was
created, declaration accepted, bundle uploaded or release submitted in this
check. HARD-008 remains Partial/External despite the signed AAB on disk.

## 2026-09-21 PAY-012 manual-only payment critic

The owner excluded in-app gateway collection from the initial release: gyms
collect cash, UPI, card or bank transfer outside Gymloop, and authenticated
staff record the resulting payment. ADR-146 and PAY-012 freeze that scope.
The web payment and add-on request schemas now reject `razorpay` in addition
to the existing route/RPC and database refusals; no provider charge,
credential-capture or webhook path was activated. Existing desk navigation
and receipt behavior were preserved.

Tests were committed before the implementation (`7c160fb` after the spec
commit `fe51bdd`; implementation `71345fe`). The focused implementation
run passed 105/105 web tests across manual-only, holdout wrapper, payment
and add-on routes; shared and web typechecks and changed-file lint passed.
A fresh-context Sol critic returned **GO for the PAY-012 manual-only payment
boundary** with no blocking findings, independently passing 164/164 focused
web tests, 135/135 independent web holdout checks and web typecheck. The
critic inspected relevant SQL suites but did not run Cloud pgTAP in this
round. This is a scoped GO, **not** Phase 8 customer-launch GO; unrelated
HARD gates and the owner-led visual gate remain open.

## 2026-09-22 shared-database pilot architecture checkpoint

At repository `40b3c9a`, the linked project was positively identified as
`pecxrpskmfeuyzngvewq`. A read-only `supabase db query --linked` succeeded
through the CLI's temporary-login path. Three existing rollback-wrapped visible
pgTAP files then ran on that project through the repository's `splice.py`
counter check: `02_tenancy_rls` **36/36**, `04_contract_meta` **29/29**, and
`05_membership_money_rls` **136/136**, all with zero failures (201 assertions
total). This rechecks tenant read/write isolation, policy/index metadata and
membership/money boundaries on the current schema; it does not replace the
independent holdout suite or the missing browser A–D journeys. The tests left
no fixture rows because each file ended in `ROLLBACK`.

A read-only comparison of `supabase_migrations.schema_migrations` with the
tracked migration filenames found **71 local / 71 applied**, no missing or
unexpected versions, latest `20260918103000`. Fresh Cloud-generated database
types matched the committed generated file after the same comment/blank-line
normalization used by CI. Thus the failed DB workflow did **not** leave a
pending schema migration, but the workflow itself is still red and must be
repaired before a future migration can ship.

Connection diagnosis remained inconclusive for the session pooler. Both
`supabase migration list --linked` and `supabase db push --linked --dry-run`
timed out even with `SUPABASE_DB_PASSWORD` unset, while the passwordless
Management-API-backed `db query --linked` succeeded. Refreshing the local
project link returned the same session-pooler host; TCP ports 5432 and 6543
were reachable and the project ban list was empty. A separate PostgreSQL
client timed out on the 5432 session pooler; its first 6543 attempt stopped at
certificate verification before authentication. A second **encrypted but
certificate-unverified diagnostic only**, matching Supabase's documented
`sslmode=require` behavior, reached the transaction pooler and received a
password-authentication rejection for the value currently in `.env.local`.
The value was neither printed nor recorded. This proves the local value is
not accepted by that pooler now; it does not prove GitHub's masked secret has
the same value. The failed DB run `35633578490` was retried once (attempt 2)
and again failed at `db push --linked` before applying anything. No migration,
password rotation, durable fixture, or destructive operation was performed.
The password/pooler path is still not valid for CI and needs credential repair
and a green rerun before the next migration.
The available in-app browser session redirected the project's Database Settings
page to Organizations with “You do not have access to this project,” so no
dashboard credential change was attempted. The final password-change action
requires owner handoff; do not infer that the browser's signed-in account is
the CLI-linked project owner.

The prior 10 × 50 rollback result and these focused checks support a bounded
multi-tenant **pilot architecture** assessment on one database. They do not
prove peak capacity, a full Phase 8 GO, privacy operations, recovery, alert
delivery, exact-AAB Play installation, or visual acceptance. Keep those gates
open rather than converting a 3–10-gym hypothesis into an unmeasured claim.

## 2026-09-22 read-only monitoring destination preflight

At 06:44:47 UTC, the authenticated Vercel CLI resolved identity `ogun01` to
project `ogun01s-projects/gymloop` (`prj_mteQVcRk0VT6NMeVA3HLmBjPZEAs`).
`vercel alerts --project prj_mteQVcRk0VT6NMeVA3HLmBjPZEAs --json`
returned no alert groups. `vercel alerts rules ls --project
prj_mteQVcRk0VT6NMeVA3HLmBjPZEAs --all --json` found only default rule
`ar_default` with `notifications: []`. Its owner/admin autosubscribe flags
are configuration metadata, not a verified recipient or delivered receipt.
The eight active GitHub workflows include no monitoring workflow; Supabase
still identifies the linked Gymloop project as `ACTIVE_HEALTHY`. No alert rule,
environment variable, event, recipient or production data was changed. The
exact remaining work and redacted receipt requirement are in
`docs/runbooks/operational-monitoring.md`. HARD-005 remains Partial/External.

`docs/evidence/phase8/pilot-coreloop.md` separately reconciles the existing
bounded two-gym deployed checks with PILOT-002/003. It adds no new mutation
proof: a repeatable second-owner browser fixture and durable synthetic-history
run remain to be executed under the now-frozen ADR-147 policy before checked-in
A–D journeys can be claimed.

The member-linked schema has now been inventoried in
`docs/planning/privacy-field-inventory.md` against migrations and generated
types. This is a technical candidate map, not the frozen export/erasure
allowlist or qualified legal review; no request, retention runner, Auth
revocation or destructive privacy operation ran. HARD-006 remains Blocked.

At 06:49 UTC, a read-only `supabase db query --linked` returned two gyms,
fifty members, 985 attendance rows, 38 payment rows and total database size
32,009,363 bytes. This is a baseline for fixture/recovery planning, not a
five-gym throughput measurement or a promise of Free-plan capacity.

## 2026-09-22 five-gym controlled-pilot rehearsal

The owner froze a five-gym first-customer target in
`docs/planning/five-gym-pilot-release.md` (`3e7eede`). Two independent authors
then added visible and holdout rollback suites in the test-only commit
`d6406e0`. Against the existing linked project, the visible five-gym suite
passed **40/40** assertions and the independently authored holdout passed
**29/29**, with zero failures. Each created five synthetic organizations,
branches and owner staff identities and fifty members per organization inside
one transaction; under five distinct owner-claim simulations, each could read
only its own fifty members and organization. Cross-tenant member updates
affected zero rows, deletes were refused, and foreign rows remained unchanged.
Both suites ended in `ROLLBACK`; independent postflight counts for their
synthetic organizations, branches, owners and members were all zero. The
holdout author reported only the verdict; its contents were not inspected by
the orchestrator or visible-test author. `check-pgtap-rollback` accepted all
91 pgTAP files after the addition.

Focused existing platform checks passed **33/33** structural and **43/43**
behavioral pgTAP assertions on the linked project. The affected web platform
route/page tests passed **17/17** from `apps/web`. These are additional
onboarding and status-contract checks, not proof of a five-gym live onboarding
journey. Read-only project totals remain **two gyms, two branches and fifty
members**; both gyms have settings and linked active owners. No five real
customers were created or claimed. A real owner still needs an independent
identity and authorized onboarding for each pilot gym.

`SUPABASE_DB_PASSWORD` is present in `.env.local`, but the current value was
rejected by the transaction pooler in the earlier encrypted diagnostic and
the session-pooler CLI migration path still times out. A proposed credential
synchronization was blocked by the execution environment before it ran: no
Supabase password or GitHub secret was changed. The test-only push triggered
[DB workflow `35684949391`](https://github.com/OGUN01/gymloop/actions/runs/35684949391):
rollback lint passed, but `migrate` failed at `supabase db push --linked`
with `Failed to connect` and the CLI's explicit `SUPABASE_DB_PASSWORD`
guidance. Schema drift, full pgTAP and seed dry-run were consequently skipped.
No new migration was in this push, and none was applied. PILOT-001 is a
bounded database rehearsal only.
PILOT-002 through PILOT-004 and the frozen HARD gates remain open.

### Atomic five-onboarding command rehearsal

The owner-facing acceptance was frozen as PILOT-006 in `a476b54`, distinct
from PILOT-001's direct tenant fixtures. The independent visible suite
`supabase/tests/63_phase8_five_gym_onboarding.sql` passed **27/27** against
the linked project: one synthetic super-admin called the actual
`public.onboard_gym` command five times with distinct request keys. The
transaction contained five trial organizations with distinct six-character
codes; exactly one settings row, default branch, zero-credit wallet, active
unlinked owner profile and keyed audit event per gym. Exact retries returned
their original results without duplicate children/audits, and changed-facts
reuse was refused for all five. A separately authored holdout passed **25/25**
after correcting its synthetic-auth and public-schema test bindings. Its
contents were not inspected by the orchestrator or visible author. Both
rehearsals ended in `ROLLBACK`; independent postflight found zero synthetic
organizations, child/audit rows and Auth/platform identities. The test-only
commit is `23570d3`; rollback lint accepted all 93 pgTAP files. No real gym,
Google owner link, activation or deployed-browser onboarding was claimed.

The owner asked to defer password rotation until all independent preparatory
work is complete, recorded in `docs/planning/current-campaign-goal.md`. That
does not waive the pre-customer credential/green-CI gate. DB workflow
[`35694552410`](https://github.com/OGUN01/gymloop/actions/runs/35694552410)
again failed in `migrate` before the full pgTAP job could run; rollback lint
passed, while schema drift, full pgTAP and seed dry-run were skipped. No
migration was included or applied. A read-only privacy audit also corrected
the member-linked `razorpay_mandates` classification in `docs/security.md`
(`e996ce8`), while
the unfrozen field map/non-null erasure blockers and legal review remain
open under HARD-006. The real-customer sequence is now in
`docs/runbooks/five-gym-pilot-onboarding.md` (`d3c186d`), with a stop line
before inviting any gym rather than fabricated permanent customers.

### Bounded QA-owner identity command rehearsal

The PILOT-007 SQL fixture contract was frozen in `e31e38f`, `f5200bc`,
`d9c6936`, `f343a87` and `7e56509`. The visible rollback-only test
`supabase/tests/64_phase8_pilot_owner_link.sql` was independently authored and
passed **22/22** focused assertions on the linked shared project after a
test-only hook-role and exact-replay fixture correction (`c12b970`). A separate
holdout author, without reading the visible suite or implementation, reported
**22/22** assertions passed from
`supabase/tests-holdout/64_phase8_pilot_qa_owner.sql` (`362c402`). **That
initial holdout pass is withdrawn:** a fresh Sol critic found that pgTAP
results produced inside procedural blocks were discarded, so the count could
hide failed assertions. The author repaired TAP emission in `f725470`, proved
one deliberately failing probe reports a failure, and reported 19/19 on the
focused rerun. The critic still found two underspecified holdout checks (exact
idempotency error and keyed audit); their correction is in progress. The
visible suite also needs to replace a self-comparison and derive RLS claims
from the hook result. Until both narrow corrections and another critic pass,
the PILOT-007 SQL evidence is **NO-GO**. Postflight found zero of the initial
synthetic Auth users and organizations. The orchestrator has not inspected
the holdout contents. No persistent QA owner, real Auth sign-in, browser A–D
journey or customer identity was created by these SQL rehearsals. GitHub DB
run `35697955080` additionally failed rollback lint on the initial holdout
file's trailing postflight statement and failed `migrate` on the existing
database credential; full pgTAP, schema drift and seed dry-run were skipped.
The corrected holdout file ends in `ROLLBACK`, but CI still needs a successful
rerun and a valid credential before this is complete release evidence.

Read-only Android preflight found the connected OnePlus DN2101 still reporting
Gymloop version `1.0.0` (`5`). The on-disk preview APK's signing certificate
SHA-256 is `AA923C583E2A9DE0B25446DA1917E640198E664687EEDF2B38750DB13333C863`,
matching the recorded production AAB upload certificate. This is useful
signing-continuity evidence, **not** a fresh fingerprint of the installed
package, an exact-AAB install, or proof that Play App Signing/internal-track
delivery worked. No APK was installed,
app data cleared or phone setting changed in this check. HARD-008 remains
Partial until the exact-artifact device/Play journey is run.

On 2026-09-22 a second read-only OnePlus DN2101 preflight queried the
installed `in.gymloop.mobile` package (`versionName=1.0.0`, `versionCode=5`),
pulled its installed base APK without reinstalling it, and ran Android SDK
build-tools 36.0.0 `apksigner verify --print-certs`. The installed APK SHA-256
was `D2E384BDECAC8C3E9C1D7F0D0FC45D35D8BF6968057267EB36266318CAA51AF8`,
byte-identical to the recorded v5 preview APK; its signing certificate SHA-256
was `AA923C583E2A9DE0B25446DA1917E640198E664687EEDF2B38750DB13333C863`,
the same upload certificate recorded for the v5 production AAB. This closes
the previously missing *installed-package fingerprint* check only. It is not
an install from that AAB or a Play internal track. No phone settings, app
session or product data were changed.

## External dependency index

| Dependency | HARD IDs | Current state | Owner and action | Evidence needed |
|---|---|---|---|---|
| Frozen 100 × 500 / 50,000-check-in load gate | HARD-004 | Unperformed; owner authorizes the current prelaunch shared project for bounded synthetic tests, not a claim that the frozen scale was measured | Run only a recorded, bounded same-project preflight with exact synthetic IDs and non-destructive cleanup policy; defer or explicitly re-decide the full gate before launch | Test plan, project/ref, request mix and concurrency, raw results, resource telemetry, fixture disposition and independent tenant-isolation postflight |
| Monitoring destination and alert route | HARD-005 | External; no delivery proof | Production owner chooses/configures a real destination and escalation owner | Redacted event id, alert receipt, thresholds, retention and ownership |
| DPDP/DPA and breach-notification legal review | HARD-006/007 | External; not approved | Production owner obtains qualified current legal/privacy review | Dated approval/decision naming durations, hold behavior, audiences, timing and channels |
| Supabase cloud backup/PITR restore | HARD-007 | External/unperformed | Project administrator runs approved disposable-target drill | Cloud operation id, source/distinct target, timings, validation and cleanup |
| Production API deployment and EAS environment | HARD-002/008 | **Resolved 2026-09-20**; public Vercel alias and EAS production public variables verified | Deployment owner keeps the public endpoint and environment current | Deployment and variable-name evidence in `docs/evidence/2026-09-20-phase8-production-release.md` |
| Production Android signing/keystore | HARD-002/008 | **Resolved 2026-09-20**; managed EAS credentials produced the signed AAB | Android release owner preserves EAS credential ownership and build provenance | Certificate fingerprint, EAS build id and AAB SHA-256 in the production release evidence |
| Google Play app, signing and track | HARD-008 | Existing personal developer account `Ductx` (account ID `7649203845150858113`) is accessible; Gymloop is not among its three apps. `in.gymloop.mobile` checked available 2026-09-21; form prepared but not submitted. No upload/publication claim. | Account holder reviews and truthfully certifies Play developer policy and U.S. export-law declarations before app creation, confirms this developer identity for Gymloop, then enrolls Play App Signing, uploads to an internal track and installs the exact artifact. | App/package id, policy declarations, Play artifact/version id, internal-track install, physical-device checklist and console status. A new personal-account app may also require the current closed-test production-access process. |
| Razorpay provider-signed webhook evidence | Gates 20/21; future online-payment release only (ADR-146) | Deferred and not applicable while all in-app gateway paths remain disabled; no provider proof claimed | Reopen only if the owner elects to enable online payments; freeze a provider-evidence contract first | Provider-produced signature/payload, verifier tests against independent evidence, deployment and money-path audit before any online-payment release. |
| Cloudflare edge rate-limit and Turnstile evidence | Gate 24; HARD-009 | External; no edge-control proof attached | Edge/security owner configures the actual production zone and tests the public/OTP abuse paths when provider credentials exist | Cloudflare rule/zone IDs, non-secret configuration capture, controlled allowed/blocked requests and alert/log evidence; then re-evaluate gate 24. |

These pre-launch security gaps are not discharged by any Phase 8 local test.
