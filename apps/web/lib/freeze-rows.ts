import { freezeEffectiveCondition, type DeskFreezeRequestRow, type FreezeEffectiveState, type MemberFreezeRequestRow } from '@gymloop/shared';

/**
 * The one safe-read row vocabulary for the SLF loaders (SLF-001/SLF-013): the
 * RPC client shape both member and staff readers use, the defensive text
 * coercion, and the shared row prefix every frozen request row carries — the
 * SQL side owns the authoritative shape, and an unreadable row is a failed
 * read, never a fake empty.
 */
export type FreezeRpcClient = {
  rpc(name: string, args?: Record<string, unknown>): PromiseLike<{ data: unknown; error: { code: string } | null }>;
};

export function freezeText(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

type FreezeRowBase = {
  requestId: string;
  status: MemberFreezeRequestRow['status'];
  startsOn: string;
  endsOn: string;
  reason: string;
  decisionReason: string | null;
};

/** The frozen prefix every request row shares; null when the row is unreadable. */
function freezeRowBase(raw: unknown): FreezeRowBase | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const row = raw as Record<string, unknown>;
  const requestId = freezeText(row.request_id);
  const status = freezeText(row.status);
  const startsOn = freezeText(row.starts_on);
  const endsOn = freezeText(row.ends_on);
  if (!requestId || !status || !startsOn || !endsOn) return null;
  return {
    requestId,
    status: status as MemberFreezeRequestRow['status'],
    startsOn,
    endsOn,
    reason: freezeText(row.reason) ?? '',
    decisionReason: freezeText(row.decision_reason),
  };
}

function explicitEffective(raw: Record<string, unknown>): FreezeEffectiveState | null {
  const value = freezeText(raw.effective);
  return value === 'scheduled' || value === 'paused' || value === 'completed' ? value : null;
}

/** The member projection: the RPC's explicit effective condition, else the derived one. */
export function toMemberFreezeRow(raw: unknown, todayIso: string): MemberFreezeRequestRow | null {
  const base = freezeRowBase(raw);
  if (base === null) return null;
  const row = raw as Record<string, unknown>;
  return {
    ...base,
    effective: explicitEffective(row) ?? freezeEffectiveCondition(base.status, base.startsOn, base.endsOn, todayIso),
    replayed: row.replayed === true,
  };
}

/** The desk projection: same prefix plus the roster facts; unreadable rows stay null. */
export function toDeskFreezeRow(raw: unknown): DeskFreezeRequestRow | null {
  const base = freezeRowBase(raw);
  if (base === null) return null;
  const row = raw as Record<string, unknown>;
  return {
    ...base,
    effective: null,
    memberName: freezeText(row.member_name) ?? 'Member',
    memberCode: freezeText(row.member_code) ?? '',
    adoptedByStaffId: freezeText(row.adopted_by_staff_id),
    revision: (typeof row.revision === 'string' || typeof row.revision === 'number') ? String(row.revision) : '',
  };
}