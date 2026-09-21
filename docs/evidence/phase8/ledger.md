# Phase 8 evidence ledger

Updated 2026-09-21. Status meanings: **Passed** has fetchable evidence for the
full stated requirement; **Partial** has real evidence but an acceptance part is
missing; **Blocked** cannot proceed safely until the named prerequisite exists;
**External** requires a real owner/provider/legal/cloud/store action. A local
mock or synthetic provider response never changes External to Passed.

| Requirement | Status | Commit/build, environment and time | Command or procedure and fetchable evidence | Blocker, owner, required evidence and next safe step |
|---|---|---|---|---|
| HARD-001 | **Partial** | Phase 7 closeout `d1888c6`; Phase 8 contract `c768dff`; repository, 2026-09-20 | Procedure: review each HARD row for status, identity, time, result, artifact and dependency. This ledger is the current artifact. | Owner: Phase 8 orchestrator. Complete only after every row links exact executed commands/procedures and results; keep skipped/blocked/external visible. |
| HARD-002 | **Passed** | Original contract/config `cdd99fb`/`674255e`; least-permission contract/config `94f058f`/`2252bdc`; version contract/config `d894ad5`/`7a31384`; CI `35530050420`; EAS build `146221dd-dab2-4ef1-a99b-61dc14be4675`, 2026-09-20 | Focused HARD-002 checks passed 5/5 and mobile typecheck passed; CI, holdout and test immutability were green. The production `STORE` build from `7a31384` is a managed-credential signed AAB for `in.gymloop.mobile` version `1.0.0` (`2`). Artifact, certificate and merged-permission evidence: `docs/evidence/2026-09-20-phase8-production-release.md`; AAB SHA-256 `129C5339A629C3AB2BFE937C7C304D44E4A3BEBEB1ED3CFCEB393F34A674C239`. | HARD-002's reviewable configuration, unique release version, test integration, least-privilege manifest and signed-AAB readiness proof are satisfied. Physical-device install and Play publication remain separately Partial/External under HARD-008. |
| HARD-003 | **Partial** | Test `6ef23cb`; credential tests/config `f6035dc`/`0505432`; role-home specs/fixes `9e234d2`, `2bd1050`, `12125cd`, `6f40a81`, `7a9fc74`, `731e25b`; CI `35507247973`; latest Vercel deployment `9h745WmLGeD3YeMBtMkgCrb54qdm`, 2026-09-21 | Local/CI accessibility passed 3/3. Production `https://gymloop-phi.vercel.app` is Ready in `bom1`; `/sign-in` returned 200. A production-targeted run had two green cases plus one cold-start member timeout; the narrow role-landing rerun then passed member/front desk/owner. Details: `docs/evidence/2026-09-20-phase8-production-release.md`. | Mutation-complete journeys A–D and a true second-gym cross-tenant browser fixture remain blocked pending a disposable/non-production environment and second tenant identity; read-only production smoke is not substituted for that automation. Owner: web acceptance/infrastructure owner. |
| HARD-004 | **Partial / External execution** | Red visible/blind contracts from `552313a` and `47ad1f7`, frozen interface through `20e2fff`, final implementation `ee0bc4d`; repository, 2026-09-20 | `pnpm exec vitest run scripts/__tests__/phase8-load-safety.test.ts supabase/tests-holdout/phase8-load-safety.holdout.test.ts` passed 16/16. Fresh Sol critic returned GO after direct-k6 parity review. `scripts/phase8-load-safety.mjs`, `tests/load/phase8-morning-checkin.js`, and `docs/runbooks/load-testing.md` provide the fail-closed preflight, exact 100 × 500 morning spike, approved p95 threshold, unique event keys, real read/mutation denial probes and credential-free evidence boundary. No k6/network/database command was run. | Owner: infrastructure owner. Provision and positively verify a separate non-production Supabase project, deployed API and synthetic 100 × 500 fixture, then execute the runbook and attach raw-result checksum and measured evidence. Production remains refused. |
| HARD-005 | **Partial / External destination** | Interface `6edba6d`; visible/holdout red tests `c114182`/`6797571`; contract corrections `cf5afc9`/`154a4c8`; implementation `12beeca`; production-call-site tests `658525f` and implementation `bdfc81d`; repository, 2026-09-20/21 | Adapter checks passed 7/7. The API 500 path now emits one minimal event; independent visible/holdout call-site checks passed 3/3 each, and web typecheck/lint passed. `docs/runbooks/operational-monitoring.md` names proposed thresholds, role ownership, escalation and retention, explicitly unconfigured. No production provider delivery was observed. | Owner: production owner. Configure a real monitoring destination and alert route. Evidence still required: provider event id, alert receipt, actual rules/retention and named escalation owner. Until provider proof exists, external monitoring remains External. |
| HARD-006 | **Blocked / External legal** | Read-only implementation audit completed 2026-09-20; no runner or execution evidence attached | Governing durations and broad blank/delete/hold categories are in `docs/security.md`, but the contract does not classify personal columns, define clocks for several retention rows, cover `razorpay_mandates`, define export wire content, or distinguish category-wide retention from case-specific legal holds. `members.full_name` and `phone` are also non-null today, so truthful erasure cannot be added without a schema/product decision. No destructive command was run. | Owner: product/privacy owner freezes those decisions; production owner obtains qualified legal review. Then independent visible/holdout authors specify the member-derived export/erasure RPCs and service-only retention runner before CI-only migration work starts. Local tests cannot satisfy legal sign-off. |
| HARD-007 | **Partial / External restore** | Runbooks committed in `055e83c` on 2026-09-20; no cloud operation id | Procedures: `docs/runbooks/incident-and-breach.md` and `docs/runbooks/backup-and-restore.md`. They define roles, checkpoints, evidence, safe read-only review and the destructive approval boundary. No tabletop or Supabase cloud PITR restore was performed. | Owner: production owner/platform administrator; Privacy Lead for legal notification confirmation. Evidence: role/contact roster, tabletop record, current legal/DPA decision, backup-control capture and disposable-target cloud restore operation with validation/cleanup. Gate 29 remains external/unperformed. |
| HARD-008 | **Partial / External exact-artifact device and Play** | Current-source production EAS build `7d603487-57a7-4f71-9413-3b60b6ca6302` from `acd7b44d04044db11019f2552b66a15414cbf422`, completed 2026-09-21 07:04:46 UTC; prior v2 build/evidence in `docs/evidence/2026-09-20-phase8-production-release.md` | Public HTTPS web/API and EAS production public-variable names are configured. Managed-credential `STORE` AAB for `in.gymloop.mobile` version `1.0.0` (`5`) downloaded to `dist/releases/gymloop-1.0.0-5-production-acd7b44.aab` (95,189,796 bytes), SHA-256 `46F4C1F45D3F98A29051C1F6F3C3911E5991E9CEF07DB0A1445FC1D8D12C8AB9`; `jarsigner -verify` said `jar verified`, and upload certificate SHA-256 is `AA:92:3C:58:3E:2A:9D:E0:B2:54:46:DA:19:17:E6:40:19:8E:66:46:87:EE:DF:2B:38:75:0D:B1:33:33:C8:63`. CI, holdout and immutability for source commit passed. Baseline debug-device journey remains `docs/evidence/2026-09-20-phase7-android-device.md`. | No exact-AAB physical smoke or Play upload occurred. Gymloop has no Play app record yet; account-holder policy/export declarations, Play App Signing and internal-track install precede the checklist. A matching preview APK may verify product behavior, not discharge exact-AAB/Play proof. Owner: Play account holder and release tester. |
| HARD-009 | **Partial** | This ledger and production release evidence, 2026-09-20 | Each unresolved row names its real dependency, owner role, evidence and next safe step. No provider, legal, store, backup, monitoring or device success is synthesized. | Owner: Phase 8 orchestrator keeps this current. Remaining external items: non-production load project, monitoring destination, legal/DPA sign-off, Supabase restore control/drill, exact-AAB device smoke and Play account/upload. Attach real evidence before changing any to Passed. |
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
the owner-deferred staging environment is still needed for that proof.

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

## External dependency index

| Dependency | HARD IDs | Current state | Owner and action | Evidence needed |
|---|---|---|---|---|
| Separate non-production Supabase project | HARD-004 | External; not identified | Infrastructure owner provisions/authorizes it and records its distinct project reference | Safety preflight, non-production credentials source, k6 command/raw result |
| Monitoring destination and alert route | HARD-005 | External; no delivery proof | Production owner chooses/configures a real destination and escalation owner | Redacted event id, alert receipt, thresholds, retention and ownership |
| DPDP/DPA and breach-notification legal review | HARD-006/007 | External; not approved | Production owner obtains qualified current legal/privacy review | Dated approval/decision naming durations, hold behavior, audiences, timing and channels |
| Supabase cloud backup/PITR restore | HARD-007 | External/unperformed | Project administrator runs approved disposable-target drill | Cloud operation id, source/distinct target, timings, validation and cleanup |
| Production API deployment and EAS environment | HARD-002/008 | **Resolved 2026-09-20**; public Vercel alias and EAS production public variables verified | Deployment owner keeps the public endpoint and environment current | Deployment and variable-name evidence in `docs/evidence/2026-09-20-phase8-production-release.md` |
| Production Android signing/keystore | HARD-002/008 | **Resolved 2026-09-20**; managed EAS credentials produced the signed AAB | Android release owner preserves EAS credential ownership and build provenance | Certificate fingerprint, EAS build id and AAB SHA-256 in the production release evidence |
| Google Play app, signing and track | HARD-008 | Existing personal developer account `Ductx` (account ID `7649203845150858113`) is accessible; Gymloop is not among its three apps. `in.gymloop.mobile` checked available 2026-09-21; form prepared but not submitted. No upload/publication claim. | Account holder reviews and truthfully certifies Play developer policy and U.S. export-law declarations before app creation, confirms this developer identity for Gymloop, then enrolls Play App Signing, uploads to an internal track and installs the exact artifact. | App/package id, policy declarations, Play artifact/version id, internal-track install, physical-device checklist and console status. A new personal-account app may also require the current closed-test production-access process. |
| Razorpay provider-signed webhook evidence | Gates 20/21; HARD-009 | External; no provider-signed payload or credential verified | Payments owner obtains a real test-mode payload and signature from Razorpay; freeze a provider-evidence contract before implementation | Captured provider-produced signature/payload reference, verifier tests against that independent evidence, deployment and money-path audit; then re-evaluate gates 20/21. |
| Cloudflare edge rate-limit and Turnstile evidence | Gate 24; HARD-009 | External; no edge-control proof attached | Edge/security owner configures the actual production zone and tests the public/OTP abuse paths when provider credentials exist | Cloudflare rule/zone IDs, non-secret configuration capture, controlled allowed/blocked requests and alert/log evidence; then re-evaluate gate 24. |

These pre-launch security gaps are not discharged by any Phase 8 local test.
