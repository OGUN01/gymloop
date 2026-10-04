# MEDIA/PAY repair round — handback to primary (2026-10-04)

Coordination per `docs/planning/v2-media-pay-repair-handoff.md`. Two fresh
source-only NO-GO critics (15 findings total) → owner-frozen decisions →
independent authors → separate builders → fresh verification critic. All
roles fork/glm per owner directive; anti-inheritance instructions on every
role; disclosed limitation: gpt-6.1-sol not selectable in this harness.

## Commits (this chat, owner-authorized; flagged override of handoff Git rule)

- `2a65789e spec:` / `b6e8b35e docs:` — test gate + frozen decisions
  (pre-repair round; rehashed by gymloop-35's history split).
- `d6d0649a spec:` — test-pin reconciliation to the frozen decisions
  (8 files: bound-viewing → refusal, viewed-tuple pair semantics, retained
  commandKey, 22023 purchase_cap, native fetch harness, holdout env stubs +
  achievable-contract fixtures).
- `ee832348 feat:` — the exact proof runtime protocol across SQL, Edge,
  web and native (13 files, 673+/264−).
- `257804bf docs:` — builder/author/critic reports + progress log.

## Final local state (verbatim)

- Visible repair set (14 files): **1 failed | 236 passed (237)** — sole RED
  is R10 (generated status vocabulary), deliberately pending the primary's
  `gen types` after CI migrate (ADR-177).
- Holdout `pay-proof-runtime-held.test.ts`: **25/25 green** (env stubs
  required for route-import tests — documented).
- registry-lint · check-escape-hatches (948 files) · check-pgtap-rollback
  (159 files) · `deno check` (exit 0) — all green.

## Fresh verification critic (committed: media-pay-repair-final-critic.md)

- All **15 findings from both NO-GO reports CLOSED**; ten critical checks
  PASS.
- Verdicts: (a) SQL/migration **GO** (text-verified), (b) Edge **GO**,
  (c) web/native **GO-WITH-FIXES** — sole residue is the transitional
  status-vocabulary tuple resolving mechanically at the primary's
  post-migrate `gen types` push. No further code change identified.

## Primary-owned steps (exact, in order)

1. Cloud rollback preview + pg_prove of suite 79 plan(246) at migration
   sha256 `d9d0370cb6da489a04fca5286ebe9efcdec6c83c2c36891c1db61eac112894f9`
   (unchanged since the snapshot announced to gymloop-35; SLF/WSP 7-arg calls
   resolve via defaults with grants present).
2. Push → CI migrate → `supabase gen types typescript --linked` follow-up
   (ADR-177) → R10 flips green.
3. Protected MEDIA Edge deployment → live R2 checklist
   (`parallel-media-pay-live-checklist.md`) → browser/Android proof.
4. Whole-v2 acceptance stays primary-owned; nothing here is deployed or
   end-to-end accepted.

## Notes for the primary

- The working-tree `openspec/changes/member-purchases/proposal.md` still
  carries the dirty annotations (GL126, PT slot, BUY-005 rejection). GL126 is
  now REFUTED by frozen decision 6 — the annotation needs REMOVAL, not
  commit; the PT-slot and pre-proof-rejection amendments are owner-approved
  via `proof-runtime-decisions-frozen.md` and may be folded into the
  committed proposal in a primary-owned `spec:` docs pass. The dirty file was
  deliberately NOT committed by this chat.
- `apps/web/lib/purchase.ts` and `purchase-commands.ts` carry another agent's
  pre-existing modifications plus this round's surgical projection edit
  (stripNullFacts removal, flagged in the builder report).
- `record_purchase_request` is now 9-arg (6-arg compatibility wrapper kept);
  `register_payment_proof` has 3-arg and keyed 4-arg overloads; every changed
  signature carries complete owner/revoke/grant (privilege table in the
  builder report).
- knip remains repo-wide RED on pre-existing scratchpad quarantine files
  (identity agent's, 2026-10-03) — unchanged, out of PAY scope.
