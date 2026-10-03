import { serviceRequestSchema, parseServiceResultUpdate, classIdentifierSchema } from '@gymloop/shared';
import { classCommand, classRpc } from '../../../../lib/class-http';
export async function PUT(request: Request, context: { params: Promise<{ serviceId: string }> }): Promise<Response> {
  const { serviceId } = await context.params;
  return classCommand(request, { schema: serviceRequestSchema, roles: ['gym_owner', 'gym_manager'], errors: { '42501': ['not_found', 'service_not_found'], '23505': ['conflict', 'service_name_taken'] },
    execute: (client, input) => classIdentifierSchema.safeParse(serviceId).success ? classRpc(client, 'update_service', { p_service_id: serviceId, p_name: input.name, p_description: input.description ?? null, p_default_duration_minutes: input.defaultDurationMinutes, p_default_capacity: input.defaultCapacity, p_sort_order: input.sortOrder }) : Promise.resolve({ data: null, error: { code: '22023' } }),
    answer: (data) => parseServiceResultUpdate(data, serviceId),
  });
}
