import { guardianProfileRequestSchema } from '@gymloop/shared';
import { FRONT_OFFICE_ROLES } from '../../../lib/leads';
import { inviteOk, inviteRpcFailure } from '../../../lib/member-invite-routes';
import { guardianStaffCommand } from '../../../lib/guardian-routes';

const FAILED = { code: 'guardian_save_failed', message: 'The age and guardian details could not be saved. Try again.' };
const REFUSALS = {
  '42501': { status: 'not_found', code: 'member_not_found', message: 'That member could not be found. Reload the page and try again.' },
  '22023': { status: 'bad_request', code: 'invalid_request', message: 'Check the age and guardian details, then try again.' },
  date_of_birth_in_future: { status: 'unprocessable', code: 'date_of_birth_in_future', message: 'The date of birth cannot be in the future.' },
  members_guardian_name_chk: { status: 'unprocessable', code: 'guardian_name_invalid', message: 'Enter a valid guardian name.' },
  members_guardian_phone_format_chk: { status: 'unprocessable', code: 'guardian_phone_invalid', message: 'Enter the guardian phone with its country code, such as +919876543210.' },
  members_guardian_email_format_chk: { status: 'unprocessable', code: 'guardian_email_invalid', message: 'Enter a valid guardian email address.' },
  members_guardian_identity_chk: { status: 'unprocessable', code: 'guardian_details_incomplete', message: 'Add both the guardian name and relation.' },
  members_guardian_contact_chk: { status: 'unprocessable', code: 'guardian_details_incomplete', message: 'Add the guardian name and relation before their contact details.' },
} as const;
export async function POST(request: Request): Promise<Response> {
  const command = await guardianStaffCommand(request, FRONT_OFFICE_ROLES, guardianProfileRequestSchema);
  if ('failure' in command) return command.failure;
  const { memberId, dateOfBirth, guardian } = command.input;
  try {
    const { error } = await command.supabase.rpc('set_member_age_guardian', { p_member_id: memberId, p_date_of_birth: dateOfBirth!,
      p_guardian_name: (guardian?.name ?? null)!, p_guardian_relation: (guardian?.relation ?? null)!, p_guardian_phone: (guardian?.phone ?? null)!, p_guardian_email: (guardian?.email ?? null)! });
    if (!error) return inviteOk({ updated: true });
    const detail = `${error.message ?? ''} ${error.details ?? ''}`;
    const code = error.code === '42501' ? error.code
      : error.code === '22023' ? detail.includes('date_of_birth_in_future') ? 'date_of_birth_in_future' : error.code
        : error.code === '23514' ? detail.match(/\bconstraint "([^"]+)"/)?.[1] ?? '' : '';
    return inviteRpcFailure({ code }, REFUSALS, FAILED);
  } catch { return inviteRpcFailure({}, REFUSALS, FAILED); }
}
