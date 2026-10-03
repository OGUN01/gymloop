import { apiFail, jsonBody, staffSession, type StaffSession } from '../../../lib/api';
import type { StaffRole } from '@gymloop/shared';

type GateCommand<Input> = { failure: Response } | { session: StaffSession; input: Input };

/** Owner/manager authorization then strict command shape, shared by gate mutations. */
export async function gateAdminCommand<Input>(
  request: Request,
  schema: { safeParse(payload: unknown): { success: true; data: Input } | { success: false } },
  invalidCode: string,
  invalidMessage: string,
  roles: readonly StaffRole[] = ['gym_owner', 'gym_manager'],
): Promise<GateCommand<Input>> {
  const caller = await staffSession(roles, { completeWrongAudience: 'forbidden' });
  if ('failure' in caller) return { failure: caller.failure };
  const body = await jsonBody(request);
  if ('failure' in body) return { failure: body.failure };
  const parsed = schema.safeParse(body.payload);
  if (!parsed.success) return { failure: apiFail('bad_request', invalidCode, invalidMessage) };
  return { session: caller.session, input: parsed.data };
}
