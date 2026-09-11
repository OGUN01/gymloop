import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createHash } from 'node:crypto';

/**
 * Phase 6 member-import HTTP boundary, authored from the frozen import
 * contract (docs/planning/phase6-import-contract.md) and the frozen module
 * layout (openspec/changes/phase6-import/plan.md) before any route, parser,
 * normalizer or RPC exists. The database suites own identity/RLS, duplicate
 * classification and run transitions; the unit suite owns CSV/XLSX bytes,
 * limits and normalization. Per the contract's test split, this suite owns
 * exact inspect/preview/commit file binding, the stable envelopes and
 * statuses of the "Stable file/API error codes" table, the SQL-null commit
 * probe running before parser-version comparison or row reconstruction,
 * terminal HTTP replay of both completed and failed runs, and the code-only
 * downloadable report. No production source and no other suite was consulted.
 *
 * The mocked `prepare_member_import`/`commit_member_import` results follow the
 * contract's own vocabulary: camelCase jsonb keys (the leads RPC convention),
 * the stored `error_report` shape for a pending prepare ("returns the winning
 * stored effective_on, report and counters"), the frozen terminal
 * `MemberImportCommitResult` fields for commit, and a pending probe returning
 * "the stored parser contract, mapping, branch, country, effective day and
 * candidate row numbers needed by the route".
 */
type Result = { data: unknown; error: { code: string; message: string } | null };

const state = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
  results: [] as Result[],
  operations: [] as Array<
    | { kind: 'rpc'; name: string; args: Record<string, unknown> }
    | { kind: 'table'; table: string }
  >,
}));

vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: async () => ({
    auth: { getClaims: async () => ({ data: state.claims && { claims: state.claims }, error: null }) },
    rpc: async (name: string, args: Record<string, unknown>) => {
      state.rpc.push({ name, args });
      state.operations.push({ kind: 'rpc', name, args });
      return state.results.shift() ?? { data: null, error: { code: 'XX000', message: 'Unexpected RPC' } };
    },
    from: (table: string) => {
      state.operations.push({ kind: 'table', table });
      const result = state.results.shift() ?? { data: null, error: null };
      const chain: Record<string, unknown> = {
        then: (resolve: (value: Result) => unknown) => Promise.resolve(result).then(resolve),
        single: async () => result,
        maybeSingle: async () => result,
      };
      for (const method of ['insert', 'update', 'delete', 'select', 'eq', 'limit', 'order', 'range']) {
        chain[method] = () => chain;
      }
      return chain;
    },
  }),
}));

const TENANT_ID = '11111111-1111-4111-8111-111111111111';
const STAFF_ID = '22222222-2222-4222-8222-222222222222';
const MEMBER_ID = '33333333-3333-4333-8333-333333333333';
const BRANCH_ID = '44444444-4444-4444-8444-444444444444';
const IMPORT_ID = '55555555-5555-4555-8555-555555555555';
const REQUEST_KEY = 'a1a2a3a4-b1b2-4c3c-8d4d-e1e2e3e4e5e6';

const OWNER = {
  sub: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_role: 'gym_owner',
  tenant_id: TENANT_ID, staff_id: STAFF_ID,
};
const MANAGER = { ...OWNER, app_role: 'gym_manager' };
const FRONT_DESK = { ...OWNER, app_role: 'front_desk' };
const TRAINER = { ...OWNER, app_role: 'trainer' };
const MEMBER_TOKEN = {
  sub: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', app_role: 'member',
  tenant_id: TENANT_ID, member_id: MEMBER_ID,
};
const IMPERSONATION = {
  sub: OWNER.sub, app_role: 'gym_owner', tenant_id: TENANT_ID,
  impersonation_session_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
};
const PLATFORM = {
  sub: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', app_role: 'platform_support',
};

const WRONG_IDENTITIES: Array<[string, Record<string, unknown>]> = [
  ['a front-desk user', FRONT_DESK],
  ['a trainer', TRAINER],
  ['a member', MEMBER_TOKEN],
  ['platform support', PLATFORM],
  ['an impersonating gym owner', IMPERSONATION],
];

const sha256 = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');

const CSV_TEXT = 'Full Name,Phone\nAsha Rao,+919876543210\nBela Das,+919999999999\n';
const CSV_BYTES = Buffer.from(CSV_TEXT, 'utf8');
const CSV_SHA = sha256(CSV_BYTES);
// The invisible first character below is the literal U+FEFF BOM; it is the
// point of this fixture; do not strip it.
const BOM_BYTES = Buffer.from(`﻿${CSV_TEXT}`, 'utf8');
const BAD_PHONE_BYTES = Buffer.from('Full Name,Phone\nAsha Rao,+919876543210\nCara Po,12345\n', 'utf8');
const SWAPPED_BYTES = Buffer.from('Phone,Full Name\n+919876543210,Asha Rao\n', 'utf8');
const GARBAGE_BYTES = Buffer.from([0xff, 0xfe, 0x00, 0x81]);
const OVER_LIMIT_BYTES = Buffer.alloc(5242881, 0x61);

const ERROR_REPORT_URL = `/api/member-imports/${IMPORT_ID}/errors`;

const ok = (data: unknown): Result => ({ data, error: null });
const refused = (code: string, message: string): Result => ({ data: null, error: { code, message } });

const PREPARE_NEW = {
  importId: IMPORT_ID,
  status: 'pending',
  replayed: false,
  effectiveOn: '2026-09-10',
  counts: { rows: 2, wouldImport: 1, duplicates: 1, invalid: 0 },
  report: {
    version: 1,
    summary: { invalid: 0, duplicate: 1 },
    previewCandidateRows: [2],
    importedRows: [] as number[],
    rows: [{ rowNumber: 3, disposition: 'duplicate', field: 'phone', reasonCode: 'file_phone' }],
    failure: null,
  },
};

const PREPARE_INVALID = {
  importId: IMPORT_ID,
  status: 'pending',
  replayed: false,
  effectiveOn: '2026-09-10',
  counts: { rows: 2, wouldImport: 1, duplicates: 0, invalid: 1 },
  report: {
    version: 1,
    summary: { invalid: 1, duplicate: 0 },
    previewCandidateRows: [2],
    importedRows: [] as number[],
    rows: [{ rowNumber: 3, disposition: 'invalid', field: 'phone', reasonCode: 'ambiguous_phone' }],
    failure: null,
  },
};

function pendingProbe(parserContract: string, columnMapping: Record<string, number> = { full_name: 0, phone: 1 }) {
  return {
    status: 'pending',
    parserContract,
    columnMapping,
    branchId: BRANCH_ID,
    phoneDefaultCountry: 'IN',
    effectiveOn: '2026-09-10',
    candidateRows: [2],
  };
}

const COMMIT_COMPLETED = {
  importId: IMPORT_ID,
  status: 'completed',
  replayed: false,
  counts: { rows: 2, imported: 1, duplicates: 1, invalid: 0 },
  failure: null,
  errorReportUrl: ERROR_REPORT_URL,
};

const COMMIT_FAILED = {
  importId: IMPORT_ID,
  status: 'failed',
  replayed: false,
  counts: { rows: 2, imported: 0, duplicates: 1, invalid: 1 },
  failure: { code: 'processing_failed' },
  errorReportUrl: ERROR_REPORT_URL,
};

const CANDIDATE_ROW = {
  rowNumber: 2,
  full_name: 'Asha Rao',
  phone: '+919876543210',
  member_code: null,
  email: null,
  gender: null,
  date_of_birth: null,
  joined_on: '2026-09-10',
  notes: null,
};

const STORED_REPORT = {
  version: 1,
  summary: { invalid: 1, duplicate: 1 },
  previewCandidateRows: [4],
  importedRows: [2, 3],
  rows: [
    { rowNumber: 5, disposition: 'invalid', field: 'phone', reasonCode: 'ambiguous_phone' },
    { rowNumber: 6, disposition: 'duplicate', field: 'phone', reasonCode: 'existing_phone' },
  ],
  failure: null,
};

const inspectRoute = async () => (await import('../api/member-imports/inspect/route'));
const previewRoute = async () => (await import('../api/member-imports/route'));
const commitRoute = async () => (await import('../api/member-imports/[importId]/commit/route'));
const errorsRoute = async () => (await import('../api/member-imports/[importId]/errors/route'));

const toFile = (bytes: Buffer, name: string) => new File([new Uint8Array(bytes)], name);

function post(path: string, form: FormData) {
  return new Request(`https://gym.example${path}`, { method: 'POST', body: form });
}

function brokenBody(path: string) {
  return new Request(`https://gym.example${path}`, {
    method: 'POST',
    headers: { 'content-type': 'multipart/form-data; boundary=nope' },
    body: 'not a multipart body',
  });
}

async function inspect(bytes: Buffer | null, name = 'members.csv') {
  const { POST } = await inspectRoute();
  const form = new FormData();
  if (bytes !== null) form.append('file', toFile(bytes, name));
  return await POST(post('/api/member-imports/inspect', form));
}

const VALID_PREVIEW_FIELDS: Record<string, string | File> = {
  file: toFile(CSV_BYTES, 'members.csv'),
  inspectedFileSha256: CSV_SHA,
  requestKey: REQUEST_KEY,
  branchId: BRANCH_ID,
  phoneDefaultCountry: 'IN',
  columnMapping: JSON.stringify({ full_name: 0, phone: 1 }),
};

function previewRequest(changes: Record<string, string | File | null> = {}) {
  const form = new FormData();
  for (const [key, value] of Object.entries({ ...VALID_PREVIEW_FIELDS, ...changes })) {
    if (value !== null && value !== undefined) form.append(key, value);
  }
  return post('/api/member-imports', form);
}

async function preview(request: Request) {
  const { POST } = await previewRoute();
  return await POST(request);
}

async function commit(bytes: Buffer | null = CSV_BYTES, name = 'members.csv', importId: string = IMPORT_ID) {
  const { POST } = await commitRoute();
  const form = new FormData();
  if (bytes !== null) form.append('file', toFile(bytes, name));
  return await POST(post(`/api/member-imports/${importId}/commit`, form), {
    params: Promise.resolve({ importId }),
  });
}

async function commitBrokenBody(importId: string = IMPORT_ID) {
  const { POST } = await commitRoute();
  return await POST(brokenBody(`/api/member-imports/${importId}/commit`), {
    params: Promise.resolve({ importId }),
  });
}

async function errors(importId: string = IMPORT_ID) {
  const { GET } = await errorsRoute();
  return await GET(new Request(`https://gym.example/api/member-imports/${importId}/errors`), {
    params: Promise.resolve({ importId }),
  });
}

async function jsonOf(response: Response) {
  return await response.json() as {
    ok: boolean;
    data?: Record<string, unknown>;
    error?: { code: string; message: string };
  };
}

/** One preview call, to capture the parser-contract version this deployment sends. */
async function deployedParserVersion(): Promise<string> {
  state.results.push(ok(PREPARE_NEW));
  const response = await preview(previewRequest());
  expect(response.status).toBe(200);
  const prepare = state.rpc.find(call => call.name === 'prepare_member_import');
  const version = prepare?.args.p_parser_contract;
  expect(typeof version).toBe('string');
  expect(version).not.toBe('');
  return version as string;
}

/** Parses one report data line under the contract's strict quoting rules. */
function reportRow(line: string) {
  const match = line.match(/^("?\d+"?),"([a-z_]+)","([a-z_]+)","([a-z_]+)","([^"]+)"$/);
  expect(match, `report line is not strictly quoted: ${line}`).not.toBeNull();
  return {
    rowNumber: Number((match?.[1] ?? '').replace(/"/g, '')),
    disposition: match?.[2],
    field: match?.[3],
    reasonCode: match?.[4],
    message: match?.[5],
  };
}

beforeEach(() => {
  state.claims = OWNER;
  state.rpc = [];
  state.results = [];
  state.operations = [];
});

describe('inspecting an uploaded file', () => {
  it('returns the exact inspection for a CSV, hashing the exact uploaded bytes, and touches no database', async () => {
    const response = await inspect(CSV_BYTES);

    expect(response.status).toBe(200);
    expect(await jsonOf(response)).toEqual({
      ok: true,
      data: {
        fileName: 'members.csv',
        fileSha256: CSV_SHA,
        format: 'csv',
        headers: [{ index: 0, label: 'Full Name' }, { index: 1, label: 'Phone' }],
        rowCount: 2,
        sampleRows: [
          { rowNumber: 2, cells: ['Asha Rao', '+919876543210'] },
          { rowNumber: 3, cells: ['Bela Das', '+919999999999'] },
        ],
      },
    });
    expect(state.operations).toEqual([]);
  });

  it('hashes the exact uploaded bytes even when decoding strips a leading BOM', async () => {
    const response = await inspect(BOM_BYTES);

    expect(response.status).toBe(200);
    const payload = await jsonOf(response);
    expect(payload.data).toMatchObject({ fileSha256: sha256(BOM_BYTES), format: 'csv', rowCount: 2 });
    const data = payload.data as { headers: Array<{ index: number; label: string }> };
    expect(data.headers[0]).toEqual({ index: 0, label: 'Full Name' });
  });

  it('accepts an uppercase .CSV filename under ASCII case-insensitive comparison', async () => {
    const response = await inspect(CSV_BYTES, 'MEMBERS.CSV');

    expect(response.status).toBe(200);
    expect((await jsonOf(response)).data).toMatchObject({ fileName: 'MEMBERS.CSV', format: 'csv' });
  });

  it('admits a gym manager as well as a gym owner', async () => {
    state.claims = MANAGER;
    const response = await inspect(CSV_BYTES);

    expect(response.status).toBe(200);
    expect((await jsonOf(response)).ok).toBe(true);
  });

  it('refuses an empty file as missing_header', async () => {
    const response = await inspect(Buffer.alloc(0));

    expect(response.status).toBe(422);
    expect((await jsonOf(response)).error?.code).toBe('missing_header');
    expect(state.operations).toEqual([]);
  });

  it.each([
    ['xls', 'workbook.xls'],
    ['txt', 'export.txt'],
  ])('refuses a filename ending in .%s as invalid_file_type', async (_extension, name) => {
    const response = await inspect(CSV_BYTES, name);

    expect(response.status).toBe(422);
    expect((await jsonOf(response)).error?.code).toBe('invalid_file_type');
    expect(state.operations).toEqual([]);
  });

  it('refuses a request with no file part as file_required', async () => {
    const response = await inspect(null);

    expect(response.status).toBe(400);
    expect((await jsonOf(response)).error?.code).toBe('file_required');
  });

  it('refuses a file one byte above 5 MiB as file_too_large', async () => {
    const response = await inspect(OVER_LIMIT_BYTES, 'big.csv');

    expect(response.status).toBe(413);
    expect((await jsonOf(response)).error?.code).toBe('file_too_large');
    expect(state.operations).toEqual([]);
  });

  it('answers a body that is not multipart with malformed_body', async () => {
    const { POST } = await inspectRoute();
    const response = await POST(brokenBody('/api/member-imports/inspect'));

    expect(response.status).toBe(400);
    expect((await jsonOf(response)).error?.code).toBe('malformed_body');
  });

  it('refuses an unsigned caller with 401 before reading the body', async () => {
    state.claims = null;
    const { POST } = await inspectRoute();
    const response = await POST(brokenBody('/api/member-imports/inspect'));

    expect(response.status).toBe(401);
    expect((await jsonOf(response)).error?.code).toBe('not_signed_in');
    expect(state.operations).toEqual([]);
  });

  it('refuses a member with 403 before reading the body', async () => {
    state.claims = MEMBER_TOKEN;
    const { POST } = await inspectRoute();
    const response = await POST(brokenBody('/api/member-imports/inspect'));

    expect(response.status).toBe(403);
    expect((await jsonOf(response)).error?.code).toBe('not_permitted');
    expect(state.operations).toEqual([]);
  });

  it.each(WRONG_IDENTITIES)('refuses %s with 403 before anything else', async (_name, claims) => {
    state.claims = claims;
    const response = await inspect(CSV_BYTES);

    expect(response.status).toBe(403);
    expect((await jsonOf(response)).error?.code).toBe('not_permitted');
    expect(state.operations).toEqual([]);
  });
});

describe('previewing an import', () => {
  it('sends the exact ten prepare facts with phase-A-normalized rows and returns the pending preview', async () => {
    state.results = [ok(PREPARE_NEW)];
    const response = await preview(previewRequest());

    expect(response.status).toBe(200);
    expect(await jsonOf(response)).toEqual({
      ok: true,
      data: {
        importId: IMPORT_ID,
        status: 'pending',
        replayed: false,
        fileName: 'members.csv',
        fileSha256: CSV_SHA,
        effectiveOn: '2026-09-10',
        counts: { rows: 2, wouldImport: 1, duplicates: 1, invalid: 0 },
        hasMoreRows: false,
        sampleRows: [
          expect.objectContaining({
            rowNumber: 2,
            disposition: 'would_import',
            reasonCodes: [],
            normalized: expect.objectContaining({
              full_name: 'Asha Rao', phone: '+919876543210', joined_on: '2026-09-10',
            }),
          }),
          expect.objectContaining({
            rowNumber: 3,
            disposition: 'duplicate',
            reasonCodes: ['file_phone'],
            normalized: expect.objectContaining({
              full_name: 'Bela Das', phone: '+919999999999', joined_on: '2026-09-10',
            }),
          }),
        ],
      },
    });
    expect(state.rpc).toEqual([{
      name: 'prepare_member_import',
      args: {
        p_request_key: REQUEST_KEY,
        p_file_name: 'members.csv',
        p_file_sha256: CSV_SHA,
        p_parser_contract: expect.any(String),
        p_branch_id: BRANCH_ID,
        p_phone_default_country: 'IN',
        p_column_mapping: { full_name: 0, phone: 1 },
        p_row_count: 2,
        p_rows: [
          expect.objectContaining({ rowNumber: 2, full_name: 'Asha Rao', phone: '+919876543210', joined_on: null }),
          expect.objectContaining({ rowNumber: 3, full_name: 'Bela Das', phone: '+919999999999', joined_on: null }),
        ],
        p_preclassified_report: [],
      },
    }]);
    expect(state.rpc[0]?.args.p_parser_contract).not.toBe('');
    expect(state.operations.every(operation => operation.kind === 'rpc')).toBe(true);
  });

  it('binds the E164 phone-country mode into the RPC', async () => {
    state.results = [ok(PREPARE_NEW)];
    const response = await preview(previewRequest({ phoneDefaultCountry: 'E164' }));

    expect(response.status).toBe(200);
    expect(state.rpc[0]?.args.p_phone_default_country).toBe('E164');
  });

  it('sends invalid rows too, with null unparseable values and the phase-A report', async () => {
    state.results = [ok(PREPARE_INVALID)];
    const response = await preview(previewRequest({
      file: toFile(BAD_PHONE_BYTES, 'members.csv'),
      inspectedFileSha256: sha256(BAD_PHONE_BYTES),
    }));

    expect(response.status).toBe(200);
    const args = state.rpc[0]?.args as { p_row_count: number; p_rows: unknown[]; p_preclassified_report: unknown[] };
    expect(args.p_row_count).toBe(2);
    expect(args.p_rows).toEqual([
      expect.objectContaining({ rowNumber: 2, full_name: 'Asha Rao', phone: '+919876543210', joined_on: null }),
      expect.objectContaining({ rowNumber: 3, full_name: 'Cara Po', phone: null, joined_on: null }),
    ]);
    expect(args.p_preclassified_report).toEqual([
      expect.objectContaining({ rowNumber: 3, field: 'phone', reasonCode: 'ambiguous_phone' }),
    ]);
    const data = (await jsonOf(response)).data as { sampleRows: Array<Record<string, unknown>> };
    expect(data.sampleRows[1]).toEqual(expect.objectContaining({
      rowNumber: 3,
      disposition: 'invalid',
      reasonCodes: ['ambiguous_phone'],
      normalized: expect.objectContaining({ full_name: 'Cara Po', phone: null }),
    }));
  });

  it('answers an exact replay with the stored day, status and replayed flag', async () => {
    state.results = [ok({ ...PREPARE_NEW, replayed: true, status: 'completed', effectiveOn: '2026-01-05' })];
    const response = await preview(previewRequest());

    expect(response.status).toBe(200);
    expect(await jsonOf(response)).toMatchObject({
      ok: true,
      data: { importId: IMPORT_ID, status: 'completed', replayed: true, effectiveOn: '2026-01-05' },
    });
    expect(state.rpc).toHaveLength(1);
  });

  it('refuses bytes that differ from the inspected digest as source_changed, without calling prepare', async () => {
    const otherSha = sha256(Buffer.from('Full Name,Phone\nAsha Rao,+919876543210\n', 'utf8'));
    const response = await preview(previewRequest({ inspectedFileSha256: otherSha }));

    expect(response.status).toBe(409);
    expect((await jsonOf(response)).error?.code).toBe('source_changed');
    expect(state.rpc).toEqual([]);
  });

  it('maps a GL068 refusal to idempotency_conflict without revealing stored facts', async () => {
    state.results = [refused(
      'GL068',
      `CANARY stored key ${REQUEST_KEY} of staff ${STAFF_ID} in tenant ${TENANT_ID}`,
    )];
    const response = await preview(previewRequest());
    const text = await response.text();
    const payload = JSON.parse(text) as { ok: boolean; error?: { code: string } };

    expect(response.status).toBe(409);
    expect(payload.ok).toBe(false);
    expect(payload.error?.code).toBe('idempotency_conflict');
    expect(text).not.toContain('CANARY');
    expect(text).not.toContain(STAFF_ID);
  });

  it.each([
    ['GL068', 409, 'idempotency_conflict'],
    ['42501', 403, 'not_permitted'],
    ['22023', 400, 'invalid_request'],
  ])('maps prepare refusal %s to HTTP %s without inventing success', async (code, status, mapped) => {
    state.results = [refused(code, 'refused')];
    const response = await preview(previewRequest());
    const payload = await jsonOf(response);

    expect(response.status).toBe(status);
    expect(payload.ok).toBe(false);
    expect(payload.error?.code).toBe(mapped);
  });

  it.each([
    ['a missing inspected digest', { inspectedFileSha256: null }],
    ['a malformed inspected digest', { inspectedFileSha256: 'nothex' }],
    ['a missing request key', { requestKey: null }],
    ['a non-UUID request key', { requestKey: 'not-a-uuid' }],
    ['an uppercase request key', { requestKey: REQUEST_KEY.toUpperCase() }],
    ['a missing branch', { branchId: null }],
    ['a non-UUID branch', { branchId: 'not-a-uuid' }],
    ['a missing phone-country mode', { phoneDefaultCountry: null }],
    ['an off-catalogue phone-country mode', { phoneDefaultCountry: 'US' }],
    ['a missing mapping', { columnMapping: null }],
    ['a mapping that is not JSON', { columnMapping: '{not json' }],
  ])('refuses %s as invalid_request before calling prepare', async (_name, changes) => {
    const response = await preview(previewRequest(changes));

    expect(response.status).toBe(400);
    expect((await jsonOf(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it.each([
    ['a mapping without phone', { columnMapping: JSON.stringify({ full_name: 0 }) }],
    ['a mapping with an unknown member field', { columnMapping: JSON.stringify({ full_name: 0, phone: 1, status: 2 }) }],
    ['one source column feeding two targets', { columnMapping: JSON.stringify({ full_name: 0, phone: 0 }) }],
    ['a source index beyond the header', { columnMapping: JSON.stringify({ full_name: 0, phone: 5 }) }],
    ['a negative source index', { columnMapping: JSON.stringify({ full_name: 0, phone: -1 }) }],
  ])('refuses %s as invalid_mapping before calling prepare', async (_name, changes) => {
    const response = await preview(previewRequest(changes));

    expect(response.status).toBe(422);
    expect((await jsonOf(response)).error?.code).toBe('invalid_mapping');
    expect(state.rpc).toEqual([]);
  });

  it('refuses a file one byte above 5 MiB as file_too_large before calling prepare', async () => {
    const response = await preview(previewRequest({ file: toFile(OVER_LIMIT_BYTES, 'big.csv') }));

    expect(response.status).toBe(413);
    expect((await jsonOf(response)).error?.code).toBe('file_too_large');
    expect(state.rpc).toEqual([]);
  });

  it('refuses a request with no file part as file_required', async () => {
    const response = await preview(previewRequest({ file: null }));

    expect(response.status).toBe(400);
    expect((await jsonOf(response)).error?.code).toBe('file_required');
    expect(state.rpc).toEqual([]);
  });

  it('answers a body that is not multipart with malformed_body', async () => {
    const { POST } = await previewRoute();
    const response = await POST(brokenBody('/api/member-imports'));

    expect(response.status).toBe(400);
    expect((await jsonOf(response)).error?.code).toBe('malformed_body');
  });

  it('treats an unrecognizable prepare result as a failure, never as success', async () => {
    state.results = [ok({ importId: 42 })];
    const response = await preview(previewRequest());

    expect(response.status).toBe(500);
    expect((await jsonOf(response)).ok).toBe(false);
  });

  it('refuses an unsigned caller with 401 before reading the body', async () => {
    state.claims = null;
    const { POST } = await previewRoute();
    const response = await POST(brokenBody('/api/member-imports'));

    expect(response.status).toBe(401);
    expect((await jsonOf(response)).error?.code).toBe('not_signed_in');
    expect(state.operations).toEqual([]);
  });

  it('refuses a member with 403 before reading the body', async () => {
    state.claims = MEMBER_TOKEN;
    const { POST } = await previewRoute();
    const response = await POST(brokenBody('/api/member-imports'));

    expect(response.status).toBe(403);
    expect((await jsonOf(response)).error?.code).toBe('not_permitted');
    expect(state.operations).toEqual([]);
  });

  it.each(WRONG_IDENTITIES)('refuses %s with 403 before calling prepare', async (_name, claims) => {
    state.claims = claims;
    const response = await preview(previewRequest());

    expect(response.status).toBe(403);
    expect((await jsonOf(response)).error?.code).toBe('not_permitted');
    expect(state.operations).toEqual([]);
  });
});

describe('committing an import', () => {
  it('probes with a SQL-null rows argument, then sends exactly the stored-day candidate rows, then replays through the probe alone', async () => {
    const deployed = await deployedParserVersion();
    state.results.push(ok(pendingProbe(deployed)), ok(COMMIT_COMPLETED));

    const first = await commit();
    expect(first.status).toBe(200);
    expect(await jsonOf(first)).toEqual({ ok: true, data: COMMIT_COMPLETED });
    expect(state.rpc).toEqual([
      { name: 'prepare_member_import', args: expect.objectContaining({ p_request_key: REQUEST_KEY }) },
      { name: 'commit_member_import', args: { p_import_id: IMPORT_ID, p_file_sha256: CSV_SHA, p_rows: null } },
      { name: 'commit_member_import', args: { p_import_id: IMPORT_ID, p_file_sha256: CSV_SHA, p_rows: [CANDIDATE_ROW] } },
    ]);
    expect(state.operations.every(operation => operation.kind === 'rpc')).toBe(true);

    state.results.push(ok({ ...COMMIT_COMPLETED, replayed: true }));
    const again = await commit();
    expect(again.status).toBe(200);
    expect(await jsonOf(again)).toEqual({ ok: true, data: { ...COMMIT_COMPLETED, replayed: true } });
    expect(state.rpc).toHaveLength(4);
    expect(state.rpc[3]).toEqual({
      name: 'commit_member_import',
      args: { p_import_id: IMPORT_ID, p_file_sha256: CSV_SHA, p_rows: null },
    });
  });

  it('replays a completed run through the null probe without reparsing, whatever the file and parser version now are', async () => {
    const deployed = await deployedParserVersion();
    state.results.push(ok({
      importId: IMPORT_ID,
      status: 'completed',
      replayed: true,
      parserContract: `${deployed}|retired-parser-contract`,
      counts: COMMIT_COMPLETED.counts,
      failure: null,
      errorReportUrl: ERROR_REPORT_URL,
    }));

    const response = await commit(GARBAGE_BYTES, 'not-a-spreadsheet.txt');

    expect(response.status).toBe(200);
    expect(await jsonOf(response)).toEqual({
      ok: true,
      data: {
        importId: IMPORT_ID,
        status: 'completed',
        replayed: true,
        counts: COMMIT_COMPLETED.counts,
        failure: null,
        errorReportUrl: ERROR_REPORT_URL,
      },
    });
    expect(state.rpc).toHaveLength(2);
    expect(state.rpc[1]).toEqual({
      name: 'commit_member_import',
      args: { p_import_id: IMPORT_ID, p_file_sha256: sha256(GARBAGE_BYTES), p_rows: null },
    });
  });

  it('replays a failed run the same way, as an HTTP 200 success', async () => {
    await deployedParserVersion();
    state.results.push(ok({ ...COMMIT_FAILED, replayed: true }));

    const response = await commit(GARBAGE_BYTES, 'not-a-spreadsheet.txt');

    expect(response.status).toBe(200);
    expect(await jsonOf(response)).toEqual({ ok: true, data: { ...COMMIT_FAILED, replayed: true } });
    expect(state.rpc).toHaveLength(2);
    expect(state.rpc[1]?.args.p_rows).toBeNull();
  });

  it('answers a stale stored parser contract with preview_expired, leaving only the probe call', async () => {
    const deployed = await deployedParserVersion();
    state.results.push(ok(pendingProbe(`${deployed}|retired-parser-contract`)));

    const response = await commit(GARBAGE_BYTES, 'not-a-spreadsheet.txt');

    expect(response.status).toBe(409);
    expect((await jsonOf(response)).error?.code).toBe('preview_expired');
    expect(state.rpc).toHaveLength(2);
    expect(state.rpc[1]?.args.p_rows).toBeNull();
  });

  it('runs the full file checks only after a matching probe, refusing a non-spreadsheet file', async () => {
    const deployed = await deployedParserVersion();
    state.results.push(ok(pendingProbe(deployed)));

    const response = await commit(GARBAGE_BYTES, 'not-a-spreadsheet.txt');

    expect(response.status).toBe(422);
    expect((await jsonOf(response)).error?.code).toBe('invalid_file_type');
    expect(state.rpc).toHaveLength(2);
  });

  it('reconstructs candidates with the stored mapping, not with anything resubmitted', async () => {
    const deployed = await deployedParserVersion();
    state.results.push(ok(pendingProbe(deployed, { full_name: 1, phone: 0 })), ok(COMMIT_COMPLETED));

    const response = await commit(SWAPPED_BYTES, 'swapped.csv');

    expect(response.status).toBe(200);
    expect(state.rpc[2]).toEqual({
      name: 'commit_member_import',
      args: { p_import_id: IMPORT_ID, p_file_sha256: sha256(SWAPPED_BYTES), p_rows: [CANDIDATE_ROW] },
    });
  });

  it('maps a GL063 refusal from the rows call to preview_payload_mismatch', async () => {
    const deployed = await deployedParserVersion();
    state.results.push(ok(pendingProbe(deployed)), refused('GL063', 'candidate digest mismatch'));

    const response = await commit();

    expect(response.status).toBe(409);
    expect((await jsonOf(response)).error?.code).toBe('preview_payload_mismatch');
    expect(state.rpc).toHaveLength(3);
    expect(state.rpc[2]?.args.p_rows).toEqual([CANDIDATE_ROW]);
  });

  it('answers a processing failure as a stored HTTP 200 result with zero imported rows', async () => {
    const deployed = await deployedParserVersion();
    state.results.push(ok(pendingProbe(deployed)), ok(COMMIT_FAILED));

    const response = await commit();

    expect(response.status).toBe(200);
    expect(await jsonOf(response)).toEqual({ ok: true, data: COMMIT_FAILED });
  });

  it.each([
    ['GL064', 409, 'preview_file_mismatch'],
    ['42501', 403, 'not_permitted'],
    ['55000', 409, 'import_not_pending'],
    ['22023', 400, 'invalid_request'],
  ])('maps probe refusal %s to HTTP %s, leaving the run pending', async (code, status, mapped) => {
    state.results = [refused(code, 'refused')];
    const response = await commit();

    expect(response.status).toBe(status);
    expect((await jsonOf(response)).error?.code).toBe(mapped);
    expect(state.rpc).toEqual([{
      name: 'commit_member_import',
      args: { p_import_id: IMPORT_ID, p_file_sha256: CSV_SHA, p_rows: null },
    }]);
  });

  it('answers an unexpected database error with 500 and no SQL text', async () => {
    const deployed = await deployedParserVersion();
    state.results.push(
      ok(pendingProbe(deployed)),
      refused('XX000', 'CANARY SQLSTATE XX000 from SELECT members.phone'),
    );

    const response = await commit();
    const text = await response.text();
    const payload = JSON.parse(text) as { ok: boolean; error?: { code: string } };

    expect(response.status).toBe(500);
    expect(payload.ok).toBe(false);
    expect(text).not.toContain('CANARY');
    expect(text).not.toContain('SELECT');
  });

  it('treats an unrecognizable probe result as a failure, never as success', async () => {
    state.results = [ok({})];
    const response = await commit();

    expect(response.status).toBe(500);
    expect((await jsonOf(response)).ok).toBe(false);
  });

  it('refuses a file one byte above 5 MiB before the probe', async () => {
    const response = await commit(OVER_LIMIT_BYTES, 'big.csv');

    expect(response.status).toBe(413);
    expect((await jsonOf(response)).error?.code).toBe('file_too_large');
    expect(state.rpc).toEqual([]);
  });

  it('refuses a request with no file part as file_required', async () => {
    const response = await commit(null);

    expect(response.status).toBe(400);
    expect((await jsonOf(response)).error?.code).toBe('file_required');
    expect(state.rpc).toEqual([]);
  });

  it('refuses a malformed import id as invalid_request', async () => {
    const response = await commit(CSV_BYTES, 'members.csv', 'not-a-uuid');

    expect(response.status).toBe(400);
    expect((await jsonOf(response)).error?.code).toBe('invalid_request');
    expect(state.rpc).toEqual([]);
  });

  it('answers a body that is not multipart with malformed_body', async () => {
    const response = await commitBrokenBody();

    expect(response.status).toBe(400);
    expect((await jsonOf(response)).error?.code).toBe('malformed_body');
  });

  it('refuses an unsigned caller with 401 before reading the body', async () => {
    state.claims = null;
    const response = await commitBrokenBody();

    expect(response.status).toBe(401);
    expect((await jsonOf(response)).error?.code).toBe('not_signed_in');
    expect(state.operations).toEqual([]);
  });

  it('refuses a member with 403 before reading the body', async () => {
    state.claims = MEMBER_TOKEN;
    const response = await commitBrokenBody();

    expect(response.status).toBe(403);
    expect((await jsonOf(response)).error?.code).toBe('not_permitted');
    expect(state.operations).toEqual([]);
  });

  it.each(WRONG_IDENTITIES)('refuses %s with 403 before the probe', async (_name, claims) => {
    state.claims = claims;
    const response = await commit();

    expect(response.status).toBe(403);
    expect((await jsonOf(response)).error?.code).toBe('not_permitted');
    expect(state.operations).toEqual([]);
  });
});

describe('downloading the stored report', () => {
  it('returns the fixed UTF-8 CSV with BOM, CRLF, allowlisted cells and the fixed filename', async () => {
    state.results = [ok({ id: IMPORT_ID, status: 'completed', error_report: STORED_REPORT })];

    const response = await errors();

    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toBe('text/csv; charset=utf-8');
    const disposition = response.headers.get('content-disposition') ?? '';
    expect(disposition).toContain(`member-import-${IMPORT_ID}-errors.csv`);
    expect(disposition).toMatch(
      /member-import-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-errors\.csv/,
    );

    // The BOM must be asserted at the byte level: `response.text()` decodes
    // UTF-8 and strips a leading BOM per the fetch spec, so a string starting
    // with U+FEFF is unsatisfiable for a body that carries exactly one BOM —
    // which is what the contract requires (CSV-D15).
    const raw = new Uint8Array(await response.arrayBuffer());
    const bomAndHeader = [...new TextEncoder().encode('row_number,disposition,field,reason_code,message\r\n')];
    expect([...raw.slice(0, 3)]).toEqual([0xef, 0xbb, 0xbf]);
    expect([...raw.slice(3, 3 + bomAndHeader.length)]).toEqual(bomAndHeader);

    const text = new TextDecoder().decode(raw.slice(3));
    expect(text.replace(/\r\n/g, '')).not.toContain('\n');

    const lines = text.split('\r\n').filter(line => line !== '');
    expect(lines).toHaveLength(3);
    expect(reportRow(lines[1] ?? '')).toEqual({
      rowNumber: 5,
      disposition: 'invalid',
      field: 'phone',
      reasonCode: 'ambiguous_phone',
      message: expect.any(String),
    });
    expect(reportRow(lines[2] ?? '')).toEqual({
      rowNumber: 6,
      disposition: 'duplicate',
      field: 'phone',
      reasonCode: 'existing_phone',
      message: expect.any(String),
    });

    expect(text).not.toContain('Asha');
    expect(text).not.toContain('+919876543210');
    expect(text).not.toContain('Full Name');
    expect(text).not.toContain('members.csv');
  });

  it('refuses a malformed import id as invalid_request', async () => {
    const response = await errors('not-a-uuid');

    expect(response.status).toBe(400);
    expect((await jsonOf(response)).error?.code).toBe('invalid_request');
    expect(state.operations).toEqual([]);
  });

  it('refuses an unsigned caller with 401 before any read', async () => {
    state.claims = null;
    const response = await errors();

    expect(response.status).toBe(401);
    expect((await jsonOf(response)).error?.code).toBe('not_signed_in');
    expect(state.operations).toEqual([]);
  });

  it.each(WRONG_IDENTITIES)('refuses %s with 403 before any read', async (_name, claims) => {
    state.claims = claims;
    const response = await errors();

    expect(response.status).toBe(403);
    expect((await jsonOf(response)).error?.code).toBe('not_permitted');
    expect(state.operations).toEqual([]);
  });
});
