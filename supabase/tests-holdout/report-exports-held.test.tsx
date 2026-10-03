// Independent holdout for RPE (report exports), frozen contract 2026-10-03:
// openspec/changes/report-exports/proposal.md (CSV-first delivery,
// RPE-001…009 + RPE-013; the invoice half is deferred and untested here) and
// docs/design/v2/rpe-bar.md. Authored without reading any visible suite,
// implementation, registry or other holdout.
//
// Driver assumptions derived from the frozen contract only (the orchestrator
// reconciles exact names at implementation): the route-facing orchestration is
// one seam, `runReportExport({ session, adapter, body, now })`, reading through
// one injected bounded snapshot adapter and one audited append-only audit
// writer; the pure serializer is `buildReportCsv(dataset, meta, rows)`; the
// frozen caps live centrally as `RPE_LIMITS`. Until those exports exist every
// test fails on its dynamic import — the expected RED — and becomes meaningful
// as the implementation lands.
import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';

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
  fromInstant?: string;
  throughInstant?: string;
  timezone: string;
  branchId?: string | null;
  probe: number;
};
type SnapshotResult = {
  rows: Array<Record<string, string | null>>;
  snapshotAt: string;
  timezone: string;
  basis: string;
  count: number;
};
type AuditEvent = { kind: 'report_export.prepared' | 'report_export.released' } & Record<string, unknown>;
type Adapter = {
  fetchSnapshot: (request: SnapshotRequest) => Promise<SnapshotResult>;
  appendAudit: (event: AuditEvent) => Promise<void>;
};
type ExportOutcome = {
  status: number;
  headers: Record<string, string>;
  body: Uint8Array | { error: string; detail?: unknown };
  exportId?: string;
};

const owner = (overrides: Partial<OwnerSession> = {}): OwnerSession => ({
  tenantId: TENANT,
  userId: OWNER_USER,
  staffId: OWNER_STAFF,
  role: 'gym_owner',
  staffActive: true,
  ...overrides,
});

type AdapterScript = {
  rows?: Array<Record<string, string | null>>;
  count?: number;
  snapshotAt?: string;
  timezone?: string;
  basis?: string;
  snapshotError?: Error;
  auditErrorOn?: AuditEvent['kind'];
};

const makeAdapter = (script: AdapterScript = {}) => {
  const events: AuditEvent[] = [];
  const order: string[] = [];
  const seenRequests: SnapshotRequest[] = [];
  const adapter: Adapter = {
    fetchSnapshot: async (request) => {
      order.push('snapshot');
      seenRequests.push(request);
      if (script.snapshotError) throw script.snapshotError;
      const rows = script.rows ?? [];
      return {
        rows,
        snapshotAt: script.snapshotAt ?? NOW,
        timezone: script.timezone ?? 'Asia/Kolkata',
        basis: script.basis ?? 'created_at',
        count: script.count ?? rows.length,
      };
    },
    appendAudit: async (event) => {
      order.push(event.kind);
      if (script.auditErrorOn === event.kind) throw new Error('audit write failed');
      events.push(event);
    },
  };
  return { adapter, events, order, seenRequests };
};

const runExport = async (input: {
  session: OwnerSession;
  adapter: Adapter;
  body: unknown;
  now?: () => Date;
}): Promise<ExportOutcome> => {
  const mod = (await import('../../apps/web/lib/report-exports')) as {
    runReportExport: (input: unknown) => Promise<ExportOutcome>;
  };
  return mod.runReportExport(input);
};

const csvModule = async () =>
  (await import('../../apps/web/lib/report-exports')) as {
    buildReportCsv: (
      dataset: Dataset,
      meta: Record<string, string>,
      rows: Array<Record<string, string | null>>,
    ) => Uint8Array;
  };

const limitsModule = async () =>
  (await import('../../packages/shared/src/config/constants')) as {
    RPE_LIMITS: Record<string, number>;
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

describe('RPE-001/002 identity and RLS ordering', () => {
  it('a non-owner identity is refused before any parameter validation, lookup or source read', async () => {
    for (const role of ['gym_manager', 'front_desk', 'trainer', 'member', 'support', 'platform_super_admin'] as const) {
      const { adapter, order } = makeAdapter({ rows: [paymentRow()] });
      const outcome = await runExport({
        session: owner({ role }),
        adapter,
        body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' },
      });
      expect(outcome.status).toBe(403);
      expect((outcome.body as { error: string }).error).toBeTruthy();
      expect(order).toEqual([]);
    }
  });
  it('an inactive, impersonated or preview owner claim is refused without target facts', async () => {
    for (const overrides of [{ staffActive: false }, { impersonated: true }, { preview: true }]) {
      const { adapter, order } = makeAdapter({ rows: [paymentRow()] });
      const outcome = await runExport({ session: owner(overrides), adapter, body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
      expect(outcome.status).toBe(403);
      expect(order).toEqual([]);
    }
  });
  it('an invalid dataset or reversed range on a valid owner session is refused without a snapshot read', async () => {
    const { adapter, order, seenRequests } = makeAdapter();
    const bad = await runExport({ session: owner(), adapter, body: { dataset: 'invoices', from: '2026-09-01', through: '2026-09-30' } });
    expect(bad.status).toBe(400);
    const reversed = await runExport({ session: owner(), adapter, body: { dataset: 'payments', from: '2026-09-30', through: '2026-09-01' } });
    expect(reversed.status).toBe(400);
    expect(seenRequests).toEqual([]);
    expect(order).toEqual([]);
  });
  it('an oversize transport body is refused with no source facts even before authentication', async () => {
    const { adapter, order } = makeAdapter({ rows: [paymentRow()] });
    const limits = (await limitsModule()).RPE_LIMITS;
    const filler = 'x'.repeat((limits?.bodyMaxBytes ?? 2048) + 1);
    const outcome = await runExport({
      session: owner(),
      adapter,
      body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30', note: filler },
    });
    expect(outcome.status).not.toBe(200);
    expect(order).toEqual([]);
  });
  it('unknown and foreign branch ids share one unavailable response after actor validation', async () => {
    const unknownRun = makeAdapter();
    const foreignRun = makeAdapter();
    const body = { dataset: 'attendance', from: '2026-09-01', through: '2026-09-30', branchId: BRANCH_A };
    const unknown = await runExport({ session: owner(), adapter: unknownRun.adapter, body });
    const foreign = await runExport({ session: owner({ tenantId: '75900000-0000-4000-8000-000000000009' }), adapter: foreignRun.adapter, body: { ...body, branchId: BRANCH_B } });
    expect(unknown.status).toBe(foreign.status);
    expect(unknown.status).not.toBe(200);
    expect((unknown.body as { error: string }).error).toBe((foreign.body as { error: string }).error);
  });
});

describe('RPE-003 exact range conversion', () => {
  it('attendance bounds are branch-local midnights across a spring-forward offset change', async () => {
    const { adapter, seenRequests } = makeAdapter({ timezone: 'America/New_York', basis: 'checked_in_at' });
    const outcome = await runExport({
      session: owner(),
      adapter,
      body: { dataset: 'attendance', from: '2026-03-07', through: '2026-03-08' },
    });
    expect(outcome.status).toBe(200);
    expect(seenRequests).toHaveLength(1);
    // 2026-03-07 local midnight EST = 05:00Z; 2026-03-08 local midnight EDT = 04:00Z.
    expect(seenRequests[0].fromInstant).toBe('2026-03-07T05:00:00.000Z');
    expect(seenRequests[0].throughInstant).toBe('2026-03-08T04:00:00.000Z');
  });
  it('attendance bounds across a fall-back offset change keep both midnights one hour apart', async () => {
    const { adapter, seenRequests } = makeAdapter({ timezone: 'America/New_York', basis: 'checked_in_at' });
    await runExport({ session: owner(), adapter, body: { dataset: 'attendance', from: '2026-10-31', through: '2026-11-01' } });
    expect(seenRequests[0].fromInstant).toBe('2026-10-31T04:00:00.000Z');
    expect(seenRequests[0].throughInstant).toBe('2026-11-01T05:00:00.000Z');
  });
  it('members use direct joined_on date comparison with no instant conversion', async () => {
    const { adapter, seenRequests } = makeAdapter({ basis: 'joined_on', timezone: 'America/New_York' });
    await runExport({ session: owner(), adapter, body: { dataset: 'members', from: '2026-03-07', through: '2026-03-08' } });
    expect(seenRequests[0].from).toBe('2026-03-07');
    expect(seenRequests[0].through).toBe('2026-03-08');
    expect(seenRequests[0].fromInstant).toBeUndefined();
    expect(seenRequests[0].throughInstant).toBeUndefined();
  });
  it('a range beyond 366 days and an invalid UUID branch are refused before the bounded scan', async () => {
    const limits = (await limitsModule()).RPE_LIMITS;
    const { adapter, seenRequests } = makeAdapter();
    const long = await runExport({ session: owner(), adapter, body: { dataset: 'payments', from: '2025-01-01', through: '2026-01-01' } });
    expect(long.status).toBe(400);
    const badBranch = await runExport({ session: owner(), adapter, body: { dataset: 'attendance', from: '2026-09-01', through: '2026-09-02', branchId: 'not-a-uuid' } });
    expect(badBranch.status).toBe(400);
    expect(seenRequests).toEqual([]);
    expect(limits.maxRangeDays).toBe(366);
  });
});

describe('RPE-004 one complete snapshot', () => {
  it('the source operation is one bounded payload, not paged HTTP reads', async () => {
    const rows = [paymentRow(), paymentRow({ payment_id: '75900000-0000-4000-8000-000000000302' })];
    const { adapter, seenRequests } = makeAdapter({ rows });
    await runExport({ session: owner(), adapter, body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    expect(seenRequests).toHaveLength(1);
    expect(seenRequests[0].probe).toBeGreaterThan(rows.length);
  });
  it('cap+1 rows refuse the entire file before any bytes are produced', async () => {
    const limits = (await limitsModule()).RPE_LIMITS;
    const rows = Array.from({ length: (limits?.csvMaxRows ?? 5000) + 1 }, (_, i) =>
      paymentRow({ payment_id: `75900000-0000-4000-8000-${String(3000 + i).padStart(12, '0')}` }));
    const { adapter, events, order } = makeAdapter({ rows, count: rows.length });
    const outcome = await runExport({ session: owner(), adapter, body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    expect(outcome.status).not.toBe(200);
    expect(order).not.toContain('report_export.released');
    expect(events.every((e) => e.kind === 'report_export.prepared')).toBe(true);
  });
  it('a deadline overrun releases no partial file', async () => {
    const limits = (await limitsModule()).RPE_LIMITS;
    let calls = 0;
    const { adapter, events, order } = makeAdapter({ rows: [paymentRow()] });
    const slowAdapter: Adapter = {
      fetchSnapshot: async (request) => {
        calls += 1;
        return adapter.fetchSnapshot(request);
      },
      appendAudit: adapter.appendAudit,
    };
    const outcome = await runExport({
      session: owner(),
      adapter: slowAdapter,
      body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' },
      now: () => {
        calls += 0;
        return new Date(Date.parse(NOW) + calls * ((limits?.generationDeadlineMs ?? 15000) + 1000));
      },
    });
    expect(outcome.status).not.toBe(200);
    expect(order).not.toContain('report_export.released');
    expect(events.every((e) => e.kind === 'report_export.prepared')).toBe(true);
  });
});

describe('RPE-005 defined projection and unknowns', () => {
  it('each dataset emits exactly its frozen data columns after the common columns', async () => {
    const build = (await csvModule()).buildReportCsv;
    const meta = { export_id: '75900000-0000-4000-8000-000000000501', generated_at_utc: NOW, snapshot_at_utc: NOW, range_from: '2026-09-01', range_through: '2026-09-30', range_basis: 'created_at', timezone: 'Asia/Kolkata', branch_scope: 'whole gym' };
    const payments = parseCsv(build('payments', meta, [paymentRow()]));
    expect(payments[0]).toEqual([...COMMON_COLUMNS, ...PAYMENTS_COLUMNS]);
    const attendance = parseCsv(build('attendance', { ...meta, range_basis: 'checked_in_at' }, [{ attendance_id: '75900000-0000-4000-8000-000000000601', member_id: '75900000-0000-4000-8000-000000000401', member_code: 'MEM-0001', current_member_name: 'Ravi Kumar', branch_id: BRANCH_A, source: 'assisted', checked_in_at_utc: '2026-09-01T04:30:00Z', checked_in_local: '2026-09-01T10:00:00+05:30', checked_out_at_utc: null, offline_recorded_at_utc: null, replayed_at_utc: null }]));
    expect(attendance[0]).toEqual([...COMMON_COLUMNS, ...ATTENDANCE_COLUMNS]);
    const members = parseCsv(build('members', { ...meta, range_basis: 'joined_on' }, [{ member_id: '75900000-0000-4000-8000-000000000401', member_code: 'MEM-0001', full_name: 'Ravi Kumar', phone: '+919876543210', email: 'ravi@example.com', branch_id: BRANCH_A, status: 'active', joined_on: '2026-09-01' }]));
    expect(members[0]).toEqual([...COMMON_COLUMNS, ...MEMBERS_COLUMNS]);
  });
  it('a null paid time, receipt or erased profile stays blank and is never inferred', async () => {
    const build = (await csvModule()).buildReportCsv;
    const meta = { export_id: '75900000-0000-4000-8000-000000000502', generated_at_utc: NOW, snapshot_at_utc: NOW, range_from: '2026-09-01', range_through: '2026-09-30', range_basis: 'created_at', timezone: 'Asia/Kolkata', branch_scope: 'whole gym' };
    const records = parseCsv(build('payments', meta, [paymentRow({ paid_at_utc: null, receipt_number: null, current_member_name: null, member_code: null })]));
    const data = records[2];
    expect(data[COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('paid_at_utc')]).toBe('');
    expect(data[COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('receipt_number')]).toBe('');
    expect(data[COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('current_member_name')]).toBe('');
    expect(data[COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('member_code')]).toBe('');
  });
  it('cross-currency rows keep their own currency and no totals row is added', async () => {
    const build = (await csvModule()).buildReportCsv;
    const meta = { export_id: '75900000-0000-4000-8000-000000000503', generated_at_utc: NOW, snapshot_at_utc: NOW, range_from: '2026-09-01', range_through: '2026-09-30', range_basis: 'created_at', timezone: 'Asia/Kolkata', branch_scope: 'whole gym' };
    const records = parseCsv(build('payments', meta, [paymentRow(), paymentRow({ payment_id: '75900000-0000-4000-8000-000000000303', currency: 'USD', amount_paise: '2500', amount_display: '$25.00' })]));
    expect(records).toHaveLength(4); // header + metadata + two data rows
    expect(records[3][COMMON_COLUMNS.length + PAYMENTS_COLUMNS.indexOf('currency')]).toBe('USD');
    expect(records.every((r) => r[0] !== 'total')).toBe(true);
  });
});

describe('RPE-007 spreadsheet-safe CSV', () => {
  const build2 = async () => (await csvModule()).buildReportCsv;
  const meta = () => ({ export_id: '75900000-0000-4000-8000-000000000504', generated_at_utc: NOW, snapshot_at_utc: NOW, range_from: '2026-09-01', range_through: '2026-09-30', range_basis: 'created_at', timezone: 'Asia/Kolkata', branch_scope: 'whole gym' });

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
    const metaMembers = { ...meta(), range_basis: 'joined_on' };
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
  const meta = () => ({ export_id: '75900000-0000-4000-8000-000000000505', generated_at_utc: NOW, snapshot_at_utc: NOW, range_from: '2026-09-01', range_through: '2026-09-30', range_basis: 'created_at', timezone: 'Asia/Kolkata', branch_scope: 'whole gym' });
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
    const { adapter, events, order } = makeAdapter({ rows: [paymentRow({ amount_paise: '12.5' })] });
    const outcome = await runExport({ session: owner(), adapter, body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    expect(outcome.status).not.toBe(200);
    expect(order).not.toContain('report_export.released');
    expect(events.every((e) => e.kind === 'report_export.prepared')).toBe(true);
  });
});

describe('RPE-008 stamps and download protection', () => {
  it('a zero-match file still carries the header, metadata record and zero data rows', async () => {
    const { adapter } = makeAdapter({ rows: [], count: 0 });
    const outcome = await runExport({ session: owner(), adapter, body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    expect(outcome.status).toBe(200);
    const records = parseCsv(outcome.body as Uint8Array);
    expect(records).toHaveLength(2);
    expect(records[1][0]).toBe('metadata');
    expect(records[1][COMMON_COLUMNS.indexOf('data_row_count')]).toBe('0');
  });
  it('UTC stamps carry Z and the local stamp carries its offset and named zone', async () => {
    const { adapter } = makeAdapter({ rows: [paymentRow()], snapshotAt: '2026-10-03T09:30:00Z', timezone: 'Asia/Kolkata' });
    const outcome = await runExport({ session: owner(), adapter, body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    const records = parseCsv(outcome.body as Uint8Array);
    const metaRow = records[1];
    expect(metaRow[COMMON_COLUMNS.indexOf('generated_at_utc')]).toMatch(/Z$/);
    expect(metaRow[COMMON_COLUMNS.indexOf('snapshot_at_utc')]).toMatch(/Z$/);
    expect(metaRow[COMMON_COLUMNS.indexOf('timezone')]).toBe('Asia/Kolkata');
    expect(metaRow[COMMON_COLUMNS.indexOf('range_basis')]).toBe('created_at');
  });
  it('the response is a private attachment with a safe ASCII filename and no-store caching', async () => {
    const { adapter } = makeAdapter({ rows: [paymentRow()] });
    const outcome = await runExport({ session: owner(), adapter, body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    expect(outcome.headers['content-type']).toMatch(/text\/csv/);
    expect(outcome.headers['content-disposition']).toMatch(/^attachment; filename="/);
    const filename = /filename="([^"]+)"/.exec(outcome.headers['content-disposition'])?.[1] ?? '';
    expect(filename).toMatch(/^[A-Za-z0-9._-]+$/);
    expect(outcome.headers['cache-control']).toBe('no-store');
    expect(outcome.headers['x-content-type-options']).toBe('nosniff');
  });
  it('row caps exclude the header and metadata record', async () => {
    const limits = (await limitsModule()).RPE_LIMITS;
    const rows = Array.from({ length: limits?.csvMaxRows ?? 5000 }, (_, i) =>
      paymentRow({ payment_id: `75900000-0000-4000-8000-${String(4000 + i).padStart(12, '0')}` }));
    const { adapter } = makeAdapter({ rows, count: rows.length });
    const outcome = await runExport({ session: owner(), adapter, body: { dataset: 'payments', from: '2026-09-01', through: '2026-09-30' } });
    expect(outcome.status).toBe(200);
    expect(parseCsv(outcome.body as Uint8Array)).toHaveLength(rows.length + 2);
  });
});

describe('RPE-009 data-egress audit', () => {
  const body = { dataset: 'payments' as const, from: '2026-09-01', through: '2026-09-30' };
  it('prepared is appended before the payload leaves the database; released before the first byte', async () => {
    const { adapter, order } = makeAdapter({ rows: [paymentRow()] });
    const outcome = await runExport({ session: owner(), adapter, body });
    expect(outcome.status).toBe(200);
    expect(order.indexOf('report_export.prepared')).toBeGreaterThanOrEqual(0);
    expect(order.indexOf('report_export.prepared')).toBeLessThan(order.indexOf('snapshot'));
    expect(order.indexOf('report_export.released')).toBeGreaterThan(order.indexOf('snapshot'));
  });
  it('both audit events share one server-generated export UUID and carry scope without personal content', async () => {
    const { adapter, events } = makeAdapter({ rows: [paymentRow()] });
    const outcome = await runExport({ session: owner(), adapter, body });
    expect(events).toHaveLength(2);
    const [prepared, released] = events;
    expect(prepared.exportId).toBeTruthy();
    expect(released.exportId).toBe(prepared.exportId);
    const serialized = JSON.stringify(events);
    expect(serialized).not.toContain('Ravi Kumar');
    expect(serialized).not.toContain('+919876543210');
    expect(serialized).not.toContain('R-2026-0007');
    expect(released.byteCount).toBe((outcome.body as Uint8Array).byteLength);
    expect(released.sha256).toBe(createHash('sha256').update(Buffer.from(outcome.body as Uint8Array)).digest('hex'));
    expect(prepared.rowCount).toBe(1);
  });
  it('audit failure releases no file and repeated downloads are fresh auditable attempts', async () => {
    const failing = makeAdapter({ rows: [paymentRow()], auditErrorOn: 'report_export.released' });
    const refused = await runExport({ session: owner(), adapter: failing.adapter, body });
    expect(refused.status).not.toBe(200);
    expect(failing.order).not.toContain('report_export.released');
    const first = makeAdapter({ rows: [paymentRow()] });
    const second = makeAdapter({ rows: [paymentRow()] });
    const one = await runExport({ session: owner(), adapter: first.adapter, body });
    const two = await runExport({ session: owner(), adapter: second.adapter, body });
    expect(first.events[0].exportId).not.toBe(second.events[0].exportId);
    expect(text(one.body as Uint8Array)).toBe(text(two.body as Uint8Array));
  });
  it('a source snapshot failure leaves a truthful prepared-only audit trail', async () => {
    const { adapter, events, order } = makeAdapter({ snapshotError: new Error('snapshot failed') });
    const outcome = await runExport({ session: owner(), adapter, body });
    expect(outcome.status).not.toBe(200);
    expect(events.map((e) => e.kind)).toEqual(['report_export.prepared']);
    expect(order).not.toContain('report_export.released');
  });
});
