import { loadMemberMessages } from '../../../lib/member-messages';
import { MemberMessageAck } from './member-message-actions';

/**
 * The member `/member/messages` screen (contract §4): the member's own
 * in-app sent/delivered messages, plus a separate consent history. The
 * loader has already refused every identity that is not a real member, so
 * this component renders only what a verified caller can see. Reading a
 * message never happens from this render alone — `MemberMessageAck` posts
 * only on an explicit click.
 */
export default async function MemberMessagesPage(_props: object = {}) {
  void _props;
  const screen = await loadMemberMessages();

  return <main className="member-route route-workspace">
    <h1 className="text-2xl font-semibold">Your messages</h1>

    {screen.errorMessage !== null
      ? <p role="alert" className="mt-4 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{screen.errorMessage}</p>
      : null}

    <section aria-labelledby="messages-heading" className="mt-6">
      <h2 id="messages-heading" className="text-lg font-semibold">Messages</h2>
      {screen.messages.length === 0 && screen.errorMessage === null ? <p className="mt-2 text-sm text-neutral-600">No messages yet.</p> : null}
      <ul className="mt-3 space-y-3">
        {screen.messages.map((message) => <li key={message.id} className="rounded-lg border border-neutral-200 p-3 text-sm">
          <p>{message.body}</p>
          <p className="mt-1 text-neutral-600">{message.status === 'delivered' ? 'Read' : 'New'}</p>
          {message.status === 'sent' ? <MemberMessageAck notificationId={message.id} /> : null}
        </li>)}
      </ul>
    </section>

    <section aria-labelledby="consent-heading" className="mt-8">
      <h2 id="consent-heading" className="text-lg font-semibold">Consent history</h2>
      {screen.consents.length === 0 && screen.errorMessage === null ? <p className="mt-2 text-sm text-neutral-600">No consent decisions recorded yet.</p> : null}
      <ul className="mt-3 space-y-1 text-sm">
        {screen.consents.map((consent, index) => <li key={index}>{consent.purpose}: {consent.granted ? 'granted' : 'withdrawn'}</li>)}
      </ul>
    </section>
  </main>;
}
