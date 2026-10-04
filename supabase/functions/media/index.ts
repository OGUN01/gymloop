import { createHash } from 'node:crypto';
import { BUY_LIMITS, MEDIA_LIMITS, MEDIA_IMAGE_SIGNATURES, MEDIA_RUNTIME_LIMITS, MEDIA_HTTP_STATUS } from '../../../packages/shared/src/config/constants.ts';

declare const Deno: { env: { get(name: string): string | undefined }; serve(handler: (request: Request) => Promise<Response>): void };

// Auth/REST follow the existing Edge transport. Only Auth-verified token claims
// determine identity; private REST credentials never leave this runtime.
const STATUS = MEDIA_HTTP_STATUS;
type Refusal = Exclude<keyof typeof STATUS, 'ok' | 'partialContent' | 'preconditionFailed'>;
const COPY = {
  invalid_request: 'Choose a valid photo and try again.', not_permitted: 'This account cannot perform this photo action.',
  asset_not_found: 'That photo is no longer available. Choose it again.', upload_missing: "The photo didn't arrive. Choose it again and retry.",
  upload_changed: 'The photo changed while it was being checked. Choose it again and retry.', upload_rejected: "That file isn't a photo we can use. Choose a JPEG, PNG or WebP image under 2 MB.",
  storage_unavailable: "Photo storage isn't available right now. Try again in a few minutes.", media_not_ready: 'That photo is no longer available. Choose it again.', media_in_use: 'That photo is already in use.', media_failed: "That photo couldn't be saved. Try again.",
} as const;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const KEY = /^([0-9a-f-]+)\/(staging|published)\/(product|trainer|announcement|payment_proof)\/([0-9a-f-]+)\.(jpg|png|webp)$/;
const SAFE = 'id,tenant_id,kind,mime,bytes,created_by_staff_id,created_at,confirmed_at,deleted_at,attached_to_id';
// The member creator is service-only: the authenticated grant does not carry
// the column, so naming it in a caller-scoped read would fail at runtime.
const PRIVATE = `${SAFE},staging_object_key,object_key,verified_source_etag,published_etag,created_by_member_id,linked_request_id`;
type Row = Record<string, unknown>;
type Actor = { userId: string; tenantId: string; staffId?: string; memberId?: string; previewId?: string; role: string; preview: boolean };
type Config = { url: string; anon: string; service: string; endpoint: string; bucket: string; key: string; secret: string };
class Refused extends Error { constructor(readonly code: Refusal) { super(code); } }
function reject(code: Refusal): never { throw new Refused(code); }
function json(data: unknown, status: number = STATUS.ok): Response { return new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } }); }
function refusal(code: Refusal): Response { return json({ ok: false, error: { code, message: COPY[code] } }, STATUS[code]); }
function uuid(value: unknown): value is string { return typeof value === 'string' && UUID.test(value); }
function config(): Config {
  const values = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'R2_ENDPOINT', 'R2_BUCKET', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY'].map(name => Deno.env.get(name));
  if (values.some(value => !value)) reject('storage_unavailable');
  const [url, anon, service, endpoint, bucket, key, secret] = values as string[];
  return { url: url!, anon: anon!, service: service!, endpoint: endpoint!, bucket: bucket!, key: key!, secret: secret! };
}
async function network(url: string | URL, init?: RequestInit): Promise<Response> { return fetch(url, { ...init, signal: AbortSignal.timeout(MEDIA_RUNTIME_LIMITS.networkTimeoutMs) }); }
async function rest(c: Config, token: string, path: string, body?: unknown, trusted = false): Promise<unknown> {
  const credential = trusted ? c.service : token;
  const result = await network(`${c.url}/rest/v1/${path}`, { method: body === undefined ? 'GET' : 'POST', headers: { apikey: trusted ? c.service : c.anon, Authorization: `Bearer ${credential}`, 'content-type': 'application/json' }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
  if (!result.ok) {
    const error = await result.json().catch(() => null) as Row | null;
    if (error?.code === '42501') reject('not_permitted');
    if (error?.code === 'GL086' && error.details === 'media_not_ready') reject('asset_not_found');
    if (error?.code === 'GL086' && error.details === 'media_verification_invariant') reject('media_failed');
    reject('storage_unavailable');
  }
  return result.json();
}
function row(value: unknown): Row | null { return Array.isArray(value) && value.length === 1 && value[0] && typeof value[0] === 'object' ? value[0] as Row : null; }
async function identify(c: Config, token: string): Promise<Actor> {
  const auth = await network(`${c.url}/auth/v1/user`, { headers: { apikey: c.anon, Authorization: `Bearer ${token}` } });
  if (!auth.ok) reject('not_permitted');
  const user = await auth.json() as Row;
  const parts = token.split('.');
  if (parts.length !== MEDIA_RUNTIME_LIMITS.jwtParts) reject('not_permitted');
  let claims: Row;
  try { claims = JSON.parse(atob(parts[1]!.replace(/-/g, '+').replace(/_/g, '/'))) as Row; } catch { reject('not_permitted'); }
  if (claims.role !== 'authenticated' || !uuid(claims.sub) || user.id !== claims.sub || !uuid(claims.tenant_id) || typeof claims.exp !== 'number' || claims.exp * MEDIA_RUNTIME_LIMITS.millisecondsPerSecond <= Date.now()) reject('not_permitted');
  const base = { userId: claims.sub.toLowerCase(), tenantId: claims.tenant_id.toLowerCase() };
  if (claims.app_role === 'member' && uuid(claims.member_id) && claims.staff_id == null && claims.impersonation_session_id == null) return { ...base, role: 'member', memberId: claims.member_id.toLowerCase(), preview: false };
  if (claims.app_role === 'gym_owner' && uuid(claims.impersonation_session_id) && claims.staff_id == null && claims.member_id == null) return { ...base, role: 'gym_owner', previewId: claims.impersonation_session_id.toLowerCase(), preview: true };
  if (['gym_owner', 'gym_manager', 'front_desk'].includes(String(claims.app_role)) && uuid(claims.staff_id) && claims.member_id == null && claims.impersonation_session_id == null) return { ...base, role: String(claims.app_role), staffId: claims.staff_id.toLowerCase(), preview: false };
  reject('not_permitted');
}
async function activeActor(c: Config, token: string, actor: Actor): Promise<void> {
  if (actor.preview) {
    const preview = row(await rest(c, token, `impersonation_sessions?select=id,tenant_id,actor_user_id,ended_at,expires_at&id=eq.${actor.previewId}`));
    if (!preview || preview.id !== actor.previewId || preview.tenant_id !== actor.tenantId || preview.actor_user_id !== actor.userId || preview.ended_at != null || typeof preview.expires_at !== 'string' || !(Date.parse(preview.expires_at) > Date.now())) reject('not_permitted');
    return;
  }
  if (actor.memberId) {
    const member = row(await rest(c, token, `members?select=id,tenant_id,user_id,status,erased_at&id=eq.${actor.memberId}`));
    if (!member || member.id !== actor.memberId || member.tenant_id !== actor.tenantId || member.user_id !== actor.userId || member.erased_at != null || ['blocked', 'cancelled', 'anonymized'].includes(String(member.status))) reject('not_permitted');
  } else {
    const staff = row(await rest(c, token, `staff?select=id,tenant_id,user_id,role,is_active&id=eq.${actor.staffId}`));
    if (!staff || staff.id !== actor.staffId || staff.tenant_id !== actor.tenantId || staff.user_id !== actor.userId || staff.role !== actor.role || staff.is_active !== true) reject('not_permitted');
  }
}
async function asset(c: Config, token: string, id: string, trusted = false): Promise<Row> {
  const value = row(await rest(c, token, `media_assets?select=${trusted ? PRIVATE : SAFE}&id=eq.${id}`, undefined, trusted));
  if (!value || value.id !== id || value.deleted_at != null) reject('asset_not_found');
  return value;
}
function scoped(value: Row, actor: Actor, area: 'staging' | 'published'): string {
  const key = area === 'staging' ? value.staging_object_key : value.object_key;
  const match = typeof key === 'string' ? KEY.exec(key) : null;
  const ext: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
  if (value.tenant_id !== actor.tenantId || !match || !uuid(match[1]) || !uuid(match[4]) || match[1] !== actor.tenantId || match[2] !== area || match[3] !== value.kind || match[5] !== ext[String(value.mime)]) reject('asset_not_found');
  return key as string;
}
function published(value: Row, actor: Actor): string {
  if (!value.confirmed_at || value.deleted_at != null || typeof value.verified_source_etag !== 'string' || !value.verified_source_etag || typeof value.published_etag !== 'string' || !value.published_etag) reject('asset_not_found');
  return scoped(value, actor, 'published');
}
function signature(mime: unknown, bytes: Uint8Array): boolean {
  const hex = Array.from(bytes, byte => byte.toString(MEDIA_RUNTIME_LIMITS.hexRadix).padStart('FF'.length, '0')).join('').toUpperCase();
  if (mime === 'image/jpeg') return hex.startsWith(MEDIA_IMAGE_SIGNATURES.jpegHex);
  if (mime === 'image/png') return hex.startsWith(MEDIA_IMAGE_SIGNATURES.pngHex);
  return mime === 'image/webp' && bytes.length >= MEDIA_LIMITS.signatureHeadBytes && new TextDecoder().decode(bytes.slice(0, MEDIA_IMAGE_SIGNATURES.webpContainer.length)) === MEDIA_IMAGE_SIGNATURES.webpContainer && new TextDecoder().decode(bytes.slice(MEDIA_IMAGE_SIGNATURES.webpFormatOffset, MEDIA_LIMITS.signatureHeadBytes)) === MEDIA_IMAGE_SIGNATURES.webpFormat;
}
const encoder = new TextEncoder();
function hex(bytes: ArrayBuffer): string { return Array.from(new Uint8Array(bytes), byte => byte.toString(MEDIA_RUNTIME_LIMITS.hexRadix).padStart('FF'.length, '0')).join(''); }
async function hash(value: string): Promise<string> { return hex(await crypto.subtle.digest('SHA-256', encoder.encode(value))); }
async function hmac(key: string | ArrayBuffer, text: string): Promise<ArrayBuffer> {
  const imported = await crypto.subtle.importKey('raw', typeof key === 'string' ? encoder.encode(key) : key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return crypto.subtle.sign('HMAC', imported, encoder.encode(text));
}
function encoded(value: string): string { return encodeURIComponent(value).replace(/[!'()*]/g, char => `%${char.charCodeAt(0).toString(MEDIA_RUNTIME_LIMITS.hexRadix).toUpperCase()}`); }
async function signed(c: Config, method: string, key: string, supplied: Record<string, string> = {}, ttl?: number, mime?: string): Promise<{ url: URL; headers: Headers }> {
  const url = new URL(`${c.endpoint.replace(/\/$/, '')}/${encoded(c.bucket)}/${key.split('/').map(encoded).join('/')}`);
  const date = new Date().toISOString().replace(/[:-]|\.\d{3}/g, '');
  const day = date.slice(0, MEDIA_RUNTIME_LIMITS.datePrefixLength);
  const scope = `${day}/auto/s3/aws4_request`;
  const headers = new Headers(supplied); headers.set('host', url.host);
  const payload = ttl ? 'UNSIGNED-PAYLOAD' : await hash('');
  if (ttl) {
    url.searchParams.set('X-Amz-Algorithm', 'AWS4-HMAC-SHA256'); url.searchParams.set('X-Amz-Credential', `${c.key}/${scope}`); url.searchParams.set('X-Amz-Date', date); url.searchParams.set('X-Amz-Expires', String(ttl));
    if (mime) url.searchParams.set('response-content-type', mime);
  } else { headers.set('x-amz-date', date); headers.set('x-amz-content-sha256', payload); }
  const names = Array.from(headers.keys()).sort(); const signedNames = names.join(';');
  if (ttl) url.searchParams.set('X-Amz-SignedHeaders', signedNames);
  const query = Array.from(url.searchParams.entries()).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0).map(([name, value]) => `${encoded(name)}=${encoded(value)}`).join('&');
  const canonical = [method, url.pathname, query, names.map(name => `${name}:${headers.get(name)!.trim().replace(/\s+/g, ' ')}\n`).join(''), signedNames, payload].join('\n');
  const signing = await hmac(await hmac(await hmac(await hmac(`AWS4${c.secret}`, day), 'auto'), 's3'), 'aws4_request');
  const sig = hex(await hmac(signing, `AWS4-HMAC-SHA256\n${date}\n${scope}\n${await hash(canonical)}`));
  if (ttl) url.searchParams.set('X-Amz-Signature', sig);
  else headers.set('authorization', `AWS4-HMAC-SHA256 Credential=${c.key}/${scope}, SignedHeaders=${signedNames}, Signature=${sig}`);
  headers.delete('host');
  return { url, headers };
}
async function r2(c: Config, method: string, key: string, headers?: Record<string, string>): Promise<Response> { const request = await signed(c, method, key, headers); return network(request.url, { method, headers: request.headers }); }
async function cleanup(c: Config, key: string): Promise<void> { try { await r2(c, 'DELETE', key); } catch { /* Orphan pruning is object-only, MED-012. */ } }
async function checked(c: Config, key: string, value: Row, expected?: string): Promise<string> {
  const source = expected === undefined;
  const head = await r2(c, 'HEAD', key);
  if (!head.ok) reject(source && head.status === STATUS.asset_not_found ? 'upload_missing' : 'storage_unavailable');
  const etag = head.headers.get('etag');
  if (!etag || (expected !== undefined && etag !== expected)) reject('storage_unavailable');
  if (Number(head.headers.get('content-length')) !== value.bytes || head.headers.get('content-type') !== value.mime) reject(source ? 'upload_rejected' : 'storage_unavailable');
  const sample = await r2(c, 'GET', key, { 'if-match': etag, range: `bytes=0-${MEDIA_LIMITS.signatureHeadBytes - 1}` });
  if (sample.status === STATUS.preconditionFailed) reject(source ? 'upload_changed' : 'storage_unavailable');
  if (!sample.ok || sample.headers.get('etag') !== etag || sample.headers.get('content-type') !== value.mime) reject('storage_unavailable');
  const bytes = new Uint8Array(await sample.arrayBuffer());
  const rangeBytes = Math.min(Number(value.bytes), MEDIA_LIMITS.signatureHeadBytes);
  if (sample.status !== STATUS.partialContent || bytes.length !== rangeBytes || sample.headers.get('content-range') !== `bytes 0-${rangeBytes - 1}/${value.bytes}`) reject('storage_unavailable');
  if (!signature(value.mime, bytes)) reject(source ? 'upload_rejected' : 'storage_unavailable');
  return etag;
}
function sameRegistration(safe: Row, privateRow: Row): boolean { return ['id', 'tenant_id', 'kind', 'mime', 'bytes', 'created_by_staff_id', 'created_at'].every(key => safe[key] === privateRow[key]); }
async function confirm(c: Config, token: string, actor: Actor, id: string, safe: Row): Promise<unknown> {
  if (actor.preview || actor.memberId || (actor.role === 'front_desk' && safe.kind !== 'announcement')) reject('not_permitted');
  const value = await asset(c, token, id, true);
  if (!sameRegistration(safe, value)) reject('asset_not_found');
  const stage = scoped(value, actor, 'staging');
  if (value.confirmed_at) { published(value, actor); return { assetId: id, confirmed: true }; }
  return publishAndFinalize(c, token, actor, id, value, stage, actor.role, () => activeActor(c, token, actor));
}
/**
 * The verified publication pipeline shared by the photo and proof flows:
 * ranged If-Match verification, ETag-conditional copy to a fresh unpublished
 * destination, independent destination recheck, then exactly one service-only
 * finalizer call. `role` is the actor identity the finalizer revalidates;
 * `recheck` re-proves live caller authority wherever an await could have
 * outlived it (revocation, concurrent winner, unknown commit outcome).
 */
async function publishAndFinalize(c: Config, token: string, actor: Actor, id: string, value: Row, stage: string, role: string, recheck: () => Promise<void>): Promise<unknown> {
  let sourceEtag: string;
  try { sourceEtag = await checked(c, stage, value); }
  catch (error) {
    if (error instanceof Refused && error.code === 'upload_rejected') {
      try { await rest(c, token, 'rpc/delete_media_asset', { p_asset_id: id, p_unconfirmed_only: true }); await cleanup(c, stage); } catch { /* Never mutate a confirmed winner. */ }
    }
    throw error;
  }
  let candidate = '';
  for (let attempt = 0; attempt < MEDIA_RUNTIME_LIMITS.destinationAttempts; attempt++) {
    const key = `${actor.tenantId}/published/${value.kind}/${crypto.randomUUID()}.${stage.split('.').pop()}`;
    const probe = await r2(c, 'HEAD', key);
    if (probe.status === STATUS.asset_not_found) { candidate = key; break; }
    if (!probe.ok) reject('storage_unavailable');
  }
  if (!candidate) reject('storage_unavailable');
  try {
    const copy = await r2(c, 'PUT', candidate, { 'x-amz-copy-source': `/${encoded(c.bucket)}/${stage.split('/').map(encoded).join('/')}`, 'x-amz-copy-source-if-match': sourceEtag, 'x-amz-metadata-directive': 'REPLACE', 'content-type': String(value.mime) });
    if (copy.status === STATUS.preconditionFailed) reject('upload_changed');
    const xml = await copy.text(); const copyEtag = /<ETag>([^<]+)<\/ETag>/.exec(xml)?.[1]?.replace(/&quot;/g, '"');
    if (!copy.ok || /<Error(?:\s|>)/.test(xml) || !copyEtag) reject('storage_unavailable');
    const destinationEtag = await checked(c, candidate, value, copyEtag);
    const args = { p_asset_id: id, p_actor_user_id: actor.userId, p_actor_staff_id: role === 'member' ? null : actor.staffId ?? null, p_actor_role: role, p_tenant_id: actor.tenantId, p_kind: value.kind, p_mime: value.mime, p_bytes: value.bytes, p_staging_object_key: stage, p_source_etag: sourceEtag, p_published_object_key: candidate, p_published_etag: destinationEtag };
    let outcome: unknown;
    try { outcome = await rest(c, token, 'rpc/finalize_media_asset', args, true); }
    catch (error) {
      // A network failure is an unknown commit outcome. An unconfirmed reread
      // cannot prove rollback; retain the object until locked reconciliation.
      if (error instanceof Refused && error.code !== 'storage_unavailable') { await cleanup(c, candidate); throw error; }
      await recheck();
      const rereadSafe = await asset(c, token, id);
      const reread = await asset(c, token, id, true);
      if (reread.confirmed_at && sameRegistration(rereadSafe, reread) && reread.object_key === candidate && published(reread, actor) === candidate) return { assetId: id, confirmed: true };
      reject('storage_unavailable');
    }
    if (outcome === true) { await cleanup(c, stage); return { assetId: id, confirmed: true }; }
    if (outcome === false) {
      await recheck();
      const winnerSafe = await asset(c, token, id);
      const winner = await asset(c, token, id, true);
      if (!sameRegistration(winnerSafe, winner)) reject('storage_unavailable');
      const winnerKey = published(winner, actor);
      if (winnerKey !== candidate) await cleanup(c, candidate);
      await cleanup(c, stage);
      return { assetId: id, confirmed: true };
    }
    reject('storage_unavailable');
  } catch (error) {
    // Failures before the finalizer never made this candidate authoritative.
    // Unknown finalizer failures are deliberately retained by the branch above.
    if (error instanceof Refused && error.code === 'upload_changed') await cleanup(c, candidate);
    throw error;
  }
}
/**
 * PAY proof boundary (BUY-008/009): the caller's own RLS-scoped purchase
 * request read is the authorization evidence and strictly precedes every
 * privileged lookup or storage access. A foreign, unexposed or unknown target
 * shares the one external refusal. Confirm requires a live owned request;
 * proof-url serves only the currently ACTIVE proof of a live request (frozen
 * decision 1: recorded, mismatch and bound history are safe metadata, never
 * viewable) — the attached active proof, or before the first attach the
 * member's latest confirmed unattached registration for that exact request.
 */
const PROOF_LIVE_STATUSES = ['owner_accepted', 'payment_proof_uploaded'] as const;
async function proofRows(c: Config, token: string, actor: Actor): Promise<Row[]> {
  const rpc = actor.memberId ? 'read_member_purchase_requests' : 'read_purchase_requests';
  const data = await rest(c, token, `rpc/${rpc}`, { p_limit: 0, p_after_created_at: null, p_after_id: null });
  const rows = Array.isArray(data) ? data : data !== null && typeof data === 'object' && Array.isArray((data as Row).requests) ? (data as Row).requests as unknown[] : null;
  if (!rows) reject('asset_not_found');
  const live = rows.filter(item => item !== null && typeof item === 'object' && (PROOF_LIVE_STATUSES as readonly string[]).includes(String((item as Row).status))) as Row[];
  if (live.length === 0) reject('asset_not_found');
  return live;
}
async function proofConfirm(c: Config, token: string, actor: Actor, id: string): Promise<unknown> {
  const live = await proofRows(c, token, actor);
  const value = await asset(c, token, id, true);
  if (value.tenant_id !== actor.tenantId || value.kind !== 'payment_proof' || value.created_by_member_id !== actor.memberId) reject('asset_not_found');
  const stage = scoped(value, actor, 'staging');
  if (value.confirmed_at) {
    // A confirmed-asset replay is read-only but not authority-free: the
    // registered request must still be live, owned and visible to this exact
    // caller (revalidated from the caller-JWT read alone).
    const linked = typeof value.linked_request_id === 'string' ? value.linked_request_id.toLowerCase() : '';
    if (!uuid(linked) || !live.some(item => item.requestId === linked)) reject('asset_not_found');
    await activeActor(c, token, actor);
    published(value, actor);
    return { assetId: id, confirmed: true };
  }
  return publishAndFinalize(c, token, actor, id, value, stage, 'member', async () => { await proofRows(c, token, actor); await activeActor(c, token, actor); });
}
async function proofUrl(c: Config, token: string, actor: Actor, id: string): Promise<unknown> {
  // The caller read alone carries the live requests this caller may verify;
  // every refusal below resolves from it or from the exact registered link —
  // never from an any-live-request fallback (BUY-009, frozen decision 1).
  const live = await proofRows(c, token, actor);
  const value = await asset(c, token, id, true);
  if (value.tenant_id !== actor.tenantId || value.kind !== 'payment_proof') reject('asset_not_found');
  if (actor.memberId && value.created_by_member_id !== actor.memberId) reject('asset_not_found');
  const linked = typeof value.linked_request_id === 'string' ? value.linked_request_id.toLowerCase() : '';
  if (!uuid(linked)) reject('asset_not_found');
  const bound = live.find(item => item.requestId === linked);
  if (!bound) reject('asset_not_found');
  // Attached path: the request's active proof asset must be exactly this one.
  // Unattached path: no active proof yet and this asset is the member's latest
  // confirmed, never-attached registration for that exact request (a rejected
  // or superseded earlier proof is history, never the current view).
  if (bound.activeProofAssetId != null) {
    if (bound.activeProofAssetId !== id) reject('asset_not_found');
  } else {
    const latest = row(await rest(c, token, `media_assets?select=id&tenant_id=eq.${actor.tenantId}&kind=eq.payment_proof&linked_request_id=eq.${linked}&confirmed_at=not.is.null&deleted_at=is.null&attached_to_id=is.null&order=created_at.desc,id.desc&limit=1`, undefined, true));
    if (!latest || latest.id !== id) reject('asset_not_found');
    const history = row(await rest(c, token, `payment_proofs?select=id&tenant_id=eq.${actor.tenantId}&asset_id=eq.${id}&limit=1`, undefined, true));
    if (history) reject('asset_not_found');
  }
  // Only a verified, immutably published proof is signable: missing verified
  // state shares the one external refusal (BUY-009/018).
  const key = published(value, actor);
  // Revalidate after the privileged lookups: current actor, current live
  // requests, and an unchanged registration (BUY-001/009, MEDIA amendment).
  const current = await asset(c, token, id);
  if (!sameRegistration(current, value) || current.confirmed_at !== value.confirmed_at) reject('asset_not_found');
  await activeActor(c, token, actor);
  const stillLive = await proofRows(c, token, actor);
  const stillBound = stillLive.find(item => item.requestId === linked);
  if (!stillBound || (stillBound.activeProofAssetId != null ? stillBound.activeProofAssetId !== id : false)) reject('asset_not_found');
  const signedRequest = await signed(c, 'GET', key, {}, BUY_LIMITS.privateProofGetTtlSeconds, String(value.mime));
  await activeActor(c, token, actor);
  const finalLive = await proofRows(c, token, actor);
  if (!finalLive.some(item => item.requestId === linked)) reject('asset_not_found');
  return { imageUrl: signedRequest.url.toString() };
}
type Exposure = { kind: string; parent: string };
async function exposure(c: Config, token: string, id: string): Promise<Exposure> {
  for (const [kind, rpc, field] of [['product', 'read_member_shop', 'item_id'], ['trainer', 'read_member_trainers', 'trainer_key'], ['announcement', 'read_member_announcements', 'announcement_id']]) {
    const rows = await rest(c, token, `rpc/${rpc}`, {});
    if (!Array.isArray(rows)) reject('storage_unavailable');
    const exposed = rows.find(item => item && item.image_asset_id === id);
    if (exposed && uuid(exposed[field!])) return { kind: kind!, parent: exposed[field!].toLowerCase() };
  }
  reject('asset_not_found');
}
function attachment(value: Row, actor: Actor, exposed: Exposure): void {
  if (value.kind !== exposed.kind || !uuid(value.attached_to_id)) reject('asset_not_found');
  let parent = value.attached_to_id.toLowerCase();
  if (exposed.kind === 'trainer') {
    const digest = createHash('md5').update(`pt-trainer:${actor.tenantId}:${parent}`, 'utf8').digest('hex');
    const [a, b, c, d] = MEDIA_RUNTIME_LIMITS.md5GroupEnds;
    parent = `${digest.slice(0, a)}-${digest.slice(a, b)}-${digest.slice(b, c)}-${digest.slice(c, d)}-${digest.slice(d)}`;
  }
  if (parent !== exposed.parent) reject('asset_not_found');
}
Deno.serve(async (request: Request): Promise<Response> => {
  try {
    const bearer = /^Bearer (\S+)$/.exec(request.headers.get('authorization') ?? '')?.[1];
    if (!bearer) return refusal('not_permitted');
    const c = config();
    const actor = await identify(c, bearer);
    let body: Row;
    try { body = await request.json() as Row; } catch { reject('invalid_request'); }
    if (request.method !== 'POST' || !body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).sort().join(',') !== 'assetId,operation' || !uuid(body.assetId) || !['confirm', 'member-url', 'staff-url', 'proof-confirm', 'proof-url'].includes(String(body.operation))) reject('invalid_request');
    const id = body.assetId.toLowerCase(); const operation = body.operation;
    const proof = String(operation).startsWith('proof-');
    if (!proof && (operation === 'member-url') !== !!actor.memberId) reject('not_permitted');
    if (operation === 'confirm' && actor.preview) reject('not_permitted');
    // Proof verification is member-work only; the private proof URL serves the
    // owning member or a real same-tenant front-office verifier (BUY-009).
    if (proof && actor.preview) reject('not_permitted');
    if (operation === 'proof-confirm' && !actor.memberId) reject('not_permitted');
    if (operation === 'proof-url' && !actor.memberId && !actor.staffId) reject('not_permitted');
    if (operation === 'proof-confirm') return json({ ok: true, data: await proofConfirm(c, bearer, actor, id) });
    if (operation === 'proof-url') return json({ ok: true, data: await proofUrl(c, bearer, actor, id) });
    let exposed: Exposure | undefined;
    let safe: Row | undefined;
    if (operation === 'member-url') {
      // Member exposure is the caller-JWT feature read itself; the member
      // active-actor revalidation joins the pre-mint gate below (BUY-009).
      exposed = await exposure(c, bearer, id);
    }
    else {
      await activeActor(c, bearer, actor);
      safe = await asset(c, bearer, id);
      if (safe.tenant_id !== actor.tenantId) reject('asset_not_found');
      // The photo boundary signs and finalizes the original photo kinds only:
      // proof objects and any future private kind never come through here.
      if (String(safe.kind) === 'payment_proof') reject('asset_not_found');
      if (operation === 'confirm') return json({ ok: true, data: await confirm(c, bearer, actor, id, safe) });
    }
    const value = await asset(c, bearer, id, true);
    if (safe && !sameRegistration(safe, value)) reject('asset_not_found');
    const key = published(value, actor);
    if (exposed) attachment(value, actor, exposed);
    // Repeat caller authorization after every privileged lookup/signing await.
    if (exposed) await activeActor(c, bearer, actor);
    const signedRequest = await signed(c, 'GET', key, {}, MEDIA_LIMITS.displayUrlTtlSeconds, String(value.mime));
    await activeActor(c, bearer, actor);
    if (exposed) attachment(value, actor, await exposure(c, bearer, id));
    else { const current = await asset(c, bearer, id); if (current.confirmed_at !== value.confirmed_at || current.attached_to_id !== value.attached_to_id || !sameRegistration(current, value)) reject('asset_not_found'); }
    return json({ ok: true, data: { imageUrl: signedRequest.url.toString() } });
  } catch (error) { return refusal(error instanceof Refused ? error.code : 'storage_unavailable'); }
});
