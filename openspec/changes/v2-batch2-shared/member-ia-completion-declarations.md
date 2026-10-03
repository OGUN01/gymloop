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
Existing `AddonOrderDetails`, `AddonSessionRows`, `AddonLoadError`, registered
columns/formatters and completed-return RPC remain unchanged.

Independent visible tests explicitly amend the former Add-ons catalogue
expectation while preserving order/return/session assertions. A separate held
author covers caller/history retention and no replacement product inference.
Then one source integrator owns these exact IA locations, avoiding the concurrent
PT console/member confirmation files except the trainer section anchor. Fresh
complete review, all gates and the final consolidated scenario sweep remain.
