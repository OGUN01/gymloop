# Five-gym controlled-pilot acceptance

**Owner direction, 2026-09-22.** Prepare Gymloop for five independent gyms to
use the existing shared Supabase project. This is a controlled first-customer
target, not a claim that five real gyms have been onboarded or that the free
plan has measured capacity for thousands. No gym receives its own database.
The owner handles the separate visual redesign; this document does not waive
any frozen Phase 8 HARD gate or enable Razorpay.

## Data and identity boundary

- **PILOT-001** WHEN a prelaunch five-gym database rehearsal runs, THE SYSTEM
  SHALL create five synthetic tenant/branch/owner fixtures with fifty members
  per tenant inside one transaction; under each distinct authenticated owner
  claim it SHALL reveal exactly that owner's fifty members and one organization,
  reveal no foreign member by id, and refuse cross-tenant update/delete without
  changing the foreign row. The rehearsal SHALL end in `ROLLBACK`, and an
  independent postflight SHALL find zero fixture rows. This proves a bounded
  RLS/relationship property, not browser authentication or throughput.
- **PILOT-002** WHEN two distinct gym owners use the deployed application, THE
  SYSTEM SHALL show each only their gym's members, payments, add-ons, messages
  and metrics; direct foreign reads and mutations SHALL fail with no side
  effects. The exact sessions, tenant ids and denial results SHALL be recorded.
  Existing 2026-09-21 evidence covers several read and check-in refusals, not
  a repeatable mutation-complete acceptance suite.
- **PILOT-006** WHEN one verified super admin submits five distinct gym
  onboarding requests through `public.onboard_gym` in a prelaunch transaction,
  THE SYSTEM SHALL create five distinct trial organizations with unique
  six-character codes, one settings row, one default branch, one zero-credit
  wallet, one active unlinked owner profile and one keyed onboarding audit
  event per gym. An exact replay of each request SHALL return its original
  result without a second child or audit row; a reused key with changed facts
  SHALL be refused. This rehearsal SHALL end in `ROLLBACK` and an independent
  postflight SHALL find no synthetic gym, child, audit or Auth identity. It
  proves the atomic database command at five-gym scale, not Google owner
  linking, activation, a deployed browser journey or customer onboarding.
- **PILOT-007** WHEN the controlled two-gym browser acceptance is prepared on
  the existing shared project, THE SYSTEM SHALL use an independently signed-in
  synthetic QA owner whose Auth user is linked through the authenticated
  platform owner-link command to an unlinked QA-gym owner profile. The existing
  Google QA owner and Iron Box identities SHALL remain unchanged. The test
  SHALL verify the new owner's fresh tenant/role/staff claims and the owner-link
  audit event before any business write. Its named synthetic attendance,
  follow-up, manual-payment, add-on and audit history SHALL be retained rather
  than deleted to make the test appear clean. The test identity SHALL be
  deactivated and its sessions revoked after the one controlled acceptance;
  fresh sign-in SHALL have no Gymloop access. No mutation-complete A–D run
  SHALL be scheduled in CI against this shared project (ADR-147).

  **Frozen owner-link interface for independent tests:** after a separately
  created Auth user and an unlinked active `gym_owner` row in the QA tenant,
  a verified `super_admin` calls
  `public.link_gym_owner(p_tenant_id uuid, p_owner_staff_id uuid,
  p_expected_user_id uuid, p_owner_email text, p_request_key uuid) -> jsonb`.
  For first link, `p_expected_user_id` is null. The returned object has exact
  `tenantId`, `ownerStaffId`, `userId`, `ownerAccessPending=false`; one
  `staff.owner_linked` audit row is written for the request key. Exact replay
  returns the prior result without another link/audit; changed-facts replay
  is refused. The deployed HTTP adapter is
  `POST /api/platform/gyms/{tenantId}/owner-link` with JSON body
  `{ownerStaffId,expectedUserId,ownerEmail,requestKey}` and the ordinary
  `{ok:true,data}` success envelope. The test-only Auth user is created with
  no Gymloop claims; no role or tenant is assigned by the client.

  **Rollback-only SQL fixture contract for independent pgTAP authors:** begin
  one transaction, use `SET LOCAL ROLE postgres` and `SET LOCAL search_path =
  extensions, public`, and insert distinct synthetic `auth.users(id, email)`
  rows for the platform actor and target owner. The two columns are sufficient
  for this database-command test; this does not issue a real Auth session. Insert
  `public.platform_users(user_id, role, full_name, email, is_active)` for the
  platform actor with `role='super_admin'` and `is_active=true`. Set the local
  `request.jwt.claims` JSON to that actor's `sub`, `role='authenticated'`, and
  `app_role='super_admin'`, then `SET LOCAL ROLE authenticated`. Call
  `public.onboard_gym(p_request_key uuid, p_name text, p_timezone text,
  p_currency text, p_preset public.gym_preset, p_branch_name text,
  p_owner_name text, p_owner_email text)` using distinct synthetic values,
  `Asia/Kolkata`, `INR`, and `premium_studio`. Its JSON result supplies
  `organization.tenantId` and `ownerStaffId`; the latter identifies the active,
  unlinked owner row. Supply the target owner's exact synthetic Auth email to
  `public.link_gym_owner` as specified above. Assert the resulting owner link,
  one keyed audit and replay/refusal. The linked Management API SQL session
  is `postgres`, which has hook execute privilege but cannot `SET ROLE` to
  `supabase_auth_admin`; switch back to `SET LOCAL ROLE postgres` before each
  **test-only** hook invocation, then return to `authenticated` before RLS or
  platform-command assertions. Production Auth calls this hook through its
  `supabase_auth_admin` role, not through this SQL fixture. Obtain fresh claims
  by calling
  `app.custom_access_token_hook(jsonb_build_object('user_id', owner_user_id,
  'claims', jsonb_build_object('sub', owner_user_id, 'role', 'authenticated')))`:
  the returned `claims` must include `app_role='gym_owner'`, that tenant id,
  and that staff id. A second synthetic gym made through `onboard_gym` supplies
  the foreign-row denial target. For an owner RLS assertion, set local
  `request.jwt.claims` to the returned `claims` and remain `authenticated`;
  reset to the platform actor's claims and assert that a direct
  `UPDATE public.staff SET is_active=false` for the linked owner is refused
  with `GL049`. Retire that exact row only through
  `public.deactivate_gym_owner(tenant_id, owner_staff_id,
  expected_user_id, request_key)` as the authenticated super-admin, then
  verify the keyed platform audit and zero sessions. Switch to `postgres`
  for the fresh test-only hook invocation; it must then omit
  Gymloop role/tenant/staff claims. End in `ROLLBACK`
  and assert postflight absence of all synthetic IDs. This SQL fixture validates
  the command/claim/RLS contract only; the deployed acceptance must separately
  use real Auth sessions, never forged JWT claims or service-role browser access.

  **Frozen deployed owner-fixture protocol (manual-only, one run):** the
  checked-in browser test must fail before any write unless
  `PILOT_SHARED_PROJECT_ACCEPTANCE=ONE_SHARED_PRELAUNCH_PROJECT`,
  `SUPABASE_PROJECT_REF=pecxrpskmfeuyzngvewq`, the Supabase URL is exactly
  `https://pecxrpskmfeuyzngvewq.supabase.co`, and the browser base origin is
  exactly `https://gymloop-phi.vercel.app`. The opt-in is read only through
  `packages/shared/src/config/env.ts`, never `process.env` in a test file.
  Its narrow exported `pilotAcceptanceEnv()` returns
  `{PILOT_SHARED_PROJECT_ACCEPTANCE: 'ONE_SHARED_PRELAUNCH_PROJECT'}` after
  literal validation; the runner combines this with existing `clientEnv()`,
  `serverEnv()` and `playwrightEnv()` rather than duplicating secret parsing.
  The runner generates one high-entropy password in memory and one unique
  `@gymloop.test` synthetic email; neither secret nor a token is logged or
  placed in a browser URL, evidence document, screenshot, or repository file.
  A server-side-only Supabase Auth Admin call creates and confirms that user
  with no Gymloop claims. A **real** password-authenticated super-admin session
  inserts one active unlinked `gym_owner` staff profile into existing QA gym
  `7eb2f564-0c3b-49b6-8104-1902241a5955` through ordinary tenant-aware
  PostgREST, then submits the deployed `POST /api/platform/gyms/{tenantId}/owner-link`
  adapter from its cookie-authenticated browser context. The request uses the
  newly returned staff id, null expected user id, exact synthetic Auth email,
  and a fresh UUID key. Service-role credentials may create the Auth fixture
  and perform read-only postflights on the test runner only; they never bind
  the staff row, call the owner-link command, or enter a browser context.

  Before business writes, a fresh independent QA-owner password sign-in must
  land on the QA gym and carry `gym_owner`, that tenant id and the newly linked
  staff id; the owner-link audit must contain the request key. A separately
  signed-in Iron Box owner (`owner@ironbox.example.com`, tenant
  `00000001-0000-4000-8000-000000000001`) must retain its own gym context.
  The exact existing synthetic QA member is
  `6211481a-30fc-4f7c-891b-c02d06e95c74`; one Iron member for denial is
  `00000005-0000-4000-8000-000000000013`. The member-detail denial is a
  direct caller-session Supabase PostgREST read of `members`, selecting only
  `id,tenant_id` with an exact member-id equality filter and `maybeSingle()`:
  each owner sees its own row and receives `null` without an error for the
  foreign row. This checks deployed RLS without inventing a page URL. Each
  sends one cross-gym `POST /api/check-in` with a fresh `clientEventId` and
  nonempty synthetic desk reason; both must receive `404/member_unknown`, and
  a read-only postflight must find zero attendance rows for those two keys.
  The exact user/staff/tenant IDs, request/event keys, HTTP status/envelope,
  two distinct session identities, audit id and zero-side-effect counts go to
  a redacted run ledger attached to the Playwright result as JSON; it must
  contain no password, key or token. After a successful run, commit only a
  human-readable redacted summary under `docs/evidence/phase8/`. If any
  preflight fails, do not create a fixture.

  In a `finally` path, the authenticated super-admin retires only the newly
  created linked owner through the PILOT-008 command; the identity trigger
  must revoke its Auth
  sessions. A read-only postflight must count zero `auth.sessions` for that
  exact user id through the correctly linked Supabase CLI Management API using
  `supabase db query --linked --output-format json` and parse `rows[0].n`;
  it must not use the DB password or interpolate unvalidated input. A
  test user and a fresh password sign-in must yield no Gymloop role, tenant or
  staff access. If retirement fails or the runner is interrupted, fail the
  run and use the manifest's exact IDs for a guarded operator recovery; never
  delete financial/audit rows or make a blanket cleanup query. Retain the
  synthetic Auth/staff/audit history, with the account inactive. This run
  proves the deployed second-owner boundary only; A–D money/follow-up/add-on
  journeys need their own frozen fixture and assertions before they are run.

- **PILOT-008** WHEN a non-preview super-admin retires one linked active gym
  owner, THE SYSTEM SHALL expose `public.deactivate_gym_owner(tenant_id,
  owner_staff_id, expected_user_id, request_key)` through the deployed
  `POST /api/platform/gyms/{tenantId}/owner-deactivation` adapter. The request
  body is exactly `{ownerStaffId,expectedUserId,requestKey}` with UUID values.
  The command SHALL lock and verify the tenant and exact `gym_owner` staff
  row, require that its current linked user matches the non-null expected
  user, set only that row's `is_active=false`, preserve its Auth/staff/audit
  history, and append one keyed `staff.owner_deactivated` audit event with
  actor and before/after state in the same transaction. The existing identity
  trigger SHALL revoke all sessions for that user. Exact keyed replay SHALL
  return the original result without another write or audit; changed facts
  under the key SHALL fail `GL068`, stale linked-user or inactive first-use
  SHALL fail as stale state, and unknown/foreign staff SHALL be not-found.
  Staff/gym owners, support, preview identities, anonymous and service-role
  callers SHALL have no execution grant. No direct authenticated staff update
  or service-role cleanup is an acceptance substitute. The deployed runner
  SHALL preflight all read-only assumptions before creating an Auth user,
  record exact non-secret fixture IDs immediately after each creation for
  guarded recovery, disable screenshots/traces/video, and assert one-row
  retirement, zero `auth.sessions`, and fresh unlinked claims.

- **PILOT-009 — deployed two-gym mutation-complete A–D acceptance (manual,
  one run).** AFTER PILOT-007 has completed its independently authenticated
  QA-owner acceptance and retirement, and after the PILOT-008 migration, web deployment, Auth hook, `pg_cron`
  `no-show-scan-nightly` job, and deployed `no-show-scan` Edge Function are
  verified at the shared-project production origins, one operator MAY execute
  this controlled acceptance. It is prerequisite evidence for PILOT-003, not
  CI, a load test, customer onboarding, or authority to mutate a real gym.
  It MUST use the same literal opt-in, project ref, Supabase URL, Vercel origin,
  redacted JSON ledger, and screenshot/trace/video prohibition as PILOT-007,
  with this multi-day credential exception: before creating the staged Auth
  user, generate one high-entropy password and escrow it under the opaque run
  marker in an operator-controlled encrypted OS credential store outside the
  repository. Only the operator/runner may retrieve it into memory for fresh
  sign-ins; it MUST NOT appear in repository or environment files, logs,
  evidence, URLs, or persistent browser state. Retain the encrypted entry for
  exact-ID recovery if interrupted; remove it only after owner deactivation,
  zero-session verification, and fresh no-access sign-in. Each resumed phase
  MUST authenticate the same Auth user anew and verify its QA tenant, staff,
  and role claims; it need not reuse a cookie or browser session across days.
  It MUST first confirm the current deployed commit
  contains the owner-deactivation command; a successful local build or a
  migration merely present in the repository is not a deployment prerequisite.

  **Feasibility gate, identity lifecycle, and bounded retained fixture.** The
  run manifest SHALL have one opaque run marker and contain only: the PILOT-007
  QA tenant `7eb2f564-0c3b-49b6-8104-1902241a5955`; one newly created,
  independently authenticated **PILOT-009 staged** `gym_owner` user and staff
  id; exactly one newly created QA branch member
  whose display name includes that marker, whose E.164 test phone has a
  deterministic numeric marker-derived suffix, and whose nullable email is
  either marked and non-deliverable or null;
  exactly one active QA membership for that member; its one selected active QA
  plan; one active QA `product` offer named with the marker; the resulting one
  no-show case, one follow-up, attendance row, **two** manual membership
  payments (the initial paid-period basis and the later renewal), add-on order,
  add-on payment and audit ids; and the existing Iron Box owner
  and foreign member `00000005-0000-4000-8000-000000000013` in tenant
  `00000001-0000-4000-8000-000000000001`. No second synthetic member, plan,
  offer, payment, order, case, or identity is permitted beyond those two
  named membership payments. The PILOT-007 owner is already retired in that
  protocol's `finally` path and MUST NOT be reused or reactivated. Before any
  Auth/staff/plan/business fixture write, verify the exact deployed targets,
  current migration and web adapter, independently authenticated super-admin
  and Iron sessions, existing QA/Iron tenants and members, QA branch,
  threshold and schedule, no colliding run marker, and owner-link/deactivation
  authority with read-only facts. After that preflight, a real
  password-authenticated super-admin creates the staged
  Auth user without Gymloop claims, creates exactly one active unlinked QA
  `gym_owner` staff row through ordinary QA-scoped PostgREST, and calls the
  deployed owner-link adapter with that row id, the staged email, null expected
  user id, and a fresh request key. It then verifies the returned owner-link
  audit and a fresh staged-owner sign-in with exactly its QA tenant/staff/
  `gym_owner` claims. This is the PILOT-007 link protocol applied to a distinct
  manifest identity, not a relaxation of its retirement rule. The QA member has no attendance before the scan,
  no approved pause, and a membership with a verified paid period before it is
  eligible for no-show evaluation. The selected plan MUST already be active,
  QA-scoped, INR, positive-price representable by the deployed
  `amountRupees` codec with price exactly `12500` paise, and have a recorded
  duration of at least 14 QA-local calendar days when the threshold is 7.
  Its price and duration
  are captured as immutable run facts. The product is quantity one, INR, `pricePaise`
  exactly `12500`, positive stock exactly one, complete nonblank disclosure
  and cancellation terms, no trainer/session facts, and a captured
  `quoteVersion`. The membership payment and product price are intentionally
  separate facts: the former proves renewal and receipt behavior and the
  latter proves the add-on atomic money path. **The present QA tenant has zero
  plans, so PILOT-009 is not runnable until the following single owner-RLS
  fixture setup is separately verified.** In the staged owner's ordinary
  caller-scoped PostgREST session, create exactly one marked QA plan with
  `{tenant_id:<QA tenant>,name:<marked name>,description:<nonblank>,
  duration_days:<at least 14 when threshold is 7>,price_paise:12500,currency:'INR',
  gst_rate_bp:0,max_freeze_days:0,is_active:true,sort_order:0}` and record its
  returned id, price, duration and tenant. This is an authorized catalogue
  write under RLS, not a service-role/SQL insert and not a direct insert or
  update of a paid membership period. If this exact plan creation cannot be
  independently verified under the staged owner's claims, stop before member
  creation and leave PILOT-009 blocked.

  Fixture creation SHALL use only the linked staged QA owner's ordinary
  cookie-authenticated deployed application/PostgREST session, never forged
  claims or a service-role browser. The runner records each returned id before
  advancing. It creates the member through `POST /api/members` as the native
  form fields `full_name`, `phone`, `email`, `status=active`, `branch_id`, and
  `joined_on`; creates the membership through `POST /api/memberships` with
  the exact form fields `{memberId,planId,startsOn:<current QA-local ISO day>}`;
  and creates the product through `POST /api/add-ons` with exactly
  `{kind:'product',name:<marked name>,description:<nonblank>,pricePaise:'12500',
  validityDays:<positive integer>,cancellationTerms:<nonblank>,isActive:true,
  trainerStaffId:null,trainerQualification:null,sessionCount:null,
  stockQuantity:1}`. The one
  selected plan is read-only preflight evidence after its separately verified
  owner-RLS creation: its id, INR price and duration are recorded, and the run
  stops before member creation unless it meets the stated gate. There is no
  service-role plan seeding, direct SQL fixture, or
  direct insert/update of a membership period. The member, membership,
  payment, and follow-up routes accept native URL-encoded form bodies and
  return `303 Location` on both success and some validation failures. The
  runner SHALL capture the first response without auto-following, require a
  safe same-origin destination with no `?error` for success, follow it, and
  prove the exact write by caller-scoped read-back and before/after counts;
  the member success destination is `/members/{id}`, membership and payment
  use `/memberships/{memberId}`, and follow-up uses `/red-list`. A `303` with
  an error query is not success. The deliberate duplicate payment MUST have
  `?error=possible_duplicate` and no new payment, receipt, period, or audit.

  **Identity and isolation preflight.** Before fixture creation, independently
  sign in the staged QA owner and Iron Box owner; record distinct `sub`, `staff_id`,
  `tenant_id`, role and browser-session identities, with QA claims exactly
  `gym_owner` and the staged tenant/staff ids and Iron claims retaining the
  Iron tenant. Under each caller session, a direct PostgREST `members` read
  selecting only `id,tenant_id` and using an exact id plus `maybeSingle()` MUST
  reveal its own designated row and return `null` without error for the other
  row. This pre-write member check uses the existing QA member; immediately
  after creating the marked member, repeat mutual caller-scoped exact-id
  visibility before creating membership or taking payment. Before QA
  mutations that have an existing QA target id, the Iron session repeats the
  same command against that QA id with its own fresh event/idempotency key and
  MUST receive the route's ordinary not-found/forbidden refusal; a
  caller-session read-only postflight MUST show zero rows carrying that
  foreign key and no changed QA row. Do not send an Iron create-member,
  create-plan, or create-product request without a QA target: it could
  legitimately create an Iron row. For those, assert claim-derived QA
  ownership, marker absence from Iron, and caller-scoped read-back instead.
  In particular, `POST /api/check-in` to the QA member with
  `{memberId,reason,clientEventId}` MUST be `404/member_unknown` and leave no
  attendance row for that event. Cross-tenant attempts never use an owner-link,
  service role, SQL, a supplied tenant id, or a cleanup delete.

  **Paid-period staging (not an A–D assertion).** Immediately after the
  membership route succeeds, and before any no-show wait, the staged QA owner submits
  `POST /api/payments` with `{memberId,membershipId,amountRupees:'125.00',method:'cash',
  notes:'PILOT-009 initial paid period',idempotencyKey}`. It MUST create exactly
  one paid INR receipt with caller-staff attribution and grant exactly one
  initial period: `starts_on` is the current QA-local day, `ends_on` is that
  day plus the captured membership duration, and the membership is active.
  If the plan price cannot be represented by the deployed rupee input codec,
  if the payment does not cross one full period, or if any date/status differs,
  stop and retain the failed fixture; do not alter membership dates or status.
  The runner then waits for the scheduled scan on a QA-local calendar date
  whose difference from the paid-period start date D is greater than the
  configured threshold, with no attendance. With threshold 7, date arithmetic
  makes the first eligible scan D+8 at 06:30 IST; the second is earliest D+9
  at 06:30 IST. These are actual elapsed dates, not fabricated completed-day
  counts. A new paid membership cannot honestly demonstrate silent churn on
  the day it is sold.

  **A — absence detection.** Do not call
  `public.run_no_show_scan_all()`, `app.run_no_show_scan`, or the manual Edge
  Function as part of the run: each spans every gym. Instead, after the member
  preflight is durable, wait for the deployed `pg_cron` nightly execution and
  verify the actual successful scheduled execution and, through scoped
  read-only QA facts, that it opened exactly one case for
  the marked member, with `status=open`, QA-local `opened_on`, the recorded
  threshold, and no prior attendance. A second actual successful scheduled
  execution, earliest D+9 at 06:30 IST for the `0 1 * * *` UTC job, MUST
  leave the same single live case rather than open another. Record both
  execution IDs and timestamps, and prove the membership remains live through
  both scans. If missed executions exhaust the plan-duration margin, stop and
  retire via the exact-ID recovery path; never backdate or invoke a broad
  manual scan.

  **B — contact and return.** The staged QA owner then posts the native follow-up
  form to `POST /api/follow-ups` with exactly
  `{caseId,channel:'call',outcome:'will_return',notes:'PILOT-009 follow-up',
  nextAction:'Return visit',nextFollowUpAt:<future offset ISO instant>}`;
  `correctsFollowUpId` is omitted. Assert one append-only follow-up attributed to
  the QA staff id and a live `follow_up_due` case. Finally post
  `POST /api/check-in` as the staged QA owner with `{memberId,reason:'PILOT-009 assisted
  return',clientEventId}`. Assert one `attendance` row with source `front_desk`,
  the QA member and caller staff attribution; the same case is closed with a
  non-null return time; and its follow-up remains readable. This proves
  ATT-005/006 and NSH-003/004/005 without backdating an attendance row or
  manually inserting/modifying a case.

  **C — external-money renewal.** In a newly authenticated session for the
  same staged QA owner with reverified QA claims, submit the
  native payment form to `POST /api/payments` with `{memberId,membershipId,
  amountRupees:'125.00',method:'cash',
  notes:'PILOT-009 external renewal',idempotencyKey}`. Assert the second and
  only renewal payment is `paid`, INR and exactly the captured integer plan
  price in paise, has caller-staff attribution and a non-null Gymloop receipt
  number, and has no provider identifiers. Assert its arrival advances the
  already granted membership end date exactly once by the membership's captured
  `duration_days`, without changing `starts_on`; it must not be treated as the
  initial grant. Re-submit the byte-identical request only to assert the
  documented possible-duplicate outcome and no third payment, receipt, audit,
  or extension. `razorpay` is never sent and no provider charge, webhook, raw
  card data, or raw UPI credential is used.

  **D — manual add-on sale and fulfilment.** Submit JSON to
  `POST /api/add-on-orders` as the staged QA owner:
  `{memberId,productId,quantity:1,quoteVersion,trainerStaffId:null,
  initialStartsAt:null,initialEndsAt:null,method:'upi',reason:null,
  idempotencyKey}`. Assert `{ok:true,data}` identifies one order and one
  arrived INR `12500`-paise manual payment; the order freezes the selected
  quote/disclosure, is `paid` or `active` as returned by the command, and
  reduces the marked product stock from one to zero exactly once. Replay that
  exact body and require `replayed:true` with the same ids and no extra payment,
  order, stock effect, or financial audit. Complete only that returned order
  through `POST /api/add-on-orders/{orderId}/complete` with `{}` and assert
  `replayed:false` plus terminal `completed`; replay `{}` and require
  `replayed:true` with no further state or audit. This is a product fulfilment,
  not a PT session, discount, refund, coupon, or Razorpay journey.

  **Evidence, retirement, and recovery.** A final caller-scoped QA read SHALL
  enumerate exactly the marked member's single membership, case, follow-up,
  attendance, initial paid-period payment, manual renewal payment, add-on
  order/payment and relevant audit
  events; the Iron session SHALL enumerate none of those ids. The redacted
  ledger records opaque ids, HTTP statuses/envelopes, request/event keys only
  as non-reversible labels, count-before/count-after assertions, plan-duration
  snapshot, money as decimal paise strings, cron observation time, and all
  refusal results—never passwords, cookies, access tokens, phone/email, or
  raw keys. Commit only its human-readable redacted summary under
  `docs/evidence/phase8/` after success.

  In `finally`, the authenticated super-admin invokes the deployed PILOT-008
  owner-deactivation adapter only for the manifest's QA staff/user/tenant ids,
  then uses the correctly linked Supabase CLI Management API for read-only
  verification of zero sessions and performs a fresh password sign-in proving
  no Gymloop role, tenant, or staff claims. Retain every marked business,
  money, attendance, follow-up and audit row and the inactive Auth/staff
  history. If any preflight, cron observation, assertion, or retirement fails,
  stop immediately, mark the run failed, preserve the manifest and evidence,
  and use only its exact ids for guarded operator recovery; never delete rows,
  rerun a broad scan, or issue a blanket tenant cleanup.

## Usable core loop

- **PILOT-003** BEFORE first-customer access, independently authenticated
  owner/front-desk/member journeys SHALL prove check-in, silent-churn follow-up
  and return, external-money manual payment with receipt/renewal, and add-on
  purchase/fulfilment in the deployed app. A–D browser automation and a final
  Android install remain the HARD-003/HARD-008 exit evidence. No Razorpay charge
  or provider webhook is in this initial release (PAY-012).

## Operational release conditions

- **PILOT-004** BEFORE inviting the first real gym, the migration workflow
  SHALL be green with a verified current credential; a recoverable backup and
  restore procedure, privacy export/erasure with legal review, delivered alert
  route, and exact release-artifact Android acceptance SHALL have their actual
  evidence. Synthetic rows, a runbook alone, or an upgrade promise do not pass
  those gates. The owner-led visual acceptance remains separate and required.
- **PILOT-005** The 10 × 50 and five-gym rollback rehearsals are architectural
  evidence only. They SHALL NOT be described as a measured concurrent load or
  as HARD-004's frozen 100 × 500/50,000-check-in result. Capacity, storage and
  usage must be observed during the controlled rollout; an eventual paid-plan
  upgrade adds resources but cannot repair a tenant leak or missing operation.

Do not create five fictional persistent customer accounts to make the count
look complete. Real pilot gyms need their own authorized owner identities and
onboarding details; synthetic tests must remain identified as synthetic.
