import { loadMessages, type MessageListRow, type MessageStatusCounts } from '../../../lib/messages';
import { ConsentForm, MessageTemplateForm, WhatsAppOpenButton } from './message-forms';
import { DEFAULT_TIMEZONE, formatDateTime, humanize, MESSAGE_LOG_PREVIEW_ROWS } from '@gymloop/shared';
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


/** Sample values a template preview is read with, so the owner sees a message, not `{{tokens}}`. */
const SAMPLE_VALUES: Record<string, string> = { name: 'Riya', plan: 'Monthly plan', ends_on: '13 Oct', streak: '12', amount: '₹2,999', gym: 'Iron Box' };
const TOKEN = /\{\{\s*(\w+)\s*\}\}/g;
const preview = (body: string) => body.replace(TOKEN, (whole, token: string) => SAMPLE_VALUES[token] ?? whole);
const variables = (body: string) => [...new Set([...body.matchAll(TOKEN)].map((match) => humanize(match[1] ?? '').toLowerCase()))];

/** What each count means, in the caption slot under its number. */
const COUNT_CAPTIONS: Partial<Record<keyof MessageStatusCounts, string>> = {
  scheduled: 'Waiting to send', sent: 'Not yet confirmed', delivered: 'Reached the member',
};

export default async function MessagesPage({ searchParams }: { searchParams: Promise<{ channel?: string; q?: string; memberCursor?: string; log?: string }> }) {
  const { log, ...params } = await searchParams;
  const screen = await loadMessages(Promise.resolve(params));
  const nextMemberQuery = new URLSearchParams();
  if (params.channel) nextMemberQuery.set('channel', params.channel);
  if (params.q) nextMemberQuery.set('q', params.q);
  if (screen.memberNextCursor) nextMemberQuery.set('memberCursor', screen.memberNextCursor);
  const showAll = log === 'all';
  const visibleRows = showAll ? screen.rows : screen.rows.slice(0, MESSAGE_LOG_PREVIEW_ROWS);
  const logQuery = (all: boolean) => {
    const query = new URLSearchParams();
    if (params.channel) query.set('channel', params.channel);
    if (params.q) query.set('q', params.q);
    if (all) query.set('log', 'all');
    const text = query.toString();
    return `/messages${text === '' ? '' : `?${text}`}#log`;
  };

  return <main className="cl-page comms-messages">
    <div className="cl-page-header">
      <div>
        <p className="cl-eyebrow">Reach members</p>
        <h1 className="cl-title">Messages</h1>
        <p className="cl-lede">Every renewal, payment, fulfilment, promotion and motivation message this gym has queued or sent.</p>
      </div>
      {screen.asOf !== null ? <p className="cl-muted comms-updated">Updated <time dateTime={screen.asOf}>{formatDateTime(screen.asOf, DEFAULT_TIMEZONE)}</time></p> : null}
    </div>

    <nav aria-label="Messages sections" className="comms-subnav">
      <a href="#log" data-section="log">Recent</a>
      <a href="#consent" data-section="consent">Consent</a>
      {screen.isAdmin ? <a href="#templates" data-section="templates">Templates</a> : null}
      {screen.isAdmin ? <a href="#wallet" data-section="wallet">Wallet</a> : null}
    </nav>

    {screen.errorMessage !== null ? <Alert>{screen.errorMessage}</Alert> : null}

    <section aria-labelledby="counts-heading" className="comms-counts-section">
      <h2 id="counts-heading" className="sr-only">Counts</h2>
      <div className="cl-metrics comms-counts">
        {STATUS_ORDER.map((status) => <div key={status} className="cl-metric">
          <span className="cl-eyebrow">{STATUS_LABELS[status]}</span>
          <span className="cl-metric-value tabular-nums">{screen.statusCounts[status]}</span>
          <small>{status === 'failed' ? <>{STATUS_LABELS.opted_out}: <span className="tabular-nums">{screen.statusCounts.opted_out}</span></> : COUNT_CAPTIONS[status]}</small>
        </div>)}
      </div>
    </section>

    <section id="log" aria-labelledby="messages-heading" className="cl-section comms-anchor">
      <div className="cl-section-head">
        <h2 id="messages-heading" className="cl-section-title">Recent messages</h2>
        {screen.rows.length > MESSAGE_LOG_PREVIEW_ROWS
          ? <a href={logQuery(!showAll)} className="cl-btn cl-btn--quiet">{showAll ? `Show latest ${MESSAGE_LOG_PREVIEW_ROWS}` : `Show all ${screen.rows.length}`}</a>
          : null}
      </div>
      {screen.rows.length === 0 && screen.errorMessage === null
        ? <div className="cl-empty"><strong>No messages match these filters.</strong><p>Change the channel filter or check back after the next renewal run.</p></div>
        : null}
      {screen.rows.length === 0 ? null : <div className="cl-ledger-wrap">
        <table className={`cl-ledger comms-log${showAll ? '' : ' comms-log--preview'}`}>
          <thead><tr>
            <th scope="col">Member</th><th scope="col">Channel</th><th scope="col">Type</th><th scope="col">When</th><th scope="col">Status</th><th scope="col"><span className="sr-only">Action</span></th>
          </tr></thead>
          <tbody>
            {visibleRows.map((row) => <tr key={row.id}>
              <td className="comms-log-member">{row.memberName}</td>
              <td className="comms-log-fact">{say(row.channel)}</td>
              <td className="comms-log-fact">{say(row.category)}</td>
              <td className="comms-log-fact tabular-nums">{row.sentAt !== null
                ? <time dateTime={row.sentAt}>{formatDateTime(row.sentAt, DEFAULT_TIMEZONE)}</time>
                : <>Due <time dateTime={row.scheduledFor}>{formatDateTime(row.scheduledFor, DEFAULT_TIMEZONE)}</time></>}</td>
              <td className="comms-log-status">
                <StatusWord status={row.status} label={rowLabel(row)} />
                {row.failedReason !== null ? <span className="cl-row-meta">Failed: {say(row.failedReason)}</span> : null}
                {row.optedOutReason !== null ? <span className="cl-row-meta">Opted out: {say(row.optedOutReason)}</span> : null}
              </td>
              <td className="comms-log-action">{canOpenWhatsApp(row) ? <WhatsAppOpenButton notificationId={row.id} /> : null}</td>
            </tr>)}
          </tbody>
        </table>
      </div>}
    </section>

    <section id="consent" aria-labelledby="consent-heading" className="cl-section comms-anchor comms-band">
      <div className="comms-band-intro">
        <h2 id="consent-heading" className="cl-section-title">Consent</h2>
        <p className="cl-muted">Record a member's marketing or service consent decision. Find them by phone, then record what they agreed to.</p>
      </div>
      <div className="comms-band-body">
        {!screen.isPreview ? <form action="/messages" method="get" className="cl-form">
          {params.channel ? <input type="hidden" name="channel" value={params.channel} /> : null}
          <div className="comms-search">
            <label className="cl-field"><span>Find member by phone</span>
              <input type="search" name="q" defaultValue={params.q ?? ''} placeholder="Last four digits or full phone" className="cl-input" />
            </label>
            <button type="submit" className="cl-btn">Search members</button>
          </div>
        </form> : null}
        {screen.memberSearchError ? <Alert>Member search could not be loaded.</Alert> : null}
        <ConsentForm key={`${params.q ?? ''}:${params.memberCursor ?? ''}`} members={screen.members} />
        {screen.memberNextCursor ? <a className="cl-btn cl-btn--quiet mt-3" href={`/messages?${nextMemberQuery.toString()}`}>More members</a> : null}
      </div>
    </section>

    {screen.isAdmin ? <section id="templates" aria-labelledby="templates-heading" className="cl-section comms-anchor">
      <div className="cl-section-head"><h2 id="templates-heading" className="cl-section-title">Message templates</h2></div>
      {screen.templates.length === 0 ? <div className="cl-empty"><strong>No templates yet.</strong><p>Create the first one below.</p></div> : <div className="comms-templates">
        <div className="comms-template-head" aria-hidden="true"><span>Template</span><span>Channel</span><span>Locale</span><span>State</span><span /></div>
        {screen.templates.map((template, index) => <details key={template.id} className="comms-template" open={index === 0}>
          <summary>
            <span className="comms-template-name">{say(template.key)}</span>
            <span className="comms-template-fact">{say(template.channel)}</span>
            <span className="comms-template-fact">{language(template.locale)}</span>
            <StatusWord status={template.isActive ? 'active' : 'inactive'} label={template.isActive ? 'Active' : 'Off'} />
            <span className="comms-template-toggle" aria-hidden="true">Edit</span>
          </summary>
          <div className="comms-template-panel">
            <p className="comms-preview">{preview(template.body)}</p>
            {variables(template.body).length > 0 ? <p className="cl-hint">Variables: {variables(template.body).join(', ')}. The preview uses sample values.</p> : null}
            <MessageTemplateForm template={template} />
          </div>
        </details>)}
      </div>}
      <div className="comms-band comms-new-template">
        <div className="comms-band-intro">
          <h3 className="cl-eyebrow">New template</h3>
          <p className="cl-muted">Write the message once; the variables fill in for each member when it is sent.</p>
        </div>
        <div className="comms-band-body"><MessageTemplateForm /></div>
      </div>
    </section> : null}

    {screen.isAdmin ? <section id="wallet" aria-labelledby="wallet-heading" className="cl-section comms-anchor comms-band">
      <div className="comms-band-intro">
        <h2 id="wallet-heading" className="cl-section-title">Wallet</h2>
        <p className="cl-muted">Only a platform administrator can adjust this balance.</p>
      </div>
      <dl className="cl-dl comms-band-body">
        <dt>Balance</dt><dd><span className="tabular-nums">{screen.walletBalanceCredits ?? 'Unavailable'}</span> credits</dd>
      </dl>
    </section> : null}
  </main>;
}
