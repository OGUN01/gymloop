'use client';

import {
  formatBasisPoints,
  ratioBasisPoints,
  rupeesFromPaise,
  type OwnerMetrics,
} from '@gymloop/shared';
import { useState } from 'react';

type CardKey =
  | 'visits'
  | 'liveMembers'
  | 'pausedMembers'
  | 'cases'
  | 'followUpsDue'
  | 'recoveries'
  | 'cash'
  | 'renewals'
  | 'leads'
  | 'addonCash'
  | 'ptOrders';

type DisplayRow = Record<string, unknown>;

function moneySummary(rows: OwnerMetrics['cards']['cash']): string {
  if (rows.length === 0) return 'No cash movement';
  return rows.map((row) => `${row.currency} ${rupeesFromPaise(row.netPaise)}`).join(' · ');
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
    case 'cash': return [
      ...metrics.components.collected.map((row) => ({ movement: 'collected', ...row })),
      ...metrics.components.returned.map((row) => ({ movement: 'returned', ...row })),
    ];
    case 'renewals': return metrics.components.renewals;
    case 'leads': return metrics.components.leads;
    case 'addonCash': return [
      ...metrics.components.collected
        .filter((row) => row.addonOrderId !== null)
        .map((row) => ({ movement: 'collected', ...row })),
      ...metrics.components.returned
        .filter((row) => row.addonOrderId !== null)
        .map((row) => ({ movement: 'returned', ...row })),
    ];
    case 'ptOrders': return metrics.components.ptOrders;
  }
}

function flattenText(value: unknown): string[] {
  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
    return [String(value)];
  }
  if (Array.isArray(value)) return value.flatMap(flattenText);
  if (value !== null && typeof value === 'object') return Object.values(value).flatMap(flattenText);
  return [];
}

export function MetricsDashboard({ metrics }: { metrics: OwnerMetrics }) {
  const [selected, setSelected] = useState<CardKey | null>(null);
  const cards: Array<{ key: CardKey; label: string; value: string }> = [
    { key: 'visits', label: 'Visits today · current state', value: metrics.cards.visitsToday },
    { key: 'liveMembers', label: 'Live members · current state', value: metrics.cards.liveMembers },
    { key: 'pausedMembers', label: 'Paused members · current state', value: metrics.cards.pausedMembers },
    { key: 'cases', label: 'Open cases · current state', value: metrics.cards.openCases },
    { key: 'followUpsDue', label: 'Follow-ups due · current state', value: metrics.cards.followUpsDue },
    { key: 'recoveries', label: 'Recovered', value: metrics.cards.recovered },
    { key: 'cash', label: 'Cash', value: moneySummary(metrics.cards.cash) },
    {
      key: 'renewals',
      label: 'Renewal due',
      value: metrics.cards.renewal.length === 0
        ? 'No renewals due'
        : metrics.cards.renewal
          .map((row) => `${row.currency} ${rupeesFromPaise(row.duePaise)}`)
          .join(' · '),
    },
    {
      key: 'leads',
      label: 'Lead conversion',
      value: ratioSummary(metrics.cards.leads.converted, metrics.cards.leads.total),
    },
    { key: 'addonCash', label: 'Add-on cash', value: moneySummary(metrics.cards.addonCash) },
    {
      key: 'ptOrders',
      label: 'PT usage · known-session cohort',
      value: ratioSummary(metrics.cards.pt.sessionsUsed, metrics.cards.pt.sessionsTotal),
    },
  ];
  const selectedRows = selected === null ? [] : componentRows(metrics, selected);

  return (
    <main>
      <h1>Metrics</h1>
      <p>Snapshot {metrics.asOf} · {metrics.timezone}</p>
      <form method="get">
        <label>From <input name="from" type="date" defaultValue={metrics.range.from} /></label>
        <label>Through <input name="through" type="date" defaultValue={metrics.range.through} /></label>
        <button type="submit">Apply range</button>
      </form>

      <section aria-label="Metric cards">
        {cards.map((card) => (
          <button key={card.key} type="button" onClick={() => setSelected(card.key)}>
            <strong>{card.label}</strong> {card.value}
          </button>
        ))}
      </section>

      <section aria-labelledby="data-quality-heading">
        <h2 id="data-quality-heading">Data quality</h2>
        {metrics.warnings.undatedPayments.map((row) => (
          <p key={row.paymentId} id={`warning-payment-${row.paymentId}`}>
            <a href={`#warning-payment-${row.paymentId}`}>All-date data quality: undated payment {row.amountPaise} {row.currency}</a>
          </p>
        ))}
        {metrics.warnings.undatedReturns.map((row) => (
          <p key={row.refundId} id={`warning-return-${row.refundId}`}>
            <a href={`#warning-return-${row.refundId}`}>All-date data quality: undated return {row.amountPaise} {row.currency}</a>
          </p>
        ))}
        {metrics.warnings.undatedPtOrders.map((row) => (
          <p key={row.orderId} id={`warning-pt-${row.orderId}`}>
            <a href={`#warning-pt-${row.orderId}`}>All-date data quality: undated PT order {row.orderId} · {row.status}</a>
          </p>
        ))}
        {metrics.warnings.incompletePtOrders.map((row) => (
          <p key={row.orderId} id={`warning-incomplete-pt-${row.orderId}`}>
            <a href={`#warning-incomplete-pt-${row.orderId}`}>All-date data quality: incomplete PT order {row.orderId} · {row.status} · excluded incomplete row</a>
          </p>
        ))}
      </section>

      {selected !== null && (
        <section aria-live="polite">
          <h2>{cards.find((card) => card.key === selected)?.label} details</h2>
          <p>Rows are from the same snapshot response; current-state cards remain current regardless of the selected date range.</p>
          {selectedRows.length === 0 ? <p>No component rows</p> : selectedRows.map((row) => (
            <p key={JSON.stringify(row)}>{flattenText(row).join(' · ')}</p>
          ))}
        </section>
      )}
    </main>
  );
}
