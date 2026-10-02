# Guardian handover provenance — owner decision

Status: owner approved in the campaign chat on 2026-10-02. GRD implementation
stays paused until the amended contract and independent tests are committed.

## Defect in the fixed trigger shape

GRD-012 permits account handover only for a binding made through a guardian
invite. GRD-013 stores that provenance in `members.guardian_linked_at`, but the
fixed marker trigger runs only when `user_id` changes. Existing member write
privileges therefore permit a front-office caller to put a timestamp on an
already-bound adult row without changing its user id. The subsequent owner
handover command would mistake that adult's own account for a guardian account.
The existing INV binding guard watches user_id only, so it does not stop this.
The orchestrator and separate blind implementer independently identified the gap.

## Concrete amendment

Expand the existing `members_guardian_marker` trigger, without adding a new
helper or policy, to **BEFORE INSERT OR UPDATE OF user_id, guardian_linked_at,
FOR EACH ROW**, with no WHEN clause (`tgtype = 23`). Keep the same private invoker
`app.members_guardian_marker()`, empty search_path, postgres owner, no public
execution grant.

For a caller outside INV's existing trusted writer boundary, an INSERT with a
non-null marker, or an UPDATE changing the marker in either direction, raises
`42501`, detail `guardian_binding_command_required`. Null-marker insertion and
unchanged-marker updates remain allowed under existing RLS/privileges. A forged
transaction setting cannot authorize a caller. The unchanged INV guard retains
its existing refusal order when a statement also attempts a user-id change.

Trusted writers follow the existing INV boundary: current_user postgres, or
current_user service_role with no Auth subject. The verified invite definer may
stamp the gym-local known minor's successful guardian binding; ordinary
adult/unknown-age redemption stamps null. Unlink, handover and operator rebinding
continue to clear the marker. Clearing on a trusted user-id change uses value
comparison (IS DISTINCT FROM), preserving original GRD-013: if the marker value
did not change, clear it even if the UPDATE explicitly assigns the old timestamp.
The provisioning tool still never sets a marker.
This preserves the existing infrastructure trust assumption; it does not claim
that a compromised privileged credential cannot forge database provenance.

No role, policy, table privilege, contact/consent behavior, binding uniqueness,
handover age requirement, public command or UI interaction is broadened.

## Independent tests before resuming

Separate visible and holdout authors amend their own GRD suites and pin the exact
trigger shape. Cover direct marker-only forgery on an adult's own binding,
tampering with a real guardian marker in either direction, non-null INSERT,
unchanged updates, null insertion, forged transaction settings and inappropriate
service-role-with-subject calls; ensure values, sessions and audit stay unchanged
on refusal. Verify successful minor/ordinary redemption and all trusted clearing
paths keep their existing outcomes. Commit this focused test amendment before
the separate implementer resumes; retain fresh identity/RLS review and all gates.

This completes the original guardian-only handover requirement. It changes the
frozen trigger shape and therefore needs an explicit owner decision.
