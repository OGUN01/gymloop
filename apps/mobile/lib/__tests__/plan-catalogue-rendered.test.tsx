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
