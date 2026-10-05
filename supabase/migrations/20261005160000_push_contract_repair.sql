-- Push/freeze contract repair (forward migration — the migrations it repairs
-- are already applied, so editing them never reaches the database).
--
-- Resolves the six source defects 04_contract_meta pins red:
--   1. member_devices carries stale FOR ALL write policies from the Phase 2
--      role matrix. The PUSH migration (20261004090000) revoked every
--      authenticated write on the table — tokens are reachable only through
--      command-safe RPCs — but left the policies behind. A policy permitting
--      what the grant denies is a stale artifact; the grant-derived matrix
--      invariant (design.md 8.1) requires the policies absent.
--   2. notification_push_campaigns lacks its frozen "separately approved
--      platform read policy"; the campaign contract is the one PUSH table the
--      platform-pair assertion does not exempt.
--   3. Two PUSH policies were created without a role target and therefore
--      default to PUBLIC; they are retargeted to authenticated.
--   4./5. The enumerated gate-8 index defects (final sweep 37289623896,
--      tests/04_contract_meta tests 15/16): two tables missing a
--      tenant-leading index, ten foreign-key columns with no index leading
--      them or carrying them immediately after the tenant column.

-- 1. member_devices: drop the stale FOR ALL write policies.
drop policy if exists member_devices_platform_write on public.member_devices;
drop policy if exists member_devices_tenant_write on public.member_devices;

-- 2. notification_push_campaigns: the separately approved platform read.
create policy notification_push_campaigns_platform_select
  on public.notification_push_campaigns
  for select to authenticated
  using ((select app.is_platform()));

-- 3. Retarget the two PUBLIC-defaulted PUSH policies to authenticated.
drop policy if exists notification_push_campaigns_front_office_select
  on public.notification_push_campaigns;
create policy notification_push_campaigns_front_office_select
  on public.notification_push_campaigns
  for select to authenticated
  using (
    tenant_id = app.current_tenant_id()
    and app.current_app_role() in ('gym_owner', 'gym_manager', 'front_desk')
  );

drop policy if exists member_notification_preferences_own_member_select
  on public.member_notification_preferences;
create policy member_notification_preferences_own_member_select
  on public.member_notification_preferences
  for select to authenticated
  using (
    tenant_id = app.push_preference_tenant()
    and member_id = app.push_preference_member()
  );

-- 4. gate 8 index rule 1: the two tables with no tenant-leading index.
create index notification_whatsapp_receipts_tenant_id_attempt_id_idx
  on public.notification_whatsapp_receipts (tenant_id, attempt_id);
create index notification_whatsapp_receipts_tenant_id_sender_account_id_idx
  on public.notification_whatsapp_receipts (tenant_id, sender_account_id);
create index whatsapp_command_keys_tenant_id_created_at_idx
  on public.whatsapp_command_keys (tenant_id, created_at);

-- 5. gate 8 index rule 2: every foreign-key column leads an index or sits
--    immediately after the tenant column.
create index notification_push_campaigns_tenant_id_created_by_staff_id_idx
  on public.notification_push_campaigns (tenant_id, created_by_staff_id);
create index notification_push_campaigns_tenant_id_reviewed_by_staff_id_idx
  on public.notification_push_campaigns (tenant_id, reviewed_by_staff_id);
create index notification_push_attempts_tenant_id_device_id_idx
  on public.notification_push_attempts (tenant_id, device_id);
create index notification_push_attempts_tenant_id_member_id_idx
  on public.notification_push_attempts (tenant_id, member_id);
create index purchase_requests_tenant_id_recorded_membership_id_idx
  on public.purchase_requests (tenant_id, recorded_membership_id);
create index whatsapp_template_revisions_tenant_id_sender_account_id_idx
  on public.whatsapp_template_revisions (tenant_id, sender_account_id);
create index whatsapp_channel_consents_tenant_id_recorded_by_staff_id_idx
  on public.whatsapp_channel_consents (tenant_id, recorded_by_staff_id);
create index notification_whatsapp_attempts_tenant_id_consent_id_idx
  on public.notification_whatsapp_attempts (tenant_id, consent_id);
create index notification_whatsapp_attempts_tenant_id_rate_version_id_idx
  on public.notification_whatsapp_attempts (tenant_id, rate_version_id);
create index notification_whatsapp_attempts_tenant_id_template_revision_id_idx
  on public.notification_whatsapp_attempts (tenant_id, template_revision_id);
