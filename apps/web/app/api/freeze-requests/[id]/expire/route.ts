import { freezeRoute } from '../../../../../lib/freeze-http';

/** Front office materializes the closure of an already ineffective open request (SLF-010). */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return freezeRoute(request, 'expire', context);
}
