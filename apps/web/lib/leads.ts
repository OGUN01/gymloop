import { Constants, type Database } from '@gymloop/db';
import { DEFAULT_TIMEZONE, MEMBER_PAGE_SIZE_DEFAULT, MEMBER_PAGE_SIZE_MAX } from '@gymloop/shared';
import { redirect } from 'next/navigation';
import { identityHome, type GymloopIdentity } from './identity';
import { requireAudience } from './identity-session';
import { decodeCursor, encodeCursor, pageSizeFrom, UUID_PATTERN } from './keyset';

/**
 * The leads pipeline screen's one read, per the phase 6 contract: there is no
 * `GET /api/leads`, and the `/leads` loader calls `public.list_leads` directly
 * under RLS through the caller's own client — so this module owns the filters,
 * the cursor and the counts the same way `lib/members.ts` owns the roster's.
 *
 * As everywhere else there is deliberately no `.eq('tenant_id', …)` on the
 * supporting reads: the client carries the caller's session, the policies
 * filter, and an application-side predicate would return the right rows even
 * with one of those policies broken — hiding exactly the defect the pgTAP
 * suite exists to catch.
 */

export type LeadStage = Database['public']['Enums']['lead_stage'];
export type LeadSource = Database['public']['Enums']['lead_source'];

/**
 * The roles the contract lets work a lead: owner, manager, front desk. A
 * trainer is console staff for other screens and is refused here without lead
 * facts; platform identities never reach a gym-side route at all.
 */
export const FRONT_OFFICE_ROLES = ['gym_owner', 'gym_manager', 'front_desk'] as const;

function isFrontOffice(identity: GymloopIdentity): boolean {
  return identity.kind === 'staff' && (FRONT_OFFICE_ROLES as readonly string[]).includes(identity.role);
}

/** A lead as the list RPC returns it — exactly the contract's `LeadListRow`. */
export type LeadListRow = {
  id: string;
  revision: string;
  fullName: string;
  phone: string;
  source: LeadSource;
  stage: LeadStage;
  assignedToStaffId: string | null;
  assignedToName: string | null;
  branchId: string;
  branchName: string;
  trialAt: string | null;
  convertedMemberId: string | null;
  lostReason: string | null;
  updatedAt: string;
};

/** `LeadListRow` plus exactly the detail fields the mutation RPCs return. */
export type LeadDetail = LeadListRow & {
  email: string | null;
  notes: string | null;
  convertedAt: string | null;
  createdAt: string;
};

/** The RPC's own result, before the loader substitutes `nextCursor` for `nextAfter`. */
type LeadListResult = {
  asOf: string;
  rows: LeadListRow[];
  nextAfter: { updatedAt: string; id: string } | null;
  pageResultCount: string;
  totalMatchingCount: string;
  filteredStageCounts: Record<LeadStage, string>;
};

export type StaffChoice = { id: string; fullName: string };
export type BranchChoice = { id: string; name: string };

type LeadsScreen = {
  rows: LeadListRow[];
  stageCounts: Record<LeadStage, string>;
  pageResultCount: string;
  totalMatchingCount: string;
  /**
   * The snapshot instant the RPC's counts and rows were read at — the one
   * statement's clock, rendered next to the counts so the desk never reads
   * them as a live tally. Null when the screen is unusable or the value is
   * not a usable string.
   */
  asOf: string | null;
  nextCursor: string | null;
  pageSize: number;
  timezone: string;
  staffChoices: StaffChoice[];
  branchChoices: BranchChoice[];
  /**
   * The page's leads' current email and notes, keyed by lead id, prefilled
   * into the edit form. The contract's list row carries neither, and the row
   * shape stays exactly as frozen — this is a presentation read, not part of
   * it. An absent entry means the read failed for that lead, and the edit
   * form refuses to render rather than offering a save that would clear the
   * facts it could not show; a present entry with empty strings is a lead
   * that genuinely has none.
   */
  editableText: Record<string, { email: string; notes: string }>;
  errorMessage: string | null;
};

/** A value from the generated catalogue, or null — never a hand-written union. */
function catalogueValue<T extends string>(catalogue: readonly T[], value: string | undefined): T | null {
  return value !== undefined && catalogue.includes(value as T) ? (value as T) : null;
}

function isUuidParam(value: string | undefined): value is string {
  return value !== undefined && UUID_PATTERN.test(value);
}

function emptyStageCounts(): Record<LeadStage, string> {
  return Object.fromEntries(
    Constants.public.Enums.lead_stage.map((stage) => [stage, '0']),
  ) as Record<LeadStage, string>;
}

/** Counts travel as decimal integer strings; anything else is treated as none. */
function decimalText(value: unknown): string {
  return typeof value === 'string' ? value : '0';
}

export async function loadLeads(
  searchParams: Promise<{
    stage?: string;
    source?: string;
    assignee?: string;
    branch?: string;
    q?: string;
    limit?: string;
    cursor?: string;
  }>,
): Promise<LeadsScreen> {
  const params = await searchParams;
  const { supabase, identity } = await requireAudience('console');
  // The screen is front-office only. A trainer or a support preview identity
  // is redirected home BEFORE any lead is read: the refusal must not depend
  // on what the query would have returned.
  if (!isFrontOffice(identity)) redirect(identityHome(identity));

  const pageSize = pageSizeFrom(params.limit, MEMBER_PAGE_SIZE_DEFAULT, MEMBER_PAGE_SIZE_MAX);
  const query = params.q?.trim() ?? '';
  const stage = catalogueValue(Constants.public.Enums.lead_stage, params.stage);
  const source = catalogueValue(Constants.public.Enums.lead_source, params.source);
  // Assignee is the one filter with a named non-UUID value: "unassigned" is a
  // bucket the front desk actually works from, not a staff id.
  const assignee = params.assignee === 'unassigned'
    ? 'unassigned'
    : isUuidParam(params.assignee) ? params.assignee : null;
  const branchId = isUuidParam(params.branch) ? params.branch : null;

  // An unusable cursor starts page one rather than erroring, on the same
  // terms as the roster: it is a link somebody edited or one that outlived a
  // deploy, and neither deserves an error page. The `updatedAt` half is
  // checked only for shape, not for `Date.parse` — a Postgres offset like
  // `+00` is a valid keyset boundary and not a V8 ISO instant, and deciding
  // which timestamps are real is the comparison's job, not this guard's.
  const after = decodeCursor(params.cursor, (value) =>
    typeof value.updatedAt === 'string' &&
    value.updatedAt !== '' &&
    typeof value.id === 'string' &&
    UUID_PATTERN.test(value.id)
      ? { updatedAt: value.updatedAt, id: value.id }
      : null,
  );

  // `list_leads` is not in the generated types yet — the migration lands with
  // this phase and `supabase gen types` follows it. Until then it is called
  // through the same narrow local cast the add-on screens use for
  // not-yet-generated RPCs, with the wire payload derived from the frozen
  // contract. The RPC derives tenant and actor from claims; neither is an
  // argument here, and RLS remains the boundary.
  const reader = supabase as unknown as {
    rpc(
      name: 'list_leads',
      args: {
        p_stage: LeadStage | null;
        p_source: LeadSource | null;
        p_assignee: string | null;
        p_branch_id: string | null;
        p_query: string | null;
        p_after_updated_at: string | null;
        p_after_id: string | null;
        p_limit: number;
      },
    ): Promise<{ data: LeadListResult | null; error: { message: string } | null }>;
  };

  const [page, gym, staff, branches] = await Promise.all([
    reader.rpc('list_leads', {
      p_stage: stage,
      p_source: source,
      p_assignee: assignee,
      p_branch_id: branchId,
      p_query: query === '' ? null : query,
      p_after_updated_at: after?.updatedAt ?? null,
      p_after_id: after?.id ?? null,
      p_limit: pageSize,
    }),
    // The gym's timezone, because a scheduled trial is rendered in the gym's
    // day and the desk plans in that day. One row under the caller's own
    // policies, read alongside the page so the screen cannot disagree with
    // itself about when a trial happens.
    supabase.from('organizations').select('timezone').limit(1).maybeSingle(),
    // Assignee choices for the filter and the forms: active staff, narrowed
    // client-side to the roles the contract allows to be assigned a lead.
    supabase.from('staff').select('id,full_name,role').eq('is_active', true).order('full_name').order('id'),
    supabase.from('branches').select('id,name').order('name'),
  ]);

  const timezone = gym.data?.timezone ?? DEFAULT_TIMEZONE;
  const staffChoices = (staff.data ?? [])
    .filter((member) => (FRONT_OFFICE_ROLES as readonly string[]).includes(member.role))
    .map((member) => ({ id: member.id, fullName: member.full_name }));
  const branchChoices = (branches.data ?? []).map((branch) => ({ id: branch.id, name: branch.name }));
  const stageCounts = emptyStageCounts();

  const unusable: LeadsScreen = {
    rows: [],
    stageCounts,
    pageResultCount: '0',
    totalMatchingCount: '0',
    asOf: null,
    nextCursor: null,
    pageSize,
    timezone,
    staffChoices,
    branchChoices,
    editableText: {},
    errorMessage: 'The lead list could not be loaded.',
  };

  // The supporting reads are part of the screen, not decoration: with the
  // staff or branch choices missing, the filter's assignee and branch buckets
  // and every form's selects would be silently unsatisfiable, so the screen
  // is unusable rather than half-rendered.
  if (staff.error || branches.error) return unusable;

  // A static message, never the RPC's own: a Postgres string rendered to the
  // front desk is exactly what the roster's cursor validation rejected
  // (`lib/keyset.ts` records the precedent), and the failing statement is in
  // the server logs for whoever needs the real text.
  if (page.error) return unusable;
  const result = page.data;
  if (result === null || !Array.isArray(result.rows)) return unusable;

  // The edit form's prefill for email and notes: one RLS-scoped read of the
  // page's rows, because the contract's list row deliberately carries neither
  // and a desk fixing a phone typo must see the facts it is about to clear.
  // Like the RPC this reads through the caller's own client, so the policies
  // filter. A read that fails or omits a row leaves that lead without an
  // entry, and the edit form then refuses to render for it: an edit that
  // cannot show the current facts must not offer a save that would clear
  // them.
  const editableText: LeadsScreen['editableText'] = {};
  if (result.rows.length > 0) {
    try {
      const detailRead = await supabase.from('leads').select('id,email,notes').in('id', result.rows.map((row) => row.id));
      for (const row of Array.isArray(detailRead.data) ? detailRead.data : []) {
        if (typeof row.id !== 'string') continue;
        editableText[row.id] = {
          email: typeof row.email === 'string' ? row.email : '',
          notes: typeof row.notes === 'string' ? row.notes : '',
        };
      }
    } catch {
      /* A failed read leaves no entries — the edit form refuses, it does not
         offer a blank that would wipe the facts on save. */
    }
  }

  // Every canonical stage key is present even when the RPC omitted one, so
  // the "Within current filters" row never has a hole the desk reads as
  // "nobody is at that stage".
  for (const stage of Constants.public.Enums.lead_stage) {
    const count = result.filteredStageCounts?.[stage];
    if (typeof count === 'string') stageCounts[stage] = count;
  }

  const nextAfter = result.nextAfter;
  const nextCursor = nextAfter !== null &&
    typeof nextAfter === 'object' &&
    typeof nextAfter.updatedAt === 'string' &&
    typeof nextAfter.id === 'string' &&
    UUID_PATTERN.test(nextAfter.id)
    ? encodeCursor({ updatedAt: nextAfter.updatedAt, id: nextAfter.id })
    : null;

  return {
    rows: result.rows,
    stageCounts,
    pageResultCount: decimalText(result.pageResultCount),
    totalMatchingCount: decimalText(result.totalMatchingCount),
    asOf: typeof result.asOf === 'string' && result.asOf !== '' ? result.asOf : null,
    nextCursor,
    pageSize,
    timezone,
    staffChoices,
    branchChoices,
    editableText,
    errorMessage: null,
  };
}
