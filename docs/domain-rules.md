# Domain rules (EARS)

Every rule below traces to a bullet in the master build prompt §8. Each requirement gets a stable ID (`<CATEGORY>-<NNN>`) so gate 2 ("every requirement has ≥1 visible and ≥1 holdout test") is mechanically checkable once Phase 1+ writes tests against these IDs — reference the ID in the test name or description, don't restate the requirement text in the test.

Canonical status vocabularies referenced below are defined in `docs/data-model.md`. Do not invent a parallel vocabulary.

## Attendance and QR (ATT)

- **ATT-001** WHEN a member presents a QR code to check in THE SYSTEM SHALL verify the QR session is valid and the membership is active before recording attendance.
- **ATT-002** IF the QR session is expired or invalid THEN THE SYSTEM SHALL reject the check-in and SHALL NOT record attendance.
- **ATT-003** WHEN a gym uses `rotating_screen`, THE SYSTEM SHALL issue a hash-only, expiring QR session as before; WHEN it uses `printed_poster`, THE SYSTEM SHALL persist only a hash of one active, non-expiring code per branch, never plaintext. A random session id and dedicated server-only HMAC secret deterministically derive the printable code. The secret `POSTER_CODE_SECRET` is base64url-encoded with at least 32 decoded bytes and is accessed through a narrow validated server-only accessor. Neither the raw code nor the secret belongs in a database row, audit event, client bundle, or log.
- **ATT-004** WHEN a duplicate scan for the same member arrives inside a configurable de-duplication window THE SYSTEM SHALL reject the duplicate without discarding the original, legitimate attendance record.
- **ATT-005** WHEN staff perform an assisted front-desk check-in THE SYSTEM SHALL require the acting staff member's identity and a mandatory reason before recording the check-in.
- **ATT-006** IF an assisted check-in is submitted without a reason THEN THE SYSTEM SHALL reject the check-in.
- **ATT-007** WHILE a device is offline THE SYSTEM SHALL queue check-ins locally and, on reconnect, SHALL replay each queued check-in exactly once, writing an audit stamp recording the original offline timestamp and the replay time.
- **ATT-008** THE SYSTEM SHALL treat check-out as optional in v1 — a missing check-out SHALL NOT block any other system behavior (streaks, no-show detection, or billing).
- **ATT-009** THE SYSTEM SHALL default every gym's check-in mode to `rotating_screen` (a gym with no settings row behaves as `rotating_screen`); an owner or manager opts a gym into `printed_poster` (repair migration 20260925170000: a poster default broke rotating check-in for newly created gyms). One mode belongs to the gym, not a member-supplied or per-scan value.
- **ATT-010** WHEN an owner or manager requests a replacement poster, THE SYSTEM SHALL atomically revoke the previous active poster for that branch, create one new hash-only poster session and append a before/after audit entry attributing the authenticated actor. A replacement immediately invalidates the previous poster, including for queued/offline submissions. A front desk, trainer, member, impersonator, or another gym SHALL NOT replace the poster or change the gym's mode. Owner/manager confirmation is required in the UI. A branch cannot have two active posters, including under concurrent requests.
- **ATT-011** WHEN an owner or manager changes to `rotating_screen`, THE SYSTEM SHALL revoke all active posters in that gym in the same database transaction and audit the mode change; when switching to `printed_poster`, newly issued rotating codes SHALL cease to work, and an owner or manager may create the first poster. The database SHALL reject scans whose session mode differs from the gym's current mode. Rotating `POST /api/gate-code` keeps its existing lifetime, hash-only storage and front-office role boundary.
- **ATT-012** WHEN a member or staff submits a poster QR check-in, THE SYSTEM SHALL verify the session belongs to the claimed tenant and the member's branch, is the unrevoked active poster for that branch, and the member has a live membership, before inserting attendance. The same database enforcement SHALL govern direct authenticated attendance inserts and `member_mobile_check_in()`. Cross-tenant, cross-branch, revoked, wrong-mode and lapsed scans SHALL produce specific refusals and no attendance row. No RLS policy is weakened.
- **ATT-013** WHEN a poster scan arrives, THE SYSTEM SHALL use the trusted database arrival time in the branch timezone (falling back to the gym timezone) to enforce `organization_settings.opening_hours`. An empty object permits scanning at any time. A nonempty object maps `sun`–`sat` to arrays of `HH:MM-HH:MM` ranges; a missing or empty weekday closes that day. An end earlier than its start wraps past midnight and belongs to the day it starts, including its early-morning continuation on the next day. Opening is inclusive and closing exclusive. A closed scan is refused without attendance; the rotating screen retains its previous behaviour.
- **ATT-014** WHEN a poster code is scanned after the member has checked in during that same branch-local calendar day, THE SYSTEM SHALL refuse the attempt without attendance even when the configurable seconds-based deduplication window has passed. The per-tenant/member advisory lock serializes the day check and insert. Repeated `client_event_id` remains idempotent. Poster replay is judged on trusted arrival time; an offline timestamp may be retained for provenance but cannot backdate mode, validity, opening hours, membership, or the attendance day. Rotating replay and de-duplication stay unchanged.

## Streaks (STK)

- **STK-001** THE SYSTEM SHALL support three configurable streak rule types per gym: visit streak (consecutive planned workouts), weekly goal (e.g. N of M planned visits per week), and calendar streak (challenge periods only).
- **STK-002** WHEN a member has an approved pause or a configured rest day THE SYSTEM SHALL NOT count that day as a streak break.
- **STK-003** THE SYSTEM SHALL present streak status and missed days without shaming language — copy review is part of the Phase 7 design gauntlet, not optional polish.
- **STK-004** WHEN a member disables motivational notifications THE SYSTEM SHALL stop sending streak/motivation pushes to that member while continuing to compute and display their streak in-app.

## No-show detection (NSH)

- **NSH-001** THE SYSTEM SHALL run the no-show scan once per calendar day, in each gym's own configured timezone (not UTC, not the server's local time).
- **NSH-002** WHEN the no-show scan runs THE SYSTEM SHALL exclude members whose membership is `paused`, `frozen`, `expired`, or `cancelled` from red-list evaluation.
- **NSH-003** WHEN a member's absence crosses the gym's configured no-show threshold THE SYSTEM SHALL open exactly one no-show case in `open` status.
- **NSH-004** IF a member already has an open no-show case THEN THE SYSTEM SHALL NOT open a second case for the same member, on any subsequent scan run.
- **NSH-005** WHEN a member with an open no-show case checks in THE SYSTEM SHALL automatically transition the case to `returned` and then `closed`, preserving the case's full contact history rather than deleting it.
- **NSH-006** WHILE a no-show case is being contacted by one staff member THE SYSTEM SHALL prevent a second staff member from concurrently logging a call to the same case (no double-contact race).
- **NSH-007** THE SYSTEM SHALL treat every contact-log entry as append-only; a correction to a prior contact log SHALL be written as a new entry, never as an edit or delete of the original.

## Renewals and payments (PAY)

- **PAY-001** THE SYSTEM SHALL send renewal reminders at configurable day-offsets relative to membership expiry, defaulting to 14, 7 and 3 days **before** expiry, on the expiry date itself, and 3 days **after** expiry. Encoded in `RENEWAL_REMINDER_WINDOWS`, each window carrying an explicit `daysFromExpiry` on one axis: **negative = before expiry, 0 = the expiry date, positive = after**. So the windows are `-14, -7, -3, 0, +3` and this requirement's "+3" is literally `+3`.
- **PAY-002** THE SYSTEM SHALL send at most one reminder message per configured stage.
- **PAY-003** WHEN a membership's renewal payment is verified, OR the membership is cancelled, OR the member opts out of renewal messaging THEN THE SYSTEM SHALL stop sending further renewal reminders for that renewal cycle.
- **PAY-004** WHEN a renewal payment fails THE SYSTEM SHALL escalate on a path distinct from the no-response path (different message, different staff-facing signal).
- **PAY-005** THE SYSTEM SHALL NOT store raw card numbers or raw UPI credentials anywhere in the system.
- **PAY-006** WHEN a payment uses the `razorpay` method THE SYSTEM SHALL treat Razorpay as the sole source of truth for that payment's state. A manual-method `paid` row is instead an actor-attributed record that the gym collected money outside Gymloop; it does not claim provider settlement.
- **PAY-007** THE SYSTEM SHALL NOT treat a `payment_initiated`/`created`/`pending` record as `paid` under any circumstance.
- **PAY-008** WHEN a Razorpay payment would renew a membership THE SYSTEM SHALL extend it only after a webhook signature has been verified or a provider status response has been independently verified — never on client-reported success alone. This provider condition does not apply to a staff-recorded manual payment governed by PAY-011.
- **PAY-009** WHEN a duplicate webhook delivery for an already-processed event arrives THE SYSTEM SHALL process it idempotently, producing no additional state change or duplicate membership extension.
- **PAY-010** THE SYSTEM SHALL record refunds and reversals as separate records from the original payment, never by mutating the original payment row.
- **PAY-011** IF a gym has no payment gateway connected THEN THE SYSTEM SHALL remain fully functional for cash/UPI/card payments recorded by front desk, including staff attribution, a receipt, and a working renewal pipeline.
- **PAY-012** WHILE the initial release is manual-payment-only THE SYSTEM SHALL offer no in-app charge initiation, raw card/UPI credential capture, or provider webhook ingestion; authenticated desk writes SHALL reject the `razorpay` method. The gym may collect cash, UPI, card or bank-transfer funds using its own external process and then record the amount, method and actor in Gymloop under PAY-011. Latent provider enum values and tables do not enable the gateway.

## Money and time (MNY)

- **MNY-001** THE SYSTEM SHALL store every money amount as an integer number of paise, never as a floating-point number.
- **MNY-002** THE SYSTEM SHALL store an explicit currency code alongside every money amount.
- **MNY-003** THE SYSTEM SHALL apply one documented, tested rounding rule wherever a money amount is derived (discounts, proration, tax) — the rule itself lives in `docs/decisions.md` once Phase 5 picks it, but rounding SHALL NOT be implicit or ad hoc per call site.
- **MNY-004** THE SYSTEM SHALL evaluate every scheduled or date-boundary computation (no-show scans, reminders, streak resets) in the timezone of the gym the computation concerns, not in UTC or server-local time.
- **MNY-005** THE SYSTEM SHALL be tested across timezone date boundaries (midnight rollover, DST-adjacent regions if ever expanded beyond India) so a scan does not run twice or zero times around a boundary.

## Add-ons (ADD)

- **ADD-001** THE SYSTEM SHALL NOT pre-select any add-on (PT package, diet plan, product) in a purchase flow — the member SHALL make an affirmative choice.
- **ADD-002** WHEN a member views an add-on before purchase THE SYSTEM SHALL display its exact price, validity period, trainer qualification (for PT) or stock level (for products), and cancellation terms.
- **ADD-003** WHEN a member attempts to purchase a PT add-on THE SYSTEM SHALL check trainer availability before accepting payment, not after.
- **ADD-004** IF fulfilling an add-on order would take product stock or a trainer's session count below zero THEN THE SYSTEM SHALL reject the order.
- **ADD-005** WHEN real front-office staff accept an affirmatively selected, complete add-on offer THE SYSTEM SHALL serialize the request UUID and current quote, derive the tenant, seller, exact bigint money and inclusive gym-local validity, freeze the normalized request and disclosed terms, and commit the order, any manual payment, receipt, initial PT reservation, stock effect and audit as one transaction. An exact same-seller retry SHALL be read-only; a changed retry SHALL be `GL052 idempotency_conflict`; any failure SHALL consume nothing.
- **ADD-006** WHEN an add-on order is written THE SYSTEM SHALL keep its identity, seller, request, accepted disclosure, money, validity, payment, trainer and usage facts permanent; SHALL allow only pending→paid/cancelled, paid→active/cancelled/refunded and active→completed/refunded; and SHALL keep completed, cancelled and refunded terminal. A positive-price order SHALL link one arrived, unused, same-member, same-currency payment for the exact total, while a complimentary order SHALL require a reason and create no payment.
- **ADD-007** WHEN a trainer schedules or finishes PT THE SYSTEM SHALL require that exact assigned real trainer, an active unexpired and not-fully-returned order, a gym-local slot at or after the current command, remaining purchased capacity and no overlap. Session identity, slot and notes SHALL be permanent; only scheduled→completed/cancelled/no_show is legal; completion SHALL happen after the slot ends and consume once, while cancellation/no-show consumes nothing.
- **ADD-008** WHEN front office completes a service order THE SYSTEM SHALL complete only an active diet plan inside its inclusive sold window, replay an already-completed product or diet without a write, and refuse PT, nonterminal product, unavailable or terminal orders without inventing an expired state.
- **ADD-009** WHEN an owner or manager confirms an eligible manual add-on return THE SYSTEM SHALL verify the exact displayed amount, payment currency and reason, record a server completion time and make exact retries read-only. Requested/processing amounts SHALL reserve headroom but SHALL not count as returned cash. A completed full return SHALL move only eligible paid/active orders to refunded and cancel scheduled PT, without restocking or rewriting completed usage or terminal delivery history.
- **ADD-010** WHEN a complete member identity reads its own add-on order THE SYSTEM SHALL expose frozen sold terms and only the fixed completed-return projection; direct refund reads, pending attempts, internal actors, provider facts and another member's order SHALL remain unavailable. An active PT offer may reveal its assigned trainer's display name through the member-only name projection, beyond the offer's own trainer id, but no staff contact, auth or internal identity field.
- **ADD-011** WHEN staff or members use an add-on screen THE SYSTEM SHALL preserve exact decimal-text/BigInt money, distinguish current offers from frozen sold facts, show pending return requests separately from completed returned cash, hide role-inaccessible finance, preserve retry identity after uncertain responses and provide only actions valid for the role and state. Preview identities SHALL have reads and no mutation controls.
- **ADD-012** WHEN an add-on order changes THE SYSTEM SHALL append the exact actor-attributed financial audit event in the same transaction. Cash reconciliation SHALL use payment `paid_at`, completed returned cash SHALL use refund `processed_at`, complimentary orders SHALL contribute zero and legacy unknowns SHALL remain visibly unknown rather than being invented.

## Leads (LEAD)

- **LEAD-001** WHEN front office records an enquiry THE SYSTEM SHALL require a branch, name, E.164 phone and canonical source, derive the tenant and acting staff from the verified claim, and create the lead at `new` with the request key and normalized creation facts stored as durable evidence. An exact retry by the same actor SHALL return the original lead id and its current revision without a write; a key reused with different facts or a different actor SHALL fail `GL062`, and a supplied acting or evidence actor that is not the caller SHALL be refused.
- **LEAD-002** WHEN a lead changes stage THE SYSTEM SHALL allow only `new → contacted → trial_scheduled → trial_done → converted` and a move to `lost` from any nonterminal stage, refuse self-transitions, and keep `converted` and `lost` terminal. `trial_scheduled` and `trial_done` SHALL require `trial_at`; `lost` SHALL require a trimmed nonempty reason and every other stage SHALL forbid one; conversion fields SHALL be null outside `converted`. The database SHALL enforce the same rules on RPC and direct writes (illegal edges `GL059`, invalid facts `GL060`), keep identity, tenant, timestamps and creation/conversion evidence immutable, and rotate the database-owned `revision` uuid only on accepted material changes. Every mutation SHALL compare `expectedRevision`, and a miss on a visible lead SHALL answer HTTP 409 `stale_lead` with the current revision.
- **LEAD-003** WHEN a `trial_done` lead converts with no eligible same-gym member owning the normalized exact phone THE SYSTEM SHALL create the member and convert the lead in one transaction, with `joined_on` the accepting transaction's gym-local date, and create no membership, payment, attendance, consent, auth user or member code. WHEN an eligible same-gym member owns the phone THE SYSTEM SHALL refuse automatic creation with `GL061` and offer only an explicit link, carrying at most that member's id, name, phone and status; an unavailable (cancelled, blocked or erased) same-phone member SHALL answer a generic conflict with no member facts; and a cross-gym, wrong-phone or unknown member SHALL never be revealed, offered or linked. Eligible means status not `cancelled`/`blocked` and `erased_at` null.
- **LEAD-004** WHEN two conversion requests race or one is retried THE SYSTEM SHALL produce exactly one converted lead and at most one new member. The lead lock and the `(tenant_id, phone)` unique key SHALL serialize create-create, create-link and retries; the first successful conversion SHALL be final even for an authorized direct writer, and a converted lead SHALL never convert or relink. An exact retry SHALL replay the original immutable outcome after authorization and visibility, before revision or stage checks; a changed retry SHALL fail `GL062`; a lost race SHALL answer the stale conflict.
- **LEAD-005** WHEN front office opens or filters `/leads` THE SYSTEM SHALL read through `public.list_leads` under RLS in one SQL statement snapshot, support stage/source/assignee/branch/query filters, and return rows sorted `(updated_at desc, id desc)` behind a keyset cursor. `totalMatchingCount`, `pageResultCount`, `filteredStageCounts` and the rows SHALL derive from that one statement, every displayed count SHALL equal the rows the same filters return, and each count SHALL be a decimal integer string. Only front office — an authenticated, non-impersonating owner, manager or front desk — SHALL read or mutate lead data; trainers, members and preview identities SHALL see none.

## Identity navigation (NAV)

NAV-001–005 and NAV-007 are current. NAV-006 and NAV-008 are fixed Phase 6
requirements deferred to the platform slice, before commercial controls appear.

- **NAV-001** WHEN a verified session has one complete Gymloop identity shape THE SYSTEM SHALL route it to its role's working home; missing or contradictory claims SHALL route to not-linked and authorize no mutation, while a missing verified session SHALL reach sign-in.
- **NAV-002** THE SYSTEM SHALL use one pure identity classifier and one home selector across sign-in, root, not-linked, audience layouts and API session helpers: owners and managers `/dashboard`, front desk `/console/check-in`, trainers `/console`, members `/member`, platform users `/platform`, and previews `/console`.
- **NAV-003** WHILE a super admin previews a gym THE SYSTEM SHALL show a persistent red banner naming the gym and expiry, permit only ending that caller's exact preview session among product mutations, and SHALL infer no staff or member identity.
- **NAV-004** WHEN a preview ends THE SYSTEM SHALL update only the verified claim session, refresh Auth and return to platform; IF refresh fails THEN it SHALL clear the local session and return to sign-in.
- **NAV-005** THE SYSTEM SHALL expose a real member catalogue and own-order read surface plus a real platform fleet read surface, with truthful empty/error states; platform support SHALL receive no mutation controls.
- **NAV-006** WHEN a gym is pending approval, suspended, closed or has an expired or malformed trial THE SYSTEM SHALL issue no fresh gym-side identity; an explicitly requested super-admin preview remains permitted, and suspension/closure SHALL revoke linked staff/member refresh sessions.
- **NAV-007** WHEN the access-token hook resolves or fails to resolve an identity THE SYSTEM SHALL first remove stale Gymloop claim keys, preserve reserved Auth facts, and retain the established identity precedence and deterministic tenant choice.
- **NAV-008** THE SYSTEM SHALL allow only a non-preview super admin to change organization status, tier, trial or activation fields, so a suspended gym cannot reactivate itself during the residual token window.

## Data integrity (INT)

- **INT-001** THE SYSTEM SHALL NOT hard-delete financial records, attendance corrections, or follow-up history under any user-facing action.
- **INT-002** THE SYSTEM SHALL store marketing consent and service-communication consent as separately controlled flags — withdrawing one SHALL NOT affect the other.
- **INT-003** WHEN a financial record, an attendance correction, a follow-up record, a role change, or an impersonation session is created, modified, or ended THEN THE SYSTEM SHALL write an audit row recording actor, action, record type, record id, a before/after summary, and a timestamp.

## Data-quality alerts (DQA)

- **DQA-001** THE SYSTEM SHALL flag any membership row that has no expiry date set.
- **DQA-002** THE SYSTEM SHALL flag any payment row in `paid` status that carries no provider reference.
- **DQA-003** THE SYSTEM SHALL flag any attendance correction that carries no reason.
- **DQA-004** THE SYSTEM SHALL flag any product stock level that has gone negative.
- **DQA-005** THE SYSTEM SHALL flag any trainer double-booking (two sessions for the same trainer with overlapping times).

## Compliance — DPDP (DPD)

- **DPD-001** THE SYSTEM SHALL treat the gym (organization) as the Data Fiduciary and the platform as the Data Processor for member personal data — the gym's contract carries a DPA clause reflecting this.
- **DPD-002** THE SYSTEM SHALL record consent as versioned entries, each carrying a timestamp and a stated purpose.
- **DPD-003** THE SYSTEM SHALL keep marketing consent and service consent as independently withdrawable flags (see INT-002).
- **DPD-004** WHEN a member withdraws consent THE SYSTEM SHALL stop the corresponding category of communication without deleting the consent history itself.
- **DPD-005** WHEN a member requests a data export THE SYSTEM SHALL produce their personal data in a portable format.
- **DPD-006** WHEN a member requests erasure THE SYSTEM SHALL erase their personal data EXCEPT financial records under legal hold, which SHALL be retained per the applicable retention period and excluded from the erasure.
- **DPD-007** THE SYSTEM SHALL define a per-table retention policy (recorded in `docs/security.md` once Phase 1 finalizes the schema) and a breach-notification runbook.
- **DPD-008** THE SYSTEM SHALL support storing member photos but SHALL NOT store any government-issued ID in v1.

## Secure member invites (INV)

Frozen v2 batch-1 contract: `openspec/changes/member-invites/proposal.md`, including its v1.1, v1.2 and v1.3 amendments. These rules describe the approved contract; deployment and acceptance are tracked separately. The platform read-policy pair, command check order, committed refusal audit, replay and transport-specific refresh amendments apply to the requirements below.

- **INV-001 (issue).** WHEN real front-office staff (owner, manager, front desk; never an impersonation or preview identity) issue an invite for an invitable member of their own gym, THE SYSTEM SHALL create exactly one `pending` invite that stores only the lowercase-hex SHA-256 of the token, expires 48 hours after issue, names the issuing staff, and writes `member_invite.issued`. The raw token SHALL never be stored, logged, audited or returned by the database.
- **INV-002 (invitable).** IF the member is `cancelled` or `blocked`, erased, or the gym is not eligible THEN issue SHALL fail `GL075`; IF `email` is null, blank or implausible THEN `GL076`; IF the member already has a `user_id` THEN `GL077`. A member of another gym, an unknown id and a forbidden role SHALL be indistinguishable (`42501`). Trainers, members, platform users and impersonators SHALL be refused `42501`.
- **INV-003 (one pending; resend).** A member SHALL have at most one `pending` invite, enforced by the database under concurrent issues. Issuing while a pending invite exists (including an already-expired one) SHALL, in the same transaction, mark the old invite `superseded` with `closed_at`, write `member_invite.superseded`, and return its id as `superseded_invite_id`. A superseded token SHALL never redeem.
- **INV-004 (expiry).** An invite SHALL be redeemable only while `status = 'pending'` and `expires_at > statement_timestamp()`. Expiry is derived; no sweeper runs; `read_member_app_access` reports `invite_expired` for a pending row past expiry.
- **INV-005 (revoke).** WHEN front-office staff of the same gym revoke a `pending` invite THE SYSTEM SHALL mark it `revoked`, set `closed_at`/`closed_by_staff_id`, and write `member_invite.revoked`; a revoked token SHALL never redeem. Revoking a non-pending invite SHALL fail `GL079`; another gym's or an unknown invite SHALL fail `42501`.
- **INV-006 (abuse limits).** THE SYSTEM SHALL refuse an issue `GL078` when the gym has issued 100 invites in the rolling hour or the member has been issued 5 in the rolling 24 hours (counted from `member_invites.issued_at`). A refusal writes nothing.
- **INV-007 (redeem).** WHEN an authenticated caller presents the hash of a `pending`, unexpired invite THE SYSTEM SHALL, in one transaction that takes (in this order) a per-Auth-user advisory lock, the member row lock, then the invite row lock, set `members.user_id = auth.uid()` only if **all** hold: (a) the member is still bindable — status not `cancelled`/`blocked`, `erased_at` null, `user_id` null, gym eligible; (b) the caller's Auth user has `email_confirmed_at` and a `google` identity, and is a verified identity by the PROV-006a rule (`raw_app_meta_data->>'gymloop_provisioned' = 'true'`, or no identity with provider `email`); (c) that Google identity's `identity_data->>'email'` equals the member's *current* `email` (trimmed, case-insensitive; a null or blank member email never matches); (d) the caller's Auth user is bound to no row of `members`, `staff` or `platform_users`; and (e) the caller is not impersonating (otherwise `42501`). It then marks the invite `redeemed` (`redeemed_user_id`, `closed_at`), writes `member_invite.redeemed` and `member.linked`, and returns `outcome = 'linked'` with the gym's name. After a link, `app.custom_access_token_hook` SHALL mint `app_role = 'member'` claims for that user on the next token issue.
- **INV-008 (refusals are rows, with no oracle).** Redeem refusals SHALL be returned as rows with `outcome` ∈ {`invite_unavailable`, `email_mismatch`, `identity_unverified`, `account_already_linked`, `rate_limited`} and `gym_name` null. An unknown, expired, revoked, superseded or redeemed-by-someone-else token; a cancelled, blocked or erased member; an ineligible gym; and a member row that is already bound SHALL all return `invite_unavailable`. Check order: throttle, replay (INV-009), token, member/gym state (a), then identity (b → `identity_unverified`), then email (c → `email_mismatch`), then account bindings (d → `account_already_linked`). No outcome carries member facts or the address on file. Every refusal except `rate_limited` writes `member_invite.redeem_refused` (tenant when the token resolved, else null; `after = {outcome}`).
- **INV-009 (idempotent replay).** After the throttle check and before the pending check, WHEN the Auth user recorded as `redeemed_user_id` of a `redeemed` invite presents its token again and the member is still bound to that user THE SYSTEM SHALL return `already_linked_here` with no write; any other caller SHALL get `invite_unavailable`. An account bound to a *different* member is `account_already_linked` (INV-011), never `already_linked_here`.
- **INV-010 (redeem throttle).** WHEN an Auth user has 10 or more `member_invite.redeem_refused` rows in the rolling 15 minutes THE SYSTEM SHALL return `rate_limited` before evaluating the token and write nothing.
- **INV-011 (D1: one account, one member).** IF the caller's Auth user is already bound anywhere — any gym, as member, staff or platform user — THEN THE SYSTEM SHALL return `account_already_linked` and bind nothing. Two concurrent redemptions by one account SHALL produce at most one binding (the advisory lock).
- **INV-012 (peek).** `peek_member_invite` SHALL return the gym name only for a pending, unexpired invite whose member is invitable-status and whose gym is eligible, and zero rows otherwise. It SHALL be callable signed-out and SHALL return no other column. Hashes that are not 64 lowercase-hex characters raise `22023`.
- **INV-013 (binding guard).** THE SYSTEM SHALL refuse `GL074` any insert of a `members` row with a non-null `user_id`, and any update changing `user_id`, issued through `authenticated` or `anon` (every role, including owner), while the definer commands, migrations, seed and the service-role provisioning tool (no JWT subject) continue to work.
- **INV-014 (unlink).** WHEN a real gym owner or manager unlinks a bound member with a reason of 3–200 trimmed characters THE SYSTEM SHALL clear `user_id`, delete the former user's `auth.sessions` rows, and write `member.unlinked` carrying the reason. Unlinking an unbound member SHALL fail `GL080`; front desk, trainer, member, platform, impersonator and another gym SHALL fail `42501`; a missing or too-short reason SHALL fail `22023`. A pending invite is left untouched.
- **INV-015 (read model).** `read_member_app_access` SHALL be front-office-only (`42501` otherwise, including cross-gym) and return `linked` (with `linked_at` = the latest `member.linked` audit time, or null for operator-bound members), `invite_pending`, `invite_expired`, `not_invited`, or `unavailable` (member `cancelled`, `blocked` or erased). Precedence: `linked` (a non-null `user_id`), then `unavailable`, then the newest invite (`invite_pending` if `expires_at` is in the future, else `invite_expired`; a closed `redeemed`/`revoked`/`superseded` newest invite counts as none), else `not_invited`. A member with no email and no invite is `not_invited`.
- **INV-016 (audit).** Every issue, supersede, revoke, redeem, refusal, link and unlink SHALL write `audit_log` through `app.member_invite_audit`, attributed to `auth.uid()` and role, with no token and no token hash in `before`/`after`. Shapes: `issued` after `{member_id, expires_at, superseded_invite_id}`; `superseded` before `{status:'pending'}` after `{status:'superseded', replaced_by}`; `revoked` before `{status:'pending'}` after `{status:'revoked'}`; `redeemed` (role `member`) before `{status:'pending'}` after `{status:'redeemed', member_id}`; `member.linked` before `{user_linked:false}` after `{user_linked:true, via:'invite', invite_id}`; `member.unlinked` before `{user_linked:true}` after `{user_linked:false}` with `reason`. The operator provisioning tool writes no audit row (a recorded gap, ADR-176).
- **INV-017 (tenancy).** `member_invites` SHALL be invisible across tenants and to members and trainers; `authenticated` SHALL hold no insert, update or delete privilege; every RPC SHALL be executable by no role beyond those stated (`anon` only for peek). Existing schema meta-tests are amended for the new table, unique index and definer functions.
- **INV-018 (API).** The four routes SHALL behave as in "Web", validate through the shared schemas, return the typed envelope, set `Cache-Control: no-store`, identify the caller before reading the body, map SQLSTATEs by `Object.hasOwn` lookup, and never place a token, hash or address in a log, an error message or a URL query.
- **INV-019 (console panel).** The member page SHALL show an "App access" section to front-office roles (not trainers) with dot-plus-word state: **Linked** (since date; "Unlink account" for owner/manager, behind a confirm panel with a required reason), **Invite pending** (expires time; "Resend invite" and "Revoke"), **Invite expired** ("Send a new invite"), **Not invited** ("Send invite"; when the member has no email, a message with a link to edit the member; when cancelled/blocked/erased, an explanation, no action). After issuing, the panel SHALL show the link once with Copy, a QR code, a WhatsApp share link and a `mailto:` link, and say that resending replaces the link. In support preview the panel is read-only. States enumerated per gate 30: loading, not invited, pending, expired, linked, unavailable, permission denied (hidden), error, rate-limited, offline.
- **INV-020 (accept pages).** `/invite/[token]` SHALL show, for a valid token, the gym name, the DPDP notice (`inviteNotice`) with a link to `/privacy`, and one primary action — "Continue with Google" when signed out, "Link this account" when signed in unlinked; for any invalid token ONE generic unavailable state; for a signed-in already-linked account the D1 copy and a link home; for a signed-in unlinked account whose cookie/token is valid, the signed-in email is shown. `/invite/continue` SHALL read the cookie, show gym name, signed-in email, the notice and one "Link my membership" button, map `?result=` through `inviteRefusalMessage`, and offer "Use a different Google account" (sign out; the cookie is kept). With no cookie it SHALL show the unavailable state. A signed-out visit to `/invite/continue` SHALL redirect to the token landing if the cookie holds a token, else to `/sign-in`.
- **INV-021 (OAuth round trip).** THE SYSTEM SHALL carry the token across Google OAuth only in the `fitcruxx_invite` cookie (never in `redirectTo`, `next`, a query string or local storage), expire it after 30 minutes, and honour it only in the callback's unlinked branch.
- **INV-022 (mobile).** THE SYSTEM SHALL let an unlinked signed-in member paste an invite link or token on the not-linked screen, accept `fitcruxx://invite/<token>` via the route above, save a token that arrives before sign-in and offer it after, and never queue a redemption offline (an offline attempt shows a retry message, no fake success). After a successful link the member lands on the member home with fresh claims. This amends the "no public-code join" requirement of `openspec/specs/mobile`: a single-use, expiring, email-bound invite token is not the public gym code and is not an unauthenticated join.
- **INV-023 (copy and consent).** Every user-visible string SHALL follow the product voice: specific, honest, no invented numbers; refusal copy is exactly the five sentences in "Shared"; the accept pages state what data is processed (INV-020). `/privacy` gains a sentence on invite-based account linking.
- **INV-024 (data lifecycle).** `member_invites` holds no personal data (ids, hash, timestamps). Retention: prune 1 year after `closed_at` or `expires_at` (a `docs/security.md` row; no job is built, like the other rows). A member erasure (`erased_at`) makes their pending invite unavailable at once (INV-008).

- **INV-025 (member-list invite visibility; INV-Q9).** WHEN real front-office staff view the member
  list THE SYSTEM SHALL show each member's app-access state inline as a dot plus a readable word,
  and, whenever that member has invite history, the latest invite's generated Postgres enum status
  (`pending`, `redeemed`, `revoked`, `superseded`) with its sent and expiry times as absolute date-times
  explicitly in IST. Expired pending invites SHALL be labelled expired without inventing an enum value.
  The list SHALL offer a "Not joined yet" filter listing members whose `user_id` is null, including
  never-invited, expired, revoked and unavailable members, and excluding linked members. Applying it
  SHALL preserve the existing tenant, search, status and pagination constraints. Trainers SHALL not
  receive invite or app-access metadata. Loading, empty, error and preview states SHALL be honest;
  missing or failed data SHALL never appear as a successful invite or link.
- **INV-026 (member invite history; INV-Q11).** WHEN an authorized front-office staff member views
  a member's history after a successful resend or revoke THE SYSTEM SHALL show the persisted invite
  audit activity for that member, with a readable actor, action and absolute IST timestamp. A resend
  SHALL show its supersede and issue events; a revoke SHALL show its revoke event. Successful actions
  SHALL refresh the displayed state and history without requiring a manual reload; failed actions
  SHALL never fabricate history. Only this member's invites in this tenant may contribute events;
  trainers, public invitees and support preview SHALL receive no invite history. Empty, loading and
  error states SHALL be explicit. History SHALL expose neither raw tokens nor hashes, and SHALL not
  render audit JSON or refusal-attempt identity data. An unavailable actor name SHALL have an honest
  fallback instead of being attributed to the viewer.
- **INV-027 (Google account chooser; INV-Q8, inherited by STI-014).** WHEN either
  `startInviteGoogleSignIn(token)` or `startStaffInviteGoogleSignIn(token)` starts Google OAuth,
  THE SYSTEM SHALL pass `options.queryParams: { prompt: 'select_account' }`, alongside the existing
  callback redirect. The token SHALL remain exclusively in its family's HttpOnly cookie and SHALL
  never enter OAuth query parameters or the callback URL. "Use a different Google account" SHALL
  preserve the invite and reach this chooser path. Ordinary web sign-in behavior remains unchanged;
  native Google account selection follows INV-029.

- **INV-028 (safe invite-history reader).** `public.read_member_invite_history(p_member_id uuid)`
  SHALL return `table (event_id uuid, occurred_at timestamptz, action text, actor_name text)` as a
  postgres-owned `security definer`, `stable`, with `set search_path = ''`. Only `authenticated`
  SHALL execute it; `public`, `anon` and `service_role` SHALL have no execute privilege. It SHALL
  call the existing `app.member_invite_actor(array['gym_owner','gym_manager','front_desk'])`, so
  incomplete, stale, inactive, trainer, member, platform and impersonating callers fail `42501`.
  Actor validation precedes argument validation: a null member id then fails `22023`; an unknown
  or other-tenant member fails `42501`. No caller-provided tenant is accepted.
- The reader SHALL expose only this tenant and member's persisted `member_invite.issued`,
  `member_invite.superseded`, `member_invite.revoked`, `member_invite.redeemed`, `member.linked`
  and `member.unlinked` events. Invite events must join their `record_id` to an invite of this
  exact tenant and member; member events must have this exact member `record_id`. It SHALL
  exclude every refusal event, unrelated target, platform-level event and unknown action.
  No audit JSON, token/hash, contact field, Auth id, staff id or tenant id is returned.
- `actor_name` SHALL be a real same-tenant staff name resolved from the recorded actor, or this
  member's name for their own member-attributed link/redemption event. If no truthful name can
  be resolved it SHALL be null; the UI says "Name unavailable", never names the viewer instead.
  Results SHALL be the latest 50 events ordered by `occurred_at desc, event_id desc`; empty
  history returns zero rows, and failures remain distinguishable from an empty history.
- Add the tenant-leading `audit_log_member_invite_history_idx` on
  `(tenant_id, record_type, record_id, occurred_at desc)`. The reader belongs to the pending INV
  migration; `04_contract_meta` gains only this exact stable public definer signature. Shared
  `MEMBER_INVITE_HISTORY_LIMIT = 50` records the history bound separately from unrelated roster
  page sizes. The history surface is labelled recent history and uses the reader rather than
  querying broad `audit_log` rows in the web runtime.

- **INV-029 (native landing consent).** Native invite entry SHALL load only the gym name through
  the existing locally SHA256-hashed peek; show that gym, the shared linking notice and full privacy
  link before direct Google sign-in; save the token securely and request the account chooser.
  Saved invites after sign-in SHALL retain named-gym consent. Unavailable and connection failures
  SHALL be honest and expose no member record; redemption SHALL never be queued offline.
- **INV-030 (safe reopening and account recovery).** A signed-in member reopening a token SHALL
  check idempotent replay through the existing live POST path and open Home with fresh claims only
  for `already_linked_here`. Web render/GET SHALL never mutate the binding. Other linked identities
  SHALL remain refused under D1. Refusals SHALL show only the viewer's email and one-tap account
  switching that preserves the token; no new SQL capability or another member's facts are exposed.
- **INV-031 (Google provider font and availability).** Ordinary, member and staff Google controls
  SHALL share the locally bundled official Google Sans Medium v14.000 asset, pinned SHA-256 and
  SIL OFL 1.1 provenance. They SHALL use approved provider colors/mark, 14/20 typography,
  12/10/12 padding, at least 44px web / 48dp native targets and unclipped enlarged text.
  Loading and failure SHALL be honest; retry SHALL load only the font, without Auth or token
  effects, and the Google action SHALL become usable only when conformance is guaranteed.

## Secure staff invites (STI)

Frozen v2 batch-1 contract: `openspec/changes/staff-invites/proposal.md`, including its v1.1 amendments and inherited INV clarifications. Its platform read pair is an explicit exception to STI-011's original non-owner shorthand. The accepted throttle asymmetry remains: member redemption counts member refusals; staff redemption counts both families.

- **STI-001 (create and invite).** WHEN a real gym owner (not impersonating) submits a full name, plausible email, optional E.164 phone, a role in manager/front desk/trainer and an optional branch of their own gym THE SYSTEM SHALL, in one transaction, insert one active unlinked `staff` row and one `pending` hash-only invite (48 h), write `staff.invited` and `staff_invite.issued`, and return their ids. Role `gym_owner` or any other value SHALL fail `GL082`; a staff email already used in the gym (trimmed, case-insensitive, active or not) SHALL fail `GL081`; an implausible/blank email `GL076`; another gym's branch `42501`.
- **STI-002 (issue/resend/revoke).** As INV-001/003/005 for `staff_invites`, owner-only: manager, front desk, trainer, member, platform and impersonator SHALL be refused `42501`. An inactive staff row or a `gym_owner` row SHALL fail `GL075`; one with a `user_id` `GL077`; no/implausible email `GL076`. Resend supersedes the pending (even expired) invite in the same transaction.
- **STI-003 (limits).** 30 issues per gym per rolling hour and 5 per staff row per rolling 24 h (`GL078`), counted over `staff_invites.issued_at`; `invite_staff_member` counts toward both.
- **STI-004 (redeem).** As INV-007…011 with the staff changes stated above, including: the issuing staff row must still be an active `gym_owner` of the tenant at redemption (else `invite_unavailable`); the refusal throttle counts refusals of both families; D1 counts `members`, `staff` and `platform_users`; the same advisory lock key serializes a concurrent member and staff redemption by one account so at most one binding results.
- **STI-005 (role is the owner's).** THE SYSTEM SHALL never let the invitee choose or change the role: redemption sets only `staff.user_id`; the role, branch, name and email of the row are untouched; the access-token hook then mints `app_role` = the row's role and `staff_id`.
- **STI-006 (binding guard).** `app.enforce_staff_auth_binding` SHALL admit only the two shapes in "trigger amendment"; a front-desk, manager, owner or any other session writing `staff.user_id` directly SHALL still fail `GL049`; owner linking by `/platform` is unchanged; a `gym_owner` row can never be linked or unlinked through these commands.
- **STI-007 (peek).** As INV-012, returning gym name and the row's role only for a pending, unexpired invite of an active, role-valid staff row whose issuer is still an active owner, in an eligible gym.
- **STI-008 (unlink).** As INV-014, owner-only; target role must be manager/front desk/trainer; effects: `user_id` cleared via the admitted unlink shape, the former user's sessions deleted by the existing trigger, `staff.unlinked` audited with the reason; an unbound row fails `GL080`.
- **STI-009 (read model).** `read_staff_app_access` owner-only; states and precedence as INV-015 (`unavailable` = inactive staff or `gym_owner` role).
- **STI-010 (audit).** Every create, issue, supersede, revoke, redeem, refusal, link and unlink writes `audit_log` via `app.staff_invite_audit` with no token or hash; shapes mirror INV-016 with record types `staff_invite` / `staff` and the action names listed above; `staff.invited` after `{ role, branch_id }` and the new staff id as `record_id`; `staff.linked` after `{ user_linked: true, via: 'invite', invite_id, role }`.
- **STI-011 (tenancy/grants).** `staff_invites` is invisible across tenants and to every non-owner; no write grant to `authenticated`; all seven RPCs executable by no role beyond `authenticated` (`anon` only for peek); existing meta-suites amended in a `spec:` commit.
- **STI-012 (API).** The five routes behave as above with the INV-018 rules.
- **STI-013 (post-link sign-in).** After a staff link the handler SHALL end the local session and the person SHALL see the "sign in again" notice; it SHALL NOT claim the workspace is open.
- **STI-014 (accept pages).** As INV-020/021 with the staff cookie, role label and staff notice; the OAuth callback honours the staff cookie only when no valid member-invite cookie exists.
- **STI-015 (team console).** The Team pages SHALL be reachable only by `gym_owner`, show dot-plus-word states, never show another gym's staff, enumerate loading/empty/error/permission-denied/offline states (gate 30), and keep owner rows read-only.
- **STI-016 (copy).** Refusal copy is exactly the five staff sentences; no invented numbers; the notice states role and data processed.
- **STI-017 (retention).** `staff_invites` holds no personal data; retention row in `docs/security.md` as for `member_invites`.
- **STI-018 (no regression).** Existing owner-link (`link_gym_owner`), `deactivate_gym_owner`, hook precedence, staff front-desk RPCs and the operator provisioning tool behave exactly as before.


INV/STI lifecycle interpretation: the invite status graph is pending→redeemed, pending→revoked, pending→superseded; every closed state is terminal. Expiry is a timestamp predicate, not another enum label or persisted transition. Revoke may close an expired pending invite; resend supersedes it. Account binding is separate: unlinked→linked only through a verified redeem (or the privileged recovery/platform path); reasoned unlink clears the binding and revokes sessions, never reopening a redeemed token. The references to “no personal data” in INV-024/STI-017 mean no contact fields or plaintext token: linked identifiers are pseudonymous data, and the retention/erasure qualifications in `docs/security.md` apply.

## V2 batch 2 frozen rules (implementation and acceptance pending)

The authoritative GRD-001…GRD-028 EARS text is
`openspec/changes/guardian-minors/proposal.md`, with the owner-approved
`marker-integrity-amendment.md` completing GRD-013's provenance boundary. The
owner's one-time legacy missing-DOB attestation is included in that contract.
Independent SQL suites precede the local migration draft; Cloud application,
full verification and archival into current OpenSpec truth are still pending.

The authoritative BIZ-001…BIZ-022 EARS text is
`openspec/changes/business-type/proposal.md`: canonical business type changes
nouns only, retains existing commercial data and presets, and uses owner/platform
audited commands. Direct guarded-column writes never replace those commands;
ordinary hidden-row RLS behavior remains. Cross-feature precedence remains
`openspec/changes/v2-batch2-shared/decisions.md`.
