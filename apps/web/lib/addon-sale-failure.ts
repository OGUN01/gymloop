import { apiFail } from './api';

export function saleFailure(code: string, details: string | null, message: string): Response {
  if (code === '42501') return apiFail('forbidden', 'not_permitted', 'Your role may not record this sale.');
  if (code === 'P0002') return apiFail('not_found', 'not_found', 'That member or offer is unavailable.');
  if (code === '22023') return apiFail('bad_request', 'invalid_request', 'That sale command was not valid.');
  if (code === '40001' || code === '40P01') return apiFail('conflict', 'retryable', 'Please retry that sale.');
  if (
    code === '23P01' &&
    `${message} ${details ?? ''}`.includes('pt_sessions_trainer_overlap_excl')
  ) {
    return apiFail('conflict', 'slot_unavailable', 'That PT slot is no longer available.');
  }

  const known = new Set([
    'idempotency_conflict', 'order_is_a_record', 'session_is_a_record',
    'invalid_order_transition', 'invalid_session_transition',
    'catalogue_incomplete', 'offer_unavailable', 'quote_changed',
    'unsupported_currency', 'member_unavailable', 'trainer_unavailable', 'invalid_quantity',
    'invalid_payment', 'invalid_validity', 'invalid_snapshot', 'unaccepted_order',
    'wrong_order_kind', 'order_unavailable', 'session_budget_exhausted',
    'session_outside_validity', 'session_not_ended', 'session_identity_mismatch',
    'seller_not_yours', 'trainer_not_yours', 'insufficient_stock',
  ]);
  const refusal = details !== null && known.has(details) ? details : 'operation_failed';
  return apiFail(
    refusal === 'operation_failed' ? 'server_error' : 'conflict',
    refusal,
    'That sale could not be accepted.',
  );
}


