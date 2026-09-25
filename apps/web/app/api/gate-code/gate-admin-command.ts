import { apiFail, jsonBody, staffSession, type StaffSession } from '../../../lib/api';

type GateCommand<Input> = { failure: Response } | { session: StaffSession; input: Input };

/** Owner/manager authorization then strict command shape, shared by gate mutations. */
export async function gateAdminCommand<Input>(
  request: Request,
  schema: { safeParse(payload: unknown): { success: true; data: Input } | { success: false } },
  invalidCode: string,
  invalidMessage: string,
): Promise<GateCommand<Input>> {
  const caller = await staffSession(['gym_owner', 'gym_manager'], { completeWrongAudience: 'forbidden' });
  if ('failure' in caller) return { failure: caller.failure };
  const body = await jsonBody(request);
  if ('failure' in body) return { failure: body.failure };
  const parsed = schema.safeParse(body.payload);
  if (!parsed.success) return { failure: apiFail('bad_request', invalidCode, invalidMessage) };
  return { session: caller.session, input: parsed.data };
}
