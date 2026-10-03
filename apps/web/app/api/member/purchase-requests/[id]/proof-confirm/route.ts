import { purchaseRoute } from '../../../../../../lib/purchase-http';

/** Attach a verified staging object as the request's payment proof (BUY-008/010). */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return purchaseRoute(request, 'proofConfirm', context);
}
