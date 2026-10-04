import { purchaseReadRoute } from '../../../lib/purchase';

export async function GET(request: Request): Promise<Response> {
  return purchaseReadRoute(request, 'frontOffice');
}
