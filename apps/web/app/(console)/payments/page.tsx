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

  const takings = paidTotals(payments);
  const paidCount = payments.filter((row) => row.status === 'paid').length;
  const shownCaption = `${paidCount === payments.length ? `${paidCount} ${paidCount === 1 ? 'payment' : 'payments'}` : `${paidCount} paid of ${payments.length}`}${nextHref === null ? '' : ' · older ones below'}`;

  return (
    <main className="cl-page">
      <div className="cl-page-header money-pay-header">
        <div>
          <p className="cl-eyebrow">Money</p>
          <h1 className="cl-title money-page-title">Payments</h1>
          <p className="cl-lede money-lede">
            Money taken at the desk, latest entries first. Take a payment from a
            member&rsquo;s page.
          </p>
        </div>
        {takings.length === 0 ? null : (
          <div className="cl-metric money-summary">
            <span className="cl-eyebrow">This page</span>
            <span className="cl-metric-value">{takings.join(' · ')}</span>
            <small className="cl-muted">{shownCaption}</small>
          </div>
        )}
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
        <div className="cl-section money-pay-list">
          <div className="cl-ledger-wrap money-wide">
            <table className="cl-ledger money-ledger">
              <thead>
                <tr>
                  <th scope="col">Receipt</th>
                  <th scope="col">Member</th>
                  <th scope="col" className="cl-num">Amount</th>
                  <th scope="col">Method</th>
                  <th scope="col" className="money-takenby">Taken by</th>
                  {/* The sort key is the column: rows are in entry order, so the
                      date shown first is the entry date. A payment dated to
                      another day says so underneath. */}
                  <th scope="col">Recorded</th>
                </tr>
              </thead>
              <tbody>
                {payments.map((row) => {
                  const when = whenOf(row, timezone);
                  return (
                    <tr key={row.id}>
                      <td className="tabular-nums">
                        <Link href={`/payments/${row.id}`} className={receiptClass(row)}>
                          {/* A payment that is not paid has no receipt number, and
                              saying so is more useful than an empty cell: it is the
                              difference between money received and an intention to
                              pay (PAY-008). */}
                          {receiptLabel(row)}
                        </Link>
                      </td>
                      <td className="money-member">
                        {/* A way back to the member. Its absence is why a critic
                            reached for the browser's Back button, which restored a
                            stale form and silently dropped a second payment. */}
                        <Link href={`/memberships/${row.member_id}`} title={row.members.full_name}>{row.members.full_name}</Link>
                      </td>
                      <td className="cl-num money-amount">{formatMoney(row.amount_paise, row.currency)}</td>
                      <td>{humanize(row.method)}</td>
                      <td className="money-takenby">{row.staff?.full_name ?? '—'}</td>
                      <td className="tabular-nums money-when">
                        <span title={`Recorded ${when.recordedDay}, ${when.recordedTime}`}>
                          {when.recordedDay}<span className="money-when-time">, {when.recordedTime}</span>
                        </span>
                        {when.paidDay === null ? null : <span className="money-when-paid">Paid {when.paidDay}</span>}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          {/* The same payments as ruled rows for a phone: member and amount on
              the first line, how, when and the receipt on the second. */}
          <ul className="cl-rows money-narrow">
            {payments.map((row) => {
              const when = whenOf(row, timezone);
              return (
                <li key={row.id} className="money-row">
                  {/* The whole row opens the receipt (the link stretches over
                      it in money.css); the member's name stays its own link on
                      top, so the way back to the member is kept. */}
                  <Link href={`/memberships/${row.member_id}`} className="money-row-member">
                    {row.members.full_name}
                  </Link>
                  <span className="money-row-amount">{formatMoney(row.amount_paise, row.currency)}</span>
                  <span className="money-row-meta">
                    {humanize(row.method)} · {when.recordedDay}
                  </span>
                  <Link href={`/payments/${row.id}`} className={`money-row-receipt ${receiptClass(row)}`} aria-label={`Receipt ${receiptLabel(row)}`}>
                    {receiptLabel(row)}
                  </Link>
                  {when.paidDay === null ? null : <span className="money-row-paid">Paid {when.paidDay}</span>}
                </li>
              );
            })}
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

type Row = {
  receipt_number: string | null;
  status: string;
  paid_at: string | null;
  created_at: string;
  amount_paise: string;
  currency: string;
  method: string;
};

/**
 * The receipt number, or why there is none: an online payment's receipt is
 * the provider's, and anything else unnumbered says its state (PAY-008).
 */
function receiptLabel(row: Pick<Row, 'receipt_number' | 'status' | 'method'>): string {
  if (row.receipt_number !== null) return row.receipt_number;
  if (row.status === 'paid' && row.method === 'razorpay') return 'Online';
  return `${humanize(row.status)} — no receipt`;
}

/** A real receipt number reads as a link; the "no receipt" note reads as a note. */
function receiptClass(row: Pick<Row, 'receipt_number'>): string {
  return row.receipt_number === null ? 'money-noreceipt' : 'money-receipt-link';
}

/**
 * When the payment was entered — the ledger's sort key — in the gym's day,
 * and the day it was paid, but only when that is a different day.
 */
function whenOf(row: Pick<Row, 'paid_at' | 'created_at'>, timezone: string) {
  const [recordedDay = '', recordedTime = ''] = formatDateTime(row.created_at, timezone).split(', ');
  const [paidDay = recordedDay] = row.paid_at === null ? [] : formatDateTime(row.paid_at, timezone).split(', ');
  return { recordedDay, recordedTime, paidDay: paidDay === recordedDay ? null : paidDay };
}

/** What the paid rows on this page add up to, per currency — display only, exact in BigInt. */
function paidTotals(rows: readonly Row[]): string[] {
  const totals = new Map<string, bigint>();
  for (const row of rows) {
    if (row.status !== 'paid') continue;
    totals.set(row.currency, (totals.get(row.currency) ?? BigInt(0)) + BigInt(row.amount_paise));
  }
  return [...totals].map(([currency, paise]) => formatMoney(paise.toString(), currency));
}
