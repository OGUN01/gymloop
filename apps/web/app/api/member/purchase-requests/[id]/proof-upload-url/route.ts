import { purchaseRoute } from '../../../../../../lib/purchase-http';

/**
 * Starts a payment-proof staging upload. Registration/finalization lives in
 * the MEDIA verifier boundary and lands with the SQL/MEDIA side; until then
 * this answers a real failure rather than a staging URL it cannot honour.
 */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return purchaseRoute(request, 'proofUploadUrl', context);
}
