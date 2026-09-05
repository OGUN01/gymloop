---
name: rls-policy
description: Fires when the user asks to add, change, or debug a Row-Level Security policy, or reports that a query returns too much/too little data across tenants. Expects the table and the access pattern (who should see/write which rows) as input.
---

# RLS policy

The tenant-isolation pattern for this project, non-negotiable:

- Tenant id comes from the JWT claim set by the custom access-token hook (`auth.jwt() ->> 'tenant_id'` or the project's equivalent accessor), **never** a subquery against another table inside the policy — a subquery-based policy is both slower and has historically been the source of cross-tenant leaks in Supabase RLS setups.
- The column the policy filters on is indexed. An RLS policy on an unindexed column is a performance bug waiting to be a security incident once the table has real volume.
- `super_admin`/`platform_support` cross-tenant access is a separate policy branch keyed on role — RLS is never disabled to grant them access.
- Every policy ships with a **leak test**: as Gym A, attempt to read/update/delete a Gym B row and assert it fails (returns zero rows / raises, per the operation). Write this test in the same migration/change as the policy, not as a follow-up.

Before writing a new policy, check `docs/security.md` and `docs/data-model.md`'s RLS policy map section for the established shape on similar tables — most policies in this project should look structurally identical (same claim accessor, same index pattern), so a policy that looks different from its neighbors is a signal to double-check it, not a sign of cleverness.
