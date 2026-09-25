import { describe, expect, it, vi } from 'vitest';

vi.mock('expo-secure-store', () => ({}));

import { createReplayCoordinator, shouldReplayOnSignal } from '../offline-check-in';

const ONLINE_FOREGROUND = { connected: true, foreground: true };
const OFFLINE_FOREGROUND = { connected: false, foreground: true };
const ONLINE_BACKGROUND = { connected: true, foreground: false };
const OFFLINE_BACKGROUND = { connected: false, foreground: false };

const flush = async () => {
  await new Promise((resolve) => { setTimeout(resolve, 0); });
  await new Promise((resolve) => { setTimeout(resolve, 0); });
};

describe('offline check-in replay signals', () => {
  it('replays when connectivity is regained while the app is in the foreground', () => {
    expect(shouldReplayOnSignal(OFFLINE_FOREGROUND, ONLINE_FOREGROUND)).toBe(true);
    expect(shouldReplayOnSignal(OFFLINE_BACKGROUND, ONLINE_FOREGROUND)).toBe(true);
  });

  it('replays when the app returns to the foreground while connected', () => {
    expect(shouldReplayOnSignal(ONLINE_BACKGROUND, ONLINE_FOREGROUND)).toBe(true);
    expect(shouldReplayOnSignal(OFFLINE_BACKGROUND, OFFLINE_FOREGROUND)).toBe(false);
  });

  it('treats an unknown prior signal as not ready, so the first ready signal counts as entering ready', () => {
    expect(shouldReplayOnSignal(null, ONLINE_FOREGROUND)).toBe(true);
    expect(shouldReplayOnSignal(null, OFFLINE_FOREGROUND)).toBe(false);
    expect(shouldReplayOnSignal(null, ONLINE_BACKGROUND)).toBe(false);
    expect(shouldReplayOnSignal(null, OFFLINE_BACKGROUND)).toBe(false);
  });

  it('does not replay while staying ready or while staying not ready', () => {
    expect(shouldReplayOnSignal(ONLINE_FOREGROUND, ONLINE_FOREGROUND)).toBe(false);
    expect(shouldReplayOnSignal(OFFLINE_FOREGROUND, OFFLINE_FOREGROUND)).toBe(false);
    expect(shouldReplayOnSignal(ONLINE_BACKGROUND, ONLINE_BACKGROUND)).toBe(false);
    expect(shouldReplayOnSignal(OFFLINE_BACKGROUND, OFFLINE_BACKGROUND)).toBe(false);
  });

  it('defers a reconnect that arrives while the app is backgrounded until the app is active again', () => {
    expect(shouldReplayOnSignal(OFFLINE_BACKGROUND, ONLINE_BACKGROUND)).toBe(false);
    expect(shouldReplayOnSignal(ONLINE_BACKGROUND, ONLINE_FOREGROUND)).toBe(true);
  });

  it('does not replay when the app leaves the foreground or the network drops', () => {
    expect(shouldReplayOnSignal(ONLINE_FOREGROUND, ONLINE_BACKGROUND)).toBe(false);
    expect(shouldReplayOnSignal(ONLINE_FOREGROUND, OFFLINE_FOREGROUND)).toBe(false);
    expect(shouldReplayOnSignal(ONLINE_FOREGROUND, OFFLINE_BACKGROUND)).toBe(false);
  });
});

describe('offline check-in replay coordinator', () => {
  it('runs one replay at a time and coalesces requests during a run into one trailing replay', async () => {
    const runs: number[] = [];
    let releaseFirst: () => void = () => undefined;
    const coordinator = createReplayCoordinator(async () => {
      runs.push(runs.length + 1);
      if (runs.length === 1) await new Promise<void>((resolve) => { releaseFirst = resolve; });
    });
    coordinator.requestReplay();
    await flush();
    coordinator.requestReplay();
    coordinator.requestReplay();
    coordinator.requestReplay();
    expect(runs).toEqual([1]);
    releaseFirst();
    await flush();
    expect(runs).toEqual([1, 2]);
  });

  it('runs again for a request made after a completed replay', async () => {
    const runs: number[] = [];
    const coordinator = createReplayCoordinator(async () => { runs.push(runs.length + 1); });
    coordinator.requestReplay();
    await flush();
    coordinator.requestReplay();
    await flush();
    expect(runs).toEqual([1, 2]);
  });

  it('keeps accepting replays after one replay fails', async () => {
    const attempts: number[] = [];
    const coordinator = createReplayCoordinator(async () => {
      attempts.push(attempts.length + 1);
      if (attempts.length === 1) throw new Error('transient');
    });
    coordinator.requestReplay();
    await flush();
    expect(attempts).toEqual([1]);
    coordinator.requestReplay();
    await flush();
    expect(attempts).toEqual([1, 2]);
  });
});
