import { INVITE_PAGE_METADATA } from '../../invite/invite-parts';
import { renderInviteContinue } from '../../invite/invite-pages';
export const metadata = INVITE_PAGE_METADATA;
export default async function StaffInviteContinuePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  return renderInviteContinue((await searchParams).result, true);
}
