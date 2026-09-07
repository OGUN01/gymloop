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

- **A claim is absent, or it is a well-formed value.** Never an empty string, never JSON `null`. Phase 1's accessors `nullif(…, '')` defensively, but a hook emitting `"tenant_id": ""` makes `app.current_tenant_id()` return null on a session that *does* have a tenant — which reads as "sees nothing" and is indistinguishable from a bug. If the hook has no value for a claim, it omits the key.
- **`app_role` is never a value outside the enum.** `app.current_app_role()` casts to `public.app_role`; an unknown label raises `22P02`. That is the correct loud failure and is the behaviour ADR-032 chose for a malformed `tenant_id`.
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

- **If the matched row has `is_active = false`, resolution stops. It does not fall through to the next table**, and the token gets no Gymloop claims. A deactivated super admin must not silently become a member. This is stated because "skip the inactive row and keep looking" is the obvious alternative reading and it is wrong.
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
- **One live session per actor**, enforced by a partial unique index on `actor_user_id where ended_at is null`. Which target the claims point at is then never ambiguous, and the hook needs no ordering rule.
- **The audit rows are written by the database.** A trigger on `impersonation_sessions` writes the start row on insert and the end row on the update that sets `ended_at`. INT-003 requires both. A caller who must remember is a caller who will eventually forget — and `audit_log` is read-only to `authenticated` (ADR-049), so the caller could not write it anyway.
- **Expiry needs no job.** A session past `expires_at` stops being live by the definition above, so the next refresh drops the claims. Nothing sweeps the table. **The asymmetry, stated rather than papered over:** an expired session's *end* audit row is written when someone ends it, not when it expires — so `audit_log` shows starts without matching ends for abandoned sessions, and a reader must use `expires_at` rather than assume an end row exists.

## 7. `is_active` and role changes are load-bearing (OPEN-009)

Two halves, different mechanisms.

**Half one — the claim.** Section 4: an inactive identity gets no claims. That governs every token minted *after* deactivation.

**Half two — the tokens already issued.** A claim is a copy of a row taken at issue time; changing the row changes nothing about a token already in a browser, and Supabase's default access-token lifetime is one hour. Two mechanisms, both required:

- **A trigger revokes live sessions.** On `platform_users`, `staff` and `members`, when `is_active` goes `true → false` **or when `role` changes**, the user's rows in `auth.sessions` are deleted. Deleting the session invalidates the refresh token, so the access token in hand is the last one that user will ever hold. A role change counts because a stale `app_role` claim is a stale privilege, and INT-003 requires an audit row for a role change in any case — the same trigger writes it.
- **A deliberately chosen `jwt_expiry`**, so the residual window is a number someone chose rather than a default nobody read. It goes in `config.toml`. The trade is real and must be recorded: every refresh runs the hook, so a short lifetime is a load decision as much as a security one.

**The residual window is real and must be written down**, not designed away: between the trigger firing and the current access token expiring, a deactivated user still holds valid claims. Any requirement claiming otherwise is false, and a test asserting otherwise is testing a fiction.

**Verify before relying.** That a `security definer` function owned by `postgres` may delete from `auth.sessions` on this project is an assumption until it is replayed against Cloud inside `begin … rollback` (ADR-042). If it cannot, the fallback is recorded as an ADR — not improvised.

## 8. The role matrix

### 8.1 Shape

Every tenant-scoped table carries up to three policies. Two exist today; one is new.

```sql
-- Phase 1's platform policy, write side narrowed (section 8.4)
create policy <t>_platform_all on public.<t>
  for all to authenticated
  using     ((select app.is_platform()))
  with check ((select app.current_app_role()) = 'super_admin');

-- Phase 1's gym-side policy, predicate tightened: being in the gym is no longer enough
create policy <t>_tenant_all on public.<t>
  for all to authenticated
  using     (tenant_id = (select app.current_tenant_id()) and <read gate>)
  with check (tenant_id = (select app.current_tenant_id()) and <write gate>);

-- new, and only on the tables a member may read
create policy <t>_member_select on public.<t>
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id()) and <member gate>);
```

Every accessor stays wrapped in `(select …)` so the planner evaluates it once as an InitPlan — unchanged from Phase 1, and it matters more now that there are two calls per predicate.

**Why the member policy is `for select` and separate.** Permissive policies OR together, so a member's `UPDATE` is governed only by `<t>_tenant_all`, whose read gate is false for a member: the update matches zero rows regardless of the `update` privilege. Writing it as `for all` with a write gate of `false` is the same outcome expressed less clearly.

**Why `<t>_tenant_all` keeps its name.** It is now a staff-side policy, and `tenant_all` reads like a lie. Renaming thirty-five policies costs a churned diff across every RLS test file for a naming improvement. The name stays, `docs/data-model.md` carries the sentence explaining it, and this paragraph exists so a later session does not "fix" it.

### 8.2 The four gates, and no fifth

```sql
app.current_app_role()  -- public.app_role, null when the claim is absent
app.is_staff()          -- role in (gym_owner, gym_manager, front_desk, trainer)
app.is_gym_admin()      -- role in (gym_owner, gym_manager)
app.is_front_office()   -- role in (gym_owner, gym_manager, front_desk)  -- i.e. staff who are not trainers
```

plus `app.current_member_id()`, `app.current_staff_id()`, `app.current_impersonation_id()` as claim readers.

Written as functions rather than inline role lists so that changing which roles count as staff is one edit rather than thirty-five. The matrix below uses **only** these four gates plus `= 'gym_owner'`. A table needing a fifth distinct gate is a signal that the table is wrong, not that the vocabulary is too small — raise it rather than inventing `app.can_do_x()`, which is how a per-permission matrix gets built by accident after being explicitly deferred out of v1.

### 8.3 The matrix

`M` in the member column means the member policy exists with gate `member_id = (select app.current_member_id())`; `M(all)` means the gate is the tenant match alone (the whole gym's rows are visible to its members); `M(self)` means `id = (select app.current_member_id())`; `—` means **no member policy is created for this table**, and a member reads nothing from it.

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
| `platform_users` | **no gym-side policy at all** | — | — |

Thirty-six rows, one per table in `public`. **The four read-only tables plus `impersonation_sessions` carry `<t>_tenant_select` (`for select`) instead of `<t>_tenant_all`**, matching what `impersonation_sessions` already does and matching the naming convention's existing `<table>_tenant_select` entry. Their privilege grant already withholds insert and update (ADR-047/049); making the policy say the same thing removes a policy that permits what the grant denies, which is exactly the kind of contradiction a critic should find and here does not have to.

### 8.4 Decisions inside the matrix that a reader will want justified

- **`staff` is writable only by `gym_owner`.** `staff.role` is the privilege ledger of the gym. A manager who can update it can promote itself to owner, which makes the owner/manager distinction decorative. The cost is that only an owner adds staff; the alternative is that the matrix does not hold.
- **`organizations` is writable only by `gym_owner`** — it carries `status`, `tier` and `trial_ends_at`, which are the platform's commercial relationship with the gym, not the manager's settings.
- **A trainer reads no money and no personal-contact table.** `payments`, `refunds`, `invoices`, `razorpay_*`, `document_counters`, `consents`, `notifications`, `member_devices`, `coupons`, `qr_sessions` and `leads` are all `is_front_office()` or narrower. A trainer reads members, attendance, memberships, plans, add-on products and orders, PT sessions, no-show cases and follow-ups — the retention loop, which is their job.
- **`coupons` is not readable by members.** A member who can select every coupon row can enumerate every discount code the gym has ever issued, including ones aimed at lapsed members. It is a pricing leak, not a privacy one, and it is the reason `coupons` sits apart from `plans`.
- **`qr_sessions` is not readable by members** — it holds `token_hash`, and ATT-003 is the requirement that a screenshot of a QR code does not stay scannable. A member who can read the session table can defeat rotation.
- **`no_show_cases` and `follow_ups` are not readable by members.** The red list is a staff-internal judgement about a person; showing a member "you are flagged as a churn risk, contacted twice, outcome: no answer" is a product decision nobody has made. It stays staff-side until someone makes it.
- **`organization_settings` is not readable by members**, though it holds the gym's opening hours, because it also holds `gstin`, `trainer_member_cap` and every threshold the retention engine runs on. A member-facing subset belongs in a Route Handler or a view, not in a column-level grant.
- **Members read no `staff` rows.** `staff` carries `phone`, `email` and `role` for every employee. **Named consequence:** ADD-002 requires a member to see a PT trainer's qualification before purchase, and this matrix makes that impossible to do by direct read. Phase 6 must serve it from a Route Handler. That is written here so Phase 6 finds it in the contract rather than discovering it in a failing test.
- **`invoices`, `refunds` and `membership_pauses` have no member policy because they have no `member_id` column**, and the tenancy spec forbids a policy expression referencing any table but its own — so a member gate would have to be a join, which is not available. A member reading their own invoice goes through a Route Handler in Phase 5. **No column is added to these tables in Phase 2**; adding one to satisfy a policy is a schema change driven by an access-control convenience, and it should be argued on its own merits if Phase 5 wants it.
- **The platform write side narrows to `super_admin`.** `<t>_platform_all` keeps `is_platform()` on `using` (support reads everything, which is its job) and takes `current_app_role() = 'super_admin'` on `with check`. Across all thirty-six tables that is what finally makes `platform_support` and `super_admin` different, and it costs one clause per table.
- **`platform_users` splits in two.** `platform_users_super_admin_all` (`for all`, gated on `= 'super_admin'`) and `platform_users_support_select` (`for select`, gated on `= 'platform_support'`). Under Phase 1 a support account could update its own row to `super_admin`; this is the other half of OPEN-009 and the reason `platform_users` cannot simply inherit the narrowed template.

### 8.5 Members write nothing directly

**In v1 a member session holds no write path through RLS on any table.** Every member mutation — registering a push token, withdrawing a consent, editing their own profile — goes through a Route Handler, per `docs/architecture.md` ("mutations go through Route Handlers; reads go direct through `supabase-js` with RLS").

The lazy reading of that architecture note is that no session needs write policies at all. That is wrong, and stating why prevents someone acting on it: a Route Handler should carry the **caller's** JWT so RLS still applies to its writes, escalating to `service_role` only where genuinely required (webhooks, cron, audit). Staff write gates therefore stay real. Members simply have no v1 flow that writes directly, so they get no write policy, and the two Route Handlers that will need one (`member_devices` in Phase 3, `consents` in Phase 6) are named here rather than discovered.

### 8.6 Index rule 3, discharged by measurement

`docs/data-model.md`: *"Every column appearing in an RLS policy predicate is indexed … it stops being automatic the moment a policy grows a second term."* Phase 1 discharged it through rule 1 because `tenant_id` was the only term. Every `member_id` in the matrix above is now a policy term.

**Measured against the live schema: every table with a member gate already has an index leading with `member_id` or with `(tenant_id, member_id)`** — `attendance`, `memberships`, `payments`, `notifications`, `member_devices`, `consents`, `addon_orders`, `pt_sessions`, `no_show_cases`, `razorpay_mandates`. `members`' gate is on `id`, its primary key. `organizations`' is on `id`, likewise. **Phase 2 therefore adds no index for the matrix**, and the meta-test that asserts rule 3 must accept a standalone `member_id` index as satisfying it — the same distinction rule 2 already makes.

## 9. The first `super_admin` (OPEN-001)

The gym self-signup flow requires super-admin approval, so the platform cannot bootstrap its first admin through it. The answer must not become a general-purpose way to create admins later, which is the whole difficulty.

**A manually dispatched GitHub workflow, refusing to run twice.** The same pattern as the seed (ADR-034): `workflow_dispatch`, an email as input, running against Cloud with the CI credentials. It resolves `auth.users` by that email — so the human must already have signed up through the ordinary email flow, and the workflow never creates an auth identity — and inserts one `platform_users` row **only if `platform_users` is empty**.

The emptiness check is the entire safety property, and it is a `where not exists` in the statement rather than a check in a script: after the first row exists the workflow is inert, permanently, and running it again is a no-op rather than a second admin. Every subsequent platform account is created by an existing `super_admin` through `platform_users_super_admin_all`, which is auditable and revocable. A backdoor that closes itself after one use is not a backdoor.

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
