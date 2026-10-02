import type { Database } from '@gymloop/db';
import { DEFAULT_TIMEZONE, formatDateTime, MEMBER_INVITE_HISTORY_LIMIT } from '@gymloop/shared';
import { callInviteRpc } from './member-invite-rpc';
import type { createServerSupabase } from './supabase/server';

/** The presentation projection omits the stored token hash completely. */
export type MemberInviteSummary = Pick<Database['public']['Tables']['member_invites']['Row'], 'id' | 'member_id' | 'status' | 'issued_at' | 'expires_at'>;
type Reader = Awaited<ReturnType<typeof createServerSupabase>>;

/** Read only the caller-visible invites for the requested members, newest first. */
export async function loadMemberInviteSummaries(supabase: Reader, tenantId: string, memberIds: readonly string[]): Promise<MemberInviteSummary[] | null> {
  if (memberIds.length === 0) return [];
  try {
    const { data, error } = await supabase.from('member_invites').select('id,member_id,status,issued_at,expires_at').eq('tenant_id', tenantId).in('member_id', [...memberIds]).order('issued_at', { ascending: false }).order('id', { ascending: false });
    return error ? null : data;
  } catch { return null; }
}

/** Absolute dates share one IST formatter for the roster and persisted history. */
export function inviteIST(instant: string): string {
  return Number.isNaN(Date.parse(instant)) ? 'Time unavailable' : `${formatDateTime(instant, DEFAULT_TIMEZONE)} IST`;
}

const INVITE_ACTIVITY = {
  'member_invite.issued': 'Invite sent',
  'member_invite.superseded': 'Invite replaced',
  'member_invite.revoked': 'Invite revoked',
  'member_invite.redeemed': 'Invite redeemed',
  'member.linked': 'Account linked',
  'member.unlinked': 'Account unlinked',
} as const;

/** No payload JSON, refusal identities or token material crosses this projection. */
export async function loadMemberInviteActivity(supabase: Reader, memberId: string) {
  const { data, error } = await callInviteRpc(supabase, 'read_member_invite_history', { p_member_id: memberId });
  if (error || !Array.isArray(data)) return null;
  const rows = data as unknown[];
  const events: { id: string; action: string; actor: string; occurredAt: string }[] = [];
  for (const raw of rows.slice(0, MEMBER_INVITE_HISTORY_LIMIT)) {
    if (typeof raw !== 'object' || raw === null) return null;
    const row = raw as Record<string, unknown>;
    if (typeof row.event_id !== 'string' || typeof row.occurred_at !== 'string' || Number.isNaN(Date.parse(row.occurred_at)) || typeof row.action !== 'string' || !Object.hasOwn(INVITE_ACTIVITY, row.action)) return null;
    if (row.actor_name !== null && typeof row.actor_name !== 'string') return null;
    events.push({ id: row.event_id, action: INVITE_ACTIVITY[row.action as keyof typeof INVITE_ACTIVITY], actor: typeof row.actor_name === 'string' && row.actor_name.trim() !== '' ? row.actor_name : 'Name unavailable', occurredAt: row.occurred_at });
  }
  return events;
}
