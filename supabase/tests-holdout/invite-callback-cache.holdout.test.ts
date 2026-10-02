// INV-021 / STI-014 and frozen v1.1 no-store contract. Independently authored;
// callback implementation and every other author's suite remain unread.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  cookies: new Map<string, string>(), exchangeError: false,
  exchange: vi.fn(), claims: vi.fn(), user: vi.fn(),
}));
vi.mock('../../apps/web/lib/supabase/server.ts', () => ({ createServerSupabase: async () => ({
  auth: { exchangeCodeForSession: state.exchange, getClaims: state.claims, getUser: state.user },
}) }));
vi.mock('next/headers', () => ({ cookies: async () => ({
  get: (name: string) => state.cookies.has(name) ? { name, value: state.cookies.get(name) } : undefined,
  getAll: () => [...state.cookies].map(([name, value]) => ({ name, value })),
  set: vi.fn(),
}) }));

const trustedOrigin = 'https://trusted-callback.holdout.example';
const memberToken = 'm'.repeat(43);
const staffToken = 's'.repeat(43);
const signedInUser = { id: '13572468-1234-4234-8234-123456789abc', email: 'unlinked@holdout.example' };

beforeEach(() => {
  vi.stubEnv('WEB_APP_URL', trustedOrigin);
  state.cookies.clear(); state.exchangeError = false;
  state.exchange.mockReset().mockImplementation(async () => ({
    data: state.exchangeError ? { session: null, user: null } : { session: { user: signedInUser }, user: signedInUser },
    error: state.exchangeError ? { message: 'PRIVATE_EXCHANGE_FAILURE' } : null,
  }));
  state.claims.mockReset().mockResolvedValue({ data: { claims: { sub: signedInUser.id, email: signedInUser.email } }, error: null });
  state.user.mockReset().mockResolvedValue({ data: { user: signedInUser }, error: null });
});
afterEach(() => vi.unstubAllEnvs());

async function callback(query: string) {
  const { GET } = await import('../../apps/web/app/auth/callback/route');
  // Incoming host and `next` are deliberately attacker-controlled. NextResponse itself is real.
  return GET(new Request(`https://untrusted-request.holdout.example/auth/callback${query}`));
}
function assertRedirect(response: Response, destination: string) {
  expect(response.status).toBe(303);
  expect(response.headers.get('Cache-Control')).toBe('no-store');
  const location = response.headers.get('Location');
  expect(location).toBe(`${trustedOrigin}${destination}`);
  expect(location).not.toContain(memberToken); expect(location).not.toContain(staffToken);
  expect(location).not.toContain('untrusted-request'); expect(location).not.toContain('PRIVATE_EXCHANGE_FAILURE');
}

describe('invite OAuth callback redirects remain private and uncached', () => {
  it.each([
    ['member', 'fitcruxx_invite', memberToken, '/invite/continue'],
    ['staff', 'fitcruxx_staff_invite', staffToken, '/staff-invite/continue'],
  ])('%s successful exchange continues on configured origin, 303 and no-store', async (_, cookie, token, destination) => {
    state.cookies.set(cookie, token);
    assertRedirect(await callback('?code=independent-code&next=https%3A%2F%2Fevil.example%2Finvite'), destination);
    expect(state.exchange).toHaveBeenCalledWith('independent-code');
  });
  it('valid member cookie wins when both invite families exist without exposing either token', async () => {
    state.cookies.set('fitcruxx_invite', memberToken); state.cookies.set('fitcruxx_staff_invite', staffToken);
    assertRedirect(await callback('?code=both-family-code'), '/invite/continue');
  });
  it('failed code exchange redirects privately to sign-in without caching failure', async () => {
    state.exchangeError = true;
    state.cookies.set('fitcruxx_invite', memberToken); state.cookies.set('fitcruxx_staff_invite', staffToken);
    assertRedirect(await callback('?code=failed-code'), '/sign-in?failed=1');
  });
  it('missing code redirects privately to sign-in without caching or exchanging', async () => {
    state.cookies.set('fitcruxx_invite', memberToken); state.cookies.set('fitcruxx_staff_invite', staffToken);
    assertRedirect(await callback('?next=https%3A%2F%2Fevil.example'), '/sign-in?failed=1');
    expect(state.exchange).not.toHaveBeenCalled();
  });
});
