-- Gate-8 index rule 2 completion (sweep 2, run 37316063876):
-- 04_contract_meta test 16 surfaced the next two unindexed foreign-key
-- columns after the 20261005160000 batch; the catalog census adds the
-- member_freeze pair (auth.users references, single-column by ADR-052 —
-- the parent carries no tenant column — but still owed an index).
create index whatsapp_dispatch_requests_tenant_id_requested_by_staff_id_idx
  on public.whatsapp_dispatch_requests (tenant_id, requested_by_staff_id);
create index member_freeze_requests_tenant_id_cancelled_by_user_id_idx
  on public.member_freeze_requests (tenant_id, cancelled_by_user_id);
create index member_freeze_requests_tenant_id_requested_by_user_id_idx
  on public.member_freeze_requests (tenant_id, requested_by_user_id);
create index member_freeze_commands_tenant_id_actor_user_id_idx
  on public.member_freeze_commands (tenant_id, actor_user_id);
