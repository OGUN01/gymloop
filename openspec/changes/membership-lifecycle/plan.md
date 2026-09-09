# Membership lifecycle — closing OPEN-030

Phase 5 archived GO with eight open items. Three are reachable money
manipulation; this change closes the largest, which three other rules already
depend on.

**`payments` has a state machine and `memberships` does not.**
`app.payment_transition_allowed()` decides which payment status may follow
which, and `GL039` enforces it. `memberships.status` has nothing: a critic
measured an ordinary **front-desk** session writing `cancelled → active`,
reviving a retired membership in one statement, and writing `expired` onto a
membership live for another ten days.

`docs/data-model.md` has listed the legal transitions since Phase 1 and calls
`expired` and `cancelled` terminal. **The gap was never a missing contract — it
is that nothing enforces the one that exists**, and a routing-table document
asserts a rule the database does not keep.

## Why this is not a small rule

Three rules already turn on the answer:

- **ADR-096** — a retired membership does not grow. Reachable revival is what
  made "retired" temporary.
- **ADR-084** — the check-in gate reads status as well as dates.
- `memberships_tenant_id_member_id_live_key`, partial on `('active','frozen')`.

And it forces a decision ADR-096 deferred without knowing it: **if retirement is
terminal, money paid against a retired membership can never be granted.**
ADR-096 kept that money on record precisely because a revival might yet count
it. That reasoning expires here, and the replacement has to be stated rather
than left implied.

## Order

Contract, two blind authors, tests red, implementation, critic. Then OPEN-029
(creation is unpoliced for dates) and OPEN-031 (refunds have no idempotency
key), each on its own.
