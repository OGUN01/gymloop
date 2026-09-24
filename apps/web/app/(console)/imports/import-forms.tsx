'use client';

import { useRef, useState, type ChangeEvent } from 'react';
import { Alert } from '../alert';
import { Field, inputClass } from '../field';
import type { BranchChoice, MemberImportRunRow } from '../../../lib/member-imports';

/**
 * The member-import screen's client half: one form that owns the whole
 * journey — upload → header inspection → column mapping → preview →
 * confirmation → report — over the four contract endpoints. The browser keeps
 * the `File` between steps; the same selected file is the `file` part of
 * every later request, and commit resubmits only the file.
 *
 * Every preview attempt carries one request key, minted when the mapping step
 * is first submitted and reused verbatim on an uncertain retry — a network
 * failure or an unknown error code may mean the preview landed, and a fresh
 * key would record a second run for the same upload.
 */

/** The error codes the import routes answer with, in the desk's words. */
const IMPORT_ERRORS: Record<string, string> = {
  not_signed_in: 'Your session ended. Sign in again, then start the import once more.',
  not_permitted: 'Your staff role cannot import members.',
  malformed_body: 'That upload could not be read. Re-select the file and submit it once more.',
  invalid_request: 'Check the form and submit again.',
  file_required: 'Choose the member file to upload, then submit again.',
  file_too_large: 'That file is larger than the 5 MiB limit. Split it and import the parts.',
  invalid_file_type: 'Only .csv and .xlsx files are accepted. Re-save the export in one of those forms.',
  invalid_utf8: 'That file is not valid UTF-8 text. Re-save it as UTF-8 and submit it again.',
  invalid_csv: 'That file is not a well-formed comma-separated file. Check the quoting and try again.',
  invalid_xlsx: 'That workbook cannot be read. Re-save it as a plain .xlsx without macros or encryption.',
  too_many_xlsx_entries: 'That workbook holds too many parts. Export a plain single-sheet .xlsx.',
  xlsx_expansion_too_large: 'That workbook expands beyond the size limit. Remove hidden sheets or content and try again.',
  missing_header: 'The first row must be the column header. Add it and submit again.',
  invalid_header: 'Header cells must be non-empty and unique. Fix the first row and try again.',
  too_many_rows: 'That file holds more than 5,000 member rows. Split it and import the parts.',
  too_many_columns: 'That file has more than 64 columns. Remove the extra columns and try again.',
  too_many_cells: 'That sheet holds too many cells. Remove empty columns and rows.',
  cell_too_large: 'One cell is longer than the 2,000-character limit. Shorten it and try again.',
  extra_column: 'One row has more cells than the header. Remove the extra cells and try again.',
  invalid_mapping: 'Check the column mapping — every mapped column must exist, and one column cannot feed two fields.',
  source_changed: 'That file changed since it was inspected. Re-select it and submit once more.',
  idempotency_conflict: 'This request key was already used for a different preview. Reload the screen and start again.',
  preview_file_mismatch: 'That file is not the exact one this import was previewed with. Upload the same file to confirm, or start a new import.',
  preview_payload_mismatch: 'The file no longer produces the rows this import promised. Start a new import from the file list.',
  preview_expired: 'This import was previewed with an older version of the import tool. Start the import again from the file list.',
  import_not_pending: 'That import is no longer open for confirmation. Reload the import screen.',
  operation_failed: 'The import could not be completed. Nothing was changed.',
  processing_failed: 'The import failed during processing. Nothing was changed; retry with a new import.',
};

function importProblemText(code: string): string {
  return Object.hasOwn(IMPORT_ERRORS, code)
    ? IMPORT_ERRORS[code] ?? 'Review the details and try again.'
    : 'The outcome is uncertain. Retry the same step, or reload this screen.';
}

/** The error envelope an import route can answer with. */
type ImportErrorEnvelope = { code?: unknown } & Record<string, unknown>;

/** The contract's `ImportInspection`, as inspect returns it. */
type Inspection = {
  fileName: string;
  fileSha256: string;
  format: 'csv' | 'xlsx';
  headers: Array<{ index: number; label: string }>;
  rowCount: number;
  sampleRows: Array<{ rowNumber: number; cells: Array<string | null> }>;
};

/** The contract's `MemberImportPreview`. */
type Preview = {
  importId: string;
  status: 'pending' | 'completed' | 'failed';
  replayed: boolean;
  fileName: string;
  fileSha256: string;
  effectiveOn: string;
  counts: { rows: number; wouldImport: number; duplicates: number; invalid: number };
  sampleRows: Array<{
    rowNumber: number;
    normalized: Partial<Record<
      'full_name' | 'phone' | 'member_code' | 'email' | 'gender' |
      'date_of_birth' | 'joined_on' | 'notes',
      string | null
    >>;
    disposition: 'would_import' | 'duplicate' | 'invalid';
    reasonCodes: string[];
  }>;
  hasMoreRows: boolean;
};

/** The contract's `MemberImportCommitResult`. */
type CommitResult = {
  importId: string;
  status: 'completed' | 'failed';
  replayed: boolean;
  counts: { rows: number; imported: number; duplicates: number; invalid: number };
  failure: null | { code: 'processing_failed' };
  errorReportUrl: string;
};

/** The member fields a mapping select is named after, in canonical order. */
const MAPPABLE_FIELDS = [
  'full_name', 'phone', 'member_code', 'email', 'gender', 'date_of_birth', 'joined_on', 'notes',
] as const;

type Step = 'upload' | 'mapping' | 'preview' | 'report';

/** The numbered eyebrow and heading over each step of the journey. */
function StepHead({ number, title }: { number: number; title: string }) {
  return <div>
    <p className="cl-eyebrow">Step {number} of 4</p>
    <h2 className="cl-section-title">{title}</h2>
  </div>;
}

/** One labelled count in a `cl-metrics` row. */
function Metric({ label, value }: { label: string; value: number }) {
  return <div className="cl-metric"><span className="cl-eyebrow">{label}</span><span className="cl-metric-value tabular-nums">{value}</span></div>;
}

export function MemberImportForm({ branches, runs: _runs, timezone }: {
  branches: BranchChoice[];
  runs: MemberImportRunRow[];
  timezone: string | null;
}) {
  void _runs;
  const [step, setStep] = useState<Step>('upload');
  const [file, setFile] = useState<File | null>(null);
  const [inspection, setInspection] = useState<Inspection | null>(null);
  const [mapping, setMapping] = useState<Record<string, string>>({});
  const [branchId, setBranchId] = useState<string>(branches[0]?.id ?? '');
  const [phoneDefaultCountry, setPhoneDefaultCountry] = useState<'IN' | 'E164'>('IN');
  const [preview, setPreview] = useState<Preview | null>(null);
  const [result, setResult] = useState<CommitResult | null>(null);
  const [pending, setPending] = useState(false);
  const [problem, setProblem] = useState('');
  // One request key per preview attempt: minted when the mapping step first
  // submits, reused verbatim on an uncertain retry so a lost response replays
  // the same prepare instead of recording a second run.
  const requestKey = useRef<string | null>(null);

  async function post(path: string, body: FormData): Promise<{ ok: boolean; data: Record<string, unknown> | null; errorCode: string }> {
    const response = await fetch(path, { method: 'POST', body });
    const payload = await response.json() as { ok?: boolean; data?: Record<string, unknown>; error?: ImportErrorEnvelope };
    return {
      ok: response.ok && payload.ok === true && payload.data !== null && payload.data !== undefined && typeof payload.data === 'object',
      data: (payload.data ?? null) as Record<string, unknown> | null,
      errorCode: typeof payload.error?.code === 'string' ? payload.error.code : '',
    };
  }

  async function submitUpload(event: { preventDefault: () => void }): Promise<void> {
    event.preventDefault();
    if (file === null) {
      setProblem('Choose the member file to upload, then submit again.');
      return;
    }
    setPending(true);
    setProblem('');
    try {
      const form = new FormData();
      form.append('file', file);
      const answer = await post('/api/member-imports/inspect', form);
      if (answer.ok) {
        setInspectionData(answer.data as unknown as Inspection);
        return;
      }
      setProblem(importProblemText(answer.errorCode));
    } catch {
      setProblem('The connection was interrupted. The outcome is uncertain. Retry the same upload.');
    } finally {
      setPending(false);
    }
  }

  function setInspectionData(data: Inspection): void {
    setInspection(data);
    setStep('mapping');
    // The file input keeps the File; the mapping selects start unmapped.
    setMapping({});
  }

  async function submitPreview(event: { preventDefault: () => void }): Promise<void> {
    event.preventDefault();
    if (file === null || inspection === null) return;
    const selected: Record<string, number> = {};
    for (const field of MAPPABLE_FIELDS) {
      const value = mapping[field];
      if (value !== undefined && value !== '') selected[field] = Number(value);
    }
    if (selected.full_name === undefined || selected.phone === undefined) {
      setProblem('Map the full-name and phone columns before previewing.');
      return;
    }
    if (branchId === '') {
      setProblem('Choose the one branch the whole file is imported into.');
      return;
    }
    setPending(true);
    setProblem('');
    const key = requestKey.current ?? crypto.randomUUID();
    requestKey.current = key;
    try {
      const form = new FormData();
      form.append('file', file);
      form.append('inspectedFileSha256', inspection.fileSha256);
      form.append('requestKey', key);
      form.append('branchId', branchId);
      form.append('phoneDefaultCountry', phoneDefaultCountry);
      form.append('columnMapping', JSON.stringify(selected));
      const answer = await post('/api/member-imports', form);
      if (answer.ok) {
        setPreviewData(answer.data as unknown as Preview);
        return;
      }
      // A known failure is definitive — nothing was written — so the next
      // attempt mints a fresh key. An unknown code leaves the outcome
      // uncertain and this key preserved for the retry.
      if (Object.hasOwn(IMPORT_ERRORS, answer.errorCode)) requestKey.current = null;
      setProblem(importProblemText(answer.errorCode));
    } catch {
      setProblem('The connection was interrupted. The outcome is uncertain. Retry the same preview — the same request key is reused.');
    } finally {
      setPending(false);
    }
  }

  function setPreviewData(data: Preview): void {
    setPreview(data);
    setStep('preview');
  }

  async function submitCommit(event: { preventDefault: () => void }): Promise<void> {
    event.preventDefault();
    if (file === null || preview === null) return;
    setPending(true);
    setProblem('');
    try {
      const form = new FormData();
      form.append('file', file);
      const answer = await post(`/api/member-imports/${preview.importId}/commit`, form);
      if (answer.ok) {
        setResult(answer.data as unknown as CommitResult);
        setStep('report');
        return;
      }
      setProblem(importProblemText(answer.errorCode));
    } catch {
      setProblem('The connection was interrupted. The outcome is uncertain. Retry the same confirmation — commit replays exactly.');
    } finally {
      setPending(false);
    }
  }

  function onFileChosen(event: ChangeEvent<HTMLInputElement>): void {
    const chosen = event.target.files?.[0] ?? null;
    setFile(chosen);
  }

  if (step === 'upload') {
    return <form method="post" onSubmit={submitUpload} className="cl-form cl-section">
      <StepHead number={1} title="Upload the file" />
      <Field label="Member file (.csv or .xlsx)">
        <input type="file" accept=".csv,.xlsx" onChange={onFileChosen} className={inputClass} />
      </Field>
      <div className="cl-form-row">
        <Field label="Branch">
          <select name="branchId" value={branchId} onChange={(event) => setBranchId(event.target.value)} className={inputClass}>
            {branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}
          </select>
        </Field>
        <Field label="Phone numbers">
          <select name="phoneDefaultCountry" value={phoneDefaultCountry} onChange={(event) => setPhoneDefaultCountry(event.target.value === 'E164' ? 'E164' : 'IN')} className={inputClass}>
            <option value="IN">Indian numbers (+91 added to bare 10-digit mobiles)</option>
            <option value="E164">All numbers already international (+country code)</option>
          </select>
        </Field>
      </div>
      {problem !== '' ? <Alert>{problem}</Alert> : null}
      <button type="submit" disabled={pending} className="cl-btn cl-btn--primary self-start justify-self-start">
        {pending ? 'Inspecting…' : 'Inspect file'}
      </button>
    </form>;
  }

  if (step === 'mapping' && inspection !== null) {
    return <form method="post" onSubmit={submitPreview} className="cl-form cl-section">
      <StepHead number={2} title="Match the columns" />
      <p className="cl-muted tabular-nums">
        {inspection.fileName} · {inspection.rowCount} data row{inspection.rowCount === 1 ? '' : 's'} · {inspection.format.toUpperCase()}
      </p>
      <div className="cl-form-row">
        {MAPPABLE_FIELDS.map((field) => <Field key={field} label={field.replaceAll('_', ' ')}>
          <select name={field} value={mapping[field] ?? ''} onChange={(event) => setMapping((current) => ({ ...current, [field]: event.target.value }))} className={inputClass}>
            <option value="">Not mapped</option>
            {inspection.headers.map((header) => <option key={header.index} value={String(header.index)}>{header.label}</option>)}
          </select>
        </Field>)}
        <Field label="Branch">
          <select name="branchId" value={branchId} onChange={(event) => setBranchId(event.target.value)} className={inputClass}>
            {branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}
          </select>
        </Field>
        <Field label="Phone numbers">
          <select name="phoneDefaultCountry" value={phoneDefaultCountry} onChange={(event) => setPhoneDefaultCountry(event.target.value === 'E164' ? 'E164' : 'IN')} className={inputClass}>
            <option value="IN">Indian numbers (+91 added to bare 10-digit mobiles)</option>
            <option value="E164">All numbers already international (+country code)</option>
          </select>
        </Field>
      </div>
      <details className="cl-disclosure">
        <summary>First rows of the file</summary>
        <div className="cl-ledger-wrap">
          <table className="cl-ledger">
            <thead><tr>
              {inspection.headers.map((header) => <th key={header.index} scope="col">{header.label}</th>)}
            </tr></thead>
            <tbody>
              {inspection.sampleRows.map((row) => <tr key={row.rowNumber}>
                {row.cells.map((cell, index) => <td key={index}>{cell ?? ''}</td>)}
              </tr>)}
            </tbody>
          </table>
        </div>
      </details>
      {problem !== '' ? <Alert>{problem}</Alert> : null}
      <button type="submit" disabled={pending} className="cl-btn cl-btn--primary self-start justify-self-start">
        {pending ? 'Previewing…' : 'Preview import'}
      </button>
    </form>;
  }

  if (step === 'preview' && preview !== null) {
    const dispositions = { would_import: 'Would import', duplicate: 'Duplicate', invalid: 'Invalid' } as const;
    const tones = { would_import: 'ok', duplicate: 'warn', invalid: 'risk' } as const;
    return <form method="post" onSubmit={submitCommit} className="cl-form cl-section">
      <StepHead number={3} title="Check the preview" />
      <p className="cl-muted">{preview.fileName}</p>
      <div className="cl-metrics">
        <Metric label="Rows" value={preview.counts.rows} />
        <Metric label="Would import" value={preview.counts.wouldImport} />
        <Metric label="Duplicates" value={preview.counts.duplicates} />
        <Metric label="Invalid" value={preview.counts.invalid} />
      </div>
      <p>Effective on <strong className="tabular-nums">{preview.effectiveOn}</strong>{timezone !== null ? <span className="cl-muted"> ({timezone})</span> : null}</p>
      <p className="cl-alert" data-tone="warn" role="status">
        Final imports may be fewer than this preview when a member appears after preview.
      </p>
      <div className="cl-ledger-wrap">
        <table className="cl-ledger cl-ledger-stack">
          <thead><tr><th scope="col">Row</th><th scope="col">Result</th><th scope="col">Details</th><th scope="col">Reasons</th></tr></thead>
          <tbody>
            {preview.sampleRows.map((row) => <tr key={row.rowNumber}>
              <td className="tabular-nums">{`Row ${row.rowNumber}`}</td>
              <td><span className="cl-status" data-tone={tones[row.disposition]} data-status={row.disposition}>{dispositions[row.disposition]}</span></td>
              <td>
                {Object.entries(row.normalized).filter(([, value]) => value !== null && value !== undefined)
                  .map(([field, value]) => `${field.replaceAll('_', ' ')}: ${String(value)}`).join(' · ')}
              </td>
              <td className="cl-muted">{row.reasonCodes.join(', ')}</td>
            </tr>)}
          </tbody>
        </table>
      </div>
      {preview.hasMoreRows ? <p className="cl-muted">Showing the first 100 rows</p> : null}
      {problem !== '' ? <Alert>{problem}</Alert> : null}
      <button type="submit" disabled={pending} className="cl-btn cl-btn--primary self-start justify-self-start">
        {pending ? 'Importing…' : `Import ${preview.counts.wouldImport} members`}
      </button>
    </form>;
  }

  if (step === 'report' && result !== null) {
    return <section className="cl-section" aria-labelledby="import-report-heading">
      <p className="cl-eyebrow">Step 4 of 4</p>
      <div className="cl-section-head">
        <h2 id="import-report-heading" className="cl-section-title">{result.status === 'completed' ? 'Import complete' : 'Import failed'}</h2>
        <a href={result.errorReportUrl} className="cl-btn">Download the error report</a>
      </div>
      {result.failure !== null ? <Alert>{result.failure.code}</Alert> : null}
      <div className="cl-metrics">
        <Metric label="Imported" value={result.counts.imported} />
        <Metric label="Rows" value={result.counts.rows} />
        <Metric label="Duplicates" value={result.counts.duplicates} />
        <Metric label="Invalid" value={result.counts.invalid} />
      </div>
    </section>;
  }

  return null;
}
