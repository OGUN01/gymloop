/**
 * Shared SQLSTATE refusal + row projection helpers for Wave C HTTP runners
 * (PAY purchases, NTF push). One place maps upstream error classes onto the
 * stable `{ ok:false, error:{code,message} }` envelope so no runner echoes an
 * untrusted database message, and no two runners hand-roll the same row-to-
 * camel translation.
 */

import { apiFail, apiOk, noStore, type ApiFailStatus } from './api';

export type RefusalSpec = { status: ApiFailStatus; code: string; message: string };
export type RefusalMapping = Record<string, RefusalSpec | ((details: string | null) => Response)>;

/** The refusal entries every Wave C/D runner shares verbatim (actor, target
 * invisibility, replay conflict, state conflict). Feature-specific codes
 * (GL067, GL123…, proof branches) stay in each runner's own table. */
export const WAVE_REFUSAL_MAP: Record<string, RefusalSpec> = {
  '42501': { status: 'forbidden', code: 'not_permitted', message: 'You cannot perform this action from this account.' },
  P0002: { status: 'not_found', code: 'request_unavailable', message: "That request isn't available." },
  GL068: { status: 'conflict', code: 'idempotency_conflict', message: 'This was already handled with different details.' },
  GL066: { status: 'conflict', code: 'state_conflicted', message: 'Someone else changed this first. Refresh and try again.' },
};

/** Map a Postgres error to its frozen envelope; unknown codes stay generic. */
export function sqlRefusal(mapping: RefusalMapping, code: string, details: string | null, fallback: RefusalSpec): Response {
  const entry = mapping[code];
  if (!entry) return noStore(apiFail(fallback.status, fallback.code, fallback.message));
  if (typeof entry === 'function') return entry(details);
  return noStore(apiFail(entry.status, entry.code, entry.message));
}

/** Flatten a single-row RPC result into camelCase keys, or a neutral marker. */
export function sqlRowCamel(data: unknown, fields: Record<string, string>, neutral: Record<string, unknown> = { updated: true }): Record<string, unknown> {
  const first = Array.isArray(data) ? data[0] as Record<string, unknown> | undefined : typeof data === 'object' && data !== null ? data as Record<string, unknown> : undefined;
  if (!first) return neutral;
  const out: Record<string, unknown> = {};
  for (const [snake, camel] of Object.entries(fields)) {
    if (typeof first[snake] !== 'undefined') out[camel] = first[snake];
  }
  return Object.keys(out).length ? out : neutral;
}

/** Pull one path/segment id, accepting either spelling, and require a UUID. */
export function sqlUuidFrom(segment: Record<string, string>, keys: readonly string[]): string | null {
  const value = keys.map(key => segment[key]).find(candidate => typeof candidate === 'string' && candidate.length > 0) ?? '';
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value) ? value : null;
}

export type AudienceIdentityShape = { kind: 'member' | 'staff' | 'impersonation'; role?: string };
export type WaveAudience = 'member' | 'frontOffice' | 'memberOrFrontOffice';
const FRONT_OFFICE = ['gym_owner', 'gym_manager', 'front_desk'];

/** The shared audience rule for Wave C HTTP runners: member, front office, or either. */
export function waveAudienceAllowed(identity: AudienceIdentityShape, audience: WaveAudience): boolean {
  const isMember = identity.kind === 'member';
  const isFrontOffice = identity.kind === 'staff' && FRONT_OFFICE.includes(identity.role ?? '');
  return audience === 'member' ? isMember : audience === 'frontOffice' ? isFrontOffice : isMember || isFrontOffice;
}

type MinimalSupabase = { rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { code: string; details: string | null } | null }> };

/** Run one named RPC, map its refusal through `failure`, and project its row. */
export async function sqlRpcResponse(
  supabase: MinimalSupabase,
  name: string,
  args: Record<string, unknown>,
  failure: (code: string, details: string | null) => Response,
  fields: Record<string, string>,
): Promise<Response> {
  const result = await supabase.rpc(name, args);
  if (result.error) return failure(result.error.code, result.error.details);
  return noStore(apiOk(sqlRowCamel(result.data, fields)));
}

/** Resolved Wave C route head: a verified caller or the failure to return. */
export type WaveRouteHead = { supabase: MinimalSupabase; identity: AudienceIdentityShape };

/** The shared runner preamble: verify the session, then gate the audience. */
export async function waveRouteHead(request: Request, audience: WaveAudience, resolveIdentity: (request: Request) => Promise<{ supabase: unknown; identity: unknown } | null>): Promise<WaveRouteHead | Response> {
  const resolved = await resolveIdentity(request);
  if (!resolved) return noStore(apiFail('unauthorized', 'not_permitted', 'Sign in to continue.'));
  const identity = resolved.identity as AudienceIdentityShape;
  if (!waveAudienceAllowed(identity, audience)) return noStore(apiFail('forbidden', 'not_permitted', 'You cannot perform this action from this account.'));
  return { supabase: resolved.supabase as MinimalSupabase, identity };
}
