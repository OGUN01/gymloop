const OK = new Set(['active', 'captured', 'completed', 'succeeded', 'paid', 'delivered', 'converted', 'granted', 'recovered']);
const WARN = new Set(['paused', 'pending', 'created', 'scheduled', 'trial', 'trial_scheduled', 'open', 'contacted', 'follow_up_due', 'onboarding', 'sent', 'queued']);

/** Any status vocabulary value as a Chalkline dot and a sentence-case word (UX9-003); never colour alone, never the raw enum text. */
export function StatusWord({ status, label }: { status: string; label?: string }) {
  const tone = OK.has(status) ? 'ok' : WARN.has(status) ? 'warn' : 'risk';
  const words = (label ?? status).replaceAll('_', ' ');
  return <span className="cl-status" data-tone={tone} data-status={status}>{words.charAt(0).toUpperCase()}{words.slice(1)}</span>;
}
