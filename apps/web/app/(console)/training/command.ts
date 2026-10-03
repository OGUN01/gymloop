import { isObject } from '../../../lib/keyset';
import type { ConsoleViewer } from '../../../lib/training-console';

export function managers(viewer: ConsoleViewer) { return !viewer.readOnly && (viewer.role === 'gym_owner' || viewer.role === 'gym_manager'); }
export function ownTrainer(viewer: ConsoleViewer, staffId: string) { return managers(viewer) || (!viewer.readOnly && viewer.role === 'trainer' && viewer.staffId === staffId); }
export async function postCommand(route: string, body: unknown): Promise<unknown> {
  const response = await fetch(route, { method: 'POST', credentials: 'same-origin', cache: 'no-store', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const result: unknown = await response.json();
  if (!response.ok) return isObject(result) ? { ...result, ok: false } : null;
  return result;
}
export function commandData(result: unknown): Record<string, unknown> | null {
  return isObject(result) && result.ok === true && !result.error && isObject(result.data) ? result.data : null;
}
