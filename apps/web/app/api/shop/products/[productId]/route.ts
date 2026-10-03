import { shopRoute } from '../../../../../lib/shop-http';
export function PATCH(request: Request, context: { params: Promise<Record<string, string>> }) { return shopRoute(request, 'display', context); }
