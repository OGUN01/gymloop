import { purchaseRoute } from '../../../../../../lib/purchase-http';

/** The owning member cancels an unrecorded open request (BUY-006). */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return purchaseRoute(request, 'cancel', context);
}
