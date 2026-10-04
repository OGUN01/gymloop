# WSP ordering visible suite hardening — 2026-10-04

File: `supabase/tests/80_whatsapp_consent_ordering.sql`
New sha256: `639ed459347a4f47321aa67514fe645707915fa0944ecbae6e90a13e811df34d`

## Defect captured at runtime (orchestrator diagnostic, rollback-only, stable
snapshot purchase d9d0370c…/whatsapp 771DF6C1…)

The suite aborted with `P0002: Dispatch attempt not found` at
`pg_temp.ordering_contract()` body line 39 (`authorize_whatsapp_dispatch`)
because the implementation's ctid tie-break treats member 101's current
consent (UUID-highest grant 4101, same recorded_at) as the later-inserted
withdrawal 4001. Preparation therefore refuses src_101, claim leases no
attempt for 101, and the unguarded authorize on the absent attempt aborts,
losing every later assertion.

## Edits (no assertion weakened or removed; ordering expectations untouched)

1. `plan(17)` → `plan(19)`; two contract-true assertions added, all 17
   original expectations retained verbatim.
2. Added `claim never leases the withdrawn member 102` (contract-true under
   any correct ordering; clean RED under the ctid defect, which leases 102
   instead of 101 — the old count=3 pin passed spuriously under the defect).
3. Added `claim leased member 101 attempt for final I/O` (attempt presence
   asserted before authorize, per orchestrator guidance).
4. Authorize calls for 101 and for the 109/110 loop are wrapped in
   `begin … exception when others` capturing `sqlstate`/`sqlerrm` into the
   result jsonb; the original `authorized` expectation is still asserted
   (clean RED when the attempt is absent or authorize refuses). No abort
   path remains on the captured runtime defect.
5. Header comment records the hardening and its reason.

## Expected RED under the current defective source (full plan runs)

- Green (table-level truth, defect-independent): both current-consent
  selection pins (107/108), withdrawal-preparation-rejects (113),
  no-attempt-for-102-after-preparation (114), superseded-evidence blocks for
  109/110 and their durable-refusal/no-paid-child/no-debit/sent-preserved
  pins (several pass spuriously under the defect — the refusal happens for
  the mirrored reason).
- Clean RED: preparation admits 101 (queued=true), claim count composition
  via the new 102-never-leased pin, claim pins 4101 evidence, claim leased
  101, final I/O admits 101.

Static check: `check-pgtap-rollback` green for this file. No Cloud SQL run,
no commits.
