import { isoDaySchema, ownerMetricsSchema, type OwnerMetrics } from '@gymloop/shared';
import { redirect } from 'next/navigation';
import { identityHome } from './identity';
import { requireAudience } from './identity-session';

export type MetricsLoadErrorCode =
  | 'invalid_metrics_range'
  | 'invalid_gym_timezone'
  | 'metrics_unavailable';

export class MetricsLoadError extends Error {
  constructor(public readonly code: MetricsLoadErrorCode) {
    super(code);
    this.name = 'MetricsLoadError';
  }
}

type MetricsRpcError = {
  code?: string;
  message?: string;
  details?: string;
  hint?: string;
};

function mapMetricsError(error: MetricsRpcError): MetricsLoadErrorCode {
  if (error.code !== '22023') return 'metrics_unavailable';
  const evidence = `${error.message ?? ''} ${error.details ?? ''} ${error.hint ?? ''}`.toLowerCase();
  return evidence.includes('timezone') ? 'invalid_gym_timezone' : 'invalid_metrics_range';
}

function parseMetricsRange(params: { from?: string; through?: string }): {
  from: string | null;
  through: string | null;
} {
  if ((params.from === undefined) !== (params.through === undefined)) {
    throw new MetricsLoadError('invalid_metrics_range');
  }
  if (params.from === undefined || params.through === undefined) {
    return { from: null, through: null };
  }
  if (!isoDaySchema.safeParse(params.from).success || !isoDaySchema.safeParse(params.through).success) {
    throw new MetricsLoadError('invalid_metrics_range');
  }
  if (params.from > params.through) throw new MetricsLoadError('invalid_metrics_range');
  return { from: params.from, through: params.through };
}

export async function loadOwnerMetrics(
  searchParams: Promise<{ from?: string; through?: string }>,
): Promise<OwnerMetrics> {
  const { supabase, identity } = await requireAudience('console');
  const isOwnerReader = identity.kind === 'staff' &&
    (identity.role === 'gym_owner' || identity.role === 'gym_manager');
  if (!isOwnerReader) redirect(identityHome(identity));

  const params = await searchParams;
  const range = parseMetricsRange(params);
  const reader = supabase as unknown as {
    rpc(
      name: 'owner_metrics',
      args: { p_from: string | null; p_through: string | null },
    ): Promise<{ data: unknown; error: MetricsRpcError | null }>;
  };
  const result = await reader.rpc('owner_metrics', {
    p_from: range.from,
    p_through: range.through,
  });
  if (result.error !== null) throw new MetricsLoadError(mapMetricsError(result.error));

  const parsed = ownerMetricsSchema.safeParse(result.data);
  if (!parsed.success) throw new MetricsLoadError('metrics_unavailable');
  return parsed.data;
}
