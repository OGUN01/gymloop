import { purchaseRoute } from '../../../../../lib/purchase-http';

/**
 * Record externally received money against the verified proof (BUY-012): the
 * real staff caller invokes the frozen ledger orchestration with the exact
 * received amount, currency and method.
 */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return purchaseRoute(request, 'record', context);
}
