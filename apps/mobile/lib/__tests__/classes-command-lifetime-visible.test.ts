import { beforeEach, describe, expect, it, vi } from 'vitest';
import { bookClass, cancelClassBooking, deskBookClass, deskCancelClassBooking, markClassAttendance } from '../classes';
import type { ApiClient } from '@gymloop/api-client';

const network = vi.hoisted(() => ({ probe: vi.fn() }));
vi.mock('expo-network', () => ({ getNetworkStateAsync: network.probe }));
const id = '74000000-0000-4000-8000-000000000001';
const memberId = '74000000-0000-4000-8000-000000000013';
const commands = [
  { name: 'bookClass', helper: bookClass, args: [id] },
  { name: 'cancelClassBooking', helper: cancelClassBooking, args: [id] },
  { name: 'deskBookClass', helper: deskBookClass, args: [id, memberId] },
  { name: 'deskCancelClassBooking', helper: deskCancelClassBooking, args: [id, 'Member requested'] },
  { name: 'markClassAttendance', helper: markClassAttendance, args: [id, 'attended'] },
];
const post = vi.fn();
const api: ApiClient = { post, checkIn: vi.fn() };
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(yes => { resolve = yes; }); return { promise, resolve }; }
function run(helper: unknown, args: unknown[], guard: () => boolean): Promise<unknown> {
  if (typeof helper !== 'function') throw new Error('Public command helper must be callable');
  return Promise.resolve(Reflect.apply(helper, undefined, [api, ...args, guard]));
}
beforeEach(() => { vi.clearAllMocks(); network.probe.mockResolvedValue({ isConnected: true, isInternetReachable: true }); post.mockResolvedValue({ ok: true, data: { bookingId: id, status: 'booked', spotsLeft: 3 } }); });
describe('CLS actual native command continuation guards', () => {
  it.each(commands)('$name refuses a permanently false lease before any command', async ({ helper, args }) => {
    const outcome = await run(helper, args, () => false).catch(() => null);
    expect(post, 'false lease produces no post').not.toHaveBeenCalled();
    expect(outcome, 'false lease produces no successful outcome').not.toMatchObject({ ok: true });
  });
  it.each(commands)('$name rechecks a lease revoked during the awaited network probe', async ({ helper, args }) => {
    const waiting = deferred<{ isConnected: boolean; isInternetReachable: boolean }>(); network.probe.mockReturnValue(waiting.promise);
    let current = true;
    const pending = run(helper, args, () => current).catch(() => null);
    await Promise.resolve(); expect(network.probe, 'online preflight was reached').toHaveBeenCalledTimes(1);
    current = false; waiting.resolve({ isConnected: true, isInternetReachable: true });
    const outcome = await pending;
    expect(post, 'revoked lease suppresses post after preflight').not.toHaveBeenCalled();
    expect(outcome, 'revoked continuation cannot report success').not.toMatchObject({ ok: true });
  });
  it.each(commands)('$name treats a throwing guard as refusal', async ({ helper, args }) => {
    const outcome = await run(helper, args, () => { throw new Error('Revoked fixture lease'); }).catch(() => null);
    expect(post, 'throwing presentation guard never posts').not.toHaveBeenCalled();
    expect(outcome, 'throwing guard cannot authorize success').not.toMatchObject({ ok: true });
  });
});
