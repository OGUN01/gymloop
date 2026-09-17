# Phase 6 owner and fleet metrics

Authorized under ADR-111 after communications. The normative contract is
`docs/planning/phase6-metrics-contract.md` (MET-001–008 and OPS-001/004),
frozen before authors were dispatched. PostgreSQL's statement snapshot is the
named backend bar: every displayed total must independently reconcile from the
component rows returned by that same response.

Frozen surface:

- `public.owner_metrics(date,date)`, `app.gym_metrics(uuid,timestamptz,date,date)`,
  `public.fleet_metrics()` and `app.gym_readiness(uuid)` with the exact access,
  volatility, error and decimal-string response contracts.
- Owner `/dashboard` with month-to-date/explicit range selection and
  same-response component drill-down; platform fleet metrics are consumed by
  the following platform slice rather than refetched through a second metrics
  contract.
- Integer money, counts and usage totals remain canonical decimal strings from
  PostgreSQL through rendering. No row cap, client-side cross-page sum,
  independent drill-down query or invented readiness/provider fact is allowed.

Frozen module seam for the screen author and implementer:

- `packages/shared/src/api/metrics.ts` exports `ownerMetricsSchema`,
  `fleetMetricsSchema`, their inferred response types, `ratioBasisPoints` and
  `formatBasisPoints`. Ratio inputs and the returned basis points are canonical
  decimal strings; a zero denominator returns `null`; formatting produces an
  exact two-decimal percentage without converting the ratio to `Number`.
- `apps/web/lib/metrics.ts` exports the caller-client
  `loadOwnerMetrics(searchParams: Promise<{from?: string; through?: string}>)`
  read loader and its safe mapped error vocabulary. It calls `requireAudience`
  and the caller's `owner_metrics` RPC; it accepts real owner or manager
  identities and redirects preview and every other identity before the read.
  NAV-003 hides leads from support preview, so support consumes the complete
  fleet snapshot instead of receiving a partial owner snapshot with a false
  zero lead cohort. There
  is no read Route Handler. On a database or validation failure it throws a
  `MetricsLoadError` carrying only `invalid_metrics_range`,
  `invalid_gym_timezone` or `metrics_unavailable`; the page catches that safe
  value and never renders the raw database message.
- `apps/web/app/(console)/dashboard/page.tsx` loads once and passes the snapshot
  to `MetricsDashboard`, exported from the colocated
  `metrics-dashboard.tsx` as `<MetricsDashboard metrics={snapshot} />`; that
  client component owns range navigation and
  same-response card/component disclosure without a second read.

Full blind arrangement applies because the slice combines money aggregation,
RLS/claim boundaries and the narrow readiness definer. Visible and holdout
database authors work implementation-blind, commit red before source, and the
implementer reads neither suite. The dashboard's loud presentation tests may
use the relaxed screen arrangement after the database contract is green.

- [x] Detailed owner/fleet metrics contract and snapshot bar frozen.
- [x] Independent visible and holdout database tests committed red.
- [ ] Metrics/readiness migration and exact RPC responses implemented.
- [ ] Dashboard tests committed red; route/page/components implemented.
- [ ] Focused and slice-level local gates pass.
- [ ] Fresh-context money/RLS/concurrency critic returns GO.
- [ ] CI applies migration; generated types, pgTAP, seed and workflows pass.
- [ ] Real owner/fleet browser reconciliation passes with exact cleanup.
- [ ] Current specifications, registry, evidence and roadmap synchronized; archive.
