# Native Training deferred media lease — public clarification

Status: frozen clarification of the existing permanent presentation lease,
2026-10-03. This adds no permission, policy, endpoint or persisted cache.

The existing read adapter awaits the five caller-scoped projections before
requesting display URLs. Every deferred URL request must still belong to the
current permanent Training presentation lease. Unmount, readiness loss, caller
change, supplied API replacement or read-client replacement revokes that lease;
returning to the earlier value never restores it. Already-started requests may
finish, but revoked continuations cannot initiate another media request or
publish their result. A failed image remains the existing placeholder.

The existing adapter gains only an optional refusal predicate:

```ts
declare function loadTraining(
  client: SupabaseClient<Database>,
  api?: ApiClient,
  shouldContinue?: () => boolean,
): Promise<MemberTraining>;
```

TrainingSection supplies its existing permanent current-lifetime predicate on
every read. The adapter checks that predicate synchronously immediately before
each api.post('/api/member/media-url', { assetId }), without an intervening await.
False or a throwing predicate requests no URL and falls back to the placeholder.
An omitted predicate preserves the existing adapter interface for callers that
do not own a rendered lease; it cannot widen server authority.

Independent visible and held authors pause actual projection completion, revoke
the supplied lease, then return listed trainer image metadata. They verify zero
obsolete media calls, including API/read-client/caller ABA and unmount. They also
pause the first image request, revoke, and verify subsequent image requests do
not start. Current leases still request exact asset IDs through the existing API;
false/throwing predicates fail closed. These tests precede the separate builder.
No private image key, staff identifier, token or new media parser is introduced.
