import { memberClassVisibilityRequestSchema, parseMemberClassVisibilityResult } from '@gymloop/shared';
import { classCommand, classRpc } from '../../../lib/class-http';

export async function PUT(request: Request): Promise<Response> {
  return classCommand(request, {
    schema: memberClassVisibilityRequestSchema,
    roles: ['gym_owner', 'gym_manager'],
    errors: { '42501': ['forbidden', 'not_permitted'], '22023': ['bad_request', 'invalid_request'] },
    execute: (client, input) => classRpc(client, 'set_member_classes_enabled', { p_enabled: input.enabled }),
    answer: (data) => parseMemberClassVisibilityResult(data),
  });
}
