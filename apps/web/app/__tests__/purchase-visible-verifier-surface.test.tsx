import { beforeEach, describe, expect, it, vi } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';

// R7 desk verifier surface: a real screenshot viewer for the exact active
// proof, recording enabled only after the exact proof rendered, the member
// offered proof replacement once uploaded, and no money or entitlement from
// upload alone. Authored implementation-blind against the frozen contract.

const state = vi.hoisted(() => ({ response: null as unknown, list: null as unknown, memberResponse: null as unknown, memberList: null as unknown }));
const id = '72000000-0000-4000-8000-000000000001';
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => ({ identity: { kind: 'staff', userId: id, tenantId: id, staffId: id, role: 'gym_owner' }, supabase: {} }) }));
vi.mock('../../lib/purchase-console', () => ({
  loadPurchaseRequests: async () => state.list,
  loadPurchaseRequest: async () => state.response,
}));
vi.mock('../../lib/purchase', () => ({
  loadMemberPurchaseRequests: async () => state.memberList,
  loadMemberPurchaseRequest: async () => state.memberResponse,
}));
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: () => {}, push: () => {} }), useSearchParams: () => new URLSearchParams(), redirect: (path: string) => { throw new Error(`redirect:${path}`); } }));
vi.mock('next/link', async () => { const { createElement } = await import('react'); return { default: (props: Record<string, unknown>) => createElement('a', props) }; });
vi.mock('next/image', () => ({ default: (props: Record<string, unknown>) => props.src }));

const request = {
  requestId: id, memberName: 'Visible member', kind: 'shop', status: 'payment_proof_uploaded',
  targetName: 'Verifier whey fixture', quantity: 1, amountPaise: '199900', currency: 'INR', gstRateBp: 1800,
  createdAt: '2026-10-04T04:30:00Z', acceptedAt: '2026-10-04T05:30:00Z', expiresAt: '2026-10-05T05:30:00Z',
  reason: null, proofStatus: 'active', activeProofAssetId: id, proofUrl: `/api/purchase-requests/${id}/proof-asset`, receiptId: null,
};
const memberRequest = {
  requestId: id, kind: 'shop', status: 'payment_proof_uploaded', targetName: 'Member whey fixture',
  quantity: 1, amountPaise: '199900', currency: 'INR', gstRateBp: 1800,
  createdAt: '2026-10-04T04:30:00Z', acceptedAt: '2026-10-04T05:30:00Z', expiresAt: '2026-10-05T05:30:00Z',
  replayed: false, reason: null, proofStatus: 'active', activeProofAssetId: id, proofUrl: `/api/purchase-requests/${id}/proof-asset`, receiptId: null,
};

beforeEach(() => { state.response = request; state.list = { requests: [request], nextAfter: null, nextAfterId: null }; state.memberResponse = memberRequest; state.memberList = { requests: [memberRequest], nextAfter: null, nextAfterId: null }; });

async function renderDeskDetail() {
  const { default: Detail } = await import('../(console)/purchase-requests/[requestId]/page');
  return renderToStaticMarkup(await Detail({ params: Promise.resolve({ requestId: id }) }));
}
async function renderMemberDetail() {
  const { default: Detail } = await import('../member/buy/[requestId]/page');
  return renderToStaticMarkup(await Detail({ params: Promise.resolve({ requestId: id }) }));
}

describe('R7 the desk verifier sees the exact active proof as a real screenshot', () => {
  it('renders the proof image from the bounded same-origin proof-asset route', async () => {
    const html = await renderDeskDetail();
    expect(html).toMatch(new RegExp(`/api/purchase-requests/${id}/proof-asset`));
    expect(html).toMatch(/<img|Image|proof/i);
    expect(html).not.toContain('r2.test');
    expect(html).not.toMatch(/staging\//);
  });
  it('recording is never offered enabled at first paint before the proof was viewed', async () => {
    const html = await renderDeskDetail();
    if (/Record (received )?payment/.test(html)) {
      expect(html, 'the record action must be disabled until the exact proof rendered').toMatch(/<button[^>]*disabled[^>]*>\s*Record (received )?payment/);
    }
  });
  it('the verifier disclosure names quoted amount, actual amount, method and currency', async () => {
    const html = await renderDeskDetail();
    expect(html).toMatch(/1,999|1999/);
    expect(html).toMatch(/₹|INR/);
    expect(html).toMatch(/[Mm]ethod|UPI|cash/i);
  });
  it('an upload never claims money truth: no receipt and no paid copy before recording', async () => {
    const html = await renderDeskDetail();
    expect(html).not.toMatch(/payment successful|bank verified/i);
    expect(html).not.toMatch(/RC-\d{4}/);
  });
});

describe('R7 the member is offered proof replacement while uploaded', () => {
  it('a payment_proof_uploaded request offers replace or re-upload, never a paid claim', async () => {
    const html = await renderMemberDetail();
    expect(html).toMatch(/replace|re-?upload/i);
    expect(html).toContain('Pending verification');
    expect(html).not.toMatch(/payment successful/i);
  });
  it('the member proof view uses the bounded route URL, never storage metadata', async () => {
    const html = await renderMemberDetail();
    expect(html).not.toMatch(/staging\/|etag/i);
  });
});
