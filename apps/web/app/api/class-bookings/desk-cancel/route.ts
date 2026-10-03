import { classDeskCancelRequestSchema, parseClassDeskCancelResult } from '@gymloop/shared';
import { classCommand, classRpc } from '../../../../lib/class-http';
export async function POST(request: Request): Promise<Response> {
  return classCommand(request, { schema: classDeskCancelRequestSchema, roles: ['gym_owner', 'gym_manager', 'front_desk'], booking: true, errors: { '42501': ['not_found', 'booking_not_found'], GL113: ['conflict', 'booking_not_cancellable'], GL111: ['conflict', 'session_not_open'] },
    execute: (client, input) => classRpc(client, 'desk_cancel_class_booking', { p_booking_id: input.bookingId, p_reason: input.reason }),
    answer: (data) => parseClassDeskCancelResult(data),
  });
}
