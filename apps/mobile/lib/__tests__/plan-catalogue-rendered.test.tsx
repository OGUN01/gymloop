import { createElement, isValidElement, type ReactNode } from 'react';
import { businessNouns, planCatalogueCopy, UI_TOKENS, type PlanCatalogueView } from '@gymloop/shared';
import { describe, expect, it, vi } from 'vitest';
const host = (name: string) => (props: unknown) => {
  const fields = props && typeof props === 'object' ? props as Record<string, unknown> : { children: props };
  return createElement(name, fields, fields.children as ReactNode);
};
vi.mock('react-native', () => ({ View: host('view'), Text: host('text'), ActivityIndicator: host('loading'), StyleSheet: { create: (value: unknown) => value, hairlineWidth: 1 } }));
vi.mock('../mobile-context', () => ({ useMobile: () => ({ palette: UI_TOKENS.colors.light, nouns: businessNouns('gym') }) }));
vi.mock('../../components/ui', () => new Proxy({}, {
  get: (_target, name) => name === 'then' ? undefined : name === 'FONT' ? new Proxy({}, { get: () => 'test-font' }) : host(String(name)),
  has: () => true,
}));
const { PlanCatalogueBody } = await import('../../components/plan-catalogue');
function text(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(text).join(' ');
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (!isValidElement<Record<string, unknown>>(node)) return '';
  if (typeof node.type === 'function') return text((node.type as (props: unknown) => ReactNode)(node.props));
  return text(node.props.children as ReactNode);
}
describe('PLC-009 rendered native agreed-price row', () => {
  it('PLC-Q1/Q5 keeps the held offered row and accessible group in name-price-length-badge order', () => {
    const view: PlanCatalogueView = { plans: [{ id: 'p1', name: 'Ordered held offer', description: null, durationDays: 30, pricePaise: '150000', currency: 'INR', gstRateBp: 0, held: true }], truncated: false, heldUnavailable: false, held: null };
    const tree = createElement(PlanCatalogueBody, { state: { phase: 'ready', view, loadedAt: null, staleReason: null, offline: false }, copy: planCatalogueCopy(businessNouns('gym')), timeZone: 'Asia/Kolkata', onRetry: () => undefined });
    const labels: string[] = [];
    const groups: string[] = [];
    const visit = (node: ReactNode): void => {
      if (Array.isArray(node)) { node.forEach(visit); return; }
      if (!isValidElement<Record<string, unknown>>(node)) return;
      if (typeof node.type === 'function') { visit((node.type as (props: unknown) => ReactNode)(node.props)); return; }
      if (typeof node.props.accessibilityLabel === 'string' && node.props.accessibilityLabel.startsWith('Ordered held offer,')) {
        labels.push(node.props.accessibilityLabel); groups.push(text(node));
      }
      visit(node.props.children as ReactNode);
    };
    visit(tree);
    expect(labels).toEqual(['Ordered held offer, ₹1,500 for 30 days, Your plan']);
    expect(groups).toHaveLength(1);
    expect(groups[0]?.replace(/\s+/g, ' ').trim()).toMatch(/Ordered held offer\s+₹1,500\s+for 30 days\s+Your plan/);
  });
  it('keeps the exact positive discount fact when agreed arithmetic is unsafe', () => {
    const view: PlanCatalogueView = { plans: [], truncated: false, heldUnavailable: false, held: {
      planId: 'p1', planName: null, status: 'active', past: false, endsOn: null, current: null, change: 'not_on_offer',
      recorded: { listPricePaise: '9007199254740993', discountPaise: '1', agreedPricePaise: null, currency: 'INR', durationDays: 30 },
    } };
    const rendered = text(createElement(PlanCatalogueBody, { state: { phase: 'ready', view, loadedAt: null, staleReason: null, offline: false }, copy: planCatalogueCopy(businessNouns('gym')), timeZone: 'Asia/Kolkata', onRetry: () => undefined }));
    expect(rendered).toContain('Price when sold'); expect(rendered).toContain('₹9,00,71,99,25,47,409.93');
    expect(rendered).toMatch(/Discount\s+₹0\.01/); expect(rendered).not.toContain('Agreed price');
  });
  it.each([
    ['positive', '10000', '110000', true], ['zero', '0', '120000', false],
    ['null result', '10000', null, false], ['invalid discount', 'invalid', null, false],
    ['negative discount', '-1', null, false], ['noncanonical discount', '01', null, false],
  ] as const)('%s discount obeys both row preconditions', (_label, discount, agreed, shown) => {
    const view: PlanCatalogueView = { plans: [], truncated: false, heldUnavailable: false, held: {
      planId: 'p1', planName: null, status: 'active', past: false, endsOn: null, current: null, change: 'not_on_offer',
      recorded: { listPricePaise: '120000', discountPaise: discount, agreedPricePaise: agreed, currency: 'INR', durationDays: 30 },
    } };
    const rendered = text(createElement(PlanCatalogueBody, { state: { phase: 'ready', view, loadedAt: null, staleReason: null, offline: false }, copy: planCatalogueCopy(businessNouns('gym')), timeZone: 'Asia/Kolkata', onRetry: () => undefined }));
    expect(rendered).toContain('Price when sold');
    if (shown) { expect(rendered).toContain('Agreed price'); expect(rendered).toContain('₹1,100'); }
    else expect(rendered).not.toContain('Agreed price');
  });
});
