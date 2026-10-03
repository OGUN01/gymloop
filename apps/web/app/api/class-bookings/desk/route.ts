import { classDeskBookRequestSchema, parseClassDeskBookResult } from '@gymloop/shared';
import { classCommand, classRpc } from '../../../../lib/class-http';
export async function POST(request: Request): Promise<Response> {
  return classCommand(request, { schema: classDeskBookRequestSchema, roles: ['gym_owner', 'gym_manager', 'front_desk'], booking: true, errors: { '42501': ['not_found', 'reference_not_found'], GL090: ['conflict', 'class_full'], GL091: ['conflict', 'already_booked'], GL092: ['conflict', 'not_bookable'], GL093: ['forbidden', 'membership_not_live'], GL094: ['conflict', 'other_branch'] },
    execute: (client, input) => classRpc(client, 'desk_book_class_session', { p_session_id: input.sessionId, p_member_id: input.memberId }),
    answer: (data) => parseClassDeskBookResult(data),
  });
}
