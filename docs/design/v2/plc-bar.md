# PLC quality bar — plans catalogue (structural)

Fetched 2026-10-02. Applies to PLC-001…025 and PLC-Q1…Q7. Authoritative batch-2 decision makes this bar structural. No paid member app or native catalogue was inspected; no screenshot or production parity is claimed. Contract writer is distinct from test authors. All batch-2 contracts/bars freeze before tests.

## Fetchable reference

[GOV.UK Design System: Summary list](https://design-system.service.gov.uk/components/summary-list/) separates key/value facts, provides a version without actions and uses description-list semantics. It directs simple lists to ul/ol rather than dl. Adopt dl for held membership facts and ul/li for plans, preserving Chalkline ruled rows. This supports structure, not fitness pricing or tax interpretation.

## Testable criteria

| Criterion | Pass condition | Verification |
|---|---|---|
| PLC-Q1 order | Name → price → duration, same reader order; description plain text; held facts labelled dl. | Render/semantics and mobile accessibility-label tests |
| PLC-Q2 comparison | Recorded and current prices visible together and labelled; no color-only/strike-through meaning or promise of old renewal terms. | Full held-plan change matrix |
| PLC-Q3 states | Empty/error/offline/stale explain cause and next action concisely, no raw DB text; stale includes time; accessible retry. | Reducer/render tests, later offline walkthrough |
| PLC-Q4 read-only | No offered-plan action or implied checkout; navigation/retry allowed; desk note remains. | Action/copy and request-path checks |
| PLC-Q5 parity | Same fields/order/shared sentences on web/mobile; zero GST or absent description leaves no blank label. | Render/wiring tests, not inferred native proof |
| PLC-Q6 accessibility | Chalkline, light/dark, 390/1440 web, axe-clean, 200% wrapping; maximum Android text verified later; no motion/fixed heights. | Browser and eventual owner-device review |
| PLC-Q7 money/GST | Exact integer-paise/currency formatter, tabular numerals; stored nonzero GST rate only, no tax total or inclusive/exclusive claim; business confirms final amount. | Unsafe integers, currencies, rates and copy |
| PLC-Q8 RLS | Own active plans only; inactive held join absent; staff/platform unchanged; missing/mismatched claims and foreign tenants do not leak. | Visible DB plus small independent h71 holdout, prefix 71900000 |
| PLC-Q9 offline scope | Last good copy in memory for app run, user/tenant/member scoped and cleared on scope change/unmount; cold offline has no copy; no persistence/native dependency. | Reducer/wiring and later device verification |

Pricing, RLS and stale-state requirements are **[own]** product criteria. Holdout author reads frozen contract/bar only, neither visible suite nor implementation. Sparse demo data never lowers the state/comparison bar. Final IA integrator mounts Gym entry and updates navigation/back-links after screens exist.
