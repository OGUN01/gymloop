# SLF private preparation capability — mechanical implementation declaration

Frozen 2026-10-04 before independent metadata regressions and the new source
seam. Implements the already-frozen current-defense declaration; changes no
approver, allowance, membership entitlement, source policy or public RPC.
Existing independently committed behavioral regressions are `8598007a`.

Reuse existing `slf_freeze_prepare`, `slf_freeze_finish`, `slf_freeze_lock`
and `enforce_freeze_source_consistency` signatures. Neither an ordinary GUC,
advisory marker, caller temporary object, timestamp guess nor caller-supplied
actor is preparation authority. These existing granted helpers must separately
validate the original actor and all current locked business evidence.

The new private relation is `app.slf_freeze_preparations`. Exact columns:
`transaction_id text,tenant_id uuid,actor_user_id uuid,command_key uuid,
request_id uuid,action text,expected_revision bigint,facts jsonb,
prepared_at timestamptz,source_pause_id uuid`. The optional source binding is
null before adoption inserts its source; all other fields are non-null.
Transaction identity is server-derived full `pg_current_xact_id()::text`, never
32-bit xmin or caller text. Actor/tenant derive from validated current identity.
Action and normalized facts must agree with the already-validated operation;
facts bind replay input and grant no authority over live request/source data.

Primary key is `(transaction_id,tenant_id,actor_user_id,command_key)`.
Tenant-leading `(tenant_id,request_id,transaction_id)` index supports scoped
access. Bind tenant/request to their real rows with tenant-preserving FKs.
Enable RLS with no session policies and revoke ALL from PUBLIC, anon,
authenticated and service_role. Only existing narrow postgres-owned definers
may manipulate this state. There is no API, new public helper or session grant.

Prepare writes only after all actor/resource/revision/commercial gates, under
the shared resource and evidence locks. Finish requires this exact current-
transaction actor/request/action/key/revision/facts capability and revalidates
current locked evidence; guessed/source-swapped/mismatched or absent preparation
refuses without metadata/audit changes. Successful finish consumes its row.
Abandoned committed preparation is unusable in any future transaction and may
be cleaned by prepare only for that validated actor/tenant; cleanup never revokes
another current transaction or changes request/pause/command/audit history.

For adoption, the source BEFORE INSERT hook binds exactly one matching new
source to current prepared adoption. It compares tenant/member/membership,
interval/reason and real requesting staff, refuses ambiguous preparation and
never adopts an already-existing source, even one inserted earlier in this
transaction. Finish requires that exact bound id and current reciprocal facts.

Declare four migration-installed triggers using the existing consistency
function, with empty search path and no added session EXECUTE:

- `membership_pauses_freeze_source_lock`: BEFORE INSERT/UPDATE/DELETE.
- `member_freeze_requests_source_consistency`: BEFORE INSERT/UPDATE.
- `membership_pauses_freeze_source_deferred`: CONSTRAINT AFTER INSERT/UPDATE/DELETE,
  DEFERRABLE INITIALLY DEFERRED.
- `member_freeze_requests_source_deferred`: CONSTRAINT AFTER INSERT/UPDATE,
  DEFERRABLE INITIALLY DEFERRED.

Retain the existing source AFTER consistency hook as an immediate check.
BEFORE source hook takes the same member resource and binds preparation;
every source/request writer retains exact identity/provenance and terminal
rules. Deferred hooks verify reciprocal decision truth at transaction completion.
Existing ordinary source RLS/budget/approver guards are neither replaced nor
elevated by the metadata hook.

Use the same transaction advisory resource in all writers. A nonblocking
resource acquisition refuses with existing GL066 when another transaction owns
it, before further effects, preventing a source-row-first/request-path lock
cycle. Evidence locks remain held until completion; a busy refusal neither
consumes a key nor proves success. Retrying preserves original command facts.
No new SQLSTATE or retry of an unknown committed outcome is introduced.

Register relation/index/triggers before building them. Independent authors
verify exact private scope, RLS, grants, FKs and transaction-key metadata; the
existing real-operation regressions verify no extra helper authority, replay,
overlap/allowance and atomic source/request decisions. No mirror acceptance,
extension mutation, Cloud commit or held disclosure to the builder is allowed.
