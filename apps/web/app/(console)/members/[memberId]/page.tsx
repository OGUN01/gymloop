import Link from 'next/link';
import { notFound } from 'next/navigation';
import { DEFAULT_TIMEZONE } from '@gymloop/shared';
import { createServerSupabase } from '../../../../lib/supabase/server';
import { loadMember } from '../member-data';

/**
 * One member, and what they have actually done — the visits, most recent first.
 *
 * The attendance list is the point of the screen rather than a section of it:
 * the whole product loop starts at "has this person been coming?", and that
 * question is answered by a list of dates, not by a status badge that says
 * `active` because nobody has cancelled yet.
 *
 * Every read here goes straight through `supabase-js` with RLS filtering
 * (`docs/architecture.md`), and none of them names a tenant — see
 * `member-data.ts` for why that absence is deliberate.
 */

/**
 * How much history one page shows. Enough to cover roughly two months of daily
 * visits, which is the span someone judging "have they gone quiet?" actually
 * looks at; older visits are Phase 4's retention view, not this screen's.
 */
const ATTENDANCE_PAGE_SIZE = 60;

const DATE_TIME = new Intl.DateTimeFormat('en-IN', {
  timeZone: DEFAULT_TIMEZONE,
  dateStyle: 'medium',
  timeStyle: 'short',
});

const DATE_ONLY = new Intl.DateTimeFormat('en-IN', {
  timeZone: DEFAULT_TIMEZONE,
  dateStyle: 'medium',
});

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="py-2">
      <dt className="text-xs uppercase tracking-wide text-neutral-500">{label}</dt>
      <dd className="mt-0.5 text-sm">{children}</dd>
    </div>
  );
}

export default async function MemberDetailPage({
  params,
}: {
  params: Promise<{ memberId: string }>;
}) {
  const { memberId } = await params;
  const { data: member } = await loadMember(memberId);

  // Absent because they do not exist, or absent because they belong to another
  // gym — the same answer either way, which is the answer RLS already gives.
  if (!member) notFound();

  const supabase = await createServerSupabase();
  const [{ data: branch }, { data: visits, error: visitsError }] = await Promise.all([
    supabase.from('branches').select('name').eq('id', member.branch_id).maybeSingle(),
    supabase
      .from('attendance')
      .select('id, checked_in_at, source, assist_reason')
      .eq('member_id', memberId)
      .order('checked_in_at', { ascending: false })
      .limit(ATTENDANCE_PAGE_SIZE),
  ]);

  return (
    <main className="mx-auto max-w-3xl px-6 py-8">
      <div className="flex items-baseline justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold">{member.full_name}</h1>
          <p className="text-sm tabular-nums text-neutral-600">{member.phone}</p>
        </div>
        <div className="flex shrink-0 gap-4 text-sm">
          <Link href={`/members/${member.id}/edit`} className="text-neutral-600 underline">
            Edit
          </Link>
          <Link href="/console" className="text-neutral-600 underline">
            All members
          </Link>
        </div>
      </div>

      {member.erased_at === null ? null : (
        <p className="mt-4 rounded-md bg-amber-50 px-3 py-2 text-sm text-amber-800">
          This member’s personal details were erased on {DATE_ONLY.format(new Date(member.erased_at))}.
        </p>
      )}

      <dl className="mt-6 grid grid-cols-2 gap-x-6 sm:grid-cols-3">
        <Row label="Status">
          <span className="capitalize">{member.status}</span>
        </Row>
        <Row label="Joined">{DATE_ONLY.format(new Date(member.joined_on))}</Row>
        <Row label="Branch">{branch?.name ?? '—'}</Row>
        <Row label="Email">{member.email ?? '—'}</Row>
        <Row label="Member code">{member.member_code ?? '—'}</Row>
      </dl>

      <h2 className="mt-8 text-sm font-medium text-neutral-700">
        Recent visits{visits && visits.length > 0 ? ` (${visits.length})` : ''}
      </h2>

      {visitsError ? (
        <p role="alert" className="mt-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
          The visit history could not be loaded. {visitsError.message}
        </p>
      ) : null}

      {visits && visits.length > 0 ? (
        <ul className="mt-3 divide-y divide-neutral-100">
          {visits.map((visit) => (
            <li key={visit.id} className="flex items-baseline justify-between gap-4 py-2">
              <span className="text-sm tabular-nums">
                {DATE_TIME.format(new Date(visit.checked_in_at))}
              </span>
              <span className="text-right text-sm text-neutral-600">
                {visit.source === 'qr' ? 'Scanned' : visit.source.replace('_', ' ')}
                {visit.assist_reason === null ? null : ` · ${visit.assist_reason}`}
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <p className="mt-3 text-sm text-neutral-600">No visits recorded yet.</p>
      )}
    </main>
  );
}
