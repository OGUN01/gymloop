import { afterEach, describe, expect, it, vi } from 'vitest';
const id = '72000000-0000-4000-8000-000000000001';
afterEach(() => vi.unstubAllGlobals());
describe('SHP approved browser upload helper', () => {
  it.each([['oversized', 'image/jpeg', 2097153], ['SVG', 'image/svg+xml', 12], ['GIF', 'image/gif', 12], ['HEIC', 'image/heic', 12]] as const)('refuses %s before initiating upload', async (_name, mime, size) => {
    const fetch = vi.fn(); vi.stubGlobal('fetch', fetch); const { uploadProductImage } = await import('../(console)/shop/image-upload'); await expect(uploadProductImage(new File([new Uint8Array(size)], 'photo', { type: mime }))).rejects.toThrow(); expect(fetch).not.toHaveBeenCalled();
  });
  it('sends only approved CORS header on staging PUT and waits for trusted confirmation', async () => {
    const calls: Array<{ path: string; method: string; headers: Headers; body: unknown }> = [];
    vi.stubGlobal('fetch', async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = new Request(new URL(String(input), 'https://gym.example'), init); const path = new URL(request.url).pathname; const body = request.method === 'PUT' ? await request.arrayBuffer() : await request.json(); calls.push({ path, method: request.method, headers: request.headers, body });
      if (path === '/api/media/upload-url') return Response.json({ ok: true, data: { assetId: id, uploadUrl: 'https://upload.test/staging/photo.jpg', headers: { 'content-type': 'image/jpeg' }, expiresAt: '2099-01-01T00:00:00Z' } });
      if (request.method === 'PUT') return new Response(null, { status: 200 });
      if (path === '/api/media/confirm') return Response.json({ ok: true, data: { assetId: id, confirmed: true } });
      throw new Error('Unexpected upload operation');
    });
    const { uploadProductImage } = await import('../(console)/shop/image-upload'); expect(await uploadProductImage(new File([new Uint8Array([255,216,255,0,0,0,0,0,0,0,0,0])], 'photo.jpg', { type: 'image/jpeg' }))).toEqual({ assetId: id });
    expect(calls.map(call => [call.path, call.method])).toEqual([['/api/media/upload-url', 'POST'], ['/staging/photo.jpg', 'PUT'], ['/api/media/confirm', 'POST']]);
    const [registration, upload, confirmation] = calls;
    if (!registration || !upload || !confirmation) throw new Error('All three observed upload operations are required');
    expect(registration.body).toEqual({ kind: 'product', mime: 'image/jpeg', bytes: 12 }); expect([...upload.headers.keys()]).toEqual(['content-type']); expect(confirmation.body).toEqual({ assetId: id });
  });
  it('trusted confirmation failure rejects rather than returning an asset success', async () => {
    vi.stubGlobal('fetch', async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = new Request(new URL(String(input), 'https://gym.example'), init); const path = new URL(request.url).pathname;
      if (path === '/api/media/upload-url') return Response.json({ ok: true, data: { assetId: id, uploadUrl: 'https://upload.test/staging/photo.jpg', headers: { 'content-type': 'image/jpeg' }, expiresAt: '2099-01-01T00:00:00Z' } });
      if (request.method === 'PUT') return new Response(null, { status: 200 });
      return Response.json({ ok: false, error: { code: 'upload_changed', message: 'The photo changed while it was being checked. Choose it again and retry.' } }, { status: 409 });
    });
    const { uploadProductImage } = await import('../(console)/shop/image-upload'); await expect(uploadProductImage(new File([new Uint8Array([255,216,255])], 'photo.jpg', { type: 'image/jpeg' }))).rejects.toThrow();
  });
});
