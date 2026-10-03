# Existing messaging credits: exact conversion decision

Status: owner-approved conversion boundary, 2026-10-03. The owner explicitly
selected **1 old credit = INR 1 = 100 paise**. This is
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

The approved all-zero/no-history guard therefore cannot pass. Before the owner's
explicit selection, credits had no established INR exchange rate. Neither this
inventory nor a seed reason
establishes a price, currency value or permission to reset them.

## Selected exact conversion

The owner answered the exact credit-value clarification: "Yes: 1 old credit =
₹1 (100 paise)". The selected rate is exactly **100 integer paise per old credit**.
RBI's [Indian Currency FAQ](https://www.rbi.org.in/scripts/FS_FAQs.aspx?Id=136&fn=2753)
verifies the rupee-to-paise unit conversion; the owner supplies the commercial
credit valuation. They are separate evidence. The earlier alternatives were:

| Policy chosen by owner | Existing +5,000 / -500 credit example | Current 4,500 credit balance |
|---|---|---|
| 1 credit = 1 paisa | +INR 50 / -INR 5 | INR 45 |
| 1 credit = 100 paise (INR 1) | +INR 5,000 / -INR 500 | INR 4,500 |

The 100-paise row is selected; the 1-paisa row is retained only as the previous
unselected alternative. Convert the observed 4,500-credit aggregate to exactly
450,000 paise / INR 4,500. For the original +5,000/-500 example, retain evidence
of those credit values and convert to +500,000/-50,000 paise. No floating point,
rounding, reset or later exchange-rate change is authorized.

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

## Approval and remaining engineering boundary

The exact credit valuation is approved. Publish the precise schema/consumer
cutover and evidence declarations serially before independent test authors;
this approval does not freeze the complete WSP transport contract or attest to
actual provider setup, delivery or India compliance. Existing history is retained;
no reset is authorized. The Meta provider, verified-delivery debit, recipient
opt-in and protected setup boundaries already approved remain unchanged.

The owner's later instruction delegates this decision to the orchestrator and
requests continuation without repeating the credit question. The orchestrator
retains the already recorded 100-paise choice. The new read-only complete manifest
receipt at `docs/evidence/v2/wsp-wallet-exact-manifest.json` confirms each tenant's
balance/ledger equality and that all original monetary values fit bigint after
that exact conversion. Nothing has been converted or sent by either read.
