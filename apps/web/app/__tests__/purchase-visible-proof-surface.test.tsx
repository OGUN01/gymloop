import { beforeEach, describe, expect, it, vi } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';

// Member proof upload surface contracts on the Buy detail (BUY-008/011/022).
// Static rendering contracts; interactive upload transport is covered at the
// helper/route layer. Authored implementation-blind.

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
  requestId: id, kind: 'shop', status: 'owner_accepted', targetName: 'Proof whey fixture',
  quantity: 1, amountPaise: '199900', currency: 'INR', gstRateBp: 1800,
  createdAt: '2026-10-02T04:30:00Z', acceptedAt: '2026-10-02T05:30:00Z', expiresAt: '2026-10-03T05:30:00Z',
  replayed: false, reason: null, proofStatus: 'active', receiptId: null, quotationPaise: '199900',
};

beforeEach(() => { state.failed = false; state.response = null; state.list = { requests: [base], nextAfter: null, nextAfterId: null }; });

async function renderDetail() {
  const { default: Detail } = await import('../member/buy/[requestId]/page');
  return renderToStaticMarkup(await Detail({ params: Promise.resolve({ requestId: id }) }));
}

describe('member proof upload affordance and copy truth', () => {
  it('an accepted request offers the proof upload with the honest pending-verification label', async () => {
    const html = await renderDetail();
    expect(html).toContain('Upload payment screenshot');
    expect(html).toContain('Pending verification');
    expect(html).not.toMatch(/payment successful/i);
    expect(html).not.toMatch(/bank verified/i);
  });
  it('the upload affordance names the accepted image types and size cap before upload', async () => {
    const html = await renderDetail();
    expect(html).toMatch(/JPG|JPEG|PNG|WebP/i);
    expect(html).toMatch(/2\s*MB|2\s*MiB/i);
  });
  it('a rejected proof surfaces the exact desk reason and a re-upload action, never paid copy', async () => {
    state.list = { requests: [{ ...base, status: 'owner_accepted', proofStatus: 'rejected', reason: 'Picture unclear, re-upload' }], nextAfter: null, nextAfterId: null };
    state.response = { ...base, status: 'owner_accepted', proofStatus: 'rejected', reason: 'Picture unclear, re-upload' };
    const html = await renderDetail();
    expect(html).toContain('Picture unclear, re-upload');
    expect(html).toMatch(/re-?upload/i);
    expect(html).not.toMatch(/payment successful/i);
  });
  it('a request with an uploaded proof stays Pending verification with no payment claim', async () => {
    state.list = { requests: [{ ...base, status: 'payment_proof_uploaded' }], nextAfter: null, nextAfterId: null };
    state.response = { ...base, status: 'payment_proof_uploaded' };
    const html = await renderDetail();
    expect(html).toContain('Pending verification');
    // Owner decision 2026-10-04: the ruled stepper may show "Payment recorded"
    // as a FUTURE stage label; only a money-received state claim is banned
    // before a bound ledger receipt (BUY-022).
    expect(html).toMatch(/Payment recorded/);
    expect(html).not.toMatch(/payment successful|payment has been recorded|money recorded|payment received|bank verified/i);
  });
});
