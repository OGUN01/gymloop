import { isoDayOfInstant, isoDaySchema, occupancyDefaultRangeFrom } from '@gymloop/shared';

export type OccupancyLoadErrorCode =
  | 'occupancy_unavailable'
  | 'invalid_occupancy_range'
  | 'invalid_gym_timezone'
  | 'occupancy_branch_unavailable';

export class OccupancyLoadError extends Error {
  constructor(public readonly code: OccupancyLoadErrorCode) {
    // The message is a stable code, never provider text: a foreign branch, a
    // missing snapshot and a failed read are externally indistinguishable.
    super(code);
    this.name = 'OccupancyLoadError';
  }
}

type OccupancyRpcError = {
  code?: string;
  message?: string;
  details?: string;
  hint?: string;
};

export type OccupancyRequest = {
  from?: string;
  through?: string;
  branchId?: string | null;
  excludeHolidays?: boolean;
};

export type OccupancySnapshot = {
  asOf: string | null;
  from: string;
  through: string;
  branchId: string | null;
  excludeHolidays: boolean;
  months: Array<Record<string, unknown>>;
  heatmap: Record<string, unknown> | null;
  classes: Record<string, unknown> | null;
  warnings: Record<string, unknown>;
};

const OWNER_READER_ROLES = new Set(['gym_owner', 'gym_manager']);
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** OCC-001: only a real, non-impersonating owner or manager reaches any occupancy read. */
function assertOwnerReader(identity: unknown): void {
  const candidate = identity as { kind?: string; role?: string; impersonationSessionId?: string } | null;
  const admitted = candidate !== null && candidate !== undefined
    && candidate.kind === 'staff'
    && candidate.impersonationSessionId === undefined
    && candidate.role !== undefined
    && OWNER_READER_ROLES.has(candidate.role);
  if (!admitted) throw new OccupancyLoadError('occupancy_unavailable');
}

function defaultRange(): { from: string; through: string } {
  const through = isoDayOfInstant(Date.now());
  return { from: occupancyDefaultRangeFrom(through), through };
}

function resolveRange(request: OccupancyRequest): { from: string; through: string } {
  const hasFrom = request.from !== undefined;
  const hasThrough = request.through !== undefined;
  if (hasFrom !== hasThrough) throw new OccupancyLoadError('invalid_occupancy_range');
  if (!hasFrom || !hasThrough) return defaultRange();
  const from = request.from as string;
  const through = request.through as string;
  if (!isoDaySchema.safeParse(from).success || !isoDaySchema.safeParse(through).success) {
    throw new OccupancyLoadError('invalid_occupancy_range');
  }
  if (from > through) throw new OccupancyLoadError('invalid_occupancy_range');
  return { from, through };
}

/** OCC-003: the RPC's own refusals map to their explicit states — a bad zone
 * stays a zone error, an invisible branch stays a branch refusal, and the
 * provider's text never reaches the surface. */
function mapRpcError(error: OccupancyRpcError): OccupancyLoadErrorCode {
  if (error.code === 'P0002') return 'occupancy_branch_unavailable';
  if (error.code === '22023') {
    const evidence = `${error.message ?? ''} ${error.details ?? ''} ${error.hint ?? ''}`.toLowerCase();
    return evidence.includes('timezone') ? 'invalid_gym_timezone' : 'invalid_occupancy_range';
  }
  return 'occupancy_unavailable';
}

/**
 * OCC-002: one snapshot read supplies every total, series and drill-down with a
 * single disclosed asOf. The containing statement is one versioned RPC call —
 * `owner_occupancy_analytics` is the proposed follow-up extension of the
 * metrics seam (see the implementer report); until it lands the loader is
 * wired and typed against its response shape but real deployments need the
 * RPC commissioned first. No page-by-page sums, no second read path.
 */
export async function loadOccupancyAnalytics(
  identity: unknown,
  client: unknown,
  request: OccupancyRequest,
): Promise<OccupancySnapshot> {
  assertOwnerReader(identity);
  const rawBranch = request.branchId ?? null;
  if (rawBranch !== null && !UUID_PATTERN.test(rawBranch)) {
    throw new OccupancyLoadError('occupancy_branch_unavailable');
  }
  const range = resolveRange(request);
  const excludeHolidays = request.excludeHolidays ?? true;
  const reader = client as unknown as {
    rpc(
      name: 'owner_occupancy_analytics',
      args: { p_from: string; p_through: string; p_branch_id: string | null; p_exclude_holidays: boolean },
    ): Promise<{ data: unknown; error: OccupancyRpcError | null }>;
  };
  const result = await reader.rpc('owner_occupancy_analytics', {
    p_from: range.from,
    p_through: range.through,
    p_branch_id: rawBranch,
    p_exclude_holidays: excludeHolidays,
  });
  if (result.error !== null) throw new OccupancyLoadError(mapRpcError(result.error));
  // The RPC `returns jsonb`, so supabase-js supplies one scalar snapshot value —
  // never a row array. A null or absent value is an unavailable outcome, never
  // an empty success: no asOf means no claim.
  const raw = result.data;
  const snapshot = raw !== null && raw !== undefined && typeof raw === 'object' && !Array.isArray(raw)
    ? raw as Record<string, unknown>
    : undefined;
  if (snapshot === undefined || typeof snapshot.asOf !== 'string') {
    throw new OccupancyLoadError('occupancy_unavailable');
  }
  return {
    asOf: snapshot.asOf,
    from: range.from,
    through: range.through,
    branchId: rawBranch,
    excludeHolidays,
    months: Array.isArray(snapshot.months) ? snapshot.months as Array<Record<string, unknown>> : [],
    heatmap: snapshot.heatmap !== null && snapshot.heatmap !== undefined && typeof snapshot.heatmap === 'object'
      ? snapshot.heatmap as Record<string, unknown>
      : null,
    classes: snapshot.classes !== null && snapshot.classes !== undefined && typeof snapshot.classes === 'object'
      ? snapshot.classes as Record<string, unknown>
      : null,
    warnings: snapshot.warnings !== null && snapshot.warnings !== undefined && typeof snapshot.warnings === 'object'
      ? snapshot.warnings as Record<string, unknown>
      : {},
  };
}
