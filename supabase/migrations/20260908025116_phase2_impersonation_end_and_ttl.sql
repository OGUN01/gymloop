-- Phase 2 — impersonation: someone can end a live session, and a session is bounded.
--
-- Implements openspec/changes/phase-2-identity-and-tenancy/design.md
--   § 6 Impersonation — "The impersonator ends its own session, and nobody else can"
--                     — "A hard TTL is a bound, not a future timestamp"
--   § 8.6 Index rule 3 governs `using`, not `with check`
-- Specification: openspec/changes/phase-2-identity-and-tenancy/specs/impersonation/spec.md
-- Decisions: ADR-030 (CI applies migrations), ADR-042 (replayed inside begin … rollback
--   before it is pushed), ADR-047 (a constraint is what stops a bad row existing).
--
-- Statement order is docs/data-model.md's: constraints → policies. No begin/commit.
--
-- ---------------------------------------------------------------------------
-- Why this file exists: a composition defect, not a mistake in either half
-- ---------------------------------------------------------------------------
--
-- `impersonation_sessions_platform_write` requires the caller to hold
-- `app_role = 'super_admin'` *and* to be the session's own `actor_user_id`. Both terms
-- are right on their own. Together with the hook they made `ended_at` unsettable by any
-- session at all: **while a session is live, the hook gives its actor
-- `app_role = 'gym_owner'` for the duration**, so the one person the `actor_user_id`
-- term admits is the one person who cannot satisfy the role term — and no other admin
-- satisfies the `actor_user_id` term. Only `service_role`, or waiting out `expires_at`.
-- § 6 said "it forces an explicit end, which is what writes the audit row"; nothing
-- could perform that end, so INT-003's end row never landed.
--
-- **Stated plainly, because it is the general lesson:** a policy that gates on the
-- caller's role is blind to a role the caller is *prevented from holding* by another
-- part of the same system. Neither half was wrong. The composition was, and it is only
-- visible to a reader holding the hook and the policy at once.


-- ---------------------------------------------------------------------------
-- 1. Constraints
--    A hard TTL is a bound on the *span*, not the presence of a future timestamp.
--    `docs/security.md` promises one and lists "an impersonation session with no expiry"
--    among the things that must never happen; Phase 1's
--    `impersonation_sessions_expires_at_after_started_at_chk` only asks
--    `expires_at > started_at`, under which `now() + interval '10 years'` is legal — and
--    under the defect above, unendable as well as unbounded.
--
--    Two hours is the longest support session the platform intends to allow, and **the
--    operator is `<=`, so exactly two hours is legal**. That is specified rather than
--    left to taste because a blind author declined to test the boundary while it was
--    unstated — a test that depends on which operator the implementer happened to pick
--    tests a coin toss rather than a requirement. The literal lives here because a check
--    constraint cannot import a TypeScript constant — the same exception
--    docs/data-model.md already records for the IST calendar-day defaults. If it
--    changes, this line is where it changes.
--
--    Validating, not `not valid`: measured before writing, `public.impersonation_sessions`
--    holds **zero rows**, so there is nothing for the validation scan to reject.
-- ---------------------------------------------------------------------------

alter table public.impersonation_sessions
  add constraint impersonation_sessions_ttl_chk
  check (expires_at <= started_at + interval '2 hours');


-- ---------------------------------------------------------------------------
-- 2. Policies
--    A fourth policy on `impersonation_sessions`, and the only one in the schema keyed
--    on the impersonation claim.
--
--    `using` reaches exactly one row — the session the caller is currently inside — so
--    an impersonator can end its own session and no other. `with check` makes ending it
--    the only thing that path can do: an update leaving `ended_at` null is refused, so
--    the impersonator cannot extend its own `expires_at` and cannot retarget the session
--    at another tenant.
--
--    **The role term is not redundant with the claim term.** Without it this policy has
--    no role term at all, so a token carrying `app_role = 'front_desk'` — or `member` —
--    together with an `impersonation_session_id` would end that session through this
--    path. The hook never mints such a pair and a client cannot forge one, so it is not
--    exploitable; it is a policy whose correctness would be held by a *different
--    component*, which is the identical shape to the `<t>_member_select` widening and to
--    the composition defect this policy exists to fix. Three instances of one shape in
--    one phase: "does this policy defend itself, alone?" is a standing question, not a
--    discovery.
--
--    **It carries no liveness term, and must not.** An expired, never-ended session is
--    still endable by its own claim. `and expires_at > now()` would look like tightening
--    and would in fact recreate the unreachable state for every abandoned session — and
--    because `impersonation_sessions_actor_user_id_open_key` blocks that actor until an
--    explicit end is written, "unendable" and "the actor can never impersonate again"
--    would be the same sentence. Do not add it.
--
--    `for update` and not `for all`: there is nothing to insert (an impersonating token
--    is not a super admin, and creating a session is `_platform_write`'s business) and
--    `delete` is granted to `authenticated` on no table.
--
--    Index rule 3 (§ 8.6): `using` names `id`, which leads the primary key. `ended_at`
--    appears only in `with check`, which is evaluated against one row already in hand
--    and drives no scan, so it needs no index.
--
--    **The read half of this path was checked rather than assumed**, because it is the
--    same composition trap one layer down: an UPDATE also needs a SELECT policy to admit
--    the row its `where` reads. An impersonating token fails
--    `impersonation_sessions_platform_select` (`is_platform()` is false on it, by design
--    — § 6), so the read rests entirely on `impersonation_sessions_tenant_select`, whose
--    predicate is the target tenant plus `is_gym_admin()`. The token carries that tenant
--    and `app_role = 'gym_owner'`, so both hold. Had the matrix given this table a
--    narrower read gate, this policy would have been unusable in exactly the way
--    `_platform_write` was.
-- ---------------------------------------------------------------------------

create policy impersonation_sessions_impersonator_write on public.impersonation_sessions
  for update to authenticated
  using (id = (select app.current_impersonation_id())
         and (select app.current_app_role()) = 'gym_owner')
  with check (id = (select app.current_impersonation_id())
              and (select app.current_app_role()) = 'gym_owner'
              and ended_at is not null);
