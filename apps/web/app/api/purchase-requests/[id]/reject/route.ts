import { purchaseRoute } from '../../../../../lib/purchase-http';

/** Decline a requested intent; the reason is shown to the member (BUY-011). */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return purchaseRoute(request, 'reject', context);
}
