import { afterEach, describe, expect, it, vi } from 'vitest';

import { apiFail } from '../api';

describe('apiFail operational errors', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('emits one structured redacted server-error event without changing the response', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const response = apiFail(
      'server_error',
      'raw-operation-code',
      'raw caller message with member@example.com',
      {
        authorization: 'Bearer raw-token',
        email: 'member@example.com',
        secret: 'raw-secret',
        internal: 'raw-details',
      },
    );

    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({
      ok: false,
      error: {
        authorization: 'Bearer raw-token',
        email: 'member@example.com',
        secret: 'raw-secret',
        internal: 'raw-details',
        code: 'raw-operation-code',
        message: 'raw caller message with member@example.com',
      },
    });
    expect(consoleError).toHaveBeenCalledTimes(1);

    const [event] = consoleError.mock.calls[0] ?? [];
    expect(event).toMatchObject({ level: 'error', event: 'api.server_error' });
    expect(typeof event).toBe('object');
    expect(new Date(event.timestamp).toISOString()).toBe(event.timestamp);
    expect(JSON.stringify(event)).not.toContain('raw-operation-code');
    expect(JSON.stringify(event)).not.toContain('raw caller message');
    expect(JSON.stringify(event)).not.toContain('raw-token');
    expect(JSON.stringify(event)).not.toContain('member@example.com');
    expect(JSON.stringify(event)).not.toContain('raw-secret');
    expect(JSON.stringify(event)).not.toContain('raw-details');
  });

  it('does not emit an operational event for non-server failures', () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined);

    const response = apiFail('bad_request', 'invalid_request', 'That request is invalid.');

    expect(response.status).toBe(400);
    expect(consoleError).not.toHaveBeenCalled();
  });

  it('preserves the response when the operational sink throws', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {
      throw new Error('sink failed');
    });

    const response = apiFail('server_error', 'operation_failed', 'Nothing was written.');

    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({
      ok: false,
      error: { code: 'operation_failed', message: 'Nothing was written.' },
    });
  });
});
