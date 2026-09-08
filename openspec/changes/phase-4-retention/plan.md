# Phase 4 — Retention engine

One document (ADR-060). EARS spec separate, in `specs/`.

## Why

Phase 3 records that a member turned up. **Nothing yet notices when they stop.** That is the product: the loop is *record attendance → detect silent churn → contact early → bring them back*, and Phase 3 built the first arrow and none of the rest. A gym owner can already see who came in; they still cannot see who has quietly gone.

## What this phase ships

| Layer | Phase 4 |
|---|---|
| Schema | A scan that opens cases, and whatever `no_show_cases` and `follow_ups` need to make NSH-003/004/006 hold **structurally**. One open case per member is already a partial unique index — do not reimplement it. |
| Job | A daily no-show scan, per gym, **in the gym's own timezone** (NSH-001, MNY-004). Supabase Edge Function on cron — one of exactly two things `docs/architecture.md` allows an Edge Function to be. |
| Endpoints | Log a follow-up, record an outcome, assign a case. |
| Screens | **The red list** — the screen a gym actually opens each morning. A case, who it is, how long they have been gone, what was tried, and one obvious next action. |
| Rules | NSH-001 to NSH-007. |

## The bar

`docs/architecture.md` names Linear for the owner dashboard: speed, keyboard-first, density without clutter. The red list is a work queue, not a chart. If it takes more than one glance to see who needs calling today, it has failed regardless of what it renders.

## Process (ADR-059)

| Work | How |
|---|---|
| The scan itself | **Full blind arrangement.** A scan that opens two cases, or skips a paused member, or runs twice at a timezone boundary, fails *silently* — nobody notices a case that was never opened. |
| Follow-ups, outcomes, assignment | One implementer. Spec-first, tests-first, every gate. |
| The red-list screen | One implementer. |

**Fix the contract, then fan out.**

## What Phase 3 already settled that this phase depends on

- **"Paused" is derived, not a status** (ADR-064). The scan asks `membership_pauses` for an approved pause covering the scan date. It must not read `memberships.status = 'frozen'`, which nothing sets.
- **`seed-scenarios.sql`** already contains the cases this phase must get right: a member 6 days absent against a 7-day threshold, one 8 days absent, one who never visited, one with an approved pause and a 30-day absence who **must not** be flagged, and one whose only pause was rejected and therefore must be.
- Exactly-once under concurrency is a solved problem here — `app.enforce_check_in()` is the worked example, and NSH-003/004 is the same shape.

## Out of scope

Messaging delivery — WhatsApp, SMS and push are Phase 6 and need credentials that do not exist. Phase 4 opens the case and records what a human did about it; it does not send anything.
