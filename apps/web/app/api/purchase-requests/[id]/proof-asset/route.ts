import { noStore } from '../../../../../lib/api';
import { readRequestIdentity } from '../../../../../lib/identity-session';

/**
 * The one bounded GET the campaign's proof-URL rules pin (BUY-009/018): the
 * private evidence read behind the URL `read_purchase_proof_url` hands out.
 * The POST-only rule pins command routes; this is a bounded evidence read.
 * The same actor checks as the RPC run here (the owning member or the same-
 * tenant front-office verifier — the RPC's own successful row is the
 * authorization), the ≤60s bound is validated, bytes stream through without
 * ever persisting, and unknown/foreign/unexposed requests share one generic
 * refusal. Nothing here answers with storage metadata.
 */

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const BOUNDS = { proofGetTtlSeconds: 60, clockSkewMs: 5000, msPerSecond: 1000 } as const;
const GENERIC_REFUSAL = { status: 404, body: { ok: false, error: { code: 'request_unavailable', message: "That evidence isn't available." } } } as const;

function generic(): Response {
  return noStore(new Response(JSON.stringify(GENERIC_REFUSAL.body), { status: GENERIC_REFUSAL.status, headers: { 'content-type': 'application/json' } }));
}

type ProofSupabase = {
  auth?: { getSession?: () => Promise<{ data: { session?: { access_token?: string } | null } | null }> };
  rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { code: string } | null }>;
  functions: { invoke: (name: string, options: { body: Record<string, unknown>; headers?: Record<string, string> }) => Promise<{ data: unknown; error: unknown }> };
};

export async function GET(request: Request, context: { params: Promise<Record<string, string>> }): Promise<Response> {
  const resolved = await readRequestIdentity(request);
  if (!resolved) return generic();
  const { requestId } = await context.params;
  if (!requestId || !UUID_PATTERN.test(requestId)) return generic();
  const supabase = resolved.supabase as unknown as ProofSupabase;
  // The RPC freshly re-derives actor permission and the request's currently
  // ACTIVE proof; a refused or foreign target is indistinguishable from an
  // unknown one.
  const proof = await supabase.rpc('read_purchase_proof_url', { p_request_id: requestId });
  if (proof.error || !Array.isArray(proof.data) || proof.data.length === 0) return generic();
  const row = proof.data[0] as { request_id?: unknown; url?: unknown; expires_at?: unknown; asset_id?: unknown };
  if (typeof row.url !== 'string' || typeof row.expires_at !== 'string') return generic();
  // The bounded URL lives ≤ the frozen 60-second TTL: reject anything
  // already expired, or minted with a longer life than the cap allows.
  const minted = Date.parse(row.expires_at);
  const consumed = new URL(request.url).searchParams.get('e');
  if (Number.isNaN(minted) || minted < Date.now()) return generic();
  if (minted > Date.now() + BOUNDS.proofGetTtlSeconds * BOUNDS.msPerSecond + BOUNDS.clockSkewMs) return generic();
  if (typeof consumed === 'string') {
    const consumedAt = Number.parseInt(consumed, 10);
    if (!Number.isFinite(consumedAt) || consumedAt * BOUNDS.msPerSecond < Date.now()) return generic();
  }
  if (typeof row.asset_id !== 'string' || !UUID_PATTERN.test(row.asset_id)) return generic();
  // Private MEDIA proof objects stream through the MEDIA verifier's proof
  // operation; the signed private URL never reaches the caller. The verifier
  // answers the frozen `{ ok, data: { imageUrl } }` signer envelope and the
  // verified caller capability is forwarded explicitly, header bearer first
  // and the verified cookie session otherwise (the repo's media convention).
  const header = request.headers.get('authorization');
  const bearer = header?.startsWith('Bearer ') ? header.slice('Bearer '.length) : undefined;
  const token = bearer ?? (await supabase.auth?.getSession?.().catch(() => null))?.data?.session?.access_token;
  const media = await supabase.functions.invoke('media', { body: { operation: 'proof-url', assetId: row.asset_id }, ...(token ? { headers: { Authorization: `Bearer ${token}` } } : {}) }).catch(() => null);
  const envelope = (media?.data ?? null) as { ok?: unknown; data?: { imageUrl?: unknown } } | null;
  const signedUrl = envelope?.ok === true && typeof envelope.data?.imageUrl === 'string' ? envelope.data.imageUrl : null;
  if (!signedUrl) return generic();
  const bytes = await fetch(signedUrl).catch(() => null);
  if (!bytes?.ok || !bytes.body) return generic();
  return new Response(bytes.body, {
    status: 200,
    headers: {
      'content-type': bytes.headers.get('content-type') ?? 'application/octet-stream',
      'cache-control': 'no-store',
      'content-length': bytes.headers.get('content-length') ?? '',
    },
  });
}
