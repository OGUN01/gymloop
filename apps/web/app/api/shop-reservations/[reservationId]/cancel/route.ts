import { shopRoute } from '../../../../../lib/shop-http';
export function POST(request: Request, context: { params: Promise<Record<string, string>> }) { return shopRoute(request, 'deskCancel', context); }

