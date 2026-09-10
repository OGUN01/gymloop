# Phase 6 add-on working-screen brief

Accepted Astra UI/UX brief under ADR-111. This slice must be clear, responsive
and usable; Phase 7 owns the broader visual-system redesign, density refinement,
motion, dark mode and calendar drag interactions.

## Reference bar

- Square item editing: https://squareup.com/help/us/en/article/8335-create-and-edit-items
  for kind-dependent catalogue fields and explicit availability.
- Square appointments: https://squareup.com/help/us/en/article/5349-schedule-and-accept-appointments
  for customer, service, trainer and time selection.
- Stripe mobile payment details: https://docs.stripe.com/dashboard/mobile for
  placing receipts, status and actions around one transaction.
- Stripe refunds: https://docs.stripe.com/refunds for separating request progress
  from completed return history. Gymloop's manual-return contract controls the
  labels: staff confirmation records cash returned and performs no transfer.

## Routes and information architecture

`/add-ons` is the staff workspace with catalogue, orders and PT-session views,
reachable from the console. Query state may open catalogue create/edit and a
sale draft, but a new sale keeps member and offer unselected until an explicit
choice. `/add-ons/orders/[orderId]` shows frozen sold terms, fulfilment, sessions,
receipt linkage and returned money. `/member/add-ons` shows active offers and
own orders; selected offer/order query state stays inside the member audience.
Members never enter the staff receipt route.

## Catalogue and sale

Every offer shows name, kind, exact stored amount/currency, validity and
cancellation terms, plus stock for a product or trainer, gym-stated
qualification and session count for PT. New saleable offers use INR. A readable
legacy non-INR offer keeps its actual currency, says unsupported currency and
disables sale without conversion or relabelling. Inactive, out-of-stock and
details-incomplete are separate states. Incomplete history says unavailable and
never invents terms.

Owner/manager editing has shared name, description, rupee price, validity,
terms and active fields; product adds stock, PT adds trainer/qualification/count,
and diet adds none. Explain why referenced kind cannot change. Stock adjustment
is explicit and never implied by a refund.

The sale is one sequence: select member, select offer/fulfilment, review. Reuse
phone search without losing the draft during search/pagination. Show quantity,
unit price, exact total, validity, terms and PT disclosure before commitment.
PT/diet quantity is visibly one; product quantity is a positive integer. PT
requires its assigned trainer and first gym-timezone slot. Paid sale requires an
explicit manual method and “Record INR … received”; free sale requires a reason,
no method, and “Accept complimentary offer”. An uncertain response preserves
the original key and request facts and offers the same-sale retry.

## Order, fulfilment and return

Lead with the frozen sale snapshot, member, seller, acceptance date, inclusive
validity, quantity, exact money/payment state and current fulfilment. Products
complete on sale. Diet exposes “Mark diet plan delivered”. PT shows initial and
later sessions plus Used, Scheduled, Available to book and Purchased counts.
Expired is a derived label. Missing history says “Not recorded” or “Historical
terms unavailable”. Complimentary history says “Complimentary · INR 0.00 — no
payment or receipt.”

PT rows show member, assigned trainer, local slot, status and order link. Valid
controls are Schedule session, Mark completed, Cancel session and Mark no-show.
Reschedule means cancel then create. Terminal rows have no edit/undo control;
unavailable actions explain expiry, full return or exhausted capacity.

Receipt/detail views distinguish Returned (completed refund/reversal only),
Refund requests pending (requested/processing) and Available for another refund
request (existing reserved ceiling). “Fully returned” requires completed money
equal to the payment. Manual completion repeats exact amount/currency/reason and
uses “Confirm money returned”, with text that it records staff confirmation and
does not initiate a transfer.

## Failure, responsive and accessible behavior

Quote changes refresh terms for review while retaining the draft. Stock or slot
conflicts retain selections and highlight the changed fact. Unavailable people
or offers provide reselection. Retryable/uncertain failures retain the command
key. Idempotency conflict points to recent orders. Each independently loaded
section has its own alert/retry and truthful empty state.

At 320px use one column, labelled rows, wrapping actions and full-width primary
controls. At tablet width place review beside the form when space permits. Use
approximately 44px touch targets, visible focus, explicit labels,
`fieldset`/`legend` for choices, `aria-invalid` with associated errors, a focused
error summary, and live pending/success status. Status always has text as well
as color. Verify 320px, 768px, keyboard-only use and 200% zoom. Preview preserves
all reads and hides every mutation control.
