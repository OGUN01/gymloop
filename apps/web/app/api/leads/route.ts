import { apiFail } from '../../../lib/api';
import { callLeadRpc, createLeadResult, leadOk, leadWriteFailure, parseCreateLead, readLeadCommand } from './lead-input';

/**
 * `POST /api/leads` — record an enquiry.
 *
 * Front office only: a trainer is staff for other screens and is refused
 * here, a member never reaches a console route, and a support preview
 * identity is read-only by design. The refusal happens before the body is
 * parsed — both steps are `readLeadCommand`'s, the prologue every leads route
 * shares, so this handler is only the enquiry's own facts and answer.
 */
export async function POST(request: Request): Promise<Response> {
  const read = await readLeadCommand(request, null, parseCreateLead, 'That enquiry could not be read. Check the branch, name, phone and source.');
  if ('failure' in read) return read.failure;
  const command = read.command;

  // `create_lead` derives tenant and acting staff from the caller's claims and
  // owns stage, revision and creation time — none of them is an argument. The
  // request key makes a lost-response retry a replay instead of a second lead.
  const { data, error } = await callLeadRpc(read.supabase, 'create_lead', {
    p_request_key: command.requestKey,
    p_branch_id: command.branchId,
    p_full_name: command.fullName,
    p_phone: command.phone,
    p_email: command.email,
    p_source: command.source,
    p_assigned_to_staff_id: command.assignedToStaffId,
    p_notes: command.notes,
  });

  if (error) return leadWriteFailure(error);
  const result = createLeadResult(data);
  if (result === null) {
    return apiFail('server_error', 'operation_failed', 'The enquiry could not be recorded. Nothing was written.');
  }
  // A replay answers 200 with the CURRENT revision — the original response may
  // have been lost, but the lead has not stopped moving since.
  return leadOk(result.replayed ? 'ok' : 'created', result);
}
