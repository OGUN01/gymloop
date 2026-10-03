import { purchaseRoute } from '../../../../../lib/purchase-http';

/** Reject the active proof; the request returns to accepted (BUY-011). */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return purchaseRoute(request, 'rejectProof', context);
}
