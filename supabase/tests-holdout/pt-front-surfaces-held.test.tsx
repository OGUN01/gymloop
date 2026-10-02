// Render public page exports against independently constructed RPC rows.
// No private production factory or invented component props are used.
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, expect, it, vi } from 'vitest';
const h = vi.hoisted(() => ({ rpc: vi.fn(), packs: [] as Record<string, unknown>[], sessions: [] as Record<string, unknown>[], role: 'member' }));
const ids = { tenant: '73930000-0000-4000-8000-000000000001', order: '73930000-0000-4000-8000-000000000002', trainer: '73930000-0000-4000-8000-000000000003', member: '73930000-0000-4000-8000-000000000004' };
function client() {
  return { rpc: h.rpc, from: () => {
    const response = { data: { name: 'Independent Studio', timezone: 'Asia/Kolkata', business_type: 'studio', pt_cancel_window_hours: 24, pt_late_cancel_consumes_session: true, pt_session_minutes: 60 }, error: null };
    const chain = Object.assign(Promise.resolve(response), { select: () => chain, eq: () => chain, order: () => chain, limit: () => chain, single: async () => response, maybeSingle: async () => response });
    return chain;
  } };
}
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }), notFound: () => { throw Error('not-found'); }, redirect: () => { throw Error('redirect'); } }));
vi.mock('next/link', () => ({ default: ({ children, href }: { children: React.ReactNode; href: string }) => React.createElement('a', { href }, children) }));
vi.mock('../../apps/web/lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../apps/web/lib/identity-session', () => ({
  requireAudience: async () => ({ supabase: client(), identity: { kind: h.role === 'member' ? 'member' : 'staff', role: h.role, tenantId: ids.tenant, userId: ids.member, memberId: ids.member, staffId: ids.trainer } }),
  readIdentity: async () => ({ supabase: client(), identity: { kind: 'member', tenantId: ids.tenant, userId: ids.member, memberId: ids.member } }),
}));
async function resolveServer(node: React.ReactNode): Promise<React.ReactNode> {
  if (Array.isArray(node)) return Promise.all(node.map(resolveServer));
  if (!React.isValidElement(node)) return node;
  const element = node as React.ReactElement<{ children?: React.ReactNode }>;
  if (typeof element.type === 'function' && element.type.constructor.name === 'AsyncFunction') {
    const component = element.type as (props: unknown) => Promise<React.ReactNode>;
    return resolveServer(await component(element.props));
  }
  if (element.props.children !== undefined) return React.cloneElement(element, {}, await resolveServer(element.props.children));
  return element;
}
async function html(staff = false) {
  const { default: Page } = staff ? await import('../../apps/web/app/(console)/training/packs/page') : await import('../../apps/web/app/member/classes/training/page');
  const node = await Page({ searchParams: Promise.resolve({}) });
  return renderToStaticMarkup(await resolveServer(node)).replaceAll('&#x27;', "'").replaceAll('&#39;', "'");
}
function text(markup: string) { return markup.replace(/<[^>]*>/g, '').replace(/\s+/g, ' '); }
beforeEach(() => {
  h.role = 'member'; h.sessions = []; h.packs = [{ order_id: ids.order, programme_name: 'Strength Foundations', trainer_key: ids.trainer, trainer_staff_id: ids.trainer, trainer_name: 'Nisha', trainer_active: true, member_id: ids.member, member_name: 'Ravi', member_code: 'H-73', sessions_total: 10, sessions_used: 3, sessions_scheduled: 2, sessions_remaining: 7, starts_on: '2026-08-01', expires_on: '2026-09-01', state: 'expired', can_book: false, timezone: 'Asia/Kolkata' }];
  h.rpc.mockReset(); h.rpc.mockImplementation((name: string) => {
    const data = name === 'read_member_pt_packs' || name === 'read_pt_packs' ? h.packs : name === 'read_member_pt_sessions' ? h.sessions : [];
    const response = { data, error: null }; return Object.assign(Promise.resolve(response), { single: async () => response, maybeSingle: async () => response });
  });
});
it('expired member pack keeps seven unused and two booked visibly separate, no booking link', async () => {
  const markup = await html(); expect(markup).toContain('Strength Foundations'); expect(markup).toMatch(/Expired/i);
  expect(text(markup)).toMatch(/7\s*(?:unused|left|sessions)/i); expect(text(markup)).toMatch(/2\s*(?:booked|scheduled)/i);
  expect(markup).not.toContain(`/book/${ids.order}`);
  expect(h.rpc.mock.calls.every(([name]) => String(name).startsWith('read_'))).toBe(true);
});
it('owner expired pack shows same unused balance without deriving five from reservations', async () => {
  h.role = 'gym_owner'; const markup = await html(true); expect(markup).toMatch(/Expired/i);
  const plain = text(markup); expect(plain).toMatch(/\b7\b/); expect(plain).toMatch(/\b2\b/);
  expect(plain).toMatch(/unused|remaining|left/i); expect(plain).toMatch(/booked|scheduled/i);
});
it('live member pack keeps five left to book and separate purchased/used/reserved counters', async () => {
  const pack = h.packs[0]; if (pack === undefined) throw Error('Missing pack fixture');
  Object.assign(pack, { state: 'live', can_book: true, sessions_remaining: 5, expires_on: '2027-01-01' });
  const markup = await html(); expect(text(markup)).toMatch(/5\s*(?:left|sessions)/i); expect(markup).toContain(`/book/${ids.order}`);
  expect(text(markup)).toMatch(/3\s*(?:of|used)/i); expect(text(markup)).toMatch(/2\s*(?:booked|scheduled)/i);
});
it('waived late cancellation is Cancelled by you, no consumed status, no reopening cancelled session', async () => {
  h.sessions = [{ session_id: ids.member, order_id: ids.order, programme_name: 'Strength Foundations', trainer_key: ids.trainer, trainer_name: 'Nisha', starts_at: '2026-09-01T05:00:00Z', ends_at: '2026-09-01T06:00:00Z', timezone: 'Asia/Kolkata', status: 'cancelled_by_member', consumed: false, cancelled_at: '2026-08-31T17:00:00Z', can_cancel: false, cancel_cutoff: '2026-08-31T05:00:00Z', late_now: true, consumes_now: true }];
  const markup = await html(); expect(markup).toContain('Cancelled by you'); expect(markup).not.toContain('Cancelled late - session used');
});
