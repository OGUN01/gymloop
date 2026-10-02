// Independent INV/STI frozen form-token recovery contract, implementation-blind.
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const webRequire = createRequire(new URL('../../apps/web/package.json', import.meta.url));
const { NextRequest } = webRequire('next/server');
const h = vi.hoisted(() => ({ client: null as any, cookies: new Map<string, string>(), cookieWrites: [] as any[],
  reply: null as any, rpc: vi.fn(), refresh: vi.fn(), signOut: vi.fn() }));
vi.mock('../../apps/web/lib/api.ts', async () => ({ ...(await vi.importActual<any>('../../apps/web/lib/api.ts')),
  signedInSession: async () => ({ session: { supabase: h.client, userId: 'fd111111-1111-4111-8111-111111111111' } }),
}));
vi.mock('../../apps/web/lib/supabase/server.ts', () => ({ createServerSupabase: async () => h.client }));
vi.mock('next/headers', () => ({ cookies: async () => ({
  get: (name: string) => h.cookies.has(name) ? { name, value: h.cookies.get(name) } : undefined,
  getAll: () => [...h.cookies].map(([name, value]) => ({ name, value })),
  set: (...args: any[]) => h.cookieWrites.push(args),
}) }));

const fixture = {
  origin: 'https://form-recovery.holdout.example', submitted: 'H'.repeat(43), stale: 'O'.repeat(43),
  opposite: 'X'.repeat(43), email: 'signed-in-viewer@holdout.example',
};
const families = [
  { name: 'member', cookie: 'fitcruxx_invite', oppositeCookie: 'fitcruxx_staff_invite',
    continuation: '/invite/continue', rpc: 'redeem_member_invite' },
  { name: 'staff', cookie: 'fitcruxx_staff_invite', oppositeCookie: 'fitcruxx_invite',
    continuation: '/staff-invite/continue', rpc: 'redeem_staff_invite' },
];

beforeEach(() => {
  vi.stubEnv('WEB_APP_URL', fixture.origin);
  h.cookies.clear(); h.cookieWrites = []; h.rpc.mockReset(); h.refresh.mockReset(); h.signOut.mockReset();
  h.reply = { data: [{ outcome: 'email_mismatch', gym_name: null, staff_role: null }], error: null };
  h.rpc.mockImplementation(async () => h.reply);
  h.refresh.mockResolvedValue({ data: { session: {} }, error: null });
  h.signOut.mockResolvedValue({ error: null });
  h.client = { rpc: h.rpc, auth: { refreshSession: h.refresh, signOut: h.signOut,
    getUser: async () => ({ data: { user: { id: 'fd111111-1111-4111-8111-111111111111', email: fixture.email } }, error: null }),
    getClaims: async () => ({ data: { claims: { role: 'authenticated', sub: 'fd111111-1111-4111-8111-111111111111' } }, error: null }),
  } };
});
afterEach(() => vi.unstubAllEnvs());

async function redeem(family: typeof families[number]) {
  const form = new FormData(); form.set('token', fixture.submitted);
  const request = new NextRequest(`https://untrusted-incoming.holdout.example/api/${family.name}-invites/redeem`, {
    method: 'POST', body: form,
    headers: { cookie: [...h.cookies].map(([name, value]) => `${name}=${value}`).join('; ') },
  });
  if (family.name === 'member') {
    const { POST } = await import('../../apps/web/app/api/member-invites/redeem/route');
    return POST(request);
  }
  const { POST } = await import('../../apps/web/app/api/staff-invites/redeem/route');
  return POST(request);
}
function familyCookie(response: Response, family: typeof families[number]) {
  const header = response.headers.get('set-cookie') ?? '';
  return header.split(/,(?=\s*[^;,=\s]+=)/).find(part => part.trim().startsWith(`${family.cookie}=`)) ?? '';
}
async function privateRedirect(response: Response) {
  const location = response.headers.get('location') ?? '';
  const body = await response.text();
  for (const secret of [fixture.submitted, fixture.stale, fixture.opposite, fixture.email,
    createHash('sha256').update(fixture.submitted).digest('hex'), 'PRIVATE_RPC_DIAGNOSTIC']) {
    expect(location).not.toContain(secret); expect(body).not.toContain(secret);
  }
  expect(response.headers.get('Cache-Control')).toBe('no-store');
}

describe.each(families)('$name hidden-token refusal recovery', family => {
  it.each(['absent', 'stale'])('preserves actual form token in secure family cookie when old cookie is %s', async prior => {
    if (prior === 'stale') h.cookies.set(family.cookie, fixture.stale);
    h.cookies.set(family.oppositeCookie, fixture.opposite);
    const response = await redeem(family);
    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe(`${fixture.origin}${family.continuation}?result=email_mismatch`);
    expect(h.rpc).toHaveBeenCalledWith(family.rpc, { p_token_hash: createHash('sha256').update(fixture.submitted).digest('hex') });
    const cookie = familyCookie(response, family);
    expect(cookie).toContain(`${family.cookie}=${fixture.submitted}`);
    expect(cookie).not.toContain(fixture.stale);
    expect(cookie).toMatch(/HttpOnly/i); expect(cookie).toMatch(/Max-Age=1800(?:;|$)/i);
    expect(cookie).toMatch(/SameSite=Lax(?:;|$)/i); expect(cookie).toMatch(/Path=\/(?:;|$)/i); expect(cookie).toMatch(/Secure(?:;|$)/i);
    expect(response.headers.get('set-cookie') ?? '').not.toContain(`${family.oppositeCookie}=`);
    expect(h.cookieWrites.some(args => args[0] === family.oppositeCookie)).toBe(false);
    expect(h.refresh).not.toHaveBeenCalled(); await privateRedirect(response);
  });
  it.each(['invite_unavailable', 'identity_unverified', 'account_already_linked', 'rate_limited'])('known %s refusal also saves form token for retry', async outcome => {
    h.reply = { data: [{ outcome, gym_name: null, staff_role: null }], error: null };
    const response = await redeem(family);
    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe(`${fixture.origin}${family.continuation}?result=${outcome}`);
    expect(familyCookie(response, family)).toContain(`${family.cookie}=${fixture.submitted}`);
    expect(h.refresh).not.toHaveBeenCalled(); await privateRedirect(response);
  });
  it('success clears family token and retains the opposite family', async () => {
    h.cookies.set(family.cookie, fixture.stale); h.cookies.set(family.oppositeCookie, fixture.opposite);
    h.reply = { data: [{ outcome: 'linked', gym_name: 'Recovery Gym', staff_role: 'front_desk' }], error: null };
    const response = await redeem(family);
    expect(response.status).toBe(303);
    const cookie = familyCookie(response, family);
    expect(cookie).toMatch(/Max-Age=0(?:;|$)|Expires=Thu, 01 Jan 1970/i);
    expect(cookie).not.toContain(fixture.submitted); expect(cookie).not.toContain(fixture.stale);
    expect(response.headers.get('set-cookie') ?? '').not.toContain(`${family.oppositeCookie}=`);
    if (family.name === 'member') expect(h.refresh).toHaveBeenCalledOnce();
    else expect(h.refresh).not.toHaveBeenCalled();
    await privateRedirect(response);
  });
  it.each(['rpc-error', 'no-row', 'several-rows', 'unknown-outcome'])('%s keeps existing cookies untouched and fails closed', async failure => {
    h.cookies.set(family.cookie, fixture.stale); h.cookies.set(family.oppositeCookie, fixture.opposite);
    h.reply = failure === 'rpc-error' ? { data: null, error: { message: 'PRIVATE_RPC_DIAGNOSTIC' } }
      : { data: failure === 'no-row' ? [] : failure === 'several-rows'
        ? [{ outcome: 'linked', gym_name: 'Recovery Gym' }, { outcome: 'linked', gym_name: 'Recovery Gym' }]
        : [{ outcome: 'pretend_success', gym_name: 'Recovery Gym' }], error: null };
    const response = await redeem(family);
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(familyCookie(response, family)).toBe('');
    expect(response.headers.get('set-cookie') ?? '').not.toContain(`${family.oppositeCookie}=`);
    expect(h.cookieWrites).toEqual([]); expect(h.refresh).not.toHaveBeenCalled();
    await privateRedirect(response);
  });
});
