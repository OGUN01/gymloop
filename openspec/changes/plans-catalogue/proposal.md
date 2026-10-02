# Plans catalogue in the member app (PLC-001…PLC-025)

Feature F16 of `docs/planning/v2-feature-map.md`, phase V2-B1 of `docs/planning/v2-campaign-goal.md`, batch 2
(`openspec/changes/v2-batch2-shared/decisions.md` is authoritative). Rigor: visible DB plus a small independent holdout DB `h71_plans_catalogue_holdout.sql`, prefix `71900000`, for the changed RLS policy; visible app tests and one screen implementer. Holdout author sees neither visible suite nor implementation. All batch-2 contracts and bars freeze before tests.

## Quality bar

`docs/design/v2/plc-bar.md` records the fetched official GOV.UK Summary list and the structural bar before tests. Documentation is evidence of structure, not native member-app UI proof. The critic scores its criteria and those below, with no lower standard for a sparse demo:

- **PLC-Q1** Each plan row reads, in order, name, price, length; a screen reader announces the same order.
- **PLC-Q2** When a member's recorded terms differ from today's, both numbers are on screen at once, each
  labelled ("Price when sold", "Today"), never abbreviated, never carried by colour or strike-through alone.
- **PLC-Q3** Empty, error, offline and stale each say what happened and the next action in one or two
  sentences; no raw error text, no code, no blame.
- **PLC-Q4** No control on the page or section suggests a purchase can happen here (probe: no actionable
  element or sentence contains buy, purchase, select, choose, upgrade, subscribe, checkout or request).
- **PLC-Q5** Web and Android show the same fields in the same order with the same sentences (they share
  `planCatalogueCopy` and `heldPlanNotice`).
- **PLC-Q6** Light and dark; 390 px and 1440 px on web; Android at device-maximum text size; web axe-clean;
  reduced motion has nothing to remove (this surface has no motion).
- **PLC-Q7** Money uses tabular numerals and the existing `formatMoney` grouping; GST shows a rate and
  nothing derived from it (no total, no tax amount, no inclusive/exclusive claim).

## Why

The Buy tab (PAY, F10) lets a member raise a request to renew their current plan. A member who can only see
the plan they already hold has no context for that request: they cannot see what else exists, what it
costs now, or that the gym has revised a price since they joined. PLC is the read-only view of the gym's
active plans, plus an honest comparison against what the member's own membership recorded. It sells
nothing, requests nothing and changes nothing; every plan change stays a desk conversation (the `GL043`
plan-change refusal rules, which freeze a membership's plan and price terms once any money has arrived,
are untouched).

## Scope

In: one database change (a one-conjunct narrowing of the existing member read policy on `plans`), shared
contracts (read, view model, copy, pure helpers), a web page `/member/plans` reached from the Gym screen, a
mobile "Plans & prices" section on the Gym screen, tests, ADR-180. No new table, column, function, enum,
grant, index, trigger, SQLSTATE, API route, RPC or audit action.

Out (recorded, not built): purchase, renewal request and proof upload (PAY — see "Requires / Provides" for
the documented hook); plan change, freeze and cancellation (desk); a console plan manager (none exists
today — gyms write `plans` rows through authorized PostgREST, so `description`, `gst_rate_bp` and
`sort_order` are often at their defaults, Contract question 9); coupons and discounts on offered plans;
price history and price-change notices (ANC); per-plan feature lists, images, comparison tables and
"recommended" badges; freeze allowances (see Decisions 6); per-branch plan sets (`plans` has `tenant_id`
only, so every branch of a gym shows the same list); a persisted offline cache (Decisions 7); GST invoices
(RPE).

## Decisions and deliberate deviations

1. **Read direct under RLS; no RPC (the preferred option) — and why that is sufficient for columns but
   not for rows.** Column exposure (OPEN-015, `docs/security.md`, `docs/decisions.md`): the role matrix is
   table-granular, so a member session already reads every column of every `plans` row of its own gym
   through `plans_member_select` (`supabase/migrations/20260907184315_phase2_role_matrix.sql:280-284`, member
   gate "M(all)", ADR-055). Walking the columns: `name`, `description`, `duration_days`, `price_paise`,
   `currency`, `gst_rate_bp` are the catalogue itself; `id`, `tenant_id`, `created_at`, `updated_at`,
   `sort_order`, `is_active` are structural; `max_freeze_days` is a benefit figure no rule reads. **No
   `plans` column is secret** — there is no cost, margin, staff or internal-notes column — and members seeing
   plan prices is the feature, so a "member-safe columns" definer RPC would add a function, a grant, a
   meta-suite row and a second read path while removing no exposure. The OPEN-015 concern (trainers read
   `plans.price_paise`) is a staff-side question and is unchanged. **Rows are a different matter:**
   `plans_member_select` has no `is_active` term, so today a member's own token can read the gym's
   inactive plans (retired offers, negotiated one-person plans a gym deactivated) through the API, whatever
   any screen filters. The feature map requires that "inactive or hidden plans never leak to members"; a
   client-side `is_active` filter, or an RPC beside an unchanged policy, does not meet that, because the
   table stays open. The smallest change that does is the one-conjunct narrowing below. **Verdict on "prove a database object is needed": no table, column, function, grant or index is needed; exactly one existing policy must change, which is what justifies `20261003110000_plans_catalogue.sql` and `71_plans_catalogue.sql`.**
2. **No "hidden" concept.** The feature map says "inactive or hidden"; the schema has exactly one visibility
   field, `plans.is_active`. A hidden plan is an inactive plan. No column is added.
3. **Ordering is the database's.** The console orders by `sort_order` alone; for equal `sort_order` (the
   column default is 0, so gyms that never set it have all ties) Postgres order is arbitrary. PLC orders by
   `sort_order`, then `created_at` (creation order is what an owner who never set `sort_order` means), then
   `id` (determinism only). This is a server-side `ORDER BY`; the client never sorts. Contract question 7.
4. **GST is a rate on file, nothing more.** `plans.gst_rate_bp` is stored, but no rule anywhere says whether
   `plans.price_paise` includes or excludes GST (manual payments are "entered, not calculated",
   `openspec/specs/manual-payment/spec.md`; membership GST invoicing is RPE, not built). The page therefore
   shows the stored rate, hides it when the stored rate is 0 (the column default, which may mean
   "not configured"), and makes no inclusive/exclusive claim. Contract question 3.
5. **The member's own side shows what the membership recorded.** `memberships` stores the price as sold
   (`price_paise`, a list-price snapshot the desk may legitimately set below the plan's), `discount_paise`,
   `currency` and `duration_days`; it stores **no GST rate**, so the recorded side never shows one.
6. **`plans.max_freeze_days` is never displayed.** Nothing reads it: the freeze limit that is enforced is the
   gym-wide `organization_settings.max_freeze_days_per_year`. Showing the plan column would promise a benefit
   the system does not enforce. "What it includes" is therefore the owner-written `description` only; with no
   description, no includes line is invented. (Contract question 6.)
7. **Offline: the premise "cached like the other member read views" is not true of this codebase, and the
   contract says what is true.** No member read view is persisted: `useMemberSnapshot` reads on mount and, on
   failure, shows "Your gym information could not be loaded"; `SecureStore` holds only the session, the
   cached identity, the appearance and the offline check-in queue; `expo-network` is used only by the
   scanner; the web has no service worker. PLC therefore does the same honest thing plus one improvement:
   it keeps the last good copy **in memory for the lifetime of the screen** and flags it stale with a
   timestamp when a refresh fails. A cold start offline shows the offline state. No purchase exists, so a stale
   price can cause no wrong payment. Contract question 4.
8. **Placement.** shared.md puts the catalogue on the Gym screen. Mobile: a disclosure section there,
   exactly like the existing "Membership & receipts", "Messages & consent" and "Add-ons" sections. Web: a
   row on `/member/my-gym` linking to a page, exactly like the existing Messages and Add-ons rows; the page
   is `/member/plans`, a sibling of `/member/messages` and `/member/add-ons`, so it does not move when the
   proposed information architecture renames `my-gym` to `gym`.
9. **Loading on web is the framework's navigation transition.** `chalkline-route-states.test.tsx` forbids a
   `loading.tsx` for the member audience (it replaces the `<main>` landmark while loading). The page adds none.

## Fixed names (the contract — nothing here changes while agents work against it)

### Database

| Object | Name / content |
|---|---|
| migration | `supabase/migrations/20261003110000_plans_catalogue.sql` — transactional; contains exactly `drop policy plans_member_select on public.plans;` and `create policy plans_member_select …` below. The header cites the drop exemption the role-matrix migration already took (a serial forward-only change whose purpose is to replace an applied policy) |
| policy | `plans_member_select` on `public.plans`, `for select to authenticated` — **replaced in place, same name** |
| predicate | `tenant_id = (select app.current_tenant_id()) and (select app.current_app_role()) = 'member' and (select app.current_member_id()) is not null and is_active` — the three existing conjuncts verbatim and in the same order, then the new term |
| normalized form | the meta-suite normalization (strip `as alias`, whitespace, parentheses; lower-case) of `pg_get_expr(polqual)` is exactly `tenant_id=selectapp.current_tenant_idandselectapp.current_app_role='member'::textandselectapp.current_member_idisnotnullandis_active` |
| unchanged | the other four `plans` policies; the `authenticated` grant (`select, insert, update`, no delete); `plans_tenant_id_is_active_idx (tenant_id, is_active)` (`20260906115146_membership_money.sql:346`), which serves the member query; every trigger and key |
| SQLSTATEs | none new. A hidden row is **zero rows, never an error** |
| audit | none (reads are not audited anywhere) |
| generated types | unchanged — policies are not in `packages/db/types/database.ts`, so PLC needs no types regeneration and cannot trip `schema-drift` |
| meta-suite impact | `supabase/tests/04_contract_meta.sql`, assertion "Every table's read gate matches the matrix": the `member_select using` pattern for `plans` gains the trailing fragment `andis_active` before its `$` anchor, supplied by a per-table `mb_extra` value in the same named-exception style as the existing `pol_extra` (`leads`, `member_imports`, ADR-118); its message string is updated; no other table's pattern changes. `supabase/tests-holdout/h12_role_matrix_read_holdout.sql` pins the member gate by `LIKE` fragments (`%current_member_id%`, `%is not null%`, no `member_id =`) that the new predicate still satisfies; the amending author confirms rather than assumes. No existing suite creates an inactive plan and reads it as a member (grep at drafting), so no other assertion changes |
| consequence for existing reads | see PLC-004 |

### Stored fields (exact — what is read, shown, compared, or never touched)

| Column | Use |
|---|---|
| `plans.name` | shown |
| `plans.description` | shown when non-blank, as plain text |
| `plans.duration_days` | shown as `N days`; compared with the membership's |
| `plans.price_paise` | shown (decimal text, `formatMoney`); compared with the membership's |
| `plans.currency` | shown with the price; compared |
| `plans.gst_rate_bp` | shown only as the rate label when above 0; never used in arithmetic |
| `plans.id` | key; matched to `memberships.plan_id` |
| `plans.is_active` | filter only (not selected) |
| `plans.sort_order`, `plans.created_at` | ordering only (not selected) |
| `plans.max_freeze_days`, `plans.tenant_id`, `plans.updated_at` | never selected |
| `memberships.status` | shown as dot plus word; decides `past` |
| `memberships.ends_on` | shown as `Ends` |
| `memberships.price_paise` | shown as `Price when sold`; compared |
| `memberships.discount_paise` | shown as `Discount` when above 0; input to the agreed price |
| `memberships.currency` | shown with those amounts; compared |
| `memberships.duration_days` | shown as `Length`; compared |
| `memberships.plan_id`, `memberships.id` | matching only |
| `memberships.created_at` | ordering of the latest-membership read only (not selected) |
| every other `memberships` column (`starts_on`, `coupon_id`, `periods_granted`, renewal link, cancellation fields) | never selected |

### Shared (`packages/shared`, platform-free) — `src/api/plan-catalogue.ts`, re-exported by one appended line in `src/index.ts`

Only the names below are exported; any helper beyond them stays module-private (knip).

- `PLAN_CATALOGUE_COLUMNS = 'id,name,description,duration_days,price_paise::text,currency,gst_rate_bp'`.
- `MEMBER_PLAN_TERMS_COLUMNS = 'id,plan_id,status,ends_on,price_paise::text,discount_paise::text,currency,duration_days'`. The `::text` casts are the established decimal-text pattern (`ADDON_OFFER_COLUMNS`).
- Types:
  - `PlanCatalogueEntry = { id: string; name: string; description: string | null; durationDays: number; pricePaise: string; currency: string; gstRateBp: number; held: boolean }` — `description` is `null` when the stored text is null or blank after trimming; `held` is true for the entry whose id is the member's held plan id.
  - `HeldPlanChange = 'none' | 'price' | 'length' | 'price_and_length' | 'not_on_offer' | 'unknown'`.
  - `HeldPlanView = { planId: string; status: string; past: boolean; endsOn: string | null; planName: string | null; recorded: { listPricePaise: string; discountPaise: string; agreedPricePaise: string | null; currency: string; durationDays: number }; current: { pricePaise: string; currency: string; durationDays: number } | null; change: HeldPlanChange }` — `status` is the stored `membership_status` word; `past` is true for `expired` and `cancelled` (false for `active`, `frozen`, `pending`); `planName` and `current` come from the matching catalogue entry and are `null` when that plan is not among the entries.
  - `PlanCatalogueView = { plans: PlanCatalogueEntry[]; truncated: boolean; held: HeldPlanView | null; heldUnavailable: boolean }` — `held` is `null` when the member has no membership row at all (or when `heldUnavailable`).
  - `PlanCatalogueRead = { ok: true; view: PlanCatalogueView } | { ok: false }` — `ok: false` carries no error detail.
  - `PlanCatalogueDb` — a minimal structural type for the client chain `readPlanCatalogue` uses (`from`, `select`, `eq`, `in`, `order`, `limit`, `maybeSingle`, awaitable to `{ data, error }`), declared beside the function so web and mobile each pass their `SupabaseClient` through one `as unknown as PlanCatalogueDb` (the established pattern, e.g. `memberMoney`). The shape is the implementer's; the tests drive a recording fake through it.
- `readPlanCatalogue(db: PlanCatalogueDb, memberId: string): Promise<PlanCatalogueRead>` — the only place the reads are written (jscpd threshold is 0; web and mobile must not carry copies). It issues, in parallel:
  1. plans: `from('plans').select(PLAN_CATALOGUE_COLUMNS).eq('is_active', true).order('sort_order', { ascending: true }).order('created_at', { ascending: true }).order('id', { ascending: true }).limit(MEMBER_PAGE_SIZE_DEFAULT + 1)`;
  2. live membership: `from('memberships').select(MEMBER_PLAN_TERMS_COLUMNS).eq('member_id', memberId).in('status', ['active', 'frozen']).limit(1).maybeSingle()` (at most one row exists — the live partial unique index);
  3. latest membership: `from('memberships').select(MEMBER_PLAN_TERMS_COLUMNS).eq('member_id', memberId).order('created_at', { ascending: false }).limit(1).maybeSingle()`.
  It never selects `max_freeze_days`, `is_active`, `sort_order`, `tenant_id`, `created_at` or `updated_at`. The held row is the live one if present, else the latest. A plans failure → `{ ok: false }`; a failure of either membership read (with plans fine) → `ok: true` with `heldUnavailable: true` and `held: null`; more than `MEMBER_PAGE_SIZE_DEFAULT` plan rows → the first `MEMBER_PAGE_SIZE_DEFAULT` and `truncated: true`. The returned order is the database's order, untouched.
- `buildPlanCatalogueView(input: { plans: readonly PlanRow[]; live: MembershipRow | null; latest: MembershipRow | null; heldUnavailable: boolean }): PlanCatalogueView` — the pure half of the above (row types are the structural shapes of the two column lists), exported so the order, flag and comparison rules are tested without a client. `change` rules, in order: the held plan id is not among the returned plans → `not_on_offer`, except when `truncated` (the plan may simply be past the cap) → `unknown`; otherwise compare `BigInt(recorded.listPricePaise) !== BigInt(current.pricePaise)` **or** the two currencies differ → price differs; `recorded.durationDays !== current.durationDays` → length differs; both → `price_and_length`; neither → `none`.
- `memberAgreedPrice(pricePaise: string, discountPaise: string): string | null` — the agreed price as decimal text: `String(membershipNetPrice(Number(price), Number(discount)))` when both strings are canonical non-negative integers that round-trip through `Number` as safe integers and `discount <= price`; otherwise `null` (the screen then omits the agreed-price row; nothing is rounded, clamped or guessed). It reuses `membershipNetPrice`, so the rule "a period costs the listed price minus its discount" has one implementation.
- `planGstLabel(gstRateBp: number): string | null` — `null` for 0; otherwise `GST ` + `formatBasisPoints(String(gstRateBp))` with a trailing `.00` removed before `%` (`1800` → `GST 18%`, `500` → `GST 5%`, `250` → `GST 2.50%`, `10000` → `GST 100%`).
- `planDurationLabel(days: number): string` — `1 day`, otherwise `N days`, exactly as stored (no month or year conversion).
- `planCatalogueCopy(nouns: { place: string }): PlanCatalogueCopy` — every sentence the surface shows (table below). `nouns` is `businessNouns(...)` from BIZ (shared.md primitive 5); the function takes only `place` so it compiles against any `BusinessNouns`.
- `heldPlanNotice(held: HeldPlanView, copy: PlanCatalogueCopy): string[]` — the ordered sentences under the held block (one to three), so web and Android cannot diverge.

`PlanCatalogueCopy` (strings verbatim; `{place}` = `nouns.place`, e.g. "gym"; apostrophes are straight):

| Key | Text |
|---|---|
| `title` | Plans & prices |
| `rowMeta` | What each plan costs and includes |
| `lede` | Current prices at your {place}. |
| `heldHeading` (live or pending) / `heldHeadingPast` (expired, cancelled) | Your plan / Your last plan |
| `listHeading` | On offer |
| `badge` / `badgePast` | Your plan / Your last plan |
| `keepsTerms` (live or pending) | Your membership keeps the price and length it was sold at. |
| `soldTerms` (expired, cancelled) | This is the price and length it was sold at. |
| `today(price, length)` | Today this plan is {price} for {length}. |
| `renewalPricing` | A renewal is priced when it is recorded, so it can differ from what you paid before. |
| `notOnOffer` (live or pending) | This plan is no longer on offer. Your membership keeps the price and length it was sold at. |
| `notOnOfferPast` | This plan is no longer on offer. |
| `noMembership` | You don't have a membership yet. Ask your front desk to start one. |
| `heldUnavailable` | Your own plan details could not be loaded. |
| `gstNote` (only when some listed plan has a rate above 0) | GST is shown as the rate on file for each plan. Your {place} confirms the final amount when you pay. |
| `deskNote` | To renew or change your plan, ask your front desk. |
| `truncated` | Showing the first {MEMBER_PAGE_SIZE_DEFAULT} plans. Ask your front desk about the others. |
| `emptyTitle` / `emptyBody` | No plans listed yet / Your {place} hasn't listed any plans here yet. Ask your front desk what's available. |
| `error` / `retry` | Plans could not be loaded. / Try again |
| `loading` | Loading plans… |
| `offline` | You're offline. Plans can't load until you're back online. |
| `staleOffline(time)` | You're offline. Showing prices from {time}. They may have changed. |
| `staleRefresh(time)` | Couldn't refresh. Showing prices from {time}. They may have changed. |
| held-block labels | `Plan`, `Status`, `Ends`, `Price when sold`, `Discount`, `Agreed price`, `Length` |

`heldPlanNotice` returns: `not_on_offer` → `[notOnOffer]` (live/pending) or `[notOnOfferPast]` (past); otherwise `[keepsTerms]` (live/pending) or `[soldTerms]` (past), and, when `change` is `price`, `length` or `price_and_length`, then `today(formatMoney(current.pricePaise, current.currency), planDurationLabel(current.durationDays))` and `renewalPricing`. `none` and `unknown` add nothing. "Live or pending" = `past` is false (status `active`, `frozen`, `pending`); "past" = `expired`, `cancelled`.

No new numeric constant is introduced (`MEMBER_PAGE_SIZE_DEFAULT` is reused; `0`/`1`/`-1` are exempt, ADR-026).

### Web (`apps/web`)

- `app/member/plans/page.tsx` — async server component, default export. `requireAudience('member')` first (the page verifies its own audience, like every member page); then `readPlanCatalogue(supabase as unknown as PlanCatalogueDb, identity.memberId)`; then renders. No API route, no server action, no client component, no `'use client'`, no `loading.tsx`, no `revalidate`/`unstable_cache` (the page reads the session cookie and is dynamic and uncached).
- `app/member/plans/plan-list.tsx` — server components `HeldPlanBlock` and `PlanList` (props: the view and the copy).
- `app/styles/plans.css` — new, imported by the page; only `--gymloop-*` custom properties (no colour literal, no new ramp).
- Structure: `<main className="member-route member-portal member-plans">` (the only `<main>`); `<header>` with `<Link href="/member/my-gym" className="cl-back">` text "My gym", `<h1 className="member-title">Plans &amp; prices</h1>`, `<p className="cl-lede member-lede">` (the lede); `<section id="your-plan" aria-labelledby>` (the eyebrow `cl-eyebrow member-eyebrow` is the section's `<h2>`; facts as `<dl className="member-facts">`; status as `StatusWord`; notices as `<p className="member-quiet">`); `<section id="plans" aria-labelledby>` (its eyebrow is likewise an `<h2>`) with `<ul className="plan-list" aria-label="Plans on offer">` of `<li className="plan-entry" data-held="true|false">` (name as `<h3 className="cl-row-title">`; the badge as `<span className="cl-status" data-tone="accent">`; price as `<p className="plan-price"><span className="plan-price-amount">₹1,500</span> <span className="plan-price-unit">for 30 days</span></p>`; GST as `<p className="plan-gst">`; description as `<p className="plan-description">` plain text with line breaks preserved, never HTML or links); closing `<p className="member-quiet">` notes. Entries are ruled rows (hairline, no cards, no shadows). Dates on the held block use `memberShortDate`, exactly as the Gym page.
- `app/member/my-gym/page.tsx` — one added `<li>` placed immediately before the Messages row (`<li><Link className="member-row" href="/member/messages">`): a `member-row` link to `/member/plans`, `lucide-react` `Tag` icon, title "Plans & prices", meta `rowMeta` (static text; the row performs **no** data read, so `phase7-member-surfaces.test.tsx` and the Gym page's load are unaffected), chevron.
- `app/member/member-navigation.tsx` — one exact-match edit so the "My gym" destination stays current on the new route: its `matches` gains `|| path.startsWith('/member/plans')`.

### Mobile (`apps/mobile`)

- `lib/plan-catalogue-state.ts` — pure logic. `PlanCatalogueState = { phase: 'idle' | 'loading' | 'ready' | 'failed'; view: PlanCatalogueView | null; loadedAt: string | null; staleReason: 'offline' | 'refresh_failed' | null; offline: boolean }`; `initialPlanCatalogueState`; `planCatalogueReducer(state, event)` with events `{ type: 'reset' }`, `{ type: 'started' }`, `{ type: 'succeeded'; view; at: string }`, `{ type: 'failed'; offline: boolean }`. Rules: `reset` → initial; `started` → `loading`, keeping `view`, clearing `staleReason`; `succeeded` → `ready` with the new view and `loadedAt = at`, `staleReason` null; `failed` with a prior `view` → `ready`, `view` kept, `staleReason` = `offline` or `refresh_failed`; `failed` without a view → `failed` with `offline` recorded. `planCatalogueNotice(state, copy, timeZone): { tone: 'warning' | 'error'; text: string } | null` — `ready` with a `staleReason` → warning (`staleOffline`/`staleRefresh` with `formatDateTime(loadedAt, timeZone)`); `failed` → error (`offline` or `error`); otherwise `null`.
- `lib/use-member-plans.ts` — `useMemberPlans(open: boolean): { state: PlanCatalogueState; reload(): Promise<void> }`. Reads only when `identity.kind === 'member'` and `open` is true (first open, every later open, and `reload`); keeps state in the hook (owned by `GymScreen`, so a collapse and reopen keeps the last good copy); dispatches `reset` when `(userId, tenantId, memberId)` changes; ignores a response from a request that is no longer the newest; classifies a failure with the scanner's own `expo-network` test (`!isConnected || !isInternetReachable`). **No module-level cache, no `SecureStore`, no `AsyncStorage`.**
- `components/plan-catalogue.tsx` — `PlanCatalogueBody({ state, copy, timeZone, onRetry })`, the content of the open section: inline loading (`ActivityIndicator` + muted `loading`, polite live region — the kit's `LoadingState` carries "Loading your gym" and is not reused), stale/offline/error through `StateMessage` and `ErrorRetry` (`retry` label), empty through `EmptyState`, held block as ledger rows with `Status`, entries as ruled rows using `UI_TOKENS` and `FONT` (price in the same display style as the receipts ledger amounts), notes as muted `Body`. Each entry is one accessible group whose `accessibilityLabel` is `{name}, {price} for {length}` followed by `, {GST label}` when present and `, {badge}` when held.
- `app/(member)/gym.tsx` — three exact-match additions: (1) `const plans = useMemberPlans(openSection === 'plans');` directly after the `markError` state declaration and before the first early return (rules of hooks); (2) a `Row` (icon `Tag`, title "Plans & prices", meta `rowMeta`, `expanded={openSection === 'plans'}`, `onPress={() => toggle('plans')}`, `accessibilityLabel` "Plans & prices, {rowMeta}") placed immediately before the "Attendance history" row, i.e. second in the list; (3) `{openSection === 'plans' ? <View style={[styles.sectionBody, { borderColor: palette.decorativeSeparator }]}><PlanCatalogueBody … /></View> : null}` directly after that row. `timeZone` is `data.gym.timezone`; `copy` is `planCatalogueCopy(businessNouns(null))` until BIZ supplies the gym's type (Requires R1).

## EARS requirements

- **PLC-001 (inactive plans are invisible to members, in the database).** A signed-in member SHALL be able to read a `plans` row of their own gym only while its `is_active` is true. A member session SHALL get zero rows, and no error, for an inactive plan on every access path — a select with no filter, by primary key, by `is_active = false`, a count, and an embed from `memberships` — and SHALL never see another gym's plans. Setting `is_active` to false SHALL hide the row from members within the same transaction; setting it back SHALL restore it.
- **PLC-002 (nothing else moves).** Owner, manager, front desk and trainer sessions SHALL still read active **and** inactive plans of their own gym; platform roles SHALL still read across gyms; no write path on `plans` SHALL change for any role; members SHALL still hold no insert or update, and `authenticated` still no delete or truncate. A tenant claim with no recognized role SHALL read nothing; a member-role claim SHALL remain member-scoped and read only active plans. Existing staff/platform predicates SHALL remain unchanged, including their behavior with an extraneous `member_id`; PLC makes no claim of mixed-identity validation. The signed hook's canonical claim shape SHALL remain unchanged. This precise retained boundary is owner-approved in `mixed-claim-boundary-amendment.md`.
- **PLC-003 (minimal change).** The change SHALL replace exactly one policy, `plans_member_select`, in place, by appending `and is_active` to its existing predicate (same name, `for select`, role `authenticated`), and SHALL add no table, column, function, enum value, grant, index, trigger, API route or SQLSTATE.
- **PLC-004 (named consequence for other member reads).** A member's own `memberships` rows SHALL stay readable. Where the plan of such a row is inactive, an embedded `plans(name)` SHALL be null, which the existing Home, Gym and You loaders (`apps/web/lib/member-portal.ts`, `apps/mobile/lib/mobile-data.ts`) already render as the generic label "Membership". PLC SHALL NOT edit those loaders; the consequence is accepted and recorded (Contract question 2), not hidden.
- **PLC-005 (the catalogue read).** The catalogue SHALL be read with the member's own RLS-scoped client, directly, by `readPlanCatalogue`, as exactly the plans read in "Shared": `PLAN_CATALOGUE_COLUMNS`, `is_active = true`, order `sort_order`/`created_at`/`id` ascending, limit `MEMBER_PAGE_SIZE_DEFAULT + 1`. The filter is kept although the policy now implies it (defence in depth, and it keeps working if the policy is ever reverted). The read SHALL NOT select `max_freeze_days`, `is_active`, `sort_order`, `tenant_id` or any timestamp. Money columns SHALL arrive as decimal text (`::text`).
- **PLC-006 (order is the database's).** Plans SHALL be displayed in the order received. The client SHALL NOT sort, group, filter, deduplicate or promote any entry — including the member's own plan, which keeps its position and gains a badge.
- **PLC-007 (the member's own terms).** The member's terms SHALL come from their live (`active` or `frozen`) membership if one exists, else their latest membership by `created_at`, read scoped to their member id with `MEMBER_PLAN_TERMS_COLUMNS`. A member with no membership row SHALL see `noMembership` in the held slot.
- **PLC-008 (failure isolation).** A failed plans read SHALL produce the error state with no partial list. A failed membership read with a successful plans read SHALL show the catalogue and `heldUnavailable` in the held slot, with no badge and no comparison. No database or PostgREST message SHALL reach the page.
- **PLC-009 (fields shown, exactly).** Per plan: name; description when non-blank (plain text, line breaks kept, never interpreted as markup); length as `planDurationLabel`; price as `formatMoney(pricePaise, currency)`; the GST line only when `planGstLabel` is non-null. Nothing else from `plans`. The held block shows, from `memberships`: status (dot plus word), `Ends` when `ends_on` is set, `Price when sold`, `Discount` only when it is above zero, `Agreed price` only when the discount is above zero and `memberAgreedPrice` is non-null, and `Length`; plus `Plan` (the name) only when the plan is among the entries.
- **PLC-010 (money and GST discipline).** Every amount SHALL be formatted by `formatMoney` from decimal text (integer paise, currency explicit, ADD-011). The only arithmetic SHALL be `memberAgreedPrice` (via `membershipNetPrice`) and the `BigInt` equality comparison in `change`. A price that is not a safe integer SHALL display exactly via `formatMoney` and make `memberAgreedPrice` return `null` — never rounded. GST SHALL appear only as the stored rate, with gstNote stating the gym confirms the final amount; the page SHALL NOT show a tax amount, a total with tax, an inclusive/exclusive/extra claim, a per-month or per-day price, a discount or coupon on an offered plan, or any figure the database did not store.
- **PLC-011 (recorded versus today).** The page SHALL treat `memberships.price_paise` and `plans.price_paise` as two different facts. The `change` field SHALL follow the rules in "Shared" (`not_on_offer`, `unknown` when truncated, `price` when the list prices or currencies differ, `length` when the durations differ, both, `none`). When the plan is on offer the held block SHALL show the recorded terms and the plan's entry SHALL show today's, so that when they differ both are on screen at once, labelled `Price when sold` and `Today` (the `today` sentence), never abbreviated and never conveyed by colour or strike-through alone.
- **PLC-012 (no implied old price).** No sentence SHALL say or imply that the recorded price applies to a renewal or a new purchase. When `change` is `price`, `length` or `price_and_length` the notices SHALL include `renewalPricing`. When the plan is not on offer the notice SHALL be `notOnOffer`/`notOnOfferPast`, not an assertion about what a renewal would cost. The recorded side SHALL never show a GST rate (none is stored).
- **PLC-013 (agreed price).** `memberAgreedPrice` SHALL equal `membershipNetPrice(price, discount)` for every pair of safe non-negative integers with `discount <= price`, and SHALL return `null` for any non-canonical, unsafe, negative or inconsistent input.
- **PLC-014 (read-only, no purchase).** The page and section SHALL contain no purchase, request, select, payment, upgrade, subscribe or form control, SHALL call no mutating endpoint, and SHALL send the member to the front desk with `deskNote` for any renewal or change. The only interactive elements are navigation back to My gym, the section toggle, and retry.
- **PLC-015 (web page).** `/member/plans` SHALL be built as specified in "Web": audience-guarded, server-rendered, one `<main>`, one `<h1>`, headings in order (h1 → h2 sections → h3 entries), no client JavaScript of its own, dynamic and uncached, with the Gym row and navigation edit. The Gym page SHALL perform no plans read.
- **PLC-016 (mobile section).** The Gym screen SHALL show a "Plans & prices" row, second in the list, that expands the section; the section SHALL read on open (first and every later open), never before, and SHALL render the same fields, order and sentences as the web page via the shared helpers.
- **PLC-017 (states, web — gate 30).** *Loading*: the framework's navigation transition (no skeleton, no `loading.tsx`). *Empty*: zero entries and no failure → `emptyTitle`/`emptyBody` in the `cl-empty` structure (with the held block and `deskNote` still shown). *Error*: a plans failure → `<p role="alert" className="cl-alert">` with `error` and a plain `<a href="/member/plans">` "Try again" (a full navigation, so the router cache cannot replay the failure), plus the My gym back link; a thrown render error → the existing `member/error.tsx`. *Offline/stale*: not applicable on web — the web member app has no service worker and no client cache, so there is no stale copy to flag; the browser's own offline page is outside the app (the contract adds no cache). *Permission denied*: not an in-page state — `requireAudience('member')` redirects a signed-out visitor to `/sign-in` and any other audience to its own home. *Pending, success, validation, conflict*: not applicable (read-only).
- **PLC-018 (states, mobile — gate 30).** *Loading*: first open with no copy → inline loading. *Empty*: as web, with `EmptyState`. *Error (online)*: no copy → `ErrorRetry` with `error`. *Offline*: no copy → `ErrorRetry` with `offline`. *Stale*: a refresh that fails with a copy in memory → keep the copy and show a warning `StateMessage` (`staleOffline` or `staleRefresh`, with the time in the gym's timezone) above it, plus `retry`. A response from a request that is no longer the newest SHALL be ignored. *Permission denied*: the hook never reads unless `identity.kind === 'member'`, and the member tabs mount only for members. *Pending, success, validation, conflict*: not applicable.
- **PLC-019 (no persisted cache).** Mobile SHALL keep the last good copy in memory only, scoped to `(userId, tenantId, memberId)`, and discard it when that scope changes or the screen unmounts, so sign-out and account switch leave nothing for the next user (the mobile spec's "the next user cannot inherit them"). No `SecureStore`, `AsyncStorage`, file or module-level storage SHALL be added, and no offline queue (nothing here is a command).
- **PLC-020 (permission and tenancy, tested).** A member of gym A SHALL never receive a gym B plan from any PLC read; PLC SHALL add no way to read `plans` other than the member's own RLS-scoped client.
- **PLC-021 (Chalkline and accessibility).** The surface SHALL use the existing kit (`cl-*` classes and `member-*` rows on web; `components/ui.tsx` and `UI_TOKENS` on Android), ruled rows not cards, tabular numerals for money, status as dot plus word, targets at least the touch size, no colour-only meaning, wrapping rather than truncation at 200% text, light and dark, and no fixed heights. Web SHALL pass the axe route run with `/member/plans` added.
- **PLC-022 (copy and nouns).** Every user-visible string SHALL come from `planCatalogueCopy`/`heldPlanNotice` or the static labels in "Shared", in English, specific and honest, with no invented number (the only numerals shown are stored values and `MEMBER_PAGE_SIZE_DEFAULT`). The place noun SHALL come from `businessNouns(...)`, defaulting to `gym`. No sentence SHALL contain the words buy, purchase, upgrade, subscribe, checkout, choose, select or request as an action.
- **PLC-023 (no regression).** The existing member surfaces, loaders, tests and the Gym page's data load SHALL be unchanged; the Gym row on web is static text; `phase7-member-surfaces`, `phase8-member-hig-auth` and `chalkline-route-states` stay green.
- **PLC-024 (data lifecycle).** PLC SHALL store nothing new, write no audit row, add no retention row, and log no plan name, price or membership fact (no new logging at all).
- **PLC-025 (the hook for PAY).** PLC SHALL leave PAY exactly these seams and no code stub: `readPlanCatalogue` and `buildPlanCatalogueView` (the Buy tab's renewal request finds the member's held plan, its recorded terms and today's price here); the single sentence `deskNote`, which PAY replaces with a pointer to the Buy tab when it ships; and the web anchors `#your-plan` and `#plans` and the mobile section id `plans` for deep links. PLC SHALL NOT add a button, prop, slot or placeholder for them.

## Errors and states (no new SQLSTATE; reads fail as ordinary errors or as zero rows)

| Condition | What the member sees | Mechanism |
|---|---|---|
| Plan is inactive | nothing — the plan is not listed | zero rows (PLC-001); no error |
| Gym has no active plans | `emptyTitle` / `emptyBody`; held block and `deskNote` still shown | PLC-017/018 |
| Plans read fails (any error) | web `error` + Try again; mobile `error` + Try again | `{ ok: false }`; message never shown |
| Membership read fails, plans fine | catalogue, plus `heldUnavailable` in the held slot | `heldUnavailable: true` |
| Mobile offline, no copy in memory | `offline` + Try again | Network classification |
| Mobile refresh fails, copy in memory | the copy, with `staleOffline`/`staleRefresh` and the time | reducer `failed` with a view |
| Member has no membership | `noMembership` in the held slot; catalogue shown | `held: null` |
| Held plan not on offer | `notOnOffer` (live/pending) or `notOnOfferPast`; no name, no comparison | `change: 'not_on_offer'` |
| More than `MEMBER_PAGE_SIZE_DEFAULT` active plans | the first page plus `truncated` | `truncated: true` |
| Session expired / not a member | web redirect to `/sign-in` or the audience's home; mobile never mounts the section | `requireAudience`; tab mounting |

## Operational preconditions (nothing owner-gated; nothing performed by this change)

1. The migration rides the single batch-2 migration push, after batch 1 has settled (`migrate` succeeded, ADR-177). It changes no data and no generated type.
2. Implementation starts after BIZ is on `main` so `businessNouns` is exported; if it is not, the implementer stops and escalates rather than inventing it (shared.md primitive 5).
3. Verification needs the demo gym (`docs/demo-accounts.md`; member `aarav.member@ironbox.example.com`). The seed has four active plans — Monthly, Quarterly, Half-Yearly, Annual, in that `sort_order`, all at 18% GST — and no inactive plan and no price change, so the comparison, not-on-offer and hidden-plan states are exercised by gym-admin edits through the ordinary authorized API during verification (price change on the member's plan; deactivating a plan), not by editing the seed. A plan description is plain text the owner wrote; the seed descriptions mention freeze weeks as prose and are shown as written.

## Test and deployment order

1. After all batch-2 contracts/bars freeze, `spec:` commits (separate implementation-blind visible DB and holdout DB authors, before implementation): this proposal; the amended `supabase/tests/04_contract_meta.sql` (apply on top of INV/STI/GRD/CLS amendments to the same file — the orchestrator serialises edits to it, Requires R2); visible pgTAP `supabase/tests/71_plans_catalogue.sql` (fixture prefix `71000000-0000-4000-8000-…`, `begin … rollback`); `tests/e2e/phase8-accessibility.spec.ts` (add `/member/plans` to the member route list); the TypeScript suites below.
   - pgTAP, minimum assertions: (a) a member of gym A reads exactly A's active plans, in `sort_order`; (b) the same member reads zero rows, no error, for A's inactive plan by id, by `is_active = false`, and in a count; (c) zero rows for gym B's plans, active or not; (d) the member's own `memberships` row on the inactive plan is still readable, while the join to `plans` yields no row; (e) member insert refused `42501`, update zero rows, no delete privilege; (f) owner, manager, front desk and trainer of A read all three A plans; (g) `platform_support` and `super_admin` read both gyms' plans; (h) a trainer-role token carrying a `member_id` reads zero; no claims reads zero without raising; (i) deactivate then reactivate as owner flips the member's count 2 → 1 → 2 in one transaction; (j) `pg_policy`: exactly the five `plans_*` policies by name, `plans_member_select` is `r` for `authenticated` with the pinned normalized predicate; (k) the column list of `plans` and the index `plans_tenant_id_is_active_idx` are unchanged.
   - Small independent holdout `supabase/tests-holdout/h71_plans_catalogue_holdout.sql`, fixtures `71900000-0000-4000-8000-…`, `begin … rollback`: active/inactive own-tenant visibility, cross-tenant reads in both directions, missing/role-mismatched claims, inactive own-plan join absent, deactivate/reactivate visibility, staff/platform reads unchanged. Author reads frozen contract/bar only, neither visible suite nor implementation.
   - Shared (`packages/shared/src/api/__tests__/plan-catalogue.test.ts`): a recording fake `PlanCatalogueDb` pins the three reads exactly (columns, `is_active`, the three-key order, `MEMBER_PAGE_SIZE_DEFAULT + 1`, live-first), proves forbidden columns are never selected, plans failure → `{ ok: false }`, membership failure → `heldUnavailable`, truncation at the page size; `buildPlanCatalogueView` preserves a deliberately unsorted input order (permutation test), flags the held entry, and covers the full `change` matrix including `unknown` under truncation and a currency difference; `memberAgreedPrice` equals `membershipNetPrice` on safe inputs and is `null` for `'9007199254740993'`, `'01'`, `'-1'`, `'1.5'`, `''` and discount above price; `planGstLabel` (0, 250, 500, 1800, 10000), `planDurationLabel` (1, 30), `formatMoney` on a non-safe price string; every `planCatalogueCopy` string pinned, `{place}` substitution, no action words (PLC-022); the `heldPlanNotice` matrix.
   - Web: `apps/web/app/__tests__/plans-catalogue-page.test.tsx` renders the page with `requireAudience` mocked (asserted called with `'member'`) and a fake client: ordered list, empty, plans error, `heldUnavailable`, no membership, truncation, recorded ≠ today (both amounts present and labelled), not-on-offer, GST hidden at 0 and shown at 1800, null description, a second currency, one `<main>`, one `<h1>`, no `<button`, `<form`, `action=` or `/api/` link, and `existsSync('member/plans/loading.tsx')` false, no `'use client'`, `plans.css` free of colour literals; `apps/web/app/__tests__/plans-catalogue-gym-row.test.tsx` (the Gym page links `/member/plans`, performs no plans read, the navigation marks "My gym" current on `/member/plans`).
   - Mobile: `apps/mobile/lib/__tests__/plan-catalogue-state.test.ts` (reducer and notice, including keep-copy-on-failure, scope reset and out-of-order responses at the reducer level), and `apps/web/app/__tests__/plans-catalogue-mobile-wiring.test.ts` (source match in the style of `member-invite-mobile-wiring.test.ts`: the row, `openSection === 'plans'`, the hook call before the first early return, `readPlanCatalogue` used only through the hook, `expo-network` imported by the hook, and no `SecureStore`, `AsyncStorage`, module-level `Map` or `api.post` in any PLC file).
2. Migration `20261003110000_plans_catalogue.sql` only, plus pgTAP: prove locally with `scripts/pgtap/sweep.py` splicing the migration (no DB run in flight); it goes out in the one batch-2 migration push. No types regeneration follows from PLC.
3. Implementation commits after the tests are red: shared → web → mobile, each green before the next. Because the client filter in PLC-005 is independent of the policy, the screens work before and after the migration applies, so there is no ordering hazard between the migration push and the TypeScript push.
4. Web verification first on the demo member (including the three manual state checks in precondition 3 and a direct PostgREST `plans` select as the member proving the inactive plan is absent); Android hot-reload after, with the owner, including airplane mode for the stale and offline states.

## Requires / Provides

**Requires.** R1 — BIZ: `businessNouns` exported from `@gymloop/shared`, and its member loader/provider reading `organizations.business_type` in the existing organizations select, not `read_member_portal_settings`. Only unresolved values fall back through `businessNouns(null)`. R2 — the orchestrator serialises batch-2's edits to `supabase/tests/04_contract_meta.sql` (the `member_select using` arm); PLC's edit is limited to a `mb_extra` value and the pattern concatenation. R3 — the information-architecture integrator: the Gym row and `/member/plans` survive the proposed `my-gym` → `gym` rename unchanged (the page's back link and the navigation `matches` strings are the only references and move with it).

**Provides.** P1 — `/member/plans` and the mobile section. P2 — `readPlanCatalogue`, `buildPlanCatalogueView`, `memberAgreedPrice`, `heldPlanNotice` and `planCatalogueCopy` for PAY's Buy tab (PLC-025). P3 — `plans_member_select` is now active-only: any later member-session read of `plans` (PAY's renewal request, SLF) may rely on it and must not expect inactive rows. P4 — archive-time documentation deltas for the integrator: `openspec/specs/authorization` (the "M(all)" statement for `plans` becomes "active plans only"), `docs/data-model.md` (`plans` privileges/policy note), `docs/security.md` (a sentence beside OPEN-015: members read the gym's active plan prices by design; inactive rows are no longer member-readable), `docs/domain-rules.md` (PLC-001…025). P5 — registry rows to add (alphabetical within each table): constants `MEMBER_PLAN_TERMS_COLUMNS`, `PLAN_CATALOGUE_COLUMNS`; functions `buildPlanCatalogueView`, `heldPlanNotice`, `memberAgreedPrice`, `planCatalogueCopy`, `planCatalogueNotice`, `planCatalogueReducer`, `planDurationLabel`, `planGstLabel`, `readPlanCatalogue`; types `HeldPlanChange`, `HeldPlanView`, `PlanCatalogueCopy`, `PlanCatalogueDb`, `PlanCatalogueEntry`, `PlanCatalogueRead`, `PlanCatalogueState`, `PlanCatalogueView`; hook `useMemberPlans`; components `HeldPlanBlock`, `PlanCatalogueBody`, `PlanList`; policy `plans_member_select` (amended).

## ADR-180 text

**ADR-180 — The plans catalogue is a direct read of active plans; the member read policy on `plans` gains `is_active` (agent decision on the owner's feature map F16, 2026-10-02).** F16/PLC of the v2 map adds a read-only view of a gym's active plans to the member app. Decisions, each with the alternative rejected. (1) *No RPC.* The role matrix is table-granular (OPEN-015) and `plans` has no secret column — no cost, margin, staff or notes column — so a definer RPC returning "member-safe columns" would remove no exposure while adding a function, a grant, a meta-suite row and a second read path. The catalogue is read with the member's own RLS-scoped client, as the add-ons offers and the member snapshot already are, with money cast to decimal text (`price_paise::text`, the add-ons pattern, ADD-011). (2) *The row-level hole is closed in the database.* `plans_member_select` (ADR-055, "M(all)") had no `is_active` term, so a member's token could read inactive plans through the API regardless of any screen. The feature map says inactive plans never leak to members; a client filter, or an RPC beside an unchanged policy, leaves the table open, so the policy gains one conjunct (`and is_active`), replaced in place under its own name. This follows the role-matrix migration's own precedent for dropping and re-creating an applied policy, adds no fifth gate (ADR-055), and is pinned in `04_contract_meta` through a per-table fragment in the style of ADR-118's `leads` exception. Rejected: a second RESTRICTIVE policy (it breaks the "no policy outside the template" invariant for a one-term change); an own-plan exception through a cross-table `exists` on `memberships` (the first cross-table subquery among the 226 `create policy` statements in `supabase/migrations/`, against `docs/security.md`'s stated pattern, and a new member-gate variant for a closed vocabulary). **Consequence accepted:** a member whose plan was later deactivated sees the generic label "Membership" on Home, Gym and You (the loaders' existing fallback when the embedded plan is null); reversing that costs one migration adding the own-plan clause, or a loader change reading the name through a narrow RPC. (3) *"Hidden" is "inactive".* There is no second visibility field and none is added. (4) *Order.* `sort_order`, then `created_at`, then `id`, all server-side; never a client sort. (5) *GST is a rate, not arithmetic.* No rule says whether `plans.price_paise` includes GST, so the surface shows the stored rate (hidden at 0), makes no inclusive/exclusive claim, says the gym confirms the final amount, and invents no tax figure; `plans.max_freeze_days` is not displayed because no rule enforces it. (6) *Recorded versus today.* A membership keeps the price and length it was sold at (`GL043`, ADR-090); the page shows both, labelled, derives no direction or cause (the desk may have sold below list), never implies the old price applies to a renewal, and shows no GST for the recorded side because none is stored. The agreed price reuses `membershipNetPrice`. (7) *Offline is in-memory staleness, not a cache.* No member read view is persisted today; PLC keeps the last good copy in memory for the screen's lifetime and flags it stale with a time. Rejected: a `SecureStore` copy (size-limited, needs chunking, must be scoped and cleared at sign-out) — it buys a stale price display on cold start with no purchase to protect. (8) *Placement.* A disclosure section on the mobile Gym screen; on web a row on `/member/my-gym` linking to `/member/plans`, a sibling of `/member/messages` and `/member/add-ons`, so the proposed `gym` rename does not move it. (9) *Hook for PAY.* A shared read and view model plus one replaceable sentence (`deskNote`); no code stub. Reverse cost of the whole feature: delete the page, the section and the shared module, and re-create `plans_member_select` without the last conjunct.

## Resolved decisions and deliberate scope gaps

Authoritative decisions below are frozen; remaining defaults are deliberate scope gaps, not pending owner permission.

1. **Resolved:** Retain active-only RLS policy; visible DB + small independent holdout h71_plans_catalogue_holdout.sql, prefix 71900000.
2. **Members on a since-deactivated plan lose the plan name on Home, Gym and You** (they read "Membership"); a price revision done as "deactivate old plan, add new plan" makes this the common case. Default: accept and record (ADR-180 (2)). Options: add the own-plan clause as the project's first cross-table `exists` policy (needs an ADR exception and a new member-gate variant in the meta-suite); or a narrow definer RPC for the member's own plan name plus an edit to the two loaders (more files, concurrent-edit risk).
3. **Resolved:** [owner] Show stored GST rate, claim neither inclusive nor exclusive, and say the gym confirms the final amount. No tax arithmetic or listing-copy blocker remains.
4. **Resolved:** Mobile cache is in-memory for the app run, scope-cleared and stale offline; no new native dependency; persistence is post-release.
5. **Resolved:** Final IA integrator retains /member/plans from Gym and moves back-link/navigation references to /member/gym; mobile section remains on Gym.
6. **`plans.max_freeze_days` is stored, shown to nobody and enforced by nothing** (the enforced limit is `organization_settings.max_freeze_days_per_year`). Out of scope here; worth a separate decision to enforce it or drop it, since owners may assume it works.
7. **Tie order versus the console.** The desk reads `plans` ordered by `sort_order` alone, so for equal values the desk and the member may differ; PLC adds `created_at`, `id`. Option: a later change gives the console the same three keys. Not edited here (console files are not PLC's).
8. **Resolved:** docs/design/v2/plc-bar.md is commissioned before tests; structural bar with fetched official reference.
9. **No console plan manager exists**, so most real gyms will show no description, no GST rate and tied sort orders; the catalogue degrades gracefully but will look sparse. A plan editor is outside F16; flag whether it belongs in the map.
10. **Resolved:** Demo rows, if needed, are a PLC-marked block applied to shared seed files by the orchestrator at integration.
