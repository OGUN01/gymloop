# Data model

This is the **specification** Phase 1 implements — tables, enums, relationships, and the RLS policy shape. It is not DDL; migrations are written and applied by CI only, never by hand (`AGENTS.md`).

## Tenancy

Single Postgres database, Row-Level Security on every table, `tenant_id` injected via a custom access-token hook and read from the JWT claim — **never** a per-row subquery (that's gate 8, `docs/gates.md`).

Hierarchy from day one, so Phase 2's multi-branch UI needs no schema change: **organization → branch → member**. A "gym" in every other doc is an `organization`; v1 UI only ever shows one `branch` per organization, but the column exists now.

## Canonical status vocabularies

These become **Postgres enums** in Phase 1, generated into `packages/db/types/database.ts` by `supabase gen types`, and from there into zod schemas shared by API, web and mobile. They are **not** TypeScript constants — see `docs/decisions.md`, "statuses as Postgres enums, not TypeScript constants". Never invent a parallel vocabulary for any of these.

| Vocabulary | Values |
|---|---|
| Member | `active`, `paused`, `expired`, `cancelled`, `blocked` |
| Membership | `pending`, `active`, `frozen`, `expired`, `cancelled` |
| No-show case | `open`, `contacted`, `follow_up_due`, `returned`, `closed` |
| Payment | `created`, `pending`, `paid`, `failed`, `refunded`, `reversed` |
| Add-on order | `pending`, `paid`, `active`, `completed`, `cancelled`, `refunded` |
| Notification | `scheduled`, `sent`, `delivered`, `failed`, `clicked`, `converted`, `opted_out` |
| Follow-up outcome | `will_return`, `injured`, `travelling`, `timing_issue`, `unhappy`, `no_response`, `cancelled` |

Each needs an explicit legal-transition table plus illegal-transition tests (gate 14) when Phase 1 implements it — this file records the vocabulary, not the transition graph; the transition graph is written alongside the migration that creates the enum.

## Phase 2 accommodations required in the schema now

The master prompt is explicit: Phase 2 features are accommodated by the **schema**, never by speculative code. Phase 1 must leave room for:

- **Multi-branch**: `organization → branch` hierarchy (above), even though v1 UI shows one branch.
- **UPI Autopay**: Razorpay subscription **mandate tables**, unused until Phase 2's `subscription.*` webhooks are wired. v1 uses Orders API + Payment Links only.
- Everything else in Phase 2's list (trainer app, class/batch scheduling, payroll/commission, body measurements, wearables, referrals, advanced inventory, cross-gym benchmarking, WhatsApp Business API, per-permission role matrix) needs **no schema reservation** — none of it changes the shape of v1's core tables.

## Money and time

Money is **integer paise**, never floating point, with an explicit currency column and a tested rounding rule (gate 16). All scheduled logic (no-show scans, renewal reminders) is timezone-correct **per gym** (`organizations.timezone`), tested across date boundaries (gate 15).

## Per-gym configuration ("the template that makes this sellable")

One row per organization, minimum: name, logo, brand accent, address, timezone, currency, opening hours, GSTIN, invoice prefix + financial-year reset, week-start day, plans/prices/discounts, no-show threshold days, streak rule type, renewal reminder windows (`RENEWAL_REMINDER_WINDOWS`; each has an explicit `daysFromExpiry` where negative = before expiry and positive = after, so the post-due window is `+3` — see PAY-001), grace-period days after expiry, allowed pause reasons + approver, max freeze days/year, holiday calendar, follow-up outcome list, add-on catalogue, staff/trainers, trainer-to-member cap, message templates, receipt/invoice numbering.

## RLS policy map (shape, not final policy text)

- Every table carries `tenant_id` (the `organization_id`) or is reachable via one JOIN to a table that does (gate 6).
- The tenant id is read from the JWT claim set by the custom access-token hook — RLS policies reference that claim directly, never a subquery against another table (gate 8).
- RLS columns (`tenant_id` and any FK used in a policy predicate) are indexed (gate 8).
- A pgTAP cross-tenant leak suite exists per table: Gym A must never read Gym B's rows under any role (gate 7).
- `super_admin` and `platform_support` roles bypass tenant scoping by policy design, not by disabling RLS — impersonation of a gym owner writes an audit row and carries a persistent banner (`docs/security.md`).

## Data-quality alerts (data integrity, not a feature)

Flag, do not silently accept: membership without expiry date · paid order without provider reference · attendance correction without reason · negative product stock · trainer double-booking.

## What Phase 1 must produce (exit criteria, see `docs/roadmap.md`)

Schema, enums, RLS, indexes, `supabase gen types` output, and a seed script — pgTAP cross-tenant suite green on every table, one command seeds a complete demo gym (the exact seed shape, recorded here because Phase 0 never wrote a separate seed spec and the master prompt is disposable: one Tier-2 neighbourhood gym, 30 members, 3 trainers + 1 front-desk user, 4 plan tiers, 6 members absent 10–20 days, 5 memberships expiring within 7 days, PT/diet/supplement add-ons, a few leads at different stages).
