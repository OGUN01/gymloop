-- Phase 7 offline attendance provenance repair.
--
-- A visit is either live (neither offline stamp) or a validated offline replay
-- (both stamps). Keep that invariant at the table boundary for every writer.

alter table public.attendance
  drop constraint if exists attendance_offline_stamp_pair_chk;

alter table public.attendance
  add constraint attendance_offline_stamp_pair_chk
  check ((offline_recorded_at is null) = (replayed_at is null));
