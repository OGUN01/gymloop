# Existing messaging credits: exact conversion decision

Status: proposed owner decision, 2026-10-03. Not approved or frozen. This is
the explicit nonzero/history case required by the approved
`provider-wallet-amendment.md`; its zero-value migration guard is unchanged.

## Observed inventory

The correctly linked CLI queried project `pecxrpskmfeuyzngvewq` in a read-only
BEGIN/ROLLBACK transaction while all DB workflows were completed and the
shared Cloud lock was held. It returned three wallet rows, one nonzero wallet,
an aggregate balance of 4,500 credits, two ledger rows and net ledger movement
of 4,500 credits. The lock was released; no balance or record was changed.
The seed explains credit units and contains an opening +5,000 and a -500
movement. The aggregate query does not by itself prove those are the only
exact live row identities/facts, so CI must validate that explicitly.

The approved all-zero/no-history guard therefore cannot pass. Credits have
no established INR exchange rate. Neither this inventory nor a seed reason
establishes a price, currency value or permission to reset them.

## Concrete conversion choices

The owner must set an exact positive integer number of paise per existing
credit. Two simple possible policies are:

| Policy chosen by owner | Existing +5,000 / -500 credit example | Current 4,500 credit balance |
|---|---|---|
| 1 credit = 1 paisa | +INR 50 / -INR 5 | INR 45 |
| 1 credit = 100 paise (INR 1) | +INR 5,000 / -INR 500 | INR 4,500 |

These are policy alternatives, not an inferred valuation or recommendation.
Another exact integer rate may be supplied. A fractional rate requires a
separate rounding/remainder contract; implementation must not choose one.

## Mandatory conversion mechanics after selection

Preserve every wallet tenant, ledger id, sign, ordering, reason, notification
reference, request key, creator and original timestamp. Retain the original
credit values as immutable conversion evidence with the selected exact rate,
currency, approval reference and cutover time. Multiply all original balances,
deltas and historical balance-after values with exact bigint arithmetic; null
historical balance-after stays null. Refuse overflow, inconsistent wallet/net
ledger facts or unexpected rows. Never delete history, zero a balance, invent
an opening monetary receipt, mutate a source notification or invent a debit.

CI alone applies the forward-only transaction under locks on both existing
tables. It validates the approved inventory and exact row facts again inside
that transaction; any intervening adjustment/history change refuses and
returns to the owner. Conversion must preserve the signed ledger equation and
existing replay/attribution rules. Tests for both exact mapping and refusal
are written independently before source. Update consumers atomically to
explicit INR integer paise, without reinterpreting credit-labelled API fields
silently. This amendment does not authorize changing the selected rate later.

## Owner decision

Select the exact integer-paise value of one existing credit, or keep the INR
migration blocked until the business valuation is supplied. Existing history
is retained under either waiting or conversion; no reset is proposed. The
Meta provider, verified-delivery debit, recipient opt-in and protected setup
boundaries already approved remain unchanged.
