# Lead conversion public consumer declarations

Status: proposed completion of the LDC draft, 2026-10-03. Not approved or
frozen. Read with `proposal.md` and `docs/design/v2/ldc-bar.md`. These are public
test/build seams, not an implementation body or permission to edit tests.

## Existing component and destination

Retain the registered `LeadConvertDialog` export in
`apps/web/app/(console)/leads/lead-forms.tsx`. Its final props are:

```ts
{
  leadId: string;
  revision: string;
  fullName: string;
  scopeKey: string;
  nouns?: BusinessNouns;
}
```

The required opaque `scopeKey` is supplied by the existing authorized server
page from the full verified caller identity; it is neither a raw tenant/user
identifier nor client authority. Changing caller, lead, revision or displayed
decision facts permanently revokes retained callbacks, disclosed duplicate
data, uncertain retry evidence and late feedback from the old presentation.
Unmount and a caller A-B-A transition also revoke that old lease permanently.
Every network send and accepted-result presentation checks the current lease.
Missing/empty scope refuses conversion. No service client or persisted cache.

Existing page `apps/web/app/(console)/leads/page.tsx` renders the component only
for loaded `trial_done` rows. It keeps the existing `loadLeads` projection and
all current filters; terminal converted rows offer their existing Open member
destination. No native workspace or new lead mutation is added.

`loadLeads(searchParams)` is the registered server loader in
`apps/web/lib/leads.ts`. Its input is a Promise of optional string fields
`stage`, `source`, `assignee`, `branch`, `q`, `limit`, `cursor`. The resulting
screen includes rows, stageCounts, pageResultCount, totalMatchingCount, asOf,
nextCursor, pageSize, timezone, staffChoices, branchChoices, editableText and
errorMessage. Counts remain decimal strings and the snapshot remains server
owned. Tests may supply that public projection; no new GET path is planned.

## Existing command envelope

The only write is `POST /api/leads/{leadId}/convert`, JSON:

```ts
| { requestKey: string; expectedRevision: string; mode: 'create' }
| { requestKey: string; expectedRevision: string; mode: 'link_existing';
    memberId: string }
```

Use the actual HTTP envelope `{ok:true,data:{leadId,memberId,outcome,revision,
replayed}}`; UUID fields, outcome and boolean replay must validate before
claiming acceptance. Outcomes are the existing `created_member` and
`linked_existing` values. Error envelopes remain `{ok:false,error:{code,...}}`.
The request is a strict discriminated union: create forbids memberId entirely;
link_existing requires it and a deliberate disclosed-member choice. Extra
fields, client tenant/actor fields and mixed modes retain the existing refusal.
`link_required` may disclose only `{memberId,fullName,phone,status}` for the
existing safe same-tenant candidate. Malformed/incomplete conflict data permits
no link. `stale_lead` carries currentRevision; it requires refreshed deliberate
review and never automatic resubmission. All existing refusal mappings remain.

An uncertain response retains the complete exact path/body/request key for
that decision. Retry checks that evidence, not a new member or new key. A
different explicit decision after a definitive refusal uses a fresh key.
Double local submission has one flight. Positive offline state refuses send
and reconnect never replays it. No optimistic stage/member/metric change.

## Observable result and host dependencies

Initial action is **Convert to member**, submitting create mode without
retyping stored facts. A disclosed eligible duplicate requires **Link this
member** separately. Accepted outcomes show the proposal's precise created or
linked notice and an **Open member** link to `/members/{memberId}`. Refresh
preserves filters. If that read fails, accepted evidence remains and the list
is marked as needing refresh; no fresh conversion is offered for the accepted
decision. Unknown outcome uses the exact proposal retry notice.

Existing host modules are React, `next/link`, `next/navigation`, the existing
Field/Alert/StatusWord kit, identity-session, business-type, leads loader,
keyset UUID validation and shared BusinessNouns/formatPhone/UI_TOKENS. Test
authors may double unrelated hosts, never the conversion component or its
retained callback behavior. Canonical lead stages/sources come from generated
Database enums. No new helper/type/export is required by this declaration;
any build-time reuse gap must be recorded and registered before writing it.

This packet settles routine interfaces only. It changes no trial graph,
lost-terminal rule, phone uniqueness, RLS, conversion RPC, attribution or money.
Owner approval of the draft precedes independent visible/held authoring; Wave
C remains the implementation predecessor unless the owner changes that order.
