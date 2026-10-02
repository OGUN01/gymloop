# SHP bar — Shop, reservations and MEDIA (V2-B2, F3)

Written 2026-10-02, before tests. Contract: `openspec/changes/shop/proposal.md`; authority: batch-2 `decisions.md`. Fetches below are official public documentation; no login, screenshots or deployed product inspection was performed. These are observable documented behaviours, not proof that Gymloop passes. Unobserved UI and all reservation choices are **[own]**.

## References and limits

| ID | Fetched primary reference | Observable quality | Limit |
|---|---|---|---|
| SHP-R1 | [Shopify Product media types](https://help.shopify.com/en/manual/products/product-media/product-media-types) | Product imagery supports understanding an item; documentation specifies image media constraints. | Gymloop's one-image, 2 MiB choice is its own. No storefront or reservation screen was observed. |
| SHP-R2 | [Cloudflare R2 Presigned URLs](https://developers.cloudflare.com/r2/api/s3/presigned-urls/) | Temporary object access; signing a MIME header restricts PUT content type; browser use requires CORS. | Documentation does not establish content-length or magic-byte validation; those are own server checks. |

## Criteria — all must pass

| ID | Observable criterion | Test / critic evidence |
|---|---|---|
| SHP-Q1 | Image or placeholder, real item name, price and availability word on every tile. [own, informed by R1] | Screenshot light/dark list and failed-image tile; accessible name remains text. |
| SHP-Q2 | Reserve in at most three taps from list; final sheet states no app charge, desk payment and hold expiry. [own] | Count taps and compare exact `shopReserveNotice`; no purchase/payment state invented. |
| SHP-Q3 | Reservation state words distinguish Reserved, Expired, Cancelled, Cancelled by the gym, Collected. [own] | Drive every state and inspect visible/accessibility text. |
| SHP-Q4 | One Save after choosing a file; chosen/uploading/verifying/saving/saved and each upload refusal visibly named. [own] | Component state tests, plus real browser upload after owner configures CORS. |
| SHP-Q5 | Unsupported MIME, oversized bytes and bad magic are refused by trusted Edge; staged objects publish only by verified ETag-conditional copy, reused PUT cannot replace published image, direct confirm is denied, member RPCs expose asset id only. [own, R2 mechanism] | Blind DB/app/Edge probes: source race, post-copy mismatch, concurrent confirms, actor revocation, unknown-outcome cleanup and key-column grants; signed URLs/keys absent from logs/errors, history FK survives object pruning. |
| SHP-Q6 | Every reservation refusal states outcome and next action; refresh item after refusal. [own] | Assert pinned copy and refresh with quote-change/sold-out cases. |
| SHP-Q7 | No member stock count; capped quantity stepper and availability word only. [own] | Inspect list/detail/confirmation with low and zero stock. |
| SHP-Q8 | Desk list distinguishes reserved/current price, expiry, member-visible cancel reason, and sell result. [own] | Quote-change and fulfil/refusal screenshots; existing money flow tests unchanged. |
| SHP-Q9 | In-memory identity-scoped last-good mobile copy is flagged with saved time; offline reserve/cancel disabled, never queued. [own] | Offline, failed fetch, sign-out, identity change and app restart probes. |
| SHP-Q10 | Gate-30 states; both themes, 390 px mobile/1440 px web, 200% text, reduced motion, 44 px targets and accessible controls. [own] | State matrix evidence, accessibility audit and clipped-content inspection. Chalkline only. |

The critic reports pass/fail for every row with actual evidence. Three rejections of the same dimension escalate as a contract problem. No screenshot or test pass is claimed by this bar. Final tabs, legal and seed integration remain centrally owned; the critic reviews mounted screens after integration.

Owner-approved MEDIA amendment (2026-10-02) fixes one shared Edge verifier/signer, original-JWT current exposure, protected-CI deployment/configuration, service-only finalizer and immutable publication. No new Edge/native packages; the web presigner remains approved web-only. SHP-Q4/Q5 must demonstrate this protocol, not just a successful upload animation. Issued GET URLs last at most 900s; screenshot review cannot prove grant/race correctness.
