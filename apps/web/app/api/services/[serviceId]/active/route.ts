import { serviceActiveRequestSchema, parseServiceActiveResult, classIdentifierSchema } from '@gymloop/shared';
import { classCommand, classRpc } from '../../../../../lib/class-http';
export async function POST(request: Request, context: { params: Promise<{ serviceId: string }> }): Promise<Response> {
  const { serviceId } = await context.params;
  return classCommand(request, { schema: serviceActiveRequestSchema, roles: ['gym_owner', 'gym_manager'], errors: { '42501': ['not_found', 'service_not_found'] },
    execute: (client, input) => classIdentifierSchema.safeParse(serviceId).success ? classRpc(client, 'set_service_active', { p_service_id: serviceId, p_is_active: input.isActive }) : Promise.resolve({ data: null, error: { code: '22023' } }),
    answer: (data, input) => parseServiceActiveResult(data, input, serviceId),
  });
}
