import { pushDispatchEnv } from '../../../packages/shared/src/config/env.ts';
import { Constants } from '../../../packages/db/types/database.ts';
import { PUSH_DISPATCH_RUNTIME as R, PUSH_DISPATCH_HTTP_STATUS as STATUS, PUSH_WORKER_BATCH_SIZE, PUSH_TOKEN_MAX_CHARS, PUSH_PROVIDER_MESSAGE_ID_MAX_CHARS, PUSH_FAILURE_CODE_MAX_CHARS, POSTGRES_BIGINT_MAX } from '../../../packages/shared/src/config/constants.ts';

export interface PushDispatchDependencies {
  readEnvironment(name: string): string | undefined;
  fetch: typeof globalThis.fetch;
  now(): number;
  crypto: Crypto;
}
type Row = Record<string, unknown>;
type ErrorCode = Exclude<keyof typeof STATUS, 'ok'>;
type Lease = { attemptId: string; reservationId: string; expiresAt: string };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
function row(value: unknown): value is Row { return typeof value === 'object' && value !== null && !Array.isArray(value); }
function exact(value: unknown, keys: string): value is Row { return row(value) && Object.keys(value).sort().join(',') === keys.split(',').sort().join(','); }
function uuid(value: unknown): value is string { return typeof value === 'string' && UUID.test(value); }
function nonblank(value: unknown, max = Infinity): value is string { return typeof value === 'string' && !!value.trim() && value.length <= max; }
function instant(value: unknown): value is string {
  if (typeof value !== 'string') return false;
  const parts = /^(\d{4}-\d{2}-\d{2})T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$/.exec(value);
  if (!parts) return false;
  // Compare the supplied civil date before applying its offset. A parsed
  // February 30 otherwise silently rolls into March and grants a lease.
  const civilMidnight = Date.parse(`${parts[1]}T00:00:00Z`);
  return Number.isFinite(civilMidnight) && new Date(civilMidnight).toISOString().split('T')[0] === parts[1] && Number.isFinite(Date.parse(value));
}
function lease(value: unknown, now: number): value is Lease { return exact(value, 'attemptId,reservationId,expiresAt') && uuid(value.attemptId) && uuid(value.reservationId) && instant(value.expiresAt) && Date.parse(value.expiresAt) > now; }
function base64url(bytes: Uint8Array): string { return btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join('')).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', ''); }
function encoded(value: unknown): string { return base64url(new TextEncoder().encode(JSON.stringify(value))); }
class Refusal extends Error { constructor(readonly code: ErrorCode) { super(code); } }
function refuse(code: ErrorCode): never { throw new Refusal(code); }
function requireProjection(condition: unknown): asserts condition { if (!condition) refuse('upstream_failed'); }
function notification(value: unknown, expectedId: unknown): boolean {
  if (!exact(value, 'notificationId,memberId,channel,status,sentAt,deliveredAt,failedAt,failedReason,optedOutAt,optedOutReason')) return false;
  return uuid(value.notificationId) && value.notificationId === expectedId && uuid(value.memberId) && value.channel === 'push' &&
    Constants.public.Enums.notification_status.some(status => status === value.status) &&
    ['sentAt', 'deliveredAt', 'failedAt', 'optedOutAt'].every(key => value[key] === null || instant(value[key])) &&
    ['failedReason', 'optedOutReason'].every(key => value[key] === null || nonblank(value[key]));
}

export function createPushDispatchHandler(dependencies: PushDispatchDependencies): (request: Request) => Promise<Response> {
  return async request => {
    const counts = { reserved: 0, authorized: 0, accepted: 0, failed: 0, uncertain: 0, deferred: 0 };
    let configuration: 'ready' | 'provider_unconfigured' | null = null;
    const response = (error: ErrorCode | null): Response => new Response(JSON.stringify({ ok: error === null, error, configuration, counts }), {
      status: STATUS[error ?? 'ok'], headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...(error === 'method_not_allowed' ? { Allow: 'POST' } : {}) },
    });
    try {
      if (request.method !== 'POST') refuse('method_not_allowed');
      const secret = dependencies.readEnvironment('PUSH_DISPATCH_SECRET');
      if (!nonblank(secret)) refuse('configuration_invalid');
      const supplied = request.headers.get('x-gymloop-push-dispatch-secret');
      if (supplied === null) refuse('unauthorized');
      const [expectedDigest, suppliedDigest] = await Promise.all([secret, supplied].map(async value => new Uint8Array(await dependencies.crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))));
      let difference = 0;
      for (let index = 0; index < R.digestBytes; index++) difference |= expectedDigest[index] ^ suppliedDigest[index];
      if (difference !== 0) refuse('unauthorized');
      if (new URL(request.url).search || !/^application\/json(?:\s*;\s*charset\s*=\s*(?:utf-8|"utf-8"))?\s*$/i.test(request.headers.get('Content-Type') ?? '')) refuse('bad_request');
      const reader = request.body?.getReader();
      const chunks: Uint8Array[] = [];
      let length = 0;
      if (reader) {
        while (true) {
          const next = await reader.read();
          if (next.done) break;
          length += next.value.byteLength;
          if (length > R.bodyBytes) { await reader.cancel(); refuse('payload_too_large'); }
          chunks.push(next.value);
        }
      }
      const bytes = new Uint8Array(length);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
      try { if (!exact(JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)), '')) refuse('bad_request'); }
      catch { refuse('bad_request'); }
      let config: ReturnType<typeof pushDispatchEnv>;
      let account: Row;
      let signingKey: CryptoKey;
      try {
        config = pushDispatchEnv(dependencies.readEnvironment);
        if (config.SUPABASE_URL !== R.supabaseOrigin || config.FCM_PROJECT_ID !== R.project) refuse('configuration_invalid');
        const parsed: unknown = JSON.parse(config.FCM_SERVICE_ACCOUNT_JSON);
        if (!row(parsed) || parsed.type !== 'service_account' || parsed.project_id !== R.project || parsed.client_email !== R.account || !nonblank(parsed.private_key)) refuse('configuration_invalid');
        account = parsed;
        const match = /^-----BEGIN PRIVATE KEY-----\s+([A-Za-z0-9+/=\s]+)\s*-----END PRIVATE KEY-----\s*$/.exec(parsed.private_key as string);
        if (!match) refuse('configuration_invalid');
        const keyBytes = Uint8Array.from(atob(match[1].replace(/\s/g, '')), value => value.charCodeAt(0));
        signingKey = await dependencies.crypto.subtle.importKey('pkcs8', keyBytes, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
      } catch { refuse('configuration_invalid'); }
      const oauthStarted = dependencies.now();
      const issued = Math.floor(oauthStarted / R.millisecondsPerSecond);
      const unsigned = `${encoded({ alg: 'RS256', typ: 'JWT', ...(nonblank(account.private_key_id) ? { kid: account.private_key_id } : {}) })}.${encoded({ iss: R.account, scope: R.scope, aud: R.oauthUrl, iat: issued, exp: issued + R.oauthSeconds })}`;
      const signature = await dependencies.crypto.subtle.sign('RSASSA-PKCS1-v1_5', signingKey, new TextEncoder().encode(unsigned));
      const oauth = await dependencies.fetch(R.oauthUrl, { method: 'POST', redirect: 'error', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${base64url(new Uint8Array(signature))}` }).toString() });
      const oauthData: unknown = await oauth.json().catch(() => null);
      if (oauth.status === STATUS.unauthorized || oauth.status === R.forbiddenStatus || (row(oauthData) && ['invalid_grant', 'invalid_client'].includes(String(oauthData.error)))) refuse('configuration_invalid');
      requireProjection(oauth.ok && row(oauthData) && nonblank(oauthData.access_token) && oauthData.token_type === 'Bearer' && Number.isInteger(oauthData.expires_in) && (oauthData.expires_in as number) >= 1 && (oauthData.expires_in as number) <= R.oauthSeconds);
      const oauthExpires = oauthStarted + (oauthData.expires_in as number) * R.millisecondsPerSecond;
      const rpc = async (name: 'reserve_push_attempts' | 'authorize_push_attempt' | 'finish_push_attempt', body: Row): Promise<unknown> => {
        const result = await dependencies.fetch(`${R.supabaseOrigin}/rest/v1/rpc/${name}`, { method: 'POST', redirect: 'error', headers: { 'Content-Type': 'application/json', apikey: config.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${config.SUPABASE_SERVICE_ROLE_KEY}` }, body: JSON.stringify(body) });
        requireProjection(result.ok);
        return result.json();
      };
      requireProjection(dependencies.now() < oauthExpires);
      const claim = await rpc('reserve_push_attempts', { p_limit: PUSH_WORKER_BATCH_SIZE });
      requireProjection(exact(claim, 'attempts,configuration') && ['ready', 'provider_unconfigured'].includes(String(claim.configuration)) && Array.isArray(claim.attempts) && claim.attempts.length <= PUSH_WORKER_BATCH_SIZE);
      const attempts = claim.attempts as unknown[];
      requireProjection((claim.configuration === 'ready' || attempts.length === 0) && attempts.every(value => lease(value, dependencies.now())));
      requireProjection(new Set(attempts.map(value => (value as Lease).attemptId)).size === attempts.length && new Set(attempts.map(value => (value as Lease).reservationId)).size === attempts.length);
      configuration = claim.configuration as typeof configuration;
      counts.reserved = attempts.length;
      for (const attempt of attempts as Lease[]) {
        requireProjection(dependencies.now() < oauthExpires && Date.parse(attempt.expiresAt) > dependencies.now());
        const authorized = await rpc('authorize_push_attempt', { p_attempt_id: attempt.attemptId, p_reservation_id: attempt.reservationId });
        requireProjection(row(authorized) && authorized.attemptId === attempt.attemptId && authorized.reservationId === attempt.reservationId);
        if (authorized.authorized === false) {
          requireProjection(exact(authorized, 'authorized,attemptId,reservationId,reason,deferredUntil') && nonblank(authorized.reason) && (authorized.deferredUntil === null || instant(authorized.deferredUntil)));
          counts.deferred++;
          continue;
        }
        requireProjection(exact(authorized, 'authorized,attemptId,reservationId,expiresAt,token,tokenRevision,message') && authorized.authorized === true && instant(authorized.expiresAt) && Date.parse(authorized.expiresAt) > dependencies.now() && nonblank(authorized.token, PUSH_TOKEN_MAX_CHARS) && typeof authorized.tokenRevision === 'string' && /^[1-9]\d*$/.test(authorized.tokenRevision) && BigInt(authorized.tokenRevision) <= POSTGRES_BIGINT_MAX);
        const message = authorized.message;
        requireProjection(exact(message, 'title,body,data,ttlSeconds') && nonblank(message.title) && message.body === R.genericBody && Number.isSafeInteger(message.ttlSeconds) && (message.ttlSeconds as number) >= 1);
        const data = message.data;
        requireProjection(exact(data, 'notificationId,sourceNotificationId,relatedType,relatedId') && uuid(data.notificationId) && (data.sourceNotificationId === null || uuid(data.sourceNotificationId)) && (data.relatedId === null || uuid(data.relatedId)) && (data.relatedType === null || ['membership', 'no_show_case', 'class_session', 'announcement'].includes(String(data.relatedType))));
        counts.authorized++;
        requireProjection(dependencies.now() < oauthExpires && Date.parse(authorized.expiresAt) > dependencies.now());
        let providerId: string | null = null;
        let failure: string | null = null;
        let providerAuthFailed = false;
        try {
          const provider = await dependencies.fetch(R.fcmUrl, { method: 'POST', redirect: 'error', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${oauthData.access_token}` }, body: JSON.stringify({ message: { token: authorized.token, notification: { title: message.title, body: message.body }, data: Object.fromEntries(Object.entries(data).filter(([, value]) => value !== null)), android: { ttl: `${message.ttlSeconds}s` } } }) });
          providerAuthFailed = provider.status === STATUS.unauthorized || provider.status === R.forbiddenStatus;
          const result: unknown = await provider.json().catch(() => null);
          if (provider.ok) {
            if (row(result) && nonblank(result.name, PUSH_PROVIDER_MESSAGE_ID_MAX_CHARS) && /^projects\/samuraiapi-51996\/messages\/[^/\s]+$/.test(result.name) && !Array.from(result.name).some(character => character.charCodeAt(0) < R.controlCharacterLimit || character.charCodeAt(0) === R.deleteCharacter)) providerId = result.name;
          } else if (row(result) && row(result.error)) {
            const error = result.error;
            const detail = Array.isArray(error.details) ? error.details.find(value => row(value) && value['@type'] === 'type.googleapis.com/google.firebase.fcm.v1.FcmError' && nonblank(value.errorCode, PUSH_FAILURE_CODE_MAX_CHARS)) : undefined;
            const code = row(detail) ? detail.errorCode : error.status;
            if (nonblank(code, PUSH_FAILURE_CODE_MAX_CHARS)) failure = code;
          }
        } catch { /* A lost response is uncertainty, never proof of rejection. */ }
        const uncertain = providerId === null && failure === null;
        const finished = await rpc('finish_push_attempt', { p_attempt_id: attempt.attemptId, p_reservation_id: attempt.reservationId, p_provider_message_id: providerId, p_failure_code: failure, p_uncertain: uncertain });
        requireProjection(exact(finished, 'attemptId,replayed,notification') && finished.attemptId === attempt.attemptId && typeof finished.replayed === 'boolean' && notification(finished.notification, data.notificationId));
        if (providerId !== null) counts.accepted++;
        else if (uncertain) counts.uncertain++;
        else counts.failed++;
        if (providerAuthFailed) refuse('configuration_invalid');
      }
      return response(null);
    } catch (error) { return response(error instanceof Refusal ? error.code : 'upstream_failed'); }
  };
}
