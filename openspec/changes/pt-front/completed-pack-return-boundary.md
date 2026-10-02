# Completed-pack waiver: recorded return boundary

Status: awaiting owner clarification. Both independent PTF DB authors are paused;
no PTF implementation has started. This document does not change the frozen rule.

The approved last-session amendment says “any recorded return for this order
excludes the completed-pack exception”. The existing refund lifecycle has
requested, processing, completed and failed records. Its ordinary full-return
predicate counts only completed amounts. Both independent authors identified
the same question without reading one another or an implementation.

## Concrete proposed clarification (retain the approved literal boundary)

For the completed-pack exception only, a recorded return means ANY row of
public.refunds with the same tenant_id and the order's payment_id, regardless of
requested/processing/completed/failed status, partial/full amount or currency.
Any such row refuses GL055 order_unavailable before restoration. An unrelated
tenant/payment's refund does not exclude the pack. This exception never changes
ordinary full-return accounting or active-pack waiver rules.

This retains the broad literal “any recorded return” protection, including a
failed historical request. Its tradeoff is that a failed attempt still prevents
reactivating a completed pack through this exceptional command.

Alternative owner choice: exclude only same-tenant/payment completed refunds.
Requested, processing and failed records then do not exclude this exception by
themselves. The ordinary amount/currency return rules remain unchanged. This
narrows the currently approved broad wording and requires an explicit amendment.

After the owner chooses, freeze one exact predicate in the proposal and original
waiver amendment, commit the clarification, obtain a fresh blind contract review,
then resume both independent authors. Tests cover all four statuses, partial/full
completed amounts, unrelated payment/tenant records and no-change refusal.
The separate implementer must follow those tests without reading holdouts.
