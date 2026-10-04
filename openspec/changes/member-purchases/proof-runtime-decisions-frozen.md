# PAY / MEDIA proof runtime — FROZEN decisions (owner-approved, 2026-10-04)

Authority: owner decisions recorded in the parallel repair coordination
session, 2026-10-04. This document freezes the serial decisions the review
draft `proof-runtime-protocol-declaration.md` required before author fan-out.
The declaration's other clauses stand as written unless amended here.

## Owner decisions (binding)

1. **Active-only proof viewing.** The committed contract stands: only the
   currently ACTIVE proof of a live request is viewable through the private
   proof URL, by the owning member or the real same-tenant front-office
   verifier. Recorded/mismatch_recorded/bound history is safe metadata only —
   no URL, no object access. The earlier bound-path viewing behavior
   (Edge served statuses including `recorded`/`mismatch_recorded`; SQL
   evidence helper serving bound proofs; suite-79 re-obtain cases) is
   REVERTED. Trainers, preview, impersonation, catalogue exposure: unchanged
   refusals.
2. **Dirty annotations now owner-approved (traceable authority = this
   document):** (a) BUY-005 gains the accepted→rejected transition (desk may
   reject an accepted request before proof, consistent with BUY-011);
   (b) `record_purchase_request` carries `p_initial_slot jsonb default null`
   for PT completion (trainer/slot ids validated server-side through existing
   PTF booking locks — never client-trusted; exact-price PT recording without
   a valid slot refuses and the request never strands unbound).
3. **Recorder binds exact viewed evidence via explicit parameters.**
   `record_purchase_request` gains explicit viewed-asset and
   viewed-proof-revision parameters; SQL compares them under request/proof
   locks before any ledger work. An old verifier context cannot record a
   replaced proof; proof replacement invalidates the earlier decision context
   even when price is unchanged. Replay facts include the viewed tuple.

## Mechanical adoptions (declaration clauses, resolved)

4. **Renewal revision semantics:** renewal creation sends explicit null
   `expectedRevision` (never a fake or derived UUID; null never means
   skip-check). Every accepted command echoes the request's real revision;
   renewal revision comparison is the immutable sold-terms snapshot against
   the live held membership.
5. **Registration retry identity:** `register_payment_proof` gains a
   command-key parameter (migration unapplied; seam is an implementation
   boundary, not a committed-contract RPC). Same actor/key + same normalized
   requestId/MIME/bytes replays the same asset/staging facts without another
   counter/deadline; changed facts conflict. Clients retain the registration
   key across unknown outcomes and never generate a new one for the same
   logical upload.
6. **GL126 is NOT authorized** (committed allocation stops at GL125): remove
   GL126 from the migration and all transport mappings. BUY caps (5 open,
   10/day, 10/hour) refuse with `22023` and a stable DETAIL marker
   (`purchase_cap`), mapped to HTTP 429 `rate_limited` through the existing
   DETAIL-mapping pattern (the `23514 proof_media_refused` precedent).
7. **Proof-view capability:** same-origin expiring capability minted in the
   existing trusted MEDIA runtime boundary only; bound to
   request/proof/asset + issue/expiry instants; expiry mandatory, ≤
   issuedAt + 60s, never reset or extended by a GET; no new secret, admin
   route or database-produced R2 signature.
8. **Currency:** preserve actual received currency under the frozen BUY-014
   and canonical-currency rules; accepted quotes/fulfillment remain INR; no
   silent rejection or conversion of permitted facts.
