# Remaining member information architecture

Status: frozen integration metadata, 2026-10-03. Applies the owner-approved
feature map's split of PT/Shop and shared decisions' final IA step. No new
identity, grant, money rule, product classification, booking policy or command.
Read decisions.md, shared.md primitive 4 and the feature map's "What stays in
add-ons". Existing tests are amended explicitly before separate source changes.

## Canonical destinations and compatible history

- Web Home's visible business name opens `/member/gym`. Its membership row and
  You's membership row open `/member/gym#membership`; You's business row opens
  `/member/gym`. Keep the five primary tabs unchanged.
- `apps/web/app/member/gym/page.tsx` becomes the canonical default
  `MemberGymPage`. `/member/my-gym` remains a compatibility render/re-export of
  that same page so existing incoming fragments still find `id="membership"`.
  Neither alias reads another caller or implements a redirect with guessed
  fragment state. Both use existing `loadMemberPortal()` and its verified caller.
- Gym preserves all membership and receipt facts, failure versus empty states,
  address, branch and business code, messages/consent and attendance access.
  It retains PLC `/member/plans`, adds Trainers & programmes pointing to
  `/member/classes/training#trainers`, and exposes the existing public legal
  paths. The existing Training trainer section gets stable `id="trainers"`.
- Gym links Other services to `/member/shop#services`. The existing Shop
  services section gets `id="services"`; its public section classification
  stays exactly the existing `products | services` projection. An empty services
  section remains an honest empty state; no new category predicate is inferred.
- `/member/add-ons` becomes historical Orders & completed returns. Gym links
  to those facts separately. Retain every existing caller-owned order, sold
  terms, usage, completed-return projection, selected order, keyset pagination
  and session-history path. Remove only the competing available PT/Shop offer
  catalogue and its product reads/actions. Old `offer`/`offerAfter` parameters
  cannot reintroduce that catalogue or authorize another read/write. Historical
  orders are never filtered by current product kind, activity, stock or trainer.
  Shop's existing View collected item link keeps reaching exact order history.

## Native composition

Modify the existing default Home, Gym and Classes screens without a new data
adapter. Home's visible business-name caption becomes actionable to
`/(member)/gym`; existing Home/You membership and Gym entries retain that route.
Gym retains membership/receipts and PLC disclosure with
`useMemberPlans(openSection === 'plans')` and `PlanCatalogueBody`. It adds a
Trainers & programmes row opening
`{ pathname:'/(member)/classes', params:{ section:'training' } }`, Other services
opening `/(member)/shop`, and the registered `LegalLinks`. Its existing add-on
ledger is labelled historical Orders & completed returns/purchases, keeps all
recorded orders and decimal paise strings, and offers no duplicate PT/Shop
catalogue. Do not invent completed-return facts absent from MemberSnapshot.

ClassesScreen reads only the public `section` navigation parameter. Exact
`'training'` selects the existing TrainingSection; missing, array or any other
value selects ClassesPane. A changed valid parameter updates the selected
segment. The registered SegmentedControl still lets the member explicitly choose
either section. No parameter supplies identity or permission. No pending booking
or cancellation contract is changed by this navigation composition.

Desk More adds Classes -> `/(desk)/classes` and Training -> the configured web
origin's authenticated `/training` console in the browser. Use the existing
`useMobile().webOrigin` and Expo WebBrowser boundary; never put session tokens
or identity claims in the URL, infer browser sign-in or mount member
TrainingSection under a staff identity. The Training label explains that it
opens the web console. This is the PTF console handoff; the dedicated native
trainer workflow belongs to TRV. Preserve the four desk primary tabs, lead
capture/account/legal behavior and server console audience guards.

## Public dependency declarations for source-blind authors

No new shared API exports or loader bodies are introduced. Reuse declarations:

```ts
declare function useMemberSnapshot(): {
  data: MemberSnapshot | null; error: string | null; loading: boolean;
  reload: () => Promise<void>;
};
type MemberSnapshot = {
  member: { fullName:string; memberCode:string|null; email:string|null;
    phone:string; goal:number; restDays:number[] };
  gym: { name:string; displayName:string; code:string; timezone:string;
    city:string|null; state:string|null; branchName:string;
    branchAddress:string|null };
  membership: { status:string; startsOn:string|null; endsOn:string|null;
    planName:string } | null;
  visits: { id:string; checkedInAt:string; source:string }[];
  weekVisits:number; weekStart:string;
  streak: { current:number; unit:'day'|'week'; missed:readonly string[] };
  receipts: { id:string; amountPaise:string; currency:string;
    paidAt:string|null; receiptNumber:string|null; status:string }[];
  messages: { id:string; body:string; sentAt:string|null; status:string }[];
  consents: { purpose:string; granted:boolean; recordedAt:string }[];
  addOns: { id:string; name:string; status:string; totalPaise:string;
    currency:string; sessionsUsed:number; sessionsTotal:number|null }[];
};
```

Web `loadMemberPortal()` successful projection supplies `errorMessage:null`,
`nouns:BusinessNouns`, member full_name/member_code/email/phone/weekly_goal_visits/
rest_days, gym name/gym_code/timezone/branchName/branchAddress/city/state, nullable
membership planName/status/startsOn/endsOn, visits id/checked_in_at/source,
weekVisits/weeklyGoal/weekStart/streak, nullable receipts and addOns, and nullable
latestMessage id/body/sentAt/status. Receipt amountPaise is a decimal string;
failed money read is null, successful absence is an empty array. Error projection
has non-null errorMessage; no success facts may be inferred from it.

`LegalLinks` has no props; `useMobile` supplies existing verified identity,
webOrigin, api, supabase, palette and appearance/session/signOut fields. Existing
UI Row preserves title/meta/onPress/accessibility label/hint; native hooks/router
and WebBrowser may be doubled at public seams. Web `requireAudience('member')`
remains authoritative for historical orders and all current feature reads.
Existing `AddonOrderFacts`, `AddonLoadError`, registered
columns/formatters and completed-return RPC remain unchanged.

Historical web dependency paths: requireAudience in
`apps/web/lib/identity-session.ts`; loadBusinessOrganization in
`apps/web/lib/business-type.ts`; UUID_PATTERN in `apps/web/lib/keyset.ts`;
gymTimeLabel in `apps/web/lib/time.ts`; StatusWord in
`apps/web/app/status-word.tsx`; all Addon display types/columns/components in
`apps/web/app/(console)/add-ons/display.tsx`. loadMemberPortal is in
`apps/web/lib/member-portal.ts`; businessNouns/PUBLIC_PAGE_PATHS/formatMoney
are existing shared exports. Native kit/hooks paths are
`apps/mobile/components/ui.tsx`, `apps/mobile/lib/use-member-snapshot.ts`,
`apps/mobile/lib/use-member-plans.ts`, `apps/mobile/lib/use-business-nouns.ts`,
`apps/mobile/lib/mobile-context.tsx` and `apps/mobile/components/legal-links.tsx`.
Native Classes composes `classes-pane.tsx` and `training-section.tsx` from
that same components directory; Expo Router and WebBrowser are public hosts.

Additional existing declarations (no bodies):

```ts
type Tables = Database['public']['Tables'];
type Person = { full_name:string; phone?:string };
type AddonOrder = Omit<Tables['addon_orders']['Row'], 'unit_price_paise'|'total_paise'> & {
  unit_price_paise:string; total_paise:string; sold_at:string|null;
  sold_by_staff_id:string|null;
  sale_snapshot: { kind:Tables['addon_products']['Row']['kind']; name:string;
    description:string; cancellationTerms:string; validityDays:number;
    trainerQualification:string|null } | null;
  members:Person|null; seller:Person|null; trainer:Person|null;
  addon_products:{name:string}|null;
  payments:{receipt_number:string|null; status:Tables['payments']['Row']['status'];
    method:Tables['payments']['Row']['method']; amount_paise:string; currency:string}|null;
};
type AddonSession = Tables['pt_sessions']['Row'] & { members:Person|null; staff:Person|null };
declare function AddonOrderFacts(props: { order:AddonOrder; timezone:string;
  showPayment?:boolean; detail?:boolean; children?:ReactNode }): React.JSX.Element;
declare function AddonLoadError(props:{label:string;href:string}):React.JSX.Element;
// Existing caller-owned completed-return RPC data:
type MemberReturns = { orderId:string; returns:{ refundId:string;
  kind:Database['public']['Enums']['refund_kind']; amountPaise:string;
  currency:string; processedAt:string|null }[] };
```

Historical default page accepts optional searchParams Promise with offer, order,
offerAfter, orderAfter, sessionAfter strings, and optional absent props. The
member audience result supplies the existing caller Supabase client and verified
member identity (kind/member/user/tenant IDs). Read hosts support normal select,
eq, order, gt, limit, maybeSingle and the exact-count head projection; reply shape
is `{data,error,count?}`. Orders and sessions use generated rows plus the declared
relations/decimal money overrides. The sole completed-return projection is
read_member_addon_returns({p_order_id}); no direct refunds read is authorized.
loadBusinessOrganization(client,tenantId) yields the existing organization's
timezone/business_type/name/gym_code display row with error/data state.

Independent visible tests explicitly amend the former Add-ons catalogue
expectation while preserving order/return/session assertions. A separate held
author covers caller/history retention and no replacement product inference.
Then one source integrator owns these exact IA locations, avoiding the concurrent
PT console/member confirmation files except the trainer section anchor. Fresh
complete review, all gates and the final consolidated scenario sweep remain.
