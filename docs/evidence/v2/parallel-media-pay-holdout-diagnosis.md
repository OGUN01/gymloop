# Parallel media/pay holdout diagnosis (media-proof-held)

Run: `pnpm vitest run` over media-proof-held / media-edge-held / media-confirm-uuid-held, verbose.
Counts verbatim: `Test Files  1 failed | 2 passed (3)` · `Tests  24 failed | 81 passed (105)`.
Failing file: `supabase/tests-holdout/media-proof-held.test.ts` (24 of its 48). The other two files pass fully.
Method: failing tests exercised against a faithful replica of the holdout transport with only the fixture defects below repaired, then each Class A claim verified directly against `supabase/functions/media/index.ts`.

## Fixture defects found (drive all Class C rows)

- F1: mock's service asset read compares a PostgREST `id=eq.<uuid>` query value against the bare UUID, so every privileged read returns empty — the built source can never see the registered row (the passing media-edge fixture has no such filter).
- F2: mock's copy handler never records the published object, so the contract-mandatory post-copy recheck (amendment §3) always 404s (media-edge fixture sets it in the copy handler).
- F3: mock's caller-scoped asset read passes an object as the Response status arg (throws at runtime) and returns empty where the frozen flow requires the safe projection row (reread/race paths).
- F4: simulated request-truth payload is a bare snake_case array with invented fields; the frozen reader projection is `{requests:[…]}` with camelCase `activeProofAssetId`/`status` (pay_request_json). Fixture header itself assigns this correction to the holdout author.
- F5: proof-url expectation `data.url`/`data.expiresAt` contradicts the frozen sign envelope `{ imageUrl }` (amendment §"Fixed names"; media-edge asserts `data.imageUrl` on the same function).
- F6: confirm-time demand of zero privileged reads for foreign/unknown ids contradicts the frozen first-upload flow — registration links the request on the asset row (`linked_request_id`), and the request's `active_proof_asset_id` is set only at attach, post-confirm; ownership is provable only via the privileged read. The external refusal (404, indistinguishable) is satisfied.

## Per-test classification

| Test (media-proof-held) | Class | Driver |
|---|---|---|
| verified member copy publishes privately only after the caller-JWT request proof | C | F1, F2 |
| foreign owner and unknown asset share one indistinguishable refusal with no privileged read | C | F4, F6 |
| verification failure missing → 409 upload_missing | C | F1 |
| verification failure get-changed → 409 upload_changed | C | F1 |
| verification failure copy-changed → 409 upload_changed | C | F1, F2 |
| verification failure oversize → 422 upload_rejected | C | F1 |
| verification failure wrong-mime → 422 upload_rejected | C | F1 |
| verification failure bad-magic → 422 upload_rejected | C | F1 |
| verification failure postcopy-size → 500 storage_unavailable | C | F1, F2 |
| verification failure postcopy-magic → 500 storage_unavailable | C | F1, F2 |
| verification failure embedded-copy-error → 500 storage_unavailable | C | F1, F2 |
| verification failure copy-missing-etag → 500 storage_unavailable | C | F1, F2 |
| a rejected attempt requests unconfirmed-only cleanup, deletes no published object | C | F1 |
| confirmed replay never recopies a reused staging PUT, revalidates the active caller | C | F1, F2, F4 |
| unknown finalizer outcome timeout-unconfirmed retains the candidate | C | F1, F2, F3 |
| unknown outcome with an authoritative same-candidate winner keeps the object | C | F1, F2, F3 |
| a definitive concurrent winner is preserved; loser cleans only its own candidate | C | F1, F2, F3 |
| revocation or deletion at the locked finalizer never finalizes | C | F1 |
| the owning member obtains the current active proof URL, no-store, ≤60s | C | F1, F5 |
| a real same-tenant front-office verifier obtains the same bounded URL | C | F1, F5 |
| foreign proof access shares the one external refusal | A | see below |
| unknown proof access shares the one external refusal | A | see below |
| no money command ever dispatches inside the MEDIA boundary | C | F1 |
| staging PUT failure changes nothing: no finalization, no money effect | C | F1 |

## Class A (verified in source)

- `proof-url` must refuse — from the caller-JWT request read alone, before any privileged metadata read — any requested asset that is not the currently active proof of a live request visible to the caller (own member row, or same-tenant front-office row); foreign, unknown and superseded ids share that one refusal. At URL time the frozen attach flow guarantees the linkage exists in the reader projection, so a zero-privileged-read refusal is achievable.
- Source gap: `proofUrl` (index.ts:250-254) runs the request-truth read with linkage enforcement off, then immediately performs the trusted asset read (index.ts:252) and only afterwards checks tenant/kind/ownership — so a foreign or arbitrary confirmed proof id costs a privileged read before the (correct) refusal. The bound-and-live linkage check already implemented in `proofExposure` (index.ts:235-239) is simply not required for this operation. By contrast the confirm-side zero-privileged-read demand (row 2) is not achievable in the frozen first-upload flow — that one stays Class C per F6.

## Summary

- Class A (Edge source gap): 2 — both proof-url exposure-binding tests.
- Class B (DB-path, pending Cloud preview): 0 — every failing test exercises the Edge HTTP surface over mocked transports; the SQL RPCs themselves (register_payment_proof / finalize_media_asset / read_purchase_proof_url) are not the subject here and remain covered by Cloud-run pgTAP.
- Class C (fixture defect vs frozen contract): 22.
- Recommended next step: holdout author applies F1-F5 and re-runs; owner decides F6 (relax the confirm-side assertion) and the builder closes the single Class A gap in `proofUrl`. All 22 Class C rows are expected green against the current source once F1-F5 land.
