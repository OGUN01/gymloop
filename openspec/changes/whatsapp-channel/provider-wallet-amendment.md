# WhatsApp provider and wallet decision

Status: proposed owner decision, 2026-10-03. Not approved or frozen. Read with
`proposal.md` and `docs/design/v2/wsp-bar.md`. This prepares the decisions that
block independent authors; it authorizes no provider registration, contact,
purchase, credential provisioning, deployment or commercial conversion.

## Proposed boundary

Use direct Meta Cloud API with the business's own WABA and registered sender.
Permit one narrow `supabase/functions/whatsapp` Edge adapter for authenticated
dispatch and Meta challenge/signature-verified status callbacks. This is a
specific exception to the current Edge architecture, separate from MEDIA and
the pending NTF exception. Keep audiences, consent, wallet holds, tariff
authorization and all notification transitions in SQL. Web and mobile retain
caller-scoped clients; neither receives service credentials. Keep PostgreSQL
cron as scheduling authority, with protected CI-only provisioning and a
dedicated wakeup credential. No general HTTP relay or paid messaging SDK.

Dispatch cannot select recipients or prices from a request. The service-only
claim/authorize/finish facades described in the proposal validate durable
causal attempts, current sender/template/rate/recipient revisions and exact
result replay. Only normalized, signature-verified provider evidence may
finalize a delivery. Before authors start, publish exact facade signatures,
privileges, error precedence and shared NTF notification changes serially.

## Proposed money boundary

Replace credit-denominated columns in the existing wallet and append-only
ledger with integer-paise columns and explicit INR currency. Preserve one
locked ledger-backed balance, the existing reasoned super-admin adjustment
authority, exact request replay and all history. This does not equate one
credit to one paisa or allow an application to rewrite prior movements.

The CI migration must first lock and inventory both existing tables. It may
perform the zero-value unit transition only if every wallet balance is zero
and there are no ledger movements. An absent wallet is not fabricated money.
Any nonzero balance or any ledger history refuses migration and requires a
separate owner-approved, exact, history-preserving conversion schedule. No
delete, reset, rounding, invented exchange rate or implicit balance haircut.
The zero-value check must be repeated inside the same migration transaction;
a stale preliminary inventory cannot authorize conversion.

Reserve the approved maximum all-in integer-paise tariff before dispatch.
Debit exactly once only on verified billable delivery evidence, never mere
API acceptance, a click, a failed send or a payment-proof-like claim. Known
rejection releases its hold. An uncertain started send retains its evidence
and may not be blindly retried or treated as free. Zero-cost delivery creates
no zero-delta ledger entry. Currency/tariff/receipt mismatches refuse causal
debit; a sub-paise tariff requires a separately approved exact rounding rule.
No runtime tax or exchange-rate calculation is introduced.

## Proposed consent and activation boundary

Require versioned WhatsApp-specific opt-in from the actual adult or guardian
receiving the number, independently of generic service/marketing purpose
consent. Both predicates must hold at final authorization; changing the
recipient/contact revision revokes the old channel permission. A phone field
or existing guardian consent never grants WhatsApp permission.

Keep the proposal's INR-only, template-only, no-backfill and bounded attempt
defaults. Provider-unconfigured states remain truthful and useful through
the existing inbox and explicitly manual desk contact. They are not a live
delivery win and do not remove WSP from the all-v2 goal.

Before live activation the owner supplies the actual WABA/sender, approved
templates and categories, account billing evidence and effective INR tariff,
protected credential custody, and the recorded India compliance determination
required by F9. This amendment grants no legal sign-off or DLT exemption.
Credentials must never appear in a chat, repository, evidence artifact or
mobile/web build. Real-provider acceptance remains required on an explicitly
owner-designated, consented recipient after protected setup.

## Owner decision

Approve this Meta-direct architecture, guarded INR unit transition,
delivery-evidence charging and channel-specific consent boundary, or select
the explicit alternative provider/units in the proposal. Approval allows
serial contract completion and independent tests; it does not resolve missing
provider/compliance facts or authorize guessing a historical credit value.
