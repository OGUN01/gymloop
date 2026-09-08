import type { NextRequest, NextResponse } from 'next/server';
import { updateSession } from './lib/supabase/proxy-session';

/**
 * Next 16 renamed the `middleware` file convention to `proxy` and the
 * exported function with it; a `middleware.ts` copied from a Next 14/15
 * Supabase tutorial does not run at all here. Proxy also defaults to the
 * Node.js runtime now, and setting `runtime` in this file throws.
 */
export function proxy(request: NextRequest): Promise<NextResponse> {
  return updateSession(request);
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
};
