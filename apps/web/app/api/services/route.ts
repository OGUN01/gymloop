import { serviceRequestSchema, parseServiceResult } from '@gymloop/shared';
import { classCommand, classRpc } from '../../../lib/class-http';
export async function POST(request: Request): Promise<Response> {
  return classCommand(request, { schema: serviceRequestSchema, roles: ['gym_owner', 'gym_manager'], errors: { '23505': ['conflict', 'service_name_taken'], GL114: ['conflict', 'limit_reached'] },
    execute: (client, input) => classRpc(client, 'create_service', { p_name: input.name, p_description: input.description ?? null, p_default_duration_minutes: input.defaultDurationMinutes, p_default_capacity: input.defaultCapacity, p_sort_order: input.sortOrder }),
    answer: (data) => parseServiceResult(data),
  });
}
