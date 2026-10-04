import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// R5: a logical upload retains ONE registration command UUID across unknown
// outcomes. The same actor/key with the same normalized requestId/MIME/bytes
// replays the same registration without minting a fresh identity; a retry
// after a PUT or confirm network failure reuses the original registration key
// and attachment command key; a fresh key is never generated for the same
// logical upload. Authored implementation-blind against the frozen decisions.

const state = vi.hoisted(() => ({ bodies: [] as Array<{ url: string; body: unknown }>, failPut: false, failConfirm: false }));
const id = '72000000-0000-4000-8000-000000000001';
const assetId = '72000000-0000-4000-8000-000000000002';
const proofBytes = () => { const head = new Uint8Array([255, 216, 255, 224, 0, 16, 74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]); const bytes = new Uint8Array(head.length + 980); bytes.set(head); bytes.fill(7, head.length); return bytes; };
const file = () => new File([proofBytes()], 'proof.jpg', { type: 'image/jpeg' });

const jsonResponse = (payload: unknown, status = 200) => new Response(JSON.stringify(payload), { status, headers: { 'content-type': 'application/json' } });
const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
  const url = String(input instanceof Request ? input.url : input);
  const method = (init?.method ?? (input instanceof Request ? input.method : 'GET')).toUpperCase();
  let body: unknown = null;
  if (typeof init?.body === 'string') { try { body = JSON.parse(init.body); } catch { body = init.body; } }
  if (method !== 'PUT') state.bodies.push({ url, body });
  if (method === 'PUT') { if (state.failPut) throw new TypeError('network lost'); return new Response(null, { status: 200 }); }
  if (url.includes('/proof-upload-url')) return jsonResponse({ ok: true, data: { assetId, uploadUrl: `https://upload.test/${id}/staging/payment_proof/${assetId}.jpg` } });
  if (url.includes('/proof-confirm')) { if (state.failConfirm) throw new TypeError('network lost'); return jsonResponse({ ok: true, data: { assetId } }); }
  return jsonResponse({ ok: false, error: { code: 'invalid_request', message: 'unknown route' } }, 400);
});

beforeEach(() => { state.bodies = []; state.failPut = false; state.failConfirm = false; vi.stubGlobal('fetch', fetchMock); fetchMock.mockClear(); });
afterEach(() => { vi.unstubAllGlobals(); });

async function runUpload() {
  const { uploadPaymentProof } = await import('../../lib/media-upload');
  return uploadPaymentProof(file(), id, id, id) as Promise<unknown>;
}

function registrationBodies() {
  return state.bodies.filter(entry => entry.url.includes('/proof-upload-url') && entry.body && typeof entry.body === 'object') as Array<{ url: string; body: Record<string, unknown> }>;
}
function confirmBodies() {
  return state.bodies.filter(entry => entry.url.includes('/proof-confirm') && entry.body && typeof entry.body === 'object') as Array<{ url: string; body: Record<string, unknown> }>;
}
function uuidEntries(body: Record<string, unknown>): Array<[string, string]> {
  return Object.entries(body).filter(([, value]) => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) as Array<[string, string]>;
}

describe('R5 one registration command UUID per logical upload', () => {
  it('a retry after a staging PUT failure reuses the original registration key and facts', async () => {
    state.failPut = true;
    await expect(runUpload()).rejects.toThrow();
    const failed = registrationBodies();
    expect(failed.length).toBe(1);
    state.failPut = false;
    await runUpload();
    const attempts = registrationBodies();
    expect(attempts.length).toBe(2);
    const first = attempts[0];
    const retry = attempts[1];
    if (!first || !retry) throw new Error('both registration attempts must be captured');
    const firstKeys = uuidEntries(first.body);
    // The registration body carries the retained command identity: the retry
    // must repeat every immutable fact, including the same key.
    expect(firstKeys.length, 'the registration body must carry a command identity').toBeGreaterThan(0);
    for (const [key, value] of firstKeys) expect(String(retry.body[key])).toBe(value);
    expect(first.body).toEqual(retry.body);
  });
  it('a retry after a confirm failure replays the same attachment command key', async () => {
    await runUpload();
    state.failConfirm = true;
    await expect(runUpload()).rejects.toThrow();
    state.failConfirm = false;
    await runUpload();
    const confirms = confirmBodies();
    expect(confirms.length).toBeGreaterThanOrEqual(2);
    const firstConfirm = confirms[0];
    const lastConfirm = confirms[confirms.length - 1];
    if (!firstConfirm || !lastConfirm) throw new Error('the confirm attempts must be captured');
    const firstKeys = uuidEntries(firstConfirm.body);
    expect(firstKeys.length, 'the confirm body must carry its attachment command identity').toBeGreaterThan(0);
    for (const [key, value] of firstKeys) expect(String(lastConfirm.body[key])).toBe(value);
    expect(lastConfirm.body).toEqual(firstConfirm.body);
  });
  it('the declared MIME and byte facts are carried with the registration', async () => {
    await runUpload();
    const body = registrationBodies()[0]?.body as Record<string, unknown>;
    expect(JSON.stringify(body)).toMatch(/image\/jpeg/i);
    expect(JSON.stringify(body)).toMatch(/1000/);
  });
});
