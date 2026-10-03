import { freezeRoute } from '../../../../lib/freeze-http';

/** The member raises a freeze request; every decision stays in the RPC (SLF-004). */
export async function POST(request: Request) {
  return freezeRoute(request, 'create');
}
