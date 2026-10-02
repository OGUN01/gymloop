import { INVITE_PAGE_METADATA } from '../invite-parts';
import { renderInviteLanding } from '../invite-pages';
export const metadata = INVITE_PAGE_METADATA;
export default async function InviteLandingPage({ params }: { params: Promise<{ token: string }> }) {
  return renderInviteLanding((await params).token, false);
}
