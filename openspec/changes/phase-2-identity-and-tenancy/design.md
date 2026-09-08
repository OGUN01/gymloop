# Phase 2 design — identity & tenancy

This is the **contract**. Phase 1's most expensive lesson was that an ambiguous sentence here does not produce one mistake — it produces the same mistake independently in every agent that reads it (ADR-052's note: two blind authors wrote the identical over-broad rule from one loose sentence, and neither was at fault). Every rule below is written to be mechanically checkable, and where a rule has an exception the exception is named rather than implied.

Two facts about the platform were established by measurement before this was written, and both change the design:

- **A Postgres auth hook fails closed, with a two-second budget.** Supabase propagates a hook's exception into an HTTP error and issues no token; it does not fall through to a token without claims (`supabase.com/docs/guides/auth/auth-hooks`). The hook is global. **An unhandled exception in this one function locks every user of the product out of sign-in *and* token refresh simultaneously.** That single fact drives section 2's exception rule.
- **The hook can be enabled without a Dashboard click**, so enabling it is CI's work like everything else here. `supabase config push` exists in CLI 2.110.0 and is the obvious route; §10 explains why it is nonetheless the wrong one on this repo, and what replaces it.

## 1. Where the hook lives, and why not in `public`

**`app.custom_access_token_hook(event jsonb) returns jsonb`.** Supabase's own documentation puts it in `public`; here it must not be.

`supabase/config.toml` exposes only `public` and `graphql_public` to the Data API, and `packages/db/types/database.ts` is generated from `public`. A hook in `public` would therefore be a PostgREST RPC and would appear in the generated types as a callable function — a `schema-drift` diff on every regeneration, and a function on the public API surface whose entire job is to decide who is a super admin. ADR-032 already put the two accessors in `app` for exactly this reason. The hook goes in `app` and the URI is `pg-functions://postgres/app/custom_access_token_hook`.

**It is `security definer`, owned by `postgres`, with `set search_path = ''`.** The documented alternative — leave it `security invoker` and grant `supabase_auth_admin` privileges on every table it reads — means five table grants to a role whose interaction with RLS the Supabase documentation does not settle (the research is explicit that this point is *not established*). `security definer` under an owner that holds `BYPASSRLS` removes the question: the hook reads what it needs, `supabase_auth_admin` gets `usage` on schema `app` and `execute` on this one function and nothing else, and `execute` is revoked from `public`, `anon` and `authenticated`. The surface is one function callable by one role.

## 2. The exception rule — the most important paragraph in this document

**The hook body's entire logic sits inside a block with `exception when others then return event;`.**

If claim resolution raises for any reason — a type cast, a null, a schema change, a row that should not exist — the hook returns the event exactly as it received it. The user gets a token with no Gymloop claims. Under Phase 1's arithmetic that session reads zero rows from every table and raises nothing, which is the safe state the tenancy spec already guarantees and already tests.

The alternative is that the exception propagates, Supabase issues no token, and **nobody can sign in to the product until someone deploys a migration**. Between "everyone is signed in and sees nothing" and "nobody can sign in", the first is recoverable in a browser refresh and the second is an outage with a CI round-trip as its floor.

This is deliberately *not* a general licence to swallow errors — it is one handler, at one boundary, on a function whose failure mode is a total outage. It must be written with a comment saying so, or a later reader will delete it as sloppy.

**The corollary:** because a swallowed exception is silent, the hook's behaviour cannot be inferred from the product working. It is proven by calling `app.custom_access_token_hook(<synthetic event>)` directly from pgTAP as `postgres` and asserting on the returned jsonb — which works, because it is an ordinary function. Every rule in sections 3 through 6 is testable that way, and the exit criterion depends on it.

## 3. The claim contract

ADR-032 fixed two claim names and warned that Phase 2's hook must set **exactly** these or every policy in the schema silently matches nothing. Phase 2 sets those two and adds three.

| Claim | Type in the JWT | Set when | Read by |
|---|---|---|---|
| `tenant_id` | uuid **as a string** | the identity belongs to a gym, or an impersonation session is live | `app.current_tenant_id()` |
| `app_role` | one label of the `app_role` enum, as a string | whenever an identity resolved | `app.current_app_role()` and the three gate functions |
| `member_id` | uuid as a string | the identity is a gym member | `app.current_member_id()` |
| `staff_id` | uuid as a string | the identity is a staff member | `app.current_staff_id()` |
| `impersonation_session_id` | uuid as a string | **and only when** the token is impersonating | `app.current_impersonation_id()` |

Rules, each because a policy depends on it:

**When a test may set an impossible claim set, and when it may not.** *(A rule, not an anecdote: four assertions across two files were found constructing claim sets the hook cannot mint, and the distinction below is the visible-suite author's.)* Hand-setting a claim combination the hook would never issue is **wrong when the test asserts that something works** — it proves the operation is reachable under conditions that never occur, which is how a requirement with no implementation passed for two rounds. It is **right when the test asserts that a policy refuses it** — there the impossible claim set is the point, because it proves the policy stands on its own rather than leaning on the hook to never produce it. Every one of this phase's three "policy defends itself" clauses is verified that way. A third case is legitimate and worth naming so it is not mistaken for the first: a claim set that is not mintable *now* but was minted earlier and is still in hand, which is exactly what §7's residual window guarantees exists.

- **A claim is absent, or it is a well-formed value.** Never an empty string, never JSON `null`. Phase 1's accessors `nullif(…, '')` defensively, but a hook emitting `"tenant_id": ""` makes `app.current_tenant_id()` return null on a session that *does* have a tenant — which reads as "sees nothing" and is indistinguishable from a bug. If the hook has no value for a claim, it omits the key.
- **`app_role` is never a value outside the enum** — but nothing raises if one appears. **`app.current_app_role()` returns `text` and performs no cast.** *(Revised: the first draft had it return `public.app_role` and raise `22P02` on an unknown label, by analogy with ADR-032's malformed-`tenant_id` rule. The analogy is wrong and the implementer was right to say so.* A malformed `tenant_id` cannot mean anything at all, so raising is the only honest answer. An unrecognised **role** has an obvious and safe meaning — *this session holds no privileges* — and it is the reading every gate would reach anyway. Worse, a cast makes the failure mode inconsistent across the schema: the gate functions would return false and yield zero rows, while the handful of policies comparing the role directly would raise, so the same forged claim behaves differently table by table. Text comparison throughout means an unknown role reads nothing, writes nothing, and raises nowhere.*)
- **A platform token carries no gym claims.** `app_role` in (`super_admin`, `platform_support`) ⇒ no `tenant_id`, no `member_id`, no `staff_id` — unless it is impersonating, which is section 6.
- **A member token carries `tenant_id` and `member_id`, and never `staff_id`.**
- **A staff token carries `tenant_id` and `staff_id`, and never `member_id`** — even when the same human is also a member of that gym. One token is one identity.
- **The hook returns the whole claims object, not a diff.** Supabase performs no implicit merge; a hook that returns only its own keys drops every claim it did not copy, and Auth then rejects the token for missing required claims. The body reads `event->'claims'`, `jsonb_set`s into it, and writes it back under `claims`.
- **Reserved claims are never written**: `iss`, `aud`, `exp`, `iat`, `sub`, `role`, `aal`, `session_id`, `email`, `phone`, `is_anonymous`. The documentation states these must be *present* after the hook runs; it does **not** state that Auth repairs a hook that corrupts one, and we must not assume it does. Overwriting `role` would change which Postgres role the request runs as — the single most destructive thing this function could do.

## 4. Identity resolution — exactly one identity, in a fixed order

The hook resolves `event->>'user_id'` against three tables **in this order, stopping at the first match**:

1. `public.platform_users` by `user_id`
2. `public.staff` by `user_id`
3. `public.members` by `user_id`

The order answers a real question — a platform engineer who is also a member of a test gym must get their platform identity — and it is fixed here so that no implementer has to choose.

**What "active" means, per table.** *(Revised: the first draft said `is_active` for all three tables. `members` has no such column — its lifecycle column is `status member_status`, values `active | paused | expired | cancelled | blocked`, plus `erased_at`. The implementer caught it. Naming a column that does not exist is precisely the kind of contract defect that produces the same wrong guess in every agent that reads it.)*

| Table | An identity is active when |
|---|---|
| `platform_users` | `is_active` |
| `staff` | `is_active` |
| `members` | `status not in ('cancelled', 'blocked')` **and** `erased_at is null` |

A `paused` or `expired` member **signs in normally**. That is not leniency — the renewal loop is the product, and a member whose membership lapsed is exactly the person who must be able to log in and pay. `cancelled` and `blocked` are the two states that mean the gym has ended the relationship. `erased_at` is DPD-006: a member whose personal data has been erased must not hold a live session, and the retention table already says the row survives for the financial history that references it.

**Resolution is committed by the table, not by the row.** A user may have several `staff` rows or several `members` rows, so "the matched row" is not well defined until a tenant is chosen — and choosing the tenant is section 5, which runs *after*. The rule is therefore: **if the user has any row in a table, resolution commits to that table.** If none of that table's rows is active, resolution **stops and returns no claims**; it does not fall through to the next table. A deactivated super admin must not silently become a member. This is stated because "skip the inactive row and keep looking" is the obvious alternative reading, it is wrong, and it is also the only reading consistent with section 5's scenario where a user active in gym A and deactivated in gym B gets gym A.
- **If no row matches anywhere, the token gets no Gymloop claims.** That is the state of a freshly signed-up `auth.users` row no gym has linked yet. It is a **supported state, not an error**: `app.current_tenant_id()` is null, `app.is_platform()` is false, both policies fail, the session reads zero rows and raises nothing.
- **The hook never raises for a data reason.** The failure modes it must survive are: no matching row; an inactive row; several matching rows (section 5); an expired impersonation session (section 6); and a null `event->>'user_id'`. Section 2's handler is the backstop, not the plan.

## 5. Gym switching — one token is one tenant

One `auth.users` row may match **several** `staff` rows in different tenants, or several `members` rows. The schema permits it deliberately: `staff_tenant_id_user_id_key` and `members_tenant_id_user_id_key` are unique **per tenant**, not globally.

- The hook reads a **requested tenant** from `auth.users.raw_app_meta_data ->> 'active_tenant_id'`.
- **It validates the request before honouring it.** If the user has an *active* row in that tenant, the token is for that tenant. If not — the row was removed, deactivated, or the value was never valid — the hook falls back to the default below **and does not raise**. It must never mint a token for a tenant the user has no active row in; that would be a cross-tenant escalation whose only cost is a metadata write.
- **The deterministic default**, when no valid request is present: the active row with the **earliest `created_at`**, ties broken by the lower `id`. Deterministic is the requirement. An implementer choosing "any row" produces a token whose tenant changes between refreshes — a bug that only ever appears in production.
- **Switching gyms means minting a new token**: write `active_tenant_id`, then force a refresh. There is no claim-widening path and no token carrying two tenants. `raw_app_meta_data` is writable only by `service_role` and by Auth itself, never by the user — which is what makes reading it safe. The hook validates it anyway, because a claim contract that depends on another system's write path holding is not a contract.

## 6. Impersonation

`impersonation_sessions` exists with its reason and expiry constraints (Phase 1). Phase 2 gives it behaviour.

- **A session is live** when `ended_at is null and expires_at > now()`. That expression appears in exactly one function and never inline in two places.
- **Only `super_admin` may impersonate.** The hook checks for a live session only for an identity that resolved as a platform user with that role. `platform_support` may not — that is one half of making the two roles distinguishable.
- **An impersonating token** carries `tenant_id` = the session's target, `app_role` = `gym_owner`, `impersonation_session_id` = the session id, and **no `staff_id`, no `member_id`**. `app.is_platform()` is therefore **false** on it: an impersonator acts *as the gym*, with the gym's reach, not with both. A token that is simultaneously platform-wide and gym-scoped has a strictly larger blast radius than either, for no product reason.
- **An impersonation session names its own author, and this is enforced by the policy rather than by convention.** `_platform_write` gates the *caller*; without a further term it says nothing about the `actor_user_id` **column**, so a `super_admin` could create a session naming a different platform user as the actor — including a `platform_support` account, which is otherwise forbidden to impersonate at all. The audit trail would then name the wrong person, which is the one thing an impersonation audit row exists to get right. `impersonation_sessions_platform_write` therefore carries `and actor_user_id = (select auth.uid())` on both `using` and `with check`. *(Found by the blind visible-suite author, who noticed its own fixture depended on the gap being permitted and asked rather than assuming. `actor_user_id` already leads `impersonation_sessions_actor_user_id_idx`, so index rule 3 is discharged.)*
- **One *open* session per actor**, enforced by a partial unique index on `actor_user_id where ended_at is null`, named `impersonation_sessions_actor_user_id_open_key`. **This index is globally scoped on purpose, and it is the third exemption to ADR-047's rule.** ADR-047 says every unique or exclusion constraint in `public` leads with the tenant column, because a globally-scoped one is a cross-tenant denial of service — gym A takes a slot gym B can then never claim or even see. Two exemptions were named there (`organizations.gym_code`, which identifies a gym across the platform, and `qr_sessions.token_hash`, which is a secret). **This is the third**, and it must be added to the rule rather than allowed to trip its meta-test — which is how it was found, by that Phase 1 assertion failing during the replay.

Making it `(tenant_id, actor_user_id)` would not merely be unnecessary, it would **defeat the constraint**: a super admin could then hold an open session in fifty gyms at once, and the hook would have no way to decide which tenant an impersonating token names. One open session *per actor, across the whole platform* is the requirement. It is safe to scope globally for the reason ADR-047's danger does not apply here: no gym-side role can insert into this table at all, so no gym can take a slot from another. The actor is a platform user, and the platform is one tenant of one.

**Only the "open" half of liveness is enforceable by an index** — `now()` is not immutable, so `expires_at > now()` cannot appear in an index predicate. The qualifier in the name is therefore `open`, not `live`, following the naming rule that `<qualifier>` names what the partial index selects. The consequence is exact and worth stating: an actor may hold one *open* session, which may have expired. The hook still treats it as not live, so it sets no claims; but a second session cannot be created until the expired one is ended. That is the correct trade — it forces an explicit end, which is what writes the audit row.
- **The audit rows are written by the database.** A trigger on `impersonation_sessions` writes the start row on insert and the end row on the update that sets `ended_at`. INT-003 requires both. A caller who must remember is a caller who will eventually forget — and `audit_log` is read-only to `authenticated` (ADR-049), so the caller could not write it anyway.

  **The exact row, because "naming the acting user" was ambiguous enough that a blind author flagged it.** The trigger fires under `service_role` or `postgres` and therefore holds no JWT, so every value comes from the session row, never from a claim:

  | Column | Value |
  |---|---|
  | `tenant_id` | the session's target tenant |
  | `actor_user_id` | `impersonation_sessions.actor_user_id` — **not** a claim |
  | `actor_role` | `super_admin` |
  | `impersonation_session_id` | the session's `id` |
  | `record_type` | `impersonation_session` |
  | `record_id` | the session's `id` |
  | `action` | `impersonation_session.started` / `impersonation_session.ended` |
  | `reason` | the session's `reason`, on **both** rows — an auditor reading only the end row should not have to join to learn why the session existed |
  | `before` / `after` | **required by INT-003**, which says an audit row carries a before/after summary. On start: `before` null, `after` the session's `started_at`, `expires_at` and target tenant. On end: `before` the session as it stood (`ended_at` null), `after` the `ended_at` that was set. |

  *The `before`/`after` row above is a correction. The first version of this table listed the other seven columns and stopped, and the implementer — reading a contract that had just been made exact — took the literal reading and dropped the jsonb summary it had already written. That was the right call on the text and the wrong outcome, because INT-003 requires the summary and this table was simply incomplete. Recorded rather than silently patched: when a contract becomes precise, an omission from it starts reading as a prohibition, which is a new failure mode that arrives with the precision.*

  `record_id` and `impersonation_session_id` both carry the session id, and that is deliberate rather than redundant: `record_id` says what this row is *about*, and `impersonation_session_id` is the column every other audit row uses to say what session it was written *under*. A query for "everything done during session X" finds the start and end rows through the same column as the rest.
- **The impersonator ends its own session, and nobody else can.** *(Added after a blind critic found that nobody could.)* The hook gives the actor `app_role = 'gym_owner'` for the duration, so **while a session is live its actor cannot hold a `super_admin` token** — and `_platform_write` demands exactly that, plus `actor_user_id = auth.uid()`, which no *other* admin satisfies either. The two protections composed into a table whose `ended_at` was unsettable by any session at all. A fourth policy closes it:

  ```sql
  create policy impersonation_sessions_impersonator_write on public.impersonation_sessions
    for update to authenticated
    using      (id = (select app.current_impersonation_id())
                and (select app.current_app_role()) = 'gym_owner')
    with check (id = (select app.current_impersonation_id())
                and (select app.current_app_role()) = 'gym_owner'
                and ended_at is not null);
  ```

  **The role term is there because a blind author asked for it, and the argument is one this document has already accepted twice.** Without it the policy has no role term at all: a token carrying `app_role = 'front_desk'` — or `member` — together with an `impersonation_session_id` would end that session through this path. The hook never mints such a pair and a client cannot forge one, so it is not exploitable; it is a policy whose correctness is held by a *different component*, which is the identical shape to the `<t>_member_select` widening §8.1 closed and to the composition defect this policy exists to fix. One clause makes it self-contained. Three instances of one shape in one phase is the argument for treating "does this policy defend itself, alone?" as a standing question rather than a discovery.

  **It carries no liveness term, and must not.** An expired, never-ended session is still endable by its own claim. Adding `and expires_at > now()` would look like tightening and would in fact recreate the unreachable state for every abandoned session — and because the one-open-session index blocks that actor until an explicit end is written, "unendable" and "the actor can never impersonate again" would be the same sentence.

  The `using` clause reaches exactly one row — the session the caller is inside — and the `with check` makes ending it the only thing that path can do. An impersonator cannot extend its own expiry, because an update that leaves `ended_at` null is refused. The claim is minted by the hook and cannot be forged, so the policy needs no other term.

  **This is why `<t>_platform_write` alone was not enough, stated plainly:** a policy that gates on the caller's role is blind to a role the caller is *prevented from holding* by another part of the same system.

  **The seam one layer down, checked rather than assumed.** An `UPDATE` also needs a `SELECT` policy to admit the row its `WHERE` reads (§8.1). An impersonating token fails `impersonation_sessions_platform_select`, because `is_platform()` is false on it by design — so the entire read path rests on `impersonation_sessions_tenant_select`, gated on the target tenant **and** `is_gym_admin()`. The token carries that tenant and `app_role = 'gym_owner'`, so both hold and the end works. **Had the matrix given this table a narrower read gate — `= 'gym_owner'` alone would have been enough to break it — the new policy would have been unusable in precisely the way `_platform_write` was.** The implementer checked this without being asked, which is the right instinct one round after the same shape of defect: the fix for a composition bug is itself a composition. Neither half was wrong; the composition was.

- **A hard TTL is a bound, not a future timestamp.** `docs/security.md` promises a hard TTL and lists "an impersonation session with no expiry" among the things that must never happen, and Phase 1's constraint only requires `expires_at > started_at` — under which `now() + interval '10 years'` is legal. `impersonation_sessions_ttl_chk` bounds the span to **two hours**, the longest support session the platform intends to allow. **The operator is `<=`** — `expires_at <= started_at + interval '2 hours'`, so exactly two hours is legal. That is stated because a blind author declined to test the boundary while it was unstated, on the grounds that a test which depends on which operator the implementer happened to pick is a test of a coin toss rather than of a requirement. It was right, and the fix is to specify rather than to avoid. The literal lives in the migration because a check constraint cannot import a TypeScript constant, the same exception `docs/data-model.md` already records for the IST date defaults; if it changes, the migration is where it changes.

- **Expiry needs no job.** A session past `expires_at` stops being live by the definition above, so the next refresh drops the claims. Nothing sweeps the table. **The asymmetry, stated rather than papered over:** an expired session's *end* audit row is written when someone ends it, not when it expires — so `audit_log` shows starts without matching ends for abandoned sessions, and a reader must use `expires_at` rather than assume an end row exists.

## 7. `is_active` and role changes are load-bearing (OPEN-009)

Two halves, different mechanisms.

**Half one — the claim.** Section 4: an inactive identity gets no claims. That governs every token minted *after* deactivation.

**Half two — the tokens already issued.** A claim is a copy of a row taken at issue time; changing the row changes nothing about a token already in a browser, and Supabase's default access-token lifetime is one hour. Two mechanisms, both required:

- **A trigger revokes live sessions.** On `platform_users`, `staff` and `members`, when the identity stops being active by section 4's per-table definition — `is_active` going `true → false`, or a member's `status` becoming `cancelled`/`blocked`, or `erased_at` being set — **or when `role` changes** on the two tables that have one, the user's rows in `auth.sessions` are deleted. `members` carries no `role` column, so it writes no role-change audit row; that asymmetry is real and is not an omission. Deleting the session invalidates the refresh token, so the access token in hand is the last one that user will ever hold. A role change counts because a stale `app_role` claim is a stale privilege, and INT-003 requires an audit row for a role change in any case — the same trigger writes it.
- **A deliberately chosen `jwt_expiry`**, so the residual window is a number someone chose rather than a default nobody read. It goes in `config.toml`. The trade is real and must be recorded: every refresh runs the hook, so a short lifetime is a load decision as much as a security one.

**The audit row these triggers write, specified column by column.** §6 got this treatment for impersonation and this did not, which a blind author correctly called the same class of gap. Two events are audited on the identity tables:

| Column | On a role change | On a deactivation |
|---|---|---|
| `action` | `staff.role_changed` / `platform_user.role_changed` | `staff.deactivated` / `platform_user.deactivated` / `member.deactivated` |
| `record_type` | `staff` / `platform_user` | `staff` / `platform_user` / `member` |
| `record_id` | the row's `id`, or `user_id` for `platform_users`, which has no `id` | same |
| `tenant_id` | the row's tenant; null for `platform_users` | same |
| `actor_user_id` | `auth.uid()` — this trigger *does* run under the caller's session, unlike §6's | same |
| `actor_role` | the caller's role claim, resolved through the enum's catalogue so a forged label records as null rather than raising | same |
| `before` / `after` | `{"role": <old>}` / `{"role": <new>}` | `{"is_active": true}` / `{"is_active": false}`; for a member, the `status` and `erased_at` that changed |
| `impersonation_session_id` | the claim, when the caller is impersonating; null otherwise | same |

*The `impersonation_session_id` row is the implementer's addition, kept.* §6 defines that column as saying what session a row was written **under**, and a super admin who changes a staff member's role while impersonating a gym should stamp it — otherwise the one class of write most worth attributing to a support session is the one that does not carry the attribution. It is the only column here read from a claim rather than from the row, and it is correct precisely because this trigger, unlike §6's, runs under the caller's session.

**Deactivation is audited even though INT-003 does not list it.** INT-003 names a role change and not a deactivation, so this is an addition, made deliberately and recorded here rather than slipped in. The reason: deactivating a compromised super admin is the single most security-relevant write in this schema, the trigger is already firing on that transition to revoke sessions, and a schema that audits "front desk became a manager" but not "the super admin was switched off" is inconsistent in the direction that matters. `members` has no `role`, so it writes only the deactivation row.

**Deactivating one identity signs the user out of every gym, and that is correct rather than merely convenient.** A blind author noticed that the trigger deletes *all* of a user's `auth.sessions`, so a staff member employed at two gyms who is deactivated at one is signed out of both. There is no narrower option — a session row carries no tenant, so there is nothing to filter on — but the wider behaviour is also the right one: the deactivated identity may be the very tenant the user's current token names, and the only way to be sure the next token's claims are correct is to make the next token be minted. The cost is one re-authentication at the other gym. Stated so nobody later reads it as a bug.

**The residual window is real and must be written down**, not designed away: between the trigger firing and the current access token expiring, a deactivated user still holds valid claims. Any requirement claiming otherwise is false, and a test asserting otherwise is testing a fiction.

**Verify before relying.** That a `security definer` function owned by `postgres` may delete from `auth.sessions` on this project is an assumption until it is replayed against Cloud inside `begin … rollback` (ADR-042). If it cannot, the fallback is recorded as an ADR — not improvised. *(Measured: `postgres` holds `DELETE` on `auth.sessions` and `rolbypassrls`, and `auth.refresh_tokens` cascades from `sessions(id)`, so deleting the session takes the refresh token with it. The mechanism is available.)*

**One consequence §3 created and did not mention**, found by the implementer. `audit_log.actor_role` is `public.app_role`, but `app.current_app_role()` now returns `text` and casts nothing — so the role-change audit row needs a cast the accessor no longer performs. A plain `::public.app_role` would raise `22P02` on a forged claim, which would turn an audit write into a failed UPDATE and reintroduce exactly the failure mode §3 removed. **The cast must therefore be total**: resolve the label through the enum's own catalogue, so an unrecognised role records as `null` and nothing raises. Not through an inline list of the seven labels, which is a second role vocabulary and would drift — the same argument ADR-031 made when it deleted `ROLES` from `packages/shared`.

## 8. The role matrix

### 8.1 Shape

*Revised after the implementer's reading. The first draft of this section gave each table one `for all` gym-side policy with a read gate on `using` and a write gate on `with check`. That shape does not produce the behaviour the specs state, and the correction is recorded rather than quietly made — see the note at the end of this section.*

Every tenant-scoped table carries up to four policies.

```sql
-- platform read: support and super admin both see across tenants
create policy <t>_platform_select on public.<t>
  for select to authenticated
  using ((select app.is_platform()));

-- platform write: super admin only (section 8.4)
create policy <t>_platform_write on public.<t>
  for all to authenticated
  using     ((select app.current_app_role()) = 'super_admin')
  with check ((select app.current_app_role()) = 'super_admin');

-- gym-side read
create policy <t>_tenant_select on public.<t>
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and <read gate>);

-- gym-side write
create policy <t>_tenant_write on public.<t>
  for all to authenticated
  using     (tenant_id = (select app.current_tenant_id()) and <write gate>)
  with check (tenant_id = (select app.current_tenant_id()) and <write gate>);

-- and, only on the tables a member may read
create policy <t>_member_select on public.<t>
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and <member gate>);
```

Every accessor stays wrapped in `(select …)` so the planner evaluates it once as an InitPlan — unchanged from Phase 1, and it matters more now that a predicate makes two calls.

**Why the member policy names the role explicitly.** *(Added after the blind visible-suite author pointed out that it did not.)* The member gate on its own reads a `member_id` claim, and §3 guarantees that only a member token ever carries one. But that guarantee lives in the hook, not in the policy — so a token carrying `app_role: 'trainer'` **and** a `member_id` would read a member's rows through the member policy. On the five `M(all)` tables this grants nothing, since a trainer reads them anyway. On `consents`, `notifications`, `member_devices` and `payments` it is a real widening: a trainer is outside those read gates. The hook never mints such a pair and a client cannot forge one, so this is not an exploitable hole today — it is a policy whose correctness depends on a property of a different component. One clause makes each policy self-contained, which is the same argument ADR-047 made for tenant-scoping a constraint that RLS already covered.

**Why the write policy is `for all` and not `for update, insert`.** Postgres policy commands are `ALL`, `SELECT`, `INSERT`, `UPDATE`, `DELETE` — there is no two-command form. `for all` with the write gate on `using` covers insert, update and delete; its `using` also applies to `SELECT`, but permissive policies OR together and the write gate is a subset of the read gate on every row of the matrix, so `SELECT` still resolves to the read gate. No table gets more read access than the matrix gives it.

**Why this is not the shape the first draft had, and why it matters.** With a single `for all` policy whose `using` was the read gate, an `UPDATE` by a caller who may read but not write behaves like this: `using` admits the row, the row is updated, and then `with check` rejects the new version — Postgres raises **`42501`**. Three scenarios in the authorization spec say such an update "SHALL affect **zero rows**": a manager promoting itself on `staff`, front desk repricing a `plans` row, and `platform_support` updating a gym's data. Under the old shape all three raise instead.

That is not a spec defect to be edited away. **Zero rows rather than an error is Phase 1's established, documented and tested semantics** — `docs/data-model.md` argues it explicitly: *"Zero rows, not an error — a policy that raised would let a caller tell 'nothing here' apart from 'wrong tenant'."* An error on update is an existence oracle inside the tenant, which is a smaller version of exactly what ADR-047 was about. And decisively: two blind authors wrote their assertions from the spec, so editing the spec to match the implementation would be tests following code, which is the one thing hard rule 10 exists to prevent.

Splitting read from write gives the stated behaviour on every path: a permitted `SELECT` passes the read policy; a forbidden `UPDATE` fails the write policy's `using` and touches **zero rows**; a forbidden `INSERT` still raises `42501`, because there is no existing row for a `using` clause to filter and `with check` is the only gate an insert meets. The specs say exactly that, per operation, and now they are achievable.

The cost is one extra policy per table. The final count is **147** — `_platform_select` 36, `_platform_write` 32, `_tenant_select` 35, `_tenant_write` 30, `_member_select` 14 — against 86 under the single-policy shape. That is the price of the semantics being uniform, and a policy is cheap.

**No policy admits a command the grant denies — on either side.** *(This paragraph exists because a blind author found the hole and neither of the other two did.)* Four tables grant `authenticated` `select` and nothing else: `messaging_wallets`, `messaging_wallet_ledger`, `webhook_events`, `audit_log` (ADR-047, ADR-049). §8.3 justified their gym-side select-only policy by saying a policy permitting what the grant denies is a contradiction a critic should not have to find. **The same argument applies to `<t>_platform_write`, and the first draft did not say so** — it left the platform side reading as if every table got the pair.

So the rule, stated once and covering both sides: **a write policy exists on a table exactly when `authenticated` holds `insert` or `update` on it.** Those four tables therefore carry `<t>_platform_select` and no `<t>_platform_write`. A super admin is an `authenticated` session and holds no write grant there, so such a policy would be inert in any case — the wallet's arithmetic, its ledger, every audit row and every webhook record are written by `service_role`, which is never revoked from and bypasses RLS entirely.

`impersonation_sessions` is **not** one of the four and the distinction is worth being exact about: its grant *is* `select, insert, update` (the history tier), and a super admin genuinely creates sessions through it. It carries `<t>_platform_write`. What it does not carry is `<t>_tenant_write` — a gym may read the record of being impersonated and may not write it — and that is a policy decision, not a grant one. The read-only five are five for two different reasons, and conflating them is how the wrong table ends up writable.

The resulting counts are `<t>_platform_write` on 32 tables and `<t>_tenant_write` on 30, which is less tidy than "every table has both". **The invariant that replaces it is stronger, not weaker**, because it ties two things that must agree: for every table in `public`, if `authenticated` holds neither `insert` nor `update`, then no policy on that table is `for all`, `for insert` or `for update`. A meta-test asserts that over the catalogue, and it keeps holding when a later phase changes a grant.

**Naming.** `<t>_tenant_select`, `<t>_tenant_write`, `<t>_platform_select`, `<t>_platform_write`, `<t>_member_select` — and one sixth name that exists on exactly one table, `impersonation_sessions_impersonator_write` (§6). It is named for its audience like the others; it is not a template, and a second table growing an `_impersonator_write` would be a mistake rather than a pattern. `<t>_tenant_all` and `<t>_platform_all` cease to exist. `docs/data-model.md`'s naming table lists only `<table>_tenant_all`, `<table>_platform_all` and `<table>_tenant_select`, so it takes a `spec:` edit in this change to add the three new patterns — the implementer was right to flag that it does not currently license `<t>_member_select` either.

### 8.2 The four gates, and no fifth

```sql
app.current_app_role()  -- text, never cast; null when the claim is absent
app.is_staff()          -- role in (gym_owner, gym_manager, front_desk, trainer)
app.is_gym_admin()      -- role in (gym_owner, gym_manager)
app.is_front_office()   -- role in (gym_owner, gym_manager, front_desk)  -- i.e. staff who are not trainers
```

plus `app.current_member_id()`, `app.current_staff_id()`, `app.current_impersonation_id()` as claim readers.

Written as functions rather than inline role lists so that changing which roles count as staff is one edit rather than thirty-five. The matrix below uses **only** these four gates plus `= 'gym_owner'`. A table needing a fifth distinct gate is a signal that the table is wrong, not that the vocabulary is too small — raise it rather than inventing `app.can_do_x()`, which is how a per-permission matrix gets built by accident after being explicitly deferred out of v1.

### 8.3 The matrix

`M` in the member column means the member policy exists with gate `member_id = (select app.current_member_id())`; `M(self)` means `id = (select app.current_member_id())`; `M(all)` means **`(select app.current_member_id()) is not null`** — every member of the gym sees every row; `—` means **no member policy is created for this table**, and a member reads nothing from it.

*Revised: `M(all)` first read "the tenant match alone", which was a contradiction the implementer caught. A gate of `true` would hand these tables to any session carrying a tenant claim and no role at all — flatly against the authorization spec's first requirement, that a tenant claim alone grants nothing. `current_member_id() is not null` selects exactly the sessions the hook gives a `member_id` to, and it also satisfies the spec's "a member with no member claim reads zero rows" scenario, which a gate of `true` would have failed.*

| Table | read gate | write gate | member |
|---|---|---|---|
| `organizations` | `is_staff()` | `= 'gym_owner'` | `M(all)` — on `id`, being the tenant itself |
| `organization_settings` | `is_staff()` | `is_gym_admin()` | — |
| `branches` | `is_staff()` | `is_gym_admin()` | `M(all)` |
| `staff` | `is_staff()` | `= 'gym_owner'` | — |
| `members` | `is_staff()` | `is_front_office()` | `M(self)` |
| `plans` | `is_staff()` | `is_gym_admin()` | `M(all)` |
| `coupons` | `is_front_office()` | `is_gym_admin()` | — |
| `memberships` | `is_staff()` | `is_front_office()` | `M` |
| `membership_pauses` | `is_staff()` | `is_front_office()` | — |
| `payments` | `is_front_office()` | `is_front_office()` | `M` |
| `refunds` | `is_front_office()` | `is_gym_admin()` | — |
| `invoices` | `is_front_office()` | `is_front_office()` | — |
| `document_counters` | `is_front_office()` | `is_front_office()` | — |
| `razorpay_accounts` | `is_gym_admin()` | `= 'gym_owner'` | — |
| `razorpay_mandates` | `is_front_office()` | `is_front_office()` | — |
| `attendance` | `is_staff()` | `is_front_office()` | `M` |
| `attendance_corrections` | `is_staff()` | `is_front_office()` | — |
| `qr_sessions` | `is_front_office()` | `is_front_office()` | — |
| `organization_holidays` | `is_staff()` | `is_gym_admin()` | `M(all)` |
| `no_show_cases` | `is_staff()` | `is_staff()` | — |
| `follow_ups` | `is_staff()` | `is_staff()` | — |
| `addon_products` | `is_staff()` | `is_gym_admin()` | `M(all)` |
| `addon_orders` | `is_staff()` | `is_front_office()` | `M` |
| `pt_sessions` | `is_staff()` | `is_staff()` | `M` |
| `consents` | `is_front_office()` | `is_front_office()` | `M` |
| `notifications` | `is_front_office()` | `is_gym_admin()` | `M` |
| `member_devices` | `is_front_office()` | `is_front_office()` | `M` |
| `message_templates` | `is_staff()` | `is_gym_admin()` | — |
| `leads` | `is_front_office()` | `is_front_office()` | — |
| `member_imports` | `is_gym_admin()` | `is_gym_admin()` | — |
| `messaging_wallets` | `is_gym_admin()` | *(select-only policy)* | — |
| `messaging_wallet_ledger` | `is_gym_admin()` | *(select-only policy)* | — |
| `webhook_events` | `is_gym_admin()` | *(select-only policy)* | — |
| `audit_log` | `is_gym_admin()` | *(select-only policy)* | — |
| `impersonation_sessions` | `is_gym_admin()` | *(select-only policy)* | — |
| `platform_users` | **no gym-side policy at all** — the platform pair only, unmodified | — | — |

Thirty-six rows, one per table in `public`. **All thirty-five tenant-scoped tables carry `<t>_tenant_select`** — that is §8.1's shape, not a special case. The five marked *(select-only policy)* above simply carry **no `<t>_tenant_write`**: the four whose grant already withholds insert and update (ADR-047/049), plus `impersonation_sessions`, whose grant permits writes but whose *policy* denies them to the gym, because a gym may read the record of being impersonated and may not author it. Making the policy say what the grant already says removes a policy that permits what the grant denies — the contradiction §8.1 now generalises to the platform side as well.

### 8.4 Decisions inside the matrix that a reader will want justified

- **`staff` is writable only by `gym_owner`.** `staff.role` is the privilege ledger of the gym. A manager who can update it can promote itself to owner, which makes the owner/manager distinction decorative. The cost is that only an owner adds staff; the alternative is that the matrix does not hold.
- **`organizations` is writable only by `gym_owner`** — it carries `status`, `tier` and `trial_ends_at`, which are the platform's commercial relationship with the gym, not the manager's settings.
- **A trainer reads no *transaction* and no personal-contact table.** `payments`, `refunds`, `invoices`, `razorpay_*`, `document_counters`, `consents`, `notifications`, `member_devices`, `coupons`, `qr_sessions` and `leads` are all `is_front_office()` or narrower. A trainer reads members, attendance, memberships, plans, add-on products and orders, PT sessions, no-show cases and follow-ups — the retention loop, which is their job.

  **An earlier draft of this bullet said "a trainer reads no money", and that was false.** A blind critic checked it against the live columns rather than against the sentence: `memberships` carries `price_paise` and `discount_paise`, `addon_orders` carries `unit_price_paise` and `total_paise`, `plans` carries `price_paise`, and `organization_settings` — also `is_staff()` — carries `gstin` and every retention threshold. The matrix is **table-granular**, so a role that needs any column of a table gets all of them. That is a real limit of this design and it is the honest answer to "what intra-tenant read remains that a role should not have": a trainer sees what a membership and an add-on cost. Narrowing it needs column privileges or a view, which is a bigger decision than this phase should make on its own — recorded as OPEN-015 rather than quietly tolerated.
- **`coupons` is not readable by members.** A member who can select every coupon row can enumerate every discount code the gym has ever issued, including ones aimed at lapsed members. It is a pricing leak, not a privacy one, and it is the reason `coupons` sits apart from `plans`.
- **`qr_sessions` is not readable by members** — it holds `token_hash`, and ATT-003 is the requirement that a screenshot of a QR code does not stay scannable. A member who can read the session table can defeat rotation.
- **`no_show_cases` and `follow_ups` are not readable by members.** The red list is a staff-internal judgement about a person; showing a member "you are flagged as a churn risk, contacted twice, outcome: no answer" is a product decision nobody has made. It stays staff-side until someone makes it.
- **`organization_settings` is not readable by members**, though it holds the gym's opening hours, because it also holds `gstin`, `trainer_member_cap` and every threshold the retention engine runs on. A member-facing subset belongs in a Route Handler or a view, not in a column-level grant.
- **Members read no `staff` rows.** `staff` carries `phone`, `email` and `role` for every employee. **Named consequence:** ADD-002 requires a member to see a PT trainer's qualification before purchase, and this matrix makes that impossible to do by direct read. Phase 6 must serve it from a Route Handler. That is written here so Phase 6 finds it in the contract rather than discovering it in a failing test.
- **`invoices`, `refunds` and `membership_pauses` have no member policy because they have no `member_id` column**, and the tenancy spec forbids a policy expression referencing any table but its own — so a member gate would have to be a join, which is not available. A member reading their own invoice goes through a Route Handler in Phase 5. **No column is added to these tables in Phase 2**; adding one to satisfy a policy is a schema change driven by an access-control convenience, and it should be argued on its own merits if Phase 5 wants it.
- **The platform write side narrows to `super_admin`.** `<t>_platform_select` carries `is_platform()` — support reads everything, which is its job — and `<t>_platform_write` carries `current_app_role() = 'super_admin'`. Across all thirty-six tables that is what finally makes `platform_support` and `super_admin` different, and it costs one policy per table.
- **`platform_users` needs no special case, and that is a change from this document's first draft.** It was going to take a bespoke pair, `platform_users_super_admin_all` and `platform_users_support_select`, because under Phase 1 a support account could update its own row to `super_admin` and the old single `_platform_all` policy could not express the difference. Once §8.1 split platform read from platform write, the bespoke pair became **identical in meaning to the template**: `_platform_select` on `is_platform()` lets support read the roster, `_platform_write` on `= 'super_admin'` stops it writing its own row. So `platform_users` carries the ordinary platform pair and no gym-side policy at all, and the schema is left with no policy named `_all` anywhere. The implementer noticed the leftover names and asked; the right answer was to delete the special case rather than rename it.

### 8.5 Members write nothing directly

**In v1 a member session holds no write path through RLS on any table.** Every member mutation — registering a push token, withdrawing a consent, editing their own profile — goes through a Route Handler, per `docs/architecture.md` ("mutations go through Route Handlers; reads go direct through `supabase-js` with RLS").

The lazy reading of that architecture note is that no session needs write policies at all. That is wrong, and stating why prevents someone acting on it: a Route Handler should carry the **caller's** JWT so RLS still applies to its writes, escalating to `service_role` only where genuinely required (webhooks, cron, audit). Staff write gates therefore stay real. Members simply have no v1 flow that writes directly, so they get no write policy, and the two Route Handlers that will need one (`member_devices` in Phase 3, `consents` in Phase 6) are named here rather than discovered.

### 8.6 Index rule 3, discharged by measurement

`docs/data-model.md`: *"Every column appearing in an RLS policy predicate is indexed … it stops being automatic the moment a policy grows a second term."* Phase 1 discharged it through rule 1 because `tenant_id` was the only term. Every `member_id` in the matrix above is now a policy term.

**Rule 3 governs `using`, not `with check`.** *(Stated because the impersonator policy above puts `ended_at` in a `with check` and would otherwise trip the meta-test.)* The rule exists so that a predicate which **selects rows** has an index behind it. A `using` clause does that and is covered. A `with check` clause is evaluated against a single row that is already in hand — the one being written — so it drives no scan and an index would serve nothing. The meta-assertion reads `polqual` and not `polwithcheck`, deliberately.

**Measured against the live schema: every table with a member gate already has an index leading with `member_id` or with `(tenant_id, member_id)`** — `attendance`, `memberships`, `payments`, `notifications`, `member_devices`, `consents`, `addon_orders`, `pt_sessions`. (`no_show_cases` and `razorpay_mandates` carry a `member_id` column and are indexed on it, but the matrix gives them **no member gate**, so they are not part of this obligation — the distinction between having the column and having the policy term is the whole of index rule 3.) `members`' gate is on `id`, its primary key. `organizations`' is on `id`, likewise. **Phase 2 therefore adds no index for the matrix**, and the meta-test that asserts rule 3 must accept a standalone `member_id` index as satisfying it — the same distinction rule 2 already makes.

## 9. The first `super_admin` (OPEN-001)

The gym self-signup flow requires super-admin approval, so the platform cannot bootstrap its first admin through it. The answer must not become a general-purpose way to create admins later, which is the whole difficulty.

**A manually dispatched GitHub workflow, refusing to run twice.** The same pattern as the seed (ADR-034): `workflow_dispatch`, an email as input, running against Cloud with the CI credentials. It resolves `auth.users` by that email — so the human must already have signed up through the ordinary email flow, and the workflow never creates an auth identity — and inserts one `platform_users` row **only if `platform_users` is empty**.

The emptiness check is the entire safety property, and it is a `where not exists` in the statement rather than a check in a script: after the first row exists the workflow is inert, permanently, and running it again is a no-op rather than a second admin. Every subsequent platform account is created by an existing `super_admin` through the ordinary `platform_users_platform_write` policy, which is auditable and revocable. A backdoor that closes itself after one use is not a backdoor.

## 10. Auth configuration

`supabase config push` (CLI 2.110.0) can push `config.toml` to the linked project. **It is the wrong tool here, and the reason is worth stating because it is the obvious choice.**

`config push` pushes the *whole file*. This repo's `config.toml` is 414 lines of Supabase's local-development defaults — `site_url = "http://127.0.0.1:3000"`, `additional_redirect_urls = ["https://127.0.0.1:3000"]`, a local SMTP block, storage and realtime sections — none of which has ever been reconciled against what the Cloud project actually has. Pushing it to enable one hook would silently set a production project's site URL to localhost, which breaks every email link the moment staff email sign-in is used. There is no `--dry-run`.

**Instead: a manually dispatched GitHub workflow that PATCHes exactly the fields this phase decides**, against `PATCH /v1/projects/{ref}/config/auth`, using the `SUPABASE_ACCESS_TOKEN` repo secret. Same pattern as the seed (ADR-034): `workflow_dispatch`, CI credentials, one reviewable file. The body carries only:

```json
{ "hook_custom_access_token_enabled": true,
  "hook_custom_access_token_uri": "pg-functions://postgres/app/custom_access_token_hook",
  "jwt_exp": <the chosen lifetime> }
```

Three fields changed, nothing else touched, and the diff is the file. `config.toml` is updated in the same change so the repo still *describes* the project truthfully — it is the record, not the mechanism, until someone reconciles the other 400 lines deliberately.

**A known unknown:** an open Supabase issue reports the Management API rejecting a `send_email` hook PATCH with "Auth Hooks can only be configured on Team or Enterprise Plans", on a project where the Dashboard had already enabled it. Whether the same gate applies to `hook_custom_access_token_*` is not established. If the PATCH is refused for that reason, the fallback is the Dashboard toggle, done once by the owner and recorded — not a wholesale `config push` sneaked in as a workaround.

Settings this phase decides: `[auth.hook.custom_access_token]` enabled with the `app`-schema URI; `[auth] jwt_expiry` (section 7); phone sign-in for members and email sign-in for staff.

**A stated gap, not a deferral.** No SMS provider credential exists — `[auth.sms.*]` cannot be enabled against a real provider, so the member phone-OTP path is **configured but not exercisable end to end in this phase**. Staff email sign-in runs on Supabase's default mailer, which its own documentation calls unsuitable for production; OPEN-004 (transactional email provider) is the decision that fixes it, and this is the evidence for pulling it forward rather than leaving it in Phase 6.

## 11. What this phase does not build

- **No Route Handlers and no `packages/api-client`.** `docs/architecture.md` defers `api-client` to "Phase 2" on the reasoning that there is nothing to generate until Route Handlers exist. There are still none. The deferral moves to Phase 3 and OPEN-002 is amended to say so, rather than being silently carried.
- **No per-permission role matrix.** Roles are the unit. Section 8.2's "no fifth gate" rule is what keeps it that way.
- **No UI, no gym-switching screen, no impersonation banner.** The banner is a Phase 7 obligation that `docs/security.md` already records; Phase 2 supplies the claim it reads.
