# Phase 2 — Identity & tenancy

## Why

Phase 1 built a schema in which **every signed-in session sees its whole gym**. Every tenant-scoped table carries exactly one gym-side policy, `tenant_id = app.current_tenant_id()`, and nothing more. That was the correct Phase 1 scope and it is recorded as `OPEN-013`, but it means the `member` label in the `app_role` enum currently describes a session that can read every other member's phone number, every payment, every staff row's `role`, and the gym's Razorpay account. **No member token may be issued until that is closed**, and Phase 3 cannot issue one without it. It is DPDP-relevant: the gym is the Data Fiduciary and a member session under this shape reads the whole gym's personal data.

Second, the claims those policies read are set by nothing. `app.current_tenant_id()` and `app.is_platform()` were written in Phase 1 against claim names ADR-032 fixed — `tenant_id` and `app_role` — and the custom access-token hook that populates them was deliberately deferred to here. Until it exists there is no way to sign in as anybody: the entire RLS suite is exercised by `set_config` in pgTAP fixtures, and not one real token has ever carried a claim.

Third, `is_active` is written and read by nothing (`OPEN-009`). Deactivating a compromised super admin revokes no live session, and `platform_support` and `super_admin` are indistinguishable to every Phase 1 policy — so a support account can promote itself by updating its own `platform_users` row.

## What Changes

- **A custom access-token hook** (`app.custom_access_token_hook`) resolves a signed-in `auth.users` row to exactly one identity — platform user, staff member, or gym member — and stamps the claims every policy in the schema already reads. It is the first thing in this project that makes a real JWT mean anything.
- **`is_active` becomes load-bearing.** An inactive identity gets no claims, and deactivation revokes live sessions rather than waiting for a token to expire — the answer OPEN-009 asks for, stated as a mechanism and not as a hope.
- **A role matrix**: every tenant-scoped table gains a role-gated read predicate and a role-gated write predicate, and the tables a member may see gain a member-scoped read policy. This is what closes OPEN-013. It is a **coarse role matrix** — role → table → operation — not the per-permission matrix `docs/data-model.md` defers out of v1.
- **Gym switching**: one `auth.users` row may be staff at several gyms, or a member at several gyms. The hook resolves which tenant a token is for, and switching means minting a new token, never widening an existing one.
- **Impersonation**: a super admin may act as a gym under a session that has a stated reason, a hard expiry, an audit row written by the database rather than by a caller who might forget, and a claim that marks every request as impersonated.
- **`OPEN-001` is answered**: how the very first `super_admin` comes into existence, without leaving a general-purpose backdoor for creating admins later.
- **Auth configuration**: phone-OTP sign-in for members and email sign-in for staff, expressed in `supabase/config.toml`, with the access-token lifetime chosen deliberately rather than left at its default — because a claim derived from a database row is only as fresh as the token carrying it.
- **BREAKING**: every gym-side policy predicate in the schema changes. A session whose token carries `tenant_id` but no recognised `app_role` reads **nothing** after this change, where before it read the whole gym.

  **The blast radius was measured before it was estimated.** Every `set_config('request.jwt.claims', …)` in the eighteen visible pgTAP files already carries an `app_role`, and the distribution is `gym_owner` ×15, `super_admin` ×7, `platform_support` ×1, `front_desk` ×1. `gym_owner` keeps full read and write inside its tenant, so the visible suite should survive this change almost intact; the single `front_desk` fixture and the `platform_support` one are the two that must be re-read against the new matrix. The holdout suite has not been inspected and cannot be — if it is red on merge, the matrix is what is wrong, not the test.

## Capabilities

### New Capabilities
- `identity`: the access-token hook, the claim contract, identity resolution across platform user / staff / member, `is_active` enforcement and session revocation, gym switching, and the first-super-admin bootstrap.
- `authorization`: the role matrix — for every table, which of the seven roles may read it, which may write it, and which rows of it a member sees.
- `impersonation`: starting, ending, and expiring an impersonation session; the claims it sets; and the audit rows it writes without being asked.

### Modified Capabilities
- `tenancy`: the RLS policy shape gains a role term. The Phase 1 guarantee — one gym never reaches another gym's rows — is unchanged and must stay proven; what changes is that being inside the right gym is no longer sufficient.
- `platform`: `platform_users` stops being writable by any platform role, `platform_support` becomes distinguishable from `super_admin`, and `impersonation_sessions` gains the machinery behind its constraints.

## Out of scope, stated so it is not assumed

- **No Route Handlers, no `packages/api-client`, no UI.** `docs/architecture.md` defers `api-client` to "Phase 2", on the reasoning that there is nothing to generate until Route Handlers exist. There are still none, and this phase adds none — the deferral moves to Phase 3, recorded rather than silently carried.
- **No per-permission role matrix.** Roles are the unit; a custom-permission grid is explicitly out of v1.
- **No SMS provider.** Phone-OTP sign-in is configured, but no SMS credential exists yet, so the member sign-in path cannot be exercised end to end in this phase. Named as a gap here rather than discovered in Phase 3.
