import { beforeEach, describe, expect, it, vi } from 'vitest';

type RefundRow = {
  id: string;
  payment_id: string;
  amount_paise: string;
  currency: string;
  kind: 'refund' | 'reversal';
  reason: string;
  status: 'requested' | 'processing' | 'completed' | 'failed';
  created_at: string;
  staff: { full_name: string };
};

type RefundQuery = {
  orders: Array<{ column: string; ascending: boolean }>;
  range: [number, number] | null;
};

const PAYMENT_ID = 'b5500000-0000-4000-8000-000000000001';
const POSTGREST_ROW_CAP = 1000;
const SAME_CREATED_AT = '2026-09-10T10:00:00Z';

const state = vi.hoisted(() => ({
  refundRows: [] as RefundRow[],
  refundQueries: [] as RefundQuery[],
}));

vi.mock('../supabase/server', () => ({
  createServerSupabase: async () => ({
    from: (table: string) => {
      const filters: Array<[string, unknown]> = [];
      const orders: Array<{ column: string; ascending: boolean }> = [];
      let selectedRange: [number, number] | null = null;
      const refundQuery: RefundQuery | null = table === 'refunds'
        ? { orders, range: selectedRange }
        : null;
      if (refundQuery) state.refundQueries.push(refundQuery);

      const execute = () => {
        if (table === 'payments') {
          return { data: {
            id: PAYMENT_ID,
            amount_paise: '9007199254750000',
            currency: 'INR',
            status: 'paid',
          }, error: null };
        }
        if (table === 'organizations') {
          return { data: { name: 'Pagination Gym', gym_code: 'PAGE', timezone: 'Asia/Kolkata' }, error: null };
        }
        if (table === 'addon_orders') return { data: null, error: null };
        if (table !== 'refunds') return { data: null, error: null };

        let rows = state.refundRows.filter((row) =>
          filters.every(([column, value]) => row[column as keyof RefundRow] === value),
        );
        for (const { column, ascending } of [...orders].reverse()) {
          rows = [...rows].sort((left, right) => {
            const comparison = String(left[column as keyof RefundRow]).localeCompare(
              String(right[column as keyof RefundRow]),
            );
            return ascending ? comparison : -comparison;
          });
        }

        const start = selectedRange?.[0] ?? 0;
        const requestedEnd = selectedRange === null
          ? start + POSTGREST_ROW_CAP
          : selectedRange[1] + 1;
        const cappedEnd = Math.min(requestedEnd, start + POSTGREST_ROW_CAP);
        return { data: rows.slice(start, cappedEnd), error: null };
      };

      const query = {
        select: () => query,
        eq: (column: string, value: unknown) => { filters.push([column, value]); return query; },
        order: (column: string, options?: { ascending?: boolean }) => {
          orders.push({ column, ascending: options?.ascending ?? true });
          return query;
        },
        limit: () => query,
        range: (from: number, to: number) => {
          selectedRange = [from, to];
          if (refundQuery) refundQuery.range = selectedRange;
          return query;
        },
        maybeSingle: async () => execute(),
        single: async () => execute(),
        then: (
          resolve: (value: ReturnType<typeof execute>) => unknown,
          reject: (reason: unknown) => unknown,
        ) => Promise.resolve(execute()).then(resolve, reject),
      };
      return query;
    },
  }),
}));

const { loadReceipt } = await import('../payments');

const failedRefund = (index: number): RefundRow => ({
  id: `a${String(index).padStart(4, '0')}`,
  payment_id: PAYMENT_ID,
  amount_paise: '9007199254740993',
  currency: 'INR',
  kind: 'refund',
  reason: 'Failed history must reserve nothing',
  status: 'failed',
  created_at: SAME_CREATED_AT,
  staff: { full_name: 'Owner' },
});

beforeEach(() => {
  state.refundQueries = [];
  state.refundRows = [
    ...Array.from({ length: POSTGREST_ROW_CAP }, (_, index) => failedRefund(index)),
    { ...failedRefund(POSTGREST_ROW_CAP), id: 'z001', status: 'completed', amount_paise: '9007199254740993' },
    { ...failedRefund(POSTGREST_ROW_CAP + 1), id: 'z002', status: 'requested', amount_paise: '1001' },
    { ...failedRefund(POSTGREST_ROW_CAP + 2), id: 'z003', status: 'processing', amount_paise: '2002', kind: 'reversal' },
    { ...failedRefund(POSTGREST_ROW_CAP + 3), id: 'z004', status: 'failed', amount_paise: '7000' },
  ];
});

describe('loadReceipt refund reconciliation beyond the PostgREST row cap', () => {
  it('ADD-009/ADD-011: reads every stable page and keeps completed, pending and failed exact BigInt amounts distinct', async () => {
    const result = await loadReceipt(PAYMENT_ID);

    expect.soft(result.refunds).toHaveLength(POSTGREST_ROW_CAP + 4);
    expect.soft(result.completedReturnedPaise).toBe('9007199254740993');
    expect.soft(result.pendingRefundPaise).toBe('3003');
    expect.soft(result.refundablePaise).toBe('6004');
    expect.soft(new Set(result.refunds.map(({ id }) => id)).size).toBe(POSTGREST_ROW_CAP + 4);

    expect.soft(state.refundQueries.length).toBeGreaterThan(1);
    const ranges = state.refundQueries
      .map(({ range }) => range)
      .filter((range): range is [number, number] => range !== null);
    expect.soft(ranges).toHaveLength(state.refundQueries.length);
    if (ranges.length > 0) {
      expect.soft(ranges[0]![0]).toBe(0);
      for (const [index, [from, to]] of ranges.entries()) {
        expect.soft(to - from + 1).toBeLessThanOrEqual(POSTGREST_ROW_CAP);
        if (index > 0) expect.soft(from).toBe(ranges[index - 1]![1] + 1);
      }
      expect.soft(ranges.at(-1)![1]).toBeGreaterThanOrEqual(state.refundRows.length - 1);
    }
    for (const { orders } of state.refundQueries) {
      expect.soft(orders).toEqual([
        { column: 'created_at', ascending: true },
        { column: 'id', ascending: true },
      ]);
    }
  });
});
