import { EventEmitter } from 'node:events';
import { readFileSync } from 'node:fs';
import { isAbsolute, resolve } from 'node:path';
import { runInNewContext } from 'node:vm';
import { describe, expect, it, vi } from 'vitest';
import { MEDIA_RUNTIME_LIMITS, NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS } from '../../packages/shared/src/config/constants';

describe('held pre-job active deadline and delayed admission', () => {
  it('reserves one second in a separate central active deadline', () => {
    const active = NATIVE_DB_VALIDATION.processStopGraceMs - MEDIA_RUNTIME_LIMITS.millisecondsPerSecond;
    expect(Reflect.get(NATIVE_DB_VALIDATION, 'runnerHookActiveTimeoutMs')).toBe(active);
    expect(active < NATIVE_DB_VALIDATION.processStopGraceMs).toBe(true);
  });

  it.each([
    'timer-active-only',
    'timely-zero',
    'zero-at-active',
    'zero-after-active',
    'wall-clock-rollback-late-zero',
    'timely-nonzero',
    'timely-child-signal',
    'hook-signal',
    'stalled-child',
    'queued-zero-after-timeout',
    'child-startup-error',
  ])('keeps controlled admission and termination: %s', (scenario) => {
    const second = MEDIA_RUNTIME_LIMITS.millisecondsPerSecond;
    const general = NATIVE_DB_VALIDATION.processStopGraceMs;
    const active = general - second;
    const initialMonotonicMs = general;
    let monotonicMs = initialMonotonicMs;
    let wallMs = general;
    const exits: number[] = [];
    const writes: string[] = [];
    let controlledChildClosed = false;
    const timers: Array<{
      callback: () => void;
      delay: number;
      handle: { unref: () => void };
      cleared: boolean;
    }> = [];
    const child = Object.assign(new EventEmitter(), {
      pid: 1,
      stdout: Object.assign(new EventEmitter(), { resume: vi.fn() }),
      stderr: Object.assign(new EventEmitter(), { resume: vi.fn() }),
      kill: vi.fn(() => true),
      unref: vi.fn(),
    });
    const spawn = vi.fn(() => {
      monotonicMs += second;
      wallMs += second;
      return child;
    });
    child.on('close', () => { controlledChildClosed = true; });
    const monotonic = {
      now: vi.fn(() => monotonicMs),
    };
    const facade = Object.assign(new EventEmitter(), {
      argv: [
        'C:/Program Files/nodejs/node.exe',
        resolve('controlled-hook.mjs'),
        resolve('controlled-guard.mjs'),
        resolve('controlled-binding.json'),
      ],
      execPath: 'C:/Program Files/nodejs/node.exe',
      stdout: { write: vi.fn((chunk: unknown, encodingOrCallback?: unknown, callback?: unknown) => {
        writes.push(String(chunk));
        const completed = typeof encodingOrCallback === 'function' ? encodingOrCallback : callback;
        if (typeof completed === 'function') completed();
        return true;
      }) },
      stderr: { write: vi.fn((chunk: unknown, encodingOrCallback?: unknown, callback?: unknown) => {
        writes.push(String(chunk));
        const completed = typeof encodingOrCallback === 'function' ? encodingOrCallback : callback;
        if (typeof completed === 'function') completed();
        return true;
      }) },
      exit: vi.fn((code: number) => { exits.push(code); }),
      kill: vi.fn(() => { throw new Error('controlled-unowned-stop-denied'); }),
      hrtime: Object.assign(vi.fn((previous?: [number, number]) => {
        const now: [number, number] = [
          Math.floor(monotonicMs / second),
          (monotonicMs % second) * second * second,
        ];
        if (!previous) return now;
        const elapsed = monotonicMs - previous[0] * second - previous[1] / second / second;
        return [Math.floor(elapsed / second), (elapsed % second) * second * second];
      }), {
        bigint: vi.fn(() => BigInt(monotonicMs) * BigInt(second) * BigInt(second)),
      }),
    });
    const opaqueSource = readFileSync(new URL('../../scripts/native-runner-hook.mjs', import.meta.url), 'utf8');
    const isolatedSource = opaqueSource.replace(
      /^[\t ]*import\s+[\s\S]*?from[\t ]*['"][^'"]+['"][\t ]*;?[\t ]*(?:\r?\n|$)/gmu,
      '',
    );
    runInNewContext(isolatedSource, {
      spawn,
      isAbsolute,
      NATIVE_DB_VALIDATION,
      PHASE8_BACKUP_LIMITS,
      performance: monotonic,
      hrtime: facade.hrtime,
      process: facade,
      Date: { now: vi.fn(() => wallMs) },
      console: {
        log: vi.fn((...chunks: unknown[]) => { writes.push(chunks.map(String).join(' ')); }),
        error: vi.fn((...chunks: unknown[]) => { writes.push(chunks.map(String).join(' ')); }),
      },
      setTimeout: vi.fn((callback: () => void, delay: number) => {
        const handle = { unref: vi.fn() };
        timers.push({ callback, delay, handle, cleared: false });
        return handle;
      }),
      clearTimeout: vi.fn((handle: unknown) => {
        const timer = timers.find((candidate) => candidate.handle === handle);
        if (timer) timer.cleared = true;
      }),
    }, { filename: 'controlled-hook-runtime.mjs' });

    expect(spawn.mock.calls.length).toBe(1);
    expect(timers.length).toBe(1);
    expect(exits.length).toBe(0);
    child.stdout.emit('data', 'controlled-private-output');
    child.stderr.emit('data', 'controlled-private-output');

    if (scenario === 'timer-active-only') {
      expect(timers[0].delay).toBe(active);
      expect(child.kill.mock.calls.length).toBe(0);
      return;
    }

    let elapsed = second;
    if (scenario === 'timely-zero') elapsed = active - second;
    if (scenario === 'zero-at-active' || scenario === 'stalled-child' || scenario === 'queued-zero-after-timeout') elapsed = active;
    if (scenario === 'zero-after-active') elapsed = general;
    if (scenario === 'wall-clock-rollback-late-zero') elapsed = active + 1;
    monotonicMs = initialMonotonicMs + elapsed;
    wallMs = initialMonotonicMs + elapsed;
    if (scenario === 'wall-clock-rollback-late-zero') wallMs = initialMonotonicMs - general;

    if (scenario === 'hook-signal') {
      facade.emit('SIGTERM');
    } else if (scenario === 'stalled-child' || scenario === 'queued-zero-after-timeout') {
      timers[0].callback();
      if (scenario === 'queued-zero-after-timeout') {
        child.emit('exit', 0, null);
        child.emit('close', 0, null);
      }
    } else if (scenario === 'child-startup-error') {
      child.emit('error', new Error('controlled-private-output'));
      child.emit('close', 1, null);
    } else if (scenario === 'timely-nonzero') {
      child.emit('exit', 1, null);
      child.emit('close', 1, null);
    } else if (scenario === 'timely-child-signal') {
      child.emit('exit', 0, 'SIGTERM');
      child.emit('close', 0, 'SIGTERM');
    } else {
      child.emit('exit', 0, null);
      child.emit('close', 0, null);
    }

    const terminatesChild = scenario === 'hook-signal'
      || scenario === 'stalled-child'
      || scenario === 'queued-zero-after-timeout';
    if (!terminatesChild && exits.length === 0 && controlledChildClosed && timers[0].cleared && Reflect.has(facade, 'exitCode')) {
      exits.push(Number(Reflect.get(facade, 'exitCode')));
    }
    expect(exits.length).toBe(1);
    expect(exits[0] === 0).toBe(scenario === 'timely-zero');
    expect(spawn.mock.calls.length).toBe(1);
    expect(timers.length).toBe(1);
    expect(facade.kill.mock.calls.length).toBe(0);
    expect(child.kill.mock.calls.length).toBe(terminatesChild ? 1 : 0);
    expect(writes.length > 0).toBe(true);
    expect(writes.every((write) => !write.includes('controlled-private-output'))).toBe(true);
    expect(timers[0].cleared).toBe(true);
  });
});
