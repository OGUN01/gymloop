# h83 + h84 final convergence — read-only verification (no edits needed)

## h83_occupancy_analytics_holdout.sql
The current working-tree bytes (976350c4) are the committed resolution:
- The block split is in place (offer+payment commit separately from the order)
- The exact-buy matrix verified column-by-column against the live trigger
  (pt_front enforce_addon_order, the UPDATE pending→paid path rel=425-434):
  member, amount, currency, status=paid, paid_at, membership/mandate/coupon/
  provider all null, recorded_by=sold_by, idempotency='addon-sale:'||key,
  method='cash' matching sale_request, notes='H83 analytics staging' matching
  the sale_request's reason, no completed refunds on the payment.
- The acceptance UPDATE runs under the front-desk claims (staff …a3,
  app_role=front_desk) with the sold_at=now() transaction-stable window.
- The residual exit-3 in the last CI run predated these fixes (the CI's
  checkout was 5dacd967; the fixture fixes landed after).

## h84_push_scheduler_holdout.sql
The A-cluster (8 operator-gated extension functions: 5 cron + 3 vault) stays
RED-by-design — the operator prerequisite. The remaining ~17 failures were
the fixture/pin classes fixed by the earlier rounds (the provider-config
staging columns, the lock-key observability, the perform→select conversion).

## The verification path
The next CI run at HEAD (with all fixture fixes pushed) verifies both files.
The h81's exit-3 is the CI's parallel-psql deadlock (documented; --jobs 1
fixes it at the CI level).

## No edits made — the files are at their converged state.
