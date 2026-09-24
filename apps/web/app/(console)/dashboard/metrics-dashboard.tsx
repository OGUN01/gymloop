'use client';

import {
  BASIS_POINTS_PER_PERCENT,
  OWNER_OVERVIEW_CASE_PREVIEW_LIMIT,
  OWNER_OVERVIEW_SUPPORTING_PREVIEW_LIMIT,
  ratioBasisPoints,
  rupeesFromPaise,
  type OwnerMetrics,
  UI_TOKENS,
  formatDateTime,
  formatDay,
  formatDayRange,
  formatMoney as formatDisplayMoney,
  humanize,
} from '@gymloop/shared';
import { useState } from 'react';
import { ChevronRight, CreditCard, UserPlus } from 'lucide-react';

type CardKey =
  | 'visits' | 'liveMembers' | 'pausedMembers' | 'cases' | 'followUpsDue'
  | 'recoveries' | 'cash' | 'renewals' | 'leads' | 'addonCash' | 'ptOrders';
function moneySummary(rows: OwnerMetrics['cards']['cash']): string {
  return rows.length === 0
    ? 'No cash movement'
    : rows.map((row) => formatDisplayMoney(row.netPaise, row.currency)).join(' · ');
}
function formatMoney(currency: string, paise: string, useRupeeSymbol = false): string {
  const rendered = rupeesFromPaise(paise);
  const [whole = '0', decimal = '00'] = rendered.replace('-', '').split('.');
  const grouped = currency === 'INR'
    ? new Intl.NumberFormat('en-IN').format(BigInt(whole))
    : whole;
  const sign = rendered.startsWith('-') ? '-' : '';
  return currency === 'INR' && useRupeeSymbol
    ? `${sign}₹${grouped}${decimal === '00' ? '' : `.${decimal}`}`
    : `${sign}${currency} ${grouped}.${decimal}`;
}
function formatLocalDay(day: string): string {
  return formatDay(day);
}
function formatSnapshotInstant(value: string, timezone: string): string {
  return formatDateTime(value, timezone);
}
function humanizeStatus(status: string): string {
  return humanize(status);
}
/** A ratio as people say it — "2 of 9 · 22%" — rounded half-up to a whole percent. */
function ratioSummary(numerator: string, denominator: string, noun = ''): string {
  const basisPoints = ratioBasisPoints(numerator, denominator);
  const exact = `${numerator} of ${denominator}${noun}`;
  if (basisPoints === null) return `${exact} · No cohort`;
  const value = BigInt(basisPoints);
  const rest = value % BASIS_POINTS_PER_PERCENT;
  const whole = value / BASIS_POINTS_PER_PERCENT + (rest + rest >= BASIS_POINTS_PER_PERCENT ? BigInt(1) : BigInt(0));
  return `${exact} · ${whole}%`;
}
/** Due amounts per currency, exact in BigInt, as display money ("₹21,800"). */
function dueTotals(rows: ReadonlyArray<{ currency: string; duePaise: string }>): string[] {
  const byCurrency = new Map<string, bigint>();
  rows.forEach((row) => byCurrency.set(row.currency, BigInt(row.duePaise) + (byCurrency.get(row.currency) ?? BigInt(0))));
  return Array.from(byCurrency, ([currency, paise]) => formatDisplayMoney(paise.toString(), currency));
}
function detailSummaries(metrics: OwnerMetrics, selected: CardKey): string[] {
  switch (selected) {
    case 'visits': return metrics.components.visits.map((row) => `${row.memberName} checked in ${formatSnapshotInstant(row.checkedInAt, metrics.timezone)}`);
    case 'liveMembers': return metrics.components.liveMembers.map((row) => `${row.memberName}: ${row.memberships.length} live memberships${row.paused ? ' · Currently paused' : ''}`);
    case 'pausedMembers': return metrics.components.liveMembers.filter((row) => row.paused).map((row) => `${row.memberName}: currently paused`);
    case 'cases':
    case 'followUpsDue': return metrics.components.cases.filter((row) => selected === 'cases' || row.due).map((row) => `${row.memberName}: ${humanizeStatus(row.status)} · ${row.due ? 'Follow-up due' : 'No follow-up due'}${row.nextFollowUpAt === null ? '' : ` · Next ${formatSnapshotInstant(row.nextFollowUpAt, metrics.timezone)}`}`);
    case 'recoveries': return metrics.components.recoveries.map((row) => `${row.memberName} returned ${formatSnapshotInstant(row.returnedAt, metrics.timezone)}`);
    case 'cash': return [...metrics.components.collected.map((row) => `${row.memberName}: collected ${formatMoney(row.currency, row.amountPaise)} · ${formatSnapshotInstant(row.paidAt, metrics.timezone)}`), ...metrics.components.returned.map((row) => `${row.memberName}: returned ${formatMoney(row.currency, row.amountPaise)} · ${formatSnapshotInstant(row.processedAt, metrics.timezone)}`)];
    case 'renewals': return metrics.components.renewals.map((row) => `${row.memberName}: ${formatMoney(row.currency, row.duePaise)} due by ${formatLocalDay(row.endsOn)}`);
    case 'leads': return metrics.components.leads.map((row) => `${row.fullName}: ${humanizeStatus(row.stage)} · ${row.converted ? 'Converted' : 'Not converted'} · ${formatSnapshotInstant(row.createdAt, metrics.timezone)}`);
    case 'addonCash': return [...metrics.components.collected.filter((row) => row.addonOrderId !== null).map((row) => `${row.memberName}: collected ${formatMoney(row.currency, row.amountPaise)} · ${formatSnapshotInstant(row.paidAt, metrics.timezone)}`), ...metrics.components.returned.filter((row) => row.addonOrderId !== null).map((row) => `${row.memberName}: returned ${formatMoney(row.currency, row.amountPaise)} · ${formatSnapshotInstant(row.processedAt, metrics.timezone)}`)];
    case 'ptOrders': return metrics.components.ptOrders.map((row) => `${row.memberName}: ${humanizeStatus(row.status)} · ${row.sessionsUsed} of ${row.sessionsTotal} sessions used`);
  }
}

export function MetricsDashboard({ metrics }: { metrics: OwnerMetrics }) {
  const [selected, setSelected] = useState<CardKey | null>(null);
  const primaryCards: Array<{ key: CardKey; label: string; value: string; scope: string }> = [
    { key: 'visits', label: 'Visits today', value: metrics.cards.visitsToday, scope: formatLocalDay(metrics.localToday) },
    // The numeral is the open-case count, so it agrees with the section's "N open" link; what is due now is the caption.
    { key: 'cases', label: 'Open follow-ups', value: metrics.cards.openCases, scope: `${metrics.cards.followUpsDue} due now` },
    { key: 'renewals', label: 'Renewals due', value: metrics.cards.renewal.length === 0 ? 'No renewals due' : metrics.cards.renewal.map((row) => formatMoney(row.currency, row.duePaise, true)).join(' · '), scope: formatDayRange(metrics.range.from, metrics.range.through) },
    { key: 'cash', label: 'Net collected', value: metrics.cards.cash.length === 0 ? 'No cash movement' : metrics.cards.cash.map((row) => formatMoney(row.currency, row.netPaise, true)).join(' · '), scope: formatDayRange(metrics.range.from, metrics.range.through) },
  ];
  const secondaryCards: Array<{ key: CardKey; label: string; value: string }> = [
    { key: 'liveMembers', label: 'Live members', value: metrics.cards.liveMembers },
    { key: 'pausedMembers', label: 'Paused members', value: metrics.cards.pausedMembers },
    { key: 'leads', label: 'Lead conversion', value: ratioSummary(metrics.cards.leads.converted, metrics.cards.leads.total) },
    { key: 'addonCash', label: 'Add-on cash', value: moneySummary(metrics.cards.addonCash) },
    { key: 'ptOrders', label: 'PT sessions used', value: ratioSummary(metrics.cards.pt.sessionsUsed, metrics.cards.pt.sessionsTotal, ' used') },
  ];
  const selectedRows = selected === null ? [] : detailSummaries(metrics, selected);
  const cases = metrics.components.cases.slice(0, OWNER_OVERVIEW_CASE_PREVIEW_LIMIT);
  const renewals = metrics.components.renewals.slice(0, OWNER_OVERVIEW_SUPPORTING_PREVIEW_LIMIT);
  const recoveries = metrics.components.recoveries.slice(0, OWNER_OVERVIEW_SUPPORTING_PREVIEW_LIMIT);
  const renewalsDue = metrics.components.renewals.length;
  // The list is a preview; its closing row reconciles it with the headline number, from this same snapshot.
  const shownDue = dueTotals(renewals);
  const allDue = dueTotals(metrics.cards.renewal);
  const renewalAmounts = shownDue.length === 1 && allDue.length === 1 ? ` · ${shownDue.join('')} of ${allDue.join('')}` : '';
  const warningCount = metrics.warnings.undatedPayments.length + metrics.warnings.undatedReturns.length
    + metrics.warnings.undatedPtOrders.length + metrics.warnings.incompletePtOrders.length;
  const chevron = <ChevronRight aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />;

  return <main className="dashboard-workspace">
    <header className="dashboard-header">
      <div>
        <h1>Overview</h1>
        <p className="dashboard-subtitle">Your gym at a glance<span className="money-dash-sep"> · </span><span className="money-dash-updated">updated {formatSnapshotInstant(metrics.asOf, metrics.timezone)}</span></p>
      </div>
      <div className="dashboard-controls">
        <details className="dashboard-period">
          <summary aria-label={`Period ${metrics.range.from} to ${metrics.range.through}`}>{formatDayRange(metrics.range.from, metrics.range.through)}</summary>
          <form className="dashboard-range" method="get">
            <label>From <input name="from" type="date" defaultValue={metrics.range.from} /></label>
            <label>Through <input name="through" type="date" defaultValue={metrics.range.through} /></label>
            <button type="submit">Apply range</button>
          </form>
        </details>
        <div className="dashboard-actions">
          <a className="dashboard-secondary-action" href="/console/check-in"><UserPlus aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />Check in a member</a>
          <a className="dashboard-primary-action" href="/console"><CreditCard aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />Record payment</a>
        </div>
      </div>
    </header>
    <section className="dashboard-primary-metrics" aria-label="Primary metrics">
      {primaryCards.map((card) => <button aria-pressed={selected === card.key} className="dashboard-primary-metric" data-currency-context={card.value.includes('₹') ? `INR ${card.value}` : undefined} key={card.key} onClick={() => setSelected(selected === card.key ? null : card.key)} type="button"><span>{card.label}</span><strong>{card.value}</strong><small>{card.scope}</small></button>)}
    </section>
    {selected !== null && <section aria-live="polite" className="dashboard-detail"><div className="dashboard-detail-head"><h2>{[...primaryCards, ...secondaryCards].find((card) => card.key === selected)?.label} details</h2><button type="button" className="cl-btn cl-btn--small cl-btn--quiet" onClick={() => setSelected(null)}>Close</button></div><p>Rows are from the same snapshot response; current-state cards remain current regardless of the selected date range.</p>{selectedRows.length === 0 ? <p>No component rows</p> : <ul className="cl-rows">{selectedRows.map((row) => <li key={row}>{row}</li>)}</ul>}</section>}
    <div className="dashboard-main-grid">
      <section className="dashboard-panel dashboard-cases" aria-labelledby="dashboard-cases-heading">
        <div className="dashboard-panel-heading"><div><h2 id="dashboard-cases-heading">People to follow up with</h2><p>Longest-open cases first.</p></div><a href="/red-list">{metrics.cards.openCases} open {chevron}</a></div>
        {cases.length === 0 ? <div className="cl-empty dashboard-empty"><strong>Nobody to chase</strong><p>No open follow-up cases in this snapshot.</p></div> : <>
          {/* The next step rides on the status line: as its own column it was mostly dashes. */}
          <ul className="dashboard-case-list">{cases.map((item) => <li key={item.caseId}><a href={`/members/${item.memberId}`}><div className="dashboard-case-who"><strong>{item.memberName}</strong><p><span className="cl-status" data-tone={item.due ? 'risk' : 'warn'}>{humanizeStatus(item.status)}</span>{' · '}{item.due ? <span className="money-dash-now">Contact now</span> : item.nextFollowUpAt === null ? <span className="dashboard-muted">Not scheduled</span> : `Next ${formatSnapshotInstant(item.nextFollowUpAt, metrics.timezone)}`}</p></div><ChevronRight className="dashboard-row-chevron" aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></a></li>)}</ul>
          {metrics.components.cases.length > cases.length ? <p className="money-dash-more">Showing {cases.length} of {metrics.cards.openCases} open</p> : null}
        </>}
      </section>
      <aside className="dashboard-supporting" aria-label="Renewal and recovery summary">
        <section className="dashboard-panel" aria-labelledby="dashboard-renewals-heading">
          <div className="dashboard-panel-heading"><div><h2 id="dashboard-renewals-heading">Renewals due</h2><p>{formatDayRange(metrics.range.from, metrics.range.through)}</p></div>{renewalsDue === 0 ? null : <a href="/memberships">{renewalsDue} due {chevron}</a>}</div>
          {renewals.length === 0 ? <div className="cl-empty dashboard-empty"><strong>No renewals due</strong><p>No renewals due in this range.</p></div> : <>
            <div className="dashboard-columns dashboard-renewal-columns" aria-hidden="true"><span>Member</span><span>Due</span><span>Amount</span></div>
            <ul className="dashboard-renewal-list">{renewals.map((item) => <li key={item.membershipId}><a href={`/memberships/${item.memberId}`}>{item.memberName}<small><span className="cl-status" data-tone={item.endsOn < metrics.localToday ? 'risk' : 'warn'}>{item.endsOn < metrics.localToday ? 'Overdue' : 'Due'}</span></small></a><time dateTime={item.endsOn}>{formatLocalDay(item.endsOn)}</time><span className="money-dash-amount">{formatDisplayMoney(item.duePaise, item.currency)}</span></li>)}</ul>
            {renewalsDue > renewals.length ? <p className="money-dash-more">Showing {renewals.length} of {renewalsDue}{renewalAmounts}</p> : null}
          </>}
        </section>
        <section className="dashboard-panel dashboard-recovery" aria-labelledby="dashboard-recovery-heading"><div className="dashboard-panel-heading"><div><h2 id="dashboard-recovery-heading">Back in the gym</h2><p>Recovered after a follow-up</p></div></div><p className="money-dash-recovered"><strong>{metrics.cards.recovered}</strong> members returned</p>{recoveries.length > 0 && <ul>{recoveries.map((item) => <li key={item.caseId}><a href={`/members/${item.memberId}`}>{item.memberName}</a> · {formatSnapshotInstant(item.returnedAt, metrics.timezone)}</li>)}</ul>}</section>
      </aside>
    </div>
    <section className="dashboard-secondary-metrics" aria-label="More snapshot details"><h2>More from this snapshot</h2><div>{secondaryCards.map((card) => <button aria-pressed={selected === card.key} key={card.key} onClick={() => setSelected(selected === card.key ? null : card.key)} type="button"><span>{card.label}</span><strong>{card.value}</strong></button>)}</div>
      {warningCount === 0 ? <p className="money-dash-complete">Every number above is complete for this range.</p> : null}
    </section>
    {/* Only when there is something to say: an all-clear does not need its own section. */}
    {warningCount === 0 ? null : <section className="dashboard-quality" aria-labelledby="data-quality-heading"><h2 id="data-quality-heading">Data quality</h2>
      {metrics.warnings.undatedPayments.map((row) => <p key={row.paymentId} id={`warning-payment-${row.paymentId}`}><a href={`#warning-payment-${row.paymentId}`}>All-date data quality: undated payment {row.amountPaise} {row.currency}</a></p>)}
      {metrics.warnings.undatedReturns.map((row) => <p key={row.refundId} id={`warning-return-${row.refundId}`}><a href={`#warning-return-${row.refundId}`}>All-date data quality: undated return {row.amountPaise} {row.currency}</a></p>)}
      {metrics.warnings.undatedPtOrders.map((row) => <p key={row.orderId} id={`warning-pt-${row.orderId}`}><a href={`#warning-pt-${row.orderId}`}>All-date data quality: undated PT order {row.orderId} · {row.status}</a></p>)}
      {metrics.warnings.incompletePtOrders.map((row) => <p key={row.orderId} id={`warning-incomplete-pt-${row.orderId}`}><a href={`#warning-incomplete-pt-${row.orderId}`}>All-date data quality: incomplete PT order {row.orderId} · {row.status} · excluded incomplete row</a></p>)}
    </section>}
  </main>;
}
