import { freezeRoute } from '../../../../lib/freeze-http';

/** Keyset list of the tenant's freeze requests for the desk queue (SLF-006). */
export async function POST(request: Request) {
  return freezeRoute(request, 'staffRead');
}
