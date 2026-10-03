# PT booking reuse declarations

Frozen engineering composition, 2026-10-03. Preserves the approved member
booking, exact retry, caller/focus revocation, interval and consumption rules.
Four actual duplicated responsibilities move to these narrow existing-layer
primitives; no actor, booking, money, policy or UI contract changes.

## Shared platform-free Training projection

In `packages/shared/src/api/pt-front-data.ts`:

```ts
export function ptBookingTrainingFacts(
  training: MemberTraining, orderId: string,
): { pack: PtPack | null; sessions: PtReadSection<PtSession> };

export function ptBookingCancellationConsumption(
  sessions: PtReadSection<PtSession> | undefined,
  answer: Pick<PtSession, 'sessionId' | 'orderId' | 'startsAt' | 'endsAt'>,
): boolean | null;
```

Training projection selects a pack only from a succeeded packs section with
array data and exactly one exact order-id match. Otherwise pack is null.
Combine upcoming/history sessions only when both sections have error === null
and array data; otherwise sessions is `{data:null,error:'retryable'}`. Returned
sessions stay complete member facts; no current product/kind filter or invented
consumption is added. Inputs remain unchanged.

Consumption returns the actual boolean only from a succeeded section and
exactly one row matching all four supplied identity/recorded-instant fields.
That row must be cancelled_by_member, have a boolean consumed and pass the
registered ptRecordedInterval validator including its timezone. Missing,
failed, nonmatching, duplicate or invalid facts return null; false is positive
evidence of no consumption. No completed/refund/forfeiture inference.

These functions are synchronous and read no claims, clock, client or storage.
The surfaces still await their fresh reads and prove their original permanent
caller/focus capability after every await, before publication or helper use.

## Existing decoder, one public booking answer boundary

In `packages/shared/src/api/pt-front.ts`:

```ts
export type PtBookingAnswer = z.infer<typeof bookedAnswer>;
export function ptBookingAnswer(
  data: unknown, command: z.infer<typeof ptBookRequestSchema>,
): PtBookingAnswer | null;
```

The private bookedAnswer schema remains canonical. Accept only a non-null
nonarray public camel-case response object; map its existing public fields to
the registered ptCommandAnswer('book', ...) boundary. Require exact sessionId,
orderId and startsAt equality with the command, and a valid recorded end later
than the submitted start. Return the decoded camel-case public answer or null.
Its existing fields are sessionId, orderId, startsAt, endsAt, status,
inCancelWindow and replayed; no other result vocabulary is introduced.
The existing generated-enum restriction excluding session_cancelled remains
authoritative. Do not add a status validator, fallback status or new copy.

Both platforms retain their existing HTTP/RPC envelope checks before this
boundary. Null retains the uncertain sheet and original body/UUID for explicit
retry. Transport, changed-facts confirmation, lifetime and status/neutral
feedback logic remain in their respective surfaces.

## Fresh original-member web action caller

New thin server adapter `apps/web/lib/member-action-caller.ts` imports the
registered requireAudience from identity-session; the identity core is unchanged.

```ts
export async function requireOriginalMember(
  original: Pick<Extract<GymloopIdentity, {kind:'member'}>,
    'userId' | 'tenantId' | 'memberId'>,
): Promise<Awaited<ReturnType<typeof requireAudience<'member'>>> | null>;
```

Freshly call requireAudience('member'), then require exact original user,
tenant and member equality. Return that current caller only on equality;
refusal/throw/mismatch returns null. No retained client/cache, alternate guard,
admin key, token transport or caller supplied by navigation. The Classes and
booking captured server actions read only through a non-null current caller;
they preserve their existing failure handling for subsequent reader calls.
The equality comparison is essential: requireAudience proves audience, not
equality with the original captured caller.

## Tests-first reuse integration

Independent visible and holdout authors pin success/failure boundaries,
malformed/CLS-only answers, exact retry identity, duplicate/invalid consumption,
and all three original-caller equality checks. Their tests commit before the
separate source builder. Existing web/native rendered booking, focus, cutoff,
uncertain replay and changed-caller tests remain unchanged and are rerun after
integration. No duplication exclusion or formatting workaround is allowed.

## Remaining cancellation feedback and open-slot grouping reuse

Frozen engineering continuation, 2026-10-03. This changes no business rule,
retry, asynchronous lifetime or presentation vocabulary. Two remaining shared
responsibilities belong in the existing platform-free pt-front-data module:

```ts
export function ptBookingCancellationFeedback(
  sessions: PtReadSection<PtSession> | undefined,
  answer: Pick<PtSession, 'sessionId' | 'orderId' | 'startsAt' | 'endsAt'>,
  placeNoun: string,
): { message: string | null; label: string | null };

export function ptBookingOpenSlotGroups(
  pack: PtPack | null | undefined,
  slots: PtReadSection<{
    startsAt: string; endsAt: string; timezone: string;
  }> | undefined,
  orderId: string,
  now: number,
): Map<string, { startsAt: string; endsAt: string; timezone: string }[]>;
```

Cancellation feedback delegates to registered ptBookingCancellationConsumption.
Unavailable consumption returns exactly message `Cancelled. Reload to check
whether a session was used.` and null label. An authoritative boolean returns
null message and the existing ptBookingStatusLabel('cancelled_by_member',
consumed, placeNoun). False remains authoritative no-consumption evidence.
Both surfaces still publish their initial neutral acknowledgement, await their
own fresh read and verify their original permanent lifetime before this helper.
They publish through their existing web status object/native status string;
there is no shared asynchronous control, seventh status or changed copy.

Open-slot grouping returns an empty Map for a nonfinite now, missing/wrong-order
pack, non-live pack, canBook other than true, failed/missing/nonarray slots.
For a succeeded section, retain only valid ptRecordedInterval rows whose start
is strictly after supplied now; group using registered toLocalDate in each
row's own timezone. Preserve day insertion order and original slot order and
objects, without mutating inputs or reading a clock. Both surfaces supply their
own Date.now(), and retain existing selection/rendering. No generated calendar,
new availability inference, filtering by current product or alternate timezone.
The existing groupSlotsByLocalDay uses one timezone and cannot own this exact
row-zone and own-live-pack boundary without changing its public contract.

Independent visible/holdout additions commit RED before the separate builder
adds these exports or integrates them. Earlier tests remain unchanged.
