# Phase 3 — Core domain, and the first screens

One document, per ADR-060. The EARS spec stays separate (`specs/`), because that is what tests derive from and what an independent author reads.

## Why

Phase 2 built an identity layer nobody has used. `auth.users` is empty, `platform_users` is empty, and the access-token hook — live on the project since 2026-09-08 — has never issued a claim to a real person. Everything proven so far is proven by pgTAP setting `request.jwt.claims` by hand.

Phase 3 is where the product starts existing. Under **ADR-059** it ships a **vertical slice**: schema, endpoint, and a screen the owner can click. At the end of it a gym owner signs in, sees their members, and a member checks in with a QR code — on a real device, against the real database.

## What changes first — the process migration (ADR-060)

These land **before any agent is dispatched**, because two of them make everything after cheaper.

- [ ] **Holdout suite into this repo**, `supabase/tests-holdout/`. Move the 12 files by content, delete `github.com/OGUN01/gymloop-holdout`'s role as a dependency, drop the cross-repo checkout and the `HOLDOUT_DEPLOY_KEY` step from `db.yml`, and rewrite hard rule 10 in `AGENTS.md` and ADR-043 (superseded). The second independent author stays; the second repository goes.
- [ ] **Shared pgTAP fixtures.** 35 files each build two gyms from scratch; 1,928 assertions take **688 seconds**. One fixture function, called per file inside the same `begin … rollback`. Stop asserting the role matrix in both suites — the holdout keeps the behavioural half, the visible suite keeps the catalogue half. **Target: under 240 seconds.**
- [ ] **`plan.md` replaces `proposal.md` + `design.md` + `tasks.md`** — this file is the first instance.
- [ ] Shorter ADRs: decision, why, what was rejected.

## What the slice is

**The bar** (`docs/architecture.md`): Square POS for the front desk, a metro gate for check-in — sub-second scan to confirmation, where latency *is* the design.

| Layer | Phase 3 ships |
|---|---|
| Schema | Nothing new. Phase 1's tables carry all of this; if a migration is needed, that is a finding. |
| Auth | Staff email sign-in end to end. **Member phone-OTP is blocked** — no SMS credential exists (ADR-058). |
| Endpoints | Route Handlers for: assisted check-in, QR check-in, member create/edit, membership create. First `packages/api-client` (OPEN-002, deferred here from Phase 2). |
| Screens | Sign-in · member list with search by phone · member detail · **check-in screen** · a front-desk assisted check-in with its mandatory reason (ATT-005/006). |
| Rules | ATT-001 to ATT-008, STK-001 to STK-004, and the pause rules from `docs/domain-rules.md`. |

**Out of scope, named so it is not assumed:** offline queue and replay (ATT-007) ships with the mobile app in Phase 7 — a web page is not the device that goes offline in a gym basement; streak *display* is Phase 7's, the computation is here.

## Process, calibrated (ADR-059)

| Work | How |
|---|---|
| Any RLS or policy change | Full blind arrangement — independent test author, holdout author, implementer, fresh-context critic |
| Check-in correctness — double-scan, exactly-once, the dedupe window | Full blind arrangement. A duplicate attendance row is **silent**. |
| Endpoints, screens, CRUD | One implementer. Spec-first, tests-first, every CI gate. |

**Fix the contract, then fan out.** Phase 2 spent about a third of its round-trips on edits made after agents were already working. If a finding changes the contract mid-flight, that is evidence it was not ready.

## Tasks

- [ ] The four process changes above.
- [ ] **Owner step, and nothing proceeds without it:** sign up with a real email, then `gh workflow run bootstrap-platform-user.yml -f email=… -f full_name=…`. There is no super admin, so there is nobody to create the first gym.
- [ ] Seed a real gym through the product rather than through `seed.sql` — the first proof the write path works.
- [ ] EARS spec for check-in, assisted check-in, and the dedupe window.
- [ ] Tests, then endpoints, then screens.
- [ ] Run the real app: sign in, list members, scan a code, see attendance land. Screenshot it.
- [ ] Blind critic, gates, archive.

## Exit criteria

The roadmap's are "holdout suite green; double-scan and offline replay produce exactly-once attendance". Amended by ADR-059 to add: **the owner signs in on their own phone and checks a member in.** A phase that cannot be demonstrated has not shipped.
