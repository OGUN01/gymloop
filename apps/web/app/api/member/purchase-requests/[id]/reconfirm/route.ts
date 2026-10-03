import { purchaseRoute } from '../../../../../../lib/purchase-http';

/** Explicit member reconfirmation of a revised quotation (BUY-004). */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return purchaseRoute(request, 'reconfirm', context);
}
