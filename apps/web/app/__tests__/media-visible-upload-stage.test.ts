import { afterEach, describe, expect, it, vi } from 'vitest';

type Stage = 'uploading' | 'verifying';
type Observer = (stage: Stage) => void;
type Upload = (file: File, kind: 'product', observer?: Observer) => Promise<{ assetId: string }>;
type ProductUpload = (file: File, observer?: Observer) => Promise<{ assetId: string }>;
const assetId = '72000000-0000-4000-8000-000000000011';
const photo = () => new File([new Uint8Array([255, 216, 255])], 'photo.jpg', { type: 'image/jpeg' });
const confirmed = () => Response.json({ ok: true, data: { assetId, confirmed: true } });
const refused = () => Response.json({ ok: false, error: { code: 'upload_changed', message: 'The photo changed while it was being checked. Choose it again and retry.' } }, { status: 409 });
function transport(events: string[], failure?: 'registration' | 'put' | 'confirm') {
  const requests: Array<{ path: string; method: string; headers: string[][]; body: unknown }> = [];
  vi.stubGlobal('fetch', async (input: RequestInfo | URL, init?: RequestInit) => {
    const request = new Request(new URL(String(input), 'https://gym.example'), init);
    const path = new URL(request.url).pathname;
    const body = request.method === 'PUT' ? Array.from(new Uint8Array(await request.arrayBuffer())) : await request.json();
    requests.push({ path, method: request.method, headers: Array.from(request.headers.entries()), body });
    if (path === '/api/media/upload-url') {
      events.push('registration');
      if (failure === 'registration') return refused();
      return Response.json({ ok: true, data: { assetId, uploadUrl: 'https://upload.test/staging/photo.jpg', headers: { 'content-type': 'image/jpeg' }, expiresAt: '2099-01-01T00:00:00Z' } });
    }
    if (request.method === 'PUT') {
      events.push('put');
      if (failure === 'put') return new Response(null, { status: 500 });
      events.push('put-success');
      return new Response(null, { status: 200 });
    }
    if (path === '/api/media/confirm') { events.push('confirm'); return failure === 'confirm' ? refused() : confirmed(); }
    throw new Error('Unexpected upload operation');
  });
  return requests;
}
async function helper(): Promise<Upload> { return (await import('../../lib/media-upload')).uploadMediaFile; }
afterEach(() => { vi.unstubAllGlobals(); vi.doUnmock('../../lib/media-upload'); vi.resetModules(); });

describe('MEDIA additive upload-stage observer public contract', () => {
  it('reports uploading before registration and verifying after successful PUT before confirmation', async () => {
    const events: string[] = []; transport(events);
    const upload = await helper();
    expect(await upload(photo(), 'product', stage => events.push(stage))).toEqual({ assetId });
    expect(events).toEqual(['uploading', 'registration', 'put', 'put-success', 'verifying', 'confirm']);
  });
  it.each([['empty', 'image/jpeg', 0], ['oversized', 'image/jpeg', 2097153], ['SVG', 'image/svg+xml', 3], ['GIF', 'image/gif', 3], ['HEIC', 'image/heic', 3]] as const)('%s preflight emits no stages or requests', async (_name, mime, bytes) => {
    const events: string[] = []; const requests = transport(events); const upload = await helper();
    await expect(upload(new File([new Uint8Array(bytes)], 'photo', { type: mime }), 'product', stage => events.push(stage))).rejects.toThrow();
    expect(events).toEqual([]); expect(requests).toEqual([]);
  });
  it.each(['registration', 'put'] as const)('%s failure never reports verifying or confirms', async failure => {
    const events: string[] = []; transport(events, failure); const upload = await helper();
    await expect(upload(photo(), 'product', stage => events.push(stage))).rejects.toThrow();
    expect(events).toEqual(failure === 'registration' ? ['uploading', 'registration'] : ['uploading', 'registration', 'put']);
  });
  it('confirmation failure retains the trusted error and cannot return an asset result', async () => {
    const events: string[] = []; transport(events, 'confirm'); const upload = await helper();
    await expect(upload(photo(), 'product', stage => events.push(stage))).rejects.toThrow('The photo changed while it was being checked. Choose it again and retry.');
    expect(events).toEqual(['uploading', 'registration', 'put', 'put-success', 'verifying', 'confirm']);
  });
  it.each([false, true])('observer preserves the no-observer request protocol even when it throws=%s', async throws => {
    const upload = await helper(); const originalEvents: string[] = []; const originalRequests = transport(originalEvents);
    const original = await upload(photo(), 'product');
    const events: string[] = []; const requests = transport(events);
    const observed = await upload(photo(), 'product', stage => { events.push(stage); if (throws) throw new Error('Display observer failed'); });
    expect(observed).toEqual(original); expect(requests).toEqual(originalRequests);
    expect(events).toEqual(['uploading', 'registration', 'put', 'put-success', 'verifying', 'confirm']);
    expect(requests.map(request => [request.path, request.method])).toEqual([['/api/media/upload-url', 'POST'], ['/staging/photo.jpg', 'PUT'], ['/api/media/confirm', 'POST']]);
    expect(requests[0]?.body).toEqual({ kind: 'product', mime: 'image/jpeg', bytes: 3 });
    expect(requests[1]?.headers).toEqual([['content-type', 'image/jpeg']]);
    expect(requests[1]?.body).toEqual([255, 216, 255]);
    expect(requests[2]?.body).toEqual({ assetId });
  });
  it('a throwing observer cannot replace a trusted confirmation failure', async () => {
    const events: string[] = []; transport(events, 'confirm'); const upload = await helper();
    await expect(upload(photo(), 'product', stage => { events.push(stage); throw new Error('Display observer failed'); })).rejects.toThrow('The photo changed while it was being checked. Choose it again and retry.');
    expect(events).toEqual(['uploading', 'registration', 'put', 'put-success', 'verifying', 'confirm']);
  });
  it.each([false, true])('product wrapper delegates exactly once with the identical optional observer present=%s', async present => {
    const uploadMediaFile = vi.fn(async () => ({ assetId }));
    vi.doMock('../../lib/media-upload', () => ({ uploadMediaFile }));
    const uploadProductImage: ProductUpload = (await import('../(console)/shop/image-upload')).uploadProductImage;
    const file = photo(); const observer = present ? vi.fn<Observer>() : undefined;
    expect(await uploadProductImage(file, observer)).toEqual({ assetId });
    expect(uploadMediaFile).toHaveBeenCalledTimes(1);
    if (present) expect(uploadMediaFile).toHaveBeenCalledWith(file, 'product', observer);
    else expect(uploadMediaFile.mock.calls[0]?.slice(0, 2)).toEqual([file, 'product']);
    if (observer) expect(observer).not.toHaveBeenCalled();
  });
});
