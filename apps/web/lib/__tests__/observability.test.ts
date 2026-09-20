import { describe, expect, it, vi } from 'vitest';

import { createOperationalLogger } from '../observability';

const timestamp = '2026-09-20T12:34:56.000Z';

describe('createOperationalLogger', () => {
  it('writes one structured, recursively redacted event with permitted context', () => {
    const write = vi.fn();
    const logger = createOperationalLogger({ write, now: () => timestamp });
    const circular: Record<string, unknown> = { safe: 'kept' };
    circular.self = circular;

    logger.info('member.checked_in', {
      tenantId: 'tenant-1',
      correlationId: 'corr-1',
      message: 'member arrived',
      context: {
        authorization: 'Bearer raw-token',
        nested: {
          cookie: 'session=raw-cookie',
          password: 'raw-password',
          access_token: 'raw-access',
          refresh_token: 'raw-refresh',
          apiKey: 'raw-api-key',
          service_role: 'raw-service-role',
          secret: 'raw-secret',
          email: 'member@example.com',
          phone: '+919999999999',
          full_name: 'Member Name',
          safe: 'kept',
          circular,
        },
      },
    });

    expect(write).toHaveBeenCalledTimes(1);
    expect(write).toHaveBeenCalledWith({
      level: 'info',
      event: 'member.checked_in',
      timestamp,
      tenant_id: 'tenant-1',
      correlation_id: 'corr-1',
      message: 'member arrived',
      context: {
        authorization: '[REDACTED]',
        nested: {
          cookie: '[REDACTED]',
          password: '[REDACTED]',
          access_token: '[REDACTED]',
          refresh_token: '[REDACTED]',
          apiKey: '[REDACTED]',
          service_role: '[REDACTED]',
          secret: '[REDACTED]',
          email: '[REDACTED]',
          phone: '[REDACTED]',
          full_name: '[REDACTED]',
          safe: 'kept',
          circular: { safe: 'kept', self: '[Circular]' },
        },
      },
    });
  });

  it('sends the identical redacted error to the sink and report adapter', () => {
    const write = vi.fn();
    const report = vi.fn();
    const logger = createOperationalLogger({ write, report, now: () => timestamp });

    logger.error('payment.failed', {
      tenantId: 'tenant-2',
      correlationId: 'corr-2',
      message: 'payment failed',
      context: { api_key: 'raw-api-key', memberEmail: 'raw-email', attempt: 2 },
    });

    expect(write).toHaveBeenCalledTimes(1);
    expect(report).toHaveBeenCalledTimes(1);
    expect(report).toHaveBeenCalledWith(write.mock.calls[0][0]);
    expect(write.mock.calls[0][0]).toEqual({
      level: 'error',
      event: 'payment.failed',
      timestamp,
      tenant_id: 'tenant-2',
      correlation_id: 'corr-2',
      message: 'payment failed',
      context: { api_key: '[REDACTED]', memberEmail: '[REDACTED]', attempt: 2 },
    });
  });

  it('swallows sink and report failures without leaking raw input', () => {
    const write = vi.fn(() => { throw new Error('sink failed: raw-secret'); });
    const report = vi.fn(() => { throw new Error('report failed: raw-secret'); });
    const logger = createOperationalLogger({ write, report, now: () => timestamp });

    expect(() => logger.error('security.alert', {
      context: { secret: 'raw-secret', password: 'raw-password' },
    })).not.toThrow();
    expect(write.mock.calls[0][0]).not.toHaveProperty('context.secret', 'raw-secret');
    expect(write.mock.calls[0][0]).not.toHaveProperty('context.password', 'raw-password');
  });
});
