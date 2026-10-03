# PT availability and reassignment repair declarations

Frozen engineering boundary, 2026-10-03. Implements the already approved
PTF-008 and PTF-017 without altering booking or money eligibility. Independent
visible and holdout authors must commit tests before the separate SQL builder.

## Production enumeration seam

The forward-only migration is
`20261003170000_pt_front_contract_repairs.sql`. It adds:

```sql
app.pt_availability_grid(
  p_gym_timezone text,
  p_trainer_timezone text,
  p_from date,
  p_to date,
  p_windows jsonb,
  p_session_minutes integer
) returns table (starts_at timestamptz, ends_at timestamptz)
```

The helper is STABLE, SECURITY INVOKER, postgres-owned, with empty search_path.
Revoke all execution from PUBLIC, anon, authenticated and service_role. It reads
no tables, claims, settings, actor or clock; takes no locks and writes nothing.
The timezone catalogue may be consulted for validation. It uses the installed
timezone rules, so it does not claim timezone-database independence.

Both zones must be valid PostgreSQL timezone names. Dates are finite, non-null,
ordered, and span at most 14 inclusive days; invalid dates raise 22023 with
detail `range_invalid`. Session minutes follow the existing policy: integer
15..180, divisible by five. Windows are a JSON array of at most 28 objects with
exactly `weekday`, `startMinute`, `endMinute`, all integer JSON numbers:
weekday 0..6 and 0 <= startMinute < endMinute <= 1440. Same-weekday windows may
touch but may not overlap. Empty windows return no rows. Invalid helper-only
zone, window or policy facts raise 22023. Handle unsupported arithmetic
boundaries explicitly with 22023; introduce no arbitrary calendar-year bound.

Return every distinct absolute start whose organization/gym-local date is in
the requested inclusive range and whose trainer-local weekday and minute are
on a supplied grid: zero seconds, startMinute <= minute, minute + duration <=
endMinute, and (minute - startMinute) modulo duration = 0. Return both instants
of a repeated eligible trainer-local wall time. Nonexistent local times
contribute no candidate; normalization must not invent or duplicate starts.
Order by absolute start. End is start plus the configured elapsed duration.
The helper does not truncate candidates.

`public.read_member_pt_slots` genuinely consumes this helper with the current
member's own pack trainer's windows and server-resolved zones/policy. Preserve
all authorization, private trainer identifiers, own-pack invisibility,
can_book=false -> zero rows, both existing sold-validity boundaries, and
`app.pt_slot_state` as the sole current availability predicate. Apply the
existing 400-row cap after live filtering and ordering. Every returned start
must belong to the requested gym-local days even when gym and trainer dates
differ. No public RPC signature or result shape changes.

`app.pt_slot_state` remains reused: it classifies one supplied instant against
current facts, but cannot enumerate a DST-complete grid. The helper is a real
production seam that permits fixed-date DST proof without changing the clock,
overriding security functions or loosening sold-pack eligibility.

## Reassignment refusal order

Replace `public.reassign_pt_packs` only to enforce PTF-017's target-first order.
After existing identity/basic-input validation, acquire the existing trainer
locks and prove the target is a same-tenant active trainer. Missing, foreign,
inactive or non-trainer targets raise GL055 / trainer_unavailable, including
when both supplied ids are equal. An eligible target equal to source then
raises 22023 / same_trainer. Preserve source inactivity allowance, batch bounds,
complete prevalidation, lock order, sold terms, cancellations, counts, notices,
audit, replay and atomic rollback. Refusal writes nothing.

## Preserved current-day pack boundary

Unchanged Phase-6 `app.enforce_pt_session` additionally requires current
gym-local pack validity on ordinary inserts. PTF-023 does not replace that
function. This repair preserves that inherited boundary; it grants no booking
on a future-start pack before validity begins and changes no waiver or refund
rules. Fixed-date helper tests must remain independent of live pack eligibility.

## Independent acceptance

Use rollback-only SQL suites with real actor fixtures for reader visibility,
gym/trainer date boundaries and reassignment refusal precedence. Verify the
clock-independent production helper with fixed forward and backward DST dates,
ordinary and half-hour transitions, distinct repeated starts, absent gap starts,
grid/duration/boundary validation and grant posture. Cover live reader use and
existing refusal/atomicity behavior without replacing the production clock,
business guards or security functions. Fresh source review and affected/full
local SQL verification follow the separate source build. CI remains the sole
permanent migration applier.
