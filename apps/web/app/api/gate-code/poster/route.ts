import { randomUUID } from 'node:crypto';
import { posterReplaceCommandSchema } from '@gymloop/shared';
import { apiFail, apiOk, PG_INSUFFICIENT_PRIVILEGE } from '../../../../lib/api';
import { gateAdminCommand } from '../gate-admin-command';
import { hashGateCode, posterGateCode } from '../../../../lib/gate-code';

type ReplacePosterRpc = {
  rpc(name: 'replace_checkin_poster', args: {
    p_branch_id: string; p_session_id: string; p_token_hash: string;
  }): Promise<{ data: string | null; error: { code: string } | null }>;
};

/** POST /api/gate-code/poster — replace one branch's printed gate atomically. */
export async function POST(request: Request): Promise<Response> {
  const command = await gateAdminCommand(request, posterReplaceCommandSchema, 'confirmation_required',
    'Confirm poster replacement before revoking the old code; provide a valid branch id if selecting a branch.');
  if ('failure' in command) return command.failure;
  const { session, input } = command;
  const { supabase } = session;
  let branchQuery = supabase.from('branches').select('id');
  if (input.branchId) branchQuery = branchQuery.eq('id', input.branchId);
  const { data: branch, error: branchError } = await branchQuery.order('is_default', { ascending: false })
    .order('created_at').limit(1).maybeSingle();
  if (branchError) return apiFail('server_error', 'branch_unavailable', 'This gym’s branch could not be loaded. Try again.');
  if (!branch) return apiFail('not_found', 'branch_unknown', 'No branch of this gym matches that poster.');
  const sessionId = randomUUID();
  let code: string;
  try { code = posterGateCode(sessionId); }
  catch { return apiFail('server_error', 'poster_secret_missing', 'Poster key is unavailable. Ask an administrator to provision it before replacing a poster.'); }
  const { data, error } = await (supabase as unknown as ReplacePosterRpc)
    .rpc('replace_checkin_poster', { p_branch_id: branch.id, p_session_id: sessionId, p_token_hash: hashGateCode(code) });
  if (error?.code === PG_INSUFFICIENT_PRIVILEGE) return apiFail('forbidden', 'not_permitted', 'Only an active gym owner or manager can replace a poster for this branch.');
  if (error?.code === 'GL070') return apiFail('conflict', 'mode_changed', 'Switch this gym to printed poster mode before replacing its poster.');
  if (error || data !== sessionId) return apiFail('server_error', 'poster_replace_failed', 'Poster replacement could not be confirmed. Reload the gate before retrying.');
  return apiOk({ mode: 'printed_poster', branchId: branch.id, code });
}
