import { loadMessages, type MessageListRow, type MessageStatusCounts } from '../../../lib/messages';
import { ConsentForm, MessageTemplateForm, WhatsAppOpenButton } from './message-forms';

/**
 * The staff `/messages` screen (contract §4): scheduled/sent/delivered/
 * failed/opted-out rows and their drill-down counts from one snapshot, a
 * consent action every front-office role can use, and — gym admin only — a
 * template list and the wallet balance. The loader has already refused every
 * identity that is not real front office or a support preview, so this
 * component renders only what a verified caller can see.
 */

const STATUS_ORDER: (keyof MessageStatusCounts)[] = ['scheduled', 'sent', 'delivered', 'failed', 'opted_out'];
const STATUS_LABELS: Record<keyof MessageStatusCounts, string> = {
  scheduled: 'Scheduled', sent: 'Sent', delivered: 'Delivered', failed: 'Failed', opted_out: 'Opted out',
};

/** A row's status, in the desk's words — a WhatsApp child is always "Opened in WhatsApp" (contract §5), never its own status label. */
function rowLabel(row: MessageListRow): string {
  if (row.channel === 'whatsapp_link') return 'Opened in WhatsApp';
  return STATUS_LABELS[row.status as keyof MessageStatusCounts] ?? row.status.replaceAll('_', ' ');
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

  return <main className="route-workspace">
    <header>
      <h1 className="text-2xl font-semibold">Messages</h1>
      <p className="mt-1 text-sm text-neutral-600">Every renewal, payment, fulfilment, promotion and motivation message this gym has queued or sent.</p>
    </header>

    {screen.errorMessage !== null
      ? <p role="alert" className="mt-4 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{screen.errorMessage}</p>
      : null}

    <section aria-labelledby="counts-heading" className="mt-6">
      <h2 id="counts-heading" className="text-lg font-semibold">Counts</h2>
      {screen.asOf !== null ? <p className="mt-1 text-sm text-neutral-600">Snapshot as of {screen.asOf}.</p> : null}
      <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-sm">
        {STATUS_ORDER.map((status) => <li key={status}>{STATUS_LABELS[status]}: <span className="tabular-nums">{screen.statusCounts[status]}</span></li>)}
      </ul>
    </section>

    <section aria-labelledby="messages-heading" className="mt-6">
      <h2 id="messages-heading" className="text-lg font-semibold">Messages</h2>
      {screen.rows.length === 0 && screen.errorMessage === null ? <p className="mt-2 text-sm text-neutral-600">No messages match these filters.</p> : null}
      <ul className="mt-3 space-y-3">
        {screen.rows.map((row) => <li key={row.id} className="rounded-lg border border-neutral-200 p-3 text-sm">
          <p className="font-medium">{row.memberName} · {row.channel} · {row.category}</p>
          <p className="mt-1 text-neutral-700">{rowLabel(row)}</p>
          {row.failedReason !== null ? <p className="text-neutral-700">Failed: {row.failedReason}</p> : null}
          {row.optedOutReason !== null ? <p className="text-neutral-700">Opted out: {row.optedOutReason}</p> : null}
          {canOpenWhatsApp(row) ? <WhatsAppOpenButton notificationId={row.id} /> : null}
        </li>)}
      </ul>
    </section>

    <section aria-labelledby="consent-heading" className="mt-8">
      <h2 id="consent-heading" className="text-lg font-semibold">Consent</h2>
      <p className="mt-1 text-sm text-neutral-600">Record a member's marketing or service consent decision.</p>
      {!screen.isPreview ? <form action="/messages" method="get" className="mt-3 flex flex-wrap items-end gap-2">
        {params.channel ? <input type="hidden" name="channel" value={params.channel} /> : null}
        <label className="grid gap-1 text-sm">Find member by phone
          <input type="search" name="q" defaultValue={params.q ?? ''} placeholder="Last four digits or full phone" className="min-h-11 rounded-lg border border-neutral-400 px-3" />
        </label>
        <button type="submit" className="min-h-11 rounded-lg border border-neutral-400 px-4">Search members</button>
      </form> : null}
      {screen.memberSearchError ? <p role="alert" className="mt-2 text-sm text-red-700">Member search could not be loaded.</p> : null}
      <ConsentForm key={`${params.q ?? ''}:${params.memberCursor ?? ''}`} members={screen.members} />
      {screen.memberNextCursor ? <a className="mt-3 inline-block text-sm underline" href={`/messages?${nextMemberQuery.toString()}`}>More members</a> : null}
    </section>

    {screen.isAdmin ? <section aria-labelledby="templates-heading" className="mt-8">
      <h2 id="templates-heading" className="text-lg font-semibold">Message templates</h2>
      <ul className="mt-2 space-y-2 text-sm">
        {screen.templates.map((template) => <li key={template.id} className="rounded-lg border border-neutral-200 p-3">
          <p className="font-medium">{template.key} · {template.channel} · {template.locale} · {template.category}</p>
          <p className="mt-1 text-neutral-700">{template.body}</p>
          <MessageTemplateForm template={template} />
        </li>)}
      </ul>
      <h3 className="mt-4 font-semibold">New template</h3>
      <MessageTemplateForm />
    </section> : null}

    {screen.isAdmin ? <section aria-labelledby="wallet-heading" className="mt-8">
      <h2 id="wallet-heading" className="text-lg font-semibold">Wallet</h2>
      <p className="mt-1 text-sm">Balance: <span className="tabular-nums">{screen.walletBalanceCredits ?? 'Unavailable'}</span> credits</p>
      <p className="mt-1 text-sm text-neutral-600">Only a platform administrator can adjust this balance.</p>
    </section> : null}
  </main>;
}
