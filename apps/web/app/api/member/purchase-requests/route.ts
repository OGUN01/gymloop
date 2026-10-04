import { purchaseRoute } from '../../../../lib/purchase-http';
import { purchaseReadRoute } from '../../../../lib/purchase';

/** Member raises a purchase request; the ledger decision stays in the RPC. */
export async function POST(request: Request) {
  return purchaseRoute(request, 'create');
}

/** Keyset list of the member's own requests. */
export async function GET(request: Request) {
  return purchaseReadRoute(request, 'member');
}
