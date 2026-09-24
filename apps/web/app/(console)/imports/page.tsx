import { loadMemberImportsScreen } from '../../../lib/member-imports';
import { MemberImportForm } from './import-forms';
import { Alert } from '../alert';

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

  return <main className="cl-page">
    <div className="cl-page-header">
      <div>
        <p className="cl-eyebrow">Members</p>
        <h1 className="cl-title">Import members</h1>
        <p className="cl-lede">
          Import members from a .csv or .xlsx file into one branch. Every row is
          previewed before anything is created.
        </p>
      </div>
    </div>

    {screen.errorMessage !== null
      ? <Alert>{screen.errorMessage}</Alert>
      : <MemberImportForm branches={screen.branches} runs={screen.runs} timezone={screen.timezone} />}
  </main>;
}
