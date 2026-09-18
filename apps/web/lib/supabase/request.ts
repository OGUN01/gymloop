import type { Database } from '@gymloop/db';
import { createServerClient } from '@supabase/ssr';
import { Buffer } from 'node:buffer';
import { supabaseCredentials } from './credentials';

const SUPABASE_AUTH_COOKIE = /(?:^|;\s*)sb-[a-z0-9-]+-auth-token(?:\.\d+)?=/i;
const BEARER = /^Bearer (\S+)$/;

/** Syntax-only JWT preflight. Payload claims are deliberately never decoded here. */
function hasVerifiableJwtShape(token: string): boolean {
  const [encodedHeader, payload, signature, ...extra] = token.split('.');
  if (!encodedHeader || !payload || !signature || extra.length !== 0) return false;
  try {
    const header: unknown = JSON.parse(Buffer.from(encodedHeader, 'base64url').toString('utf8'));
    if (header === null || typeof header !== 'object' || Array.isArray(header)) return false;
    const algorithm = (header as { alg?: unknown }).alg;
    return typeof algorithm === 'string' && algorithm.trim() !== '' && algorithm.toLowerCase() !== 'none';
  } catch {
    return false;
  }
}

/**
 * Request-only caller adapter. It refuses a mixed cookie/bearer request before
 * any route parses its command body, and it never accepts an arbitrary auth
 * scheme as a user session.
 */
export function createRequestSupabase(request: Request): {
  supabase: ReturnType<typeof createServerClient<Database>>;
  bearer?: string;
} | null {
  const authorization = request.headers.get('authorization');
  const cookie = request.headers.get('cookie') ?? '';
  const hasCookieSession = SUPABASE_AUTH_COOKIE.test(cookie);
  if (authorization !== null && hasCookieSession) return null;
  if (authorization !== null) {
    const match = BEARER.exec(authorization);
    if (!match?.[1]) return null;
    const bearer = match[1];
    if (!hasVerifiableJwtShape(bearer)) return null;
    try {
      return {
        supabase: createServerClient<Database>(...supabaseCredentials(), {
          global: { headers: { Authorization: authorization } },
          cookies: { getAll: () => [], setAll: () => undefined },
        }),
        bearer,
      };
    } catch {
      return null;
    }
  }
  if (!hasCookieSession) return null;
  const entries = cookie.split(';').map((part) => {
    const separator = part.indexOf('=');
    return { name: separator > 0 ? part.slice(0, separator).trim() : '', value: separator > 0 ? part.slice(separator + 1).trim() : '' };
  });
  try {
    return {
      supabase: createServerClient<Database>(...supabaseCredentials(), {
        cookies: { getAll: () => entries, setAll: () => undefined },
      }),
    };
  } catch {
    return null;
  }
}
