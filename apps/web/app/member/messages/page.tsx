import Link from 'next/link';
import { ArrowLeft } from 'lucide-react';
import { UI_TOKENS } from '@gymloop/shared';
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

  return <main className="member-route member-portal">
    <header>
      <Link href="/member/my-gym" className="cl-back"><ArrowLeft aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />My gym</Link>
      <h1 className="member-title">Your messages</h1>
      <p className="cl-lede">Notes from your gym, and the choices you have made about hearing from them.</p>
    </header>

    {screen.errorMessage !== null ? <p role="alert" className="cl-alert">{screen.errorMessage}</p> : null}

    <section aria-labelledby="messages-heading">
      <h2 id="messages-heading" className="cl-eyebrow member-eyebrow">Messages</h2>
      {screen.messages.length === 0 && screen.errorMessage === null
        ? <div className="cl-empty"><strong>No messages yet</strong><p>When your gym sends you a note, it appears here.</p></div>
        : <ul className="cl-rows">
          {screen.messages.map((message) => <li key={message.id} className="member-message">
            <span><span className="cl-row-title member-message-body">{message.body}</span></span>
            {message.status === 'delivered' ? <span className="cl-status">Read</span> : <span className="member-message-new"><span className="cl-status" data-tone="accent">New</span><MemberMessageAck notificationId={message.id} /></span>}
          </li>)}
        </ul>}
    </section>

    <section aria-labelledby="consent-heading">
      <h2 id="consent-heading" className="cl-eyebrow member-eyebrow">Consent history</h2>
      {screen.consents.length === 0 && screen.errorMessage === null
        ? <div className="cl-empty"><strong>No consent decisions recorded yet</strong><p>Your gym records your choices here when you give or withdraw them.</p></div>
        : <ul className="cl-rows">
          {screen.consents.map((consent, index) => <li key={index}>
            <span className="cl-row-title member-sentence">{consent.purpose.replaceAll('_', ' ')}</span>
            <span className="cl-status" data-tone={consent.granted ? 'ok' : 'risk'}>{consent.granted ? 'Granted' : 'Withdrawn'}</span>
          </li>)}
        </ul>}
    </section>
  </main>;
}
