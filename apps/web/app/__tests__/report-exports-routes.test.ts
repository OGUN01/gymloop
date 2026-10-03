import type { GymloopIdentity, StaffRole } from '../../lib/identity';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// RPE frozen contract (CSV-first delivery): POST /api/report-exports is the one
// CSV download route for this wave. RPE-010…012 (invoice PDF) are deferred and
// intentionally absent here.
const state = vi.hoisted(() => ({
  kind: 'staff' as 'staff' | 'member' | 'unlinked' | 'platform',
  role: 'gym_owner' as StaffRole,
  signedIn: true,
  data: null as unknown,
  error: null as unknown,
  failWhen: null as null | ((name: string, args: Record<string, unknown>) => boolean),
  calls: [] as Array<[string, Record<string, unknown>]>,
}));

const OWNER_USER = '86000000-0000-4000-8000-000000000901';
const TENANT = '86000000-0000-4000-8000-000000000001';
const STAFF_ID = '86000000-0000-4000-8000-000000000021';
const BRANCH = '86000000-0000-4000-8000-000000000301';

const identity = (): { signedIn: boolean; authenticatedUser: boolean; supabase: unknown; identity: GymloopIdentity } => {
  const base = { signedIn: state.signedIn, authenticatedUser: state.signedIn, supabase: db };
  if (!state.signedIn) return { ...base, identity: { kind: 'unlinked' } as GymloopIdentity };
  if (state.kind === 'member') {
    return { ...base, identity: { kind: 'member', userId: OWNER_USER, tenantId: TENANT, memberId: '86000000-0000-4000-8000-000000000101' } as GymloopIdentity };
  }
  if (state.kind === 'platform') {
    return { ...base, identity: { kind: 'staff', userId: OWNER_USER, tenantId: TENANT, staffId: STAFF_ID, role: 'super_admin' as StaffRole } as GymloopIdentity };
  }
  return { ...base, identity: { kind: 'staff', userId: OWNER_USER, tenantId: TENANT, staffId: STAFF_ID, role: state.role } as GymloopIdentity };
};

const result = () => ({ data: state.data, error: state.error });
const builder: Record<string, unknown> = new Proxy({}, {
  get: (_target, prop) => {
    if (prop === 'then') {
      return (resolve: (value: unknown) => void, reject: (reason: unknown) => void) =>
        Promise.resolve(result()).then(resolve, reject);
    }
    return () => builder;
  },
});
const db = {
  rpc: (name: string, args: Record<string, unknown>) => {
    state.calls.push([name, args]);
    const failed = state.failWhen?.(name, args) ?? false;
    return Promise.resolve(failed ? { data: null, error: { message: 'audit write failed' } } : result());
  },
  from: (_table: string) => {
    state.calls.push([String(_table), {}]);
    return builder;
  },
};

vi.mock('../../lib/identity-session', () => ({
  readIdentity: async () => identity(),
  readRequestIdentity: async () => identity(),
}));

const paymentRow = (overrides: Record<string, unknown> = {}) => ({
  payment_id: '86000000-0000-4000-8000-000000000701',
  member_id: '86000000-0000-4000-8000-000000000101',
  member_code: 'M-0007',
  current_member_name: 'Aditi Rao',
  amount_paise: '150000',
  amount_display: '₹1,500',
  currency: 'INR',
  status: 'paid',
  method: 'cash',
  created_at_utc: '2026-09-01T04:30:00Z',
  paid_at_utc: '2026-09-01T04:35:00Z',
  receipt_number: 'R-2026-0042',
  ...overrides,
});

const POST = async (body: unknown, init: RequestInit = {}) => {
  const { POST: handler } = await import('../api/report-exports/route');
  return (handler as (request: Request) => Promise<Response>)(
    new Request('https://gymloop.test/api/report-exports', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: typeof body === 'string' ? body : JSON.stringify(body),
      ...init,
    }),
  );
};

const decode = async (response: Response) => new TextDecoder('utf-8', { ignoreBOM: true }).decode(await response.arrayBuffer());

const COMMON = 'row_type,export_id,generated_at_utc,snapshot_at_utc,range_from,range_through,range_basis,timezone,branch_scope,data_row_count';
const DATASET_COLUMNS: Record<string, string> = {
  payments: 'payment_id,member_id,member_code,current_member_name,amount_paise,amount_display,currency,status,method,created_at_utc,paid_at_utc,receipt_number',
  attendance: 'attendance_id,member_id,member_code,current_member_name,branch_id,source,checked_in_at_utc,checked_in_local,checked_out_at_utc,offline_recorded_at_utc,replayed_at_utc',
  members: 'member_id,member_code,full_name,phone,email,branch_id,status,joined_on',
};
const RANGE_BASIS: Record<string, string> = { payments: 'created_at', attendance: 'checked_in_at', members: 'joined_on' };

const goodBody = (dataset = 'payments') => ({ dataset, from: '2026-09-01', through: '2026-09-30' });

beforeEach(() => {
  state.kind = 'staff';
  state.role = 'gym_owner';
  state.signedIn = true;
  state.data = null;
  state.error = null;
  state.failWhen = null;
  state.calls = [];
});

describe('RPE-001/002 owner-only route with original-caller RLS', () => {
  it('gym_owner succeeds and the only data reads happen under the caller identity (no service seam)', async () => {
    state.data = [paymentRow()];
    const response = await POST(goodBody());
    expect(response.status).toBe(200);
    expect(state.calls.length).toBeGreaterThan(0);
    expect(JSON.stringify(state.calls)).not.toContain('service_role');
  });

  it.each([
    ['gym_manager', 403],
    ['front_desk', 403],
    ['trainer', 403],
  ] as Array<[StaffRole, number]>)('%s is refused before target facts', async (role, status) => {
    state.role = role;
    const response = await POST(goodBody());
    expect(response.status).toBe(status);
    expect(state.calls).toEqual([]);
  });

  it('member, signed-out and platform identities gain no export authority', async () => {
    state.kind = 'member';
    expect((await POST(goodBody())).status).toBe(403);
    state.kind = 'staff';
    state.signedIn = false;
    expect((await POST(goodBody())).status).toBe(401);
    state.signedIn = true;
    state.kind = 'platform';
    expect((await POST(goodBody())).status).toBe(403);
    expect(state.calls).toEqual([]);
  });

  it('identifies the caller before parsing a malformed body', async () => {
    state.signedIn = false;
    const response = await POST('{', { headers: { 'content-type': 'application/json' } });
    expect([401, 403]).toContain(response.status);
    expect(state.calls).toEqual([]);
  });

  it('cross-origin requests are refused (CSRF/same-origin protection)', async () => {
    state.data = [paymentRow()];
    const response = await POST(goodBody(), { headers: { 'content-type': 'application/json', origin: 'https://evil.example' } });
    expect(response.status).toBe(403);
    expect(response.headers.get('content-type')).not.toContain('csv');
  });
});

describe('RPE-003 bounded exact request', () => {
  it('rejects unknown keys strictly', async () => {
    const response = await POST({ ...goodBody(), tenantId: TENANT });
    expect(response.status).toBe(400);
    expect(state.calls).toEqual([]);
  });

  it.each([
    ['malformed date', { dataset: 'payments', from: '2026-13-01', through: '2026-09-30' }],
    ['reversed range', { dataset: 'payments', from: '2026-09-30', through: '2026-09-01' }],
    ['oversize range (367 days)', { dataset: 'payments', from: '2025-01-01', through: '2026-01-02' }],
    ['unknown dataset', { dataset: 'invoices', from: '2026-09-01', through: '2026-09-30' }],
    ['invalid branch uuid', { ...goodBody(), branchId: 'not-a-uuid' }],
  ])('refuses %s before any source scan', async (_label, body) => {
    const response = await POST(body);
    expect(response.status).toBe(400);
    expect(state.calls).toEqual([]);
  });

  it('unknown and foreign branches share one unavailable response with no existence hint', async () => {
    state.data = [];
    state.error = { code: '42501', message: 'PRIVATE branch detail' };
    const unknownResponse = await POST({ ...goodBody(), branchId: BRANCH });
    const foreignResponse = await POST({ ...goodBody(), branchId: '86000000-0000-4000-8000-000000000999' });
    expect(unknownResponse.status).toBe(404);
    const unknownBody = await unknownResponse.text();
    const foreignBody = await foreignResponse.text();
    expect(unknownBody).toBe(foreignBody);
    expect(unknownBody).not.toContain('PRIVATE');
  });

  it('a transport-oversize body is refused without source facts', async () => {
    const response = await POST(JSON.stringify({ ...goodBody(), filler: 'x'.repeat(3000) }));
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(response.headers.get('content-type')).not.toContain('csv');
    expect(state.calls).toEqual([]);
  });

  it('GET is not an export method', async () => {
    const routeModule = (await import('../api/report-exports/route')) as unknown as Record<string, unknown>;
    expect(routeModule.GET).toBeUndefined();
  });
});

describe('RPE-004/005 complete snapshot and defined projection', () => {
  it.each(['payments', 'attendance', 'members'] as const)('%s emits BOM, CRLF, the fixed header and a complete metadata record', async (dataset) => {
    state.data = dataset === 'payments' ? [paymentRow()] : [];
    const response = await POST(goodBody(dataset));
    expect(response.status).toBe(200);
    const text = await decode(response);
    expect(text.charCodeAt(0)).toBe(0xfeff);
    const records = text.slice(1).split('\r\n').filter((line) => line.length > 0);
    expect(records[0]).toBe(`${COMMON},${DATASET_COLUMNS[dataset]}`);
    const metadata = records[1]!.split(',');
    expect(metadata[0]).toBe('metadata');
    expect(metadata[1]).toMatch(/^[0-9a-f-]{36}$/);
    for (const stamp of metadata.slice(2, 9)) expect(stamp.length).toBeGreaterThan(0);
    expect(metadata[6]).toBe(RANGE_BASIS[dataset]);
    expect(metadata[9]).toBe(dataset === 'payments' ? '1' : '0');
  });

  it('a zero-match file still carries header, metadata stamps and zero data rows', async () => {
    state.data = [];
    const response = await POST(goodBody('members'));
    const text = await decode(response);
    const records = text.slice(1).split('\r\n').filter((line) => line.length > 0);
    expect(records).toHaveLength(2);
    expect(records[1]!.startsWith('metadata,')).toBe(true);
  });

  it('exceeding the 5,000-row cap releases no file', async () => {
    state.data = Array.from({ length: 5001 }, (_, index) => paymentRow({ payment_id: `86000000-0000-4000-8000-${String(index).padStart(12, '0')}` }));
    const response = await POST(goodBody());
    expect(response.status).toBe(409);
    expect(response.headers.get('content-type')).not.toContain('csv');
  });

  it('money stays canonical decimal text and the display column stays presentation-only', async () => {
    state.data = [paymentRow({ amount_paise: '12345678901234' })];
    const text = await decode(await POST(goodBody()));
    expect(text).toContain('12345678901234');
    expect(text).not.toMatch(/1\.2345678901234e\+?1[0-9]/i);
  });

  it('unavailable paid time and receipt stay blank, never inferred', async () => {
    state.data = [paymentRow({ status: 'created', paid_at_utc: null, receipt_number: null })];
    const text = await decode(await POST(goodBody()));
    const dataLine = text.split('\r\n').find((line) => line.startsWith('data,'));
    expect(dataLine).toBeDefined();
    expect(dataLine).toContain(',created,');
    expect(dataLine).not.toContain('inferred');
  });

  it('an erased/missing profile leaves name and code blank instead of reconstructing them', async () => {
    state.data = [paymentRow({ current_member_name: null, member_code: null })];
    const text = decode(await POST(goodBody())) as unknown as Promise<string>;
    const resolved = await (text as unknown as Promise<string>);
    const dataLine = resolved.split('\r\n').find((line) => line.startsWith('data,'));
    expect(dataLine).toBeDefined();
    expect(dataLine).not.toContain('Aditi');
  });

  it('untrusted text is apostrophe-prefixed and quote-doubled; phones stay text', async () => {
    state.data = [
      paymentRow({ current_member_name: '=cmd|\' /C calc\'!A0' }),
      paymentRow({ member_code: '+919876543210' }),
    ];
    const text = decode(await POST(goodBody())) as unknown as Promise<string>;
    const resolved = await (text as unknown as Promise<string>);
    expect(resolved).toContain("'=cmd");
    expect(resolved).toContain("''");
    expect(resolved).toContain("'+919876543210");
  });
});

describe('RPE-008/009 download protection and data-egress audit', () => {
  it('releases a private attachment with a safe ASCII filename', async () => {
    state.data = [paymentRow()];
    const response = await POST(goodBody());
    const disposition = response.headers.get('content-disposition') ?? '';
    expect(disposition).toContain('attachment');
    const filename = /filename="?([^";]+)"?/.exec(disposition)?.[1] ?? '';
    expect(filename).toMatch(/^[\x20-\x7e]+\.csv$/);
    expect(filename).toContain('payments');
    expect(response.headers.get('cache-control')).toContain('no-store');
    expect(response.headers.get('x-content-type-options')).toBe('nosniff');
  });

  it('appends report_export.prepared before release and report_export.released before the first byte', async () => {
    state.data = [paymentRow()];
    const response = await POST(goodBody());
    expect(response.status).toBe(200);
    const journal = JSON.stringify(state.calls);
    expect(journal).toContain('report_export.prepared');
    expect(journal).toContain('report_export.released');
    expect(journal.indexOf('report_export.prepared')).toBeLessThan(journal.indexOf('report_export.released'));
  });

  it('an audit write failure releases no file bytes', async () => {
    state.data = [paymentRow()];
    state.failWhen = (name) => name.includes('report_export');
    const response = await POST(goodBody());
    expect(response.status).toBeGreaterThanOrEqual(500);
    expect(response.headers.get('content-type')).not.toContain('csv');
  });
});
