import { freezeRoute } from '../../../../../lib/freeze-http';

/** A different configured-role staff member approves the adopted freeze (SLF-007). */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return freezeRoute(request, 'approve', context);
}
