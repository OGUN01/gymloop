import { GATE_CODE_TTL_MS } from '@gymloop/shared';
import { apiFail, apiOk, staffSession, PG_INSUFFICIENT_PRIVILEGE } from '../../../lib/api';
import { hashGateCode, newGateCode, posterGateCode } from '../../../lib/gate-code';

/** Current gate mode and branch-scoped poster; no new session is created by a read. */
export async function GET(): Promise<Response> {
  const caller = await staffSession();
  if ('failure' in caller) return caller.failure;
  const { supabase } = caller.session;
  const { data: rawSettings, error: settingsError } = await supabase.from('organization_settings')
    .select('checkin_gate_mode').maybeSingle();
  // Remove this narrow assertion after CI applies the migration and DB types regenerate.
  const settings = rawSettings as { checkin_gate_mode: 'printed_poster' | 'rotating_screen' } | null;
  if (settingsError || !settings) return apiFail('server_error', 'gate_settings_unavailable', 'Gate settings could not be loaded.');
  const { data: branch } = await supabase.from('branches').select('id')
    .order('is_default', { ascending: false }).order('created_at').limit(1).maybeSingle();
  if (!branch) return apiFail('unprocessable', 'no_branch', 'This gym has no branch to show a gate for.');
  if (settings.checkin_gate_mode !== 'printed_poster') {
    return apiOk({ mode: 'rotating_screen', branchId: branch.id });
  }
  const { data: poster, error: posterError } = await supabase.from('qr_sessions')
    .select('id, token_hash').eq('branch_id', branch.id).filter('gate_mode', 'eq', 'printed_poster')
    .is('revoked_at', null).maybeSingle();
  if (posterError) return apiFail('server_error', 'poster_unavailable', 'The current poster could not be loaded.');
  if (!poster) return apiOk({ mode: 'printed_poster', branchId: branch.id, code: null });
  try {
    const code = posterGateCode(poster.id);
    if (hashGateCode(code) !== poster.token_hash) {
      return apiFail('conflict', 'poster_secret_changed', 'Poster cannot be reprinted with this server key. Replace poster to print a new one.');
    }
    return apiOk({ mode: 'printed_poster', branchId: branch.id, code });
  } catch {
    return apiFail('server_error', 'poster_secret_missing', 'Poster code key is unavailable. Provision it and replace the poster.');
  }
}

/** Existing rotating-screen issue path, now gated by the gym-wide mode. */
export async function POST(): Promise<Response> {
  const caller = await staffSession();
  if ('failure' in caller) return caller.failure;
  const { supabase, tenantId, staffId } = caller.session;
  const { data: branch } = await supabase.from('branches').select('id')
    .order('is_default', { ascending: false }).order('created_at').limit(1).maybeSingle();
  if (!branch) return apiFail('unprocessable', 'no_branch', 'This gym has no branch to issue a code for.');
  const { data: rawSettings, error: settingsError } = await supabase.from('organization_settings')
    .select('checkin_gate_mode').maybeSingle();
  // Remove this narrow assertion after CI applies the migration and DB types regenerate.
  const settings = rawSettings as { checkin_gate_mode: 'printed_poster' | 'rotating_screen' } | null;
  if (settingsError) return apiFail('server_error', 'gate_settings_unavailable', 'Gate settings could not be loaded.');
  if (!settings) return apiFail('server_error', 'gate_settings_unavailable', 'Gate settings could not be loaded.');
  if (settings.checkin_gate_mode === 'printed_poster') {
    return apiFail('conflict', 'poster_mode_active', 'Printed poster is active. Switch to rotating screen before issuing a temporary code.');
  }
  const code = newGateCode();
  const expiresAt = new Date(Date.now() + GATE_CODE_TTL_MS).toISOString();
  const { error } = await supabase.from('qr_sessions').insert({
    tenant_id: tenantId, branch_id: branch.id, token_hash: hashGateCode(code),
    expires_at: expiresAt, created_by_staff_id: staffId,
  });
  if (error) return error.code === PG_INSUFFICIENT_PRIVILEGE
    ? apiFail('forbidden', 'not_permitted', 'Your role may not issue a gate code.')
    : apiFail('server_error', 'gate_code_failed', 'That gate code could not be issued.');
  return apiOk({ code, expiresAt, mode: 'rotating_screen' });
}
