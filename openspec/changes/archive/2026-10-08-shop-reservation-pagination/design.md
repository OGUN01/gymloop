## Context

See proposal.md for the problem. The existing `read_member_shop_reservations()` caps fifty rows and the native screen discloses them three/five. `app.shop_actor('member')` supplies current caller validation. `SHOP_LIMITS.maxOpenReservationsPerMember` is five; `NATIVE_MEMBER_LAYOUT.reservationPreview/reservationLoadMore` are three/five. Existing cache functions provide ordered writes and identity-invalidation leases. Source searches and registry discovery are complete; no new source implementation exists at contract freeze.

## Goals / Non-Goals

**Goals:** bounded transport, stable precise cursors, safe native continuation, released-client compatibility and independently proven caller isolation.

**Non-Goals:** changing stock/hold/payment/fulfilment decisions, rewriting legacy consumers, table policies, adding a generic paging framework, changing Chalkline, or using a cursor as an authorization token. Regional CI execution is a separate contract.

## Decisions

### Frozen database interface

Add `public.read_member_shop_reservation_page(p_after_created_at timestamptz default null, p_after_id uuid default null)`, returning one table row:

| Column | Type | Meaning |
| --- | --- | --- |
| `active_reservations` | jsonb array | Initial only, all current active holds, at most five |
| `history` | jsonb array | Initial at most three; continuation at most five |
| `next_after_created_at` | timestamptz nullable | Exact last returned historical timestamp if lookahead exists |
| `next_after_id` | uuid nullable | Corresponding last returned historical reservation ID |
| `as_of` | timestamptz | Statement timestamp used for all reservation state/expiry decisions |

Each array row has the same field names/values as the existing RPC projection: `reservation_id,item_id,item_name,section,quantity,unit_price_paise,total_paise,currency,state,created_at,expires_at,cancel_reason,terms_changed,order_id,image_asset_id`. No URL/storage field is added. Cursor fields are both null or both present; a partial pair raises `22023`. Initial means both input fields null; continuation requires both and returns an empty active array. History excludes current open holds and orders `(created_at desc,id desc)` with strict tuple comparison. An initial active probe is bounded at six and refuses if it detects more than five; history probes are four/six. State and projection expressions preserve the old RPC semantics. Indexes lead `(tenant_id,member_id)` and support the history timestamp/UUID and reserved expiry orders. No old function/policy/command changes.

The function is `STABLE SECURITY DEFINER`, postgres-owned, empty search_path; ordinary PUBLIC/anon/service_role execute is revoked, authenticated execute granted, and caller verification precedes argument/data handling. Complete auth authority still comes from `app.shop_actor('member')`, never cursor/HTTP fields. Record any needed existing definer metadata in the test-author-owned metadata contract without widening grants.

### Frozen HTTP/shared interface

New `POST /api/shop/catalogue/page`. Auth before JSON/schema validation, standard no-store API envelopes. New strict `shopReservationCursorSchema` is `{createdAt: timezone-aware ISO datetime string, id: UUID}`; timestamps remain strings without Date reserialization. New strict discriminated `shopPageRequestSchema` accepts exactly `{mode:'initial'}` or `{mode:'more',after:cursor}`. No arbitrary page size, tenant/member selector or null continuation cursor.

New strict `shopPageResponseSchema` accepts:

- Initial: `{mode:'initial',items:ShopItem[],reservations:ShopReservation[],nextAfter:cursor|null,truncated:boolean,serverTime:instant}`; catalogue bound remains 200 and reservation bound is eight (five active + three history).
- More: `{mode:'more',reservations:ShopReservation[],nextAfter:cursor|null,serverTime:instant}`; reservation bound five; no catalogue fields.

`ShopReservationCursor`, `ShopPageRequest` and `ShopPageResponse` are inferred types. Existing schemas remain unchanged, especially the legacy catalogue schema whose shape is reused by member cancellation. `loadMemberShopPage(supabase,input)` invokes the new RPC, maps the existing reservation projection and caller-forwarded image signer, and calls the catalogue only for initial mode. `shopPageRoute(request)` uses the existing verified member/API/error helpers. The legacy loadMemberShop/HTTP route remains valid. Reuse item/media projection internally; register new internal helpers only after checking reuse.

### Native state interface and cache reuse

Add `useMemberShopPages()` in `apps/mobile/lib/use-member-shop-pages.ts`, using `useMobile()` identity/API and `Network.useNetworkState()`. Its public return is `{view,loading,loadingMore,error,visibleCount,hasMore,reload,loadMore}`. `view` is null or `{scope,response:ShopCatalogueResponse,savedAt,stale}`; response remains compatible with existing shop cache. Error is null or plain actionable text. `visibleCount` is initialized/reset to three. `hasMore` includes either hidden already-fetched rows or an outstanding history cursor. `reload` and `loadMore` are Promise<void> actions. `loadMore` reveals at most five additional unique rows and requests one continuation only when fewer cached rows remain than the reveal budget and a cursor exists. It never speculatively loops across pages. The caller/refresh lease, continuation guard and cursor remain internal.

Use existing scoped in-memory cache and ordered writer/clear leases; cache stays last-good display data, never proof of current authorization or a resumable offline cursor. Offline reload restores a labelled stale view with continuation disabled until a successful initial read; hidden cached rows remain disclosable. Authorization codes `not_signed_in,not_permitted,unauthorized,forbidden` and any equivalent member-session/RPC denial clear the private cache/view and latch refusal for the caller lifetime. A successful authorized initial read clears that refusal. Identity/API changes and reload synchronously invalidate work before effects complete; unmount invalidates it. Merging returned rows uses reservation ID uniqueness, updates known IDs and retains loaded row identity; active-first display is retained. Native Shop reuses hook state and keeps existing command state, calling reload after every command outcome. Do not change selection, charge copy, catalogue grouping or scroll position for Load more.

### Bar and independence

Comparable backend bar: [Stripe's public cursor pagination contract](https://docs.stripe.com/api/pagination), fetched 7 October 2026: reverse chronological bounded pages, explicit continuation and a clear terminal signal. Own stricter criteria are the exact composite timestamp/UUID order, microsecond preservation, current-member revalidation, active-hold availability and caller lifetime tests; Stripe does not establish those FitCruxx-specific requirements. Use the accepted Chalkline Shop/device evidence for the unchanged visual arrangement.

Two fresh authors read this frozen public contract rather than new implementation; visible and holdout suites are committed red first. The implementer never reads holdout bodies and cannot edit tests. A fresh critic validates actual behavior/SQL authority and the named bar. Preserve all CI gates and BEGIN/ROLLBACK fixtures.

## Risks / Trade-offs

- Active five plus history three means at most eight initial public reservation rows while displaying three. This preserves cancellation availability; requiring a request on every tap would add latency without reducing the visible preview.
- State changes can move a previously loaded active row into history between requests. Merge by ID; refresh resets the population. No multi-request snapshot isolation is claimed.
- JavaScript Date drops database microseconds. Keep cursor text untouched from database through HTTP and client.
- Legacy compatibility retains its old fifty-row cap for older clients. New native clients opt into the new route; a later web migration is separately reviewable.

## Migration Plan

Independent red tests, then one additive migration and implementation commit. Pre-push focused proofs run against Cloud only inside rollback; CI alone applies. After successful migrate, regenerate types through linked CLI, never hand-edit. Require full visible/holdout native pgTAP, drift, seed and app gates before release. Backward compatibility permits keeping the new read unused if needed; no destructive down migration or data rollback is introduced.
