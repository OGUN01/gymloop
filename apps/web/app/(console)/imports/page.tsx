import { loadMemberImportsScreen } from '../../../lib/member-imports';
import { MemberImportForm } from './import-forms';

/**
 * The member-import screen: one client form that owns the whole journey —
 * upload → header inspection → column mapping → preview → confirmation →
 * report — over the four contract endpoints. The loader has already refused
 * every identity that is not a real owner or manager, so this component
 * renders only what a verified caller can do.
 */
export default async function ImportsPage({ searchParams: _searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  void _searchParams;
  const screen = await loadMemberImportsScreen();

  return <main className="mx-auto w-full max-w-5xl px-4 py-8">
    <header>
      <h1 className="text-2xl font-semibold">Import members</h1>
      <p className="mt-1 text-sm text-neutral-600">
        Import members from a .csv or .xlsx file into one branch. Every row is
        previewed before anything is created.
      </p>
    </header>

    {screen.errorMessage !== null
      ? <p role="alert" className="mt-4 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{screen.errorMessage}</p>
      : <MemberImportForm branches={screen.branches} runs={screen.runs} timezone={screen.timezone} />}
  </main>;
}
