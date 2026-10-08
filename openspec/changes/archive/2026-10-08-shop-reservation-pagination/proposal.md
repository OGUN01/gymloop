## Why

The redesigned native Shop reveals three reservations and five more per tap, but its existing read still fetches up to fifty rows and cannot continue beyond that cap. The owner directed completion of true database pagination before the next closed-test upload on 6 October 2026.

## What Changes

- Add a caller-scoped reservation read with bounded history and a precise total-order cursor.
- Keep all current active holds available, bounded by the existing five-hold rule; show three total reservations initially and reveal up to five more per explicit action.
- Add an opt-in paged Shop HTTP contract and use it in the native Shop, preserving the released legacy HTTP/RPC contracts.
- Preserve exact reservation, money, expiry, image and authorization facts; reject stale continuation responses across identity, refresh and API lifetime changes.
- Keep the existing Chalkline layout, catalogue grouping and palette.

## Capabilities

### New Capabilities

- `shop-reservation-pagination`: bounded member Shop history, active-hold access and safe continuation.

### Modified Capabilities

None. The existing legacy Shop contract and native three/five disclosure requirement remain valid; this adds the bounded database transport beneath the approved disclosure.

## Impact

One additive forward-only read RPC and supporting indexes; CLI-generated database types after CI application; shared schemas; a versioned Shop read route/loader; native Shop state and existing cache reuse. Independent visible and holdout tests precede implementation. No dependency, reservation command, sale/payment/stock logic, table policy, freeze-request logic, backend toggle or Play production rollout changes. Web legacy consumers remain compatible. Database-validation performance and the release upload are separate units documented in the campaign handoff.
