import { MutationForm } from '../../../preview-context';
import { formatDateTime, formatMoney, formatPhone, humanize, rupeesFromPaise } from '@gymloop/shared';
import { StatusWord } from '../../../status-word';
import { Constants } from '@gymloop/db';
import Link from 'next/link';
import { Alert } from '../../alert';
import { notFound } from 'next/navigation';
import { loadReceipt } from '../../../../lib/payments';
import { deskTime } from '../../../../lib/time';
import { requireAudience } from '../../../../lib/identity-session';

/**
 * A receipt — the piece of paper a member takes away, and the line an auditor
 * asks about.
 *
 * Seven facts and nothing else: the gym, the member, the amount, the method,
 * the date, the receipt number and the staff member who took the money. A
 * receipt that also carries a promotion is a receipt somebody stops trusting.
 *
 * **The amount is rendered from integer paise, once, here** (MNY-001). Nothing
 * between the column and this line is anything but the integer, and
 * `rupeesFromPaise` does the division with integer arithmetic so the last digit
 * is the one in the database.
 *
 * A payment in another gym is `notFound()`, and that is the policy's answer
 * rather than a check on this page: `payments_tenant_select` returns no row, so
 * "not this gym's payment" and "no such payment" are the same answer — which is
 * the honest one, because distinguishing them would confirm the payment exists.
 */
/** What each redirect code from the refund handler means to a person. */
/**
 * The statuses that mean money actually arrived, matching `app.grant_periods()`
 * and `GL036`'s money-arrived clause exactly.
 *
 * **This page gated on `paid` alone and the database does not.** A critic
 * measured 60,000 paise accepted against a `refunded` payment with headroom
 * left, while this screen showed no form and the line "This payment took
 * nothing, so there is nothing to send back" — false for that row. Latent only
 * because nothing writes `refunded` today; it becomes real the moment the
 * Razorpay webhook lands, which is the one part of this phase that is not
 * built.
 */
const ARRIVED = new Set(['paid', 'refunded', 'reversed']);

const MESSAGES: Record<string, string> = {
  bad_amount: 'That amount was not readable. Rupees and at most two paise digits.',
  // `GL036` now answers two questions — how much may go back, and whether any
  // money came in at all (round seventeen) — and the route maps both to this
  // one code because they are the same rule about the same ceiling. A critic
  // pointed out the old sentence explained only the first, and the second is
  // reachable by a plain POST even though the form is gated.
  exceeds_payment:
    'That refund is not possible against this payment — either it is more than the payment took, or the payment has not taken any money.',
  refund_not_yours: 'A refund is recorded by the person who sends it.',
  refund_is_a_record: 'A recorded refund cannot be edited. Record another one instead.',
  not_permitted: 'Only an owner or a manager may send money back. A front desk may take it, not return it.',
  invalid: 'That refund was not readable — check the amount and the reason.',
  refund_failed: 'That refund could not be saved.',
  idempotency_conflict: 'That submission already recorded different refund details. Check the refund below, then reload for a new request.',
};

export default async function ReceiptPage({
  params,
  searchParams,
}: {
  params: Promise<{ paymentId: string }>;
  searchParams: Promise<{ error?: string }>;
}) {
  const { paymentId } = await params;
  const { error } = await searchParams;
  const { identity } = await requireAudience('console');
  const canRefund = identity.kind === 'staff' &&
    (identity.role === 'gym_owner' || identity.role === 'gym_manager');
  const {
    payment, gym, refunds, addonOrderId, completedReturnedPaise,
    pendingRefundPaise, refundablePaise, errorMessage,
  } = await loadReceipt(paymentId);

  if (errorMessage !== null) {
    return (
      <main className="cl-page">
        <Alert>That receipt could not be loaded. {errorMessage}</Alert>
      </main>
    );
  }

  if (payment === null || gym === null) notFound();

  const takenAt = payment.paid_at ?? payment.created_at;

  return (
    <main className="cl-page">
      {/* One way back: to the add-on order this payment settled, when there
          is one, otherwise to the payments ledger. */}
      {addonOrderId ? (
        <Link href={`/add-ons/orders/${addonOrderId}`} className="cl-back print:hidden">
          ← Back to add-on order
        </Link>
      ) : (
        <Link href="/payments" className="cl-back print:hidden">
          ← All payments
        </Link>
      )}

      <article className="cl-panel">
        <header className="flex flex-wrap items-end justify-between gap-6 border-b border-rule pb-6">
          <div>
            <p className="cl-eyebrow">{gym.gym_code}</p>
            <h1 className="cl-title">{gym.name}</h1>
          </div>
          <div className="sm:text-right">
            <p className="cl-eyebrow">Receipt</p>
            <p className="text-lg font-semibold tabular-nums">
              {/* No receipt number means this payment is not `paid`. Saying so
                  is the point: a receipt for money not received would be the
                  one document in this product that lies. */}
              {payment.receipt_number ?? 'not issued'}
            </p>
          </div>
        </header>

        <dl className="cl-dl mt-6">
          <Row label="Amount">
            <span className="cl-metric-value">
              {formatMoney(payment.amount_paise, payment.currency)}
            </span>
          </Row>
          <Row label="Member">
            {payment.members.full_name}
            <span className="cl-muted ml-2 tabular-nums">{formatPhone(payment.members.phone)}</span>
          </Row>
          <Row label="Method">{humanize(payment.method)}</Row>
          <Row label="Date">{formatDateTime(takenAt, gym.timezone)}</Row>
          <Row label="Taken by">{payment.staff?.full_name ?? '—'}</Row>
          {payment.notes === null ? null : <Row label="Note">{payment.notes}</Row>}
        </dl>

        {ARRIVED.has(payment.status) ? null : (
          <p className="cl-alert mt-6" data-tone="warn">
            This payment is <strong>{humanize(payment.status).toLowerCase()}</strong>. It is not a record of money received.
          </p>
        )}

        {/* A paid payment with no number is a document that looks wrong and used
            to say nothing: this note was gated on the status, so it never
            appeared for exactly the case that needs it — a payment recorded
            before the gym's book started numbering. */}
        {payment.status === 'paid' && payment.receipt_number === null ? (
          <p className="cl-alert mt-6" data-tone="warn">
            This payment was recorded before this gym&rsquo;s receipt book was numbered, so it has no
            receipt number. The payment itself is unaffected.
          </p>
        ) : null}
      </article>

      {error === undefined ? null : (
        <Alert>{MESSAGES[error] ?? MESSAGES.refund_failed}</Alert>
      )}

      <section className="cl-section print:hidden" aria-labelledby="refunds-heading">
        <div className="cl-section-head">
          <h2 className="cl-section-title" id="refunds-heading">Refunds</h2>
        </div>

        {refunds.length === 0 ? (
          <p className="cl-muted">Nothing has been sent back.</p>
        ) : (
          <ul className="cl-rows">
            {refunds.map((row) => {
              const completed = row.status === 'completed';
              const recordedAt = completed ? row.processed_at : row.created_at;
              return <li key={row.id}>
                <span>
                  <span className="cl-row-title tabular-nums">
                    {formatMoney(row.amount_paise, row.currency)}
                  </span>
                  <span className="cl-row-meta">
                    {humanize(row.kind)} — {row.reason}
                  </span>
                </span>
                <span className="cl-row-meta text-right">
                  {row.staff?.full_name ?? '—'}
                  <br />
                  {completed ? 'Completed at' : 'Requested at'} {recordedAt ? deskTime(recordedAt, gym.timezone) : 'not recorded'} · <StatusWord status={row.status} />
                </span>
              </li>;
            })}
          </ul>
        )}

        {/* No control where one can only be refused: a payment that is not paid
            has taken nothing, and one refunded in full has nothing left. The
            database refuses both (`GL036`); offering the form anyway would be a
            button whose only outcome is an error. */}
        {canRefund && ARRIVED.has(payment.status) && refundablePaise !== '0' ? (
          <MutationForm method="post" action="/api/refunds" className="cl-form mt-6">
            <input type="hidden" name="paymentId" value={payment.id} />
            <input type="hidden" name="idempotencyKey" value={crypto.randomUUID()} />
            <div className="cl-form-row">
              <label className="cl-field">
                <span>Amount (₹)</span>
                <input
                  type="text"
                  name="amountRupees"
                  required
                  inputMode="decimal"
                  pattern="[0-9]+(\.[0-9]{1,2})?"
                  defaultValue={rupeesFromPaise(refundablePaise)}
                  className="cl-input tabular-nums"
                />
              </label>
              <label className="cl-field">
                <span>Kind</span>
                <select name="kind" required className="cl-input">
                  {Constants.public.Enums.refund_kind.map((kind) => (
                    <option key={kind} value={kind}>
                      {humanize(kind)}
                    </option>
                  ))}
                </select>
              </label>
              <label className="cl-field">
                <span>Reason</span>
                <input type="text" name="reason" required className="cl-input" />
              </label>
            </div>
            <div>
              <button type="submit" className="cl-btn cl-btn--danger">
                Record refund
              </button>
            </div>
          </MutationForm>
        ) : null}

        <p className="cl-muted mt-4 text-sm">
          {!ARRIVED.has(payment.status)
            ? 'This payment took nothing, so there is nothing to send back.'
            : completedReturnedPaise === payment.amount_paise
              ? 'This payment has been refunded in full.'
              : pendingRefundPaise !== '0'
                ? `Returned ${payment.currency} ${rupeesFromPaise(completedReturnedPaise)}. Refund requests pending ${payment.currency} ${rupeesFromPaise(pendingRefundPaise)}. Available for another refund request ${payment.currency} ${rupeesFromPaise(refundablePaise)}.`
                : `Returned ${payment.currency} ${rupeesFromPaise(completedReturnedPaise)}. Available for another refund request ${payment.currency} ${rupeesFromPaise(refundablePaise)}. Only an owner or a manager may send money back.`}
        </p>
      </section>

      <p className="cl-muted mt-6 text-sm print:hidden">
        Print this page for the member. Receipt numbers are the gym&rsquo;s own, one series per
        financial year.
      </p>
    </main>
  );
}

/** One labelled fact. Seven of these are the whole document. */
function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <>
      <dt>{label}</dt>
      <dd>{children}</dd>
    </>
  );
}
