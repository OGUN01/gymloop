# Plans catalogue: existing staff claims boundary

Status: proposed for owner decision. PLC implementation and final acceptance stay
paused at this boundary; no policy change is authorized by this document.

PLC-002 promises two incompatible outcomes: unchanged staff catalogue access, and
no rows for a non-member role carrying a member_id. PLC-003 permits changing only
plans_member_select by adding is_active. The existing plans_staff_select uses the
tenant claim plus app.is_staff(), whose role predicate accepts trainer/desk/admin
without consulting member_id. Appending is_active to the member policy cannot
remove rows already admitted by that separate staff policy.

The current independent visible probe returns three own-gym plans for trainer
plus member_id and expects zero. The held suite already preserves that legacy
staff access. Their disagreement reflects this public contract contradiction;
neither result establishes the promised stronger mixed-claim refusal.

## Recommended: retain the exact minimal catalogue change

Amend the last sentence of PLC-002 to distinguish the unchanged staff predicate:
a tenant claim with no recognized role reads nothing; a member-role claim remains
member-scoped and sees only active plans; the existing staff/platform predicates
remain unchanged, including their behavior with extraneous member_id claims.

PLC-003 remains exact: replace only plans_member_select, append only is_active,
and add no grant, helper, policy, API or other authorization hardening. This is an
explicit retained legacy boundary, not a claim that mixed identity is validated.
The signed claim hook's canonical claim shape remains unchanged.

Both independent authors pin unchanged own-gym staff access with and without the
extra member_id, member active-only reads, foreign-gym isolation and no-role
refusal. Existing policy/grant immutability assertions remain. A fresh critic
checks the exact narrowed amendment before the batch push.

## Alternative: strengthen the staff policy in this feature

Amend PLC-003 to permit replacing plans_staff_select as well, adding the explicit
current_member_id IS NULL predicate to its existing tenant/is_staff condition.
Keep ordinary staff/platform behavior and every other plans grant/policy intact.
Both independent authors commit focused mixed-claim refusal and unchanged normal
staff tests before a separate implementer changes this second policy. Catalogue
and authorization baseline sweeps and a fresh identity critic are mandatory.

This is an additional identity policy change, beyond the frozen minimal feature;
it needs the owner's approval rather than a fixture or expectation workaround.
