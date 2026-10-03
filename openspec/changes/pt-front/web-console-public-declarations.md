# PTF web console public declarations

Status: **frozen implementation metadata, root-reviewed before independent test fanout**, 2026-10-03. Read with proposal.md, application-interface-clarification.md, support-preview-clarification.md and docs/design/v2/ptf-bar.md. These are routine adapters for accepted surfaces, not owner requirement changes. No new RPC, route, grant, claim parser, scope authority, ledger vocabulary or read classification is authorized.

The member portion is superseded by the frozen [web member read/cancel packet](web-member-read-cancel-declarations.md). Its page, callback and client declarations remain solely there. New-booking policy and confirmation remain owner-pending.

## Types and verified caller boundary

Documentation aliases below need not become exported production symbols. Reuse generated Database types, registered BusinessNouns, TrainerWindow and PtReadSection; new implementation exports require registry review.

```ts
type CallerClient = SupabaseClient<Database>;
type ConsoleIdentity = Extract<GymloopIdentity, { kind: 'staff' | 'impersonation' }>;
// Existing shared identity arms, declaration only:
// staff: { kind:'staff'; userId:string; tenantId:string; staffId:string; role:StaffRole }
// impersonation: { kind:'impersonation'; userId:string; tenantId:string; impersonationSessionId:string }
type StaffRole = Extract<GymloopIdentity, { kind: 'staff' }>['role'];
type ConsoleViewer = {
  role: StaffRole | null;
  staffId: string | null;
  readOnly: boolean;
  scopeKey: string;
};
type VerifiedConsoleViewer = {
  identity: ConsoleIdentity;
  viewer: ConsoleViewer;
};
type TrainerChoice = {
  staffId: string;
  displayName: string;
  isActive: boolean;
  qualification: string | null;
  timezone: string;
  branchName: string | null;
};
type StaffBooking = Omit<Database['public']['Functions']['read_pt_bookings']['Returns'][number], 'cancelled_at'> & {
  cancelled_at: string | null;
};
type StaffPack = Database['public']['Functions']['read_pt_packs']['Returns'][number];
type TrainerProfile = Pick<Database['public']['Tables']['trainer_profiles']['Row'],
  'bio' | 'specialities' | 'photo_asset_id' | 'is_listed'>;
type TimeOff = Pick<Database['public']['Tables']['trainer_time_off']['Row'],
  'id' | 'starts_on' | 'ends_on' | 'reason' | 'removed_at'>;
type PtPolicy = { cancelWindowHours: number; lateCancelConsumes: boolean; sessionMinutes: number };
type ReadValue<T> = { data: T | null; error: string | null };
type BookingArgs = Database['public']['Functions']['read_pt_bookings']['Args'];
type PackArgs = Database['public']['Functions']['read_pt_packs']['Args'];

// Existing apps/web/lib/identity-session.ts declarations; not replacement guards.
declare function requireAudience(audience: 'console'): Promise<{
  supabase: CallerClient;
  identity: ConsoleIdentity;
}>;
declare function readIdentity(client?: CallerClient): Promise<{
  supabase: CallerClient;
  signedIn: boolean;
  authenticatedUser: boolean;
  identity: GymloopIdentity;
}>;
```

Every server page independently calls requireAudience('console') before feature reads, then checks PTF-028's allowed staff roles or canonical admitted preview. The existing request-scoped client and verified identity stay server-side. VerifiedConsoleViewer carries that existing result to adapters; it is not a new parser, client-supplied credential or exported authority constructor. Adapter scope and permission derive from caller.identity; presentation viewer fields cannot grant them. Inconsistent identity/viewer pairs refuse before feature reads. Unsupported roles, another trainer's detail and malformed filters refuse before feature table access. Preview maps to role=null, staffId=null, readOnly=true; never fabricate a staff identity from its owner-like SQL read admission. Mutating impersonation is refused by the existing server commands.

scopeKey is a presentation lease derived from complete verified identity, including preview session when present. It carries no token, command field or authorization. Only ConsoleViewer crosses client props; verified identity and Supabase clients do not.

## Proposed server adapters

These are concrete missing implementation targets in apps/web/lib/training-console.ts. Independent authors can import these declared exports; no function body is specified. Args are validated using existing generated vocabularies, registered schemas/cursor guards and constants before calling adapters. Adapters preserve tenant and own-trainer scope regardless of optional filters.

```ts
declare function loadPtBookings(client: CallerClient, caller: VerifiedConsoleViewer,
  args: BookingArgs): Promise<PtReadSection<StaffBooking>>;
declare function loadPtPacks(client: CallerClient, caller: VerifiedConsoleViewer,
  args: PackArgs): Promise<PtReadSection<StaffPack>>;
declare function loadTrainerChoices(client: CallerClient,
  caller: VerifiedConsoleViewer): Promise<PtReadSection<TrainerChoice>>;
declare function loadTrainerDetail(client: CallerClient, caller: VerifiedConsoleViewer,
  staffId: string): Promise<{
    trainer: ReadValue<TrainerChoice>;
    profile: ReadValue<TrainerProfile>;
    windows: PtReadSection<TrainerWindow>;
    timeOff: PtReadSection<TimeOff>;
    imageUrl: ReadValue<string>;
  }>;
declare function loadPtPolicy(client: CallerClient,
  caller: VerifiedConsoleViewer): Promise<ReadValue<PtPolicy>>;
declare function loadReassignmentCandidates(client: CallerClient,
  caller: VerifiedConsoleViewer, fromStaffId: string): Promise<ReadValue<{
    packs: StaffPack[];
    scheduledCount: number;
    overLimit: boolean;
  }>>;
declare function loadTimeOffBookings(client: CallerClient,
  caller: VerifiedConsoleViewer, staffId: string, startsOn: string,
  endsOn: string, timezone: string): Promise<PtReadSection<StaffBooking>>;
```

loadPtBookings/loadPtPacks return one RPC page. Returned booking cancelled_at is nullable because the cancellation join can be absent; generated function output annotations do not express that SQL nullability. All error strings are sanitized. Failed sections have null data; successful empty arrays and successful absent profile/image remain distinct from errors. A missing/failed policy is null/error, never an editable default. Detail sections fail independently after audience/target guards; a failed prerequisite trainer cannot authorize downstream reads.

Safe table projections under existing caller RLS: staff id/full_name/is_active/qualification/branch_id with trainer-role filtering; branches name/timezone and organization timezone only for display resolution; trainer_profiles bio/specialities/photo_asset_id/is_listed; trainer_availability weekday/start_minute/end_minute; trainer_time_off id/starts_on/ends_on/reason/removed_at; organization_settings pt_cancel_window_hours/pt_late_cancel_consumes_session/pt_session_minutes. Staff/branch IDs used for server joins do not broaden public metadata. TrainerChoice exposes only declared display fields, with branch timezone falling back to organization timezone and nullable branchName. Ordinary trainers receive only themselves and their own details. No phone/email/user id or whole staff row reaches the client. Window minutes map mechanically to the registered strict camelCase shape. Images use existing caller-forwarded mediaDisplayUrl and expose imageUrl only, no private asset metadata or storage keys.

loadPtPolicy admits owner/manager and read-only canonical preview; other roles refuse before settings reads. loadReassignmentCandidates admits ordinary owner/manager only and refuses preview or other roles before ledger access. It exhausts unfiltered-by-state source read_pt_packs pages and the existing tenant/source/ACTIVE addon_orders projection id,status,trainer_staff_id, intersects complete IDs, and returns only corresponding StaffPack rows plus their summed sessions_scheduled and overLimit. The supplement is solely an owner/manager reassignment preparation fact; neither the projection nor status rows become client props or a TRV ledger list. PTF-032 continues rendering trainer balances and clients solely through existing RPCs.

State is not underlying status: app.pt_pack_state maps active orders before their validity to closed, which also represents refunded orders. live/fully_booked/expired cannot yield an exact ACTIVE set. Expired active orders remain reassignment candidates; spent/completed and refunded/closed do not. The intersection preserves read_pt_packs' exact frozen PT-kind predicate without inventing another product classification. A failed page in either source returns null/error, not a partial complete count. overLimit means more than the existing 100-order command maximum; never truncate all-source selection to fit. Explicit selection also uses underlying active IDs from this complete set. Scheduled cancellation totals include past unclosed scheduled sessions, as the command does.

Both staff RPCs clamp p_limit to 1..50 (default/null 50). Packs ascend order_id with p_after_id; bookings ascend (starts_at,session_id) and require both cursor fields together. Bookings use [p_from,p_to), capped at 62 elapsed days, with no 28-day read horizon. Exhaust complete reads until no rows remain; duplicate/nonprogressing cursors fail safely. loadTimeOffBookings resolves inclusive date bounds to trainer-local midnight through midnight after endsOn, splits into contiguous half-open intervals each within 62 elapsed days, and exhausts every booking page using p_trainer_staff_id and booked status. Time off has no maximum date span. The 14-day member slot cap and 28-day new-booking horizon never truncate standing bookings. Any chunk/page failure returns null/error and invalidates a complete affected count.

Authoritative command-time validation remains final; these multi-read counts are a current presentation snapshot, not a lock or guarantee against concurrent changes.

## Default server pages at fixed proposal paths

```ts
// apps/web/app/(console)/training/page.tsx
declare function Page(props: { searchParams: Promise<{
  from?: string; to?: string; trainerStaffId?: string; status?: string;
  afterStartsAt?: string; afterId?: string;
}> }): Promise<React.JSX.Element>;
// apps/web/app/(console)/training/packs/page.tsx
declare function Page(props: { searchParams: Promise<{
  trainerStaffId?: string; state?: string; afterId?: string;
}> }): Promise<React.JSX.Element>;
// apps/web/app/(console)/training/trainers/page.tsx
declare function Page(): Promise<React.JSX.Element>;
// apps/web/app/(console)/training/trainers/[staffId]/page.tsx
declare function Page(props: { params: Promise<{ staffId: string }> }): Promise<React.JSX.Element>;
// apps/web/app/(console)/training/policy/page.tsx
declare function Page(): Promise<React.JSX.Element>;
```

Search parameters are untrusted strings, not enum assertions or authority. Invalid values/cursor pairs do not become feature reads. Pages render all gate-30 states, preserve successful independent sections, and never equate failure with empty success. Trainers list warnings require complete scoped pack facts, not a first-page total. All support-preview pages remain read-only.

## Client controls and command coordination

```ts
// apps/web/app/(console)/training/booking-actions.tsx
declare function BookingRowActions(props: {
  booking: StaffBooking; viewer: ConsoleViewer; nouns: BusinessNouns;
}): React.JSX.Element;
// apps/web/app/(console)/training/reassign-panel.tsx
declare function ReassignPacksPanel(props: {
  candidates: ReadValue<{ packs: StaffPack[]; scheduledCount: number; overLimit: boolean }>;
  trainers: TrainerChoice[]; viewer: ConsoleViewer; nouns: BusinessNouns;
}): React.JSX.Element;
// apps/web/app/(console)/training/trainers/[staffId]/trainer-forms.tsx
declare function TrainerProfileForm(props: {
  trainer: TrainerChoice; profile: TrainerProfile | null; imageUrl: string | null;
  viewer: ConsoleViewer; nouns: BusinessNouns;
}): React.JSX.Element;
declare function TrainerAvailabilityEditor(props: {
  trainer: TrainerChoice; windows: TrainerWindow[]; viewer: ConsoleViewer; nouns: BusinessNouns;
}): React.JSX.Element;
declare function TrainerTimeOffPanel(props: {
  trainer: TrainerChoice; entries: TimeOff[]; bookings: PtReadSection<StaffBooking>;
  viewer: ConsoleViewer; nouns: BusinessNouns;
}): React.JSX.Element;
// apps/web/app/(console)/training/policy/pt-policy-form.tsx
declare function PtPolicyForm(props: {
  policy: PtPolicy; viewer: ConsoleViewer; nouns: BusinessNouns;
}): React.JSX.Element;
// apps/web/lib/use-pt-command.tsx: proposed shared console coordinator
// Body/result types come from existing strict schemas and accepted envelopes.
declare function usePtCommand<TBody, TResult>(options: {
  viewer: ConsoleViewer;
  operationKey: string;
  nouns: BusinessNouns;
  canSubmit: (viewer: ConsoleViewer) => boolean;
  send: (body: TBody) => Promise<TResult>;
  accepted: (result: TResult) => boolean;
  refresh: () => void;
}): {
  pending: boolean;
  error: string | null;
  submit: (body: TBody) => Promise<TResult | null>;
};
```

Root accepts the declared prop shapes and companion filenames. Parent pages never mount editable forms from failed reads. Reassignment candidates are prepared for the selected source; source change invalidates prior counts and confirmation, and every source needing all-active confirmation must have its own complete authoritative render. No arbitrary browser database read or new read route is implied.

operationKey is a control-local presentation identity for the exact target and authoritative props relevant to its confirmation, not a token or command field. Target/read-prop changes revoke retained handlers, pending feedback, upload continuations and confirmations even when the caller stays the same. Returning A to B to A never revives the first lease. Ordinary field edits within the same current control do not manufacture authority or renew an obsolete confirmation. Failed reads cannot supply editable defaults. Callers must retain stable command callbacks for unchanged controls; callback identity alone is not a new verified audience.

usePtCommand coordinates existing cookie-authenticated POST/fetch only. The permission callback implements the unchanged PTF role matrix and is checked at submission, alongside readOnly. It does not grant authority. It reuses PT refusal copy, existing envelopes and router refresh; existing class hooks cannot supply PT refusal/uncertainty semantics. It owns one in-flight submission, positive offline refusal/no queue, sanitized error state, accepted-envelope-only refresh, and a permanent lifetime lease: viewer/scope changes or unmount invalidate retained handlers and pending results; A→B→A never revives the first A lease. Unknown/transport failures remain failures, reconnect never submits, and stale responses cannot refresh or show success. No additional lifecycle hook or dependency is proposed.

| Control | Existing command and submitted public fields |
|---|---|
| BookingRowActions | /api/pt-bookings/cancel {sessionId,reason}; /api/pt-forfeits/waive {sessionId,reason} |
| ReassignPacksPanel | /api/pt-reassignments {fromStaffId,toStaffId,orderIds?,reason}; omitted orderIds means all eligible source active packs |
| TrainerProfileForm, owner/manager | /api/trainer-profiles {staffId,bio,specialities,photoAssetId,isListed} |
| TrainerProfileForm, own linked trainer | /api/trainer-profiles/own {bio,specialities}; photo/listing controls absent |
| TrainerAvailabilityEditor | /api/trainer-availability {staffId,windows} |
| TrainerTimeOffPanel | /api/trainer-time-off {staffId,startsOn,endsOn,reason?}; /api/trainer-time-off/remove {timeOffId} |
| PtPolicyForm | /api/pt-policy {cancelWindowHours,lateCancelConsumes,sessionMinutes} |

PTF-028's role matrix is unchanged: owner/manager reassignment, policy, waiver and profile listing; owner/manager/front desk gym cancellation; owner/manager or own trainer availability/time off; own trainer profile limited to bio/specialities. Preview exposes no mutation control. Cancellation/waiver require reason and explicit confirmation; reassignment confirms the exact complete selected scheduled count and member notices. Availability shows inline overlap refusal; existing schema and database remain backstops. Profile upload uses existing SHP upload/confirm/display seams. Changing availability or adding time off never cancels existing sessions.

## Existing presentation/media dependency declarations

```ts
// apps/web/app/(console)/field.tsx
declare function Field(props: { label: string; children: ReactNode }): React.JSX.Element;
declare const inputClass: 'cl-input';
// apps/web/lib/media-upload.ts
type MediaUploadStage = 'uploading' | 'verifying';
declare function uploadMediaFile(file: File, kind: MediaKind,
  onStage?: (stage: MediaUploadStage) => void): Promise<{ assetId: string }>;
// apps/web/lib/media.ts; caller-forwarded existing Edge API, no admin client
declare function mediaDisplayUrl(client: CallerClient, assetId: string,
  verifiedToken?: string): Promise<string | null>;
// apps/web/lib/business-type.ts
declare function loadBusinessNouns(client: CallerClient, tenantId: string): Promise<BusinessNouns>;
```

Actual rendered hosts may be doubled only at these public boundaries while
preserving labels/children/control callbacks. Doubles do not establish real
target dimensions, layout, keyboard focus or browser acceptance. Next router's
existing refresh/push and HTML online/offline events are presentation boundaries.

## Source truth and review status

SQL references: supabase/migrations/20261003130000_pt_front.sql (read_pt_bookings/read_pt_packs, app.pt_pack_state, reassign_pt_packs, table projections); supabase/migrations/20260907184315_phase2_role_matrix.sql (existing addon_orders tenant SELECT). Generated signatures: packages/db/types/database.ts read_pt_bookings/read_pt_packs/reassign_pt_packs and named table rows. Existing guard signatures: apps/web/lib/identity-session.ts. Requirements: proposal.md PTF-007/018/022/028/032, its limits table, and support-preview-clarification.md.

These choices preserve approved eligibility, money, sold facts, identity, RLS and commands. Independent visible and held authors may now import the declared missing targets and commit meaningful red checks before a separate implementer. Existing booking-policy and confirmation amendments remain owner-pending and outside this packet.
