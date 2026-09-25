import type { Database } from '@gymloop/db';
import { z } from 'zod';

/** Derived from the canonical Postgres vocabulary; rejects tenant/actor fields. */
type GateMode = Database['public']['Enums'] extends { checkin_gate_mode: infer Mode }
  ? Mode : 'printed_poster' | 'rotating_screen';

export const gateModeCommandSchema: z.ZodType<{ mode: GateMode }> = z.strictObject({
  mode: z.enum(['printed_poster', 'rotating_screen']),
});

/** Refuse silent poster rotation, unknown branches, and request-supplied tenant ids. */
export const posterReplaceCommandSchema = z.strictObject({
  confirmed: z.literal(true),
  branchId: z.uuid().optional(),
});
