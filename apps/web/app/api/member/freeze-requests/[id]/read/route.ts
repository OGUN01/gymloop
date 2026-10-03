import { freezeRoute } from '../../../../../../lib/freeze-http';

/** One own freeze request, revalidated inside the safe RPC (SLF-003). */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return freezeRoute(request, 'readOne', context);
}
