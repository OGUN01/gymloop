# ANC direct-table platform policy clarification

Status: approved technical reconciliation under the orchestrator's delegated
contract authority, after a fresh independent contract GO on 2026-10-02. No
additional owner permission decision is required. ANC source edits resume only
after the exact corrected central metadata test commit.

The frozen ANC-016 fixed-name table and independent visible suite specify only
front-office tenant SELECT on announcements and announcement_versions, and only
own-member SELECT on announcement_receipts. The general catalogue template
expects a platform SELECT pair on other public tables. The first central ANC
metadata draft exempted only receipts, contradicting the two explicit content
policy lists. No implementation has added a platform policy.

Preserve the narrower frozen feature contract. Record in ADR-184 the exact three
named exceptions: announcements, announcement_versions and announcement_receipts
have no platform policy. Content keeps only the two respective tenant-select
policies; receipts keep only announcement_receipts_member_select. No table gets a
write policy or authenticated DML grant, and no unrelated template row changes.
The catalogue asserts the exact absence of platform policies on these three
tables, rather than accepting arbitrary alternatives.

Real front-office staff continue the tenant-scoped content reads. Support preview
continues only through the frozen authenticated, actor-checked, read-only ANC RPC
path; this amendment grants no direct cross-tenant platform content or receipt
read, no publication authority and no member-level receipt-count detail.

After a fresh independent contract GO, update the public fixed-name row and
ADR-184, then have the original central metadata author correct the exact named
allowance. The existing independent visible exact policy-list assertions remain
unchanged. Resume the separate implementer only after that test commit. If review
finds a product permission decision is required, escalate to the owner rather
than changing the permission boundary implicitly.
