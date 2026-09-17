import { isValidElement, type ReactNode } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  identity: null as Record<string, unknown> | null,
  rpc: [] as unknown[], result: null as unknown, error: null as unknown,
  hooks: [] as unknown[], cursor: 0, redirects: [] as string[],
}));
vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  return { ...actual, useState: (initial: unknown) => {
    const index = state.cursor++;
    if (!(index in state.hooks)) state.hooks[index] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
    return [state.hooks[index], (next: unknown) => { state.hooks[index] = typeof next === 'function' ? (next as (old: unknown) => unknown)(state.hooks[index]) : next; }];
  } };
});
vi.mock('next/navigation', () => ({ redirect: (path: string) => { state.redirects.push(path); throw new Error(`REDIRECT:${path}`); } }));
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => ({ identity: state.identity, supabase: { rpc: async (name: string, args: unknown) => { state.rpc.push({ name, args }); return { data: state.result, error: state.error }; } } }) }));

const response = { tenantId: '11111111-1111-4111-8111-111111111111', asOf: '2026-09-17T10:00:00+00:00', timezone: 'Asia/Kolkata', localToday: '2026-09-17', range: { from: '2026-09-01', through: '2026-09-17', startsAt: '2026-08-31T18:30:00+00:00', endsBefore: '2026-09-17T18:30:00+00:00', mode: 'explicit' }, cards: { visitsToday: '2', liveMembers: '0', pausedMembers: '0', openCases: '1', followUpsDue: '0', recovered: '0', cash: [], renewal: [], leads: { converted: '0', total: '0' }, addonCash: [], pt: { sessionsUsed: '0', sessionsTotal: '0', orders: '0' } }, components: { visits: [{ attendanceId: 'a', memberId: 'm', memberName: 'Asha', checkedInAt: '2026-09-17T04:00:00+00:00' }], liveMembers: [], cases: [], recoveries: [], collected: [], returned: [], renewals: [], leads: [], ptOrders: [] }, warnings: { undatedPayments: [{ paymentId: 'p', amountPaise: '100', currency: 'INR' }], undatedReturns: [], undatedPtOrders: [], incompletePtOrders: [] } };

const USER_ID = '22222222-2222-4222-8222-222222222222';
const STAFF_ID = '33333333-3333-4333-8333-333333333333';
beforeEach(() => { state.identity = { kind: 'staff', role: 'gym_owner', userId: USER_ID, tenantId: response.tenantId, staffId: STAFF_ID }; state.rpc = []; state.result = response; state.error = null; state.hooks = []; state.cursor = 0; state.redirects = []; });
function inspect(node: ReactNode): string { if (Array.isArray(node)) return node.map(inspect).join(' '); if (!isValidElement<Record<string, unknown>>(node)) return typeof node === 'string' || typeof node === 'number' ? String(node) : ''; if (typeof node.type === 'function') return inspect((node.type as (props: Record<string, unknown>) => ReactNode)(node.props)); return inspect(node.props.children as ReactNode); }
function buttons(node: ReactNode): Array<Record<string, unknown>> { if (Array.isArray(node)) return node.flatMap(buttons); if (!isValidElement<Record<string, unknown>>(node)) return []; if (typeof node.type === 'function') return buttons((node.type as (props: Record<string, unknown>) => ReactNode)(node.props)); return [node.props, ...buttons(node.props.children as ReactNode)]; }

describe('owner dashboard metrics', () => {
  it.each([
    { label: 'owner', identity: { kind: 'staff', role: 'gym_owner', userId: USER_ID, tenantId: response.tenantId, staffId: STAFF_ID } },
    { label: 'manager', identity: { kind: 'staff', role: 'gym_manager', userId: USER_ID, tenantId: response.tenantId, staffId: STAFF_ID } },
  ])('admits $label and calls owner_metrics once', async ({ identity }) => { state.identity = identity; const { loadOwnerMetrics } = await import('../../lib/metrics'); await loadOwnerMetrics(Promise.resolve({ from: '2026-09-01', through: '2026-09-17' })); expect(state.rpc).toEqual([{ name: 'owner_metrics', args: { p_from: '2026-09-01', p_through: '2026-09-17' } }]); });
  it('defaults absent dates and refuses preview or unauthorized staff before RPC', async () => { const { loadOwnerMetrics } = await import('../../lib/metrics'); await loadOwnerMetrics(Promise.resolve({})); expect(state.rpc).toEqual([{ name: 'owner_metrics', args: { p_from: null, p_through: null } }]); for (const identity of [{ kind: 'staff', role: 'trainer', userId: USER_ID, tenantId: response.tenantId, staffId: STAFF_ID }, { kind: 'impersonation', userId: USER_ID, tenantId: response.tenantId, impersonationSessionId: STAFF_ID }]) { state.rpc = []; state.identity = identity; await expect(loadOwnerMetrics(Promise.resolve({}))).rejects.toThrow(/^REDIRECT:/); expect(state.rpc).toHaveLength(0); } });
  it.each([
    { from: '2026-02-31', through: '2026-03-01' },
    { from: '2026-09-01' },
    { from: '2026-09-18', through: '2026-09-17' },
  ])('rejects malformed or incomplete ranges before RPC', async (searchParams) => { const { loadOwnerMetrics } = await import('../../lib/metrics'); await expect(loadOwnerMetrics(Promise.resolve(searchParams))).rejects.toMatchObject({ code: 'invalid_metrics_range' }); expect(state.rpc).toHaveLength(0); });
  it.each(['invalid_metrics_range', 'invalid_gym_timezone'])('maps %s without raw database text', async (code) => { state.error = { code: '22023', message: `${code}: secret postgres detail` }; const { loadOwnerMetrics } = await import('../../lib/metrics'); try { await loadOwnerMetrics(Promise.resolve({})); throw new Error('expected metrics loader to fail'); } catch (error) { expect(error).toMatchObject({ code }); expect(String(error)).not.toContain('secret postgres detail'); } });
  it('renders cards, empty states, warning, and same-response component row', async () => {
    const { default: Page } = await import('../(console)/dashboard/page');
    const view = await Page({ searchParams: Promise.resolve({}) });
    state.cursor = 0;
    const text = inspect(view);
    expect(text).toContain('2'); expect(text).toContain('No cohort'); expect(text).toContain('No cash movement');
    expect(text).toMatch(/undated payment|data quality/i); expect(text).toContain('100'); expect(text).not.toContain('Asha');
    const { MetricsDashboard } = await import('../(console)/dashboard/metrics-dashboard');
    state.hooks = []; state.cursor = 0;
    const dashboard = (MetricsDashboard as unknown as (props: Record<string, unknown>) => ReactNode)({ metrics: response });
    const visitControl = buttons(dashboard).find((props) => typeof props.onClick === 'function' && /visit/i.test(inspect(props.children as ReactNode)));
    expect(visitControl).toBeDefined();
    await (visitControl!.onClick as () => unknown)();
    state.cursor = 0;
    expect(inspect((MetricsDashboard as unknown as (props: Record<string, unknown>) => ReactNode)({ metrics: response }))).toContain('Asha');
    expect(state.rpc).toHaveLength(1);
  });
});
