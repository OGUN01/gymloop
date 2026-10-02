import { inviteIST, type loadMemberInviteActivity } from '../../../../lib/member-invite-history';
import { Alert } from '../../alert';
/** Persisted audit history is never inferred from the current access state. */
export function InviteHistory({ activity }: {
  activity: Awaited<ReturnType<typeof loadMemberInviteActivity>>;
}) {
  return <section className="app-access" aria-labelledby="invite-history-heading"><h2 id="invite-history-heading" className="cl-section-title member-detail-heading">Recent invite history</h2>{activity === null ? <Alert>Invite history could not be loaded. Reload the page to try again.</Alert> : activity.length === 0 ? <p className="app-access-note">No invite activity yet.</p> : <ul className="cl-rows">{activity.map(event => <li key={event.id}><div><strong>{event.action}</strong><p>{event.actor}</p></div><time dateTime={event.occurredAt}>{inviteIST(event.occurredAt)}</time></li>)}</ul>}</section>;
}
