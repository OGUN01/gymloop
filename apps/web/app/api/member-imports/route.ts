import {
  MEMBER_IMPORT_REPORT_REASON_CODES,
  memberImportPhoneCountrySchema,
  validateMemberImportMapping,
  type MemberImportPreviewRow,
} from '@gymloop/shared';
import { UUID_PATTERN } from '../../../lib/keyset';
import {
  authorizedUpload,
  canonicalUuidField,
  importFail,
  importOk,
  isSha256Hex,
  previewArgsFrom,
  previewSampleFrom,
  reportRowEntries,
} from './support';

/** The typed phone-country mode, from the shared catalogue. */
function phoneCountryField(value: FormDataEntryValue | null): 'IN' | 'E164' | null {
  if (typeof value !== 'string') return null;
  return memberImportPhoneCountrySchema.safeParse(value).success
    ? (value as 'IN' | 'E164')
    : null;
}

/**
 * `POST /api/member-imports` — preview one member import.
 *
 * Accepts multipart `file`, `inspectedFileSha256`, `requestKey`, `branchId`,
 * `phoneDefaultCountry` and JSON `columnMapping`. The handler recomputes the
 * raw-file SHA-256 and answers `409 source_changed` when it differs from
 * `inspectedFileSha256`; it then reparses and phase-A-normalizes
 * server-side before calling `public.prepare_member_import(...)`. That RPC
 * derives the verified JWT user, tenant and real staff identity from claims,
 * validates the same-tenant branch, freezes the gym-local `effective_on`,
 * defaults blank joined dates and raises future-date errors, classifies all
 * same-gym and within-file duplicates in one un-truncated response, and
 * inserts one `pending` v1 run with immutable evidence. Blank `joined_on`
 * stays null here and syntactically valid dates are not compared with
 * today's date in this handler.
 */

/**
 * The database refusal codes the contract names for prepare, each with the
 * one honest answer. Stored facts are never echoed: a reused request key
 * with different immutable facts reads as a generic conflict (GL068's own
 * message would disclose the stored key and uploader), and nothing from
 * another tenant is ever described.
 */
const PREPARE_REFUSALS: Record<string, { status: 'conflict' | 'forbidden' | 'bad_request'; code: string; message: string }> = {
  GL068: {
    status: 'conflict',
    code: 'idempotency_conflict',
    message: 'This request key was already used for a different preview. Start the import again — the safe attempt gets a fresh key.',
  },
  '42501': {
    status: 'forbidden',
    code: 'not_permitted',
    message: 'Your staff role cannot import members.',
  },
  '22023': {
    status: 'bad_request',
    code: 'invalid_request',
    message: 'That preview request is malformed. Reopen the import screen and try again.',
  },
};

/** One prepare refusal, without revealing any stored fact. */
function prepareFailure(error: { code: string }): Response {
  const refusal = Object.hasOwn(PREPARE_REFUSALS, error.code)
    ? PREPARE_REFUSALS[error.code]
    : undefined;
  return refusal === undefined
    ? importFail('server_error', 'operation_failed', 'The preview could not be recorded. Nothing was written.')
    : importFail(refusal.status, refusal.code, refusal.message);
}

/** The winning prepare or replay result, as the contract freezes it. */
type PrepareResult = {
  importId: string;
  status: 'pending' | 'completed' | 'failed';
  replayed: boolean;
  effectiveOn: string;
  counts: { rows: number; wouldImport: number; duplicates: number; invalid: number };
  report: unknown;
};

/**
 * Narrows the RPC's answer to the contract's prepare shape. A result that
 * does not match is treated as a failure rather than passed through — an RPC
 * that answers nonsense must not be turned into a success the owner then
 * acts on.
 */
function prepareResult(data: unknown): PrepareResult | null {
  if (typeof data !== 'object' || data === null) return null;
  const facts = data as Record<string, unknown>;
  if (typeof facts.importId !== 'string' || !UUID_PATTERN.test(facts.importId)) return null;
  if (facts.status !== 'pending' && facts.status !== 'completed' && facts.status !== 'failed') return null;
  if (typeof facts.replayed !== 'boolean') return null;
  if (typeof facts.effectiveOn !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(facts.effectiveOn)) return null;
  if (typeof facts.counts !== 'object' || facts.counts === null) return null;
  const counts = facts.counts as Record<string, unknown>;
  const rows = counts.rows;
  const wouldImport = counts.wouldImport;
  const duplicates = counts.duplicates;
  const invalid = counts.invalid;
  if (typeof rows !== 'number' || typeof wouldImport !== 'number' ||
    typeof duplicates !== 'number' || typeof invalid !== 'number') return null;
  if (facts.report === undefined || typeof facts.report !== 'object' || facts.report === null) return null;
  return {
    importId: facts.importId,
    status: facts.status,
    replayed: facts.replayed,
    effectiveOn: facts.effectiveOn,
    counts: { rows, wouldImport, duplicates, invalid },
    report: facts.report,
  };
}

/**
 * One stored report row, narrowed to the fields the preview sample reads.
 * The allowlist is the shared module's; anything else is not a report row.
 */
function reportRows(report: unknown): Array<{ rowNumber: number; disposition: string; reasonCode: string }> | null {
  const entries = reportRowEntries(report);
  if (entries === null) return null;
  const known = new Set<string>(MEMBER_IMPORT_REPORT_REASON_CODES);
  const out: Array<{ rowNumber: number; disposition: string; reasonCode: string }> = [];
  for (const entry of entries) {
    if (typeof entry.reasonCode !== 'string' || !known.has(entry.reasonCode)) return null;
    out.push({ rowNumber: entry.rowNumber, disposition: entry.disposition, reasonCode: entry.reasonCode });
  }
  return out;
}

/** The disposition a preview sample row shows for one report item's row. */
function dispositionOf(stored: string): MemberImportPreviewRow['disposition'] {
  if (stored === 'imported') return 'would_import';
  if (stored === 'would_import') return 'would_import';
  if (stored === 'duplicate') return 'duplicate';
  return 'invalid';
}

export async function POST(request: Request): Promise<Response> {
  const upload = await authorizedUpload(request);
  if ('failure' in upload) return upload.failure;
  const { form, ...caller } = upload;

  // The digest the caller presents must be exactly what inspect returned:
  // replay binds every later command to those bytes.
  const inspected = form.get('inspectedFileSha256');
  if (typeof inspected !== 'string' || !isSha256Hex(inspected)) {
    return importFail('bad_request', 'invalid_request', 'That preview request is missing the inspected-file digest. Inspect the file again.');
  }
  if (inspected !== upload.fileSha256) {
    return importFail('conflict', 'source_changed', 'That file changed since it was inspected. Re-select it and submit once more.');
  }

  const requestKey = canonicalUuidField(form.get('requestKey'));
  if (requestKey === null) {
    return importFail('bad_request', 'invalid_request', 'That preview attempt is missing a valid request key. Reopen the import screen.');
  }
  const branchId = canonicalUuidField(form.get('branchId'));
  if (branchId === null) {
    return importFail('bad_request', 'invalid_request', 'Choose the one branch the whole file is imported into.');
  }

  const country = phoneCountryField(form.get('phoneDefaultCountry'));
  if (country === null) {
    return importFail('bad_request', 'invalid_request', 'Choose how bare phone numbers are treated: with the Indian country code, or already international.');
  }

  const mappingField = form.get('columnMapping');
  if (typeof mappingField !== 'string') {
    return importFail('bad_request', 'invalid_request', 'The column mapping is missing. Map the columns and submit again.');
  }
  let mappingInput: unknown;
  try {
    mappingInput = JSON.parse(mappingField) as unknown;
  } catch {
    return importFail('bad_request', 'invalid_request', 'The column mapping is not valid JSON. Map the columns and submit again.');
  }
  const validated = validateMemberImportMapping(mappingInput, upload.parsed.headers.length);
  if ('error' in validated) {
    return importFail('unprocessable', 'invalid_mapping', 'Check the column mapping — every mapped column must exist, and one column cannot feed two fields.');
  }

  // `prepare_member_import` is not in the generated types yet — the migration
  // lands with this phase and `supabase gen types` follows it. Until then it
  // is called through the same narrow local cast the leads routes use, with
  // the wire payload derived from the frozen contract. The RPC derives the
  // verified JWT user, tenant and real staff identity from claims; neither is
  // an argument here.
  const writer = caller.supabase as unknown as {
    rpc(name: 'prepare_member_import', args: Record<string, unknown>): Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };

  const { data, error } = await writer.rpc(
    'prepare_member_import',
    previewArgsFrom(upload.parsed, validated.mapping, requestKey, upload.fileName, upload.fileSha256, branchId, country),
  );

  if (error !== null) return prepareFailure(error);

  const prepared = prepareResult(data);
  if (prepared === null) {
    return importFail('server_error', 'operation_failed', 'The preview could not be confirmed. Nothing was written.');
  }
  const rows = reportRows(prepared.report);
  if (rows === null) {
    return importFail('server_error', 'operation_failed', 'The preview could not be confirmed. Nothing was written.');
  }

  // The sample is built from the returned day and dispositions, so displayed
  // blank joined dates and future-date errors match persisted evidence. A row
  // the report does not name is one of the pending run's candidates — its
  // disposition is `would_import` (the report partitions every non-blank row
  // between previewCandidateRows and rows), so the default must say that.
  const reasonOrder = new Map<string, number>(MEMBER_IMPORT_REPORT_REASON_CODES.map((code, index) => [code, index]));
  const dispositions = new Map<number, { disposition: MemberImportPreviewRow['disposition']; reasonCodes: string[] }>();
  for (const row of rows) {
    const current = dispositions.get(row.rowNumber) ?? { disposition: 'would_import' as MemberImportPreviewRow['disposition'], reasonCodes: [] as string[] };
    const codes = current.reasonCodes.includes(row.reasonCode)
      ? current.reasonCodes
      : [...current.reasonCodes, row.reasonCode];
    codes.sort((left, right) => (reasonOrder.get(left) ?? reasonOrder.size) - (reasonOrder.get(right) ?? reasonOrder.size));
    dispositions.set(row.rowNumber, {
      disposition: dispositionOf(row.disposition),
      reasonCodes: codes,
    });
  }

  const { sampleRows, hasMoreRows } = previewSampleFrom(upload.parsed, validated.mapping, country, prepared.effectiveOn, dispositions);
  return importOk({
    importId: prepared.importId,
    status: prepared.status,
    replayed: prepared.replayed,
    fileName: upload.fileName,
    fileSha256: upload.fileSha256,
    effectiveOn: prepared.effectiveOn,
    counts: prepared.counts,
    sampleRows,
    hasMoreRows,
  });
}
