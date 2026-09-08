# Phase 2 tasks

Order matters. Migrations are applied by CI on merge (ADR-030) and a push must wait for the previous push's DB run, so the three migrations land serially. Tests are committed red before the implementation that turns them green (ADR-038, hard rule 10).

## 0 — Contract

- [x] Inventory the live schema: every table, policy, grant, `app` function, and the indexes any member gate would need. *(done — database-derived, 36 tables / 71 policies)*
- [x] Establish the auth-hook mechanics from primary sources: contract, grants, enablement path, failure behaviour, testability. *(done — fail-closed, 2s budget, `supabase config push` available in CLI 2.110.0)*
- [x] Write `design.md`: claim contract, resolution order, gym switching, impersonation, the four gates, the 36-row matrix, OPEN-001's answer, and what is out of scope.
- [x] Write the EARS specs: `identity`, `authorization`, `impersonation`.

## 1 — Tests, written blind, committed red

- [x] **Visible suite** (`supabase/tests/`), written from the specs and `design.md` §8.3 without seeing any implementation. New files, not edits to Phase 1's:
  - `11_identity_hook.sql` — the hook called directly with synthetic events: resolution order, inactive stops, unlinked user, claim well-formedness, reserved claims preserved, gym switching and its fallback.
  - `12_role_matrix_read.sql` and `13_role_matrix_write.sql` — every role × every table, read and write.
  - `14_impersonation.sql` — claims, liveness, one-live-session, the audit rows.
  - `15_identity_triggers.sql` — session revocation on deactivation and on role change, and the role-change audit row.
- [x] **Holdout suite** (`github.com/OGUN01/gymloop-holdout`), written from the same specs by an author who reads neither the visible suite nor the implementation.
- [x] Existing Phase 1 files that the matrix changes: the single `front_desk` fixture and the `platform_support` fixture, plus `04_contract_meta`'s policy assertions. **This is the `spec:` case** — the requirement itself changes — so the commit carries the prefix and the reason.

## 2 — Migration 1: accessors, gates, and the hook

- [x] `app.current_app_role()`, `app.current_member_id()`, `app.current_staff_id()`, `app.current_impersonation_id()`.
- [x] `app.is_staff()`, `app.is_gym_admin()`, `app.is_front_office()`.
- [x] `app.impersonation_is_live(...)` — the one place the liveness expression exists.
- [x] `app.custom_access_token_hook(event jsonb)` — `security definer`, `set search_path = ''`, the exception handler of `design.md` §2 with the comment explaining it.
- [x] Grants: `usage` on `app` and `execute` on the hook to `supabase_auth_admin`; `execute` revoked from `public`, `anon`, `authenticated`.
- [x] Replay against Cloud inside `begin … rollback` (ADR-042) — all 23 visible files pass; migrations applied in run `34157595114`.

## 3 — Migration 2: the role matrix

- [x] Thirty-six tables, per `design.md` §8.3: tighten `<t>_tenant_all`, narrow `<t>_platform_all`'s `with check` to `super_admin`, add `<t>_member_select` where the matrix names one, convert the five read-only tables to `<t>_tenant_select`, and split `platform_users` into a super-admin policy and a support select policy.
- [x] Add nothing else. No index is required (§8.6, measured), no column is added (§8.4).
- [x] Replay against Cloud before pushing — done.

## 4 — Migration 3: triggers

- [x] Session revocation on `platform_users`, `staff`, `members` when `is_active` goes true → false or `role` changes. **Verify first** that a `security definer` function owned by `postgres` may delete from `auth.sessions` on this project; if it may not, stop and record the fallback as an ADR rather than improvising.
- [x] The role-change audit row (INT-003), written by the same trigger.
- [x] Impersonation start and end audit rows, written by a trigger on `impersonation_sessions`.
- [x] Partial unique index: one live session per actor.
- [x] Replay against Cloud before pushing — done.

## 5 — Configuration

- [x] **Do not `supabase config push`** — it pushes all 414 lines, including `site_url = "http://127.0.0.1:3000"`, and there is no dry run (`design.md` §10).
- [x] A manually dispatched workflow PATCHing exactly three fields of `/v1/projects/{ref}/config/auth`: the hook enabled, its `pg-functions://postgres/app/…` URI, and `jwt_exp`.
- [x] Mirror the same three settings into `supabase/config.toml` so the repo describes the project truthfully — as the record, not the mechanism.
- [x] Phone sign-in for members and email sign-in for staff, with the SMS-provider gap recorded rather than faked.
- [x] The bootstrap workflow for the first `super_admin` (`design.md` §9), inert once `platform_users` is non-empty.

## 6 — Close

- [ ] Regenerate `packages/db/types/database.ts` and confirm `schema-drift` is green. The hook lives in `app`, so it must **not** appear in the generated types — if it does, it is in the wrong schema.
- [ ] Blind final critic, fresh context, reading the specs and the built system but not this task list.
- [x] ADRs for: the hook's schema and exception rule, the matrix and its four gates, OPEN-009's answer and its residual window, OPEN-001's answer. Mark OPEN-009 and OPEN-013 resolved; amend OPEN-002 to say the `api-client` deferral moved to Phase 3.
- [x] Update `docs/data-model.md` (policy shape, the matrix, index rule 3), `docs/security.md` (impersonation mechanics, session revocation), `docs/registry.md`, `docs/gates.md`.
- [ ] Archive the change into `openspec/specs/`.
