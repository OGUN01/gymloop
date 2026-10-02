# Completed-pack waiver: recorded return boundary

Status: owner approved in the campaign chat on 2026-10-02: block ANY refund
record, retaining the approved literal boundary. Both independent DB authors
remain paused until the updated freeze receives fresh review. No PTF
implementation has started.

The approved last-session amendment says “any recorded return for this order
excludes the completed-pack exception”. The existing refund lifecycle has
requested, processing, completed and failed records. Its ordinary full-return
predicate counts only completed amounts. Both independent authors identified
the same question without reading one another or an implementation.

## Approved clarification (retain the approved literal boundary)

For the completed-pack exception only, a recorded return means ANY row of
public.refunds with the same tenant_id and the order's payment_id, regardless of
requested/processing/completed/failed status, partial/full amount or currency.
Any such row refuses GL055 order_unavailable before restoration. An unrelated
tenant/payment's refund does not exclude the pack. This exception never changes
ordinary full-return accounting or active-pack waiver rules.

This retains the broad literal “any recorded return” protection, including a
failed historical request. Its tradeoff is that a failed attempt still prevents
reactivating a completed pack through this exceptional command.

Rejected alternative: exclude only same-tenant/payment completed refunds.
Requested, processing and failed records then do not exclude this exception by
themselves. The ordinary amount/currency return rules remain unchanged. This
narrows the currently approved broad wording and requires an explicit amendment.

After this approval, freeze the exact predicate in the proposal and original
waiver amendment, commit the clarification, obtain a fresh blind contract review,
then resume both independent authors. Tests cover all four statuses, partial/full
completed amounts, unrelated payment/tenant records and no-change refusal.
The separate implementer must follow those tests without reading holdouts.
