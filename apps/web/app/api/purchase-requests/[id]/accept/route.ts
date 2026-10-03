import { purchaseRoute } from '../../../../../lib/purchase-http';

/** Front office accepts a requested intent and places its hard hold (BUY-004). */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return purchaseRoute(request, 'accept', context);
}
