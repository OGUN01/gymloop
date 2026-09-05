# MASTER BUILD PROMPT — Gymloop (multi-tenant gym retention SaaS)

> **How to use this file:** paste the whole thing into a fresh Claude Code session as the first message. Optionally attach `Gym-App-Blueprint-by-Roy-Digital.pdf` as supporting context. This prompt is a **bootstrap**, not a build order for the whole product — read §3 carefully.
>
> **Model and effort per phase.** Every phase that builds or designs runs on **Claude Fable 5.1**. This is a deliberate decision by the product owner: quality is the constraint, not cost. Do not substitute a cheaper model to save tokens, and do not propose it. Effort is the only lever that varies.
>
> | Phase | Model | Effort | Why this effort |
> |---|---|---|---|
> | 0 · Foundation | Fable 5.1 | `high` | Scaffolding — errors surface instantly. |
> | 0 · final critic | Fable 5.1 | `xhigh` | Deep judgement on whether the gates really fire. |
> | 1 · Data model + RLS | Fable 5.1 | `xhigh` | An RLS hole is silent and leaks another gym's members. |
> | 2 · Identity & tenancy | Fable 5.1 | `high` | Well-trodden auth wiring; role tests fail loudly. |
> | 3 · Core domain | Fable 5.1 | `xhigh` | Double-scan, offline replay, exactly-once. Concurrency bugs are silent. |
> | 4 · Retention engine | Fable 5.1 | `xhigh` | Per-timezone scans, no duplicate open cases. |
> | 5 · Money | Fable 5.1 | `xhigh` | Webhook idempotency, never-mark-paid. Real money, real disputes. |
> | 6 · Growth surfaces | Fable 5.1 | `high` | Mostly CRUD over an already-proven core. |
> | **7 · Design & UI** | Fable 5.1 | `max` | **The design must be the best part of this product.** It is also a vision task: the blind critic judges rendered screens against captured screenshots of the bars in §9, and Fable 5.1's vision on dense inputs is strongest when it can crop and zoom to verify its own work. Give the critic a crop tool (bounding box in, cropped-and-enlarged region out) or a container with PIL/OpenCV, and check the logs that it actually called it — at lower effort it judges from an overall impression without zooming, which makes the blind comparison worthless. Loop until our screen wins the blind comparison; never lower the bar. |
> | 8 · Hardening | Fable 5.1 | `xhigh` | Last look before real gyms. |
>
> At `xhigh` and `max`, set a large `max_tokens` — it is a hard ceiling on thinking *plus* response, and a long deliverable can otherwise be drafted in thinking and truncated in the reply. Because effort is the only lever, §14's instructions against unrequested refactoring, tidying and test sprawl matter more, not less: higher effort makes those behaviours more likely, and they are the cost of running hot everywhere.

---

## 1. Your role

You are the lead engineer building **Gymloop**, a production, multi-tenant SaaS for Indian gyms. You are not prototyping. Everything you produce is intended to run in production, be sold to paying gym owners, and be maintained across many future sessions by agents who will not have read this prompt.

The single most important consequence of that last point: **your job in this session is to create the source of truth, not to build the application.**

## 2. What Gymloop is

A hosted SaaS platform with three tiers of user:

- **Super Admin** (the platform owner) — sees and manages every gym.
- **Gym** (the customer) — an organisation with its own staff, members, plans, prices, rules and branding. A gym owner gets a web dashboard and the same analytics inside the mobile app.
- **Members** — belong to one or more gyms, use a single shared mobile app.

The product's core insight, which must never be diluted: gyms lose money to **silent churn**, not to failed acquisition. A member goes quiet for 10–15 days, nobody notices, and by the time the fee is missed they have mentally left. Gymloop closes that loop:

> **Record attendance → detect risk → contact early → bring the member back → collect renewal on time → deliver useful add-ons → show the owner what worked.**

Every feature must serve that loop. Decorative dashboards and vanity charts are explicitly out of scope. Each owner-facing metric must answer one of: *Who do I call today? Which fee is due? Which payment failed? Who came back? Which add-on still needs delivering?*

### What the product must not promise
No retention guarantee, no revenue guarantee, no medical/nutritional/transformation claims. Software provides visibility and workflow; results depend on the gym.

---

## 3. YOUR TASK IN THIS SESSION — Phase 0 only

**Build the repository and its source-of-truth documents. Do not implement application features. Do not write business logic. Do not create UI.**

Reason: coding-agent output degrades measurably from roughly 65% context fill, and errors compound because your own output becomes your next context. A single session cannot build this system. So this session builds the scaffolding that lets *every future session* work correctly from files instead of from memory or from this prompt. After Phase 0, this prompt is disposable.

**Deliverables of this session are listed in §12. Read the whole document before starting.**

---

## 4. Locked technical decisions — do not re-litigate

| Area | Decision |
|---|---|
| Repo | pnpm + Turborepo monorepo: `apps/web`, `apps/mobile`, `packages/shared`, `packages/db`, `packages/api-client` |
| Web | Next.js 16.3 (App Router, React 19.2) + TypeScript strict + Tailwind + shadcn/ui, hosted on Vercel |
| Mobile | Expo SDK 56 / React Native 0.85 (New Architecture, mandatory) + expo-router + NativeWind, EAS Build + OTA Update |
| Database / Auth | Supabase Postgres, **Mumbai (ap-south-1) region** — chosen because Neon has no India region and latency is a product requirement |
| Tenancy | Single database, Row-Level Security, `tenant_id` injected via a custom access-token hook |
| Object storage | **Cloudflare R2** (zero egress) + Cloudflare Images. Access via short-lived presigned URLs minted server-side after an authorisation check |
| Edge / security | Cloudflare DNS, CDN, WAF, and **Turnstile** on OTP, signup and public endpoints |
| Payments | **Razorpay**, each gym connects its own account |
| Jobs | `pg_cron` for scheduled scans; `pgmq` / Supabase Queues for notification dispatch with retry + dead-letter |
| Observability | Sentry (web, mobile, edge) + structured JSON logs carrying `tenant_id` on every line |
| i18n | English + Hindi from day one |

### API architecture (important — one place for every invariant)
- **All mutations** go through Next.js Route Handlers, zod-validated, returning a typed error envelope. Web and mobile both consume them via one generated client in `packages/api-client`.
- **Reads** go direct through `supabase-js` with RLS, for speed and realtime.
- **Supabase Edge Functions only** for Razorpay webhooks and cron jobs — these must sit next to the database and must not depend on Vercel.

### Explicitly rejected
Cloudflare Workers as the backend. Cloudflare D1 as the database. Neon. Flutter. No-code builders. Do not propose them.

### Provisioned infrastructure — already exists, do not recreate

| Resource | Value |
|---|---|
| Main repo | `github.com/OGUN01/gymloop` (private) |
| Holdout-test repo | `github.com/OGUN01/gymloop-holdout` (private) — CI clones it at test time; **implementing agents must never read it** |
| Supabase project | ref `pecxrpskmfeuyzngvewq`, name `gymloop`, region `ap-south-1` (Mumbai), org `gjjnocawiprbwdkktogn` |
| Supabase URL | `https://pecxrpskmfeuyzngvewq.supabase.co` |
| R2 bucket | `gymloop-media` — credentials verified with a full write/read/delete round-trip |
| Local secrets | `.env.local` (gitignored). `.env.example` must list the variable **names** only. |

**⚠️ Do not use the Supabase MCP server on this project.** It is authenticated to a *different* Supabase account (`sageharsh9887@gmail.com`, org `tgfogbcaackxhcxytrrc`, a project in `ap-southeast-1`). Calling `apply_migration` or `execute_sql` through MCP would silently hit the wrong database. **All Supabase work goes through the `supabase` CLI**, which is authenticated to the correct account. CI can only use the CLI in any case. Put this warning in `AGENTS.md`.

Environment variables in `.env.local`: `SUPABASE_PROJECT_REF`, `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` (new-format `sb_publishable_…`), `SUPABASE_SERVICE_ROLE_KEY` (new-format `sb_secret_…`, server-only — **never** prefix with `NEXT_PUBLIC_`), `SUPABASE_DB_PASSWORD`, `CLOUDFLARE_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, `R2_ENDPOINT`.

---

## 5. Locked product decisions

**Distribution.** One member app for all gyms. A member finds their gym by (a) scanning the gym's invite QR, (b) typing a 6-character gym code, or (c) automatic match on phone number against the gym's imported roster. (c) is the path that actually works for non-technical members — make it excellent. In-app branding is gym logo + one accent colour + gym name. A member in two gyms gets a gym switcher in the header.

**Payments.** Each gym connects its **own** Razorpay account; the platform never touches member money and takes no cut of it. Revenue is subscription only. A gym with no gateway connected must remain **fully functional offline** — cash / UPI / card payments recorded by front desk with staff attribution, receipts, and a working renewal pipeline. Most early gyms will be in exactly this state. Razorpay usage: Orders API + Checkout in-app; **Payment Links** for renewal reminders to members who never installed the app; webhooks `payment.captured`, `payment.failed`, `order.paid`, `refund.processed` (`subscription.*` reserved for Phase 2 UPI Autopay). Per-gym `key_id`, `key_secret` and `webhook_secret` encrypted at rest via Supabase Vault, with a per-gym test-mode flag. Onboarding includes a guided connect wizard that verifies keys **and** webhook secret with a ₹1 test payment before the gym goes live.

**Messaging.** v1 is push notifications (Expo + FCM/APNs) plus click-to-WhatsApp (`wa.me` deep links that open the staff member's own phone with a pre-filled message). No SMS, no DLT registration. **But the messaging layer must be written as a provider interface with a per-gym credit wallet from day one**, because WhatsApp Business API ships in Phase 1.5 as the paid tier and Indian competitors already have it.

**Commercial.** Hosted SaaS. Three tiers by active-member count (approx ₹1,499 / ₹2,999 / ₹4,999 per month). 14-day full-feature trial, no card. Gym self-signup → onboarding wizard → super-admin approval before going live. In-app platform billing of gyms lands in Phase 1.5; manual activation at launch.

---

## 6. Roles and permissions

`super_admin`, `platform_support`, `gym_owner`, `gym_manager`, `front_desk`, `trainer`, `member`.

Fixed roles in v1; a per-permission matrix is Phase 2. Super Admin can impersonate a gym owner for support — with a persistent red banner, a mandatory typed reason, an audit row, and an auto-expiring session.

---

## 7. Scope

### v1 — build this
Member profile and active membership · gym plans, prices, discounts and expiry rules · QR check-in with assisted front-desk fallback · attendance history · configurable no-show red list · follow-up outcomes and next actions · weekly goal / streak · renewal options with verified payment state · offline payment recording · GST invoices · PT, diet and product catalogue · basic add-on orders and usage state · **lead / enquiry management** (walk-in → trial → conversion with source tracking) · coupon codes on renewal · owner dashboard and daily summary · super-admin console · consent, opt-out and audit history · CSV/Excel member import with column mapping and duplicate-phone detection · three gym presets (neighbourhood gym / premium studio / functional box).

### Phase 2 — schema must accommodate, do not build
Multi-branch UI (schema carries `organization → branch` from day one) · full trainer app · class/batch scheduling · UPI Autopay via Razorpay subscriptions (**mandate tables in the schema now**) · staff payroll and trainer commission · body measurements and progress photos · wearables · referrals · advanced inventory · anonymised cross-gym benchmarking · WhatsApp Business API · per-permission role matrix.

### Per-gym configuration (the "template" that makes this sellable)
Name, logo, brand accent, address, timezone, currency, opening hours, GSTIN, invoice prefix and financial-year reset, week-start day, plans/prices/discounts, no-show threshold days, streak rule type, renewal reminder windows (14/7/3/0/+3), grace-period days after expiry, allowed pause reasons and approver, max freeze days per year, holiday calendar, follow-up outcome list, add-on catalogue, staff and trainers, trainer-to-member cap, message templates, receipt/invoice numbering.

---

## 8. Domain rules and edge cases

Write every one of these as an **EARS** requirement (`WHEN <trigger> THE SYSTEM SHALL <response>` / `WHILE <state> …` / `IF <error> THEN …`) in `docs/domain-rules.md`.

**Statuses (canonical — never invent parallel vocabularies)**
- Member: `active`, `paused`, `expired`, `cancelled`, `blocked`
- Membership: `pending`, `active`, `frozen`, `expired`, `cancelled`
- No-show case: `open`, `contacted`, `follow_up_due`, `returned`, `closed`
- Payment: `created`, `pending`, `paid`, `failed`, `refunded`, `reversed`
- Add-on order: `pending`, `paid`, `active`, `completed`, `cancelled`, `refunded`
- Notification: `scheduled`, `sent`, `delivered`, `failed`, `clicked`, `converted`, `opted_out`
- Follow-up outcome: `will_return`, `injured`, `travelling`, `timing_issue`, `unhappy`, `no_response`, `cancelled`

**Attendance and QR**
Verify QR session validity and active membership before recording. A static QR screenshot must not work indefinitely — use rotating or session-bound QR. Reject duplicate scans inside a configurable window without losing legitimate attendance. Assisted front-desk check-in requires staff identity and a mandatory reason. Offline check-ins queue locally and replay **exactly once** with an audit stamp. Check-out is optional in v1.

**Streaks**
Three configurable rule types: visit streak (consecutive planned workouts), weekly goal (e.g. 4 of 4 planned visits), calendar streak (challenges only). Rest days and approved pauses must not unfairly break a streak. Motivate, never shame. Members can disable motivational notifications.

**No-show detection**
Runs once each morning **in each gym's own timezone**. Excludes paused, frozen, expired and cancelled memberships. Opens exactly one case when the threshold is crossed and never creates a duplicate open case. A return check-in resolves the open case automatically while preserving history. Two staff must not be able to call the same member simultaneously. Contact logs are never deleted — corrections are new entries.

**Renewals and payments**
Reminders at configurable 14 / 7 / 3 / 0 / +3 day windows, one message per stage, stopping after verified payment, cancellation or opt-out. Failed payment escalates on a different path from no response. Never store raw card or UPI credentials. **The payment provider is the source of truth**; `payment_initiated` is never `paid`; membership extends only after a verified webhook or verified provider response; duplicate callbacks are handled idempotently; refunds and reversals are separate records.

**Money and time**
Money is stored as integer paise, never floating point, with explicit currency and a tested rounding rule. All scheduled logic is timezone-correct per gym and tested across date boundaries.

**Add-ons**
Never pre-selected. Show exact price, validity, trainer qualification or product stock, and cancellation terms before purchase. Check trainer availability before payment. Stock and PT session counts can never go negative.

**Data integrity**
Never hard-delete financial records, attendance corrections or follow-up history. Marketing consent and service communication are separately controlled. Every mutation of financial, attendance-correction, follow-up, role and impersonation data writes an audit row (actor, action, record type, record id, before/after summary, timestamp).

**Data-quality alerts**
Membership without expiry date · paid order without provider reference · attendance correction without reason · negative product stock · trainer double-booking.

**Compliance (DPDP)**
The **gym is the Data Fiduciary; the platform is the Data Processor** — the gym contract needs a DPA clause. Build versioned consent records with timestamp and purpose, separate marketing and service consent, a withdrawal flow, data export, and erasure requests with a legal hold on financial records. Per-table retention policy and a breach-notification runbook. Member photos yes; no government ID storage in v1.

---

## 9. Methodology — the Gauntlet Loop

Every unit of work follows this loop. There is **no budget cap**; the loop exits when the work wins, never after a fixed number of rounds.

```
1  BAR        Name a specific, fetchable, comparable reference for this piece
2  SPEC       EARS requirements → human approves
3  TESTS      Visible + holdout suites written FIRST, from the spec,
              by a session that has not seen an implementation. Committed RED.
4  BUILD      Implementer makes them green. May NOT touch test files.
5  GAUNTLET   Fresh-context critic, blind comparison vs the bar → win, or loop
6  GATES      The 33 checks in §11
7  ARCHIVE    Fold the change back into specs, update the registry, /clear
```

**Why tests come first, and why this is non-negotiable.** Models saturate visible test suites while still reward-hacking underneath; the gap between visible and holdout pass rates widens with task complexity. A test written after an implementation tends to encode what the code does, not what the requirement says. Therefore:

- Tests derive from the approved EARS spec, authored implementation-blind.
- A **holdout suite lives in a separate private repository** that CI clones at test time. The implementing agent never sees it. A visible-vs-holdout gap is treated as a build failure and investigated as reward hacking, not as flaky tests.
- Test files are **immutable to the implementer**. CI fails any commit touching both `tests/**` and `src/**` unless the commit message carries an explicit `spec:` prefix, which signals a human-approved specification change.
- Three orthogonal graders: code-based (does it run), model-based (blind critic), human (intent).

**Critic independence.** The builder knows how hard it tried and will rationalise its own output. The critic must get fresh context and no knowledge of the build effort.

**Escalation.** If a critic rejects the same dimension three times, that is evidence the **requirement is under-specified**. Escalate to the human as a specification question. Never silently lower the bar.

### Test layers
| Layer | Tool | Covers |
|---|---|---|
| Database | pgTAP | RLS, tenant isolation, constraints, triggers |
| Unit | Vitest | Streak calculation, absent-days, money, timezone maths |
| Integration | Vitest against a real local Supabase (`supabase start`) — **not mocks** | API contracts, state machines, idempotency |
| E2E | Playwright (MCP to author, CI to run) | The four journeys below |
| Load | k6 | 100 gyms × 500 members, morning check-in spike |
| Holdout | Same runners, CI-only, separate private repo | Anti-gaming signal |

### The four journeys that must pass end-to-end
- **A — Healthy member:** QR check-in → streak update → continued visits → reminder 7 days before expiry → plan selection → payment → membership extends only after verified payment.
- **B — Silent churn:** member stops attending → daily scan reaches threshold → appears in red list → staff contacts and records reason → follow-up or approved pause scheduled → return check-in resolves the case and records recovery.
- **C — Add-on conversion:** member browses → relevant optional plans shown → reviews price, trainer and validity → payment verified → session/plan usage becomes visible → owner sees utilisation, not just revenue.
- **D — Front-desk assisted:** staff searches by mobile or ID → assisted check-in with reason → member receives confirmation → audit log shows who changed the record.

### Quality bars (design phase)
Deliberately **not** the direct competitors — beating ₹89/month software proves nothing. Capture these with Playwright MCP from public surfaces, supplemented by published UI reference libraries where a product is behind a login. Never authenticate into third-party accounts.

| Surface | Bar |
|---|---|
| Owner web dashboard | Linear — speed, keyboard-first, density without clutter |
| Payments, renewals, receipts | Stripe Dashboard — payment states and failures legible at a glance |
| Member streak & history | Strava — habit made visible without shaming a missed day |
| Member dark data display | Whoop / Oura |
| Member payment flow | Revolut — minimum taps, unambiguous states |
| Front desk | Square POS — fast, tablet-first, forgiving under pressure |
| Super Admin fleet view | Vercel / Stripe Connect platform view |
| Gym onboarding wizard | Stripe onboarding — long setup that never feels long |
| QR check-in | A metro gate — sub-second scan to confirmation. Latency *is* the design. |

For the **backend** phases the bar is measurable rather than visual: zero visible-vs-holdout gap, Stripe-grade API ergonomics (typed error envelopes, idempotency keys, predictable pagination, errors that say how to fix themselves), the p95 latency budget from Mumbai, and a green pgTAP isolation suite.

### 2026 design direction (for the UI phase, not now)
Dark-first with a refined light mode. Spatial depth and subtle tactile surfaces rather than flat cards. Thumb-optimised reach on mobile. Purposeful microinteractions and haptics — especially the check-in confirmation. Large numerals and high contrast for a gym floor. Gesture-first navigation. Expressive but restrained motion. Inclusive accessibility as a requirement, not a pass. Owner dashboard prioritises actionable lists over decorative charts. Clear English/Hindi labels and rupee amounts.

---

## 10. Repository and document framework to create

Layered deliberately, because context degrades as it fills. Small always-on file; everything else pulled on demand.

```
CLAUDE.md                      # one line: @AGENTS.md
AGENTS.md                      # ALWAYS LOADED — keep under ~150 lines
                               # what this is · the hard rules · routing table
.claude/skills/                # PROCEDURES — progressive disclosure, ~100 tokens each at rest
  new-feature/SKILL.md         #   pre-flight: search registry → EARS spec → tests → then code
  db-migration/SKILL.md        #   tenant_id, RLS policy, index, pgTAP test, regen types, register
  new-api-endpoint/SKILL.md    #   canonical route + zod + error envelope + auth guard
  rls-policy/SKILL.md          #   tenant isolation pattern + leak test
  payment-flow/SKILL.md        #   idempotency, webhook verification, never-mark-paid rules
docs/
  architecture.md              # layers, boundaries, folder map, "what lives where"
  data-model.md                # tables, enums, relationships, RLS policy map
  domain-rules.md              # all of §8 as EARS requirements
  security.md                  # RLS, DPDP, payment integrity, audit
  registry.md                  # ★ anti-duplication index
  decisions.md                 # ADR log, append-only
  gates.md                     # the 33 gates from §11
openspec/
  specs/                       # current system truth
  changes/                     # proposals, archived back into specs when complete
supabase/migrations/           # applied by CI only, never by hand
tests/{visible,e2e,load}/      # holdout suite lives in a separate private repo
```

**`CLAUDE.md` must import `AGENTS.md` with a first-line `@AGENTS.md`. Do not create a symlink** — the developer is on Windows, where symlinks require Developer Mode or an admin shell.

### `docs/registry.md` — the piece that prevents the failure the client is most worried about
A searchable table per category: **Constants · Enums · Types · Utilities · Hooks · Components · Env vars**. Each row: `name | file path | purpose | used by`.

The constitutional rule, which belongs in `AGENTS.md`:
> **If it is not in the registry, it does not exist. Before writing any helper, constant, type or component, search the registry and grep the codebase. Reuse, or record why you could not in `docs/decisions.md`. Adding an exported symbol without registering it fails CI.**

### Code-side single sources of truth
- `packages/shared/src/config/constants.ts` — every magic number and string. ESLint `no-magic-numbers` makes hardcoding fail lint.
- `packages/shared/src/config/env.ts` — zod-validated, single export. `process.env` is banned everywhere else via `no-restricted-properties`.
- **One truth chain for data:** Postgres enum → `supabase gen types` → `packages/db/types/database.ts` (**generated, never hand-edited**) → zod schemas derived from it → shared by API, web and mobile. CI regenerates and diffs; drift fails the build.

### CI gates — advisory rules do not work, only failing builds do
| Gate | Catches |
|---|---|
| `tsc --noEmit` (strict) | type drift |
| `knip` | unused exports/files/deps — "built twice, wired once" |
| `jscpd` | copy-paste duplication |
| `dependency-cruiser` | layer violations (`db` ↛ `ui`, `features/*` ↛ each other) |
| `supabase gen types` diff | schema/type drift |
| pgTAP cross-tenant suite | Gym A reading Gym B — hard fail |
| registry lint | new exported symbol missing from `docs/registry.md` |
| test-immutability check | commit touching `tests/**` and `src/**` together |

### Session hygiene (put this in `AGENTS.md`)
One feature per session. `/clear` between features. Archive the OpenSpec change before stopping. If a session passes ~70% context and something feels off, **archive, clear and restart** rather than pushing through — a fresh session reading a small `AGENTS.md` plus one spec outperforms a long session that has been drifting.

---

## 11. The 33 gates

Put these in `docs/gates.md` as a checklist, and automate every one that can be automated.

**Spec & contract** — 1 EARS requirements approved before code · 2 every requirement has ≥1 visible and ≥1 holdout test · 3 CI blocks commits touching tests and implementation together · 4 quality bar captured as real artifacts · 5 blind critic sign-off, exit on win not round count

**Data & tenancy** — 6 every table has `tenant_id` (or is reachable via one) with RLS enabled · 7 pgTAP cross-tenant leak suite per table · 8 RLS columns indexed, tenant read from JWT claim not a per-row subquery · 9 forward-only migrations applied by CI · 10 DB enums generate TS types, drift fails CI · 11 a full demo gym seeded by one command

**Backend correctness** — 12 zod validation and a typed error envelope on every endpoint · 13 idempotency proven by replaying duplicate webhooks, scans and sends · 14 explicit legal-transition table per state machine plus illegal-transition tests · 15 daily scans correct in each gym's timezone, tested across date boundaries · 16 money as integer paise with tested rounding · 17 concurrency: double scan, two staff on one case, simultaneous renewal · 18 offline queue replays exactly-once with an audit stamp

**Security & compliance** — 19 no secrets client-side, env zod-validated, per-gym Razorpay keys encrypted at rest · 20 webhook signature verified per gym before any state change · 21 never `paid` without a verified provider response, never extend before that · 22 audit log on every financial, attendance-correction, follow-up, role and impersonation mutation · 23 DPDP: versioned consent, marketing/service split, withdrawal, export, erasure with legal hold · 24 rate limiting and Turnstile on OTP, signup and public endpoints

**Reliability & scale** — 25 p95 latency budget asserted in CI · 26 no N+1, cursor pagination on every list · 27 load test at 100 gyms × 500 members with a morning check-in spike · 28 structured logs carrying `tenant_id`, error tracking, alert thresholds · 29 backup and PITR restore drill actually performed

**Frontend & UX** — 30 every screen enumerates loading, empty, error, permission-denied and offline states in its spec · 31 WCAG AA contrast, 44px targets, screen-reader labels · 32 Playwright E2E covers all four journeys · 33 blind critic picks ours over the captured bar

---

## 12. Build order

| Phase | Builds | Exits when |
|---|---|---|
| **0 · Foundation** ← *this session* | Monorepo, CI gates, doc framework, skills, OpenSpec, Supabase project, env validation | Gates provably **fail** on a deliberately bad commit — a duplicated helper, an unregistered export, a hardcoded constant |
| 1 · Data model | Schema, enums, RLS, indexes, type generation, seed | pgTAP cross-tenant suite green on every table; one command seeds a complete demo gym |
| 2 · Identity & tenancy | Phone-OTP members, email staff, JWT claims hook, role matrix, gym switching, impersonation + audit | Every role × every resource asserted; impersonation writes an audit row |
| 3 · Core domain | Members, plans, memberships, pauses, QR check-in, offline queue, streaks | Holdout suite green; double-scan and offline replay produce exactly-once attendance |
| 4 · Retention engine | Daily no-show scan per timezone, cases, follow-ups, outcomes, auto-resolution | Journey B passes end-to-end; no duplicate open cases under repeated runs |
| 5 · Money | Razorpay per gym, orders, webhooks, offline payments, GST invoices, refunds, renewals | Payment state machine complete; duplicate webhook delivery changes nothing |
| 6 · Growth surfaces | Add-ons, leads, notifications, owner metrics, super admin | Owner metrics reconcile exactly against underlying rows |
| 7 · Design & UI | Bar capture → tokens → mockups → web, then mobile | Blind critic picks ours over the captured bar |
| 8 · Hardening | Load test, a11y, backup drill, launch checklist | All 33 gates green |

### Seed data for the demo gym
One Tier-2 Indian neighbourhood gym · 30 members with realistic Indian names · 3 trainers and 1 front-desk user · monthly, quarterly, half-yearly and yearly plans · 6 members absent 10–20 days · 5 memberships expiring within 7 days · PT, diet and supplement add-on examples · a few leads at different stages. Use simulated payments until a real provider is connected.

---

## 13. Definition of done for this session

1. Monorepo initialised, installs cleanly, `turbo build` and `turbo lint` pass.
2. `CLAUDE.md` (with `@AGENTS.md`) and `AGENTS.md` written — `AGENTS.md` under ~150 lines, containing the hard rules and a routing table to every doc.
3. All five `.claude/skills/*/SKILL.md` written, each with a **routing-rule description** (when it fires and what inputs it expects — not a summary).
4. All seven `docs/*.md` written and **populated with the real content from this prompt** — not empty headings. `domain-rules.md` in EARS. `gates.md` with all 33.
5. `openspec/` initialised with `specs/` and `changes/`.
6. `packages/shared/src/config/{constants,env}.ts` created with the constants we already know, and both registered in `docs/registry.md`.
7. Every CI gate configured and wired into GitHub Actions.
8. **Proof the gates work:** create a throwaway branch containing a duplicated helper, an unregistered export and a hardcoded constant; show CI failing on each; delete the branch. A gate that has never failed is not a gate.
9. `docs/decisions.md` seeded with ADRs for the decisions in §4 and §5, each recording the rejected alternatives.
10. A short `README.md` explaining how a new session starts work.

## 14. Rules for how you work

**Grounding progress claims.** Before reporting progress, audit each claim against a tool result from this session. Only report work you can point to evidence for; if something is not yet verified, say so explicitly. If a gate does not fire, say so with the output. If a step was skipped, say that. When something is done and verified, state it plainly without hedging. "Gates configured" is not a claim you can make from having written a config file — only from having watched one fail.

**Scope.** The scope of this session is §13 and nothing else. Don't add features, refactor, or introduce abstractions beyond what the task requires. Don't design for hypothetical future requirements — Phase 2 features are accommodated by the *schema* only, never by speculative code. Don't add error handling or validation for scenarios that cannot happen. If you find a pre-existing problem while working, report it as a follow-up in your summary rather than fixing it here.

**Tests.** The tests this project asks for are specified and mandatory — write every one of them. But scratch checks and throwaway verification scripts are not tests: keep them outside the repo and delete them. Do not turn a scratch check into a permanent test file.

**Editing.** Minimize tokens spent editing. When it will not affect the end result, edit a file surgically rather than rewriting the whole thing.

**Delegation.** Use sub-agents freely for independent work, and keep working while they run. For verification specifically, a **fresh-context sub-agent that has not seen the implementation** outperforms self-critique — this is the mechanism behind the Gauntlet Loop in §9, so use it rather than reviewing your own output.

**Self-verification.** Establish a way of checking your own work as you build, and run it on a cadence rather than only at the end.

**Memory.** `docs/decisions.md` and `docs/registry.md` are your memory surface across sessions. Consult them before writing anything; update them as you go. One decision per entry, with the rejected alternatives and why. Update an existing entry rather than adding a duplicate; delete entries that turn out to be wrong.

**Finishing a turn.** Before ending your turn, check your last paragraph. If it is a plan, a question, a list of next steps, or a promise about work you have not done ("I'll…", "next I'll…"), do that work now with tool calls instead. Do not stop because the session is long — you have ample context; do not summarize or suggest a new session on account of context limits. End your turn only when §13 is complete or you are blocked on something only the user can decide.

**Asking.** This session is interactive and the user is watching. If something in this document is genuinely ambiguous or self-contradictory, ask — do not invent product decisions or silently pick an alternative. But make routine judgment calls yourself, and don't ask permission for work this prompt already authorizes.

**Other constraints.**
- Do not build application features in this session. If you find yourself writing business logic, stop.
- Do not add libraries beyond what §4 specifies without recording an ADR and asking.
- Pin exact dependency versions.
- Everything you create must be discoverable from `AGENTS.md`. An orphan file is a bug.
- The product name `Gymloop` is a placeholder. Put it in **one** constant so renaming is a single edit.

---

## 15. Context you may be given

`Gym-App-Blueprint-by-Roy-Digital.pdf` — the original single-gym blueprint this product generalises. Treat it as **product intent, not architecture**. It describes one gym; this build is multi-tenant SaaS. Where the two conflict, this prompt wins. In particular the blueprint's pricing (₹10,000 one-time build + ₹500/month) is a per-gym project quote and does **not** apply — see §5.

**Begin by reading this entire document, then confirming your understanding and listing anything ambiguous before you create a single file.**
