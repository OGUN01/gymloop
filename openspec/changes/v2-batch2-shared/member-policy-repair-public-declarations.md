# Approved member booking-policy reads — public declarations

Frozen 2026-10-03 after explicit approval of all five scoped batch-2 repairs.
The CLS prebooking-cutoff and PTF member-policy-read amendments supersede only
the precise older null-deadline/policy-unavailable boundaries. Their original
proposals and bars otherwise remain authoritative. No applied migration is edited.

## SQL test/build boundary

One forward-only follow-up migration is fixed as
`supabase/migrations/20261003160000_member_booking_policy_reads.sql`.
It changes only the existing CLS schedule projection's `cancel_by` predicate
as approved and adds the approved stable postgres-owned, empty-path DEFINER
`public.read_member_pt_policy()` two-column read. PUBLIC/anon/service_role
execution is revoked; authenticated execution is granted. Its complete caller
validation is exactly the existing private `app.pt_member_actor()`; no new
claim, private grant, RLS policy or settings-table grant. Missing settings
returns zero rows. No writes, locks, audit or notification.

Independent visible SQL owns `supabase/tests/77_member_booking_policy_reads.sql`
and the exact new signature in `04_contract_meta.sql`; independent held SQL owns
`supabase/tests-holdout/h77_member_booking_policy_reads.sql`. Both authors may
amend only their own existing unbooked-null oracle where it is superseded by
the approved CLS projection. Everything else stays unchanged. Root commits
tests RED before a separate source builder; all Cloud proof is rollback-only.

## PTF application declarations

```ts
// packages/shared/src/api/pt-front-data.ts
type PtMemberPolicy = { cancelWindowHours: number; lateCancelConsumes: boolean };
type PtPolicyRead = { data: PtMemberPolicy | null; error: string | null };
type PtPolicyReadClient = {
  rpc(name: 'read_member_pt_policy'): PromiseLike<{ data: unknown; error: unknown }>;
};
declare function readMemberPtPolicy(client: PtPolicyReadClient): Promise<PtPolicyRead>;
// apps/web/lib/training.ts
declare function loadMemberPtPolicy(supabase: StaffSession['supabase']): Promise<PtPolicyRead>;
// apps/mobile/lib/training.ts
declare function loadPtPolicy(client: SupabaseClient<Database>): Promise<PtPolicyRead>;
```

The existing platform adapters retain the supplied authenticated caller. The
new narrow transport type adds no alternative client or authority and avoids
pretending the current generated Database already contains an unapplied RPC.
The shared helper calls only `read_member_pt_policy` with no
tenant/member selectors. An empty successful projection is `{data:null,error:null}`.
One successful row requires both the current integer cancellation window in
the existing PTF-019 range 0..168 and an actual boolean late-consumption flag.
Malformed, duplicate, incomplete or failed results return null with a sanitized
retry error; never parse strings as booleans, select an arbitrary row, fall back
to a default or expose database messages. Thrown transport failures are sanitized.
The existing five-section Training reader and existing-session cancellation
projections/signatures remain unchanged.

The approved PTF-029/030 booking pages keep their original frozen routes and
web `PtBookingForm` and native default route export in the original PTF proposal
and `pt-front/application-interface-clarification.md`. New or reopened confirmation
reads policy as the current caller before enabling Confirm. Null/loading/error
policy disables commitment and permits retry. Current pack/slot facts, caller
lifetime, one sheet session id, exact retry body, server authority, offline
no-send/no-queue behavior and the original `ptBookingConsequence` remain required.
This packet authorizes the formerly blocked booking surface; it does not change
booking eligibility, balances, sold terms or the command contract.

## CLS application boundary

Existing registered web/native class readers and rendered signatures remain.
Before preparing a new booking confirmation, refresh the current caller's
schedule. Confirm only an exact available row carrying the approved authoritative
absolute `cancelBy`, displayed in that session's timezone. Missing/failed/changed
facts disable commitment or require fresh confirmation; no client setting default.
The separate approved final-send-cutoff amendment applies after every awaited
network preflight: the final synchronous cancellation guard includes current
caller lifetime and eligibility at the inclusive returned deadline, with no await
between guard and command invocation. These two repairs do not reclassify actors.
