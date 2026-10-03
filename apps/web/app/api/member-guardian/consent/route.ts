import { GUARDIAN_CONSENT_VERSION, guardianConsentRequestSchema } from '@gymloop/shared';
import { FRONT_OFFICE_ROLES } from '../../../../lib/leads';
import { inviteOk, inviteRpcFailure } from '../../../../lib/member-invite-routes';
import { guardianStaffCommand } from '../../../../lib/guardian-routes';
const FAILED = { code: 'consent_failed', message: 'The consent decision could not be recorded. Try again.' };
const REFUSALS = {
  '42501': { status: 'not_found', code: 'member_not_found', message: 'That member could not be found. Reload the page and try again.' },
  GL084: { status: 'conflict', code: 'member_not_minor', message: 'This member is no longer under 18. Reload the page to see their current status.' },
  GL083: { status: 'conflict', code: 'guardian_required', message: "Add the guardian's name, relation and phone, then record consent." },
  '22023': { status: 'bad_request', code: 'invalid_request', message: 'Enter how the consent decision was collected, then try again.' },
} as const;
export async function POST(request: Request): Promise<Response> {
  const command = await guardianStaffCommand(request, FRONT_OFFICE_ROLES, guardianConsentRequestSchema);
  if ('failure' in command) return command.failure;
  const { memberId, granted, source } = command.input;
  try {
    const { data, error } = await command.supabase.rpc('record_guardian_consent', { p_member_id: memberId, p_granted: granted, p_source: source, p_version: GUARDIAN_CONSENT_VERSION });
    const row = data?.[0];
    return error || !row ? inviteRpcFailure(error ?? {}, REFUSALS, FAILED) : inviteOk({ consentId: row.consent_id, recordedAt: row.recorded_at, changed: row.changed });
  } catch { return inviteRpcFailure({}, REFUSALS, FAILED); }
}
