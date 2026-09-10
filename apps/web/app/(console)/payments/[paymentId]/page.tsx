import { MutationForm } from '../../../preview-context';
import { rupeesFromPaise } from '@gymloop/shared';
import { Constants } from '@gymloop/db';
import Link from 'next/link';
import { Alert } from '../../alert';
import { notFound } from 'next/navigation';
import { deskTime, loadReceipt } from '../../../../lib/payments';

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
  const { payment, gym, refunds, refundablePaise, errorMessage } = await loadReceipt(paymentId);

  if (errorMessage !== null) {
    return (
      <main className="mx-auto max-w-xl px-6 py-8">
        <Alert>That receipt could not be loaded. {errorMessage}</Alert>
      </main>
    );
  }

  if (payment === null || gym === null) notFound();

  const takenAt = payment.paid_at ?? payment.created_at;

  return (
    <main className="mx-auto max-w-xl px-6 py-8">
      <Link href="/payments" className="text-sm text-neutral-600 underline print:hidden">
        All payments
      </Link>

      <article className="mt-4 rounded-lg border border-neutral-300 p-6">
        <header className="flex items-baseline justify-between border-b border-neutral-200 pb-4">
          <div>
            <h1 className="text-lg font-semibold">{gym.name}</h1>
            <p className="text-xs text-neutral-600">{gym.gym_code}</p>
          </div>
          <div className="text-right">
            <p className="text-xs uppercase tracking-wide text-neutral-600">Receipt</p>
            <p className="font-semibold tabular-nums">
              {/* No receipt number means this payment is not `paid`. Saying so
                  is the point: a receipt for money not received would be the
                  one document in this product that lies. */}
              {payment.receipt_number ?? 'not issued'}
            </p>
          </div>
        </header>

        <dl className="mt-4 space-y-3 text-sm">
          <Row label="Member">
            {payment.members.full_name}
            <span className="ml-2 tabular-nums text-neutral-600">{payment.members.phone}</span>
          </Row>
          <Row label="Amount">
            <span className="text-base font-semibold tabular-nums">
              {payment.currency} {rupeesFromPaise(payment.amount_paise)}
            </span>
          </Row>
          <Row label="Method">{payment.method.replace('_', ' ')}</Row>
          <Row label="Date">{deskTime(takenAt, gym.timezone)}</Row>
          <Row label="Taken by">{payment.staff?.full_name ?? '—'}</Row>
          {payment.notes === null ? null : <Row label="Note">{payment.notes}</Row>}
        </dl>

        {ARRIVED.has(payment.status) ? null : (
          <p className="mt-4 rounded-md bg-amber-50 px-3 py-2 text-xs text-amber-800">
            This payment is <strong>{payment.status}</strong>. It is not a record of money received.
          </p>
        )}

        {/* A paid payment with no number is a document that looks wrong and used
            to say nothing: this note was gated on the status, so it never
            appeared for exactly the case that needs it — a payment recorded
            before the gym's book started numbering. */}
        {payment.status === 'paid' && payment.receipt_number === null ? (
          <p className="mt-4 rounded-md bg-amber-50 px-3 py-2 text-xs text-amber-800">
            This payment was recorded before this gym&rsquo;s receipt book was numbered, so it has no
            receipt number. The payment itself is unaffected.
          </p>
        ) : null}
      </article>

      {error === undefined ? null : (
        <Alert>{MESSAGES[error] ?? MESSAGES.refund_failed}</Alert>
      )}

      <section className="mt-8 print:hidden">
        <h2 className="text-base font-semibold">Refunds</h2>

        {refunds.length === 0 ? (
          <p className="mt-1 text-sm text-neutral-600">Nothing has been sent back.</p>
        ) : (
          <ul className="mt-2 divide-y divide-neutral-200 text-sm">
            {refunds.map((row) => (
              <li key={row.id} className="flex justify-between gap-4 py-2">
                <span>
                  <span className="font-medium tabular-nums">
                    {row.currency} {rupeesFromPaise(row.amount_paise)}
                  </span>{' '}
                  {row.kind} — {row.reason}
                </span>
                <span className="text-right text-neutral-600">
                  {row.staff?.full_name ?? '—'}
                  <br />
                  {deskTime(row.created_at, gym.timezone)} · {row.status}
                </span>
              </li>
            ))}
          </ul>
        )}

        {/* No control where one can only be refused: a payment that is not paid
            has taken nothing, and one refunded in full has nothing left. The
            database refuses both (`GL036`); offering the form anyway would be a
            button whose only outcome is an error. */}
        {ARRIVED.has(payment.status) && refundablePaise > 0 ? (
          <MutationForm method="post" action="/api/refunds" className="mt-4 flex flex-wrap items-end gap-3">
            <input type="hidden" name="paymentId" value={payment.id} />
            <input type="hidden" name="idempotencyKey" value={crypto.randomUUID()} />
            <label className="text-sm">
              <span className="block text-neutral-600">Amount (₹)</span>
              <input
                type="text"
                name="amountRupees"
                required
                inputMode="decimal"
                pattern="\d{1,9}(\.\d{1,2})?"
                defaultValue={rupeesFromPaise(refundablePaise)}
                className="mt-1 w-32 rounded-md border border-neutral-300 px-3 py-2 text-base tabular-nums"
              />
            </label>
            <label className="text-sm">
              <span className="block text-neutral-600">Kind</span>
              <select
                name="kind"
                required
                className="mt-1 rounded-md border border-neutral-300 px-3 py-2 text-base"
              >
                {Constants.public.Enums.refund_kind.map((kind) => (
                  <option key={kind} value={kind}>
                    {kind}
                  </option>
                ))}
              </select>
            </label>
            <label className="text-sm">
              <span className="block text-neutral-600">Reason</span>
              <input
                type="text"
                name="reason"
                required
                className="mt-1 rounded-md border border-neutral-300 px-3 py-2 text-base"
              />
            </label>
            <button type="submit" className="rounded-md bg-neutral-900 px-4 py-2 text-white">
              Record refund
            </button>
          </MutationForm>
        ) : null}

        <p className="mt-2 text-xs text-neutral-500">
          {!ARRIVED.has(payment.status)
            ? 'This payment took nothing, so there is nothing to send back.'
            : refundablePaise > 0
              ? `${payment.currency} ${rupeesFromPaise(refundablePaise)} of this payment has not been refunded. Only an owner or a manager may send money back.`
              : 'This payment has been refunded in full.'}
        </p>
      </section>

      <p className="mt-4 text-xs text-neutral-500 print:hidden">
        Print this page for the member. Receipt numbers are the gym&rsquo;s own, one series per
        financial year.
      </p>
    </main>
  );
}

/** One labelled fact. Seven of these are the whole document. */
function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-neutral-600">{label}</dt>
      <dd className="text-right">{children}</dd>
    </div>
  );
}
