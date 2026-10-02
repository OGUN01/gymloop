import { renderToStaticMarkup } from 'react-dom/server';
import type { ReactNode } from 'react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const request = vi.hoisted(() => ({
  tenant: '70000000-0000-4000-8000-000000000001',
  user: '70000000-0000-4000-8000-000000000901',
  member: false, allowed: true, type: 'dance', afterRead: 'yoga', reads: [] as string[],
  cache: new Map<unknown, Array<{ args: unknown[]; value: unknown }>>(),
}));
vi.mock('react', async (original) => {
  const react = await original<typeof import('react')>();
  return { ...react, cache: (fn: (...args: unknown[]) => unknown) => (...args: unknown[]) => {
    const entries = request.cache.get(fn) ?? [];
    const hit = entries.find((entry) => entry.args.length === args.length && entry.args.every((arg, index) => Object.is(arg, args[index])));
    if (hit) return hit.value;
    const value = fn(...args); entries.push({ args, value }); request.cache.set(fn, entries); return value;
  } };
});

// Each server-client creation gets a distinct object but the same verified session.
const client = () => {
  const scope = { tenant: request.tenant, user: request.user, allowed: request.allowed, member: request.member };
  const claims = { sub: scope.user, role: 'authenticated', app_role: scope.member ? 'member' : 'gym_owner', tenant_id: scope.tenant,
    ...(scope.member ? { member_id: '70000000-0000-4000-8000-000000000101' } : { staff_id: '70000000-0000-4000-8000-000000000021' }) };
  return {
    auth: { getClaims: async () => ({ data: { claims }, error: null }) },
    rpc: async () => ({ data: [], error: null }),
    from: (table: string) => {
      let projection = ''; let target = scope.tenant;
      const result = () => {
        if (table === 'organizations') {
          const vocabulary = projection.split(',').some((column) => column.trim() === 'business_type' || column.trim() === '*');
          const type = request.type;
          if (vocabulary) { request.reads.push(`${scope.user}:${target}`); request.type = request.afterRead; }
          return { data: scope.allowed && target === scope.tenant ? { id: scope.tenant, name: 'BIZ Academy', gym_code: 'BIZ70A', timezone: 'Asia/Kolkata', ...(vocabulary ? { business_type: type } : {}) } : null, error: null };
        }
        if (table === 'members' && scope.member) return { data: { id: 'member_id' in claims ? claims.member_id : null, full_name: 'Aarav Sharma', member_code: 'BIZ-101', phone: '+917000000101', email: null, branch_id: null, status: 'active' }, error: null };
        return { data: [], error: null, count: 0 };
      };
      const query = {
        select: (columns: string) => { projection = columns; return query; },
        eq: (column: string, value: string) => { if (table === 'organizations' && column === 'id') target = value; return query; },
        in: () => query, is: () => query, order: () => query, limit: () => query, range: () => query, or: () => query,
        gte: () => query, lte: () => query, lt: () => query, gt: () => query,
        maybeSingle: async () => result(), single: async () => result(),
        then: (resolve: (value: ReturnType<typeof result>) => unknown) => Promise.resolve(result()).then(resolve),
      };
      return query;
    },
  };
};
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => ({ supabase: client(), identity: request.member
  ? { kind: 'member', userId: request.user, tenantId: request.tenant, memberId: '70000000-0000-4000-8000-000000000101' }
  : { kind: 'staff', userId: request.user, tenantId: request.tenant, staffId: '70000000-0000-4000-8000-000000000021', role: 'gym_owner' } }) }));
vi.mock('../../lib/auth-actions', () => ({ signOut: vi.fn() }));
vi.mock('next-themes', () => ({ useTheme: () => ({ theme: 'system', setTheme: vi.fn() }) }));
vi.mock('next/navigation', () => ({ usePathname: () => request.member ? '/member' : '/console', redirect: vi.fn(), notFound: vi.fn() }));

const startRequest = (type: string, afterRead = type) => { request.cache.clear(); request.reads = []; request.type = type; request.afterRead = afterRead; };
const renderRequest = async (surface: 'console' | 'member') => {
  request.member = surface === 'member';
  const page: ReactNode = surface === 'console'
    ? await (await import('../(console)/console/page')).default({ searchParams: Promise.resolve({}) })
    : await (await import('../member/page')).default();
  const tree = surface === 'console'
    ? await (await import('../(console)/layout')).default({ children: page })
    : await (await import('../member/layout')).default({ children: page });
  return renderToStaticMarkup(tree).replace(/<[^>]*>/g, ' ');
};
beforeEach(() => { request.tenant = '70000000-0000-4000-8000-000000000001'; request.user = '70000000-0000-4000-8000-000000000901'; request.allowed = true; startRequest('dance'); });
describe('BIZ-010/020 request vocabulary consistency', () => {
  it.each(['console', 'member'] as const)('%s shell and page share one authoritative read even when storage changes', async (surface) => {
    startRequest('dance', 'yoga');
    const text = await renderRequest(surface);
    expect.soft(request.reads).toEqual([`${request.user}:${request.tenant}`]);
    expect(text).toContain(surface === 'member' ? 'academy' : 'students');
    expect(text).not.toMatch(/\b(?:gym|members?|trainer|studio)\b/i);
  });
  it.each(['console', 'member'] as const)('%s next request observes a changed value and then an unknown-value fallback', async (surface) => {
    await renderRequest(surface);
    startRequest('yoga');
    expect(await renderRequest(surface)).toContain('studio');
    expect.soft(request.reads).toEqual([`${request.user}:${request.tenant}`]);
    startRequest('unknown');
    expect(await renderRequest(surface)).toContain(surface === 'member' ? 'gym' : 'members');
    expect.soft(request.reads).toEqual([`${request.user}:${request.tenant}`]);
  });
  it.each(['console', 'member'] as const)('%s does not reuse another tenant or a denied caller vocabulary', async (surface) => {
    await renderRequest(surface);
    request.tenant = '70000000-0000-4000-8000-000000000002'; request.user = '70000000-0000-4000-8000-000000000902';
    startRequest('yoga');
    expect(await renderRequest(surface)).toContain('studio');
    expect.soft(request.reads).toEqual([`${request.user}:${request.tenant}`]);
    request.allowed = false; request.user = '70000000-0000-4000-8000-000000000903'; startRequest('dance');
    const denied = await renderRequest(surface);
    expect(denied).not.toMatch(/\b(?:academy|students?|instructors?)\b/i);
  });
});



