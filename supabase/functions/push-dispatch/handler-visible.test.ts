// Independent visible author: frozen NTF transport packet only; no implementation or other suites read.
import { test } from 'vitest';
import { createPushDispatchHandler, type PushDispatchDependencies } from './handler.ts';

function equal(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}
function check(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
const zero = { reserved: 0, authorized: 0, accepted: 0, failed: 0, uncertain: 0, deferred: 0 };
const instant = Date.parse('2026-10-04T10:00:00Z');
const account = 'fitcruxx-push-sender@samuraiapi-51996.iam.gserviceaccount.com';
const origin = 'https://pecxrpskmfeuyzngvewq.supabase.co';
const lease = { attemptId: '78000000-0000-4000-8000-000000000001', reservationId: '78000000-0000-4000-8000-000000000002', expiresAt: '2026-10-04T10:01:30Z' };
const authorization = { authorized: true, ...lease, token: 'TEST_ONLY_DEVICE_TOKEN', tokenRevision: '1', message: { title: 'Visible gym', body: 'You have an update. Open the app to view it.', data: { notificationId: '78000000-0000-4000-8000-000000000003', sourceNotificationId: null, relatedType: null, relatedId: null }, ttlSeconds: 60 } };
const notification = { notificationId: authorization.message.data.notificationId, memberId: '78000000-0000-4000-8000-000000000004', channel: 'push', status: 'sent', sentAt: '2026-10-04T10:00:00Z', deliveredAt: null, failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null };
type Call = { url: string; init: RequestInit; body: Record<string, unknown> };
async function fixture(options: { env?: Record<string, string | undefined>; claim?: unknown; authorize?: unknown; provider?: Response | Error; finish?: Response; oauth?: Response | Error; clock?: number | (() => number) } = {}) {
  const pair = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  const bytes = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  const key = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...bytes))}\n-----END PRIVATE KEY-----\n`;
  const environment: Record<string, string | undefined> = { SUPABASE_URL: origin, SUPABASE_SERVICE_ROLE_KEY: 'TEST_ONLY_SERVICE_KEY', PUSH_DISPATCH_SECRET: 'TEST_ONLY_WAKEUP_SECRET', FCM_PROJECT_ID: 'samuraiapi-51996', FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({ type: 'service_account', project_id: 'samuraiapi-51996', client_email: account, private_key: key, token_uri: 'https://evil.invalid/token' }), ...options.env };
  const calls: Call[] = [];
  const json = (value: unknown) => new Response(JSON.stringify(value), { headers: { 'Content-Type': 'application/json' } });
  const dependencies: PushDispatchDependencies = {
    readEnvironment: name => environment[name], now: () => typeof options.clock === 'function' ? options.clock() : options.clock ?? instant, crypto,
    fetch: async (input, init = {}) => {
      const url = input instanceof Request ? input.url : String(input);
      if (input instanceof Request) init = { method: input.method, headers: input.headers, redirect: input.redirect, body: await input.text(), ...init };
      const body = typeof init.body === 'string' && init.body.startsWith('{') ? JSON.parse(init.body) : {};
      calls.push({ url, init, body });
      check(init.redirect === 'error', 'All outbound requests must reject redirects');
      if (url === 'https://oauth2.googleapis.com/token') {
        if (options.oauth instanceof Error) throw options.oauth;
        return options.oauth ?? json({ access_token: 'TEST_ONLY_OAUTH', token_type: 'Bearer', expires_in: 3600 });
      }
      if (url === `${origin}/rest/v1/rpc/reserve_push_attempts`) return json(options.claim ?? { attempts: [lease], configuration: 'ready' });
      if (url === `${origin}/rest/v1/rpc/authorize_push_attempt`) return json(options.authorize ?? { ...authorization, attemptId: body.p_attempt_id, reservationId: body.p_reservation_id });
      if (url === `${origin}/rest/v1/rpc/finish_push_attempt`) return options.finish ?? json({ attemptId: body.p_attempt_id, replayed: false, notification: body.p_provider_message_id ? notification : { ...notification, status: 'failed', sentAt: null, failedAt: '2026-10-04T10:00:00Z', failedReason: body.p_uncertain ? 'delivery_unknown' : body.p_failure_code } });
      if (url === 'https://fcm.googleapis.com/v1/projects/samuraiapi-51996/messages:send') {
        if (options.provider instanceof Error) throw options.provider;
        return options.provider ?? json({ name: 'projects/samuraiapi-51996/messages/TEST_ONLY_MESSAGE' });
      }
      throw new Error('Unexpected outbound destination');
    },
  };
  const handler = createPushDispatchHandler(dependencies);
  equal(calls, []);
  return { handler, calls, environment };
}
function request(body = '{}', headers: Record<string, string> = {}, url = 'https://edge.invalid/functions/v1/push-dispatch', method = 'POST') {
  return new Request(url, { method, ...(method === 'GET' ? {} : { body }), headers: { 'Content-Type': 'application/json', 'x-gymloop-push-dispatch-secret': 'TEST_ONLY_WAKEUP_SECRET', ...headers } });
}
async function envelope(response: Response, status: number, error: string | null, configuration: string | null = null, counts = zero) {
  equal(response.status, status);
  check(response.headers.get('Content-Type')?.startsWith('application/json'), 'JSON response required');
  equal(response.headers.get('Cache-Control'), 'no-store');
  check(![...response.headers.keys()].some(name => name.startsWith('access-control-')), 'No CORS');
  equal(await response.json(), { ok: error === null, error, configuration, counts });
}

test('NTF transport: method and secret precede body and all I/O', async () => {
  for (const method of ['GET', 'OPTIONS', 'PUT']) {
    const f = await fixture(); const response = await f.handler(request('{}', {}, undefined, method));
    equal(response.headers.get('Allow'), 'POST'); await envelope(response, 405, 'method_not_allowed'); equal(f.calls, []);
  }
  for (const supplied of ['', 'TEST_ONLY_WAKEUP_SECRET_suffix', 'TEST_ONLY_WAKEUP_SECRE', 'test_only_wakeup_secret']) {
    const f = await fixture(); const r = request('{broken', { 'x-gymloop-push-dispatch-secret': supplied }); await envelope(await f.handler(r), 401, 'unauthorized'); check(!r.bodyUsed, 'Credential denial must not read body'); equal(f.calls, []);
  }
  const f = await fixture({ env: { PUSH_DISPATCH_SECRET: undefined } });
  await envelope(await f.handler(request()), 503, 'configuration_invalid'); equal(f.calls, []);
  const missing = await fixture(); const r = request(); r.headers.delete('x-gymloop-push-dispatch-secret'); r.headers.set('Authorization', 'Bearer TEST_ONLY_SERVICE_KEY');
  await envelope(await missing.handler(r), 401, 'unauthorized'); equal(missing.calls, []);
});
test('NTF transport: exact empty object, query, media and actual UTF-8 byte bound', async () => {
  for (const body of ['[]', 'null', '0', '""', '{"tenant_id":"foreign"}', '{broken']) {
    const f = await fixture(); await envelope(await f.handler(request(body)), 400, 'bad_request'); equal(f.calls, []);
  }
  for (const headers of [{ 'Content-Type': 'text/plain' }, { 'Content-Type': 'application/octet-stream' }]) {
    const f = await fixture(); await envelope(await f.handler(request('{}', headers)), 400, 'bad_request'); equal(f.calls, []);
  }
  const query = await fixture(); await envelope(await query.handler(request('{}', {}, 'https://edge.invalid/?tenant_id=foreign')), 400, 'bad_request'); equal(query.calls, []);
  for (const headers of [{}, { 'Content-Length': '2' }]) {
    const f = await fixture(); await envelope(await f.handler(request(' '.repeat(1023) + '{}', headers)), 413, 'payload_too_large'); equal(f.calls, []);
  }
  const edge = await fixture({ claim: { attempts: [], configuration: 'ready' } });
  await envelope(await edge.handler(request(' '.repeat(1022) + '{}', { 'Content-Type': 'application/json; charset=utf-8' })), 200, null, 'ready');
});
test('NTF transport: protected identity mismatch fails before credential transmission', async () => {
  for (const url of ['https://evil.invalid', `${origin}/path`, `${origin}?x=1`, `${origin}#x`, 'https://user:pass@pecxrpskmfeuyzngvewq.supabase.co']) {
    const f = await fixture({ env: { SUPABASE_URL: url } }); await envelope(await f.handler(request()), 503, 'configuration_invalid'); equal(f.calls, []);
  }
  for (const env of [{ FCM_PROJECT_ID: 'foreign' }, { FCM_SERVICE_ACCOUNT_JSON: '{broken' }, { SUPABASE_SERVICE_ROLE_KEY: undefined }]) {
    const f = await fixture({ env }); await envelope(await f.handler(request()), 503, 'configuration_invalid'); equal(f.calls, []);
  }
  const f = await fixture(); const json = JSON.parse(f.environment.FCM_SERVICE_ACCOUNT_JSON!); json.client_email = 'foreign@samuraiapi-51996.iam.gserviceaccount.com'; f.environment.FCM_SERVICE_ACCOUNT_JSON = JSON.stringify(json);
  await envelope(await f.handler(request()), 503, 'configuration_invalid'); equal(f.calls, []);
});
test('NTF transport: one fresh individual authorization, one send, factual acceptance and no receipt', async () => {
  const f = await fixture(); await envelope(await f.handler(request()), 200, null, 'ready', { ...zero, reserved: 1, authorized: 1, accepted: 1 });
  equal(f.calls.map(call => call.url), ['https://oauth2.googleapis.com/token', `${origin}/rest/v1/rpc/reserve_push_attempts`, `${origin}/rest/v1/rpc/authorize_push_attempt`, 'https://fcm.googleapis.com/v1/projects/samuraiapi-51996/messages:send', `${origin}/rest/v1/rpc/finish_push_attempt`]);
  equal(f.calls[2].body, { p_attempt_id: lease.attemptId, p_reservation_id: lease.reservationId });
  equal(f.calls[4].body, { p_attempt_id: lease.attemptId, p_reservation_id: lease.reservationId, p_provider_message_id: 'projects/samuraiapi-51996/messages/TEST_ONLY_MESSAGE', p_failure_code: null, p_uncertain: false });
  const oauthForm = new URLSearchParams(String(f.calls[0].init.body));
  equal(oauthForm.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');
  const assertion = oauthForm.get('assertion'); check(assertion, 'Signed OAuth assertion required');
  const segments = assertion.split('.'); equal(segments.length, 3);
  const decode = (segment: string) => JSON.parse(atob(segment.replaceAll('-', '+').replaceAll('_', '/')));
  equal(decode(segments[0]).alg, 'RS256');
  const claims = decode(segments[1]); equal(claims.iss, account); equal(claims.aud, 'https://oauth2.googleapis.com/token'); equal(claims.scope, 'https://www.googleapis.com/auth/firebase.messaging');
  check(Number.isInteger(claims.iat) && Number.isInteger(claims.exp) && claims.exp > claims.iat, 'Short-lived epoch claims');
  check(claims.exp - claims.iat <= 3600, 'Assertion lifetime does not exceed frozen bound');
  const send = f.calls[3]; const message = send.body.message as Record<string, unknown>; equal(message.token, authorization.token); check(!('topic' in message) && !('condition' in message), 'Individual token only');
  for (const call of f.calls) {
    const h = new Headers(call.init.headers); if (!call.url.startsWith(origin)) check(!JSON.stringify([...h]).includes('TEST_ONLY_SERVICE_KEY'), 'Service key confined to SQL');
  }
});
test('NTF transport: refusal/expiry cannot become send permission', async () => {
  const f = await fixture({ authorize: { authorized: false, ...lease, reason: 'consent', deferredUntil: null } });
  await envelope(await f.handler(request()), 200, null, 'ready', { ...zero, reserved: 1, deferred: 1 });
  check(!f.calls.some(call => call.url.includes('messages:send') || call.url.endsWith('finish_push_attempt')), 'Refusal cannot send/finalize');
  const expired = await fixture({ authorize: { ...authorization, expiresAt: '2026-10-04T10:00:00Z' } }); await expired.handler(request());
  check(!expired.calls.some(call => call.url.includes('messages:send')), 'Expiry equality is expired');
});
test('NTF transport: known failure versus lost/malformed response, no retries or invalidation RPC', async () => {
  for (const scenario of [
    { provider: new Response(JSON.stringify({ error: { status: 'UNREGISTERED', details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'UNREGISTERED' }] } }), { status: 404 }), failure: 'UNREGISTERED', uncertain: false },
    { provider: new Response(JSON.stringify({ error: { status: 'INVALID_ARGUMENT', details: [] } }), { status: 400 }), failure: 'INVALID_ARGUMENT', uncertain: false },
    { provider: new Error('TEST_ONLY_LOST_RESPONSE'), failure: null, uncertain: true },
    { provider: new Response('not-json', { status: 200 }), failure: null, uncertain: true },
  ]) {
    const f = await fixture(scenario); await envelope(await f.handler(request()), 200, null, 'ready', { ...zero, reserved: 1, authorized: 1, ...(scenario.uncertain ? { uncertain: 1 } : { failed: 1 }) }); const finishes = f.calls.filter(call => call.url.endsWith('finish_push_attempt'));
    equal(finishes.length, 1); equal(finishes[0].body.p_failure_code, scenario.failure); equal(finishes[0].body.p_uncertain, scenario.uncertain); equal(finishes[0].body.p_provider_message_id, null);
    equal(f.calls.filter(call => call.url.includes('messages:send')).length, 1);
    check(f.calls.every(call => !call.url.includes('invalidate') && !call.url.includes('acknowledge')), 'SQL owns revision invalidation and receipts');
  }
});
test('NTF transport: empty unconfigured claim and failed finish preserve factual counts', async () => {
  const inert = await fixture({ claim: { attempts: [], configuration: 'provider_unconfigured' } }); await envelope(await inert.handler(request()), 200, null, 'provider_unconfigured'); equal(inert.calls.length, 2);
  const failed = await fixture({ finish: new Response('TEST_ONLY_PRIVATE_UPSTREAM', { status: 500 }) });
  await envelope(await failed.handler(request()), 502, 'upstream_failed', 'ready', { ...zero, reserved: 1, authorized: 1 });
  const stop = await fixture({ oauth: new Response('TEST_ONLY_PRIVATE_AUTH_ERROR', { status: 500 }) }); const response = await stop.handler(request());
  await envelope(response.clone(), 502, 'upstream_failed'); equal(stop.calls.length, 1);
  const text = await response.text(); check(!text.includes('TEST_ONLY_PRIVATE') && !text.includes('TEST_ONLY_SERVICE_KEY'), 'No upstream or credential leakage');
});
test('NTF transport: each individual send requires its own immediately preceding authorization', async () => {
  const second = { ...lease, attemptId: '78000000-0000-4000-8000-000000000005', reservationId: '78000000-0000-4000-8000-000000000006' };
  const f = await fixture({ claim: { attempts: [lease, second], configuration: 'ready' } });
  await envelope(await f.handler(request()), 200, null, 'ready', { ...zero, reserved: 2, authorized: 2, accepted: 2 });
  const sends = f.calls.filter(call => call.url.includes('messages:send')); equal(sends.length, 2);
  for (const send of sends) equal(f.calls[f.calls.indexOf(send) - 1].url, `${origin}/rest/v1/rpc/authorize_push_attempt`);
  equal(f.calls.filter(call => call.url.endsWith('authorize_push_attempt')).map(call => call.body), [lease, second].map(item => ({ p_attempt_id: item.attemptId, p_reservation_id: item.reservationId })));
  equal(f.calls.filter(call => call.url.endsWith('reserve_push_attempts')).length, 1);
});


test('NTF readiness declaration: OAuth credential refusals stop before SQL claim', async () => {
  for (const oauth of [
    new Response('TEST_ONLY_PRIVATE_OAUTH', { status: 401 }),
    new Response('TEST_ONLY_PRIVATE_OAUTH', { status: 403 }),
    new Response(JSON.stringify({ error: 'invalid_grant' }), { status: 400 }),
    new Response(JSON.stringify({ error: 'invalid_client' }), { status: 400 }),
  ]) {
    const f = await fixture({ oauth });
    await envelope(await f.handler(request()), 503, 'configuration_invalid');
    equal(f.calls.map(call => call.url), ['https://oauth2.googleapis.com/token']);
  }
});

test('NTF readiness declaration: OAuth transient and unusable results stop before SQL claim', async () => {
  for (const oauth of [
    new Error('TEST_ONLY_PRIVATE_NETWORK_FAILURE'),
    new Response('TEST_ONLY_PRIVATE_OAUTH', { status: 500 }),
    new Response('TEST_ONLY_PRIVATE_OAUTH', { status: 503 }),
    new Response(JSON.stringify({ error: 'temporarily_unavailable' }), { status: 400 }),
    new Response('not-json', { status: 200 }),
    new Response(JSON.stringify({}), { status: 200 }),
    new Response(JSON.stringify({ access_token: '', token_type: 'Bearer', expires_in: 3600 }), { status: 200 }),
  ]) {
    const f = await fixture({ oauth });
    await envelope(await f.handler(request()), 502, 'upstream_failed');
    equal(f.calls.map(call => call.url), ['https://oauth2.googleapis.com/token']);
  }
});

test('NTF readiness declaration: unusable private key fails without I/O', async () => {
  const f = await fixture();
  const configured = JSON.parse(f.environment.FCM_SERVICE_ACCOUNT_JSON!);
  configured.private_key = 'TEST_ONLY_INVALID_PRIVATE_KEY';
  f.environment.FCM_SERVICE_ACCOUNT_JSON = JSON.stringify(configured);
  await envelope(await f.handler(request()), 503, 'configuration_invalid');
  equal(f.calls, []);
});

test('NTF provider declaration: exact OAuth lifetime and type before claim', async () => {
  for (const expires_in of [1, 3600]) {
    const f = await fixture({ oauth: new Response(JSON.stringify({ access_token: 'TEST_ONLY_OAUTH', token_type: 'Bearer', expires_in })), claim: { attempts: [], configuration: 'ready' } });
    await envelope(await f.handler(request()), 200, null, 'ready');
  }
  for (const value of [
    ...[0, -1, 3601, 1.5, '3600', null].map(expires_in => ({ access_token: 'TEST_ONLY_OAUTH', token_type: 'Bearer', expires_in })),
    { access_token: '   ', token_type: 'Bearer', expires_in: 3600 },
    { access_token: 'TEST_ONLY_OAUTH', token_type: 'bearer', expires_in: 3600 },
  ]) {
    const f = await fixture({ oauth: new Response(JSON.stringify(value)) });
    await envelope(await f.handler(request()), 502, 'upstream_failed'); equal(f.calls.length, 1);
  }
});

test('NTF provider declaration: OAuth expiry cannot authorize a provider send', async () => {
  let reads = 0;
  const f = await fixture({ oauth: new Response(JSON.stringify({ access_token: 'TEST_ONLY_OAUTH', token_type: 'Bearer', expires_in: 1 })), clock: () => reads++ === 0 ? instant : Date.parse('2026-10-04T10:00:01Z') });
  await f.handler(request());
  check(!f.calls.some(call => call.url.includes('messages:send')), 'Expiry equality forbids send');
  equal(f.calls.filter(call => call.url === 'https://oauth2.googleapis.com/token').length, 1);
});

test('NTF provider declaration: invalid or duplicate claims do no individual work', async () => {
  for (const claim of [
    { attempts: [], configuration: 'ready', extra: true },
    { attempts: [{ ...lease, extra: true }], configuration: 'ready' },
    { attempts: [{ ...lease, expiresAt: 'not-a-date' }], configuration: 'ready' },
    { attempts: [{ ...lease, expiresAt: '2026-10-04T10:00:00Z' }], configuration: 'ready' },
    { attempts: [lease, { ...lease, reservationId: '78000000-0000-4000-8000-000000000008' }], configuration: 'ready' },
    { attempts: [lease, { ...lease, attemptId: '78000000-0000-4000-8000-000000000008' }], configuration: 'ready' },
    { attempts: Array.from({ length: 101 }, (_, index) => ({ ...lease, attemptId: '78000000-0000-0000-0000-' + String(index + 1).padStart(12, '0'), reservationId: '78000000-0000-0000-0001-' + String(index + 1).padStart(12, '0') })), configuration: 'ready' },
    { attempts: [lease], configuration: 'provider_unconfigured' },
  ]) {
    const f = await fixture({ claim }); equal((await f.handler(request())).status, 502);
    check(!f.calls.some(call => call.url.endsWith('authorize_push_attempt') || call.url.includes('messages:send') || call.url.endsWith('finish_push_attempt')), 'Invalid claim cannot start work');
  }
});

test('NTF provider declaration: 100 canonical UUID leases accept non-RFC version grouping', async () => {
  const attempts = Array.from({ length: 100 }, (_, index) => ({ ...lease, attemptId: '78000000-0000-0000-0000-' + String(index + 1).padStart(12, '0'), reservationId: '78000000-0000-0000-0001-' + String(index + 1).padStart(12, '0') }));
  const f = await fixture({ claim: { attempts, configuration: 'ready' } });
  await envelope(await f.handler(request()), 200, null, 'ready', { ...zero, reserved: 100, authorized: 100, accepted: 100 });
  equal(f.calls.filter(call => call.url.includes('messages:send')).length, 100);
});

test('NTF provider declaration: bigint revision is canonical signed-bigint positive text', async () => {
  for (const tokenRevision of ['1', '9223372036854775807']) {
    const f = await fixture({ authorize: { ...authorization, tokenRevision } });
    await envelope(await f.handler(request()), 200, null, 'ready', { ...zero, reserved: 1, authorized: 1, accepted: 1 });
  }
  for (const tokenRevision of [1, '0', '-1', '01', '+1', '1.0', ' 1', '9223372036854775808']) {
    const f = await fixture({ authorize: { ...authorization, tokenRevision } });
    await envelope(await f.handler(request()), 502, 'upstream_failed', 'ready', { ...zero, reserved: 1 });
    check(!f.calls.some(call => call.url.includes('messages:send')), 'Invalid revision is not authority');
  }
});

test('NTF provider declaration: invalid authorization and finish preserve validated facts', async () => {
  for (const authorize of [
    { ...authorization, extra: true }, { ...authorization, attemptId: '78000000-0000-4000-8000-000000000009' },
    { ...authorization, reservationId: '78000000-0000-4000-8000-000000000009' },
    { ...authorization, message: { ...authorization.message, extra: true } },
  ]) {
    const f = await fixture({ authorize });
    await envelope(await f.handler(request()), 502, 'upstream_failed', 'ready', { ...zero, reserved: 1 });
    check(!f.calls.some(call => call.url.includes('messages:send') || call.url.endsWith('finish_push_attempt')), 'Invalid authorization cannot dispatch');
  }
  for (const finish of [
    { attemptId: lease.attemptId, replayed: false, notification, extra: true },
    { attemptId: '78000000-0000-4000-8000-000000000009', replayed: false, notification },
    { attemptId: lease.attemptId, replayed: 'false', notification },
    { attemptId: lease.attemptId, replayed: false, notification: { ...notification, extra: true } },
    { attemptId: lease.attemptId, replayed: false, notification: { ...notification, notificationId: '78000000-0000-4000-8000-000000000009' } },
  ]) {
    const f = await fixture({ finish: new Response(JSON.stringify(finish)) });
    await envelope(await f.handler(request()), 502, 'upstream_failed', 'ready', { ...zero, reserved: 1, authorized: 1 });
  }
  const replay = await fixture({ finish: new Response(JSON.stringify({ attemptId: lease.attemptId, replayed: true, notification })) });
  await envelope(await replay.handler(request()), 200, null, 'ready', { ...zero, reserved: 1, authorized: 1, accepted: 1 });
});

test('NTF provider declaration: acceptance name confinement and one uncertainty finish', async () => {
  for (const name of [null, '', 'projects/foreign/messages/id', 'projects/samuraiapi-51996/messages/', 'projects/samuraiapi-51996/messages/a/b', 'projects/samuraiapi-51996/messages/a b', 'projects/samuraiapi-51996/messages/a\n', 'projects/samuraiapi-51996/messages/' + 'x'.repeat(256)]) {
    const f = await fixture({ provider: new Response(JSON.stringify({ name })) });
    await envelope(await f.handler(request()), 200, null, 'ready', { ...zero, reserved: 1, authorized: 1, uncertain: 1 });
    const finishes = f.calls.filter(call => call.url.endsWith('finish_push_attempt'));
    equal(finishes.length, 1); equal(finishes[0].body.p_uncertain, true); equal(finishes[0].body.p_provider_message_id, null);
    equal(f.calls.filter(call => call.url.includes('messages:send')).length, 1);
  }
  const f = await fixture({ provider: new Response(JSON.stringify({ name: 'projects/samuraiapi-51996/messages/TEST_ONLY_MESSAGE', metadata: 'TEST_ONLY_PRIVATE_METADATA' })) });
  await envelope(await f.handler(request()), 200, null, 'ready', { ...zero, reserved: 1, authorized: 1, accepted: 1 });
});

test('NTF provider declaration: provider401/403 finish refusal then stop before next authorization', async () => {
  const second = { ...lease, attemptId: '78000000-0000-4000-8000-000000000005', reservationId: '78000000-0000-4000-8000-000000000006' };
  for (const status of [401, 403]) {
    const f = await fixture({ claim: { attempts: [lease, second], configuration: 'ready' }, provider: new Response(JSON.stringify({ error: { status: 'PERMISSION_DENIED', message: 'TEST_ONLY_PRIVATE_MESSAGE', details: [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode: 'THIRD_PARTY_AUTH_ERROR' }] } }), { status }) });
    await envelope(await f.handler(request()), 503, 'configuration_invalid', 'ready', { ...zero, reserved: 2, authorized: 1, failed: 1 });
    equal(f.calls.filter(call => call.url.endsWith('authorize_push_attempt')).length, 1);
    const finishes = f.calls.filter(call => call.url.endsWith('finish_push_attempt')); equal(finishes.length, 1);
    equal(finishes[0].body.p_failure_code, 'THIRD_PARTY_AUTH_ERROR'); equal(finishes[0].body.p_uncertain, false);
  }
});

test('NTF provider declaration: error debug text and untyped details cannot establish rejection code', async () => {
  const f = await fixture({ provider: new Response(JSON.stringify({ error: { message: 'UNREGISTERED', details: [{ errorCode: 'UNREGISTERED' }] } }), { status: 400 }) });
  await envelope(await f.handler(request()), 200, null, 'ready', { ...zero, reserved: 1, authorized: 1, uncertain: 1 });
  const finishes = f.calls.filter(call => call.url.endsWith('finish_push_attempt'));
  equal(finishes.length, 1); equal(finishes[0].body.p_failure_code, null); equal(finishes[0].body.p_uncertain, true);
});
