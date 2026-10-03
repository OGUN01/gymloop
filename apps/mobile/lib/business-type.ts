import { isBusinessType, type BusinessType } from '@gymloop/shared';
export const BUSINESS_TYPE_STORAGE_KEY = 'gymloop.business-type';
export function encodePersistedBusinessType(tenantId: string, type: BusinessType): string { return JSON.stringify({ t: tenantId, b: type }); }
export function readPersistedBusinessType(raw: string | null, tenantId: string): BusinessType | null {
  try {
    const row: unknown = raw === null ? null : JSON.parse(raw);
    if (row === null || typeof row !== 'object' || !('t' in row) || !('b' in row)) return null;
    return row.t === tenantId && isBusinessType(row.b) ? row.b : null;
  } catch { return null; }
}
export function resolveBusinessType(input: { fetched: BusinessType | null; persisted: BusinessType | null }): BusinessType | null { return input.fetched ?? input.persisted ?? null; }
