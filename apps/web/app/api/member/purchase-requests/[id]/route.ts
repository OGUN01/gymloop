import { purchaseReadRoute } from '../../../../../lib/purchase';

export async function GET(request: Request, context: { params: Promise<Record<string, string>> }): Promise<Response> {
  return purchaseReadRoute(request, 'member', context);
}
