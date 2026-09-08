import { PAYMENT_PAGE_SIZE_DEFAULT, rupeesFromPaise } from '@gymloop/shared';
import Link from 'next/link';
import { Alert } from '../alert';
import { deskTime, loadPayments } from '../../../lib/payments';

/**
 * The day's takings — what a front desk reconciles the cash drawer against at
 * close, and where every receipt is reachable from.
 *
 * A ledger, not a dashboard. Newest first, because the question at 9pm is
 * "what did we take today", and the answer is at the top.
 *
 * A Server Component with no client JavaScript, on the same terms as the red
 * list and the check-in gate: a front desk on a bad connection in Indore is the
 * user, and this page must render an amount without a bundle.
 */

/** What the handler's short codes mean. The screen owns the wording. */
const MESSAGES: Record<string, string> = {
  bad_amount:
    'That amount was not readable. Rupees and at most two paise digits — 1500 or 1500.50, never 1500.505.',
  payment_not_yours: 'A payment is recorded by the person who took it.',
  provider_claimed:
    'An online payment is recorded by the provider. The desk takes cash, UPI, card or a bank transfer.',
  not_permitted: 'Your role may not record payments.',
  invalid: 'That payment was not readable — check the amount and the method.',
  payment_failed: 'That payment could not be saved.',
};

export default async function PaymentsPage({
  searchParams,
}: {
  searchParams: Promise<{ cursor?: string; limit?: string; error?: string }>;
}) {
  const params = await searchParams;
  const { payments, pageSize, nextCursor, errorMessage } = await loadPayments(searchParams);
  const problem =
    params.error === undefined ? null : (MESSAGES[params.error] ?? MESSAGES.payment_failed);

  const nextHref =
    nextCursor === null
      ? null
      : `?${new URLSearchParams({
          ...(pageSize === PAYMENT_PAGE_SIZE_DEFAULT ? {} : { limit: String(pageSize) }),
          cursor: nextCursor,
        }).toString()}`;

  return (
    <main className="mx-auto max-w-5xl px-6 py-8">
      <div className="flex items-baseline justify-between">
        <h1 className="text-xl font-semibold">Payments</h1>
        <Link href="/console" className="text-sm text-neutral-600 underline">
          Members
        </Link>
      </div>
      <p className="mt-1 text-sm text-neutral-600">
        Money taken at the desk, newest first. Take a payment from a member&rsquo;s page.
      </p>

      {problem === null ? null : <Alert>{problem}</Alert>}

      {errorMessage === null ? null : (
        <Alert>The payments could not be loaded. {errorMessage}</Alert>
      )}

      {payments.length === 0 ? (
        <p className="mt-8 text-sm text-neutral-600">No payments recorded yet.</p>
      ) : (
        <table className="mt-6 w-full text-sm">
          <thead className="text-left text-neutral-600">
            <tr className="border-b border-neutral-200">
              <th className="py-2 font-medium">Receipt</th>
              <th className="py-2 font-medium">Member</th>
              <th className="py-2 text-right font-medium">Amount</th>
              <th className="py-2 font-medium">Method</th>
              <th className="py-2 font-medium">Taken by</th>
              <th className="py-2 font-medium">When</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-neutral-200">
            {payments.map((row) => (
              <tr key={row.id}>
                <td className="py-2 tabular-nums">
                  <Link href={`/payments/${row.id}`} className="underline">
                    {/* A payment that is not paid has no receipt number, and
                        saying so is more useful than an empty cell: it is the
                        difference between money received and an intention to
                        pay (PAY-008). */}
                    {row.receipt_number ?? `${row.status} — no receipt`}
                  </Link>
                </td>
                <td className="py-2">{row.members.full_name}</td>
                <td className="py-2 text-right tabular-nums">
                  {row.currency} {rupeesFromPaise(row.amount_paise)}
                </td>
                <td className="py-2">{row.method.replace('_', ' ')}</td>
                <td className="py-2">{row.staff?.full_name ?? '—'}</td>
                <td className="py-2 tabular-nums text-neutral-600">
                  {deskTime(row.paid_at ?? row.created_at)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {nextHref === null ? null : (
        <Link href={nextHref} className="mt-6 inline-block text-sm underline">
          Older payments
        </Link>
      )}
    </main>
  );
}
