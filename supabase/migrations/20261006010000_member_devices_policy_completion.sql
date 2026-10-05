-- Completes the member_devices PUSH reconciliation (sweep 37341063236, 04
-- test 7): the migration 20261004090000 revoked every authenticated table
-- privilege — tokens and metadata are reachable only through command-safe
-- RPCs — and 20261005160000 dropped the stale FOR ALL write policies. The
-- phase-2 SELECT policies remained, but they are dead letters: each permits
-- reads the grant no longer carries, which is the same
-- "policy permitting what the grant denies" artifact class the matrix
-- invariant exists to catch. The grant-derived matrix row (all nulls,
-- committed in b05c13ae) expects them absent.
drop policy if exists member_devices_platform_select on public.member_devices;
drop policy if exists member_devices_tenant_select on public.member_devices;
drop policy if exists member_devices_member_select on public.member_devices;
