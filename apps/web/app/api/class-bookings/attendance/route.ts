import { classAttendanceRequestSchema, parseClassAttendanceResult } from '@gymloop/shared';
import { classCommand, classRpc } from '../../../../lib/class-http';
export async function POST(request: Request): Promise<Response> {
  return classCommand(request, { schema: classAttendanceRequestSchema, roles: ['gym_owner', 'gym_manager', 'front_desk', 'trainer'], booking: true, errors: { '42501': ['not_found', 'booking_not_found'], GL113: ['conflict', 'booking_not_markable'], GL111: ['conflict', 'session_not_open'] },
    execute: (client, input) => classRpc(client, 'mark_class_attendance', { p_booking_id: input.bookingId, p_status: input.status }),
    answer: (data, input) => parseClassAttendanceResult(data, input),
  });
}
