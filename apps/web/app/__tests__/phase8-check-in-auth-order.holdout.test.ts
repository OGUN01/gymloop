import { expect, it, vi } from 'vitest';

const identityBoundary = vi.hoisted(() => ({
  readIdentity: vi.fn(),
  readRequestIdentity: vi.fn(),
}));

vi.mock('../../lib/identity-session', () => identityBoundary);

import { POST } from '../api/check-in/route';

it('refuses an unverified bearer before parsing the check-in command', async () => {
  identityBoundary.readRequestIdentity.mockResolvedValue(null);
  const request = new Request('https://gymloop.example/api/check-in', {
    method: 'POST',
    headers: { authorization: 'Bearer unverified' },
  });
  const parseBody = vi.fn().mockRejectedValue(new Error('body must not be read'));
  request.json = parseBody;

  const response = await POST(request as never);

  expect(response.status).toBe(401);
  expect(identityBoundary.readRequestIdentity).toHaveBeenCalledExactlyOnceWith(request);
  expect(parseBody).not.toHaveBeenCalled();
});
