# Refund retry, money-refusal precedence and financial-audit contract

Status: **frozen contract under ADR-111, 2026-09-10**. This makes the accepted
`REF-001` through `REF-005` and `ERR-001` through `ERR-003` requirements in
`docs/planning/phase5-remaining-draft.md` implementable. It also closes the
existing INT-003 gap for `payments` and `refunds` under the delegated decision
recorded for this unit. It is not an OpenSpec change, a migration, or permission
to edit tests.

The implementation must remain one money-integrity unit: refund idempotency,
the payment/refund project-owned refusal order, and financial audit triggers
land together. Visible and holdout authors derive tests independently from the
frozen contract before an implementer reads either suite. Migrations are applied
by CI only.

## Scope and preserved behaviour

This unit changes only these observable facts:

- a product refund submission has a stable request key and an exact-replay
  result;
- reuse of that key for different refund facts has stable refusal `GL048`;
- the order among the named project-owned payment and refund refusals is fixed;
- every successful `payments` or `refunds` row insert or update writes one
  append-only `audit_log` event.

Everything else stays as currently specified. A refund remains a new row and
does not mutate its payment. The refund total cannot exceed money that arrived;
`failed` refunds remain outside that total; a completed refund cannot be
demoted; only the acting owner or manager may create a product refund; and the
payment/refund tables remain non-deletable to `authenticated`.

This unit does not add a refund status transition graph, require a key from
provider or trusted database writers, change the payment form's existing
duplicate UX, backfill audit history, or decide a general ordering among RLS,
privileges, foreign keys, checks, indexes and triggers.

## Normative requirements

### REF-001 — One request, one refund

WHEN an owner or manager submits the product refund form, THE SYSTEM SHALL send
a stable `idempotencyKey` with that request. Repeating the request with the same
key, serially or concurrently, SHALL produce one `refunds` row, return that same
row's id, and produce one `refund.created` audit event.

An equivalent replay is a read of the existing result. It SHALL NOT update the
refund, touch `updated_at`, or write another audit event.

### REF-002 — Exact replay or explicit conflict

The facts bound to a refund request key are:

1. the gym, by the verified `tenant_id` claim;
2. `payment_id`;
3. `amount_paise`;
4. `currency`;
5. `kind`; and
6. `reason`.

WHEN a key is reused in the same gym and all five stored refund facts after the
gym match the submitted facts, byte for byte after normal request parsing, THE
SYSTEM SHALL return the existing `refund_id` with `replayed = true`.

WHEN the key matches but any one of those facts differs, THE SYSTEM SHALL refuse
with SQLSTATE `GL048`, mapped by the form route to the stable UI error
`idempotency_conflict`. The existing row and its audit history SHALL remain
unchanged.

`status`, `provider_refund_id`, `processed_at`, `initiated_by_staff_id` and `id`
are deliberately not replay-comparison inputs. They describe the recorded
result or its later processing, not the request. A replay after processing
returns the same id and the current recorded result.

The request parser trims outer whitespace from `reason`; it performs no case,
Unicode or internal-whitespace normalization. The UUID parameter is stored in
PostgreSQL's canonical lowercase text form. Key lookup therefore compares that
canonical representation, while the five refund facts are compared exactly as
stored with `IS NOT DISTINCT FROM`; in particular, the stored reason is exactly
the parser-normalized reason. Because REF-004 does not freeze `reason`, an
authorized later reason edit changes the current replay comparison: the old
text then conflicts and the current text is equivalent. This is explicit rather
than silently adding an unapproved reason freeze or a second stored fingerprint.

### REF-003 — Tenant scope, form nonce and historical nulls

The database SHALL store the key as nullable `refunds.idempotency_key text` and
enforce uniqueness with the partial unique index
`refunds_tenant_id_idempotency_key_key` on `(tenant_id, idempotency_key) WHERE
idempotency_key IS NOT NULL`.

The product receipt page SHALL mint a new cryptographically random UUID for
each render and submit it in a hidden `idempotencyKey` field. The shared refund
request schema SHALL require that field and validate it as a UUID before any
database call. A missing, blank, malformed or non-UUID form nonce SHALL redirect
back with `error=invalid` and write nothing.

The route SHALL store the submitted UUID itself. It SHALL NOT compose the key
from the amount or other refund fields: reuse with changed facts must be
observable as `GL048`, rather than evaded by silently manufacturing a new key.

A successful form post redirects to a freshly rendered receipt and therefore
mints a fresh key. That is how an owner intentionally records a second partial
refund with otherwise identical facts. A network retry or double click reuses
the original request body and key.

Existing refunds SHALL receive `NULL`, with no backfill. `NULL` values do not
conflict with one another. An existing null key SHALL remain null: REF-004 makes
`NULL` to non-null an immutable-key change. Product submissions require a key;
the column remains nullable for historical rows and non-product trusted flows.

### REF-004 — Immutable identity and unchanged authorization

After a refund exists, changes to any of these columns SHALL be refused with
`GL041`: `id`, `idempotency_key`, `payment_id`, `amount_paise`, `currency` or
`kind`. This extends the existing immutable-record clause; it does not create a
new refusal family.

`refunds_tenant_write` remains gated by the canonical `app.is_gym_admin()`
predicate. The product RPC SHALL check that same accessor before it performs an
insert or a replay lookup. It SHALL also require a real `staff_id` from the
verified JWT and SHALL accept neither tenant nor staff identity as an argument.
A bare platform session is not a product refund caller. An impersonating token
deliberately has no `staff_id`, so its gym-owner preview remains read-only for
this financial action: the RPC refuses it with `42501` before keyed lookup and
never invents or resolves a staff id for the platform actor.

At the database boundary an unauthorized RPC caller SHALL receive `42501` and
SHALL NOT be told whether a request key exists. At the product boundary,
`staffFormParsed` stops a token with no real `staff_id` first with its existing
`unauthorized` / `not_signed_in` envelope, so an impersonating preview never
reaches the RPC. A caller in another gym cannot collide with or select the row
because the unique key is tenant-scoped and the function remains under the
caller's RLS and privileges. The RPC authorization check supplements the table
policy with the same canonical predicate; it does not replace or restate the
role vocabulary.

### REF-005 — Only a proven replay is success

The system SHALL treat a duplicate as success only after it has read the row
for the same tenant and request key and proved the REF-002 facts equivalent.

The database operation SHALL name only
`refunds_tenant_id_idempotency_key_key` as its conflict target. Therefore a
different unique violation, a missing replay row, a replay lookup failure, an
audit failure, or any policy/constraint/trigger failure propagates as a
failure. The form route may translate failures into its existing short messages,
but SHALL NOT remove the error and SHALL NOT report success merely because the
SQLSTATE was `23505`.

A failed original attempt stores no refund and consumes no key. Retrying the
same key after the underlying failure is corrected may create the refund.

### ERR-001 — Payment refusal order

For one candidate payment row that simultaneously violates multiple applicable
project-owned payment rules, the first applicable refusal SHALL be:

1. `GL038` — immutable id and paid-record freeze;
2. `GL042` — member/membership identity;
3. `GL039` — legal payment status transition or an insert that arrives already
   `refunded`/`reversed`;
4. `GL034` — actor attribution; then
5. `GL035` — manual/provider separation.

Rules that do not apply to the operation are skipped. For example, the paid-row
freeze does not apply to an ordinary insert, while the all-status id freeze
does apply to an update of a created row.

The order is total among these five rules. In pairwise form: `GL038` beats each
later code; `GL042` beats `GL039`, `GL034` and `GL035`; `GL039` beats `GL034`
and `GL035`; and `GL034` beats `GL035`.

### ERR-002 — Refund refusal order

For one candidate refund row that simultaneously violates multiple applicable
project-owned refund rules, the first applicable refusal SHALL be:

1. `GL041` — immutable id/request/money facts or the completed-status rule;
2. `GL040` — actor attribution; then
3. `GL036` — money-arrived and total-ceiling rules.

The order is total among these three rules: `GL041` beats `GL040` and `GL036`,
and `GL040` beats `GL036`. `GL048` is a request-key reuse refusal issued by the
RPC when no new row is written; it is outside this row-rule order.

### ERR-003 — Boundary of the ordering promise

ERR-001 and ERR-002 apply per candidate row and only among the named
project-owned rules. They make no precedence claim over PostgreSQL privileges,
RLS, `NOT NULL`, checks, enum casts, foreign keys, unique or exclusion indexes,
internal constraint triggers, or any other database mechanism.

Tests of the project-owned order must construct a row that passes all excluded
mechanisms. If an excluded mechanism rejects a different shape first, its native
SQLSTATE and timing remain valid.

For a multi-row statement, every individual row has the rule order above. The
contract does not choose which physical row PostgreSQL evaluates first, so if
different rows violate different rules the statement may surface either row's
otherwise-correct first refusal.

### AUD-001 — Financial rows write append-only audit events

AFTER every successful row `INSERT` or `UPDATE` on `payments` or `refunds`, THE
SYSTEM SHALL write exactly one row to `audit_log`, in the same transaction, with
these exact actions and record types:

| table operation | `action` | `record_type` | `record_id` |
|---|---|---|---|
| insert payment | `payment.created` | `payment` | payment id |
| update payment | `payment.updated` | `payment` | payment id |
| insert refund | `refund.created` | `refund` | refund id |
| update refund | `refund.updated` | `refund` | refund id |

On insert, `before` SHALL be null and `after` SHALL contain the financial
summary. On update, both summaries SHALL be present. An accepted update writes
one event even when the caller writes a value back unchanged; the audit records
the accepted operation rather than guessing intent from a diff.

A denied or rolled-back write SHALL leave no audit row. An equivalent keyed
refund replay is a `SELECT`, not an update, and SHALL leave no audit row. There
is no historical backfill for payments or refunds that predate this migration.

### AUD-002 — Actor and financial summary

For a caller with a verified end-user JWT, each audit event SHALL take
`actor_user_id` from `auth.uid()`, resolve `actor_role` safely against the
canonical Postgres enum, and copy `app.current_impersonation_id()` into
`impersonation_session_id`. A malformed or absent role claim makes
`actor_role` null rather than aborting the financial write with an enum cast
error.

For a trusted context with no verified end-user Gymloop claims, all three actor
fields SHALL be explicitly null. The audit writer SHALL NOT infer this from
`row_security_active()` inside the security-definer function: there the current
effective role is the function owner. It SHALL derive the distinction from the
canonical JWT accessors. It also SHALL NOT invent a human actor from
`recorded_by_staff_id` or `initiated_by_staff_id`: a webhook, migration or other
trusted writer may have no authenticated user, and the row's attribution is
already present in the summary.

The payment summary SHALL contain these domain columns and SHALL exclude only
the storage timestamps `created_at` and `updated_at`:

`member_id`, `membership_id`, `mandate_id`, `coupon_id`, `amount_paise`,
`currency`, `status`, `method`, `provider`, `provider_order_id`,
`provider_payment_id`, `receipt_number`, `recorded_by_staff_id`,
`idempotency_key`, `paid_at`, `failed_reason`, `notes`.

The refund summary SHALL contain these domain columns and SHALL exclude only
the storage timestamps `created_at` and `updated_at`:

`payment_id`, `kind`, `amount_paise`, `currency`, `status`,
`provider_refund_id`, `reason`, `initiated_by_staff_id`, `processed_at`,
`idempotency_key`.

`audit_log.tenant_id` SHALL equal the financial row's tenant. For refund events,
`audit_log.reason` SHALL carry the refund row's current reason as well as the
reason appearing in the summary; for payment events it SHALL be null. The
duplication uses the existing audit shape deliberately: `reason` is the
human-readable audit reason, while `before`/`after` make a change reviewable.

## Database and API convention

### One security-invoker RPC owns insert-or-replay

Add the exposed function:

```sql
public.record_refund(
  p_payment_id uuid,
  p_amount_paise bigint,
  p_currency text,
  p_kind public.refund_kind,
  p_reason text,
  p_idempotency_key uuid
)
returns table (refund_id uuid, replayed boolean)
```

The function is `volatile`, `security invoker`, and `SET search_path = ''`.
Revoke execution from `PUBLIC` and `anon`; grant it only to `authenticated`.
It does not accept `tenant_id`, `initiated_by_staff_id`, `status`, an id, or a
provider refund id.

Its transaction is:

1. Require `app.is_gym_admin()`, non-null tenant/staff claims and a non-null
   UUID request key before any keyed read. Authorization failure is `42501`; a
   null key is invalid input and stores nothing.
2. Insert a `requested` refund using `app.current_tenant_id()` and
   `app.current_staff_id()`, storing the UUID's canonical text form. Use `ON
   CONFLICT (tenant_id, idempotency_key) WHERE idempotency_key IS NOT NULL DO
   NOTHING RETURNING id` so only the intended partial unique index is handled.
3. If an id was returned, return it with `replayed = false`. The ordinary table
   policy, refund triggers and financial audit trigger all apply.
4. If no id was returned, select by the current tenant and key under the
   caller's RLS. Compare every REF-002 fact with `IS NOT DISTINCT FROM`.
5. Return that id with `replayed = true` only on exact equivalence. Otherwise
   raise `GL048` without changing anything.

No preflight existence query is permitted. With two concurrent requests,
PostgreSQL's named conflict target serializes on the unique index. Equivalent
requests return one id and create one row/audit event. For concurrent requests
with different facts, whichever insert wins becomes the recorded request and
the other receives `GL048`; the contract does not assign a winner before the
database does.

The product route obtains `amount_paise` through the existing
`paiseFromRupees` conversion, checks `kind` against generated
`Constants.public.Enums.refund_kind`, and supplies `DEFAULT_CURRENCY` explicitly
as the current product refund currency. Currency is not a client-editable form
field. This preserves the current INR route behaviour while making the replay
fact explicit; this unit does not introduce a new cross-currency refund rule.

The route calls `.rpc('record_refund', ...)` instead of inserting directly. A
successful first call and an equivalent replay both redirect to the same
receipt without an error. The receipt already renders the returned refund row;
no new duplicate warning is required by REF-001. `GL048` maps to
`error=idempotency_conflict`. Existing mappings remain:

| database result | form result |
|---|---|
| `42501` | `not_permitted` |
| `GL036` | `exceeds_payment` |
| `GL040` | `refund_not_yours` |
| `GL041` | `refund_is_a_record` |
| `GL048` | `idempotency_conflict` |
| any other error, including an unhandled `23505` | `refund_failed` |

### One function owns each row's refusal order

Implement ERR-001 by making `app.enforce_payment()` the single after-row
function containing all five project-owned payment refusal families in the
specified clause order. Fold the all-status id freeze from
`app.enforce_payment_identity()` and the insert arrival-status rule from
`app.enforce_payment_arrival_status()` into it, then drop those two redundant
triggers and functions. Keep stamping and membership-extension triggers in
their existing roles. This is smaller and more reviewable than trying to encode
a five-way clause order through alphabetically sorted trigger names.

Implement ERR-002 inside the existing `app.enforce_refund_total()`: extend its
first `GL041` clause with `id`, `idempotency_key`, `currency` and `kind`, keep
the completed-status `GL041` beside it, move the applicable `GL040` attribution
checks ahead of both `GL036` checks, then run money-arrived and ceiling checks.
Trusted contexts skip the claim-based `GL040` clause and still meet the
invariant `GL041`/`GL036` rules.

Both functions remain `security invoker`, after-row triggers, with an empty
search path. That preserves the existing policy-first design where PostgreSQL
allows it, without making an ordering promise about any excluded mechanism.

### One non-callable elevated writer owns money audit

Add one private trigger function, `app.audit_money_change()`, and attach it as
an `AFTER INSERT OR UPDATE FOR EACH ROW` trigger to both financial tables. Name
the triggers `payments_money_audit` and `refunds_money_audit`, after the
respective enforcement trigger in this project's measured same-timing,
same-level name order.

The function is `security definer`, owned by the migration owner, and `SET
search_path = ''`; every table, function, enum and catalog reference is fully
qualified. It may only insert the AUD-001/AUD-002 shape into `public.audit_log`.
Revoke function execution from `PUBLIC`, `anon` and `authenticated`; trigger
invocation needs no user-callable elevated path. This follows the existing
`app.audit_impersonation_session()` pattern because `audit_log` correctly gives
`authenticated` no insert privilege.

An audit insert that fails aborts the financial mutation in the same
transaction. If a later trigger rejects the financial row, PostgreSQL rolls the
earlier audit insert back with it; the observable rule remains “accepted row,
one event; refused row, none.”

## Schema, generated-type and registry impact

One CI-applied forward migration is required. It:

- adds nullable `public.refunds.idempotency_key text` with no default or
  backfill;
- creates `refunds_tenant_id_idempotency_key_key`;
- creates and privileges `public.record_refund(...)`;
- reorders/consolidates the payment and refund project-owned trigger functions;
- creates the one private audit writer and its two triggers; and
- does not alter an enum or rewrite a historical payment/refund row.

After CI applies the migration, regenerate `packages/db/types/database.ts` with
the repository's required Supabase CLI flow; never edit it by hand. The
generated `refunds` Row/Insert/Update types gain nullable `idempotency_key`, and
`Functions.record_refund` gains the RPC argument and result types. Private
`app` functions remain absent because the schema is not exposed.

On a fresh database, the existing seed's first successful payment inserts now
produce trusted-context `payment.created` audit rows. Its later `ON CONFLICT
(id) DO NOTHING` reruns produce no new payment or audit rows. The seed's comments
and any exact audit-count expectations must be updated to describe that
trigger-produced history; the seed must not insert audit rows itself or disable
the audit trigger.

Update `docs/data-model.md`, the relevant archived OpenSpec specs,
`docs/security.md`, `docs/decisions.md` (closing OPEN-031 and OPEN-034), and
`docs/registry.md` in the eventual implementation/archive commits. Registry
changes include the public RPC, `app.audit_money_change()`, the changed
`refundRequestSchema`/`RefundRequest` contract, revised descriptions of
`app.enforce_payment()` and `app.enforce_refund_total()`, and removal of the two
dropped private payment helpers. No new shared constant or hand-written enum is
needed.

## Required acceptance cases for independent authors

The visible and holdout suites must independently cover at least:

- serial and truly concurrent equivalent submissions: one refund id, one row,
  one `refund.created` event;
- concurrent same-key submissions differing in one fact: one winner and one
  `GL048`, without claiming which request wins;
- a separate `GL048` case for each comparison fact: payment, paise, currency,
  kind and reason;
- the same key in two gyms: one refund per gym;
- missing, blank and malformed form keys: invalid before the RPC;
- historical null-key rows coexisting, remaining null, and refusing a key edit
  with `GL041`;
- a fresh receipt render allowing a second intentional, otherwise-identical
  partial refund;
- an equivalent replay after status/processing fields change, returning the
  original id with no update or audit;
- owner and manager success; front-desk, trainer, member, missing-claim and
  other-tenant attempts revealing no keyed result and creating no audit; plus
  an impersonating preview being stopped for lack of a real `staff_id` before
  the product route calls the RPC;
- an original `GL036`, `GL040`, `GL041`, policy, check, foreign-key, audit, or
  unrelated unique failure never becoming replay success;
- every ERR-001 and ERR-002 pair, with excluded PostgreSQL mechanisms made
  valid so the asserted SQLSTATE measures the project-owned order;
- successful payment/refund inserts and updates producing the exact action,
  actor and before/after summary; trusted writes producing explicit null actor
  fields; refused writes and keyed replay producing no audit event; and
- a database assertion that the elevated audit function is not directly
  executable by `anon` or `authenticated`, while its triggers still write the
  event.

The payment-flow skill's duplicate-delivery and provider-unreachable cases
remain required where the implementation touches provider behaviour. This unit
does not add provider calls, so “provider unreachable” must not be simulated as
though recording a manual refund contacted Razorpay.
