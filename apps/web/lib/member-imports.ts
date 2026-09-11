import type { Database } from '@gymloop/db';
import { DEFAULT_TIMEZONE } from '@gymloop/shared';
import { redirect } from 'next/navigation';
import { identityHome, type GymloopIdentity } from './identity';
import { requireAudience } from './identity-session';

/**
 * The imports screen's reads (phase 6, CSV-D01; the `lib/leads.ts` pattern).
 * The screen is owner/manager only — a trainer, a member or a support preview
 * identity is redirected home BEFORE any read, so the refusal never depends
 * on what a query would have returned.
 *
 * As everywhere else there is deliberately no `.eq('tenant_id', …)` on the
 * reads: the client carries the caller's session, the policies filter, and
 * an application-side predicate would return the right rows even with one of
 * those policies broken — hiding exactly the defect the pgTAP suite exists
 * to catch.
 */

/**
 * The roles the contract lets run a member import. Front desk is excluded
 * here — unlike the leads screen — because imports create members.
 */
const IMPORT_ROLES = ['gym_owner', 'gym_manager'] as const;

/** Whether this identity may open the imports screen at all. */
export function canImportMembers(identity: GymloopIdentity): boolean {
  return identity.kind === 'staff' && (IMPORT_ROLES as readonly string[]).includes(identity.role);
}

/** One branch choice for the import form's branch select. */
export type BranchChoice = { id: string; name: string };

/** One past v1 import run as the screen lists it. */
export type MemberImportRunRow = {
  id: string;
  status: Database['public']['Enums']['import_status'];
  fileName: string;
  createdAt: string;
};

export type MemberImportsScreen = {
  branches: BranchChoice[];
  runs: MemberImportRunRow[];
  /**
   * The gym's timezone, rendered beside the effective-day note so the desk
   * plans in the gym's day. Null when the read failed; the screen then shows
   * the static refusal.
   */
  timezone: string | null;
  errorMessage: string | null;
};

const MAX_RUNS_ON_SCREEN = 20;

export async function loadMemberImportsScreen(): Promise<MemberImportsScreen> {
  const { supabase, identity } = await requireAudience('console');
  if (!canImportMembers(identity)) redirect(identityHome(identity));

  // `member_imports.request_key` is not in the generated types yet — the
  // migration lands with this phase and `supabase gen types` follows it.
  // Until then the run listing goes through the same narrow local cast the
  // leads loader uses for not-yet-generated RPCs; the payload shape comes
  // from the frozen contract.
  const runReader = supabase as unknown as {
    from(table: 'member_imports'): {
      select(columns: string): {
        order(column: string, options: { ascending: boolean }): {
          limit(count: number): Promise<{
            data: Array<{
              id: string;
              status: Database['public']['Enums']['import_status'];
              file_name: string;
              created_at: string;
              request_key: string | null;
            }> | null;
            error: { message: string } | null;
          }>;
        };
      };
    };
  };

  const [gym, branches, runs] = await Promise.all([
    supabase.from('organizations').select('timezone').limit(1).maybeSingle(),
    supabase.from('branches').select('id,name').order('name'),
    runReader
      .from('member_imports')
      .select('id,status,file_name,created_at,request_key')
      .order('created_at', { ascending: false })
      .limit(MAX_RUNS_ON_SCREEN),
  ]);

  if (branches.error || runs.error) {
    return { branches: [], runs: [], timezone: null, errorMessage: 'The import screen could not be loaded.' };
  }

  const branchChoices = (branches.data ?? []).map((branch) => ({ id: branch.id, name: branch.name }));
  // Only v1 runs — the ones prepare created, carrying a request key. Legacy
  // pre-phase-6 rows stay historical and are not importable, so the screen
  // does not list them.
  const runRows: MemberImportRunRow[] = (runs.data ?? [])
    .filter((run) => typeof run.request_key === 'string' && run.request_key !== '')
    .map((run) => ({
      id: run.id,
      status: run.status,
      fileName: run.file_name,
      createdAt: run.created_at,
    }));

  return {
    branches: branchChoices,
    runs: runRows,
    timezone: gym.data?.timezone ?? DEFAULT_TIMEZONE,
    errorMessage: null,
  };
}
