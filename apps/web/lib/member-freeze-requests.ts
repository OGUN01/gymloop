import { DEFAULT_TIMEZONE, MEMBER_PAGE_SIZE_DEFAULT, memberAgreedPrice, toLocalDate, freezeEffectiveCondition, freezeRequestEligible, type MemberFreezeRequestRow, type FreezeEffectiveState } from '@gymloop/shared';
import { requireAudience } from './identity-session';

/**
 * The member freeze surface's single caller-session, RLS-scoped fact source:
 * the held membership with its recorded sold terms, and the member's own
 * requests through the safe read RPC. Nothing here decides, prices or
 * approves a pause — the ledger and the desk command do that.
 */

type FreezeRpcClient = {
  rpc(name: string, args?: Record<string, unknown>): PromiseLike<{ data: unknown; error: { code: string } | null }>;
};

type MembershipRead = {
  status: string | null;
  starts_on: string | null;
  ends_on: string | null;
  price_paise: number | string | null;
  discount_paise: number | string | null;
  currency: string | null;
  plans: { name?: unknown } | null;
};

type MembershipQuery = PromiseLike<{ data: MembershipRead | null; error: { message: string } | null }>;

function text(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

/** Map one safe RPC row defensively; the SQL side owns the authoritative shape. */
function toRequestRow(raw: unknown, todayIso: string): MemberFreezeRequestRow | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const row = raw as Record<string, unknown>;
  const requestId = text(row.request_id);
  const status = text(row.status);
  const startsOn = text(row.starts_on);
  const endsOn = text(row.ends_on);
  if (!requestId || !status || !startsOn || !endsOn) return null;
  const effective = text(row.effective);
  return {
    requestId,
    status: status as MemberFreezeRequestRow['status'],
    startsOn,
    endsOn,
    reason: text(row.reason) ?? '',
    decisionReason: text(row.decision_reason),
    effective: (effective === 'scheduled' || effective === 'paused' || effective === 'completed'
      ? effective
      : freezeEffectiveCondition(status, startsOn, endsOn, todayIso)) as FreezeEffectiveState | null,
    replayed: row.replayed === true,
  };
}

/** The membership facts the surface discloses before any action (SLF-001). */
export async function loadMemberFreezeContext() {
  const { supabase, identity } = await requireAudience('member');
  const membershipRead = await supabase.from('memberships')
    .select('status,starts_on,ends_on,price_paise,discount_paise,currency,plans(name)')
    .eq('member_id', identity.memberId)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle() as unknown as MembershipQuery;
  const membershipResult = await membershipRead;
  if (membershipResult.error) return { error: 'Your membership information could not be loaded.' } as const;
  const membershipRow = membershipResult.data;
  const planRelation = membershipRow && 'plans' in membershipRow ? membershipRow.plans : null;
  const agreed = membershipRow && typeof membershipRow.price_paise === 'number' && typeof membershipRow.discount_paise === 'number'
    ? memberAgreedPrice(String(membershipRow.price_paise), String(membershipRow.discount_paise))
    : null;
  // The create command revalidates this id server-side; the surface only needs
  // it to name which held membership the request is for (SLF-004).
  const membershipIdRead = await supabase.from('memberships').select('id').eq('member_id', identity.memberId).order('created_at', { ascending: false }).limit(1).maybeSingle() as unknown as PromiseLike<{ data: { id: string } | null; error: { message: string } | null }>;
  const membershipIdResult = await membershipIdRead;
  const membershipId = membershipIdResult.data?.id ?? null;
  const membership = membershipRow
    ? {
      planName: text(planRelation?.name) ?? 'Membership',
      status: text(membershipRow.status) ?? '',
      startsOn: text(membershipRow.starts_on),
      endsOn: text(membershipRow.ends_on),
      recordedAgreedPricePaise: agreed === null ? null : String(agreed),
      currency: text(membershipRow.currency) ?? 'INR',
    }
    : null;
  const result = await (supabase as unknown as FreezeRpcClient).rpc('read_member_freeze_requests', {
    p_limit: MEMBER_PAGE_SIZE_DEFAULT,
    p_after_created_at: null,
    p_after_id: null,
  });
  const todayIso = toLocalDate(new Date(), DEFAULT_TIMEZONE);
  const requests = Array.isArray(result.data)
    ? (result.data as unknown[]).map((row) => toRequestRow(row, todayIso)).filter((row): row is MemberFreezeRequestRow => row !== null)
    : [];
  return {
    membership,
    membershipId,
    requests,
    // SLF-004: creation is open only against a live, currently dated membership.
    canRequest: membership !== null && freezeRequestEligible(membership.status),
    loadedAt: new Date().toISOString(),
  } as const;
}
