'use client';

import { useState } from 'react';
import { REPORT_DATASETS, REPORT_EXPORT_STATES, type ReportDataset, type ReportExportState } from '../../../lib/report-exports';

/**
 * One dataset's download form (RPE-013). The chosen dates are kept in state so
 * a refusal preserves the requested range, and every failure maps to its
 * frozen outcome state with the specific next action. The POST goes to the one
 * export route; a successful response is the CSV attachment itself.
 */

const FAILURE_STATE_BY_CODE: Record<string, ReportExportState> = {
  invalid_request: 'invalid_range',
  body_too_large: 'too_large',
  export_too_large: 'too_large',
  request_unavailable: 'unavailable',
  not_permitted: 'permission',
  export_integrity: 'integrity',
  audit_failed: 'audit',
  operation_failed: 'server_error',
};

export function ReportExportDownloadForm({ dataset }: { dataset: ReportDataset }) {
  const [from, setFrom] = useState('');
  const [through, setThrough] = useState('');
  const [pending, setPending] = useState(false);
  const [outcome, setOutcome] = useState<{ state: ReportExportState; detail?: string } | null>(null);

  const submit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setPending(true);
    setOutcome({ state: 'generating' });
    try {
      const response = await fetch('/api/report-exports', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ dataset, from, through }),
      });
      if (response.ok) {
        const blob = await response.blob();
        const disposition = response.headers.get('content-disposition') ?? '';
        const match = /filename="?([^";]+)"?/.exec(disposition);
        const url = URL.createObjectURL(blob);
        const anchor = document.createElement('a');
        anchor.href = url;
        anchor.download = match?.[1] ?? `${dataset}.csv`;
        anchor.click();
        URL.revokeObjectURL(url);
        setOutcome({ state: 'ready' });
      } else {
        const body = (await response.json().catch(() => null)) as { error?: { code?: string; message?: string } } | null;
        const code = body?.error?.code ?? 'server_error';
        const detail = body?.error?.message;
        setOutcome(detail !== undefined && detail.length > 0 ? { state: FAILURE_STATE_BY_CODE[code] ?? 'server_error', detail } : { state: FAILURE_STATE_BY_CODE[code] ?? 'server_error' });
      }
    } catch {
      setOutcome({ state: 'timeout' });
    } finally {
      setPending(false);
    }
  };

  const definition = REPORT_DATASETS[dataset];
  const shown = outcome === null ? null : REPORT_EXPORT_STATES[outcome.state];

  return (
    <form onSubmit={submit} className="cl-section" aria-label={`${definition.meaning}`}>
      <div className="cl-form-row">
        <label className="cl-field">
          <span>From</span>
          <input type="date" required value={from} onChange={(event) => setFrom(event.target.value)} className="cl-input" />
        </label>
        <label className="cl-field">
          <span>Through</span>
          <input type="date" required value={through} onChange={(event) => setThrough(event.target.value)} className="cl-input" />
        </label>
      </div>
      <button type="submit" className="cl-btn cl-btn--primary" disabled={pending}>
        {pending ? 'Generating…' : 'Download CSV'}
      </button>
      {shown !== null && (
        <p className="cl-muted" role="status">
          <strong>{shown.label}</strong> {shown.action}
          {outcome?.detail !== undefined && outcome.detail.length > 0 ? ` ${outcome.detail}` : ''}
        </p>
      )}
    </form>
  );
}