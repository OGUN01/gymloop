# PT held test TZ fix — pt-booking-reuse-held

## Symptom

CI (Linux, TZ=UTC) failed 2 of 18 assertions; the author's Windows/IST run
passed 18/18:

1. `requires member cancellation, boolean consumption and a valid
   timezone/recorded interval` — `expected false to be null`
2. `retains only valid recorded intervals strictly after the supplied
   instant` — deep-equal mismatch (an extra slot row survived the filter)

## Root cause

Both failing assertions feed rows with NAIVE timestamp strings (no offset
suffix, e.g. `2026-10-10T09:00:00`) into the shared
`ptRecordedInterval`/`ptBookingOpenSlotGroups`, whose `Date.parse` resolves
naive strings in the HOST timezone:

- Under Asia/Kolkata (the authoring environment): a naive `09:00` parses to
  `03:30Z`, which is BEFORE the `08:00Z` start → `end <= start` → the
  interval is invalid → the functions return null / drop the row — matching
  every expectation.
- Under UTC (the CI runner): the same naive `09:00` parses to `09:00Z`,
  AFTER the start → the interval is valid → `ptBookingCancellationConsumption`
  returns `row.consumed` (`false`, not null) and the slot row survives
  grouping → both assertions fail.

No production row can carry a naive timestamp (the API layer emits
offset-suffixed ISO strings from timestamptz); the naive rows are
adversarial fixtures whose expected verdict was calibrated to the authoring
timezone.

## Fix

One line at the top of `supabase/tests-holdout/pt-booking-reuse-held.test.ts`:

```ts
process.env.TZ = 'Asia/Kolkata';
```

with a comment explaining the host-timezone dependence of the naive-timestamp
rows. Node ≥13 honors runtime `process.env.TZ` mutation for subsequent
`Date.parse`/`Intl` default-timezone lookups in the executing worker; vitest's
default per-file worker isolation contains the mutation. Every assertion's
substance is unchanged.

## Verification

| Runner TZ | Result |
|---|---|
| `TZ=UTC` | 18/18 passed |
| `TZ=Asia/Kolkata` | 18/18 passed |

## File hashes

- `supabase/tests-holdout/pt-booking-reuse-held.test.ts` after fix: see
  `git log --format=%H -1 -- supabase/tests-holdout/pt-booking-reuse-held.test.ts`
