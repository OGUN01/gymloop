'use client';

import {
  formatBasisPoints,
  ratioBasisPoints,
  rupeesFromPaise,
  type OwnerMetrics,
} from '@gymloop/shared';
import { useState } from 'react';

type CardKey =
  | 'visits' | 'liveMembers' | 'pausedMembers' | 'cases' | 'followUpsDue'
  | 'recoveries' | 'cash' | 'renewals' | 'leads' | 'addonCash' | 'ptOrders';
type DisplayRow = Record<string, unknown>;

function moneySummary(rows: OwnerMetrics['cards']['cash']): string {
  return rows.length === 0
    ? 'No cash movement'
    : rows.map((row) => `${row.currency} ${rupeesFromPaise(row.netPaise)}`).join(' · ');
}
function renewalSummary(rows: OwnerMetrics['cards']['renewal']): string {
  return rows.length === 0
    ? 'No renewals due'
    : rows.map((row) => `${row.currency} ${rupeesFromPaise(row.duePaise)}`).join(' · ');
}
function ratioSummary(numerator: string, denominator: string): string {
  const basisPoints = ratioBasisPoints(numerator, denominator);
  const exact = `${numerator} / ${denominator}`;
  return basisPoints === null ? `${exact} · No cohort` : `${exact} · ${formatBasisPoints(basisPoints)}`;
}
function componentRows(metrics: OwnerMetrics, selected: CardKey): DisplayRow[] {
  switch (selected) {
    case 'visits': return metrics.components.visits;
    case 'liveMembers': return metrics.components.liveMembers;
    case 'pausedMembers': return metrics.components.liveMembers.filter((row) => row.paused);
    case 'cases': return metrics.components.cases;
    case 'followUpsDue': return metrics.components.cases.filter((row) => row.due);
    case 'recoveries': return metrics.components.recoveries;
    case 'cash': return [...metrics.components.collected.map((row) => ({ movement: 'collected', ...row })), ...metrics.components.returned.map((row) => ({ movement: 'returned', ...row }))];
    case 'renewals': return metrics.components.renewals;
    case 'leads': return metrics.components.leads;
    case 'addonCash': return [...metrics.components.collected.filter((row) => row.addonOrderId !== null).map((row) => ({ movement: 'collected', ...row })), ...metrics.components.returned.filter((row) => row.addonOrderId !== null).map((row) => ({ movement: 'returned', ...row }))];
    case 'ptOrders': return metrics.components.ptOrders;
  }
}
function flattenText(value: unknown): string[] {
  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') return [String(value)];
  if (Array.isArray(value)) return value.flatMap(flattenText);
  if (value !== null && typeof value === 'object') return Object.values(value).flatMap(flattenText);
  return [];
}

export function MetricsDashboard({ metrics }: { metrics: OwnerMetrics }) {
  const [selected, setSelected] = useState<CardKey | null>(null);
  const primaryCards: Array<{ key: CardKey; label: string; value: string; scope: string }> = [
    { key: 'visits', label: 'Visits today', value: metrics.cards.visitsToday, scope: `Current state · ${metrics.localToday}` },
    { key: 'followUpsDue', label: 'Open follow-ups', value: metrics.cards.followUpsDue, scope: 'Current state' },
    { key: 'renewals', label: 'Renewals due', value: renewalSummary(metrics.cards.renewal), scope: `${metrics.range.from} to ${metrics.range.through}` },
    { key: 'cash', label: 'Net collected', value: moneySummary(metrics.cards.cash), scope: `${metrics.range.from} to ${metrics.range.through}` },
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
  const selectedRows = selected === null ? [] : componentRows(metrics, selected);
  const displayLimits = { cases: 6, supportingRows: 3 };
  const cases = metrics.components.cases.slice(0, displayLimits.cases);
  const renewals = metrics.components.renewals.slice(0, displayLimits.supportingRows);
  const recoveries = metrics.components.recoveries.slice(0, displayLimits.supportingRows);

  return <main className="dashboard-workspace">
    <header className="dashboard-header">
      <div>
        <p className="dashboard-kicker">{metrics.localToday} · {metrics.timezone}</p>
        <h1>A good day starts here.</h1>
        <p className="dashboard-subtitle">Snapshot {metrics.asOf} · selected range {metrics.range.from} to {metrics.range.through}</p>
      </div>
      <div className="dashboard-actions">
        <a className="dashboard-primary-action" href="/console/check-in">Check in a member</a>
        <a className="dashboard-secondary-action" href="/console">Record payment</a>
      </div>
    </header>
    <form className="dashboard-range" method="get">
      <label>From <input name="from" type="date" defaultValue={metrics.range.from} /></label>
      <label>Through <input name="through" type="date" defaultValue={metrics.range.through} /></label>
      <button type="submit">Apply range</button>
    </form>
    <section className="dashboard-primary-metrics" aria-label="Primary metrics">
      {primaryCards.map((card) => <button aria-pressed={selected === card.key} className="dashboard-primary-metric" key={card.key} onClick={() => setSelected(card.key)} type="button"><span>{card.label}</span><strong>{card.value}</strong><small>{card.scope}</small></button>)}
    </section>
    <div className="dashboard-main-grid">
      <section className="dashboard-panel dashboard-cases" aria-labelledby="dashboard-cases-heading">
        <div className="dashboard-panel-heading"><div><h2 id="dashboard-cases-heading">People to follow up</h2><p>Current cases from this snapshot.</p></div><a href="/red-list">View all</a></div>
        {cases.length === 0 ? <p className="dashboard-empty">No open follow-up cases in this snapshot.</p> : <ul className="dashboard-case-list">{cases.map((item) => <li key={item.caseId}><a href={`/memberships/${item.memberId}`}><strong>{item.memberName}</strong><span>{item.status}</span></a><p>{item.due ? 'Follow-up due' : 'No follow-up due'}{item.nextFollowUpAt === null ? ' · No next follow-up scheduled' : ` · Next ${item.nextFollowUpAt}`}</p></li>)}</ul>}
      </section>
      <aside className="dashboard-supporting" aria-label="Renewal and recovery summary">
        <section className="dashboard-panel" aria-labelledby="dashboard-renewals-heading"><div className="dashboard-panel-heading"><div><h2 id="dashboard-renewals-heading">Renewals due</h2><p>{metrics.range.from} to {metrics.range.through}</p></div></div>{renewals.length === 0 ? <p className="dashboard-empty">No renewals due in this range.</p> : <ul className="dashboard-renewal-list">{renewals.map((item) => <li key={item.membershipId}><a href={`/memberships/${item.memberId}`}>{item.memberName}</a><span>{item.currency} {rupeesFromPaise(item.duePaise)}</span></li>)}</ul>}</section>
        <section className="dashboard-panel dashboard-recovery" aria-labelledby="dashboard-recovery-heading"><h2 id="dashboard-recovery-heading">Back in the gym</h2><p><strong>{metrics.cards.recovered}</strong> members returned</p>{recoveries.length > 0 && <ul>{recoveries.map((item) => <li key={item.caseId}><a href={`/memberships/${item.memberId}`}>{item.memberName}</a> · {item.returnedAt}</li>)}</ul>}</section>
      </aside>
    </div>
    <section className="dashboard-secondary-metrics" aria-label="More snapshot details"><h2>More snapshot details</h2><div>{secondaryCards.map((card) => <button aria-pressed={selected === card.key} key={card.key} onClick={() => setSelected(card.key)} type="button"><span>{card.label}</span><strong>{card.value}</strong></button>)}</div></section>
    <section className="dashboard-quality" aria-labelledby="data-quality-heading"><h2 id="data-quality-heading">Data quality</h2>
      {metrics.warnings.undatedPayments.map((row) => <p key={row.paymentId} id={`warning-payment-${row.paymentId}`}><a href={`#warning-payment-${row.paymentId}`}>All-date data quality: undated payment {row.amountPaise} {row.currency}</a></p>)}
      {metrics.warnings.undatedReturns.map((row) => <p key={row.refundId} id={`warning-return-${row.refundId}`}><a href={`#warning-return-${row.refundId}`}>All-date data quality: undated return {row.amountPaise} {row.currency}</a></p>)}
      {metrics.warnings.undatedPtOrders.map((row) => <p key={row.orderId} id={`warning-pt-${row.orderId}`}><a href={`#warning-pt-${row.orderId}`}>All-date data quality: undated PT order {row.orderId} · {row.status}</a></p>)}
      {metrics.warnings.incompletePtOrders.map((row) => <p key={row.orderId} id={`warning-incomplete-pt-${row.orderId}`}><a href={`#warning-incomplete-pt-${row.orderId}`}>All-date data quality: incomplete PT order {row.orderId} · {row.status} · excluded incomplete row</a></p>)}
      {metrics.warnings.undatedPayments.length === 0 && metrics.warnings.undatedReturns.length === 0 && metrics.warnings.undatedPtOrders.length === 0 && metrics.warnings.incompletePtOrders.length === 0 && <p>No data-quality warnings in this snapshot.</p>}
    </section>
    {selected !== null && <section aria-live="polite" className="dashboard-detail"><h2>{[...primaryCards, ...secondaryCards].find((card) => card.key === selected)?.label} details</h2><p>Rows are from the same snapshot response; current-state cards remain current regardless of the selected date range.</p>{selectedRows.length === 0 ? <p>No component rows</p> : selectedRows.map((row) => <p key={JSON.stringify(row)}>{flattenText(row).join(' · ')}</p>)}</section>}
  </main>;
}
