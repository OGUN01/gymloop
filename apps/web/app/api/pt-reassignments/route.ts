import { ptReassignRequestSchema, ptCommandAnswer } from '@gymloop/shared';
import { ptCommand, ptNullableRpc } from '../../../lib/pt-http';

export async function POST(request: Request): Promise<Response> {
  return ptCommand(request, {
    roles: ['gym_owner', 'gym_manager'],
    schema: ptReassignRequestSchema,
    execute: (client, input) => ptNullableRpc(client, 'reassign_pt_packs', { p_from_staff_id: input.fromStaffId, p_to_staff_id: input.toStaffId, p_order_ids: input.orderIds ?? null, p_reason: input.reason }),
    answer: (data) => ptCommandAnswer('reassign', data),
  });
}
