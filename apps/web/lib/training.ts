import { readMemberTraining, readMemberPtSlots, readMemberPtHistory, type PtReadClient, type PtHistoryCursor } from '@gymloop/shared';
import { memberMediaUrl } from './media';
import type { StaffSession } from './api';

/** Every projection and image uses the supplied caller's current session. */
export function loadMemberTraining(supabase: StaffSession['supabase']) {
  return readMemberTraining(supabase as unknown as PtReadClient, (assetId) => memberMediaUrl(supabase, assetId));
}
export function loadMemberSlots(supabase: StaffSession['supabase'], orderId: string, from: string, to: string) { return readMemberPtSlots(supabase as unknown as PtReadClient, orderId, from, to); }
export function loadMemberTrainingHistory(supabase: StaffSession['supabase'], cursor?: PtHistoryCursor) { return readMemberPtHistory(supabase as unknown as PtReadClient, cursor); }
