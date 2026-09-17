import { describe, expect, it } from 'vitest';
import { fleetMetricsSchema, formatBasisPoints, ownerMetricsSchema, ratioBasisPoints } from '../metrics';

// Authored from the frozen Phase 6 contract before the metrics implementation.
const response = {
  tenantId: '11111111-1111-4111-8111-111111111111', asOf: '2026-09-17T10:00:00+00:00',
  timezone: 'Asia/Kolkata', localToday: '2026-09-17',
  range: { from: '2026-09-01', through: '2026-09-17', startsAt: '2026-08-31T18:30:00+00:00', endsBefore: '2026-09-17T18:30:00+00:00', mode: 'explicit' },
  cards: { visitsToday: '2', liveMembers: '12', pausedMembers: '1', openCases: '3', followUpsDue: '1', recovered: '4', cash: [{ currency: 'INR', collectedPaise: '150000', returnedPaise: '0', netPaise: '150000' }], renewal: [{ currency: 'INR', duePaise: '50000' }], leads: { converted: '2', total: '5' }, addonCash: [], pt: { sessionsUsed: '3', sessionsTotal: '10', orders: '2' } },
  components: { visits: [], liveMembers: [], cases: [], recoveries: [], collected: [], returned: [], renewals: [], leads: [], ptOrders: [] },
  warnings: { undatedPayments: [], undatedReturns: [], undatedPtOrders: [], incompletePtOrders: [] },
};

describe('metrics schemas and exact arithmetic', () => {
  it('freezes the exact fleet envelope and decimal count representation', () => {
    const fleet = { asOf: response.asOf, gyms: [], exceptions: { settingsIncomplete: [], ownerAccessPending: [], providerUnavailable: [], trialExpired: [] } };
    expect(fleetMetricsSchema.parse(fleet)).toEqual(fleet);
    expect(() => fleetMetricsSchema.parse({ ...fleet, extra: true })).toThrow();
  });

  it('accepts canonical decimal strings and rejects JSON numbers', () => {
    expect(ownerMetricsSchema.parse(response)).toEqual(response);
    expect(() => ownerMetricsSchema.parse({ ...response, cards: { ...response.cards, visitsToday: 2 } })).toThrow();
  });

  it('rejects extra keys at every exact object boundary', () => {
    expect(() => ownerMetricsSchema.parse({ ...response, unexpected: true })).toThrow();
    expect(() => ownerMetricsSchema.parse({ ...response, range: { ...response.range, unexpected: true } })).toThrow();
  });

  it('rounds BigInt-safe ratios half-up and returns null for zero denominator', () => {
    expect(ratioBasisPoints('1', '3')).toBe('3333');
    expect(ratioBasisPoints('2', '3')).toBe('6667');
    expect(ratioBasisPoints('9007199254740993', '2')).toBe('45035996273704965000');
    expect(ratioBasisPoints('5', '0')).toBeNull();
    expect(formatBasisPoints('3333')).toBe('33.33%');
    expect(formatBasisPoints('0')).toBe('0.00%');
  });
});
