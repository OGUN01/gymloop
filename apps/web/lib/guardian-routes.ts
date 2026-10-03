import { apiFail, noStore } from './api';
import { inviteStaffCommand } from './member-invite-routes';

/** Preserve shared authorization order, while GRD owns its invalid-body code. */
export async function guardianStaffCommand<T>(
  ...args: Parameters<typeof inviteStaffCommand<T>>
) {
  const command = await inviteStaffCommand(...args);
  if ('failure' in command) {
    const envelope = await command.failure.clone().json() as { error?: { code?: unknown } };
    if (envelope.error?.code === 'malformed_body') {
      return { failure: noStore(apiFail('bad_request', 'invalid_request', 'That request could not be read. Reload the page and try again.')) };
    }
  }
  return command;
}
