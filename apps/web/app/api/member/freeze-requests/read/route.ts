import { freezeRoute } from '../../../../../lib/freeze-http';

/** Keyset list of the member's own freeze requests, read through the safe RPC (SLF-003). */
export async function POST(request: Request) {
  return freezeRoute(request, 'readList');
}
