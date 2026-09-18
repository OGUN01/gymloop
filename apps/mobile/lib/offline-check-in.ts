import * as SecureStore from 'expo-secure-store';
import type { ApiClient, ApiEnvelope, CheckInResult } from '@gymloop/api-client';

const OFFLINE_QUEUE_KEY = 'gymloop.offline-check-in';
export type OfflineCheckInCommand = { clientEventId: string; token: string; offlineRecordedAt: string; memberId: string; tenantId: string; userId: string };
export type OfflineCheckInOutcome = { command: OfflineCheckInCommand; result: ApiEnvelope<CheckInResult> | null };

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

/**
 * Device-only commands are scoped to the verified account and gym that created
 * them. A later account, sign-out or association change gets no replay list.
 */
export async function loadOfflineCheckIns(scope: Pick<OfflineCheckInCommand, 'tenantId' | 'userId' | 'memberId'>): Promise<OfflineCheckInCommand[]> {
  return await serialized(async () => {
    const commands = await readQueue();
    if (commands.some((command) => command.tenantId !== scope.tenantId || command.userId !== scope.userId || command.memberId !== scope.memberId)) {
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
