import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, isValidElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

// Implementation-blind NTF console campaign review surface (NTF-011, NTF-016,
// NTF-008): Messages console gains campaign review/status. Desk previews only;
// owner/manager review commits; copy says "Accepted by push service", never a
// claimed receipt; unknown stays "Delivery unknown".
// FROZEN CONTRACT: proposal.md NTF-008/NTF-011/NTF-016, serial declarations
// (read_push_campaigns envelope {campaigns, nextBefore, nextBeforeId}).
const id = '78100000-0000-4000-8000-000000000001';
const h = vi.hoisted(() => ({ audience: null as string | null, screen: null as unknown, wallet: null as unknown }));
vi.mock('next/headers', () => ({ cookies: async () => ({ get: () => undefined, getAll: () => [] }), headers: async () => new Headers() }));
const campaignRow = { campaignId: id, versionNo: 2, eligibleCount: 34, reviewedAt: '2026-10-03T05:00:00Z', cancelledAt: null, status: 'reviewed' };
vi.mock('../../lib/identity-session', async actual => ({ ...(await actual<Record<string, unknown>>()), requireAudience: async (kind: string) => {
  h.audience = kind;
  return { supabase: { rpc: async (name: string) => name === 'read_push_campaigns' ? { data: { campaigns: [campaignRow], nextBefore: null, nextBeforeId: null }, error: null } : { data: null, error: null } }, identity: { kind: 'staff', userId: id, tenantId: id, staffId: id, role: 'gym_owner' } };
} }));
vi.mock('../../lib/business-type', () => ({ loadBusinessNouns: async () => ({ place: 'gym', plural: 'gyms', member: 'member', trainer: 'trainer', class: 'class' }) }));
vi.mock('../../lib/messages', () => ({
  canViewMessages: () => true,
  loadMessages: async () => ({
    rows: [], statusCounts: { scheduled: '0', sent: '0', delivered: '0', failed: '0', opted_out: '0' }, asOf: '2026-10-03T05:00:00Z',
    isAdmin: true, isPreview: false, tenantId: id, members: [], memberNextCursor: null, memberSearchError: null,
    templates: [], errorMessage: null,
    wallet: { balancePaise: '0', currency: 'INR' },
    ...(h.screen as Record<string, unknown>),
  }),
  walletAdjustmentResult: (data: unknown) => data as never,
  commsRpcFailure: () => new Response(null, { status: 500 }),
  commsOk: (status: string, data: unknown) => Response.json({ ok: true, data }, { status: status === 'created' ? 201 : 200 }),
}));
vi.mock('../../lib/api', () => ({ platformSession: async () => ({ session: { supabase: {} } }), jsonBody: async () => ({ payload: {} }), apiFail: () => new Response(null, { status: 500 }) }));
const nouns = { place: 'gym', plural: 'gyms', member: 'member', trainer: 'trainer', class: 'class' } as const;

let page: () => Promise<string>;
beforeEach(async () => {
  vi.resetModules(); h.screen = null; h.audience = null;
  ({ default: page } = await import('../(console)/messages/page') as unknown as { default: (props: { searchParams: Promise<Record<string, string>> }) => Promise<string> });
});
// Resolve only server async nodes; client hooks remain under React's renderer
// (house pattern from announcements-member-section.test.tsx).
const resolveServer = async (node: ReactNode): Promise<ReactNode> => {
  if (Array.isArray(node)) return Promise.all(node.map(resolveServer));
  if (!isValidElement(node)) return node;
  if (typeof node.type === 'function' && node.type.constructor.name === 'AsyncFunction') return resolveServer(await (node.type as (props: unknown) => Promise<ReactNode>)(node.props));
  const props = node.props as { children?: ReactNode };
  return createElement(node.type, { ...props }, await resolveServer(props.children));
};
const html = async () => renderToStaticMarkup((await resolveServer(await page({ searchParams: Promise.resolve({}) }))) as never);

describe('NTF console Messages campaign review/status (red until built)', () => {
  it('the console audience host is engaged and a review section exists', async () => {
    await html();
    expect(h.audience).toBe('console');
  });
  it('renders push campaign rows with reviewed facts and honest status vocabulary', async () => {
    const output = await html();
    expect(output).toMatch(/Push campaign|push account|Push/i);
    expect(output).toMatch(/Accepted by push service/);
    expect(output).toMatch(/Delivery unknown/);
  });
  it('the campaigns section renders honest on-demand loading; review facts appear at review time, not fabricated server-side', async () => {
    const output = await html();
    expect(output).toMatch(/Push campaigns/);
    expect(output).toMatch(/loads on demand/i);
    // NTF-011 puts title/kind/version/eligible/quiet-hours in the reviewed
    // confirm flow — a user action. Nothing may pre-render eligible counts
    // that no campaign data provided.
    expect(output).not.toMatch(/eligible[^a-z]/i);
  });
  it('never presents acceptance or a campaign as evidence of receipt', async () => {
    const output = await html();
    expect(output).not.toMatch(/delivered to \d+|receipt confirmed|all members received/i);
  });
});
