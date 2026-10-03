import { beforeEach, describe, expect, it, vi } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';

// Member Buy tab rendering contracts. The page module does not exist yet — the
// failing import is the expected RED. State grid per BUY-025; copy honesty per
// BUY-022; private-evidence hygiene per BUY-009.

const state = vi.hoisted(() => ({ response: null as unknown, failed: false, list: null as unknown }));
const id = '72000000-0000-4000-8000-000000000001';
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => ({ identity: { kind: 'member', userId: id, tenantId: id, memberId: id }, supabase: {} }) }));
vi.mock('../../lib/purchase', () => ({
  loadMemberPurchaseRequests: async () => { if (state.failed) throw new Error('private DB error'); return state.list; },
  loadMemberPurchaseRequest: async () => { if (state.failed) throw new Error('private DB error'); return state.response; },
}));
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: () => {}, push: () => {} }), useSearchParams: () => new URLSearchParams(), redirect: (path: string) => { throw new Error(`redirect:${path}`); } }));
vi.mock('next/link', async () => { const { createElement } = await import('react'); return { default: (props: Record<string, unknown>) => createElement('a', props) }; });

const base = {
  requestId: id, kind: 'shop', status: 'payment_proof_uploaded', targetName: 'Visible whey fixture',
  quantity: 1, amountPaise: '199900', currency: 'INR', gstRateBp: 1800,
  createdAt: '2026-10-02T04:30:00Z', acceptedAt: '2026-10-02T05:30:00Z', expiresAt: '2026-10-03T05:30:00Z',
  replayed: false, reason: null, proofStatus: 'active', receiptId: null, quotationPaise: '199900',
};

beforeEach(() => { state.failed = false; state.response = null; state.list = { requests: [base], nextAfter: null, nextAfterId: null }; });

async function renderPage() {
  const { default: Page } = await import('../member/buy/page');
  return renderToStaticMarkup(await Page({ searchParams: Promise.resolve({}) }));
}
async function renderDetail() {
  const { default: Detail } = await import('../member/buy/[requestId]/page');
  return renderToStaticMarkup(await Detail({ params: Promise.resolve({ requestId: id }) }));
}

describe('PAY member Buy list and detail real entrypoint', () => {
  it('detail shows the ruled requested/accepted/pending-verification/recorded sequence honestly', async () => {
    const html = await renderDetail();
    for (const word of ['Requested', 'Accepted', 'Pending verification', 'Payment recorded']) expect(html).toContain(word);
    expect(html).toContain('Visible whey fixture');
    expect(html).toMatch(/1,999|1999/);
  });
  it('never claims paid, bank verified or automatic settlement before ledger truth', async () => {
    const html = await renderDetail();
    expect(html).not.toMatch(/payment successful/i);
    expect(html).not.toMatch(/bank verified/i);
  });
  it('recorded state links the genuine receipt number only after ledger truth', async () => {
    state.list = { requests: [{ ...base, status: 'recorded', proofStatus: 'bound', receiptId: 'RC-0007' }], nextAfter: null, nextAfterId: null };
    state.response = { ...base, status: 'recorded', proofStatus: 'bound', receiptId: 'RC-0007', resulting: { endDate: '2026-11-02T00:00:00Z' } };
    const html = await renderDetail();
    expect(html).toContain('Payment recorded');
    expect(html).toContain('RC-0007');
  });
  it('rejected request surfaces the exact desk reason shown to the member', async () => {
    state.list = { requests: [{ ...base, status: 'rejected', reason: 'Stock reserved for another member' }], nextAfter: null, nextAfterId: null };
    const html = await renderPage();
    expect(html).toContain('Stock reserved for another member');
  });
  it('expired request shows Expired with the next action, not a pending montage', async () => {
    state.list = { requests: [{ ...base, status: 'expired' }], nextAfter: null, nextAfterId: null };
    const html = await renderPage();
    expect(html).toContain('Expired');
  });
  it('mismatch_recorded shows quoted, received, difference and the desk-resolution copy', async () => {
    state.response = { ...base, status: 'mismatch_recorded', proofStatus: 'bound', receivedPaise: '149900', differencePaise: '50000', saleResolved: false };
    const html = await renderDetail();
    expect(html).toMatch(/1,499|1499/);
    expect(html).toMatch(/500|50,000/);
    expect(html).toMatch(/desk/i);
    expect(html).not.toMatch(/payment successful/i);
  });
  it('failed load renders retry instead of an empty or happy fallback', async () => {
    state.failed = true;
    const html = await renderPage();
    expect(html).toContain("couldn&#x27;t be loaded.");
    expect(html).toContain('Retry');
    expect(html).not.toContain('private DB error');
  });
  it('does not expose storage internals: keys, ETags or private URLs', async () => {
    state.response = { ...base, stagingKey: 'secret-staging-key', publishedEtag: 'etag-secret', proofUrl: 'https://r2.test/private' };
    const html = await renderDetail();
    expect(html).not.toContain('secret-staging-key');
    expect(html).not.toContain('etag-secret');
    expect(html).not.toContain('r2.test');
  });
});
