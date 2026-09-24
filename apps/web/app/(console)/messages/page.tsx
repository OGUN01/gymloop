import { loadMessages, type MessageListRow, type MessageStatusCounts } from '../../../lib/messages';
import { ConsentForm, MessageTemplateForm, WhatsAppOpenButton } from './message-forms';
import { DEFAULT_TIMEZONE, formatDateTime, humanize } from '@gymloop/shared';
import { Alert } from '../alert';
import { StatusWord } from '../../status-word';

/**
 * The staff `/messages` screen (contract §4): scheduled/sent/delivered/
 * failed/opted-out rows and their drill-down counts from one snapshot, a
 * consent action every front-office role can use, and — gym admin only — a
 * template list and the wallet balance. The loader has already refused every
 * identity that is not real front office or a support preview, so this
 * component renders only what a verified caller can see.
 */

/** The four counts in the strip; opted out is a muted line under it so the strip never wraps a lone fifth metric. */
const STATUS_ORDER: (keyof MessageStatusCounts)[] = ['scheduled', 'sent', 'delivered', 'failed'];
const STATUS_LABELS: Record<keyof MessageStatusCounts, string> = {
  scheduled: 'Scheduled', sent: 'Sent', delivered: 'Delivered', failed: 'Failed', opted_out: 'Opted out',
};

/** A vocabulary value as people say it ("in_app" → "In app"). Live rows can carry a null despite the row type, so null reads as nothing. */
const say = (value: string | null) => value ? humanize(value) : '';
/** A template locale code as its language name in English ("hi" → "Hindi"). */
const LANGUAGES = new Intl.DisplayNames(['en'], { type: 'language' });
const language = (code: string) => LANGUAGES.of(code) ?? code;

/** A row's status, in the desk's words — a WhatsApp child is always "Opened in WhatsApp" (contract §5), never its own status label. */
function rowLabel(row: MessageListRow): string {
  if (row.channel === 'whatsapp_link') return 'Opened in WhatsApp';
  return STATUS_LABELS[row.status as keyof MessageStatusCounts] ?? humanize(row.status);
}

/** Only an already-sent or delivered in-app message has a source to open in WhatsApp (contract §5). */
function canOpenWhatsApp(row: MessageListRow): boolean {
  return row.channel === 'in_app' && (row.status === 'sent' || row.status === 'delivered');
}

export default async function MessagesPage({ searchParams }: { searchParams: Promise<{ channel?: string; q?: string; memberCursor?: string }> }) {
  const params = await searchParams;
  const screen = await loadMessages(Promise.resolve(params));
  const nextMemberQuery = new URLSearchParams();
  if (params.channel) nextMemberQuery.set('channel', params.channel);
  if (params.q) nextMemberQuery.set('q', params.q);
  if (screen.memberNextCursor) nextMemberQuery.set('memberCursor', screen.memberNextCursor);

  return <main className="cl-page">
    <div className="cl-page-header">
      <div>
        <p className="cl-eyebrow">Reach members</p>
        <h1 className="cl-title">Messages</h1>
        <p className="cl-lede">Every renewal, payment, fulfilment, promotion and motivation message this gym has queued or sent.</p>
      </div>
    </div>

    {screen.errorMessage !== null ? <Alert>{screen.errorMessage}</Alert> : null}

    <section aria-labelledby="counts-heading" className="cl-section">
      <div className="cl-section-head">
        <h2 id="counts-heading" className="cl-section-title">Counts</h2>
        {screen.asOf !== null ? <p className="cl-muted">Updated <time dateTime={screen.asOf}>{formatDateTime(screen.asOf, DEFAULT_TIMEZONE)}</time></p> : null}
      </div>
      <div className="cl-metrics">
        {STATUS_ORDER.map((status) => <div key={status} className="cl-metric">
          <span className="cl-eyebrow">{STATUS_LABELS[status]}</span>
          <span className="cl-metric-value tabular-nums">{screen.statusCounts[status]}</span>
        </div>)}
      </div>
      <p className="cl-muted mt-2">{STATUS_LABELS.opted_out}: <span className="tabular-nums">{screen.statusCounts.opted_out}</span></p>
    </section>

    <section aria-labelledby="messages-heading" className="cl-section">
      <div className="cl-section-head"><h2 id="messages-heading" className="cl-section-title">Messages</h2></div>
      {screen.rows.length === 0 && screen.errorMessage === null
        ? <div className="cl-empty"><strong>No messages match these filters.</strong><p>Change the channel filter or check back after the next renewal run.</p></div>
        : null}
      {screen.rows.length === 0 ? null : <ul className="cl-rows">
        {screen.rows.map((row) => <li key={row.id}>
          <span>
            <span className="cl-row-title">{row.memberName}</span>
            <span className="cl-row-meta">{[say(row.channel), say(row.category)].filter(Boolean).join(' · ')}{row.sentAt === null ? null : <> · Sent <time dateTime={row.sentAt}>{formatDateTime(row.sentAt, DEFAULT_TIMEZONE)}</time></>}</span>
            {row.failedReason !== null ? <span className="cl-row-meta">Failed: {say(row.failedReason)}</span> : null}
            {row.optedOutReason !== null ? <span className="cl-row-meta">Opted out: {say(row.optedOutReason)}</span> : null}
          </span>
          <span className="flex flex-wrap items-center justify-end gap-3">
            <StatusWord status={row.status} label={rowLabel(row)} />
            {canOpenWhatsApp(row) ? <WhatsAppOpenButton notificationId={row.id} /> : null}
          </span>
        </li>)}
      </ul>}
    </section>

    <section aria-labelledby="consent-heading" className="cl-section">
      <div className="cl-section-head"><h2 id="consent-heading" className="cl-section-title">Consent</h2></div>
      <p className="cl-muted">Record a member's marketing or service consent decision.</p>
      {!screen.isPreview ? <form action="/messages" method="get" className="cl-form mt-4">
        {params.channel ? <input type="hidden" name="channel" value={params.channel} /> : null}
        <div className="cl-form-row items-end">
          <label className="cl-field"><span>Find member by phone</span>
            <input type="search" name="q" defaultValue={params.q ?? ''} placeholder="Last four digits or full phone" className="cl-input" />
          </label>
          <div><button type="submit" className="cl-btn">Search members</button></div>
        </div>
      </form> : null}
      {screen.memberSearchError ? <Alert>Member search could not be loaded.</Alert> : null}
      <ConsentForm key={`${params.q ?? ''}:${params.memberCursor ?? ''}`} members={screen.members} />
      {screen.memberNextCursor ? <a className="cl-btn cl-btn--quiet mt-3" href={`/messages?${nextMemberQuery.toString()}`}>More members</a> : null}
    </section>

    {screen.isAdmin ? <section aria-labelledby="templates-heading" className="cl-section">
      <div className="cl-section-head"><h2 id="templates-heading" className="cl-section-title">Message templates</h2></div>
      <ul className="cl-rows">
        {screen.templates.map((template) => <li key={template.id}>
          <div className="w-full">
            <span className="cl-row-title">{say(template.key)}</span>
            <span className="cl-row-meta">{[say(template.channel), language(template.locale), say(template.category)].filter(Boolean).join(' · ')}</span>
            <p className="mt-2">{template.body}</p>
            <MessageTemplateForm template={template} />
          </div>
        </li>)}
      </ul>
      <h3 className="cl-eyebrow mt-6">New template</h3>
      <MessageTemplateForm />
    </section> : null}

    {screen.isAdmin ? <section aria-labelledby="wallet-heading" className="cl-section">
      <div className="cl-section-head"><h2 id="wallet-heading" className="cl-section-title">Wallet</h2></div>
      <div className="cl-metrics">
        <div className="cl-metric">
          <span className="cl-eyebrow">Balance</span>
          <span className="cl-metric-value tabular-nums">{screen.walletBalanceCredits ?? 'Unavailable'}</span>
          <small>credits</small>
        </div>
      </div>
      <p className="cl-muted mt-2">Only a platform administrator can adjust this balance.</p>
    </section> : null}
  </main>;
}
