import { PAYMENT_PAGE_SIZE_DEFAULT, formatDateTime, formatMoney, humanize } from '@gymloop/shared';
import Link from 'next/link';
import { Alert } from '../alert';
import { loadPayments } from '../../../lib/payments';

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
  already_recorded:
    'Something this payment would create already exists, so nothing was recorded. Reload the member’s page and take it again.',
  payment_is_a_record:
    'A payment that has been taken cannot be edited. Record a refund or a new payment instead.',
  status_cannot_go_there: 'A payment cannot go back to that state.',
  membership_not_theirs: 'That membership belongs to a different member.',
  payment_failed: 'That payment could not be saved.',
};

export default async function PaymentsPage({
  searchParams,
}: {
  searchParams: Promise<{ cursor?: string; limit?: string; error?: string }>;
}) {
  const params = await searchParams;
  const { payments, pageSize, timezone, nextCursor, errorMessage } = await loadPayments(searchParams);
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
    <main className="cl-page">
      <div className="cl-page-header">
        <div>
          <p className="cl-eyebrow">Front desk</p>
          <h1 className="cl-title">Payments</h1>
          <p className="cl-lede">
            Money taken at the desk, most recently recorded first. Take a payment from a
            member&rsquo;s page.
          </p>
        </div>
      </div>

      {problem === null ? null : <Alert>{problem}</Alert>}

      {errorMessage === null ? null : (
        <Alert>The payments could not be loaded. {errorMessage}</Alert>
      )}

      {payments.length === 0 ? (
        <div className="cl-empty cl-section">
          <strong>No payments recorded yet.</strong>
          <p>Take a payment from a member&rsquo;s page and it appears here.</p>
        </div>
      ) : (
        <div className="cl-section">
          <div className="cl-ledger-wrap hidden sm:block">
            <table className="cl-ledger">
              <thead>
                <tr>
                  <th scope="col">Receipt</th>
                  <th scope="col">Member</th>
                  <th scope="col" className="cl-num">Amount</th>
                  <th scope="col">Method</th>
                  <th scope="col">Taken by</th>
                  <th scope="col">When</th>
                </tr>
              </thead>
              <tbody>
                {payments.map((row) => (
                  <tr key={row.id}>
                    <td className="tabular-nums">
                      <Link href={`/payments/${row.id}`}>
                        {/* A payment that is not paid has no receipt number, and
                            saying so is more useful than an empty cell: it is the
                            difference between money received and an intention to
                            pay (PAY-008). */}
                        {receiptLabel(row)}
                      </Link>
                    </td>
                    <td>
                      {/* A way back to the member. Its absence is why a critic
                          reached for the browser's Back button, which restored a
                          stale form and silently dropped a second payment. */}
                      <Link href={`/memberships/${row.member_id}`}>{row.members.full_name}</Link>
                    </td>
                    <td className="cl-num">{formatMoney(row.amount_paise, row.currency)}</td>
                    <td>{humanize(row.method)}</td>
                    <td>{row.staff?.full_name ?? '—'}</td>
                    <td className="cl-muted tabular-nums">
                      {formatDateTime(row.paid_at ?? row.created_at, timezone)}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* The same payments as ruled rows for a phone: member and amount on
              the first line, how, when and the receipt on the second. */}
          <ul className="cl-rows sm:hidden">
            {payments.map((row) => (
              <li key={row.id} className="flex-nowrap">
                <span>
                  <Link href={`/memberships/${row.member_id}`} className="cl-row-title text-ink">
                    {row.members.full_name}
                  </Link>
                  <span className="cl-row-meta tabular-nums">
                    {humanize(row.method)} · {formatDateTime(row.paid_at ?? row.created_at, timezone)} ·{' '}
                    <Link href={`/payments/${row.id}`} className="text-clay whitespace-nowrap">
                      {receiptLabel(row)}
                    </Link>
                  </span>
                </span>
                <span className="font-semibold tabular-nums">
                  {formatMoney(row.amount_paise, row.currency)}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}

      {nextHref === null ? null : (
        <div className="mt-6">
          <Link href={nextHref} className="cl-btn">
            Older payments
          </Link>
        </div>
      )}
    </main>
  );
}

/** The receipt number, or why there is none. */
function receiptLabel(row: { receipt_number: string | null; status: string }): string {
  return row.receipt_number ?? `${humanize(row.status)} — no receipt`;
}
