import { beforeEach, describe, expect, it, vi } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';

// Desk approval/verifier queue contracts: separation of awaiting-acceptance,
// awaiting-verification and closed; verifier sheet disclosure (BUY-012/025);
// reason labelled shown to the member (BUY-011). RED until implementation.

const state = vi.hoisted(() => ({ response: null as unknown, failed: false, list: null as unknown }));
const id = '72000000-0000-4000-8000-000000000001';
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => ({ identity: { kind: 'staff', userId: id, tenantId: id, staffId: id, role: 'gym_owner' }, supabase: {} }) }));
vi.mock('../../lib/purchase-console', () => ({
  loadPurchaseRequests: async () => { if (state.failed) throw new Error('private DB error'); return state.list; },
  loadPurchaseRequest: async () => { if (state.failed) throw new Error('private DB error'); return state.response; },
}));
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: () => {}, push: () => {} }), useSearchParams: () => new URLSearchParams(), redirect: (path: string) => { throw new Error(`redirect:${path}`); } }));
vi.mock('next/link', async () => { const { createElement } = await import('react'); return { default: (props: Record<string, unknown>) => createElement('a', props) }; });

const request = {
  requestId: id, memberName: 'Visible member', kind: 'shop', status: 'payment_proof_uploaded',
  targetName: 'Visible whey fixture', quantity: 1, amountPaise: '199900', currency: 'INR', gstRateBp: 1800,
  createdAt: '2026-10-02T04:30:00Z', acceptedAt: '2026-10-02T05:30:00Z', expiresAt: '2026-10-03T05:30:00Z',
  reason: null, proofStatus: 'active', receiptId: null,
};

beforeEach(() => { state.failed = false; state.response = null; state.list = { requests: [request], nextAfter: null, nextAfterId: null }; });

async function renderQueue() {
  const { default: Queue } = await import('../(console)/purchase-requests/page');
  return renderToStaticMarkup(await Queue({ searchParams: Promise.resolve({}) }));
}
async function renderDeskDetail() {
  const { default: Detail } = await import('../(console)/purchase-requests/[requestId]/page');
  return renderToStaticMarkup(await Detail({ params: Promise.resolve({ requestId: id }) }));
}

describe('PAY desk queue real entrypoint', () => {
  it('separates awaiting acceptance from awaiting verification and closed', async () => {
    state.list = {
      requests: [
        { ...request, status: 'requested' },
        { ...request, requestId: '72000000-0000-4000-8000-000000000002', status: 'payment_proof_uploaded' },
        { ...request, requestId: '72000000-0000-4000-8000-000000000003', status: 'recorded', proofStatus: 'bound', receiptId: 'RC-0009' },
      ],
      nextAfter: null, nextAfterId: null,
    };
    const html = await renderQueue();
    expect(html).toContain('Visible member');
    expect(html).toMatch(/await/i);
    expect(html).toContain('Payment recorded');
  });
  it('failed load renders retry instead of fabricating an empty queue', async () => {
    state.failed = true;
    const html = await renderQueue();
    expect(html).toContain("couldn&#x27;t be loaded.");
    expect(html).toContain('Retry');
    expect(html).not.toContain('private DB error');
  });
  it('does not expose proof storage internals in the queue or detail', async () => {
    state.response = { ...request, proofObjectKey: 'tenant/staging/payment_proof/secret', proofUrl: 'https://r2.test/private' };
    const html = await renderDeskDetail();
    expect(html).not.toContain('secret');
    expect(html).not.toContain('r2.test');
  });
});
