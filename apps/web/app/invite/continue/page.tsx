import { INVITE_PAGE_METADATA } from '../invite-parts';
import { renderInviteContinue } from '../invite-pages';
export const metadata = INVITE_PAGE_METADATA;
export default async function InviteContinuePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  return renderInviteContinue((await searchParams).result, false);
}
