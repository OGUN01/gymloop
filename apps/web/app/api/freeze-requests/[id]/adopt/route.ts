import { freezeRoute } from '../../../../../lib/freeze-http';

/** Front office adopts a requested freeze into an ordinary undecided desk pause (SLF-006). */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return freezeRoute(request, 'adopt', context);
}
