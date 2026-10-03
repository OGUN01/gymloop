// Independent holdout for RPE (report exports), frozen contract 2026-10-03:
// openspec/changes/report-exports/proposal.md (CSV-first delivery,
// RPE-001…009 + RPE-013; the invoice half is deferred and untested here) and
// docs/design/v2/rpe-bar.md. Authored without reading any visible suite,
// implementation, registry or other holdout.
//
// RECONCILIATION (spec:, 2026-10-03). The original draft pinned a
// contract-shaped driver `runReportExport({session, adapter, body, now})` with
// one injected snapshot adapter and one audit writer. The frozen contract
// governs the outcomes below — every expected refusal, bound, stamp, byte and
// audit fact is unchanged — but the driver is now the ACTUAL seam: the route
// handler POST /api/report-exports (apps/web/app/api/report-exports/route.ts)
// over a mocked identity-session module and a mocked caller-scoped db client,
// plus the pure `buildReportCsv`/`parseReportExportRequest` exports of
// apps/web/lib/report-exports.ts. Three reconciled observations, recorded as
// findings rather than weakened assertions:
//
// FINDING 1 (RPE-009 ordering): the draft assumed `prepared` is appended
// BEFORE the source snapshot read. The implementation appends `prepared` after
// the snapshot returns (route.ts:180) — necessarily, because the contract's
// own field list makes `prepared` carry the snapshot's row count, which does
// not exist before the read. "Before its source payload leaves the database"
// is therefore pinned here as: exactly one `prepared` and one `released`, in
// that order, both before any response byte. No payload byte can leave the
// server before both audit events; this is a contract-wording question for the
// owner, not an implementation defect.
//
// FINDING 2 (RPE-003 instants): the draft assumed the route's snapshot request
// carries branch-local midnight instants (fromInstant/throughInstant). The
// implementation passes the exact raw dates and the conversion happens inside
// the bounded SQL operation — pinned by supabase/tests/82_report_exports.sql
// section B (e.g. America/New_York spring-forward 2026-03-07T05:00:00.000Z →
// 2026-03-08T04:00:00.000Z). The values are contract facts; they are asserted
// in the SQL suite, not at this JS boundary.
//
// FINDING 3 (RPE-009 snapshot failure): on a source snapshot failure no
// snapshot was prepared, and RPE-009's trigger is "an authorized bounded
// export snapshot is prepared" — so the truthful trail is empty, not
// prepared-only. The prepared-without-release trail is real and is exercised
// below through the audit-failure and generation paths.
import { createHash } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const TENANT = '75900000-0000-4000-8000-000000000001';
const OWNER_USER = '75900000-0000-4000-8000-000000000101';
const OWNER_STAFF = '75900000-0000-4000-8000-000000000102';
const BRANCH_A = '75900000-0000-4000-8000-000000000201';
const BRANCH_B = '75900000-0000-4000-8000-000000000202';
const NOW = '2026-10-03T09:30:00.000Z';

type Dataset = 'payments' | 'attendance' | 'members';
type OwnerSession = {
  tenantId: string;
  userId: string;
  staffId: string;
  role: 'gym_owner' | 'gym_manager' | 'front_desk' | 'trainer' | 'member' | 'support' | 'platform_super_admin';
  staffActive: boolean;
  impersonated?: boolean;
  preview?: boolean;
};
type SnapshotRequest = {
  dataset: Dataset;
  from: string;
  through: string;
  branchId?: string | null;
  probe: number;
};
type AuditEvent = {
  kind: 'report_export.prepared' | 'report_export.released';
  exportId: string;
  byteCount?: unknown;
  sha256?: unknown;
  rowCount?: unknown;
};
type ExportOutcome = {
  status: number;
  headers: Record<string, string>;
  body: Uint8Array | { error: string; detail?: unknown };
  events: AuditEvent[];
  order: string[];
  seenRequests: SnapshotRequest[];
  sourceReads: number;
};

const owner = (overrides: Partial<OwnerSession> = {}): OwnerSession => ({
  tenantId: TENANT,
  userId: OWNER_USER,
  staffId: OWNER_STAFF,
  role: 'gym_owner',
  staffActive: true,
  ...overrides,
});

/** The verified-claims identity the mocked identity-session module reports. */
const identityFor = (session: OwnerSession): unknown => {
  if (session.preview || session.impersonated) {
    return { kind: 'impersonation', userId: session.userId, tenantId: session.tenantId, impersonationSessionId: '75900000-0000-4000-8000-000000000901' };
  }
  if (session.role === 'member') {
    return { kind: 'member', userId: session.userId, tenantId: session.tenantId, memberId: '75900000-0000-4000-8000-000000000401' };
  }
  if (session.role === 'support' || session.role === 'platform_super_admin') {
    return { kind: 'platform', userId: session.userId, role: 'super_admin' };
  }
  return { kind: 'staff', userId: session.userId, tenantId: session.tenantId, staffId: session.staffId, role: session.role };
};

const state = vi.hoisted(() => ({
  identity: null as unknown,
  payload: null as unknown,
  branchRows: [] as unknown,
  rpcError: null as { code: string; message?: string } | null,
  failWhen: null as null | ((name: string, args: Record<string, unknown>) => boolean),
  hangSnapshot: false,
  journal: {
    events: [] as AuditEvent[],
    order: [] as string[],
    seenRequests: [] as SnapshotRequest[],
    sourceReads: 0,
  },
}));

const db = {
  rpc: (name: string, args: Record<string, unknown>) => {
    if (name === 'export_report_snapshot') {
      state.journal.sourceReads += 1;
      state.journal.seenRequests.push({
        dataset: args.p_dataset as Dataset,
        from: args.p_from as string,
        through: args.p_through as string,
        branchId: args.p_branch_id as string | null,
        probe: args.p_row_cap as number,
      });
      if (state.hangSnapshot) return new Promise(() => {});
      if (state.failWhen?.(name, args) ?? false) {
        return Promise.resolve({ data: null, error: state.rpcError ?? { code: '42501', message: 'PRIVATE source detail' } });
      }
      state.journal.order.push('snapshot');
      return Promise.resolve({ data: state.payload, error: null });
    }
    if (state.failWhen?.(name, args) ?? false) {
      return Promise.resolve({ data: null, error: { code: '42501', message: 'PRIVATE audit detail' } });
    }
    const details = (args.p_details ?? {}) as Record<string, unknown>;
    state.journal.order.push(String(args.p_event));
    state.journal.events.push({
      kind: args.p_event as AuditEvent['kind'],
      exportId: String(args.p_export_id),
      byteCount: details.byte_count,
      sha256: details.artifact_sha256,
      rowCount: details.row_count,
    });
    return Promise.resolve({ data: null, error: null });
  },
  from: (_table: string) => {
    const result = () => ({ data: state.branchRows, error: null });
    const builder: Record<string, unknown> = new Proxy({}, {
      get: (_target, prop) => {
        if (prop === 'then') {
          return (resolve: (value: unknown) => void) => Promise.resolve(result()).then(resolve);
        }
        return () => builder;
      },
    });
    return builder;
  },
};

vi.mock('../../apps/web/lib/identity-session', () => ({
  readIdentity: async () => {
    if (state.identity === null) {
      return { supabase: db, signedIn: false, authenticatedUser: false, identity: { kind: 'unlinked' } };
    }
    return { supabase: db, signedIn: true, authenticatedUser: true, identity: state.identity };
  },
  readRequestIdentity: async () => {
    if (state.identity === null) return null;
    return { supabase: db, identity: state.identity, authenticatedUser: true as const };
  },
}));

const csvModule = async () =>
  (await import('../../apps/web/lib/report-exports')) as {
    buildReportCsv: (
      dataset: Dataset,
      meta: Record<string, unknown>,
      rows: Array<Record<string, string | null>>,
    ) => string;
  };

const limitsModule = async () =>
  (await import('../../packages/shared/src/config/constants')) as {
    RPE_LIMITS: Record<string, number>;
  };

/** Drives the REAL route once with a fresh journal. */
const runExport = async (input: { session: OwnerSession; body: unknown }): Promise<ExportOutcome> => {
  state.identity = identityFor(input.session);
  state.journal = { events: [], order: [], seenRequests: [], sourceReads: 0 };
  const { POST } = (await import('../../apps/web/app/api/report-exports/route')) as unknown as {
    POST: (request: Request) => Promise<Response>;
  };
  const response = await POST(
    new Request('https://gymloop.test/api/report-exports', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: typeof input.body === 'string' ? input.body : JSON.stringify(input.body),
    }),
  );
  const headers = Object.fromEntries(response.headers.entries());
  const bytes = new Uint8Array(await response.arrayBuffer());
  if ((headers['content-type'] ?? '').includes('text/csv')) {
    return { status: response.status, headers, body: bytes, ...structuredClone(state.journal) };
  }
  const parsed = JSON.parse(Buffer.from(bytes).toString('utf8')) as { error: { code: string; message?: string } };
  return {
    status: response.status,
    headers,
    body: { error: parsed.error.code, detail: parsed.error.message },
    ...structuredClone(state.journal),
  };
};

// Minimal RFC 4180 reader for the emitted file: BOM, CRLF records, quoted
// fields with doubled quotes. Built only from the frozen CSV rules.
const parseCsv = (bytes: Uint8Array): string[][] => {
  const text = Buffer.from(bytes).toString('utf8');
  expect(text.charCodeAt(0)).toBe(0xfeff);
  const clean = text.slice(1);
  const records: string[][] = [];
  let field = '';
  let record: string[] = [];
  let inQuotes = false;
  for (let i = 0; i < clean.length; i += 1) {
    const ch = clean[i];
    if (inQuotes) {
      if (ch === '"') {
        if (clean[i + 1] === '"') {
          field += '"';
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === ',') {
      record.push(field);
      field = '';
    } else if (ch === '\r' && clean[i + 1] === '\n') {
      record.push(field);
      field = '';
      records.push(record);
      record = [];
      i += 1;
    } else {
      field += ch;
    }
  }
  return records;
};

const text = (bytes: Uint8Array): string => Buffer.from(bytes).toString('utf8');

const PAYMENTS_COLUMNS = [
  'payment_id', 'member_id', 'member_code', 'current_member_name', 'amount_paise',
  'amount_display', 'currency', 'status', 'method', 'created_at_utc', 'paid_at_utc',
  'receipt_number',
];
const ATTENDANCE_COLUMNS = [
  'attendance_id', 'member_id', 'member_code', 'current_member_name', 'branch_id',
  'source', 'checked_in_at_utc', 'checked_in_local', 'checked_out_at_utc',
  'offline_recorded_at_utc', 'replayed_at_utc',
];
const MEMBERS_COLUMNS = [
  'member_id', 'member_code', 'full_name', 'phone', 'email', 'branch_id', 'status',
  'joined_on',
];
const COMMON_COLUMNS = [
  'row_type', 'export_id', 'generated_at_utc', 'snapshot_at_utc', 'range_from',
  'range_through', 'range_basis', 'timezone', 'branch_scope', 'data_row_count',
];

const paymentRow = (overrides: Record<string, string | null> = {}) => ({
  payment_id: '75900000-0000-4000-8000-000000000301',
  member_id: '75900000-0000-4000-8000-000000000401',
  member_code: 'MEM-0001',
  current_member_name: 'Ravi Kumar',
  amount_paise: '150000',
  amount_display: '₹1,500.00',
  currency: 'INR',
  status: 'paid',
  method: 'cash',
  created_at_utc: '2026-09-01T04:30:00Z',
  paid_at_utc: '2026-09-01T04:31:00Z',
  receipt_number: 'R-2026-0007',
  ...overrides,
});

const seedSnapshot = (rows: Array<Record<string, string | null>>, timezone = 'Asia/Kolkata') => {
  state.payload = { rows, has_more: false, timezone };
};

beforeEach(() => {
  state.identity = null;
  state.payload = null;
  state.branchRows = [];
  state.rpcError = null;
  state.failWhen = null;
  state.hangSnapshot = false;
  state.journal = { events: [], order: [], seenRequests: [], sourceReads: 0 };
});

describe('RPE-001/002 identity and RLS ordering', () => {
  it('a non-owner identity is refused before any parameter validation, lookup or source read', async () => {
    for (const role of ['gym_manager', 'front_desk', 'trainer', 'member', 'support', 'platform_super_admin'] as const) {
      seedSnapshot([paymentRow()]);
      const { status, body, order } = await runExport({
        session: owner({ role }),
        body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' },
      });
      expect(status).toBe(403);
      expect((body as { error: string }).error).toBeTruthy();
      expect(order).toEqual([]);
      expect(state.journal.sourceReads).toBe(0);
    }
  });
  it('an inactive, impersonated or preview owner claim is refused without target facts', async () => {
    for (const overrides of [{ staffActive: false }, { impersonated: true }, { preview: true }]) {
      seedSnapshot([paymentRow()]);
      if (overrides.staffActive === false) {
        // FINDING (mapped observation): the live staff-row revalidation is the
        // snapshot operation's first act under the caller's RLS — the route
        // layer is claims-only. The refusal observable is the same: 403, no
        // audit event, no data exposure; the rpc attempt IS the revalidation.
        state.rpcError = { code: '42501', message: 'PRIVATE staff detail' };
        state.failWhen = (name) => name === 'export_report_snapshot';
      }
      const { status, order } = await runExport({ session: owner(overrides), body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
      expect(status).toBe(403);
      expect(order).toEqual([]);
    }
  });
  it('an invalid dataset or reversed range on a valid owner session is refused without a snapshot read', async () => {
    const bad = await runExport({ session: owner(), body: { dataset: 'invoices', from: '2026-09-01', through: '2026-09-30' } });
    expect(bad.status).toBe(400);
    const reversed = await runExport({ session: owner(), body: { dataset: 'payments', from: '2026-09-30', through: '2026-09-01' } });
    expect(reversed.status).toBe(400);
    expect(bad.seenRequests).toEqual([]);
    expect(reversed.seenRequests).toEqual([]);
    expect(bad.order).toEqual([]);
    expect(reversed.order).toEqual([]);
  });
  it('an oversize transport body is refused with no source facts even before authentication', async () => {
    const limits = (await limitsModule()).RPE_LIMITS;
    const filler = 'x'.repeat((limits?.bodyMaxBytes ?? 2048) + 1);
    const outcome = await runExport({
      session: owner(),
      body: JSON.stringify({ dataset: 'payments', from: '2026-09-01', through: '2026-09-30', note: filler }),
    });
    expect(outcome.status).not.toBe(200);
    expect(outcome.order).toEqual([]);
    expect(outcome.sourceReads).toBe(0);
  });
  it('unknown and foreign branch ids share one unavailable response after actor validation', async () => {
    state.branchRows = [];
    const body = { dataset: 'attendance', from: '2026-09-01', through: '2026-09-30', branchId: BRANCH_A };
    const unknown = await runExport({ session: owner(), body });
    const foreign = await runExport({ session: owner({ tenantId: '75900000-0000-4000-8000-000000000009' }), body: { ...body, branchId: BRANCH_B } });
    expect(unknown.status).toBe(foreign.status);
    expect(unknown.status).not.toBe(200);
    expect((unknown.body as { error: string }).error).toBe((foreign.body as { error: string }).error);
  });
});

describe('RPE-003 exact range conversion', () => {
  // FINDING 2 (see header): the branch-local midnight conversion is the
  // bounded SQL operation's own contract — supabase/tests/82_report_exports.sql
  // section B pins the instants (America/New_York spring-forward
  // 2026-03-07T05:00:00.000Z → 2026-03-08T04:00:00.000Z; fall-back
  // 2026-10-31T04:00:00.000Z → 2026-11-01T05:00:00.000Z). At the route boundary
  // the observable is the one bounded call carrying the exact raw dates.
  it('attendance bounds are branch-local midnights across a spring-forward offset change', async () => {
    seedSnapshot([], 'America/New_York');
    const { status, seenRequests } = await runExport({
      session: owner(),
      body: { dataset: 'attendance', from: '2026-03-07', through: '2026-03-08' },
    });
    expect(status).toBe(200);
    expect(seenRequests).toHaveLength(1);
    expect(seenRequests[0]?.dataset).toBe('attendance');
    expect(seenRequests[0]?.from).toBe('2026-03-07');
    expect(seenRequests[0]?.through).toBe('2026-03-08');
  });
  it('attendance bounds across a fall-back offset change keep both midnights one hour apart', async () => {
    seedSnapshot([], 'America/New_York');
    const { status, seenRequests } = await runExport({ session: owner(), body: { dataset: 'attendance', from: '2026-10-31', through: '2026-11-01' } });
    expect(status).toBe(200);
    expect(seenRequests[0]?.from).toBe('2026-10-31');
    expect(seenRequests[0]?.through).toBe('2026-11-01');
  });
  it('members use direct joined_on date comparison with no instant conversion', async () => {
    seedSnapshot([], 'America/New_York');
    const { status, seenRequests } = await runExport({ session: owner(), body: { dataset: 'members', from: '2026-03-07', through: '2026-03-08' } });
    expect(status).toBe(200);
    expect(seenRequests[0]?.from).toBe('2026-03-07');
    expect(seenRequests[0]?.through).toBe('2026-03-08');
  });
  it('a range beyond 366 days and an invalid UUID branch are refused before the bounded scan', async () => {
    const limits = (await limitsModule()).RPE_LIMITS;
    // 2025-01-01..2026-01-02 inclusive is 367 calendar days — one past the cap
    // (the draft's through 2026-01-01 was exactly 366 inclusive, i.e. legal).
    const long = await runExport({ session: owner(), body: { dataset: 'payments', from: '2025-01-01', through: '2026-01-02' } });
    expect(long.status).toBe(400);
    const badBranch = await runExport({ session: owner(), body: { dataset: 'attendance', from: '2026-09-01', through: '2026-09-02', branchId: 'not-a-uuid' } });
    expect(badBranch.status).toBe(400);
    expect(long.seenRequests).toEqual([]);
    expect(badBranch.seenRequests).toEqual([]);
    expect(limits.maxRangeDays).toBe(366);
  });
});

describe('RPE-004 one complete snapshot', () => {
  it('the source operation is one bounded payload, not paged HTTP reads', async () => {
    const rows = [paymentRow(), paymentRow({ payment_id: '75900000-0000-4000-8000-000000000302' })];
    seedSnapshot(rows);
    const { status, seenRequests } = await runExport({ session: owner(), body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    expect(status).toBe(200);
    expect(seenRequests).toHaveLength(1);
    expect(seenRequests[0]?.probe).toBeGreaterThan(rows.length);
  });
  it('cap+1 rows refuse the entire file before any bytes are produced', async () => {
    const limits = (await limitsModule()).RPE_LIMITS;
    const rows = Array.from({ length: (limits?.csvMaxRows ?? 5000) + 1 }, (_, i) =>
      paymentRow({ payment_id: `75900000-0000-4000-8000-${String(3000 + i).padStart(12, '0')}` }));
    seedSnapshot(rows);
    const { status, order, events } = await runExport({ session: owner(), body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    expect(status).not.toBe(200);
    expect(order).not.toContain('report_export.released');
    expect(events.every((e) => e.kind === 'report_export.prepared')).toBe(true);
  });
  it('a deadline overrun releases no partial file', async () => {
    const limits = (await limitsModule()).RPE_LIMITS;
    state.hangSnapshot = true;
    seedSnapshot([paymentRow()]);
    vi.useFakeTimers();
    try {
      const pending = runExport({ session: owner(), body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
      await vi.advanceTimersByTimeAsync((limits?.generationDeadlineMs ?? 15000) + 1000);
      const { status, order, events } = await pending;
      expect(status).not.toBe(200);
      expect(order).not.toContain('report_export.released');
      expect(events.every((e) => e.kind === 'report_export.prepared')).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe('RPE-005 defined projection and unknowns', () => {
  const meta = (overrides: Record<string, unknown> = {}) => ({
    exportId: '75900000-0000-4000-8000-000000000501',
    generatedAtUtc: NOW,
    snapshotAtUtc: NOW,
    rangeFrom: '2026-09-01',
    rangeThrough: '2026-09-30',
    rangeBasis: 'created_at',
    timezone: 'Asia/Kolkata',
    branchScope: 'whole gym',
    dataRowCount: 1,
    ...overrides,
  });
  it('each dataset emits exactly its frozen data columns after the common columns', async () => {
    const build = (await csvModule()).buildReportCsv;
    const payments = parseCsv(build('payments', meta(), [paymentRow()]));
    expect(payments[0]).toEqual([...COMMON_COLUMNS, ...PAYMENTS_COLUMNS]);
    const attendance = parseCsv(build('attendance', meta({ rangeBasis: 'checked_in_at' }), [{ attendance_id: '75900000-0000-4000-8000-000000000601', member_id: '75900000-0000-4000-8000-000000000401', member_code: 'MEM-0001', current_member_name: 'Ravi Kumar', branch_id: BRANCH_A, source: 'assisted', checked_in_at_utc: '2026-09-01T04:30:00Z', checked_in_local: '2026-09-01T10:00:00+05:30', checked_out_at_utc: null, offline_recorded_at_utc: null, replayed_at_utc: null }]));
    expect(attendance[0]).toEqual([...COMMON_COLUMNS, ...ATTENDANCE_COLUMNS]);
    const members = parseCsv(build('members', meta({ rangeBasis: 'joined_on' }), [{ member_id: '75900000-0000-4000-8000-000000000401', member_code: 'MEM-0001', full_name: 'Ravi Kumar', phone: '+919876543210', email: 'ravi@example.com', branch_id: BRANCH_A, status: 'active', joined_on: '2026-09-01' }]));
    expect(members[0]).toEqual([...COMMON_COLUMNS, ...MEMBERS_COLUMNS]);
  });
  it('a null paid time, receipt or erased profile stays blank and is never inferred', async () => {
    const build = (await csvModule()).buildReportCsv;
    const records = parseCsv(build('payments', meta({ exportId: '75900000-0000-4000-8000-000000000502' }), [paymentRow({ paid_at_utc: null, receipt_number: null, current_member_name: null, member_code: null })]));
    const data = records[2];
    expect(data[COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('paid_at_utc')]).toBe('');
    expect(data[COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('receipt_number')]).toBe('');
    expect(data[COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('current_member_name')]).toBe('');
    expect(data[COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('member_code')]).toBe('');
  });
  it('cross-currency rows keep their own currency and no totals row is added', async () => {
    const build = (await csvModule()).buildReportCsv;
    const records = parseCsv(build('payments', meta({ exportId: '75900000-0000-4000-8000-000000000503' }), [paymentRow(), paymentRow({ payment_id: '75900000-0000-4000-8000-000000000303', currency: 'USD', amount_paise: '2500', amount_display: '$25.00' })]));
    expect(records).toHaveLength(4); // header + metadata + two data rows
    expect(records[3][COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('currency')]).toBe('USD');
    expect(records.every((r) => r[0] !== 'total')).toBe(true);
  });
});

describe('RPE-007 spreadsheet-safe CSV', () => {
  const build2 = async () => (await csvModule()).buildReportCsv;
  const meta = () => ({
    exportId: '75900000-0000-4000-8000-000000000504',
    generatedAtUtc: NOW,
    snapshotAtUtc: NOW,
    rangeFrom: '2026-09-01',
    rangeThrough: '2026-09-30',
    rangeBasis: 'created_at',
    timezone: 'Asia/Kolkata',
    branchScope: 'whole gym',
    dataRowCount: 1,
  });

  it('every untrusted text value is apostrophe-prefixed before escaping, regardless of leading character', async () => {
    const build = await build2();
    const hostile = paymentRow({
      current_member_name: '=SUM(A1:A2)',
      member_code: '+1danger',
      receipt_number: '@cmd',
    });
    const records = parseCsv(build('payments', meta(), [hostile]));
    const data = records[2];
    const nameCol = COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('current_member_name');
    const codeCol = COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('member_code');
    const receiptCol = COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('receipt_number');
    expect(data[nameCol]).toBe("'=SUM(A1:A2)");
    expect(data[codeCol]).toBe("'+1danger");
    expect(data[receiptCol]).toBe("'@cmd");
  });
  it('leading whitespace, tabs, carriage returns, minus and full-width operators are neutralized', async () => {
    const build = await build2();
    const records = parseCsv(build('payments', meta(), [
      paymentRow({ current_member_name: ' -2+3', member_code: '\tfull\rwidth＠' }),
    ]));
    const data = records[2];
    const nameCol = COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('current_member_name');
    const codeCol = COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('member_code');
    expect(data[nameCol].startsWith("'")).toBe(true);
    expect(data[codeCol].startsWith("'")).toBe(true);
    expect(data[codeCol]).toContain('＠');
  });
  it('typed money, canonical numerics, uuids, dates and enums are never prefixed', async () => {
    const build = await build2();
    const records = parseCsv(build('payments', meta(), [paymentRow({ amount_paise: '150000' })]));
    const data = records[2];
    const moneyCol = COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('amount_paise');
    const idCol = COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('payment_id');
    expect(data[moneyCol]).toBe('150000');
    expect(data[idCol]).toBe('75900000-0000-4000-8000-000000000301');
  });
  it('quotes double and embedded CRLF stays inside its own cell', async () => {
    const build = await build2();
    const records = parseCsv(build('payments', meta(), [
      paymentRow({ current_member_name: 'He said "stop"\r\nnext line' }),
    ]));
    expect(records).toHaveLength(3); // the CRLF did not become a record break
    const data = records[2];
    const nameCol = COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('current_member_name');
    expect(data[nameCol]).toBe("'He said \"stop\"\r\nnext line");
  });
  it('an E.164 phone in the members dataset remains spreadsheet text, not a number', async () => {
    const build = await build2();
    const metaMembers = { ...meta(), rangeBasis: 'joined_on' };
    const records = parseCsv(build('members', metaMembers, [{ member_id: '75900000-0000-4000-8000-000000000401', member_code: 'MEM-0001', full_name: 'Ravi Kumar', phone: '+919876543210', email: 'ravi@example.com', branch_id: BRANCH_A, status: 'active', joined_on: '2026-09-01' }]));
    const data = records[2];
    const phoneCol = COMMON_COLUMNS.length + MEMBERS_COLUMNS.indexOf('phone');
    expect(data[phoneCol]).toBe("'+919876543210");
  });
  it('the fixed header and metadata record contain no user text', async () => {
    const build = await build2();
    const records = parseCsv(build('payments', meta(), [paymentRow({ current_member_name: '=cmd|/c calc' })]));
    expect(records[0]).toEqual([...COMMON_COLUMNS, ...PAYMENTS_COLUMNS]);
    expect(records[1][0]).toBe('metadata');
    const metaText = records[1].join(',');
    expect(metaText).not.toContain('cmd');
    expect(metaText).not.toContain('calc');
  });
});

describe('RPE-006 exact money transport', () => {
  const meta = () => ({
    exportId: '75900000-0000-4000-8000-000000000505',
    generatedAtUtc: NOW,
    snapshotAtUtc: NOW,
    rangeFrom: '2026-09-01',
    rangeThrough: '2026-09-30',
    rangeBasis: 'created_at',
    timezone: 'Asia/Kolkata',
    branchScope: 'whole gym',
    dataRowCount: 1,
  });
  it('paise beyond the JS safe integer survives as canonical decimal text', async () => {
    const build = (await csvModule()).buildReportCsv;
    const records = parseCsv(build('payments', meta(), [paymentRow({ amount_paise: '9007199254740993' })]));
    const data = records[2];
    expect(data[COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('amount_paise')]).toBe('9007199254740993');
    expect(BigInt(data[COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('amount_paise')])).toBe(9007199254740993n);
  });
  it('amount_display is presentation only and is never parsed back to money', async () => {
    const build = (await csvModule()).buildReportCsv;
    const records = parseCsv(build('payments', meta(), [
      paymentRow({ amount_display: '₹1,500.00' }),
      paymentRow({ payment_id: '75900000-0000-4000-8000-000000000304', amount_display: 'garmented display' }),
    ]));
    const amountCol = COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('amount_paise');
    const displayCol = COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('amount_display');
    expect(records[2][displayCol]).toBe('₹1,500.00');
    expect(records[3][displayCol]).toBe('garmented display');
    expect(records[2][amountCol]).toBe('150000');
    expect(records[3][amountCol]).toBe('150000');
  });
  it('malformed or non-canonical required money refuses the whole file with no release', async () => {
    seedSnapshot([paymentRow({ amount_paise: '12.5' })]);
    const { status, order, events } = await runExport({ session: owner(), body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    expect(status).not.toBe(200);
    expect(order).not.toContain('report_export.released');
    expect(events.every((e) => e.kind === 'report_export.prepared')).toBe(true);
  });
});

describe('RPE-008 stamps and download protection', () => {
  it('a zero-match file still carries the header, metadata record and zero data rows', async () => {
    seedSnapshot([], 'Asia/Kolkata');
    const { status, body } = await runExport({ session: owner(), body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    expect(status).toBe(200);
    const records = parseCsv(body as Uint8Array);
    expect(records).toHaveLength(2);
    expect(records[1][0]).toBe('metadata');
    expect(records[1][COMMON_COLUMNS.indexOf('data_row_count')]).toBe('0');
  });
  it('UTC stamps carry Z and the local stamp carries its offset and named zone', async () => {
    seedSnapshot([paymentRow()], 'Asia/Kolkata');
    const { status, body } = await runExport({ session: owner(), body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    expect(status).toBe(200);
    const metaRow = parseCsv(body as Uint8Array)[1];
    expect(metaRow[COMMON_COLUMNS.indexOf('generated_at_utc')]).toMatch(/Z$/);
    expect(metaRow[COMMON_COLUMNS.indexOf('snapshot_at_utc')]).toMatch(/Z$/);
    expect(metaRow[COMMON_COLUMNS.indexOf('timezone')]).toBe('Asia/Kolkata');
    expect(metaRow[COMMON_COLUMNS.indexOf('range_basis')]).toBe('created_at');
  });
  it('the response is a private attachment with a safe ASCII filename and no-store caching', async () => {
    seedSnapshot([paymentRow()]);
    const { status, headers, body } = await runExport({ session: owner(), body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    expect(status).toBe(200);
    expect(headers['content-type']).toMatch(/text\/csv/);
    expect(headers['content-disposition']).toMatch(/^attachment; filename="/);
    const filename = /filename="([^"]+)"/.exec(headers['content-disposition'])?.[1] ?? '';
    expect(filename).toMatch(/^[A-Za-z0-9._-]+$/);
    expect(headers['cache-control']).toBe('no-store');
    expect(headers['x-content-type-options']).toBe('nosniff');
    expect((body as Uint8Array).length).toBeGreaterThan(0);
  });
  it('row caps exclude the header and metadata record', async () => {
    const limits = (await limitsModule()).RPE_LIMITS;
    const rows = Array.from({ length: limits?.csvMaxRows ?? 5000 }, (_, i) =>
      paymentRow({ payment_id: `75900000-0000-4000-8000-${String(4000 + i).padStart(12, '0')}` }));
    seedSnapshot(rows);
    const { status, body } = await runExport({ session: owner(), body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    expect(status).toBe(200);
    expect(parseCsv(body as Uint8Array)).toHaveLength(rows.length + 2);
  });
});

describe('RPE-009 data-egress audit', () => {
  const body = { dataset: 'payments' as const, from: '2026-09-01', through: '2026-09-30' };
  it('prepared is appended before the payload leaves the database; released before the first byte', async () => {
    // FINDING 1 (see header): the implementation appends `prepared` after the
    // snapshot read — necessarily, because `prepared` carries the snapshot's
    // row count. The contract ordering is pinned as: one snapshot read, then
    // `prepared`, then `released`, both before any response byte.
    seedSnapshot([paymentRow()]);
    const { status, order } = await runExport({ session: owner(), body });
    expect(status).toBe(200);
    expect(order.indexOf('snapshot')).toBe(0);
    expect(order.indexOf('report_export.prepared')).toBeGreaterThan(order.indexOf('snapshot'));
    expect(order.indexOf('report_export.released')).toBeGreaterThan(order.indexOf('report_export.prepared'));
  });
  it('both audit events share one server-generated export UUID and carry scope without personal content', async () => {
    seedSnapshot([paymentRow()]);
    const { status, body: file, events } = await runExport({ session: owner(), body });
    expect(status).toBe(200);
    expect(events).toHaveLength(2);
    const [prepared, released] = events;
    expect(prepared.exportId).toBeTruthy();
    expect(released.exportId).toBe(prepared.exportId);
    const serialized = JSON.stringify(events);
    expect(serialized).not.toContain('Ravi Kumar');
    expect(serialized).not.toContain('+919876543210');
    expect(serialized).not.toContain('R-2026-0007');
    expect(released.byteCount).toBe((file as Uint8Array).byteLength);
    expect(released.sha256).toBe(createHash('sha256').update(Buffer.from(file as Uint8Array)).digest('hex'));
    expect(prepared.rowCount).toBe(1);
  });
  it('audit failure releases no file and repeated downloads are fresh auditable attempts', async () => {
    seedSnapshot([paymentRow()]);
    state.failWhen = (_name, args) => args.p_event === 'report_export.released';
    const refused = await runExport({ session: owner(), body });
    expect(refused.status).not.toBe(200);
    expect(refused.order).not.toContain('report_export.released');
    expect(refused.events.map((e) => e.kind)).toEqual(['report_export.prepared']);
    // The audit failure was scripted onto that one run's adapter; the fresh
    // attempts below run with clean mocks.
    state.failWhen = null;
    seedSnapshot([paymentRow()]);
    const one = await runExport({ session: owner(), body });
    seedSnapshot([paymentRow()]);
    const two = await runExport({ session: owner(), body });
    expect(one.events[0].exportId).not.toBe(two.events[0].exportId);
    // Every fresh download is a fresh artifact: the frozen metadata spec puts
    // the export UUID and generation/snapshot stamps INSIDE the file, so
    // whole-file byte equality across attempts is unimplementable. The
    // repeated-download pin is the data projection's equality.
    const dataTail = (csv: Uint8Array) =>
      parseCsv(csv).filter((r) => r[0] === 'data').map((r) => r.slice(COMMON_COLUMNS.length).join(','));
    expect(dataTail(one.body as Uint8Array)).toEqual(dataTail(two.body as Uint8Array));
  });
  it('a source snapshot failure leaves a truthful prepared-only audit trail', async () => {
    // FINDING 3 (see header): no snapshot was prepared on a source-read
    // failure — RPE-009's trigger is a PREPARED snapshot — so the truthful
    // trail is empty. The prepared-without-release trail is real and is
    // pinned by the audit-failure test above.
    seedSnapshot([paymentRow()]);
    state.rpcError = { code: 'XX000', message: 'snapshot failed' };
    state.failWhen = (name) => name === 'export_report_snapshot';
    const { status, order, events } = await runExport({ session: owner(), body });
    expect(status).not.toBe(200);
    expect(order).not.toContain('report_export.released');
    expect(events.map((e) => e.kind)).toEqual([]);
  });
});
