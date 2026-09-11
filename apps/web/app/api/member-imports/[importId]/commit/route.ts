import { MEMBER_IMPORT_FIELDS, MEMBER_IMPORT_PARSER_CONTRACT, type MemberImportField } from '@gymloop/shared';
import {
  importFail,
  importFilePart,
  importOk,
  readImportForm,
  rawFileTooLarge,
  rowsWithFacts,
  sha256Hex,
  withImportCaller,
} from '../../support';
import {
  MemberImportParseError,
  parseMemberImportFile,
  type MemberImportParsedFile,
} from '../../../../../lib/member-import-parse';

/**
 * `POST /api/member-imports/{importId}/commit` — confirm one previewed import.
 *
 * Accepts only multipart `file`. Mapping, branch, country choice, parser
 * version and `effective_on` come from the pending run and cannot be
 * resubmitted. The route requires the same real staff and JWT user that
 * created the preview — both are checked inside the RPC against the stored
 * run, and the route's session gate already demanded a real owner/manager
 * (CSV-D01, CSV-D09).
 *
 * The order is the contract's: hash the bytes, then call
 * `public.commit_member_import(import_id, file_sha256, null)` as a state
 * probe. GL064 maps a byte mismatch to `409 preview_file_mismatch` and
 * leaves a pending run unchanged. A terminal result replays with
 * `replayed=true` without ZIP inspection, parser-version comparison, reparse
 * or row reconstruction — making terminal replay independent of an old
 * parser deployment. A pending probe returns the stored parser contract,
 * mapping and effective day; a different deployed parser maps to
 * `409 preview_expired` and leaves the run pending. Only then does the route
 * parse the exact file, apply phase-A normalization and the stored-day
 * defaults, reconstruct exactly the stored candidate rows (every canonical
 * field and null, and only the `would_import` row numbers), and call the
 * commit RPC with rows. GL063 maps a mismatch to
 * `409 preview_payload_mismatch`.
 */

/** The commit RPC's refusal table, exactly the contract's mapping. */
const COMMIT_REFUSALS: Record<string, { status: 'conflict' | 'forbidden' | 'bad_request'; code: string; message: string }> = {
  GL064: {
    status: 'conflict',
    code: 'preview_file_mismatch',
    message: 'That file is not the exact one this import was previewed with. Upload the same file to confirm, or start a new import.',
  },
  GL063: {
    status: 'conflict',
    code: 'preview_payload_mismatch',
    message: 'The file no longer produces the rows this import promised. Start a new import from the file list.',
  },
  '42501': {
    status: 'forbidden',
    code: 'not_permitted',
    message: 'Your staff role cannot import members.',
  },
  '55000': {
    status: 'conflict',
    code: 'import_not_pending',
    message: 'That import is no longer open for confirmation. Reload the import screen.',
  },
  '22023': {
    status: 'bad_request',
    code: 'invalid_request',
    message: 'That confirmation request is malformed. Reopen the import screen and try again.',
  },
};

/** One commit refusal, without revealing any stored or cross-tenant fact. */
function commitFailure(error: { code: string }): Response {
  const refusal = Object.hasOwn(COMMIT_REFUSALS, error.code)
    ? COMMIT_REFUSALS[error.code]
    : undefined;
  return refusal === undefined
    ? importFail('server_error', 'operation_failed', 'The import could not be completed. Its recorded result is unchanged.')
    : importFail(refusal.status, refusal.code, refusal.message);
}

/** A pending probe's answer, narrowed to what the route reconstructs from. */
type PendingProbe = {
  status: 'pending';
  parserContract: string;
  columnMapping: Record<string, number>;
  branchId: string;
  phoneDefaultCountry: string;
  effectiveOn: string;
  candidateRows: number[];
};

/** The counts a terminal result must carry, checked field by field. */
function isTerminalCounts(value: unknown): value is { rows: number; imported: number; duplicates: number; invalid: number } {
  if (typeof value !== 'object' || value === null) return false;
  const counts = value as Record<string, unknown>;
  return typeof counts.rows === 'number' && typeof counts.imported === 'number' &&
    typeof counts.duplicates === 'number' && typeof counts.invalid === 'number';
}

/**
 * Narrows the probe result. A terminal result replays as-is; a pending probe
 * is recognized by its stored parser contract; anything else is a failure
 * the route never turns into a success.
 */
function probeResult(data: unknown): { kind: 'terminal'; result: Record<string, unknown> } | { kind: 'pending'; probe: PendingProbe } | null {
  if (typeof data !== 'object' || data === null) return null;
  const facts = data as Record<string, unknown>;

  if ((facts.status === 'completed' || facts.status === 'failed') &&
    typeof facts.replayed === 'boolean' && isTerminalCounts(facts.counts) &&
    typeof facts.errorReportUrl === 'string') {
    return { kind: 'terminal', result: facts };
  }

  if (facts.status === 'pending' &&
    typeof facts.parserContract === 'string' && facts.parserContract !== '' &&
    typeof facts.columnMapping === 'object' && facts.columnMapping !== null && !Array.isArray(facts.columnMapping) &&
    typeof facts.effectiveOn === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(facts.effectiveOn) &&
    Array.isArray(facts.candidateRows)) {
    const mapping: Record<string, number> = {};
    for (const [key, value] of Object.entries(facts.columnMapping as Record<string, unknown>)) {
      if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) return null;
      mapping[key] = value;
    }
    const candidateRows: number[] = [];
    for (const rowNumber of facts.candidateRows) {
      if (typeof rowNumber !== 'number' || !Number.isInteger(rowNumber) || rowNumber < 1) return null;
      candidateRows.push(rowNumber);
    }
    return {
      kind: 'pending',
      probe: {
        status: 'pending',
        parserContract: facts.parserContract,
        columnMapping: mapping,
        branchId: typeof facts.branchId === 'string' ? facts.branchId : '',
        phoneDefaultCountry: typeof facts.phoneDefaultCountry === 'string' ? facts.phoneDefaultCountry : '',
        effectiveOn: facts.effectiveOn,
        candidateRows,
      },
    };
  }
  return null;
}

/**
 * Reconstructs the exact canonical candidate payload from the parsed file,
 * the stored mapping and the stored day: only the stored `would_import` row
 * numbers, each with `rowNumber` and every whitelisted field, nulls included
 * (CSV-D09a). Blank `joined_on` is set to the stored effective day — the
 * winning date prepare froze, never the day of this replay.
 */
function candidateRowsFrom(
  parsed: MemberImportParsedFile,
  mapping: Record<string, number>,
  phoneDefaultCountry: 'IN' | 'E164',
  effectiveOn: string,
  candidateRows: number[],
): Array<Record<string, unknown>> | null {
  const wanted = new Set(candidateRows);
  const withFacts = rowsWithFacts(parsed.rows, mapping as Partial<Record<MemberImportField, number>>, phoneDefaultCountry);
  const rows: Array<Record<string, unknown>> = [];
  for (const row of withFacts) {
    if (!wanted.has(row.rowNumber)) continue;
    if (row.errors.length > 0) return null;
    const { errors, ...facts } = row;
    void errors;
    rows.push({ ...facts, joined_on: facts.joined_on ?? effectiveOn });
  }
  return rows.length === candidateRows.length ? rows : null;
}

export const POST = withImportCaller(async (caller, request) => {
  const { importId } = caller;

  const body = await readImportForm(request);
  if ('failure' in body) return body.failure;
  const part = importFilePart(body.form);
  if ('failure' in part) return part.failure;
  if (rawFileTooLarge(part.file.size)) {
    return importFail('payload_too_large', 'file_too_large', 'That file is larger than the 5 MiB upload limit.');
  }
  const bytes = new Uint8Array(await part.file.arrayBuffer());
  const fileSha256 = sha256Hex(bytes);

  // `commit_member_import` is not in the generated types yet — the migration
  // lands with this phase and `supabase gen types` follows it. Until then it
  // is called through the same narrow local cast the leads routes use.
  const writer = caller.supabase as unknown as {
    rpc(name: 'commit_member_import', args: Record<string, unknown>): Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };

  // The SQL-NULL probe is an intentional state check and always runs first:
  // authorization, the run lock, the uploader comparison and the exact file
  // digest are the RPC's, and a terminal result must replay before anything
  // reads the parser version or a row (CSV-D09, CSV-D12).
  const probe = await writer.rpc('commit_member_import', { p_import_id: importId, p_file_sha256: fileSha256, p_rows: null });
  if (probe.error !== null) return commitFailure(probe.error);

  const read = probeResult(probe.data);
  if (read === null) {
    return importFail('server_error', 'operation_failed', 'The import could not be completed. Its recorded result is unchanged.');
  }
  if (read.kind === 'terminal') {
    const facts = read.result;
    const replay: Record<string, unknown> = {
      importId,
      status: facts.status,
      replayed: facts.replayed,
      counts: facts.counts,
      failure: (facts.failure as { code: 'processing_failed' } | null | undefined) ?? null,
      errorReportUrl: facts.errorReportUrl,
    };
    return importOk(replay);
  }

  // The run is pending: the stored parser contract must match this
  // deployment's, or the preview is stale and nothing is written.
  if (read.probe.parserContract !== MEMBER_IMPORT_PARSER_CONTRACT) {
    return importFail('conflict', 'preview_expired', 'This import was previewed with an older version of the import tool. Start the import again from the file list.');
  }

  const mapping = read.probe.columnMapping;
  for (const field of MEMBER_IMPORT_FIELDS) {
    const index = mapping[field];
    if (index === undefined) continue;
    if (!Number.isInteger(index) || index < 0) {
      return importFail('server_error', 'operation_failed', 'The import could not be completed. Its recorded result is unchanged.');
    }
  }
  const country = phoneCountryOf(read.probe.phoneDefaultCountry);
  if (country === null) return importFail('server_error', 'operation_failed', 'The import could not be completed. Its recorded result is unchanged.');

  // Only now the full file checks run, under the same fixed format as
  // inspect and preview.
  const fileName = part.file.name;
  let parsed: MemberImportParsedFile;
  try {
    parsed = await parseMemberImportFile(fileName, bytes);
  } catch (error) {
    if (error instanceof MemberImportParseError) return parseFailure(error);
    throw error;
  }

  const rows = candidateRowsFrom(parsed, mapping, country, read.probe.effectiveOn, read.probe.candidateRows);
  if (rows === null) {
    return importFail('conflict', 'preview_payload_mismatch', 'This file no longer produces the rows the preview promised. Start a new import.');
  }

  const result = await writer.rpc('commit_member_import', {
    p_import_id: importId,
    p_file_sha256: fileSha256,
    p_rows: rows,
  });
  if (result.error !== null) return commitFailure(result.error);
  const terminal = terminalResult(result.data, importId);
  if (terminal === null) {
    return importFail('server_error', 'operation_failed', 'The import could not be completed. Its recorded result is unchanged.');
  }
  return importOk(terminal);
});

/**
 * Narrows a terminal commit result to the contract's exact HTTP shape, with
 * the import id from the URL — the RPC's terminal result carries the run's
 * facts, and the route owns the reference it was called with.
 */
function terminalResult(data: unknown, importId: string): Record<string, unknown> | null {
  if (typeof data !== 'object' || data === null) return null;
  const facts = data as Record<string, unknown>;
  if ((facts.status !== 'completed' && facts.status !== 'failed') ||
    typeof facts.replayed !== 'boolean' || !isTerminalCounts(facts.counts) ||
    typeof facts.errorReportUrl !== 'string') {
    return null;
  }
  const failure = facts.failure;
  if (failure !== null && (typeof failure !== 'object' || failure === null ||
    (failure as Record<string, unknown>).code !== 'processing_failed')) {
    return null;
  }
  return {
    importId,
    status: facts.status,
    replayed: facts.replayed,
    counts: facts.counts,
    failure: (failure as { code: 'processing_failed' } | null) ?? null,
    errorReportUrl: facts.errorReportUrl,
  };
}

/** The stored phone-country mode, from the catalogue's two names. */
function phoneCountryOf(value: string): 'IN' | 'E164' | null {
  return value === 'IN' || value === 'E164' ? value : null;
}

/** One parse refusal during commit, with the same stable envelope. */
function parseFailure(error: MemberImportParseError): Response {
  return importFail('unprocessable', error.code, 'That file cannot be read under the import format. Start a new import with a clean file.');
}
