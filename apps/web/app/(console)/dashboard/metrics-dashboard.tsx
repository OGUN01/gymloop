'use client';

import {
  formatBasisPoints,
  OWNER_OVERVIEW_CASE_PREVIEW_LIMIT,
  OWNER_OVERVIEW_SUPPORTING_PREVIEW_LIMIT,
  ratioBasisPoints,
  rupeesFromPaise,
  type OwnerMetrics,
  UI_TOKENS,
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
    : rows.map((row) => formatMoney(row.currency, row.netPaise)).join(' · ');
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
  return new Intl.DateTimeFormat('en-IN', {
    day: 'numeric',
    month: 'long',
    timeZone: 'UTC',
    weekday: 'long',
  }).format(new Date(`${day}T00:00:00.000Z`));
}
function formatSnapshotInstant(value: string, timezone: string): string {
  return new Intl.DateTimeFormat('en-IN', {
    day: 'numeric',
    hour: '2-digit',
    hourCycle: 'h23',
    minute: '2-digit',
    month: 'long',
    timeZone: timezone,
    year: 'numeric',
  }).format(new Date(value));
}
function humanizeStatus(status: string): string {
  return humanize(status);
}
function ratioSummary(numerator: string, denominator: string): string {
  const basisPoints = ratioBasisPoints(numerator, denominator);
  const exact = `${numerator} / ${denominator}`;
  return basisPoints === null ? `${exact} · No cohort` : `${exact} · ${formatBasisPoints(basisPoints)}`;
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
    { key: 'followUpsDue', label: 'Open follow-ups', value: metrics.cards.followUpsDue, scope: 'Members to contact now' },
    { key: 'renewals', label: 'Renewals due', value: metrics.cards.renewal.length === 0 ? 'No renewals due' : metrics.cards.renewal.map((row) => formatMoney(row.currency, row.duePaise, true)).join(' · '), scope: formatDayRange(metrics.range.from, metrics.range.through) },
    { key: 'cash', label: 'Net collected', value: metrics.cards.cash.length === 0 ? 'No cash movement' : metrics.cards.cash.map((row) => formatMoney(row.currency, row.netPaise, true)).join(' · '), scope: formatDayRange(metrics.range.from, metrics.range.through) },
  ];
  const secondaryCards: Array<{ key: CardKey; label: string; value: string }> = [
    { key: 'liveMembers', label: 'Live members', value: metrics.cards.liveMembers },
    { key: 'pausedMembers', label: 'Paused members', value: metrics.cards.pausedMembers },
    { key: 'cases', label: 'Open cases', value: metrics.cards.openCases },
    { key: 'recoveries', label: 'Recovered', value: metrics.cards.recovered },
    { key: 'leads', label: 'Lead conversion', value: ratioSummary(metrics.cards.leads.converted, metrics.cards.leads.total) },
    { key: 'addonCash', label: 'Add-on cash', value: moneySummary(metrics.cards.addonCash) },
    { key: 'ptOrders', label: 'PT usage · known-session cohort', value: ratioSummary(metrics.cards.pt.sessionsUsed, metrics.cards.pt.sessionsTotal) },
  ];
  const selectedRows = selected === null ? [] : detailSummaries(metrics, selected);
  const cases = metrics.components.cases.slice(0, OWNER_OVERVIEW_CASE_PREVIEW_LIMIT);
  const renewals = metrics.components.renewals.slice(0, OWNER_OVERVIEW_SUPPORTING_PREVIEW_LIMIT);
  const recoveries = metrics.components.recoveries.slice(0, OWNER_OVERVIEW_SUPPORTING_PREVIEW_LIMIT);

  return <main className="dashboard-workspace">
    <header className="dashboard-header">
      <div>
        <p className="cl-eyebrow dashboard-kicker">{formatLocalDay(metrics.localToday)}</p>
        <h1>Overview</h1>
        <p className="dashboard-subtitle">Your gym at a glance · updated {formatSnapshotInstant(metrics.asOf, metrics.timezone)}</p>
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
        <div className="dashboard-panel-heading"><div><h2 id="dashboard-cases-heading">People to follow up</h2><p>Current cases from this snapshot.</p></div><a href="/red-list">View all <ChevronRight aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></a></div>
        {cases.length === 0 ? <div className="cl-empty dashboard-empty"><strong>Nobody to chase</strong><p>No open follow-up cases in this snapshot.</p></div> : <ul className="dashboard-case-list">{cases.map((item) => <li key={item.caseId}><a href={`/members/${item.memberId}`}><strong>{item.memberName}</strong><span className="cl-status" data-tone={item.due ? 'risk' : 'warn'}>{humanizeStatus(item.status)}</span></a><p>{item.due ? 'Follow-up due' : 'No follow-up due'}{item.nextFollowUpAt === null ? ' · No next follow-up scheduled' : ` · Next ${formatSnapshotInstant(item.nextFollowUpAt, metrics.timezone)}`}</p></li>)}</ul>}
      </section>
      <aside className="dashboard-supporting" aria-label="Renewal and recovery summary">
        <section className="dashboard-panel" aria-labelledby="dashboard-renewals-heading"><div className="dashboard-panel-heading"><div><h2 id="dashboard-renewals-heading">Renewals due</h2><p>{formatDayRange(metrics.range.from, metrics.range.through)}</p></div></div>{renewals.length === 0 ? <div className="cl-empty dashboard-empty"><strong>No renewals due</strong><p>No renewals due in this range.</p></div> : <ul className="dashboard-renewal-list">{renewals.map((item) => <li key={item.membershipId}><a href={`/memberships/${item.memberId}`}>{item.memberName}<small>Due by {formatLocalDay(item.endsOn)}</small></a><span>{formatDisplayMoney(item.duePaise, item.currency)}</span></li>)}</ul>}</section>
        <section className="dashboard-panel dashboard-recovery" aria-labelledby="dashboard-recovery-heading"><h2 id="dashboard-recovery-heading">Back in the gym</h2><p><strong>{metrics.cards.recovered}</strong> members returned</p>{recoveries.length > 0 && <ul>{recoveries.map((item) => <li key={item.caseId}><a href={`/members/${item.memberId}`}>{item.memberName}</a> · {formatSnapshotInstant(item.returnedAt, metrics.timezone)}</li>)}</ul>}</section>
      </aside>
    </div>
    <section className="dashboard-secondary-metrics" aria-label="More snapshot details"><h2>More from this snapshot</h2><div>{secondaryCards.map((card) => <button aria-pressed={selected === card.key} key={card.key} onClick={() => setSelected(selected === card.key ? null : card.key)} type="button"><span>{card.label}</span><strong>{card.value}</strong></button>)}</div></section>
    <section className="dashboard-quality" aria-labelledby="data-quality-heading"><h2 id="data-quality-heading">Data quality</h2>
      {metrics.warnings.undatedPayments.map((row) => <p key={row.paymentId} id={`warning-payment-${row.paymentId}`}><a href={`#warning-payment-${row.paymentId}`}>All-date data quality: undated payment {row.amountPaise} {row.currency}</a></p>)}
      {metrics.warnings.undatedReturns.map((row) => <p key={row.refundId} id={`warning-return-${row.refundId}`}><a href={`#warning-return-${row.refundId}`}>All-date data quality: undated return {row.amountPaise} {row.currency}</a></p>)}
      {metrics.warnings.undatedPtOrders.map((row) => <p key={row.orderId} id={`warning-pt-${row.orderId}`}><a href={`#warning-pt-${row.orderId}`}>All-date data quality: undated PT order {row.orderId} · {row.status}</a></p>)}
      {metrics.warnings.incompletePtOrders.map((row) => <p key={row.orderId} id={`warning-incomplete-pt-${row.orderId}`}><a href={`#warning-incomplete-pt-${row.orderId}`}>All-date data quality: incomplete PT order {row.orderId} · {row.status} · excluded incomplete row</a></p>)}
      {metrics.warnings.undatedPayments.length === 0 && metrics.warnings.undatedReturns.length === 0 && metrics.warnings.undatedPtOrders.length === 0 && metrics.warnings.incompletePtOrders.length === 0 && <p><span className="cl-status" data-tone="ok">No data-quality warnings in this snapshot.</span></p>}
    </section>
  </main>;
}
