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
  reset to the platform actor's claims before an authorized deactivation via
  `UPDATE public.staff SET is_active=false` for the linked row. Switch to
  `postgres` for the fresh test-only hook invocation; it must then omit
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
  `00000005-0000-4000-8000-000000000013`. Both owners must see only their
  own member and get a not-found response for the foreign member detail. Each
  sends one cross-gym `POST /api/check-in` with a fresh `clientEventId` and
  nonempty synthetic desk reason; both must receive `404/member_unknown`, and
  a read-only postflight must find zero attendance rows for those two keys.
  The exact user/staff/tenant IDs, request/event keys, HTTP status/envelope,
  two distinct session identities, audit id and zero-side-effect counts go to
  a redacted run ledger. If any preflight fails, do not create a fixture.

  In a `finally` path, the authenticated super-admin marks only the newly
  created staff row inactive; the identity trigger must revoke its Auth
  sessions. A read-only postflight must count zero `auth.sessions` for that
  test user and a fresh password sign-in must yield no Gymloop role, tenant or
  staff access. If retirement fails or the runner is interrupted, fail the
  run and use the manifest's exact IDs for a guarded operator recovery; never
  delete financial/audit rows or make a blanket cleanup query. Retain the
  synthetic Auth/staff/audit history, with the account inactive. This run
  proves the deployed second-owner boundary only; A–D money/follow-up/add-on
  journeys need their own frozen fixture and assertions before they are run.

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
