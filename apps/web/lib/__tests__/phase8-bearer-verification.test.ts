import { beforeEach, describe, expect, it, vi } from 'vitest';

const requestClient = vi.hoisted(() => vi.fn());

vi.mock('../supabase/request', () => ({ createRequestSupabase: requestClient }));

import { POST } from '../../app/api/check-in/route';
import { readRequestIdentity } from '../identity-session';

const subject = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const tenant = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const staff = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const member = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const token = 'signed.access.token';

const staffClaims = {
  sub: subject,
  role: 'authenticated',
  app_role: 'front_desk',
  tenant_id: tenant,
  staff_id: staff,
};
const memberClaims = {
  sub: subject,
  role: 'authenticated',
  app_role: 'member',
  tenant_id: tenant,
  member_id: member,
};

function bearerRequest(extraHeaders?: Record<string, string>): Request {
  return new Request('https://gymloop.example/api/check-in', {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, ...extraHeaders },
  });
}

function authClient(claims: unknown, options?: { claimsError?: Error | null; userId?: string | null }) {
  const getClaims = vi.fn().mockResolvedValue({
    data: options?.claimsError ? null : { claims },
    error: options?.claimsError ?? null,
  });
  const getUser = vi.fn().mockResolvedValue({
    data: { user: options?.userId === null ? null : { id: options?.userId ?? subject } },
    error: null,
  });
  return { auth: { getClaims, getUser } };
}

beforeEach(() => requestClient.mockReset());

describe('HARD-004 verified bearer boundary', () => {
  it('admits a signed staff bearer from verified claims without calling Auth /user', async () => {
    const supabase = authClient(staffClaims);
    requestClient.mockReturnValue({ supabase, bearer: token });

    const result = await readRequestIdentity(bearerRequest());

    expect(supabase.auth.getClaims).toHaveBeenCalledExactlyOnceWith(token);
    expect(supabase.auth.getUser).not.toHaveBeenCalled();
    expect(result).toEqual({
      supabase,
      identity: { kind: 'staff', userId: subject, tenantId: tenant, staffId: staff, role: 'front_desk' },
      authenticatedUser: true,
    });
  });

  it('admits a signed member bearer with only the verified member association', async () => {
    const supabase = authClient(memberClaims);
    requestClient.mockReturnValue({ supabase, bearer: token });

    const result = await readRequestIdentity(bearerRequest());

    expect(supabase.auth.getClaims).toHaveBeenCalledExactlyOnceWith(token);
    expect(supabase.auth.getUser).not.toHaveBeenCalled();
    expect(result).toEqual({
      supabase,
      identity: { kind: 'member', userId: subject, tenantId: tenant, memberId: member },
      authenticatedUser: true,
    });
  });

  it.each([
    ['missing Auth role', { role: undefined }],
    ['anonymous Auth role', { role: 'anon' }],
    ['service Auth role', { role: 'service_role' }],
    ['malformed subject', { sub: 'not-a-uuid' }],
    ['missing subject', { sub: undefined }],
    ['missing tenant', { tenant_id: undefined }],
    ['missing staff', { staff_id: undefined }],
    ['contradictory member key', { member_id: member }],
    ['contradictory preview key', { impersonation_session_id: staff }],
  ])('refuses %s even when a staff-shaped claim is otherwise present', async (_label, change) => {
    const supabase = authClient({ ...staffClaims, ...change });
    requestClient.mockReturnValue({ supabase, bearer: token });

    expect(await readRequestIdentity(bearerRequest())).toBeNull();
    expect(supabase.auth.getUser).not.toHaveBeenCalled();
  });

  it.each([
    ['missing member association', { member_id: undefined }],
    ['contradictory staff association', { staff_id: staff }],
  ])('refuses a member bearer with %s', async (_label, change) => {
    const supabase = authClient({ ...memberClaims, ...change });
    requestClient.mockReturnValue({ supabase, bearer: token });

    expect(await readRequestIdentity(bearerRequest())).toBeNull();
    expect(supabase.auth.getUser).not.toHaveBeenCalled();
  });

  it('fails closed when signature or expiry verification returns an error', async () => {
    const supabase = authClient(staffClaims, { claimsError: new Error('verification failed') });
    requestClient.mockReturnValue({ supabase, bearer: token });

    expect(await readRequestIdentity(bearerRequest())).toBeNull();
    expect(supabase.auth.getUser).not.toHaveBeenCalled();
  });

  it('fails closed when signature or expiry verification throws', async () => {
    const supabase = authClient(staffClaims);
    supabase.auth.getClaims.mockRejectedValue(new Error('signing keys unavailable'));
    requestClient.mockReturnValue({ supabase, bearer: token });

    expect(await readRequestIdentity(bearerRequest())).toBeNull();
    expect(supabase.auth.getUser).not.toHaveBeenCalled();
  });

  it('rejects an absent or ambiguous transport before parsing a check-in body', async () => {
    const supabase = authClient(staffClaims);
    requestClient.mockReturnValue(null);
    const request = bearerRequest({ cookie: 'sb-project-auth-token=present' });
    const parseBody = vi.fn();
    Object.defineProperty(request, 'json', { value: parseBody });

    const response = await POST(request);

    expect(response.status).toBe(401);
    expect(parseBody).not.toHaveBeenCalled();
    expect(supabase.auth.getClaims).not.toHaveBeenCalled();
    expect(supabase.auth.getUser).not.toHaveBeenCalled();
  });

  it('rejects bad verified claims before parsing a check-in body', async () => {
    const supabase = authClient({ ...staffClaims, role: 'anon' });
    requestClient.mockReturnValue({ supabase, bearer: token });
    const request = bearerRequest();
    const parseBody = vi.fn();
    Object.defineProperty(request, 'json', { value: parseBody });

    const response = await POST(request);

    expect(response.status).toBe(401);
    expect(parseBody).not.toHaveBeenCalled();
    expect(supabase.auth.getUser).not.toHaveBeenCalled();
  });

  it('rejects a verified platform identity before parsing a check-in body', async () => {
    const supabase = authClient({
      sub: subject,
      role: 'authenticated',
      app_role: 'super_admin',
    });
    requestClient.mockReturnValue({ supabase, bearer: token });
    const request = bearerRequest();
    const parseBody = vi.fn();
    Object.defineProperty(request, 'json', { value: parseBody });

    const response = await POST(request);

    expect(response.status).toBe(403);
    expect(parseBody).not.toHaveBeenCalled();
    expect(supabase.auth.getUser).not.toHaveBeenCalled();
  });

  it('preserves the cookie session Auth user check', async () => {
    const supabase = authClient(staffClaims);
    requestClient.mockReturnValue({ supabase });
    const request = new Request('https://gymloop.example/api/check-in', {
      method: 'POST',
      headers: { cookie: 'sb-project-auth-token=present' },
    });

    const result = await readRequestIdentity(request);

    expect(supabase.auth.getClaims).toHaveBeenCalled();
    expect(supabase.auth.getUser).toHaveBeenCalled();
    expect(result?.identity).toEqual({ kind: 'staff', userId: subject, tenantId: tenant, staffId: staff, role: 'front_desk' });
  });

  it('refuses a cookie session whose Auth user differs from the verified subject', async () => {
    const supabase = authClient(staffClaims, { userId: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee' });
    requestClient.mockReturnValue({ supabase });
    const request = new Request('https://gymloop.example/api/check-in', {
      method: 'POST',
      headers: { cookie: 'sb-project-auth-token=present' },
    });

    expect(await readRequestIdentity(request)).toBeNull();
    expect(supabase.auth.getUser).toHaveBeenCalled();
  });
});
