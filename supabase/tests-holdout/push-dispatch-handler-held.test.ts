// Independent holdout: frozen NTF declarations, 2026-10-04; no implementation or visible tests read.
import { webcrypto } from 'node:crypto';
import { beforeAll, describe, expect, it, vi } from 'vitest';
import { createPushDispatchHandler } from '../functions/push-dispatch/handler';

const origin = 'https://pecxrpskmfeuyzngvewq.supabase.co';
const account = 'fitcruxx-push-sender@samuraiapi-51996.iam.gserviceaccount.com';
const attemptId = '78800000-0000-4000-8000-000000000001';
const reservationId = '78800000-0000-4000-8000-000000000002';
const foreignId = '78800000-0000-4000-8000-000000000003';
const instant = Date.parse('2026-10-04T06:00:00Z');
const expiresAt = '2026-10-04T06:01:30Z';
const zero = { reserved: 0, authorized: 0, accepted: 0, failed: 0, uncertain: 0, deferred: 0 };
let privateKey: string;
let publicKey: CryptoKey;
beforeAll(async () => {
  const pair = await webcrypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  publicKey = pair.publicKey;
  privateKey = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(await webcrypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64')}\n-----END PRIVATE KEY-----\n`;
});
function harness(overrides: Record<string, string | undefined> = {}, replies: Record<string, unknown> = {}, now = () => instant) {
  const environment: Record<string, string | undefined> = {
    SUPABASE_URL: origin, SUPABASE_SERVICE_ROLE_KEY: 'held-service-credential', PUSH_DISPATCH_SECRET: 'held wakeup secret',
    FCM_PROJECT_ID: 'samuraiapi-51996', FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({ type: 'service_account', project_id: 'samuraiapi-51996', client_email: account, private_key: privateKey, token_uri: 'https://attacker.invalid/token' }), ...overrides,
  };
  const calls: Request[] = [];
  const fetch = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const request = new Request(input, init); calls.push(request);
    const path = new URL(request.url).pathname;
    const reply = replies[path] ?? (path === '/token' ? { access_token: 'held-oauth', token_type: 'Bearer', expires_in: 3600 } : { attempts: [], configuration: 'ready' });
    const result = typeof reply === 'function' ? await reply(request) : reply;
    if (result instanceof Error) throw result;
    if (result instanceof Response) return result.clone();
    return Response.json(result);
  });
  const handler = createPushDispatchHandler({ readEnvironment: name => environment[name], fetch, now, crypto: webcrypto as unknown as Crypto });
  return { handler, calls, environment, fetch };
}
function wake(body = '{}', headers: Record<string, string> = {}, query = '') {
  return new Request(`https://worker.invalid/functions/v1/push-dispatch${query}`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-gymloop-push-dispatch-secret': 'held wakeup secret', ...headers }, body });
}
async function envelope(response: Response, status: number, error: string | null, counts = zero, configuration: string | null = null) {
  expect(response.status).toBe(status);
  expect(response.headers.get('content-type')).toContain('application/json');
  expect(response.headers.get('cache-control')).toBe('no-store');
  expect([...response.headers.keys()].some(key => key.startsWith('access-control-'))).toBe(false);
  expect(await response.json()).toEqual({ ok: error === null, error, configuration, counts });
}
const reservation = { attemptId, reservationId, expiresAt };
const authorization = { authorized: true, ...reservation, token: 'held-private-device-token', tokenRevision: '1', message: { title: 'Held gym', body: 'You have an update. Open the app to view it.', data: { notificationId: foreignId, sourceNotificationId: null, relatedType: null, relatedId: null }, ttlSeconds: 60 } };
const notification = { notificationId: foreignId, memberId: '78800000-0000-4000-8000-000000000004', channel: 'push', status: 'sent', sentAt: '2026-10-04T06:00:00Z', deliveredAt: null, failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null };
const rpc = '/rest/v1/rpc/';
function work(auth: unknown = authorization, provider: unknown = { name: 'projects/samuraiapi-51996/messages/held-accepted' }, finish: unknown = { attemptId, replayed: false, notification }) {
  return harness({}, { [`${rpc}reserve_push_attempts`]: { attempts: [reservation], configuration: 'ready' }, [`${rpc}authorize_push_attempt`]: auth, '/v1/projects/samuraiapi-51996/messages:send': provider, [`${rpc}finish_push_attempt`]: finish });
}

describe('held NTF authenticated boundary and credentials', () => {
  it.each(['GET', 'OPTIONS', 'PUT', 'DELETE'])('method %s wins before missing config', async method => {
    const h = harness({ PUSH_DISPATCH_SECRET: undefined });
    const response = await h.handler(new Request('https://worker.invalid/?tenant=x', { method }));
    expect(response.headers.get('allow')).toBe('POST'); await envelope(response, 405, 'method_not_allowed'); expect(h.calls).toEqual([]);
  });
  it('construction is inert and environment is fresh on each invocation', async () => {
    const h = harness(); expect(h.calls).toEqual([]); h.environment.PUSH_DISPATCH_SECRET = undefined;
    await envelope(await h.handler(wake()), 503, 'configuration_invalid'); expect(h.calls).toEqual([]);
  });
  it('ordinary JWT or service authorization never substitutes for dedicated secret', async () => {
    const h = harness(); const request = wake('{', { authorization: 'Bearer held-service-credential' });
    request.headers.delete('x-gymloop-push-dispatch-secret');
    const read = vi.spyOn(request, 'text');
    await envelope(await h.handler(request), 401, 'unauthorized'); expect(read).not.toHaveBeenCalled(); expect(h.calls).toEqual([]);
  });
  it.each(['', 'held wakeup', 'held wakeup secretsuffix', 'held wakeup other'])('rejects complete unequal secret %s before malformed body', async supplied => {
    const h = harness(); await envelope(await h.handler(wake('{', { 'x-gymloop-push-dispatch-secret': supplied })), 401, 'unauthorized'); expect(h.calls).toEqual([]);
  });
  it.each(['null', '[]', 'true', '"{}"', '{"tenantId":"secret"}', '{'])('rejects nonempty-object shape %s', async body => {
    const h = harness(); await envelope(await h.handler(wake(body)), 400, 'bad_request'); expect(h.calls).toEqual([]);
  });
  it.each(['text/plain', 'application/x-www-form-urlencoded'])('rejects media %s', async media => {
    const h = harness(); await envelope(await h.handler(wake('{}', { 'content-type': media })), 400, 'bad_request'); expect(h.calls).toEqual([]);
  });
  it('counts actual UTF8 bytes despite lying Content-Length', async () => {
    const h = harness(); await envelope(await h.handler(wake(`{"x":"${'é'.repeat(512)}"}`, { 'content-length': '2' })), 413, 'payload_too_large'); expect(h.calls).toEqual([]);
  });
  it('accepts exactly 1024 bytes and optional charset without extra fields', async () => {
    const h = harness(); await envelope(await h.handler(wake(`{${' '.repeat(1022)}}`, { 'content-type': 'application/json; charset=utf-8' })), 200, null, zero, 'ready');
  });
  it('rejects query input before provider config', async () => {
    const h = harness({ FCM_PROJECT_ID: undefined }); await envelope(await h.handler(wake('{}', {}, '?tenant=foreign')), 400, 'bad_request'); expect(h.calls).toEqual([]);
  });
  it.each([`${origin}/`, `${origin}/rest`, `${origin}?x=y`, `${origin}#x`, 'https://user:password@pecxrpskmfeuyzngvewq.supabase.co', 'https://foreign.supabase.co', 'http://pecxrpskmfeuyzngvewq.supabase.co'])('refuses unapproved origin %s before credential transmission', async url => {
    const h = harness({ SUPABASE_URL: url }); await envelope(await h.handler(wake()), 503, 'configuration_invalid'); expect(h.calls).toEqual([]);
  });
  it.each([{ project_id: 'foreign' }, { client_email: 'foreign@samuraiapi-51996.iam.gserviceaccount.com' }, { private_key: 'not a private key' }])('rejects service account mismatch/unusable key %j', async patch => {
    const h = harness({ FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({ type: 'service_account', project_id: 'samuraiapi-51996', client_email: account, private_key: privateKey, ...patch }) });
    await envelope(await h.handler(wake()), 503, 'configuration_invalid'); expect(h.calls).toEqual([]);
  });
  it.each([401, 403])('OAuth %i stops before claim', async status => {
    const h = harness({}, { '/token': Response.json({ error: 'held-private-error' }, { status }) }); await envelope(await h.handler(wake()), 503, 'configuration_invalid'); expect(h.calls).toHaveLength(1);
  });
  it.each(['invalid_grant', 'invalid_client'])('explicit OAuth %s is configuration refusal', async error => {
    const h = harness({}, { '/token': Response.json({ error }, { status: 400 }) }); await envelope(await h.handler(wake()), 503, 'configuration_invalid'); expect(h.calls).toHaveLength(1);
  });
  it.each([new Error('secret network detail'), Response.json({}, { status: 500 }), Response.json({ access_token: '' }), new Response('malformed', { status: 200 })])('unusable OAuth response stays count-only upstream failure', async reply => {
    const h = harness({}, { '/token': reply }); await envelope(await h.handler(wake()), 502, 'upstream_failed'); expect(h.calls).toHaveLength(1);
  });
  it('uses signed approved-account JWT and fixed OAuth endpoint, ignoring JSON token_uri', async () => {
    const h = harness(); await h.handler(wake()); const request = h.calls[0]!;
    expect(request.url).toBe('https://oauth2.googleapis.com/token'); expect(request.redirect).toBe('error');
    const form = new URLSearchParams(await request.text()); expect(form.get('grant_type')).toBe('urn:ietf:params:oauth:grant-type:jwt-bearer');
    const [header, payload, signature] = form.get('assertion')!.split('.');
    expect(JSON.parse(Buffer.from(header!, 'base64url').toString())).toMatchObject({ alg: 'RS256' });
    expect(JSON.parse(Buffer.from(payload!, 'base64url').toString())).toMatchObject({ iss: account, aud: 'https://oauth2.googleapis.com/token', scope: 'https://www.googleapis.com/auth/firebase.messaging', iat: instant / 1000 });
    expect(await webcrypto.subtle.verify('RSASSA-PKCS1-v1_5', publicKey, Buffer.from(signature!, 'base64url'), Buffer.from(`${header}.${payload}`))).toBe(true);
  });
});

describe('held NTF SQL authorization, bounded I/O and factual finish', () => {
  it('sends once after authorization and uses only three public RPCs with redirects denied', async () => {
    const h = work(); await envelope(await h.handler(wake()), 200, null, { ...zero, reserved: 1, authorized: 1, accepted: 1 }, 'ready');
    expect(h.calls.map(call => new URL(call.url).pathname)).toEqual(['/token', `${rpc}reserve_push_attempts`, `${rpc}authorize_push_attempt`, '/v1/projects/samuraiapi-51996/messages:send', `${rpc}finish_push_attempt`]);
    for (const call of h.calls) expect(call.redirect).toBe('error');
    expect(await h.calls[2]!.json()).toEqual({ p_attempt_id: attemptId, p_reservation_id: reservationId });
    const sent = await h.calls[3]!.json(); expect(sent.message.token).toBe(authorization.token); expect(sent.message.notification).toEqual({ title: authorization.message.title, body: authorization.message.body });
    expect(sent.message.topic).toBeUndefined(); expect(sent.message.condition).toBeUndefined();
    expect(await h.calls[4]!.json()).toEqual({ p_attempt_id: attemptId, p_reservation_id: reservationId, p_provider_message_id: 'projects/samuraiapi-51996/messages/held-accepted', p_failure_code: null, p_uncertain: false });
  });
  it('negative current eligibility refuses without projecting token or sending', async () => {
    const h = work({ authorized: false, attemptId, reservationId, reason: 'consent_withdrawn', deferredUntil: null });
    await envelope(await h.handler(wake()), 200, null, { ...zero, reserved: 1, deferred: 1 }, 'ready'); expect(h.calls).toHaveLength(3);
  });
  it.each([{ ...authorization, attemptId: foreignId }, { ...authorization, reservationId: foreignId }, { ...authorization, expiresAt: '2026-10-04T06:00:00Z' }, { ...authorization, authorized: 'true' }, { ...authorization, token: null }])('cannot guess malformed/foreign/expired projection into send', async auth => {
    const h = work(auth); const response = await h.handler(wake()); expect(response.status).toBe(502);
    const text = await response.text(); expect(text).not.toContain(authorization.token); expect(text).not.toContain(attemptId);
    expect(h.calls.some(call => call.url.includes('messages:send'))).toBe(false);
  });
  it('unknown provider response finalizes uncertainty once and never retries', async () => {
    const h = work(authorization, new Error('held private provider detail')); const response = await h.handler(wake()); const data = await response.json();
    expect(data.counts).toEqual({ ...zero, reserved: 1, authorized: 1, uncertain: 1 });
    expect(h.calls.filter(call => call.url.includes('messages:send'))).toHaveLength(1);
    expect(await h.calls.at(-1)!.json()).toEqual({ p_attempt_id: attemptId, p_reservation_id: reservationId, p_provider_message_id: null, p_failure_code: null, p_uncertain: true });
    expect(JSON.stringify(data)).not.toContain('held private');
  });
  it('explicit rejection supplies failure facts without receipt claims', async () => {
    const h = work(authorization, Response.json({ error: { status: 'UNREGISTERED', details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'UNREGISTERED' }] } }, { status: 404 }));
    const data = await (await h.handler(wake())).json(); expect(data.counts).toEqual({ ...zero, reserved: 1, authorized: 1, failed: 1 });
    expect(await h.calls.at(-1)!.json()).toEqual({ p_attempt_id: attemptId, p_reservation_id: reservationId, p_provider_message_id: null, p_failure_code: 'UNREGISTERED', p_uncertain: false });
  });
  it('failed finish cannot be counted as finalized acceptance', async () => {
    const h = work(authorization, undefined, Response.json({ secret: authorization.token }, { status: 500 }));
    await envelope(await h.handler(wake()), 502, 'upstream_failed', { ...zero, reserved: 1, authorized: 1 }, 'ready'); expect(h.calls).toHaveLength(5);
  });
  it('exact inert finish replay is bounded and does not trigger another send', async () => {
    const h = work(authorization, undefined, { attemptId, replayed: true, notification });
    const result = await (await h.handler(wake())).json();
    expect(result.counts.accepted).toBe(1);
    expect(h.calls.filter(call => call.url.includes('messages:send'))).toHaveLength(1);
    expect(JSON.stringify(result)).not.toContain('deliveredAt');
  });
  it('a foreign finish projection is not successfully finalized', async () => {
    const h = work(authorization, undefined, { attemptId: foreignId, replayed: false, notification });
    await envelope(await h.handler(wake()), 502, 'upstream_failed', { ...zero, reserved: 1, authorized: 1 }, 'ready');
  });
  it('unconfigured SQL empty claim remains successful and stops before authorization', async () => {
    const h = harness({}, { [`${rpc}reserve_push_attempts`]: { attempts: [], configuration: 'provider_unconfigured' } });
    await envelope(await h.handler(wake()), 200, null, zero, 'provider_unconfigured'); expect(h.calls).toHaveLength(2);
  });
  it('provider authentication failure stops later reservations rather than consuming them', async () => {
    const h = harness({}, {
      [`${rpc}reserve_push_attempts`]: { attempts: [reservation, { attemptId: foreignId, reservationId: '78800000-0000-4000-8000-000000000005', expiresAt }], configuration: 'ready' },
      [`${rpc}authorize_push_attempt`]: authorization,
      '/v1/projects/samuraiapi-51996/messages:send': Response.json({ error: { status: 'UNAUTHENTICATED', message: 'held confidential auth detail' } }, { status: 401 }),
      [`${rpc}finish_push_attempt`]: { attemptId, replayed: false, notification },
    });
    const result = await (await h.handler(wake())).json();
    expect(result.ok).toBe(false);
    expect(h.calls.filter(call => call.url.endsWith('authorize_push_attempt'))).toHaveLength(1);
    expect(h.calls.filter(call => call.url.includes('messages:send'))).toHaveLength(1);
    expect(JSON.stringify(result)).not.toContain('held confidential');
  });
});

// Supplement derives only from provider-result-declaration.md, serial freeze 5a68e5ba.
describe('held NTF exact provider-result mechanics', () => {
  it.each(['2027-02-29T06:01:30Z', '2026-11-31T06:01:30Z', '2026-10-04T24:00:00Z'])('impossible claim calendar timestamp %s cannot be normalized into authorization', async impossible => {
    const h = harness({}, { [`${rpc}reserve_push_attempts`]: { attempts: [{ ...reservation, expiresAt: impossible }], configuration: 'ready' } });
    const response = await h.handler(wake()); expect(response.status).toBe(502);
    const result = await response.json(); expect(result.error).toBe('upstream_failed'); expect(result.counts.authorized).toBe(0);
    expect(h.calls).toHaveLength(2);
  });
  it.each(['2027-02-29T06:01:30Z', '2026-11-31T06:01:30Z', '2026-10-04T24:00:00Z'])('impossible authorization calendar timestamp %s cannot permit I/O', async impossible => {
    const h = work({ ...authorization, expiresAt: impossible });
    await envelope(await h.handler(wake()), 502, 'upstream_failed', { ...zero, reserved: 1 }, 'ready');
    expect(h.calls.some(call => call.url.includes('messages:send'))).toBe(false);
  });
  it.each(['2027-02-29T08:00:00Z', '2026-11-31T08:00:00Z', '2026-10-04T24:00:00Z'])('impossible deferred calendar timestamp %s cannot count a validated refusal', async impossible => {
    const h = work({ authorized: false, attemptId, reservationId, reason: 'quiet_hours', deferredUntil: impossible });
    await envelope(await h.handler(wake()), 502, 'upstream_failed', { ...zero, reserved: 1 }, 'ready');
    expect(h.calls.some(call => call.url.includes('messages:send'))).toBe(false);
  });
  it.each([
    ['2028-02-28T23:59:00Z', '2028-02-29T00:00:30Z'],
    ['2027-02-28T23:59:00Z', '2027-03-01T00:00:30Z'],
    ['2026-11-30T23:59:00Z', '2026-12-01T00:00:30Z'],
  ])('valid Gregorian rollover from %s to %s accepts its bounded lease', async (startedAt, expiry) => {
    const pair = { attemptId, reservationId, expiresAt: expiry };
    const h = harness({}, {
      [`${rpc}reserve_push_attempts`]: { attempts: [pair], configuration: 'ready' },
      [`${rpc}authorize_push_attempt`]: { ...authorization, ...pair },
      '/v1/projects/samuraiapi-51996/messages:send': { name: 'projects/samuraiapi-51996/messages/held-calendar-control' },
      [`${rpc}finish_push_attempt`]: { attemptId, replayed: false, notification },
    }, () => Date.parse(startedAt));
    await envelope(await h.handler(wake()), 200, null, { ...zero, reserved: 1, authorized: 1, accepted: 1 }, 'ready');
  });
  it('valid leap-day deferred timestamp counts refusal without sending', async () => {
    const h = work({ authorized: false, attemptId, reservationId, reason: 'quiet_hours', deferredUntil: '2028-02-29T08:00:00Z' });
    await envelope(await h.handler(wake()), 200, null, { ...zero, reserved: 1, deferred: 1 }, 'ready');
    expect(h.calls.some(call => call.url.includes('messages:send'))).toBe(false);
  });
  it('signed JWT has a strictly positive lifetime bounded by one hour', async () => {
    const h = harness(); await h.handler(wake());
    const form = new URLSearchParams(await h.calls[0]!.text());
    const payload = JSON.parse(Buffer.from(form.get('assertion')!.split('.')[1]!, 'base64url').toString());
    expect(Number.isInteger(payload.exp)).toBe(true);
    expect(payload.exp).toBeGreaterThan(payload.iat);
    expect(payload.exp - payload.iat).toBeLessThanOrEqual(3600);
  });
  it('canonical PostgreSQL UUID grouping requires no RFC version bits', async () => {
    const pair = { attemptId: '78800000-0000-0000-0000-000000000011', reservationId: '78800000-0000-0000-0000-000000000012', expiresAt };
    const h = harness({}, {
      [`${rpc}reserve_push_attempts`]: { attempts: [pair], configuration: 'ready' },
      [`${rpc}authorize_push_attempt`]: { ...authorization, ...pair },
      '/v1/projects/samuraiapi-51996/messages:send': { name: 'projects/samuraiapi-51996/messages/held-id' },
      [`${rpc}finish_push_attempt`]: { attemptId: pair.attemptId, replayed: false, notification },
    });
    await envelope(await h.handler(wake()), 200, null, { ...zero, reserved: 1, authorized: 1, accepted: 1 }, 'ready');
  });
  it.each([
    { access_token: 'held-oauth', token_type: 'bearer', expires_in: 3600 },
    { access_token: 'held-oauth', token_type: 'Bearer', expires_in: 0 },
    { access_token: 'held-oauth', token_type: 'Bearer', expires_in: 3601 },
    { access_token: 'held-oauth', token_type: 'Bearer', expires_in: 1.5 },
    { access_token: 'held-oauth', token_type: 'Bearer', expires_in: '3600' },
    { access_token: '   ', token_type: 'Bearer', expires_in: 1 },
    { access_token: 123, token_type: 'Bearer', expires_in: 1 },
  ])('rejects unusable OAuth success %j before claim', async reply => {
    const h = harness({}, { '/token': reply });
    await envelope(await h.handler(wake()), 502, 'upstream_failed'); expect(h.calls).toHaveLength(1);
  });
  it('token expires at request-start plus lifetime, even when OAuth response is delayed', async () => {
    let clock = instant;
    const h = harness({}, {
      '/token': () => { clock = instant + 1000; return { access_token: 'held-oauth', token_type: 'Bearer', expires_in: 1 }; },
      [`${rpc}reserve_push_attempts`]: { attempts: [reservation], configuration: 'ready' },
      [`${rpc}authorize_push_attempt`]: authorization,
    }, () => clock);
    const result = await (await h.handler(wake())).json();
    expect(result.ok).toBe(false);
    expect(h.calls.some(call => call.url.includes('messages:send'))).toBe(false);
  });
  it('expiration while SQL authorization is in flight cannot produce a provider send', async () => {
    let clock = instant;
    const h = harness({}, {
      '/token': { access_token: 'held-oauth', token_type: 'Bearer', expires_in: 1 },
      [`${rpc}reserve_push_attempts`]: { attempts: [reservation], configuration: 'ready' },
      [`${rpc}authorize_push_attempt`]: () => { clock = instant + 1000; return authorization; },
    }, () => clock);
    const result = await (await h.handler(wake())).json();
    expect(result.ok).toBe(false); expect(h.calls.some(call => call.url.includes('messages:send'))).toBe(false);
  });
  it.each(['0', '-1', '01', '+1', '1.0', '1e3', '9223372036854775808', 1, null])('rejects noncanonical or out-of-range SQL bigint revision %j', async tokenRevision => {
    const h = work({ ...authorization, tokenRevision });
    await envelope(await h.handler(wake()), 502, 'upstream_failed', { ...zero, reserved: 1 }, 'ready');
    expect(h.calls.some(call => call.url.includes('messages:send'))).toBe(false);
  });
  it.each(['1', '9223372036854775807'])('accepts canonical positive signed-bigint revision %s', async tokenRevision => {
    const h = work({ ...authorization, tokenRevision });
    await envelope(await h.handler(wake()), 200, null, { ...zero, reserved: 1, authorized: 1, accepted: 1 }, 'ready');
  });
  it.each([
    { attempts: [reservation, reservation], configuration: 'ready' },
    { attempts: [reservation, { ...reservation, attemptId: foreignId }], configuration: 'ready' },
    { attempts: [reservation, { ...reservation, reservationId: foreignId }], configuration: 'ready' },
    { attempts: [reservation], configuration: 'provider_unconfigured' },
    { attempts: [], configuration: 'ready', token: 'held-private-leak' },
    { attempts: [{ ...reservation, token: 'held-private-leak' }], configuration: 'ready' },
    { attempts: [{ ...reservation, expiresAt: '2026-10-04T06:00:00Z' }], configuration: 'ready' },
    { attempts: Array.from({ length: 101 }, (_, index) => ({ attemptId: `78800000-0000-0000-0000-${String(index + 1000).padStart(12, '0')}`, reservationId: `78800000-0000-0000-0001-${String(index + 1000).padStart(12, '0')}`, expiresAt })), configuration: 'ready' },
  ])('rejects duplicate, extra, expired or oversized claim without consuming work', async claim => {
    const h = harness({}, { [`${rpc}reserve_push_attempts`]: claim });
    const response = await h.handler(wake()); expect(response.status).toBe(502);
    const result = await response.json(); expect(result.error).toBe('upstream_failed');
    expect(result.counts.authorized).toBe(0); expect(JSON.stringify(result)).not.toContain('held-private-leak');
    expect(h.calls).toHaveLength(2);
  });
  it.each([
    { ...authorization, unexpected: 'held-private-leak' },
    { ...authorization, message: { ...authorization.message, unexpected: 'held-private-leak' } },
    { ...authorization, message: { ...authorization.message, data: { ...authorization.message.data, url: 'https://attacker.invalid' } } },
    { authorized: false, attemptId, reservationId, reason: 'consent_withdrawn', deferredUntil: null, token: 'held-private-leak' },
  ])('extra authorization fields fail before I/O', async auth => {
    const h = work(auth); await envelope(await h.handler(wake()), 502, 'upstream_failed', { ...zero, reserved: 1 }, 'ready');
    expect(h.calls.some(call => call.url.includes('messages:send'))).toBe(false);
  });
  it.each([
    { attemptId, replayed: false, notification, token: 'held-private-leak' },
    { attemptId, replayed: 'false', notification },
    { attemptId, replayed: false, notification: { ...notification, token: 'held-private-leak' } },
    { attemptId, replayed: false, notification: { ...notification, notificationId: attemptId } },
  ])('malformed or uncorrelated finish cannot count acceptance', async finish => {
    const h = work(authorization, undefined, finish);
    await envelope(await h.handler(wake()), 502, 'upstream_failed', { ...zero, reserved: 1, authorized: 1 }, 'ready');
  });
  it.each([
    {}, { name: '' }, { name: 123 },
    { name: 'projects/foreign/messages/held-id' },
    { name: 'projects/samuraiapi-51996/messages/' },
    { name: 'projects/samuraiapi-51996/messages/a/b' },
    { name: 'projects/samuraiapi-51996/messages/space id' },
    { name: 'projects/samuraiapi-51996/messages/control\u0001id' },
    { name: `projects/samuraiapi-51996/messages/${'a'.repeat(256)}` },
    new Response('not JSON', { status: 200 }),
  ])('malformed or foreign successful FCM reply finishes one uncertainty', async provider => {
    const h = work(authorization, provider);
    const result = await (await h.handler(wake())).json();
    expect(result.counts).toEqual({ ...zero, reserved: 1, authorized: 1, uncertain: 1 });
    expect(await h.calls.at(-1)!.json()).toEqual({ p_attempt_id: attemptId, p_reservation_id: reservationId, p_provider_message_id: null, p_failure_code: null, p_uncertain: true });
    expect(h.calls.filter(call => call.url.includes('messages:send'))).toHaveLength(1);
  });
  it('valid accepted name ignores unrelated provider metadata', async () => {
    const h = work(authorization, { name: 'projects/samuraiapi-51996/messages/held-id', metadata: { token: 'held-private-metadata' } });
    await envelope(await h.handler(wake()), 200, null, { ...zero, reserved: 1, authorized: 1, accepted: 1 }, 'ready');
  });
  it.each([401, 403])('provider HTTP%i records one factual rejection then returns configuration failure', async status => {
    const h = harness({}, {
      [`${rpc}reserve_push_attempts`]: { attempts: [reservation, { attemptId: foreignId, reservationId: '78800000-0000-4000-8000-000000000005', expiresAt }], configuration: 'ready' },
      [`${rpc}authorize_push_attempt`]: authorization,
      '/v1/projects/samuraiapi-51996/messages:send': Response.json({ error: { status: 'PERMISSION_DENIED', message: 'held-private-auth-detail' } }, { status }),
      [`${rpc}finish_push_attempt`]: { attemptId, replayed: false, notification },
    });
    await envelope(await h.handler(wake()), 503, 'configuration_invalid', { ...zero, reserved: 2, authorized: 1, failed: 1 }, 'ready');
    expect(h.calls.filter(call => call.url.endsWith('authorize_push_attempt'))).toHaveLength(1);
    expect(await h.calls.at(-1)!.json()).toEqual({ p_attempt_id: attemptId, p_reservation_id: reservationId, p_provider_message_id: null, p_failure_code: 'PERMISSION_DENIED', p_uncertain: false });
  });
});
