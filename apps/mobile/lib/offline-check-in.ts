import * as SecureStore from 'expo-secure-store';
import type { ApiClient, ApiEnvelope, CheckInResult } from '@gymloop/api-client';

const OFFLINE_QUEUE_KEY = 'gymloop.offline-check-in';
export type OfflineCheckInCommand = { clientEventId: string; token: string; offlineRecordedAt: string; memberId: string; tenantId: string; userId: string };
export type OfflineCheckInOutcome = { command: OfflineCheckInCommand; result: ApiEnvelope<CheckInResult> | null };
type OfflineCheckInScope = Pick<OfflineCheckInCommand, 'tenantId' | 'userId' | 'memberId'>;
type QueueRecoveryIdentity = ({ kind: 'member' } & OfflineCheckInScope) | null;

let queueTail = Promise.resolve();

async function serialized<T>(work: () => Promise<T>): Promise<T> {
  let release: () => void = () => undefined;
  const previous = queueTail;
  queueTail = new Promise<void>((resolve) => { release = () => resolve(); });
  await previous;
  try { return await work(); } finally { release(); }
}

function isCommand(value: unknown): value is OfflineCheckInCommand {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
  const command = value as Record<string, unknown>;
  return ['clientEventId', 'token', 'offlineRecordedAt', 'memberId', 'tenantId', 'userId']
    .every((key) => typeof command[key] === 'string' && command[key] !== '');
}

async function readQueue(): Promise<OfflineCheckInCommand[]> {
  const saved = await SecureStore.getItemAsync(OFFLINE_QUEUE_KEY);
  if (saved === null) return [];
  try {
    const parsed: unknown = JSON.parse(saved);
    if (!Array.isArray(parsed) || !parsed.every(isCommand)) throw new Error('invalid queue');
    return parsed;
  } catch {
    await SecureStore.deleteItemAsync(OFFLINE_QUEUE_KEY);
    return [];
  }
}

/** Keep a cold-start queue private until its exact verified member returns. */
export function resolveOfflineQueueRecovery(input: {
  identity: QueueRecoveryIdentity;
  queuedScope: OfflineCheckInScope | null;
}): { queueScope: OfflineCheckInScope | null; replay: boolean } {
  if (input.queuedScope === null) return { queueScope: null, replay: false };
  if (input.identity === null) return { queueScope: input.queuedScope, replay: false };
  const sameScope = input.identity.userId === input.queuedScope.userId
    && input.identity.tenantId === input.queuedScope.tenantId
    && input.identity.memberId === input.queuedScope.memberId;
  return sameScope
    ? { queueScope: input.queuedScope, replay: true }
    : { queueScope: null, replay: false };
}

/**
 * Device-only commands are scoped to the verified account and gym that created
 * them. A later account, sign-out or association change gets no replay list.
 */
export async function loadOfflineCheckIns(scope: OfflineCheckInScope): Promise<OfflineCheckInCommand[]> {
  return await serialized(async () => {
    const commands = await readQueue();
    const first = commands[0];
    const queuedScope = first === undefined ? null : { tenantId: first.tenantId, userId: first.userId, memberId: first.memberId };
    const uniformScope = queuedScope === null || commands.every((command) => command.tenantId === queuedScope.tenantId
      && command.userId === queuedScope.userId
      && command.memberId === queuedScope.memberId);
    const recovery = resolveOfflineQueueRecovery({ identity: { kind: 'member', ...scope }, queuedScope });
    if ((!uniformScope || !recovery.replay) && queuedScope !== null) {
      await SecureStore.deleteItemAsync(OFFLINE_QUEUE_KEY);
      return [];
    }
    return commands;
  });
}
export async function saveOfflineCheckIn(command: OfflineCheckInCommand): Promise<void> {
  await serialized(async () => {
    const queue = await readQueue();
    const sameScope = queue.every((saved) => saved.tenantId === command.tenantId && saved.userId === command.userId && saved.memberId === command.memberId);
    const retained = sameScope ? queue : [];
    const existing = retained.find((saved) => saved.clientEventId === command.clientEventId);
    if (existing && JSON.stringify(existing) !== JSON.stringify(command)) throw new Error('Offline event id was reused.');
    if (!existing) await SecureStore.setItemAsync(OFFLINE_QUEUE_KEY, JSON.stringify([...retained, command]));
  });
}
export async function clearOfflineCheckIns(): Promise<void> {
  await serialized(async () => await SecureStore.deleteItemAsync(OFFLINE_QUEUE_KEY));
}

/** Serial replay removes only server-confirmed rows; failures and timeouts stay queued. */
export async function drainOfflineCheckIns(
  scope: Pick<OfflineCheckInCommand, 'tenantId' | 'userId' | 'memberId'>,
  client: ApiClient,
): Promise<OfflineCheckInOutcome[]> {
  return await serialized(async () => {
    const queue = await readQueue();
    if (queue.some((command) => command.tenantId !== scope.tenantId || command.userId !== scope.userId || command.memberId !== scope.memberId)) {
      await SecureStore.deleteItemAsync(OFFLINE_QUEUE_KEY);
      return [];
    }
    const outcomes: OfflineCheckInOutcome[] = [];
    const pending: OfflineCheckInCommand[] = [];
    for (const command of queue) {
      try {
        const result = await client.checkIn({
          token: command.token,
          clientEventId: command.clientEventId,
          offlineRecordedAt: command.offlineRecordedAt,
        });
        outcomes.push({ command, result });
        if (!result.ok) pending.push(command);
      } catch {
        outcomes.push({ command, result: null });
        pending.push(command);
      }
    }
    if (pending.length === 0) await SecureStore.deleteItemAsync(OFFLINE_QUEUE_KEY);
    else await SecureStore.setItemAsync(OFFLINE_QUEUE_KEY, JSON.stringify(pending));
    return outcomes;
  });
}

/**
 * Whether a connectivity/foreground signal means the device has just entered
 * the ready state (online and active). Replay runs on entering ready: a
 * reconnect that arrives while backgrounded waits for the foreground, and a
 * foreground return while still offline waits for the network. An unknown
 * prior signal counts as not ready, so the first ready signal does replay.
 */
export function shouldReplayOnSignal(
  previous: { connected: boolean; foreground: boolean } | null,
  next: { connected: boolean; foreground: boolean },
): boolean {
  const ready = next.connected && next.foreground;
  const wasReady = previous !== null && previous.connected && previous.foreground;
  return ready && !wasReady;
}

/**
 * At most one replay runs at a time. A request that arrives during a run is
 * coalesced into exactly one trailing replay, so mount, reconnect and
 * foreground triggers can overlap without ever draining the queue twice
 * concurrently — the per-event replay contract stays exactly-once.
 */
export function createReplayCoordinator(replay: () => Promise<void>): { requestReplay(): void } {
  let running = false;
  let queued = false;
  const run = (): void => {
    if (running) { queued = true; return; }
    running = true;
    void replay()
      .catch(() => undefined)
      .then(() => {
        running = false;
        if (queued) { queued = false; run(); }
      });
  };
  return { requestReplay: run };
}
