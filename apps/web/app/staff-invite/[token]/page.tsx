import { INVITE_PAGE_METADATA } from '../../invite/invite-parts';
import { renderInviteLanding } from '../../invite/invite-pages';
export const metadata = INVITE_PAGE_METADATA;
export default async function StaffInviteLandingPage({ params }: { params: Promise<{ token: string }> }) {
  return renderInviteLanding((await params).token, true);
}
