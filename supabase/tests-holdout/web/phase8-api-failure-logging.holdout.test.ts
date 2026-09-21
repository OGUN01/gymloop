import { afterEach, describe, expect, it, vi } from 'vitest';

import { apiFail } from '../../../apps/web/lib/api';

const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u;
const SECRET_VALUE = 'holdout-secret-value';
const PERSONAL_VALUE = 'holdout-person@example.test';

describe('HARD-005 api failure logging holdout', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('logs one sanitized structured server-error event while preserving the failure response', async () => {
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => undefined);

    const response = apiFail('server_error', 'HARD005_INTERNAL', SECRET_VALUE, {
      email: PERSONAL_VALUE,
      nested: { token: SECRET_VALUE },
    });

    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({
      ok: false,
      error: {
        code: 'HARD005_INTERNAL',
        message: SECRET_VALUE,
        email: PERSONAL_VALUE,
        nested: { token: SECRET_VALUE },
      },
    });
    expect(errorSpy).toHaveBeenCalledTimes(1);

    const [event] = errorSpy.mock.calls[0] ?? [];
    expect(errorSpy.mock.calls[0]).toHaveLength(1);
    expect(event).toMatchObject({
      event: 'api.server_error',
      level: 'error',
    });
    expect(event).toHaveProperty('timestamp');
    expect((event as { timestamp: unknown }).timestamp).toMatch(ISO_TIMESTAMP);
    expect(JSON.stringify(event)).not.toContain(SECRET_VALUE);
    expect(JSON.stringify(event)).not.toContain(PERSONAL_VALUE);
  });

  it('does not log ordinary API failures', () => {
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => undefined);

    apiFail('bad_request', 'HARD005_BAD_REQUEST', SECRET_VALUE, {
      email: PERSONAL_VALUE,
    });

    expect(errorSpy).not.toHaveBeenCalled();
  });

  it('keeps the API response available when the local log sink throws', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {
      throw new Error('local sink unavailable');
    });

    const response = apiFail('server_error', 'HARD005_SINK', SECRET_VALUE, {
      email: PERSONAL_VALUE,
    });

    expect(response.status).toBe(500);
    expect(await response.json()).toEqual({
      ok: false,
      error: {
        code: 'HARD005_SINK',
        message: SECRET_VALUE,
        email: PERSONAL_VALUE,
      },
    });
  });
});
