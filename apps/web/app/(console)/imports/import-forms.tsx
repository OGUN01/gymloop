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
    return <form method="post" onSubmit={submitUpload} className="mt-6 space-y-3 rounded-xl border border-neutral-200 p-4">
      <Field label="Member file (.csv or .xlsx)">
        <input type="file" accept=".csv,.xlsx" onChange={onFileChosen} className={inputClass} />
      </Field>
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
      {problem !== '' ? <Alert>{problem}</Alert> : null}
      <button type="submit" disabled={pending} className="min-h-11 rounded-lg bg-neutral-900 px-4 py-2 font-semibold text-white disabled:opacity-50">
        {pending ? 'Inspecting…' : 'Inspect file'}
      </button>
    </form>;
  }

  if (step === 'mapping' && inspection !== null) {
    return <form method="post" onSubmit={submitPreview} className="mt-6 space-y-4 rounded-xl border border-neutral-200 p-4">
      <p className="text-sm text-neutral-600">
        {inspection.fileName} · {inspection.rowCount} data row{inspection.rowCount === 1 ? '' : 's'} · {inspection.format.toUpperCase()}
      </p>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
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
      <details className="rounded-lg border border-neutral-200 p-3">
        <summary className="min-h-11 cursor-pointer font-medium">First rows of the file</summary>
        <table className="mt-2 w-full border-collapse text-left text-sm">
          <thead><tr className="border-b border-neutral-200 text-neutral-600">
            {inspection.headers.map((header) => <th key={header.index} scope="col" className="py-1 pr-3 font-medium">{header.label}</th>)}
          </tr></thead>
          <tbody>
            {inspection.sampleRows.map((row) => <tr key={row.rowNumber} className="border-b border-neutral-100">
              {row.cells.map((cell, index) => <td key={index} className="py-1 pr-3">{cell ?? ''}</td>)}
            </tr>)}
          </tbody>
        </table>
      </details>
      {problem !== '' ? <Alert>{problem}</Alert> : null}
      <button type="submit" disabled={pending} className="min-h-11 rounded-lg bg-neutral-900 px-4 py-2 font-semibold text-white disabled:opacity-50">
        {pending ? 'Previewing…' : 'Preview import'}
      </button>
    </form>;
  }

  if (step === 'preview' && preview !== null) {
    const dispositions = { would_import: 'Would import', duplicate: 'Duplicate', invalid: 'Invalid' } as const;
    return <form method="post" onSubmit={submitCommit} className="mt-6 space-y-4 rounded-xl border border-neutral-200 p-4">
      <p className="text-sm text-neutral-600">{preview.fileName}</p>
      <dl className="grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-4">
        <div><dt className="text-neutral-600">Rows</dt><dd className="tabular-nums">{preview.counts.rows}</dd></div>
        <div><dt className="text-neutral-600">Would import</dt><dd className="tabular-nums">{preview.counts.wouldImport}</dd></div>
        <div><dt className="text-neutral-600">Duplicates</dt><dd className="tabular-nums">{preview.counts.duplicates}</dd></div>
        <div><dt className="text-neutral-600">Invalid</dt><dd className="tabular-nums">{preview.counts.invalid}</dd></div>
      </dl>
      <p className="text-sm">Effective on <strong>{preview.effectiveOn}</strong>{timezone !== null ? <span> ({timezone})</span> : null}</p>
      <p className="rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-900">
        Final imports may be fewer than this preview when a member appears after preview.
      </p>
      <ul className="space-y-2">
        {preview.sampleRows.map((row) => <li key={row.rowNumber} className="rounded-lg border border-neutral-200 p-3 text-sm">
          <p className="font-medium">{`Row ${row.rowNumber} · ${dispositions[row.disposition]}`}</p>
          <p className="text-neutral-700">
            {Object.entries(row.normalized).filter(([, value]) => value !== null && value !== undefined)
              .map(([field, value]) => `${field.replaceAll('_', ' ')}: ${String(value)}`).join(' · ')}
          </p>
          {row.reasonCodes.length > 0 ? <p className="text-neutral-700">{row.reasonCodes.join(', ')}</p> : null}
        </li>)}
      </ul>
      {preview.hasMoreRows ? <p className="text-sm text-neutral-600">Showing the first 100 rows</p> : null}
      {problem !== '' ? <Alert>{problem}</Alert> : null}
      <button type="submit" disabled={pending} className="min-h-11 rounded-lg bg-neutral-900 px-4 py-2 font-semibold text-white disabled:opacity-50">
        {pending ? 'Importing…' : `Import ${preview.counts.wouldImport} members`}
      </button>
    </form>;
  }

  if (step === 'report' && result !== null) {
    return <div className="mt-6 space-y-3 rounded-xl border border-neutral-200 p-4">
      <h2 className="text-lg font-semibold">{result.status === 'completed' ? 'Import complete' : 'Import failed'}</h2>
      <dl className="grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-4">
        <div><dt className="text-neutral-600">Imported</dt><dd className="tabular-nums">{result.counts.imported}</dd></div>
        <div><dt className="text-neutral-600">Rows</dt><dd className="tabular-nums">{result.counts.rows}</dd></div>
        <div><dt className="text-neutral-600">Duplicates</dt><dd className="tabular-nums">{result.counts.duplicates}</dd></div>
        <div><dt className="text-neutral-600">Invalid</dt><dd className="tabular-nums">{result.counts.invalid}</dd></div>
      </dl>
      {result.failure !== null ? <p role="alert" className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{result.failure.code}</p> : null}
      <a href={result.errorReportUrl} className="inline-flex min-h-11 items-center underline">Download the error report</a>
    </div>;
  }

  return null;
}
