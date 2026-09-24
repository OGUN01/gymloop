import { loadOwnerMetrics, MetricsLoadError } from '../../../lib/metrics';
import { MetricsDashboard } from './metrics-dashboard';

type DashboardPageProps = {
  searchParams: Promise<{ from?: string; through?: string }>;
};

const METRICS_ERROR_MESSAGES = {
  invalid_metrics_range: 'Choose both dates and keep From on or before Through.',
  invalid_gym_timezone: "This gym's timezone is invalid. Ask an administrator to correct it.",
  metrics_unavailable: 'Metrics are unavailable right now.',
} as const;

export default async function DashboardPage({ searchParams }: DashboardPageProps) {
  try {
    const metrics = await loadOwnerMetrics(searchParams);
    return <MetricsDashboard metrics={metrics} />;
  } catch (error) {
    if (!(error instanceof MetricsLoadError)) throw error;
    return (
      <main className="dashboard-error-state">
        <p className="cl-eyebrow">Overview</p>
        <h1 className="cl-title">Metrics</h1>
        <p role="alert" className="cl-alert">{METRICS_ERROR_MESSAGES[error.code]}</p>
      </main>
    );
  }
}
