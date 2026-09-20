import { describe, expect, it, vi } from 'vitest';

const TENANT = 'tenant-7';
const CORRELATION = 'corr-9';
const REDACTED = '[REDACTED]';
const CIRCULAR = '[Circular]';

describe('independent HARD-005 operational logger holdout', () => {
  it('HARD-005 redacts separator and case variants at every nested depth', async () => {
    const { createOperationalLogger } = await import('../../../apps/web/lib/observability');
    const write = vi.fn();
    const logger = createOperationalLogger({ write, now: () => '2026-09-20T00:00:00.000Z' });
    const nested: Record<string, unknown> = {
      Authorization: 'Bearer hidden',
      'access-token': 'access-hidden',
      refresh_token: 'refresh-hidden',
      'service.role-key': 'service-hidden',
      profile: { E_MAIL: 'member@example.com', phone_number: '+919999999999', 'full-name': 'Member Name' },
      values: [{ Cookie: 'cookie-hidden', passWord: 'password-hidden', safe: 'kept' }],
    };

    logger.info('member.checked', { tenantId: TENANT, correlationId: CORRELATION, context: nested });

    const event = write.mock.calls[0]?.[0];
    expect(event.tenantId).toBe(TENANT);
    expect(event.correlationId).toBe(CORRELATION);
    expect(event.context).toEqual({
      Authorization: REDACTED,
      'access-token': REDACTED,
      refresh_token: REDACTED,
      'service.role-key': REDACTED,
      profile: { E_MAIL: REDACTED, phone_number: REDACTED, 'full-name': REDACTED },
      values: [{ Cookie: REDACTED, passWord: REDACTED, safe: 'kept' }],
    });
  });

  it('HARD-005 preserves JSON-safe structure, replaces cycles, and snapshots input', async () => {
    const { createOperationalLogger } = await import('../../../apps/web/lib/observability');
    const write = vi.fn();
    const logger = createOperationalLogger({ write, now: () => '2026-09-20T00:00:00.000Z' });
    const context: Record<string, unknown> = { safe: { before: true }, list: [1, { value: 'stable' }] };
    context.self = context;

    logger.info('input.checked', { context });
    context.safe = { after: true };
    (context.list as Array<unknown>).push('later');

    const event = write.mock.calls[0]?.[0];
    expect(event.context.self).toBe(CIRCULAR);
    expect(event.context.safe).toEqual({ before: true });
    expect(event.context.list).toEqual([1, { value: 'stable' }]);
    expect(() => JSON.stringify(event)).not.toThrow();
  });

  it('HARD-005 sends identical redacted events to write and report for errors', async () => {
    const { createOperationalLogger } = await import('../../../apps/web/lib/observability');
    const write = vi.fn();
    const report = vi.fn();
    const logger = createOperationalLogger({ write, report, now: () => '2026-09-20T00:00:00.000Z' });

    logger.error('payment.failed', {
      tenantId: TENANT,
      correlationId: CORRELATION,
      message: 'failure',
      context: { apiSecret: 'do-not-leak', amountPaise: 5000 },
    });

    expect(write).toHaveBeenCalledTimes(1);
    expect(report).toHaveBeenCalledTimes(1);
    expect(report.mock.calls[0]?.[0]).toEqual(write.mock.calls[0]?.[0]);
    expect(write.mock.calls[0]?.[0].context).toEqual({ apiSecret: REDACTED, amountPaise: 5000 });
  });

  it('HARD-005 contains adapter failures and never exposes raw input', async () => {
    const { createOperationalLogger } = await import('../../../apps/web/lib/observability');
    const raw = { password: 'never-log-this' };
    const write = vi.fn(() => { throw new Error('sink unavailable'); });
    const report = vi.fn(() => { throw new Error('report unavailable'); });
    const logger = createOperationalLogger({ write, report });

    expect(() => logger.error('adapter.failed', { context: raw })).not.toThrow();
    expect(JSON.stringify(write.mock.calls[0]?.[0])).not.toContain(raw.password);
    expect(JSON.stringify(report.mock.calls[0]?.[0])).not.toContain(raw.password);
  });
});
