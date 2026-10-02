# Shop rollback preview: prior-sale chronology

Status: fixture-only clarification; product requirements, money functions and
guards remain unchanged. Independent authors implement the seam separately.

The approved order-default seam models fulfilment's ordinary sale in a rollback
preview. It cannot establish strict earlier-order/later-reservation chronology
when the CLI submits the complete file as one client message: statement_timestamp
is shared and shop_reservations.created_at defaults to transaction time.

Correction after execution: the reservation RPC explicitly supplies its exact
statement_timestamp(), so a reservation DEFAULT cannot model an earlier command.
Do not change the reservation default. Only the separate negative prior-sale
fixture may temporarily set addon_orders.created_at's default to
statement_timestamp() - interval '1 microsecond'. This models a prior transaction
for the negative guard probe; it is synthetic clock evidence, not real elapsed
time or separate transactions. Capture the exact original order default first.
Create the earlier order through the genuine ordinary sale RPC using that
negative-only default, then drain the existing named deferred order guard and
restore the exact original order default before creating the later reservation
through the genuine member RPC. Assert actual stored strict chronology and that
causal linking is refused without changes. Positive fulfilment/replay continues
to use only its separately documented statement_timestamp() default seam.

Restore the exact original order default immediately after the prior order and
its named deferred guard are complete, before reservation creation or any
subsequent command. Assert exact order-default restoration and unchanged
reservation default. Keep all normal money and reservation guards,
constraints, RLS and caller identities enabled. Do not update a successful order
or reservation's timestamp, disable a guard, patch a money function, change the
causal predicate, or represent this fixture as separate committed transactions.
The enclosing test still ends in ROLLBACK and every ordinary success outside this
negative fixture retains the original reservation default, which is never changed.

Both independent SQL authors pin the earlier-order refusal, no extra sale/stock/
payment/reservation effects, exact restored defaults and ordinary later-sale
fulfilment/replay. Actual reserve, fulfil, prior-sale refusal and replay across
genuine separate transactions remain mandatory after CI before final acceptance.
This clarification adds no production clock/default migration or new permission.
