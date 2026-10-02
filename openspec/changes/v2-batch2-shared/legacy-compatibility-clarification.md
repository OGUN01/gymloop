# Batch 2 legacy compatibility boundaries

Status: mechanical reconciliation of approved PTF/SHP/GRD contracts with existing
constitutional tests. No product, money or permission behavior is newly approved.

## Staff row identifier

PTF-020's four frozen tenant SELECT policies identify a trainer's own rows through
the existing `app.current_staff_id()` accessor. Like `current_member_id`, it
identifies a row; it adds no fifth privilege gate. The central dependency check
may admit it only for the exact tenant SELECT policies on `trainer_profiles`,
`trainer_availability`, `trainer_time_off`, `pt_cancellations`. Every other policy
still rejects this additional dependency. The central matrix continues to require
each full exact PTF predicate and no write/member policy. Unrelated gates,
raw-claim bans and per-row tenant-lookup bans are unchanged.

## Foreign-key indexes

The unchanged every-FK-indexed rule caught five missing PTF indexes. Add these
exact names/shapes, implementing the existing constitutional bar:

- `trainer_profiles_tenant_id_photo_asset_id_idx (tenant_id, photo_asset_id)`,
  partial where photo_asset_id is not null.
- `trainer_time_off_tenant_id_created_by_staff_id_idx (tenant_id, created_by_staff_id)`.
- `trainer_time_off_tenant_id_removed_by_staff_id_idx (tenant_id, removed_by_staff_id)`,
  partial where removed_by_staff_id is not null.
- `pt_cancellations_tenant_id_cancelled_by_staff_id_idx (tenant_id, cancelled_by_staff_id)`,
  partial where cancelled_by_staff_id is not null.
- `pt_cancellations_tenant_id_waived_by_staff_id_idx (tenant_id, waived_by_staff_id)`,
  partial where waived_by_staff_id is not null.

The original index test remains unchanged and was committed before source;
its actual red receipt names these five columns. No FK/index exemption applies.

## Existing add-on capability test

SHP explicitly exposes `app.shop_reservation_mark_fulfilled(uuid,uuid)` as a narrow
authenticated definer capability. The old test discovers private add-on helpers
by searching their bodies for `addon_`, incidentally capturing this approved
non-private capability. Keep its no-user-execute rule for every other matching
helper. Exclude only this exact signature from that private set, and positively
assert its prescribed owner, empty path, volatility and exact grants instead.
Never exempt a name pattern, whole feature, arbitrary definer or helper. All SHP
caller/row-boundary assertions remain mandatory.

## No-show fixtures are adults

The old scan suite creates members without DOB. GRD correctly treats unknown ages
as ineligible until the approved legacy attestation exists. Its non-age scenarios
must now establish an actual adult DOB in their own fixture rows before scanning.
Preserve every expected absence, lifecycle, pause and timezone result. Do not
attest unrelated rows, weaken the unknown-age fail-safe, bypass a guard or change
scoring source. Independent GRD suites retain minor/unknown coverage.

An implementation-blind author makes these visible compatibility edits; holdouts
remain independent. Tests commit separately before isolated source work. The
full canonical sweep and a fresh policy/index source review remain required.
