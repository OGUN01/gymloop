# 0003-core-domain

Phase 3: the core domain — QR check-in with exactly-once, the assisted front-desk fallback, the member roster and check-in gate as real screens, memberships, the pause decision, streaks, and scenario data shaped so the retention loop can be exercised.

**The first phase to ship a screen** (ADR-059), and the phase that produced this project's longest gauntlet: **four critic rounds, four NO-GOs, then GO.**

## Exit criteria met

`docs/roadmap.md` asks for a check-in that is exactly-once and a screen the owner can use. Both are proven by a run and a browser, not a tick:

- **Run `34238xxxxx` (head `a177635`)** — all four workflows green: `CI`, `DB` (migrate + `pgtap-rollback` + `schema-drift` + the full TAP stream through `prove`), `Holdout`, `Test immutability`. **39 pgTAP files, 2152 assertions.**
- **`docs/evidence/phase3-check-in.png`** — the check-in gate answering *"Already checked in a moment ago"* one second after a successful scan, with the database holding exactly one attendance row and no second. Exactly-once demonstrated from the trigger, not the handler.
- **`docs/evidence/phase3-pause-approved.png`** — a freeze requested by the front desk (Divya Menon) and approved by the owner (Kabir Shah), two different people, the approver holding the gym's configured role. **The first time that path ever ran**, and it only ran because the round-four critic found that the demo gym configured an approver role it did not employ.
- 170 web tests, `registry-lint`, `check-escape-hatches`, `check-pgtap-rollback`, `check-test-immutability` all green.

## What was built

| Migration | Contents |
|---|---|
| `20260908071401_check_in_exactly_once` | `app.enforce_check_in()`, `before insert` on `attendance`: advisory lock, per-gym window, QR session validity at the instant of the scan |
| `20260908071731_attendance_assist_reason_not_blank` | `assist_reason !~ '^\s*$'` — `<> ''` accepted three spaces, and `btrim()` accepted a tab |
| `20260908081957_check_in_trigger_runs_as_invoker` | one word: `definer` → `invoker` (ADR-066) |
| `20260908090000_phase3_approver_boundary_and_missing_settings` | the pause approver moves to the table; `pause_approver_role` narrowed to roles RLS admits |
| `20260908150000_pause_decision_on_insert_and_stays_decided` | `before insert or update`; a decision is final |
| `20260908170000_attendance_is_written_once_and_a_decider_is_identified` | column freeze on `attendance`; `row_security_active()` carve-out; `GL016` |
| `20260908190000_a_frozen_column_list_goes_stale` | both denylists become `to_jsonb` allowlists; the deciding statement is governed |
| `20260908210000_a_rule_that_reads_a_nullable_column` | the null actor named as its own clause; `membership_pauses_approver_pairs_with_approval_chk` |
| `20260908230000_a_rule_that_only_refuses_belongs_after_the_policy` | the pause trigger moves to AFTER |

Plus `apps/web`: the sign-in, console, roster with cursor pagination, check-in gate, member and membership screens, and four Route Handlers with declared zod schemas.

## What this phase actually taught, which is worth more than the code

Nine of the fourteen defects found across four rounds were **introduced by the fix for the previous round's defect**. That is the single most reliable fact about this phase and it is why ADR-066 through ADR-072 exist. In order:

- **ADR-066** — a privilege boundary crossed in something that runs *before* the boundary it was meant to respect. Two directions: over-reaching (elevating past a sufficient boundary) and under-claiming (a rule left outside a boundary that never claimed it).
- **ADR-067** — a trigger's event list is a place a rule can be left out of; and in a `before` trigger, falling out of a branch *is* a decision to permit.
- **ADR-068** — "A must differ from B" is a control only if one of A and B is outside the writer's reach **in that statement**; and a trusted-context carve-out must test the property it means, not a symptom that correlates with it.
- **ADR-069** — `num_failed()` is not verification. CI's `prove` checks the TAP *stream*, and a bare `select` returning the string `ok` invents passing tests.
- **ADR-070** — immutability is per-statement and INSERT is a statement; a denylist of frozen columns is incomplete on the day it is written, not stale over time.
- **ADR-071** — a rule that reads a nullable column is not a rule until the null case is written down. `null is distinct from null` is false.
- **ADR-072** — a rule that only refuses belongs *after* the policy; only a rule that must modify the row needs to run before it.

**And five times, a confident comment stopped the next person looking.** A migration header describing a rejected draft as if it shipped; a docstring claiming the table refused what only UPDATE refused; a function comment claiming a gap was closed at its source when it is OPEN-018; a comment claiming a null actor was refused when it was not; and a seed comment calling a real gap "a known oddity … not a gap here". **A comment claiming a gap is closed has to be verified like code, because its whole function is to stop the next person looking.**

## The blind arrangement earned its cost

- The **holdout author** found three defects the visible suite passed over, then a fourth inside the fix for them — including the one no critic reached, that approving and moving `ends_on` in the same statement succeeded.
- Two blind authors, in separate sessions and separate fixture spaces, **converged on the same NULL hole from opposite directions**.
- A test author caught **its own tests passing for the wrong reason** by inverting them, and another caught **its own tooling reporting false positives**.
- The critic that returned GO listed what it checked that could have found something — sixty adversarial statements, upserts, data-modifying CTEs, multi-row statements, every claim shape. That list is what a GO after four rounds is worth.

## Carried forward

`OPEN-016` (freeze budget enforced only in the handler), `OPEN-018` (a gym with no settings row), and the gaps the round-four critic accepted: a NULL requester makes the two-person rule vacuous for trusted-context rows, `approved_at` is caller-supplied, a pending pause's content is ungoverned before approval, and `membership_pauses_platform_write` has no tenant clause so ADR-052's composite FK is what answers a tenant move for a `super_admin`.
