# Shop rollback preview: prior-sale chronology

Status: fixture-only clarification; product requirements, money functions and
guards remain unchanged. Independent authors implement the seam separately.

The approved order-default seam models fulfilment's ordinary sale in a rollback
preview. It cannot establish strict earlier-order/later-reservation chronology
when the CLI submits the complete file as one client message: statement_timestamp
is shared and shop_reservations.created_at defaults to transaction time.

Only the separate negative prior-sale fixture may temporarily replace
shop_reservations.created_at's default with clock_timestamp(). Capture the exact
original pg_get_expr default first. Create the earlier order through the genuine
ordinary sale RPC under the existing bounded order-default seam, then create the
later reservation through the genuine member RPC under this negative-only
reservation-default seam. Assert the actual captured order time strictly precedes
the reservation time and that causal linking is refused without changes.

Restore the exact original reservation default immediately after that reservation
is created, before the linking/refusal probe or any subsequent positive command.
Assert exact default restoration. Keep all normal money and reservation guards,
constraints, RLS and caller identities enabled. Do not update a successful order
or reservation's timestamp, disable a guard, patch a money function, change the
causal predicate, or represent this fixture as separate committed transactions.
The enclosing test still ends in ROLLBACK and every ordinary success outside this
negative fixture retains the original reservation default.

Both independent SQL authors pin the earlier-order refusal, no extra sale/stock/
payment/reservation effects, exact restored defaults and ordinary later-sale
fulfilment/replay. Actual reserve, fulfil, prior-sale refusal and replay across
genuine separate transactions remain mandatory after CI before final acceptance.
This clarification adds no production clock/default migration or new permission.
