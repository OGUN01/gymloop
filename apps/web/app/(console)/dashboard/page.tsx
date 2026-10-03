import type { ReactNode } from 'react';
import { requireAudience } from '../../../lib/identity-session';
import { loadBusinessNouns } from '../../../lib/business-type';
import { type BusinessNouns } from '@gymloop/shared';
import { loadOwnerMetrics, MetricsLoadError } from '../../../lib/metrics';
import { OccupancyLoadError, loadOccupancyAnalytics } from '../../../lib/occupancy';
import { MetricsDashboard } from './metrics-dashboard';
import { OccupancyAnalytics } from './occupancy-analytics';

type DashboardPageProps = {
  searchParams: Promise<{ from?: string; through?: string; occupancy?: string; branch?: string; excludeHolidays?: string }>;
};

const metricsErrorMessages = (nouns: BusinessNouns) => ({
  invalid_metrics_range: 'Choose both dates and keep From on or before Through.',
  invalid_gym_timezone: `This ${nouns.place}'s timezone is invalid. Ask an administrator to correct it.`,
  metrics_unavailable: 'Metrics are unavailable right now.',
} as const);

const occupancyErrorMessages = (nouns: BusinessNouns) => ({
  invalid_occupancy_range: 'Choose both dates and keep From on or before Through.',
  invalid_gym_timezone: `This ${nouns.place}'s timezone is invalid. Ask an administrator to correct it.`,
  occupancy_branch_unavailable: 'That branch is not available in this snapshot.',
  occupancy_unavailable: 'Occupancy analytics are unavailable right now.',
});

/** The occupancy panel loads only when the owner asks for it: the default
 * overview render stays the single owner_metrics read it has always been. */
async function occupancySection(caller: { identity: unknown; supabase: unknown }, params: {
  from?: string;
  through?: string;
  occupancy?: string;
  branch?: string;
  excludeHolidays?: string;
}, nouns: BusinessNouns): Promise<ReactNode> {
  const identity = caller.identity as { kind?: string; role?: string } | null;
  const isOwnerReader = identity !== null && identity.kind === 'staff'
    && (identity.role === 'gym_owner' || identity.role === 'gym_manager');
  if (!isOwnerReader) return null;
  if (params.occupancy !== '1') {
    return <OccupancyAnalytics errorLabel={null} nouns={nouns} snapshot={null} />;
  }
  try {
    const request: { from?: string; through?: string; branchId: string | null; excludeHolidays: boolean } = {
      branchId: params.branch ?? null,
      excludeHolidays: params.excludeHolidays !== '0',
    };
    if (params.from !== undefined) request.from = params.from;
    if (params.through !== undefined) request.through = params.through;
    const snapshot = await loadOccupancyAnalytics(caller.identity, caller.supabase, request);
    return <OccupancyAnalytics errorLabel={null} nouns={nouns} snapshot={snapshot} />;
  } catch (error) {
    if (!(error instanceof OccupancyLoadError)) throw error;
    return <OccupancyAnalytics errorLabel={occupancyErrorMessages(nouns)[error.code]} nouns={nouns} snapshot={null} />;
  }
}

export default async function DashboardPage({ searchParams }: DashboardPageProps) {
  const businessCaller = await requireAudience('console');
  const nouns = await loadBusinessNouns(businessCaller.supabase, businessCaller.identity.tenantId);
  const params = await searchParams;
  try {
    const metrics = await loadOwnerMetrics(searchParams);
    const occupancy = await occupancySection(businessCaller, params, nouns);
    return <MetricsDashboard nouns={nouns} metrics={metrics} occupancy={occupancy} />;
  } catch (error) {
    if (!(error instanceof MetricsLoadError)) throw error;
    return (
      <main className="dashboard-error-state">
        <p className="cl-eyebrow">Overview</p>
        <h1 className="cl-title">Metrics</h1>
        <p role="alert" className="cl-alert">{metricsErrorMessages(nouns)[error.code]}</p>
      </main>
    );
  }
}
