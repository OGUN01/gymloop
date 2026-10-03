import { classBookingCancelRequestSchema, parseClassBookingCancelResult } from '@gymloop/shared';
import { classCommand, classRpc } from '../../../../lib/class-http';
export async function POST(request: Request): Promise<Response> {
  return classCommand(request, { schema: classBookingCancelRequestSchema, booking: true, errors: { '42501': ['not_found', 'booking_not_found'], GL095: ['conflict', 'cancel_window_closed'], GL113: ['conflict', 'booking_not_cancellable'] },
    execute: (client, input) => classRpc(client, 'cancel_class_booking', { p_booking_id: input.bookingId }),
    answer: (data) => parseClassBookingCancelResult(data),
  });
}
