import { purchaseRoute } from '../../../../../lib/purchase-http';

/**
 * A short-lived private proof URL for the owning member or the real verifier
 * (BUY-009): only the URL and its expiry, never storage metadata, no-store.
 */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return purchaseRoute(request, 'proofUrl', context);
}
