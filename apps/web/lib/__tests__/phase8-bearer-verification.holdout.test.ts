import { beforeEach, describe, expect, it, vi } from 'vitest';

const requestAdapter = vi.hoisted(() => ({
  createRequestSupabase: vi.fn(),
}));

vi.mock('../supabase/request', () => requestAdapter);

import { readRequestIdentity } from '../identity-session';

const USER_ID = '00000000-0000-4000-8000-000000000081';
const TENANT_ID = '00000000-0000-4000-8000-000000000082';
const STAFF_ID = '00000000-0000-4000-8000-000000000083';
const MEMBER_ID = '00000000-0000-4000-8000-000000000084';
const BEARER = 'opaque.verified.access-token';

function request(withBearer = true): Request {
  return new Request('https://gymloop.example/api/check-in', {
    method: 'POST',
    ...(withBearer ? { headers: { authorization: `Bearer ${BEARER}` } } : {}),
  });
}

function claims(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    sub: USER_ID,
    role: 'authenticated',
    tenant_id: TENANT_ID,
    app_role: 'front_desk',
    staff_id: STAFF_ID,
    ...overrides,
  };
}

function client(claimSet: Record<string, unknown>, bearer: string | undefined = BEARER) {
  const getClaims = vi.fn().mockResolvedValue({ data: { claims: claimSet }, error: null });
  const getUser = vi.fn().mockResolvedValue({ data: { user: { id: USER_ID } }, error: null });
  const supabase = { auth: { getClaims, getUser } };
  requestAdapter.createRequestSupabase.mockReturnValue({ supabase, bearer });
  return { supabase, getClaims, getUser };
}

describe('HARD-004 independent bearer verification', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('admits a complete verified staff bearer without calling Auth /user', async () => {
    const { supabase, getClaims, getUser } = client(claims());

    const result = await readRequestIdentity(request());

    expect(result).toMatchObject({ supabase, authenticatedUser: true });
    expect(result?.identity).toBeDefined();
    expect(getClaims).toHaveBeenCalledExactlyOnceWith(BEARER);
    expect(getUser).not.toHaveBeenCalled();
  });

  it('admits a complete verified member bearer without an Auth /user call', async () => {
    const { getClaims, getUser } = client(claims({
      app_role: 'member',
      staff_id: undefined,
      member_id: MEMBER_ID,
    }));

    const result = await readRequestIdentity(request());

    expect(result?.identity).toBeDefined();
    expect(getClaims).toHaveBeenCalledExactlyOnceWith(BEARER);
    expect(getUser).not.toHaveBeenCalled();
  });

  it.each([
    ['missing role', { role: undefined }],
    ['anonymous role', { role: 'anon' }],
    ['missing staff identity', { staff_id: undefined }],
    ['contradictory identities', { member_id: MEMBER_ID }],
    ['malformed tenant', { tenant_id: 'not-a-uuid' }],
  ])('rejects %s even when the claims call succeeds', async (_case, overrides) => {
    const { getUser } = client(claims(overrides));

    expect(await readRequestIdentity(request())).toBeNull();
    expect(getUser).not.toHaveBeenCalled();
  });

  it('fails closed on a signature or expiry verification error', async () => {
    const { getClaims, getUser } = client(claims());
    getClaims.mockResolvedValue({ data: { claims: null }, error: new Error('invalid JWT') });

    expect(await readRequestIdentity(request())).toBeNull();
    expect(getUser).not.toHaveBeenCalled();
  });

  it('uses the existing Auth user check for a cookie request', async () => {
    const { getClaims, getUser } = client(claims(), undefined);

    const result = await readRequestIdentity(request(false));

    expect(result?.identity).toBeDefined();
    expect(getClaims).toHaveBeenCalled();
    expect(getUser).toHaveBeenCalled();
  });

  it('rejects ambiguous or absent transport before consulting Auth', async () => {
    const { getClaims, getUser } = client(claims());
    requestAdapter.createRequestSupabase.mockReturnValue(null);

    expect(await readRequestIdentity(request())).toBeNull();
    expect(getClaims).not.toHaveBeenCalled();
    expect(getUser).not.toHaveBeenCalled();
  });
});
