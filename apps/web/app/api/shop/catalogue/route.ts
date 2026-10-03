import { shopRoute } from '../../../../lib/shop-http';
export function POST(request: Request) { return shopRoute(request, 'catalogue'); }

