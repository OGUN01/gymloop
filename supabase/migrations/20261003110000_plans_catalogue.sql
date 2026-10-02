-- PLC-001..004/020: members read only their tenant's active plans.
-- Same serial forward-only policy-replacement exemption as
-- 20260907184315_phase2_role_matrix.sql (ADR-047/055): CREATE POLICY has no
-- OR REPLACE, so replace this applied policy under its existing name.
-- CI applies the migration transactionally (ADR-030); no explicit BEGIN/COMMIT.
-- No other policy, grant, table, column, index, trigger or function changes.
drop policy plans_member_select on public.plans;

create policy plans_member_select on public.plans
  for select to authenticated
  using (tenant_id = (select app.current_tenant_id())
         and (select app.current_app_role()) = 'member'
         and (select app.current_member_id()) is not null
         and is_active);
