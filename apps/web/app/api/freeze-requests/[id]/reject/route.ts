import { freezeRoute } from '../../../../../lib/freeze-http';

/** Front office rejects an open request with a reason shown to the member (SLF-008). */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return freezeRoute(request, 'reject', context);
}
