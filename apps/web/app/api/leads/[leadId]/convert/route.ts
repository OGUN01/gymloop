import { apiFail } from '../../../../../lib/api';
import {
  callLeadRpc,
  convertLeadFailure,
  convertLeadResult,
  leadOk,
  memberUnavailable,
  memberUnavailableFailure,
  parseConvertLead,
  readLeadCommand,
  staleLeadFailure,
  staleRevision,
} from '../../lead-input';

/**
 * `POST /api/leads/[leadId]/convert` — convert a trial-done lead to a member.
 *
 * The one atomic write in the leads pipeline: `convert_lead` either creates
 * and links a new member or links the one the desk explicitly names, in one
 * transaction, with one request key. The route's whole job is to carry the
 * command honestly: front office only, identity before body, unknown shapes
 * refused before the RPC — all three are `readLeadCommand`'s, the prologue
 * every leads route shares — and every documented outcome, including the
 * duplicate-phone conflict and the generic unavailable refusal, answered
 * with exactly the facts the contract allows.
 */
export async function POST(
  request: Request,
  context: { params: Promise<{ leadId: string }> },
): Promise<Response> {
  const read = await readLeadCommand(request, context, parseConvertLead, 'That conversion could not be read. Check the mode and member.');
  if ('failure' in read) return read.failure;
  const command = read.command;

  const { data, error } = await callLeadRpc(read.supabase, 'convert_lead', {
    p_lead_id: read.leadId,
    p_request_key: command.requestKey,
    p_expected_revision: command.expectedRevision,
    p_mode: command.mode,
    p_member_id: command.mode === 'link_existing' ? command.memberId : null,
  });

  if (error) return convertLeadFailure(error);
  const stale = staleRevision(data);
  if (stale !== null) return staleLeadFailure(stale);
  if (memberUnavailable(data)) return memberUnavailableFailure();
  const result = convertLeadResult(data);
  if (result === null) {
    return apiFail('server_error', 'operation_failed', 'The conversion could not be confirmed. Nothing was written.');
  }
  // A replayed conversion answers 200: the original outcome already happened
  // and is immutable, so the retry is told what it achieved, not re-run.
  return leadOk(result.replayed ? 'ok' : 'created', result);
}
