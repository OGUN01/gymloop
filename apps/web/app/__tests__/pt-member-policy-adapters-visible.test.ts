// Independent adapter tests against public frozen declarations; source-blind.
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { loadMemberPtPolicy } from '../../lib/training';
import { loadPtPolicy } from '../../../mobile/lib/training';

const boundary = vi.hoisted(() => ({ read: vi.fn() }));
// Inert Vitest host seam: the actual adapters remain under test. This package's
// server-component sentinel does not execute in the test worker.
vi.mock('server-only', () => ({}));
vi.mock('@gymloop/shared', async (importOriginal) => ({
  ...await importOriginal<Record<string, unknown>>(),
  readMemberPtPolicy: boundary.read,
}));

const adapters = [
  ['web', (caller: unknown) => loadMemberPtPolicy(caller as Parameters<typeof loadMemberPtPolicy>[0])],
  ['native', (caller: unknown) => loadPtPolicy(caller as Parameters<typeof loadPtPolicy>[0])],
] as const;

beforeEach(() => { boundary.read.mockReset(); });

describe.each(adapters)('%s member PT policy adapter', (_platform, load) => {
  it('forwards the supplied authenticated caller unchanged to the narrow shared reader', async () => {
    const caller = { rpc: vi.fn(), from: vi.fn() };
    const result = { data: { cancelWindowHours: 0, lateCancelConsumes: false }, error: null };
    boundary.read.mockResolvedValueOnce(result);
    expect(await load(caller)).toEqual(result);
    expect(boundary.read.mock.calls).toEqual([[caller]]);
    expect(boundary.read.mock.calls[0]?.[0]).toBe(caller);
    expect(caller.rpc).not.toHaveBeenCalled();
    expect(caller.from).not.toHaveBeenCalled();
  });

  it.each([
    ['empty settings', { data: null, error: null }],
    ['sanitized retry', { data: null, error: 'Please try again.' }],
    ['maximum policy', { data: { cancelWindowHours: 168, lateCancelConsumes: true }, error: null }],
  ])('preserves shared %s result without adding a default', async (_label, result) => {
    const caller = { rpc: vi.fn(), from: vi.fn() };
    boundary.read.mockResolvedValueOnce(result);
    expect(await load(caller)).toEqual(result);
    expect(boundary.read.mock.calls).toEqual([[caller]]);
    expect(caller.from).not.toHaveBeenCalled();
    expect(caller.rpc).not.toHaveBeenCalled();
  });

  it('forwards each current caller on every read with no cached prior tenant policy', async () => {
    const first = { rpc: vi.fn(), from: vi.fn(), marker: 'first caller' };
    const second = { rpc: vi.fn(), from: vi.fn(), marker: 'second caller' };
    const firstPolicy = { data: { cancelWindowHours: 8, lateCancelConsumes: true }, error: null };
    const nextPolicy = { data: { cancelWindowHours: 47, lateCancelConsumes: false }, error: null };
    boundary.read.mockResolvedValueOnce(firstPolicy).mockResolvedValueOnce(nextPolicy);
    expect(await load(first)).toEqual(firstPolicy);
    expect(await load(second)).toEqual(nextPolicy);
    expect(boundary.read.mock.calls).toEqual([[first], [second]]);
    expect(boundary.read.mock.calls[0]?.[0]).toBe(first);
    expect(boundary.read.mock.calls[1]?.[0]).toBe(second);
    expect(first.from).not.toHaveBeenCalled();
    expect(second.from).not.toHaveBeenCalled();
  });

  it('awaits the shared caller read rather than exposing policy before it resolves', async () => {
    const caller = { rpc: vi.fn(), from: vi.fn() };
    let resolveRead!: (result: { data: null; error: null }) => void;
    boundary.read.mockReturnValueOnce(new Promise((resolve) => { resolveRead = resolve; }));
    let settled = false;
    const pending = load(caller).then((result) => { settled = true; return result; });
    await Promise.resolve();
    expect(settled).toBe(false);
    expect(boundary.read.mock.calls).toEqual([[caller]]);
    resolveRead({ data: null, error: null });
    expect(await pending).toEqual({ data: null, error: null });
  });
});
