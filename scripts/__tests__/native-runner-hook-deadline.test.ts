import { readFileSync } from 'node:fs';
import { EventEmitter } from 'node:events';
import { isAbsolute } from 'node:path';
import { Script } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it, vi } from 'vitest';
import { NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS, PHASE8_PRELAUNCH_LOAD_LIMITS } from '../../packages/shared/src/config/constants';

// Frozen PUBLIC termination-headroom contract. The implementation is executed
// as opaque runtime data: neither its body nor another author's suite is read.
// Controlled child/time objects launch no actor and wait for no real deadline.
const visibleHookDeadlineSource = readFileSync(new URL('../native-runner-hook.mjs', import.meta.url), 'utf8');
const visibleHookDeadlineExecutable = ts.transpileModule(visibleHookDeadlineSource, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  fileName: 'visible-opaque-hook-runtime.ts',
}).outputText;
const visibleHookDeadlineCases = [
  { name: 'arms one nine-second timer before child startup', event: 'zero', boundary: 'early', expectedExit: 0, expectedKill: false, timerContract: true },
  { name: 'accepts a timely zero just before the active deadline', event: 'zero', boundary: 'last-timely', expectedExit: 0, expectedKill: false },
  { name: 'refuses a nonzero guard exit', event: 'nonzero', boundary: 'early', expectedExit: 1, expectedKill: false },
  { name: 'refuses a null guard exit', event: 'null', boundary: 'early', expectedExit: 1, expectedKill: false },
  { name: 'refuses a signalled zero exit', event: 'signalled-exit', boundary: 'early', expectedExit: 1, expectedKill: false },
  { name: 'refuses a child error without disclosing it', event: 'error', boundary: 'early', expectedExit: 1, expectedKill: false },
  { name: 'terminates only the exact stalled child once and refuses', event: 'timer', boundary: 'deadline', expectedExit: 1, expectedKill: true },
  { name: 'terminates the exact child once on SIGTERM', event: 'SIGTERM', boundary: 'early', expectedExit: 1, expectedKill: true },
  { name: 'terminates the exact child once on SIGINT', event: 'SIGINT', boundary: 'early', expectedExit: 1, expectedKill: true },
  { name: 'refuses zero exactly at the monotonic deadline when the timer is delayed', event: 'zero', boundary: 'deadline', expectedExit: 1, expectedKill: false },
  { name: 'refuses zero after the monotonic deadline when the timer is delayed', event: 'zero', boundary: 'late', expectedExit: 1, expectedKill: false },
  { name: 'counts synchronous child startup time inside the monotonic active bound', event: 'zero', boundary: 'startup-deadline', expectedExit: 1, expectedKill: false },
] as const;

describe('frozen Windows pre-job termination headroom', () => {
  it('centralizes exactly nine active seconds and retains ten-second general stop grace', () => {
    // Expected requirement values, not runtime configuration or a fixture cap.
    expect(Reflect.get(NATIVE_DB_VALIDATION, 'runnerHookActiveTimeoutMs')).toBe(9_000);
    expect(NATIVE_DB_VALIDATION.processStopGraceMs).toBe(10_000);
  });

  it.each(visibleHookDeadlineCases)('$name', (scenario) => {
    const activeBound = NATIVE_DB_VALIDATION.processStopGraceMs - PHASE8_PRELAUNCH_LOAD_LIMITS.millisecondsPerSecond;
    const clockOrigin = NATIVE_DB_VALIDATION.nativeCleanupReserveMs;
    let monotonicNow = clockOrigin;
    const operationOrder: string[] = [];
    const output: string[] = [];
    const errorOutput: string[] = [];
    const exits: number[] = [];
    const terminalParentExit = {};
    let childClosed = false;
    const child = new EventEmitter();
    const unrelatedChild = new EventEmitter();
    const exactChildKill = vi.fn(() => { Object.assign(child, { killed: true }); return true; });
    const unrelatedKill = vi.fn(() => true);
    Object.assign(child, { kill: exactChildKill, killed: false, exitCode: null, signalCode: null });
    Object.assign(unrelatedChild, { kill: unrelatedKill, killed: false, exitCode: null, signalCode: null });
    const timers: Array<{ callback: (...args: unknown[]) => unknown; delay: number; args: unknown[]; token: object }> = [];
    const scheduleTimer = vi.fn((callback: (...args: unknown[]) => unknown, delay: number, ...args: unknown[]) => {
      operationOrder.push('timer');
      const token = { unref: vi.fn() };
      timers.push({ callback, delay, args, token });
      return token;
    });
    const clearTimer = vi.fn();
    const monotonicClock = vi.fn(() => {
      operationOrder.push('monotonic');
      return monotonicNow;
    });
    const spawnChild = vi.fn(() => {
      operationOrder.push('spawn');
      if (scenario.boundary === 'startup-deadline') monotonicNow = clockOrigin + activeBound;
      return child;
    });
    const fakeProcess = Object.assign(new EventEmitter(), {
      argv: ['/native/node', '/visible sealed fixture/hook.mjs', '/visible sealed fixture/guard.mjs', '/visible sealed fixture/binding.json'],
      execPath: '/native/node',
      exitCode: undefined,
      exit: vi.fn((code: number) => { exits.push(code); throw terminalParentExit; }),
      stdout: { write: vi.fn((text: string) => { output.push(text); return true; }) },
      stderr: { write: vi.fn((text: string) => { errorOutput.push(text); return true; }) },
      hrtime: Object.assign(vi.fn((previous?: [number, number]) => {
        const now = monotonicClock();
        let seconds = Math.floor(now / PHASE8_PRELAUNCH_LOAD_LIMITS.millisecondsPerSecond);
        let nanoseconds = (now - seconds * PHASE8_PRELAUNCH_LOAD_LIMITS.millisecondsPerSecond)
          * PHASE8_PRELAUNCH_LOAD_LIMITS.millisecondsPerSecond * PHASE8_PRELAUNCH_LOAD_LIMITS.millisecondsPerSecond;
        if (previous) {
          seconds -= previous[0];
          nanoseconds -= previous[1];
          if (nanoseconds < 0) {
            seconds -= 1;
            nanoseconds += PHASE8_PRELAUNCH_LOAD_LIMITS.millisecondsPerSecond
              * PHASE8_PRELAUNCH_LOAD_LIMITS.millisecondsPerSecond * PHASE8_PRELAUNCH_LOAD_LIMITS.millisecondsPerSecond;
          }
        }
        return [seconds, nanoseconds];
      }), {
        bigint: vi.fn(() => BigInt(monotonicClock())
          * BigInt(PHASE8_PRELAUNCH_LOAD_LIMITS.millisecondsPerSecond)
          * BigInt(PHASE8_PRELAUNCH_LOAD_LIMITS.millisecondsPerSecond)),
      }),
    });
    const runtimeConstants = { NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS, PHASE8_PRELAUNCH_LOAD_LIMITS };
    const runtimePerformance = { now: monotonicClock };
    const moduleRecord = { exports: {} };
    try {
      new Script(visibleHookDeadlineExecutable, { filename: 'visible-opaque-hook-runtime' }).runInNewContext({
        exports: moduleRecord.exports,
        module: moduleRecord,
        process: fakeProcess,
        performance: runtimePerformance,
        // Wall time deliberately does not advance with the controlled monotonic
        // clock. A Date.now substitute cannot pass the delayed-success oracle.
        Date: { now: () => clockOrigin },
        setTimeout: scheduleTimer,
        clearTimeout: clearTimer,
        setInterval: vi.fn(() => { throw new Error('UNDECLARED_VISIBLE_INTERVAL'); }),
        clearInterval: vi.fn(),
        console: {
          log: (...values: unknown[]) => { output.push(values.join(' ') + '\n'); },
          error: (...values: unknown[]) => { errorOutput.push(values.join(' ') + '\n'); },
        },
        require: (specifier: string) => {
          if (specifier === 'node:child_process') return { spawn: spawnChild };
          if (specifier === 'node:path') return { isAbsolute };
          if (specifier === 'node:perf_hooks') return { performance: runtimePerformance };
          if (specifier === 'node:process') return Object.assign(fakeProcess, { default: fakeProcess });
          if (specifier === 'node:timers') return { setTimeout: scheduleTimer, clearTimeout: clearTimer };
          if (specifier.endsWith('/config/constants.ts') || specifier.endsWith('/config/constants.js')) return runtimeConstants;
          throw new Error('UNDECLARED_VISIBLE_RUNTIME_IMPORT');
        },
      });
    } catch (opaqueFailure) {
      const message = typeof opaqueFailure === 'object' && opaqueFailure !== null
        ? Reflect.get(opaqueFailure, 'message') : null;
      const category = typeof message === 'string' && message.includes("Cannot use 'import.meta'")
        ? 'ESM_IMPORT_META_FORMAT'
        : message === 'UNDECLARED_VISIBLE_RUNTIME_IMPORT' ? 'UNDECLARED_RUNTIME_IMPORT'
          : 'UNVERIFIED_RUNTIME_BOUNDARY';
      const exceptionName = typeof opaqueFailure === 'object' && opaqueFailure !== null
        ? Reflect.get(opaqueFailure, 'name') : null;
      const safeExceptionName = ['ReferenceError', 'TypeError', 'SyntaxError', 'Error'].includes(exceptionName)
        ? exceptionName : 'UNKNOWN_EXCEPTION';
      const missingGlobal = typeof message === 'string' ? /^([A-Za-z_$][\w$]*) is not defined$/.exec(message)?.[1] : null;
      const missingMember = typeof message === 'string'
        ? /^Cannot read properties of undefined \(reading '([A-Za-z_$][\w$]*)'\)$/.exec(message)?.[1] : null;
      throw new Error('Opaque hook refused the declared controlled visible runtime boundary: ' + category
        + ' ' + safeExceptionName + ' ' + (missingGlobal ?? missingMember ?? 'UNKNOWN_MEMBER'), { cause: opaqueFailure });
    }

    expect(spawnChild).toHaveBeenCalledTimes(1);
    expect(spawnChild).toHaveBeenCalledWith(fakeProcess.execPath,
      [fakeProcess.argv[2], fakeProcess.argv[3]], expect.objectContaining({ stdio: 'ignore', windowsHide: true, shell: false }));
    expect(scheduleTimer).toHaveBeenCalledTimes(1);
    expect(timers).toHaveLength(1);
    expect(exits).toEqual([]);

    if (scenario.boundary === 'last-timely') monotonicNow = clockOrigin + activeBound - 1;
    if (scenario.boundary === 'deadline') monotonicNow = clockOrigin + activeBound;
    if (scenario.boundary === 'late') monotonicNow = clockOrigin + activeBound + 1;
    try {
      if (scenario.event === 'timer') {
        // Fire the actual one recorded timer. Late-zero scenarios below never
        // invoke this callback, even though monotonic time reached the bound.
        monotonicNow = clockOrigin + timers[0].delay;
        timers[0].callback(...timers[0].args);
      } else if (scenario.event === 'SIGTERM' || scenario.event === 'SIGINT') {
        fakeProcess.emit(scenario.event);
      } else if (scenario.event === 'error') {
        child.emit('error', new Error('VISIBLE_PRIVATE_CHILD_ERROR'));
        childClosed = true;
        child.emit('close', null, null);
      } else {
        const code = scenario.event === 'null' ? null : scenario.event === 'nonzero' ? 1 : 0;
        const signal = scenario.event === 'signalled-exit' ? 'SIGTERM' : null;
        Object.assign(child, { exitCode: code, signalCode: signal });
        // Node emits exit and then close even with ignored child stdio. The
        // frozen CLI may observe either completion boundary.
        child.emit('exit', code, signal);
        childClosed = true;
        child.emit('close', code, signal);
      }
    } catch (termination) {
      if (termination !== terminalParentExit) throw new Error('Unverified visible event boundary failure.', { cause: termination });
    }
    const naturalCode = Reflect.get(fakeProcess, 'exitCode');
    const timerCancelled = clearTimer.mock.calls.some(([token]) => token === timers[0].token);
    const naturalParentClosed = childClosed && timerCancelled
      && (naturalCode === undefined || Number.isInteger(naturalCode));
    const observedExits = exits.length > 0 ? exits : naturalParentClosed ? [naturalCode ?? 0] : [];
    if (scenario.expectedKill) expect(fakeProcess.exit).toHaveBeenCalledTimes(1);

    expect(observedExits).toEqual([scenario.expectedExit]);
    expect(output.join('')).toBe(scenario.expectedExit === 0 ? 'Native runner binding accepted.\n' : '');
    expect(errorOutput.join('')).toBe(scenario.expectedExit === 0 ? '' : 'Native runner binding refused: RUNNER_UNTRUSTED.\n');
    expect(exactChildKill).toHaveBeenCalledTimes(scenario.expectedKill ? 1 : 0);
    expect(unrelatedKill).not.toHaveBeenCalled();
    expect(clearTimer).toHaveBeenCalledTimes(1);
    expect(clearTimer).toHaveBeenCalledWith(timers[0].token);
    if ('timerContract' in scenario) {
      expect(timers[0].delay).toBe(activeBound);
      expect(operationOrder[0]).toBe('monotonic');
    }

    // The parent really exits immediately: future child/signal/timer delivery
    // stops at that terminal boundary. Counts remain exact with no retry,
    // replacement result or termination of an unrelated child.
    expect(observedExits).toEqual([scenario.expectedExit]);
    expect(exactChildKill).toHaveBeenCalledTimes(scenario.expectedKill ? 1 : 0);
    expect(unrelatedKill).not.toHaveBeenCalled();
    expect(scheduleTimer).toHaveBeenCalledTimes(1);
    expect(clearTimer).toHaveBeenCalledTimes(1);
    expect(spawnChild).toHaveBeenCalledTimes(1);
  });
});
