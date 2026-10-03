# Demo consent clock correction

Frozen engineering correction, 2026-10-03. The actual rollback-only demo replay
rejects `consents 00000091-0000-4000-8000-000000000001`: the existing consent
invariant records the real server time instead of the requested historical time.
This corrects the fixture clock assumption; existing consent, audit, identity,
money and business requirements remain authoritative.

For the six synthetic cohort marketing rows only, this supersedes the earlier
`R-6` through `R-1` minute recorded_at declaration. All other explicitly declared
fixture clocks continue to derive from original R. The normal consent INSERT
invariant SHALL assign recorded_at and write its genuine consent.recorded audit.
The seed SHALL neither bypass that invariant nor fabricate, edit or backdate
consent/audit history. Existing cohort IDs, grant/withdrawal ordering, version,
source, staff attribution, final consent state and reach remain the same.

On replay, recover each row's original recorded_at from exactly one original
tenant-scoped audit event with action consent.recorded, record_type consent and
the exact consent record_id. Its before snapshot is null; its after snapshot
contains the matching member_id, purpose, granted, version, source,
recorded_by_staff_id and request_key (null for these static inserts). The original
recorded_at must be present, non-null and a finite timestamp. Compare the stored
consent's complete declared logical shape and recorded_at to that original
snapshot. Missing, duplicate or mismatched history SHALL refuse the whole replay.
Never trust a mutated current consent timestamp as its own original reference.

The real timestamps SHALL retain strict append order within each member's
grant/withdrawal sequence. Replays SHALL preserve every original consent row and
audit row without additional writes. No production trigger, permission,
application consent rule, existing member or history may change for this repair.

Independent visible and holdout authors adjust only their own demo fragments
from these public declarations before the separate seed builder resumes. They
verify genuine original audit timestamps, exact attribution and final states,
ordered per-member events and immutable replay. The existing full graph,
foreign-relation, legacy-money and legal-replay checks stay in force. The builder
may read this packet and existing seed/guard source, never either test fragment,
holdouts, receipts or another author's output. Fresh source critique and actual
rollback executions follow. CI remains the only permanent seed applier.
