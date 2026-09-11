import { apiFail } from '../../../../lib/api';
import {
  acceptedLead,
  callLeadRpc,
  leadOk,
  leadWriteFailure,
  parseLeadCommand,
  readLeadCommand,
  staleLeadFailure,
  staleRevision,
  trialInstantAt,
} from '../lead-input';

/**
 * `PATCH /api/leads/[leadId]` — edit a lead's facts or move its stage.
 *
 * Two commands, one endpoint, because they answer the same question ("what
 * happened to this lead?") and share the same compare-and-swap revision.
 * Front office only, and the identity check precedes the body parse — both
 * steps are `readLeadCommand`'s, the prologue every leads route shares.
 */
export async function PATCH(
  request: Request,
  context: { params: Promise<{ leadId: string }> },
): Promise<Response> {
  const read = await readLeadCommand(request, context, parseLeadCommand, 'That change could not be read. Check the command and its facts.');
  if ('failure' in read) return read.failure;
  const command = read.command;

  if (command.command === 'update_details') {
    const { data, error } = await callLeadRpc(read.supabase, 'update_lead', {
      p_lead_id: read.leadId,
      p_expected_revision: command.expectedRevision,
      p_branch_id: command.branchId,
      p_full_name: command.fullName,
      p_phone: command.phone,
      p_email: command.email,
      p_source: command.source,
      p_assigned_to_staff_id: command.assignedToStaffId,
      p_notes: command.notes,
    });

    return acceptedResponse(data, error);
  }

  // A stage move with a trial time names a gym-local wall clock: the desk
  // schedules in the gym's day, and a nonexistent or ambiguous one (a DST
  // gap or overlap) is refused here rather than silently shifted to one side
  // of it. No trial time, no timezone read — the loss path touches nothing
  // but the RPC.
  let trialAt: string | null = null;
  if (command.trialLocal !== null) {
    const gym = await read.supabase.from('organizations').select('timezone').maybeSingle();
    const timezone = gym.data?.timezone;
    if (typeof timezone !== 'string' || timezone === '') {
      return apiFail('bad_request', 'invalid_request', 'The gym timezone is unavailable, so that trial time cannot be resolved.');
    }
    trialAt = trialInstantAt(command.trialLocal, timezone);
    if (trialAt === null) {
      return apiFail('bad_request', 'invalid_request', 'That trial time is not a real gym-local time. Pick another.');
    }
  }

  const { data, error } = await callLeadRpc(read.supabase, 'transition_lead', {
    p_lead_id: read.leadId,
    p_expected_revision: command.expectedRevision,
    p_target: command.toStage,
    p_trial_at: trialAt,
    p_lost_reason: command.lostReason,
  });

  return acceptedResponse(data, error);
}

/**
 * Both commands return the accepted lead, so both share one honest answer:
 * an RPC error maps through the contract's table, a stale report carries the
 * current revision back to the caller, and a "success" whose shape the
 * contract does not recognize is a failure — never an invented acceptance.
 */
function acceptedResponse(data: unknown, error: { code: string; message: string } | null): Response {
  if (error) return leadWriteFailure(error);
  const stale = staleRevision(data);
  if (stale !== null) return staleLeadFailure(stale);
  const lead = acceptedLead(data);
  if (lead === null) {
    return apiFail('server_error', 'operation_failed', 'The change could not be confirmed. Nothing was written.');
  }
  return leadOk('ok', { lead });
}
