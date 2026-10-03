# TRV proposed public declarations

**DRAFT NOT FROZEN — 2026-10-03.** Companion to proposal.md and
`../pt-front/web-console-public-declarations.md`. No owner approval, tests,
implementation or new grant is implied. These declarations publish proposed
import targets for later independent authors; they are not registered exports.
Only public requirements, registry and declaration packets were read.

## Existing web boundary

Reuse `loadPtBookings(client, caller, args)`, `loadPtPacks(client, caller, args)`
and `loadTrainerChoices(client, caller)` exactly as published by PTF, including
`VerifiedConsoleViewer`, `StaffBooking`, `StaffPack`, `TrainerChoice` and
`PtReadSection`. Each web request calls existing `requireAudience('console')`
and admits a real trainer only. Identity and caller client stay server-side;
`ConsoleViewer.scopeKey` is presentation freshness only. Preview does not enter
TRV. Other staff retain their existing PTF page.

Choices metadata must contain the active own trainer matching the verified
staff binding and a valid branch/gym resolved timezone before date conversion.
Choices failure, missing own trainer or invalid timezone is an unavailable/access
outcome, never a device timezone fallback. This works for an empty day and an
empty pack section. Do not request profile, contact, policy or reassignment data.

Web orchestration stays in the existing Training server host. It calls the
published single-page adapters repeatedly with null/omitted trainer, status and
state filters. No new GET route, browser database reader or shared adapter is
proposed. Existing page query bounds/cursors remain valid for other staff;
trainer rendering uses its selected local date and complete own-day reads.

## Proposed native host, coordinator and screen

Documentation aliases below need not become exports. Native uses generated
Database and registered shared types, not imports from apps/web. The native
host retains its original session client and remotely verified identity from
existing session machinery. A cached offline identity cannot start a new read.
Verification/binding rejection clears facts and follows existing access handling.
No constructor for verified authority or additional claim parser is proposed.

```ts
type TrainerIdentity = Extract<GymloopIdentity, { kind: 'staff' }>;
type TrainerBooking = Omit<Database['public']['Functions']['read_pt_bookings']['Returns'][number],
  'cancelled_at'> & { cancelled_at: string | null };
type TrainerPack = Database['public']['Functions']['read_pt_packs']['Returns'][number];
type BookingArgs = Database['public']['Functions']['read_pt_bookings']['Args'];
type PackArgs = Database['public']['Functions']['read_pt_packs']['Args'];
type TrainerZone = { staffId: string; timezone: string };
type TrainerDay = {
  date: string; timezone: string;
  bookings: PtReadSection<TrainerBooking>;
  packs: PtReadSection<TrainerPack>;
};
// apps/mobile/lib/trainer-view.ts: proposed native host
// identity is an existing remotely verified result, never client-supplied authority.
declare function loadTrainerZone(client: SupabaseClient<Database>,
  identity: TrainerIdentity): Promise<{ data: TrainerZone | null; error: string | null }>;
declare function loadTrainerBookings(client: SupabaseClient<Database>,
  identity: TrainerIdentity, args: BookingArgs): Promise<PtReadSection<TrainerBooking>>;
declare function loadTrainerPacks(client: SupabaseClient<Database>,
  identity: TrainerIdentity, args: PackArgs): Promise<PtReadSection<TrainerPack>>;
// apps/mobile/lib/use-trainer-day.tsx: proposed presentation/read coordinator
// Host callbacks retain the existing verified-session lease; no authority in scopeKey.
declare function useTrainerDay(options: {
  scopeKey: string | null;
  online: boolean;
  loadZone: () => Promise<{ data: TrainerZone | null; error: string | null }>;
  loadBookings: (args: BookingArgs) => Promise<PtReadSection<TrainerBooking>>;
  loadPacks: (args: PackArgs) => Promise<PtReadSection<TrainerPack>>;
}): {
  day: TrainerDay | null;
  loading: boolean;
  stale: boolean;
  error: string | null;
  selectDate: (date: string) => void;
  today: () => void;
  previousDay: () => void;
  nextDay: () => void;
  refresh: () => void;
};
// apps/mobile/components/trainer-day-pane.tsx: proposed read-only presentation
// Documentation ReturnType alias only; no extra exported state model.
declare function TrainerDayPane(props: {
  state: ReturnType<typeof useTrainerDay>;
}): React.JSX.Element;
// apps/mobile/app/(desk)/training.tsx: proposed route, placement owner-pending
declare function TrainerTrainingScreen(): React.JSX.Element;
```

Host methods admit only the current real trainer and refuse inconsistent or
non-trainer identity before feature reads. Caller identity supplies scope;
arguments cannot select another trainer. Rows, args, status/state, cancellation
nullability and sanitized nullable section failures mirror the published PTF
contract. The zone host resolves only own metadata using PTF's published safe
staff/branch/organization choices projection under caller RLS; it returns only
staffId/timezone. Session/client/pack facts come exclusively from the two RPCs.
No contact fields, direct ledger supplement or new table/policy/RPC is proposed.

The route obtains the existing `useMobile` session/network context, current
verified identity and client; it binds host callbacks to that lease and renders
only the pane. API command capability is unnecessary. The pane renders proposal
copy and date/Refresh controls, canonical PTF labels, native Chalkline primitives
and no mutation action. Native provider/session host seams remain those already
published for PTF; this packet does not replace them.

## Complete reads and independent failure

Both platforms exhaust each section until a successful empty page. Use existing
`PT_READ_PAGE_MAX`; booking cursor is the final `(starts_at, session_id)` pair,
pack cursor the final `order_id`. Reject duplicate or nonprogressing cursor
results as a sanitized section failure; no infinite loop, truncation or complete
count from partial pages. Request all statuses/states. A day's bounds are local
midnight inclusive through next local midnight exclusive, converted separately
using existing helpers. Validate date/zone before any day RPC; never add a fixed
24-hour instant duration. The established booking maximum span still applies.

A failed page makes that entire section null/error, discarding its partial rows.
Sections remain independent: pack failure preserves successful session rows
with unavailable pack copy; booking failure renders session error, never empty.
A pack absent after complete successful paging also renders unavailable. Pack
values are returned canonical facts, never derived from booking counts or sums.

A new date, refresh, offline transition or verified-session lease invalidation
supersedes old in-flight results. A → B → A identity/date transitions cannot
revive the old request. Offline can preserve only same-lease/same-date in-memory
facts explicitly marked last loaded; switching identity/date clears them.
Reconnect requires a fresh authoritative load; no persisted client cache,
optimistic balances or queued mutation. Refresh replaces each section with its
latest successful/failure outcome and makes any incomplete pair explicit.

## Owner choices still outstanding

The EARS/bar and native desk-entry placement require owner approval after
closed-test feedback. OPEN-015 residual acceptance versus separately commissioned
legacy policy narrowing remains explicitly open. Advancing waves, combining CLS
or adding fulfilment would require a separate owner scope/order decision.
Adapter reuse, generated rows, complete paging and existing own-zone metadata
are engineering details resolved by already published contracts, not new owner
choices. Before freeze root reviews this packet; no independent test/build fanout
runs against the draft. Final symbols/consumers require registry and reuse review.
