import { guardianLegacyAttestationRequestSchema } from '@gymloop/shared';
import { inviteOk, inviteRpcFailure, OWNER_ONLY_ROLES } from '../../../../lib/member-invite-routes';
import { guardianStaffCommand } from '../../../../lib/guardian-routes';
const FAILED = { code: 'attestation_failed', message: 'The adult confirmation could not be recorded. Try again.' };
const REFUSALS = { '42501': { status: 'forbidden', code: 'not_permitted', message: 'Only the gym owner can confirm existing members are adults.' } } as const;
export async function POST(request: Request): Promise<Response> {
  const command = await guardianStaffCommand(request, OWNER_ONLY_ROLES, guardianLegacyAttestationRequestSchema);
  if ('failure' in command) return command.failure;
  try {
    const { data, error } = await command.supabase.rpc('attest_members_without_dob_adult');
    const row = data?.[0];
    return error || !row ? inviteRpcFailure(error ?? {}, REFUSALS, FAILED) : inviteOk({ attestedAt: row.members_without_dob_attested_adult_at, changed: row.changed });
  } catch { return inviteRpcFailure({}, REFUSALS, FAILED); }
}
