# Approved guardian linked-account copy — public seams

Frozen engineering declarations, 2026-10-03, following the owner's explicit
approval of linked-account-copy-boundary-amendment.md. No identity, SQL,
recipient, consent or handover rule changes. Independent tests precede build.

The existing default member detail page is
`apps/web/app/(console)/members/[memberId]/page.tsx` with
`{params: Promise<{memberId:string}>; searchParams: Promise<{visits?:string}>}`.
Its declared hosts are `requireAudience('console')`, `loadBusinessNouns`,
`loadMember(memberId)`, `loadMembershipStanding`, `loadMemberAppAccess`,
`loadMemberInviteActivity`, `loadMemberGuardian`, and the supplied authenticated
Supabase read client. Existing AppAccessPanel, GuardianPanel, InviteHistory,
StatusWord, Next Link/notFound and icon rendering may be mocked for a page-prop
test; no source-body or private helper inspection is needed.

`loadMember` returns a Supabase response with data containing id, full_name,
phone, email, status, branch_id, joined_on, member_code and erased_at, or null.
The detail page's ordinary table-read host returns branch name, attendance,
payments and organization name/timezone. Readers must retain current role and
support-preview behavior; this repair changes only account-provenance copy.

The registered `MemberAppAccess` projection has state (`linked`,
`invite_pending`, `invite_expired`, `not_invited`, `unavailable`), inviteId,
issuedAt, expiresAt and linkedAt (nullable strings). The registered
`MemberGuardian` projection includes ageState, guardianName,
guardianLinkedAt (nullable timestamp), handoverDue, guardianEmail, linkEmail,
and existing DOB/consent/scoring fields; its body-free type declaration in
`apps/web/lib/guardian.ts` is an allowed test-author metadata source.

The existing `AppAccessPanel` export accepts memberId/memberName/gymName,
email/phone (nullable strings), role, access (MemberAppAccess|null), optional
readOnly, optional staffRoleLabel, optional initialIssued
`{link:string; expiresAt:string; replacedPrevious:boolean}`, and optional
guardian `{name:string; memberFirstName:string}|null`. No new prop is required.
Its host imports include Next Link/useRouter, QRCodeSVG, usePreviewReadOnly,
StatusWord, Alert and Field/inputClass. Actual panel rendering must show only
neutral connected-membership copy when a linked account has no authoritative
guardian marker; never claim the member owns its Google account. Guardian
provenance continues for a retained marker whether age is minor, adult or
unknown. Prospective unlinked routing/sharing remains based on current minor
state and the existing eligible email; failed reads do not invent provenance.

Independent visible and held tests cover both detail-page prop selection and
actual linked/prospective panel copy. Existing invite/share/recovery/unlink and
guardian handover conditions remain unchanged. A fresh critic follows build.
