import { freezeRoute } from '../../../../../../lib/freeze-http';

/** The owning member withdraws an unapproved request (SLF-009). */
export async function POST(request: Request, context: { params: Promise<Record<string, string>> }) {
  return freezeRoute(request, 'cancel', context);
}
