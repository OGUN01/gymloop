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
