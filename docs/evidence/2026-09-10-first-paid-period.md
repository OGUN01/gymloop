# First paid membership period — verification

The first complete payment for a fully dated membership now sets the paid span
instead of adding it to an unpaid typed span. A future agreed start is preserved;
an elapsed unpaid start moves to the gym-local payment day. Renewals, partial
payments, retired memberships, currency checks and both half-dated paths retain
their existing behavior.

## Independent verification

The contract was committed before tests (`f337a3a`). Independent visible tests
were committed red (`5f7d53d`, 805 assertions, eight failures), followed by the
independent holdout (`2878076`, 1001 assertions, 69 failures). A critic and the
holdout exposed an unintended ends-only activation change. The contract was
clarified before authors changed their own suites; an added visible regression
failed against that candidate. The implementer did not read the holdout files.

The corrected candidate passed visible payment coverage (809 assertions) and
holdout payment coverage (1001 assertions). The full local database sweep passed
all 47 files and 4243 assertions, with zero failures and no incomplete plans.
Both seed files ran twice in one rollback transaction against the candidate.

A fresh-context Astra critic returned GO. Comparing the executable function
body with the preceding authoritative definition confirmed changes only to the
dated branch's two date assignments. Migration `29b9581` was pushed to `main`
for CI to apply; no migration was applied manually.

## Gates

All nine local gates, the production build, 47 script tests and dependency
boundaries passed. The copy-only membership-page follow-up passed lint,
typecheck, all 286 web tests, registry, escape-hatch and duplication checks.

- [Main CI](https://github.com/OGUN01/gymloop/actions/runs/34444695160): passed.
- [Test immutability](https://github.com/OGUN01/gymloop/actions/runs/34444695135): passed.
- [Database CI](https://github.com/OGUN01/gymloop/actions/runs/34444695146): passed, including migration apply, schema drift, rollback guard, all 47 files / 4243 assertions, and seed dry run. The pgTAP run took 1784 seconds.

The two changed current specs pass strict OpenSpec validation. The full strict
spec check reports the pre-existing tenancy warning that “A tenant claim alone
is not sufficient” lacks SHALL/MUST; it is unrelated to this change. Archive
completion uses this project's owner-approved ADR-060 `plan.md` convention.
The CLI's default artifact graph still expects the superseded separate
proposal/design/tasks files and therefore does not recognize that convention.

## Browser verification

After database CI completed, the signed-in demo owner recorded INR 1500.00 cash
through Farah Contractor's membership page. The membership started with a typed
2026-08-23 through 2026-09-22 span and zero granted periods. The payment produced
exactly one granted period, 2026-09-10 through 2026-10-10, visible in the browser
and confirmed through the CLI.

Receipt `2026-27/000007` showed Farah, INR 1500.00, cash, and Kabir Shah as the
staff member who took it. The temporary payment id was
`33ce4d80-bff4-40af-885d-39626de0d9b2`; its unique note identified this test.
The membership-page wording now describes first grants and later renewals
correctly, and was checked in the rendered product.

In the same session, a guarded transaction removed exactly that test payment
and restored the membership to its full pre-test JSON snapshot, including its
original update timestamp. The terms and timestamp triggers were disabled only
within that transaction and re-enabled before commit, following ADR-095.
The receipt counter was deliberately left advanced: number 000007 is spent.

The browser confirmed the original membership dates after cleanup. A sweep
over the browser-write window found zero new rows in payments, refunds,
memberships, attendance, QR sessions, membership pauses and members. No test
payment, refund, pause or extra membership remains from this exercise.

## Scope that remains open

OPEN-029 still permits unpaid time through direct creation. This change fixes
the first paid grant and does not reinstate the withdrawn universal creation
cap. OPEN-026's half-dated semantics, the approved OPEN-028 discount arithmetic,
refund idempotency and payment/refund refusal precedence are separate units.
