# PTF web member read and existing-session cancellation declarations

Status: **orchestrator-frozen presentation interfaces, 2026-10-03**. Read with
proposal.md, application-interface-clarification.md,
native-read-cancel-declarations.md and docs/design/v2/ptf-bar.md. No eligibility,
money, identity, policy, route or grant changes. New booking policy and booking
confirmation remain owner-pending. The separate web-console-public-declarations
packet remains proposed for its console controls.

## Public page and client interfaces

```ts
// apps/web/app/member/classes/training/page.tsx: default server-page export
declare function Page(props: {
  searchParams: Promise<{ afterStartsAt?: string; afterId?: string }>;
}): Promise<React.JSX.Element>;

// apps/web/app/member/classes/training/pt-actions.tsx
declare function PtCancelButton(props: {
  session: PtSession;
  scopeKey: string;
  nouns: BusinessNouns;
  refreshSession: () => Promise<PtSession | null>;
}): React.JSX.Element;
declare function TrainingConnectionNotice(): React.JSX.Element | null;
```

PtSession, PtPack, PtProgramme, PtTrainer, PtReadSection, PtHistoryCursor and
MemberTraining are the existing shared public types. Their full row declarations
are in native-read-cancel-declarations.md. A failed section is `{ data: null,
error: string }`; a successful empty section is `{ data: [], error: null }`.
cancelledAt and cancelCutoff are nullable; no policy default replaces null.

The page independently calls the registered requireAudience('member') before
any feature read. It renders PTF-029's order: Your sessions (upcoming and
keyset history), Your packs, Trainers and their programmes. Each failed section
keeps the independently successful sections and offers retry. Empty and failed
history remain distinct. Existing ClassesSegments has current='training'.
Displayed pack numbers, expiry exception, states, money, trainer exposure,
programme disclosures, business nouns and all gate-30 states stay exactly the
proposal. Programme purchase remains "Show at the desk". New booking targets
retain the frozen route; no booking implementation is authorized by this packet.

History uses the existing loadMemberTrainingHistory loader and its declared
cursor. The two search fields form one validated keyset cursor; malformed or
incomplete fields produce a sanitized history error without issuing a read with
invalid cursor arguments or erasing other successful sections. A More session
history link carries the last returned startsAt/sessionId pair when another
full page can be requested. No unbounded history or offset pagination is added.

TrainingConnectionNotice observes real browser connectivity and renders the
frozen offline sentence "You're offline. Showing what was last loaded." plus a
stale marker while disconnected. Reconnect clears the notice and submits no
command. Cancellation controls independently refuse positively offline sends;
the notice itself has no identity, persistence or command responsibilities.
Browser rendering, accessibility, geometry and Android remain runtime evidence.

## Caller-bound current-session callback

For each existing upcoming session the server page passes a no-argument,
read-only callback declared inline with Next's standard server-action boundary.
It captures only that exact session selection and the original verified caller
tuple. It obtains a fresh caller on **every** invocation with
requireAudience('member'), then compares verified userId, tenantId and memberId
to the original render before loadMemberTraining or any other feature read.
A changed or refused caller returns null without a feature read or write.
Only the same original caller reaches loadMemberTraining with that invocation's
fresh request-scoped Supabase client. Return that exact existing caller-owned
session or null; sanitize read failures. No caller identifier argument, browser
Supabase client, credentials in props, new public read route/RPC, identity parser
or module-global caller is introduced.

PtCancelButton refreshes before preparing, reopening and confirming. It uses the
current exact session's cancelCutoff, lateNow, consumesNow and canCancel and
displays the pinned consequence plus absolute local cutoff before submission.
Missing, wrong-session, failed or uncancellable facts cannot fall back to old
confirmation or submit. If the confirmation read changes the displayed
cancellation facts, show the new facts and require renewed explicit confirmation;
the action confirming the old facts sends nothing. The exact inclusive cutoff
and consumption rule remain PTF-013/014; the database decides command-time facts.

The command is only cookie-authenticated POST /api/member/pt-bookings/cancel
with `{ sessionId }`, using the registered envelope and refusal copy. Only an
accepted envelope may show success and refresh the current server render. No
optimistic success, queue or reconnect replay exists. Pending disables duplicate
submission; refusal, network failure and unknown outcome remain truthful.

scopeKey is a presentation lease from the complete verified current identity,
never authority or a command field. Changing it or unmounting permanently
invalidates retained handlers, pending reads/results, confirmation and feedback.
Returning A → B → A never revives the original A lease. Old work cannot issue a
command, publish feedback or refresh the new caller's page.

## Existing dependency declarations for source-blind authors

```ts
// Existing shared nouns and registered API-client envelope (declarations only)
type BusinessNouns = {
  place: string; session: string; sessions: string; class: string;
  classes: string; member: string; members: string; trainer: string;
};
type ApiEnvelope<T> = { ok: true; data: T } |
  { ok: false; error: { code: string; message: string; [detail: string]: unknown } };
type PtCancelResult = {
  sessionId: string; status: Database['public']['Enums']['booking_status'];
  late: boolean; consumed: boolean; sessionsRemaining: number; replayed: boolean;
};
// Cancel route JSON is ApiEnvelope<PtCancelResult>.
// apps/web/lib/identity-session.ts
declare function requireAudience(audience: 'member'): Promise<{
  identity: { kind: 'member'; userId: string; tenantId: string; memberId: string };
  supabase: SupabaseClient<Database>;
}>;
// apps/web/lib/training.ts
declare function loadMemberTraining(client: SupabaseClient<Database>): Promise<MemberTraining>;
declare function loadMemberTrainingHistory(client: SupabaseClient<Database>,
  cursor?: PtHistoryCursor): Promise<PtReadSection<PtSession>>;
// apps/web/lib/business-type.ts
declare function loadBusinessNouns(client: SupabaseClient<Database>,
  tenantId: string): Promise<BusinessNouns>;
// apps/web/app/member/classes/segments.tsx
declare function ClassesSegments(props: { current: 'classes' | 'training' }): React.JSX.Element;
// apps/web/app/status-word.tsx
declare function StatusWord(props: { status: string; label?: string }): React.JSX.Element;
```

Next's router.refresh, standard fetch, browser online/offline events, registered
shared display helpers, ptCopy, ptRefusalMessage and exact status labels keep
their existing public interfaces. Tests may replace these external boundaries
while importing and exercising the actual page and PtCancelButton. They must
capture the callback from the actual returned page and vary the freshly verified
caller, asserting both changed-caller zero reads and same-caller current reads;
a doubled lease factory does not establish the server boundary. Authors read
neither production bodies nor each other's suites. Tests are committed red
before a separate builder creates the page and controls.
