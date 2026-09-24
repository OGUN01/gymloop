import { humanize } from '@gymloop/shared';

const OK = new Set(['active', 'captured', 'completed', 'succeeded', 'paid', 'delivered', 'converted', 'granted', 'recovered', 'returned', 'approved', 'ready']);
const WARN = new Set(['paused', 'pending', 'created', 'scheduled', 'trial', 'trial_scheduled', 'trial_done', 'open', 'contacted', 'follow_up_due', 'onboarding', 'sent', 'queued', 'requested', 'processing', 'due']);
const RISK = new Set(['expired', 'cancelled', 'blocked', 'failed', 'overdue', 'suspended', 'lost', 'rejected', 'refunded', 'at_risk']);

/** Any status vocabulary value as a Chalkline dot and a sentence-case word (UX9-003); unknown or informational values get a neutral dot, never alarm red. */
export function StatusWord({ status, label }: { status: string; label?: string }) {
  const tone = OK.has(status) ? 'ok' : WARN.has(status) ? 'warn' : RISK.has(status) ? 'risk' : 'neutral';
  return <span className="cl-status" data-tone={tone} data-status={status}>{label ?? humanize(status)}</span>;
}
