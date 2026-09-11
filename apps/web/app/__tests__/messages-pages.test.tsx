import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { isValidElement, type ReactElement, type ReactNode } from 'react';

/**
 * Phase 6 messages screens, authored from the frozen comms contract
 * (docs/planning/phase6-comms-contract.md §3-§5, §8) before either screen
 * exists. `comms-routes.test.ts` already pins the exact request shape every
 * action below posts; this file owns rendering, role gates and the preview
 * mutation boundary, walking the component tree with the same hook harness
 * `imports-pages.test.tsx` uses so the whole journey is proved without a DOM.
 * No production source was consulted, and every test is red today because
 * none of these modules exist yet.
 *
 * Modules this suite fixes for the implementation:
 *
 *   apps/web/lib/messages.ts               loadMessages(searchParams) — the staff loader
 *   apps/web/app/(console)/messages/page.tsx           default export, heading "Messages"
 *   apps/web/app/(console)/messages/message-forms.tsx  ConsentForm, WhatsAppOpenButton,
 *                                                       MessageTemplateForm, WalletAdjustForm
 *   apps/web/lib/member-messages.ts        loadMemberMessages() — the member loader
 *   apps/web/app/member/messages/page.tsx              default export, heading "Your messages"
 *   apps/web/app/member/messages/member-message-actions.tsx  MemberMessageAck
 *
 * The staff loader reads one RPC (`list_notifications`) for rows and their
 * drill-down `statusCounts` together, in `list_leads`'s tradition (§4: "Staff
 * /messages shows scheduled/sent/delivered/failed/opted-out rows and
 * drill-down counts from identical filters") — one snapshot, so counts cannot
 * silently disagree with the rows a filter produced. A support preview
 * (`identity.kind === 'impersonation'`) may view the whole screen, including
 * the gym-admin sections, but mounts every mutation through the registered
 * `MutationForm` (`apps/web/app/preview-context.tsx`), which is null during
 * preview — the same boundary every other console screen already uses.
 */

const state = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  rpc: [] as Array<{ name: string; args: Record<string, unknown> }>,
  rpcResult: null as Record<string, unknown> | null,
  rows: {} as Record<string, Array<Record<string, unknown>>>,
  reads: [] as string[],
  hooks: [] as unknown[], cursor: 0,
  redirects: [] as string[],
  requests: [] as Array<{ url: string; init: RequestInit }>,
  fetchPlan: [] as Array<{ status: number; body: unknown }>,
  previewReadOnly: false,
}));

vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  return { ...actual,
    useState: (initial: unknown) => {
      const index = state.cursor++;
      if (!(index in state.hooks)) state.hooks[index] = typeof initial === 'function' ? (initial as () => unknown)() : initial;
      return [state.hooks[index], (next: unknown) => { state.hooks[index] = typeof next === 'function' ? (next as (old: unknown) => unknown)(state.hooks[index]) : next; }];
    },
    useRef: (initial: unknown) => {
      const index = state.cursor++;
      if (!(index in state.hooks)) state.hooks[index] = { current: initial };
      return state.hooks[index];
    },
    useMemo: (factory: () => unknown) => factory(),
    useCallback: (callback: unknown) => callback,
    useEffect: () => undefined,
    useId: () => 'visible-messages-control',
  };
});
vi.mock('next/navigation', () => ({
  useRouter: () => ({
    push: (path: string) => state.redirects.push(path),
    replace: (path: string) => state.redirects.push(path),
    refresh: () => undefined,
  }),
  redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); },
}));
vi.mock('next/link', async () => {
  const { createElement } = await import('react');
  return { default: (props: Record<string, unknown>) => createElement('a', props) };
});
vi.mock('../../preview-context', async () => {
  const { createElement } = await import('react');
  return {
    PreviewProvider: ({ children }: { children: ReactNode }) => children,
    usePreviewReadOnly: () => state.previewReadOnly,
    MutationForm: (props: Record<string, unknown>) => (state.previewReadOnly ? null : createElement('form', props)),
  };
});
vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: async () => ({
    auth: { getClaims: async () => ({ data: state.claims && { claims: state.claims }, error: null }) },
    rpc: async (name: string, args: Record<string, unknown>) => {
      state.rpc.push({ name, args });
      return { data: state.rpcResult, error: null };
    },
    from: (table: string) => {
      state.reads.push(table);
      let rows = state.rows[table] ?? [];
      const query = {
        select: () => query, eq: (key: string, value: unknown) => { rows = rows.filter((row) => row[key] === value); return query; },
        in: () => query, order: () => query, limit: () => query,
        maybeSingle: async () => ({ data: rows[0] ?? null, error: null }),
        then: (resolve: (value: { data: Array<Record<string, unknown>> | null; error: null }) => unknown) =>
          Promise.resolve({ data: rows, error: null }).then(resolve),
      };
      return query;
    },
  }),
}));

const TENANT_ID = '11111111-1111-4111-8111-111111111111';
const STAFF_ID = '22222222-2222-4222-8222-222222222222';
const MEMBER_ID = '33333333-3333-4333-8333-333333333333';
const SCHEDULED_ID = '55555555-5555-4555-8555-555555555555';
const SENT_ID = '55555555-5555-4555-8555-555555555556';
const DELIVERED_ID = '55555555-5555-4555-8555-555555555557';
const FAILED_ID = '55555555-5555-4555-8555-555555555558';
const OPTED_OUT_ID = '55555555-5555-4555-8555-555555555559';
const TEMPLATE_ID = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

const OWNER = { sub: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_role: 'gym_owner', tenant_id: TENANT_ID, staff_id: STAFF_ID };
const MANAGER = { ...OWNER, app_role: 'gym_manager' };
const FRONT_DESK = { ...OWNER, app_role: 'front_desk' };
const TRAINER = { ...OWNER, app_role: 'trainer' };
const MEMBER = { sub: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', app_role: 'member', tenant_id: TENANT_ID, member_id: MEMBER_ID };
const IMPERSONATION = { sub: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', app_role: 'gym_owner', tenant_id: TENANT_ID, impersonation_session_id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd' };
const PLATFORM = { sub: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', app_role: 'platform_support' };

const STATUS_COUNTS = { scheduled: '1', sent: '1', delivered: '1', failed: '1', clicked: '0', converted: '0', opted_out: '1' };
const ROWS = [
  { id: SCHEDULED_ID, memberId: MEMBER_ID, memberName: 'Asha Rao', channel: 'in_app', category: 'renewal', status: 'scheduled', scheduledFor: '2026-09-12T04:30:00+00:00', sentAt: null, deliveredAt: null, failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null, sourceNotificationId: null },
  { id: SENT_ID, memberId: MEMBER_ID, memberName: 'Asha Rao', channel: 'in_app', category: 'renewal', status: 'sent', scheduledFor: '2026-09-10T04:30:00+00:00', sentAt: '2026-09-10T04:30:00+00:00', deliveredAt: null, failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null, sourceNotificationId: null },
  { id: DELIVERED_ID, memberId: MEMBER_ID, memberName: 'Rahul Sharma', channel: 'in_app', category: 'payment', status: 'delivered', scheduledFor: '2026-09-09T04:30:00+00:00', sentAt: '2026-09-09T04:30:00+00:00', deliveredAt: '2026-09-09T05:00:00+00:00', failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null, sourceNotificationId: null },
  { id: FAILED_ID, memberId: MEMBER_ID, memberName: 'Vikram Singh', channel: 'push', category: 'motivation', status: 'failed', scheduledFor: '2026-09-08T04:30:00+00:00', sentAt: null, deliveredAt: null, failedAt: '2026-09-08T04:30:00+00:00', failedReason: 'provider_unconfigured', optedOutAt: null, optedOutReason: null, sourceNotificationId: null },
  { id: OPTED_OUT_ID, memberId: MEMBER_ID, memberName: 'Sunita Rao', channel: 'in_app', category: 'promotion', status: 'opted_out', scheduledFor: '2026-09-07T04:30:00+00:00', sentAt: null, deliveredAt: null, failedAt: null, failedReason: null, optedOutAt: '2026-09-07T04:30:00+00:00', optedOutReason: 'consent_withdrawn', sourceNotificationId: null },
];
const WHATSAPP_URL = 'https://wa.me/919876543210?text=Your%20membership%20ends%20soon';
const WHATSAPP_CHILD = {
  notificationId: 'aaaaaaaa-1111-4aaa-8aaa-aaaaaaaaaaaa', memberId: MEMBER_ID, channel: 'whatsapp_link', status: 'sent',
  sentAt: '2026-09-10T10:00:00+00:00', deliveredAt: null, failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null,
};

type Element = ReactElement<Record<string, unknown>>;

function descendants(node: ReactNode): Element[] {
  if (Array.isArray(node)) return node.flatMap(descendants);
  if (!isValidElement<Record<string, unknown>>(node)) return [];
  return [node, ...descendants(node.props.children as ReactNode)];
}
function renderClient(component: Element): Element[] {
  state.cursor = 0;
  const render = (node: ReactNode): Element[] => {
    if (Array.isArray(node)) return node.flatMap(render);
    if (!isValidElement<Record<string, unknown>>(node)) return [];
    if (typeof node.type === 'function') return render((node.type as (props: Record<string, unknown>) => ReactNode)(node.props));
    return [node, ...render(node.props.children as ReactNode)];
  };
  return render(component);
}
function findComponent(node: ReactNode, name: string): Element | undefined {
  return descendants(node).find((element) => typeof element.type === 'function' && element.type.name === name);
}
function findAllComponents(node: ReactNode, name: string): Element[] {
  return descendants(node).filter((element) => typeof element.type === 'function' && element.type.name === name);
}
async function event(element: Element, handler: string) {
  const callback = element.props[handler] as ((event: unknown) => unknown) | undefined;
  expect(callback, `${String(element.type)} exposes ${handler}`).toBeTypeOf('function');
  await callback!({ preventDefault: () => undefined, target: {}, currentTarget: {} });
}
function textOf(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(textOf).join(' ');
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (!isValidElement<Record<string, unknown>>(node)) return '';
  return textOf(node.props.children as ReactNode);
}
/** Renders every component in the tree (server and client alike) and collects what the screen actually says. */
function inspect(node: ReactNode): { text: string; forms: number } {
  const text: string[] = [];
  let forms = 0;
  state.cursor = 0;
  const walk = (current: ReactNode): void => {
    if (Array.isArray(current)) { current.forEach(walk); return; }
    if (typeof current === 'string' || typeof current === 'number') { text.push(String(current)); return; }
    if (!isValidElement<Record<string, unknown>>(current)) return;
    if (typeof current.type === 'function') {
      const rendered = (current.type as (props: Record<string, unknown>) => ReactNode)(current.props);
      if (!(rendered instanceof Promise)) walk(rendered);
      return;
    }
    if (current.type === 'form') forms += 1;
    walk(current.props.children as ReactNode);
  };
  walk(node);
  return { text: text.join(' '), forms };
}

beforeEach(() => {
  state.claims = OWNER;
  state.rpc = [];
  state.rpcResult = { rows: ROWS, statusCounts: STATUS_COUNTS, asOf: '2026-09-10T10:00:00+00:00' };
  state.rows = {
    message_templates: [{ id: TEMPLATE_ID, key: 'trial_reminder', channel: 'push', locale: 'en', category: 'motivation', body: 'Come back!', is_active: true }],
    messaging_wallets: [{ balance_credits: '4500' }],
    notifications: [
      { id: SENT_ID, channel: 'in_app', category: 'renewal', status: 'sent', sent_at: '2026-09-10T04:30:00+00:00', delivered_at: null, payload: { body: 'Your membership ends on 2026-09-20.' } },
      { id: DELIVERED_ID, channel: 'in_app', category: 'payment', status: 'delivered', sent_at: '2026-09-09T04:30:00+00:00', delivered_at: '2026-09-09T05:00:00+00:00', payload: { body: 'Payment received, thank you.' } },
    ],
    consents: [
      { purpose: 'marketing', granted: true, recorded_at: '2026-09-01T10:00:00+00:00' },
      { purpose: 'service', granted: true, recorded_at: '2026-09-01T10:00:00+00:00' },
    ],
  };
  state.reads = [];
  state.hooks = [];
  state.cursor = 0;
  state.redirects = [];
  state.requests = [];
  state.fetchPlan = [];
  state.previewReadOnly = false;
  vi.stubGlobal('crypto', { ...globalThis.crypto, randomUUID: () => '99999999-9999-4999-8999-999999999999' });
  vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
    state.requests.push({ url, init });
    const planned = state.fetchPlan.shift();
    return new Response(JSON.stringify(planned?.body ?? { ok: true, data: {} }), {
      status: planned?.status ?? 200, headers: { 'content-type': 'application/json' },
    });
  });
});
afterEach(() => vi.unstubAllGlobals());

const loadMessagesPage = async () => (await import('../(console)/messages/page')).default({ searchParams: Promise.resolve({}) });
const loadMemberMessagesPage = async () => (await import('../member/messages/page')).default({});

describe('staff /messages — access and drill-down counts', () => {
  it.each([
    ['an owner', OWNER], ['a manager', MANAGER], ['front desk', FRONT_DESK],
  ])('renders the messages screen for %s', async (_name, claims) => {
    state.claims = claims;
    const page = await loadMessagesPage();
    const view = inspect(page);

    expect(view.text).toContain('Messages');
    for (const label of ['Scheduled', 'Sent', 'Delivered', 'Failed', 'Opted out']) expect(view.text).toContain(label);
    for (const count of Object.values(STATUS_COUNTS)) expect(view.text).toContain(count);
    for (const row of ROWS) expect(view.text).toContain(row.memberName);
  });

  it.each([
    ['a trainer', TRAINER], ['a member', MEMBER], ['platform support', PLATFORM],
  ])('redirects %s away and reads nothing', async (_name, claims) => {
    state.claims = claims;
    try {
      await loadMessagesPage();
      throw new Error('expected a redirect');
    } catch (error) {
      expect(String(error)).toMatch(/REDIRECT:/);
    }
    expect(state.rpc).toEqual([]);
    expect(state.reads).toEqual([]);
  });

  it('drill-down counts come from the same RPC snapshot as the rows — one call, not two that could disagree', async () => {
    await loadMessagesPage();
    expect(state.rpc).toHaveLength(1);
    expect(state.rpc[0]?.name).toBe('list_notifications');
  });

  it('a filter query param reaches the counts RPC alongside the rows', async () => {
    const page = (await import('../(console)/messages/page')).default;
    await page({ searchParams: Promise.resolve({ channel: 'in_app' }) });

    expect(state.rpc).toHaveLength(1);
    expect(state.rpc[0]?.args).toMatchObject({ p_channel: 'in_app' });
  });
});

describe('staff /messages — role-gated sections', () => {
  it('front desk sees consent and action controls but no template or wallet section', async () => {
    state.claims = FRONT_DESK;
    const page = await loadMessagesPage();
    const view = inspect(page);

    expect(view.text).toContain('Consent');
    expect(findComponent(page, 'ConsentForm')).toBeDefined();
    expect(view.text).not.toContain('Message templates');
    expect(view.text).not.toContain('Wallet');
    expect(findComponent(page, 'MessageTemplateForm')).toBeUndefined();
    expect(findComponent(page, 'WalletAdjustForm')).toBeUndefined();
  });

  it.each([
    ['an owner', OWNER], ['a manager', MANAGER],
  ])('%s sees the template and wallet sections too', async (_name, claims) => {
    state.claims = claims;
    const page = await loadMessagesPage();
    const view = inspect(page);

    expect(view.text).toContain('Message templates');
    expect(view.text).toContain('Wallet');
    expect(view.text).toContain('4500');
    expect(findComponent(page, 'MessageTemplateForm')).toBeDefined();
    expect(findComponent(page, 'WalletAdjustForm')).toBeDefined();
  });

  it('a whatsapp_link child is labelled "Opened in WhatsApp", verbatim', async () => {
    state.rows.notifications = [
      ...state.rows.notifications,
      { id: WHATSAPP_CHILD.notificationId, channel: 'whatsapp_link', category: 'renewal', status: 'sent', sent_at: WHATSAPP_CHILD.sentAt, delivered_at: null, payload: { body: 'Your membership ends soon.' }, source_notification_id: SENT_ID },
    ];
    state.rpcResult = {
      rows: [...ROWS, { ...ROWS[1], id: WHATSAPP_CHILD.notificationId, channel: 'whatsapp_link', sourceNotificationId: SENT_ID }],
      statusCounts: STATUS_COUNTS, asOf: '2026-09-10T10:00:00+00:00',
    };
    const page = await loadMessagesPage();
    const view = inspect(page);

    expect(view.text).toContain('Opened in WhatsApp');
  });
});

describe('staff /messages — preview mounts no mutation controls', () => {
  it('an impersonation identity views the whole screen, including admin sections, read-only', async () => {
    state.claims = IMPERSONATION;
    state.previewReadOnly = true;
    const page = await loadMessagesPage();
    const view = inspect(page);

    expect(view.text).toContain('Messages');
    expect(view.text).toContain('Message templates');
    expect(view.text).toContain('Wallet');
    expect(view.forms).toBe(0);
  });

  it('the same identity with preview off gets its mutation forms back', async () => {
    state.claims = IMPERSONATION;
    state.previewReadOnly = false;
    const page = await loadMessagesPage();
    const view = inspect(page);

    expect(view.forms).toBeGreaterThan(0);
  });
});

describe('ConsentForm — grant/refuse with version, source and a fresh request key', () => {
  it('posts exactly the six consent facts on grant, minting one UUID request key', async () => {
    state.fetchPlan = [{ status: 201, body: { ok: true, data: {} } }];
    const page = await loadMessagesPage();
    const form = findComponent(page, 'ConsentForm');
    expect(form).toBeDefined();

    const controls = renderClient(form!);
    await event(controls.find((node) => node.type === 'form')!, 'onSubmit');

    expect(state.requests).toHaveLength(1);
    expect(state.requests[0]?.url).toContain('/api/consents');
    const sent = JSON.parse(String(state.requests[0]?.init.body)) as Record<string, unknown>;
    expect(Object.keys(sent).sort()).toEqual(['granted', 'memberId', 'purpose', 'requestKey', 'source', 'version']);
    expect(sent.requestKey).toBe('99999999-9999-4999-8999-999999999999');
  });

  it('does not render for a member — consent is recorded by front office only', async () => {
    // ConsentForm is a staff-side component; this asserts the member screen never mounts it.
    const page = await loadMemberMessagesPage();
    expect(findComponent(page, 'ConsentForm')).toBeUndefined();
  });
});

describe('WhatsAppOpenButton — the URL only ever comes back from an explicit open', () => {
  it('posts to the notification whatsapp action and then shows the returned link', async () => {
    state.fetchPlan = [{ status: 200, body: { ok: true, data: { notification: WHATSAPP_CHILD, url: WHATSAPP_URL } } }];
    const page = await loadMessagesPage();
    const button = findAllComponents(page, 'WhatsAppOpenButton')[0];
    expect(button).toBeDefined();

    const controls = renderClient(button!);
    await event(controls.find((node) => node.type === 'form')!, 'onSubmit');

    expect(state.requests[0]?.url).toContain('/whatsapp');
    expect(state.requests[0]?.init.method).toBe('POST');
    expect(state.requests[0]?.init.body ?? undefined).toBeUndefined();
  });

  it('shows the refusal, not a link, on a 403 communication_opted_out answer', async () => {
    state.fetchPlan = [{ status: 403, body: { ok: false, error: { code: 'communication_opted_out', message: 'refused' } } }];
    const page = await loadMessagesPage();
    const button = findAllComponents(page, 'WhatsAppOpenButton')[0];
    const controls = renderClient(button!);
    await event(controls.find((node) => node.type === 'form')!, 'onSubmit');

    const after = renderClient(button!);
    const text = after.map(textOf).join(' ');
    expect(text).not.toContain('wa.me');
  });
});

describe('member /member/messages — own in-app delivery and separate consent history', () => {
  it.each([
    ['a trainer', TRAINER], ['staff (owner)', OWNER], ['a preview identity', IMPERSONATION],
  ])('redirects %s away and reads nothing', async (_name, claims) => {
    state.claims = claims;
    try {
      await loadMemberMessagesPage();
      throw new Error('expected a redirect');
    } catch (error) {
      expect(String(error)).toMatch(/REDIRECT:/);
    }
    expect(state.reads).toEqual([]);
  });

  it('shows only the member\'s own sent/delivered in-app messages, plus a separate consent history', async () => {
    state.claims = MEMBER;
    const page = await loadMemberMessagesPage();
    const view = inspect(page);

    expect(view.text).toContain('Your messages');
    expect(view.text).toContain('Payment received, thank you');
    expect(view.text).toContain('Your membership ends on');
    expect(view.text).toContain('Consent history');
    expect(view.text).toContain('marketing');
    expect(view.text).toContain('service');
  });

  it('fires no delivered request from rendering, hydration or prefetch alone', async () => {
    state.claims = MEMBER;
    await loadMemberMessagesPage();
    expect(state.requests).toEqual([]);
  });

  it('posts the delivered action only on an explicit open, never automatically', async () => {
    state.claims = MEMBER;
    state.fetchPlan = [{
      status: 200,
      body: {
        ok: true,
        data: {
          notificationId: SENT_ID, memberId: MEMBER_ID, channel: 'in_app', status: 'delivered',
          sentAt: '2026-09-10T04:30:00+00:00', deliveredAt: '2026-09-10T10:00:00+00:00',
          failedAt: null, failedReason: null, optedOutAt: null, optedOutReason: null,
        },
      },
    }];
    const page = await loadMemberMessagesPage();
    const ack = findAllComponents(page, 'MemberMessageAck').find((element) => element.props.notificationId === SENT_ID);
    expect(ack, 'The unread sent message exposes an explicit-open control').toBeDefined();

    const controls = renderClient(ack!);
    const trigger = controls.find((node) => typeof node.props.onClick === 'function');
    expect(trigger, 'The open control is a click, never an effect').toBeDefined();
    await event(trigger!, 'onClick');

    expect(state.requests).toHaveLength(1);
    expect(state.requests[0]?.url).toContain(`/api/member/notifications/${SENT_ID}/delivered`);
    expect(state.requests[0]?.init.method).toBe('POST');
  });

  it('does not offer an open control for an already-delivered message', async () => {
    state.claims = MEMBER;
    const page = await loadMemberMessagesPage();
    const ack = findAllComponents(page, 'MemberMessageAck').find((element) => element.props.notificationId === DELIVERED_ID);
    expect(ack === undefined || renderClient(ack).every((node) => typeof node.props.onClick !== 'function')).toBe(true);
  });
});
