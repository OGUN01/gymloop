import { isValidElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { OwnerMetrics } from '@gymloop/shared';

const state = vi.hoisted(() => ({ hooks: [] as unknown[], cursor: 0 }));
vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  return { ...actual, useState: (initial: unknown) => {
    const index = state.cursor++;
    if (!(index in state.hooks)) state.hooks[index] = initial;
    return [state.hooks[index], (next: unknown) => { state.hooks[index] = next; }];
  } };
});

const richFixture: OwnerMetrics = {
  tenantId: 'gym-1', asOf: '2026-09-18T10:00:00+05:30', timezone: 'Asia/Kolkata', localToday: '2026-09-18',
  range: { from: '2026-09-01', through: '2026-09-18', startsAt: '2026-08-31T18:30:00+00:00', endsBefore: '2026-09-18T18:30:00+00:00', mode: 'explicit' },
  cards: {
    visitsToday: '7', liveMembers: '42', pausedMembers: '3', openCases: '5', followUpsDue: '2', recovered: '4',
    cash: [{ currency: 'INR', collectedPaise: '125000', returnedPaise: '5000', netPaise: '120000' }, { currency: 'USD', collectedPaise: '900', returnedPaise: '0', netPaise: '900' }],
    renewal: [{ currency: 'INR', duePaise: '250000', receipts: [] } as never], leads: { converted: '2', total: '8' },
    addonCash: [], pt: { sessionsUsed: '2', sessionsTotal: '5', orders: '1' },
  },
  components: {
    visits: [], liveMembers: [],
    cases: [{ caseId: 'case-1', memberId: 'member-1', memberName: 'Asha Rao', status: 'open', nextFollowUpAt: '2026-09-19T09:00:00+05:30', due: true }],
    recoveries: [{ caseId: 'case-2', memberId: 'member-2', memberName: 'Bharat Singh', returnedAt: '2026-09-17T11:00:00+05:30' }],
    collected: [], returned: [], renewals: [{ membershipId: 'membership-1', memberId: 'member-3', memberName: 'Chitra Das', currency: 'INR', endsOn: '2026-09-20', pricePaise: '300000', discountPaise: '0', netPricePaise: '300000', periodsGranted: '1', eligiblePaidPaise: '0', residualPaise: '0', duePaise: '250000', receipts: [] }], leads: [], ptOrders: [],
  },
  warnings: { undatedPayments: [], undatedReturns: [], undatedPtOrders: [], incompletePtOrders: [] },
};

const emptyFixture: OwnerMetrics = { ...richFixture, cards: { ...richFixture.cards, cash: [], renewal: [], recovered: '0' }, components: { ...richFixture.components, cases: [], renewals: [], recoveries: [] } };

function inspect(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(inspect).join(' ');
  if (!isValidElement<Record<string, unknown>>(node)) return typeof node === 'string' || typeof node === 'number' ? String(node) : '';
  if (typeof node.type === 'function') return inspect((node.type as (props: Record<string, unknown>) => ReactNode)(node.props));
  return inspect(node.props.children as ReactNode);
}
function elements(node: ReactNode): Array<Record<string, unknown>> {
  if (Array.isArray(node)) return node.flatMap(elements);
  if (!isValidElement<Record<string, unknown>>(node)) return [];
  if (typeof node.type === 'function') return elements((node.type as (props: Record<string, unknown>) => ReactNode)(node.props));
  return [node.props, ...elements(node.props.children as ReactNode)];
}

describe('Phase 7 owner overview surface', () => {
  beforeEach(() => { state.hooks = []; state.cursor = 0; });

  it('renders the approved hierarchy, truthful actions and exactly four primary facts', async () => {
    const { MetricsDashboard } = await import('../(console)/dashboard/metrics-dashboard');
    const html = renderToStaticMarkup(<MetricsDashboard metrics={richFixture} />);
    expect(html).toContain('Check in a member');
    expect(html).toContain('/console/check-in');
    expect(html).toContain('Record payment');
    expect(html).toContain('/console');
    expect(html).toContain('Visits today');
    expect(html).toContain('Open follow-ups');
    expect(html).toContain('Renewals due');
    expect(html).toContain('Net collected');
    expect(html).toContain('Asha Rao');
    expect(html).toContain('Chitra Das');
    expect(html).toContain('Bharat Singh');
    expect(html).toContain('INR');
    expect(html).toContain('USD');
    expect(html).not.toMatch(/last visit|weekly|recovery revenue/i);
  });

  it('keeps selected detail in the same response and exposes accessible state', async () => {
    const { MetricsDashboard } = await import('../(console)/dashboard/metrics-dashboard');
    const rendered = (MetricsDashboard as unknown as (props: Record<string, unknown>) => ReactNode)({ metrics: richFixture });
    const visit = elements(rendered).find((props) => typeof props.onClick === 'function' && /visits today/i.test(inspect(props.children as ReactNode)));
    expect(visit).toBeDefined();
    (visit!.onClick as () => void)();
    state.cursor = 0;
    const html = renderToStaticMarkup(<MetricsDashboard metrics={richFixture} />);
    expect(html).toMatch(/aria-label="(?:Metric cards|Primary metrics)/i);
    expect(html).toMatch(/aria-live="polite"/);
    expect(html).toMatch(/aria-pressed|aria-selected/);
    expect(html).toContain('Rows are from the same snapshot response');
  });

  it('states empty and error outcomes without fabricating zero-money or evidence', async () => {
    const { MetricsDashboard } = await import('../(console)/dashboard/metrics-dashboard');
    const html = renderToStaticMarkup(<MetricsDashboard metrics={emptyFixture} />);
    expect(html).toMatch(/no cash movement|no renewals due/i);
    expect(html).toMatch(/no renewals due|no cash movement/i);
    expect(html).not.toMatch(/last visit|this week|recovery revenue/i);
  });
});
