import { shopRoute } from '../../../../../lib/shop-http';
export function PUT(request: Request) { return shopRoute(request, 'categoryOrder'); }
