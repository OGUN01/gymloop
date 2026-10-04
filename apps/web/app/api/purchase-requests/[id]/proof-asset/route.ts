import { MEDIA_EXTENSIONS, MEDIA_MIME_TYPES, parseMediaObjectKey, serverEnv, type MediaMime } from '@gymloop/shared';
import { noStore } from '../../../../../lib/api';
import { verifyProofCapability } from '../../../../../lib/purchase-http';
import { readRequestIdentity } from '../../../../../lib/identity-session';

/**
 * The one bounded GET the campaign's proof-URL rules pin (BUY-009/018 and the
 * frozen runtime decisions): the private evidence read behind the same-origin
 * capability `read_purchase_proof_url` issued. The capability is mandatory,
 * unforgeable and request/proof/asset/actor-bound with the immutable issued
 * expiry — a GET never resets or extends that deadline, and absent, forged,
 * expired, changed-tuple or foreign-request capabilities refuse before any
 * object access. The object key never travels in the URL or the response:
 * the published key is reconstructed server-side inside the caller's tenant,
 * bytes stream through without persisting, and every answer is no-store.
 */

const GENERIC_REFUSAL = { status: 404, body: { ok: false, error: { code: 'request_unavailable', message: "That evidence isn't available." } } } as const;

function generic(): Response {
  return noStore(new Response(JSON.stringify(GENERIC_REFUSAL.body), { status: GENERIC_REFUSAL.status, headers: { 'content-type': 'application/json' } }));
}

type ProofSupabase = {
  auth?: { getSession?: () => Promise<{ data: { session?: { access_token?: string } | null } | null }> };
};

export async function GET(request: Request, context: { params: Promise<Record<string, string>> }): Promise<Response> {
  const resolved = await readRequestIdentity(request);
  if (!resolved) return generic();
  // Only a real member or front-office identity carries the tenant binding
  // this boundary authorizes; platform and unlinked identities refuse here.
  const identityKind = resolved.identity.kind;
  if (identityKind !== 'member' && identityKind !== 'staff') return generic();
  // The route lives on the [id] segment; the capability's request binding is
  // checked against exactly that segment value.
  const { id: requestId } = await context.params;
  const capability = new URL(request.url).searchParams.get('capability');
  if (!requestId || !capability) return generic();
  const verified = verifyProofCapability(capability);
  if (!verified.ok) return generic();
  const payload = verified.payload;
  // The capability is request-bound and actor-bound: another request path, a
  // different signed-in account or a foreign tenant refuses identically.
  if (payload.r !== requestId || payload.u !== resolved.identity.userId || payload.t !== resolved.identity.tenantId) return generic();
  const mime: MediaMime | null = payload.m && (MEDIA_MIME_TYPES as readonly string[]).includes(payload.m) ? payload.m : null;
  const extensions = mime ? [MEDIA_EXTENSIONS[mime]] : Object.values(MEDIA_EXTENSIONS);
  // The published key is reconstructed from the caller's own tenant and the
  // capability's asset id — never carried in, echoed back, or logged.
  const tenant = resolved.identity.tenantId;
  const keys = extensions.map(extension => `${tenant}/published/payment_proof/${payload.a}.${extension}`).filter(key => parseMediaObjectKey(key) !== null);
  if (keys.length === 0) return generic();
  const config = serverEnv();
  const { S3Client, GetObjectCommand } = await import('@aws-sdk/client-s3');
  const client = new S3Client({ region: 'auto', endpoint: config.R2_ENDPOINT, credentials: { accessKeyId: config.R2_ACCESS_KEY_ID, secretAccessKey: config.R2_SECRET_ACCESS_KEY } });
  let body: ReadableStream<Uint8Array> | null = null;
  for (const key of keys) {
    try {
      const answer = await client.send(new GetObjectCommand({ Bucket: config.R2_BUCKET, Key: key }));
      if (answer.Body) {
        body = answer.Body as ReadableStream<Uint8Array>;
        break;
      }
    } catch { /* A missing extension candidate is not an authorization fact. */ }
  }
  if (!body) return generic();
  return new Response(body, {
    status: 200,
    headers: {
      'content-type': mime ?? 'application/octet-stream',
      'cache-control': 'no-store',
    },
  });
}
