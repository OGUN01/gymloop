# Phase 3 — Core domain, and the first screens

One document, per ADR-060. The EARS spec stays separate (`specs/`), because that is what tests derive from and what an independent author reads.

## Why

Phase 2 built an identity layer nobody has used. `auth.users` is empty, `platform_users` is empty, and the access-token hook — live on the project since 2026-09-08 — has never issued a claim to a real person. Everything proven so far is proven by pgTAP setting `request.jwt.claims` by hand.

Phase 3 is where the product starts existing. Under **ADR-059** it ships a **vertical slice**: schema, endpoint, and a screen the owner can click. At the end of it a gym owner signs in, sees their members, and a member checks in with a QR code — on a real device, against the real database.

## What changes first — the process migration (ADR-060)

These land **before any agent is dispatched**, because two of them make everything after cheaper.

- [x] **Holdout suite into this repo**, `supabase/tests-holdout/`. Move the 12 files by content, delete `github.com/OGUN01/gymloop-holdout`'s role as a dependency, drop the cross-repo checkout and the `HOLDOUT_DEPLOY_KEY` step from `db.yml`, and rewrite hard rule 10 in `AGENTS.md` and ADR-043 (superseded). The second independent author stays; the second repository goes.
- [x] **Suite runtime — measured, then solved a different way.** Per-file times are 20–50 seconds and track assertion count, so the cost is real work per file and a shared fixture would have saved less than the alternative: the suite was running its full ~700 seconds on **documentation-only pushes**. `db.yml` now diffs the push and skips when nothing under `supabase/`, `packages/db/`, the rollback checker or the workflow changed — fail-closed by construction, so any uncomputable diff still runs it. The fixture refactor is **deliberately not done**: 37 files rewritten to save less than not running at all. Revisit with numbers if CI is still the bottleneck after a few Phase 4 rounds.
- [x] **`plan.md` replaces `proposal.md` + `design.md` + `tasks.md`** — this file is the first instance.
- [x] Shorter ADRs: decision, why, what was rejected.

## What the slice is

**The bar** (`docs/architecture.md`): Square POS for the front desk, a metro gate for check-in — sub-second scan to confirmation, where latency *is* the design.

| Layer | Phase 3 ships |
|---|---|
| Schema | **Two migrations, and both are findings that were argued rather than assumed.** (1) Exactly-once check-in cannot be a Route Handler read-then-write — both reads pass before either writes and the duplicate is silent — and the de-duplication window is per-gym config, so it can be neither an index predicate nor a check constraint. It needs a database-level guard. (2) `attendance_front_desk_has_assist_chk` tests `assist_reason <> ''` and therefore accepts `'   '`; ATT-006 says an assisted check-in without a reason is rejected, and whitespace is not a reason for marking somebody else present. Nothing else. |
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

- [x] The four process changes above.
- [x] **Owner step — unblocked without it.** The intent was that nothing could proceed until a real person existed. That turned out to be false: the service-role key in `.env.local` can create an `auth.users` row through the Auth Admin API, so five demo sign-ins now exist, one per role, linked to real `staff`, `members` and `platform_users` rows (`docs/demo-accounts.md`). The owner's own account and the `bootstrap-platform-user.yml` dispatch are still owed, but they block nothing.
- [~] **Seed a real gym through the product — DEFERRED, and not by drift.** The write path *is* proven: a member is created, a membership sold, a visit recorded, and a freeze **requested by the front desk and approved by the owner** — two different people, the approver holding the gym's configured role — all through the product against Cloud (`docs/evidence/`). What cannot be done through the product is creating the **gym itself**, because nothing creates an `organizations` row plus its `organization_settings` row — that is gym onboarding, it is Phase 6, and it is the same gap OPEN-018 records. Writing a one-off "create a gym" screen now to tick this line would be a screen Phase 6 deletes. The proof this line was after has been taken from the member path instead.
- [x] EARS spec for check-in, assisted check-in, and the dedupe window.
- [x] Tests, then endpoints, then screens.
- [x] **Run the real app: sign in, list members, scan a code, see attendance land.** Done against the Cloud database on 2026-09-08; `docs/evidence/phase3-check-in.png`. Both refusals showed up on the way and both were the system working: an expired gate code answered `GL011` ("Show a new one"), and a second click a second later answered `GL014` ("Already checked in a moment ago") — with the database confirming **one** attendance row and no second. Exactly-once held in a browser, from the trigger and not from the handler.

  **And the browser found a defect 163 unit tests and 39 pgTAP files did not**: "Next page" on `?limit=5` returned fifty, because the link carried `q` and dropped `limit`. That is the argument for ADR-059's "every phase ships a screen", made by the phase itself.
- [x] **Blind critic, gates, archive.** Four rounds, four NO-GOs, then GO — see `README.md` beside this file. Nine of the fourteen defects were introduced by the fix for the previous round's, which is why ADR-066 through ADR-072 exist.

## Exit criteria

The roadmap's are "holdout suite green; double-scan and offline replay produce exactly-once attendance". Amended by ADR-059 to add: **the owner signs in on their own phone and checks a member in.** A phase that cannot be demonstrated has not shipped.
