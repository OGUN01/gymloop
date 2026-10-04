# Parallel MEDIA/PAY — browser scenarios and live verification checklist

Prepared 2026-10-04 by the parallel coordinator from the frozen PAY contract
(`openspec/changes/member-purchases/proposal.md`, `docs/design/v2/pay-bar.md`).
Executable only after the primary reports: reviewed source published, relevant
gates green, protected MEDIA Edge deployment complete. Until then nothing here
is run, and no result may be claimed.

## Preconditions (all must be true before any scenario runs)

- P1 Source for the proof extension committed on `main` and CI green.
- P2 Protected MEDIA Edge deployment done (`production-media` environment);
  R2 credentials provisioned; production-origin PUT CORS active.
- P3 Demo data: own member account, a second member (foreign), a real
  front-office verifier account — per `docs/demo-accounts.md` (gym `IRNBX1`).
- P4 A Shop product with stock ≥1, a PT programme, and a held plan exist for
  the demo gym.
- P5 Real external payment means available for the desk to record actual
  amounts (no gateway is involved; recording stays manual).

## Member scenarios (web, then native viewport)

- M1 Request: Shop item "Request" → `/member/buy` shows the typed request with
  server snapshot, quoted amount, exact money formatter, "Pending verification"
  vocabulary nowhere implying payment. Copy check: no "bank verified",
  no "payment successful".
- M2 Accept: desk accepts at `/purchase-requests`; member sees accepted state
  with expiry; physical product accepts a hard hold (stock count reflected).
- M3 Staging upload: accepted request → upload affordance → choose JPG/PNG/WebP
  → PUT succeeds → pending state honest ("Pending verification").
- M4 Rejected file: attempt SVG/oversized/empty → clear rejected-file state,
  no partial state, retry possible, money state untouched.
- M5 Confirm/attach: after upload, proof shows as attached; replacing proof
  preserves history (superseded), no second active proof.
- M6 Private proof view: owning member opens proof; URL is no-store, short
  TTL; reload after expiry re-requests (no cached bytes rendered from disk
  cache); sign-out clears proof URLs; foreign member's id shares the one
  external refusal.
- M7 Verifier view: front-office verifier sees the proof for a same-tenant
  request; trainer account gets the same refusal as everyone else.
- M8 Offline: network off → upload and confirm show clear connection error,
  never queue or claim success; last-good read data flagged stale.
- M9 Rejected proof: desk rejects proof with reason 3–200 chars → member sees
  reason, request back to accepted, can re-upload within original expiry.
- M10 Recording: desk confirms actual received amount/method/currency against
  viewed proof → recorded; member sees "Payment recorded" only after the
  genuine bound ledger receipt; Shop sale created, hold consumed; renewal shows
  actual resulting membership dates (or none, per existing rules).
- M11 Mismatch: desk records different actual amount on Shop/PT → terminal
  state with quoted/received/difference and honest copy; no entitlement shown.
- M12 Cancel/expiry races: cancel after upload before record → closed, hold
  released, no purchase activation; expired request refuses upload/record.

## Negative/authorization scenarios (browser)

- N1 Direct PUT to a published `payment_proof` key fails (no client PUT).
- N2 Expired/foreign asset id in confirm path shares the one external refusal.
- N3 General MEDIA member-url operation refuses `payment_proof` kind.
- N4 Proof URL TTL: replayed POST yields a fresh bounded URL; the object is
  not exposed through any catalogue/signer path.

## Evidence rules

- Every executed scenario: exact URL, viewport, theme, timestamp, screenshot
  path under `docs/evidence/v2/media/`, and pass/fail verbatim.
- A screenshot is evidence for verification; it is NEVER an automatic claim
  that payment was received (contract BUY-008/022).
- Distinguish in every row: authored / built / locally verified / deployed /
  end-to-end accepted. Nothing is marked end-to-end accepted before P1–P5.
