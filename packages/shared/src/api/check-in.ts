import { z } from 'zod';

/**
 * The check-in request body.
 *
 * It lives here, and not next to the Route Handler that reads it, because it is
 * a contract rather than a detail of one app: the mobile client (Phase 7) posts
 * the same shape to the same endpoint, and `packages/shared` is what web,
 * mobile and Edge Functions all consume (`docs/architecture.md`, "Boundaries").
 * Keeping it here also means it is validated with the zod this package already
 * depends on rather than a second validator added to `apps/web`.
 *
 * What is deliberately absent is the whole point of it: **there is no tenant
 * field, and no acting-staff field.** The tenant comes from the verified JWT
 * claim in the Route Handler and is re-checked by `attendance_tenant_write`;
 * the acting staff member is stamped from the `staff_id` claim by the
 * `attendance_enforce_check_in` trigger. A caller cannot name either, so
 * "a check-in never crosses a tenant" is not a validation rule that could be
 * forgotten — it is a field that does not exist.
 *
 * `token` present means a scan (`source` becomes `qr`); `token` absent means the
 * front desk is recording the visit for someone, and `reason` is then required
 * (ATT-005/006). Both strings are trimmed before `min(1)`, so a reason of three
 * spaces is rejected here as well as by
 * `attendance_front_desk_has_assist_chk` — the same rule at both ends, on
 * purpose, because the constraint is the one that cannot be bypassed and the
 * schema is the one that can say something useful about it.
 *
 * `clientEventId` is the idempotency key. Sending one turns a network retry into
 * a no-op via `attendance_tenant_id_client_event_id_key` rather than a second
 * visit; omitting it is legal and simply gives up that protection.
 */
export const checkInRequestSchema = z.object({
  memberId: z.uuid(),
  token: z.string().trim().min(1).optional(),
  reason: z.string().trim().min(1).optional(),
  clientEventId: z.uuid().optional(),
});

export type CheckInRequest = z.infer<typeof checkInRequestSchema>;
