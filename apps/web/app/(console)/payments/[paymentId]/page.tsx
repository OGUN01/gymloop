import { rupeesFromPaise } from '@gymloop/shared';
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
export default async function ReceiptPage({ params }: { params: Promise<{ paymentId: string }> }) {
  const { paymentId } = await params;
  const { payment, gym, errorMessage } = await loadReceipt(paymentId);

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

        {payment.status === 'paid' ? null : (
          <p className="mt-4 rounded-md bg-amber-50 px-3 py-2 text-xs text-amber-800">
            This payment is <strong>{payment.status}</strong>. It is not a record of money received.
          </p>
        )}
      </article>

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
