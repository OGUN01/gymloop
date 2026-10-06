import { createElement, isValidElement, type ReactNode } from 'react';
import { businessNouns, UI_TOKENS } from '@gymloop/shared';
import { describe, expect, it, vi } from 'vitest';

// SLF native member surface, visible suite (red until built).
// FROZEN CONTRACT: openspec/changes/member-self-service/proposal.md
// (SLF-001/002/016/017/018) + docs/design/v2/slf-bar.md criteria 1-4, 7, 9.
// Planned interface this suite pins (implementation must satisfy it):
//   MemberFreezeBody from ../../components/freeze-requests with
//     state: { phase: 'ready' | 'loading' | 'error'; offline: boolean;
//       loadedAt: string | null; membership: { planName: string | null;
//       status: string; startsOn: string; endsOn: string | null;
//       recordedAgreedPricePaise: string | null; currency: string } | null;
//       requests: Array<{ id: string; status: 'requested' | 'desk_submitted' |
//       'approved' | 'rejected' | 'cancelled' | 'expired'; startsOn: string;
//       endsOn: string; reason: string; decisionReason: string | null;
//       effective: 'scheduled' | 'paused' | 'completed' | null }> }
//     copy: ReturnType<typeof freezeRequestCopy> (planned shared export)
//     nouns: ReturnType<typeof businessNouns>
//     timeZone: string
//     onRetry: () => void
// Central IA stays Home · Classes · Shop · Activity · You: this body mounts
// inside the existing Gym/You surfaces and must render no tab chrome.
const host = (name: string) => (props: unknown) => {
  const fields = props && typeof props === 'object' ? props as Record<string, unknown> : { children: props };
  return createElement(name, fields, fields.children as ReactNode);
};
vi.mock('react-native', () => ({ View: host('view'), Text: host('text'), ActivityIndicator: host('loading'), StyleSheet: { create: (value: unknown) => value, hairlineWidth: 1 } }));
vi.mock('../mobile-context', () => ({ useMobile: () => ({ palette: UI_TOKENS.colors.light, nouns: businessNouns('gym') }) }));
vi.mock('../../components/ui', () => new Proxy({}, {
  get: (_target, name) => name === 'then' ? undefined : name === 'FONT' ? new Proxy({}, { get: () => 'test-font' }) : host(String(name)),
  has: () => true,
}));
const nouns = businessNouns('gym');
const membership = { planName: 'Monthly Unlimited', status: 'active', startsOn: '2026-09-01', endsOn: '2026-12-31', recordedAgreedPricePaise: '150000', currency: 'INR' };
const request = (over: Partial<Record<string, unknown>> = {}) => ({
  id: '81100000-0000-4000-8000-000000000001',
  status: 'requested',
  startsOn: '2026-10-10',
  endsOn: '2026-10-17',
  reason: 'Family trip out of station',
  decisionReason: null,
  effective: null,
  ...over,
});
const state = (over: Record<string, unknown> = {}) => ({ phase: 'ready', offline: false, loadedAt: '2026-10-03T09:00:00Z', membership, requests: [], ...over });
const { MemberFreezeBody } = await import('../../components/freeze-requests');
const { freezeRequestCopy } = (await import('@gymloop/shared')) as { freezeRequestCopy: (n: typeof nouns) => Record<string, string> };
const copy = freezeRequestCopy(nouns);
function text(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(text).join(' ');
  if (typeof node === 'string' || typeof node === 'number') return String(node);
  if (!isValidElement<Record<string, unknown>>(node)) return '';
  if (typeof node.type === 'function') return text((node.type as (props: unknown) => ReactNode)(node.props));
  return text(node.props.children as ReactNode);
}
const render = (over: Record<string, unknown> = {}) => text(createElement(MemberFreezeBody as never, { state: state(), copy, nouns, timeZone: 'Asia/Kolkata', onRetry: () => undefined, ...over } as never));

describe('SLF native member surface (red until built)', () => {
  it('SLF-001 discloses held plan, recorded sold price with currency and actual inclusive dates', () => {
    const rendered = render({});
    expect(rendered).toContain('Monthly Unlimited');
    expect(rendered).toMatch(/₹1,500/);
    // NAVC-012 changes displayed date copy only; the new route test pins
    // the unchanged ISO input command sent to the existing Freeze hook.
    expect(rendered).toMatch(/1\s+(?:Sep|Sept|September)|(?:Sep|Sept|September)\s+1/i);
    expect(rendered).toMatch(/31\s+(?:Dec|December)|(?:Dec|December)\s+31/i);
  });

  it('bar 2 shows the frozen request copy with the business noun and the requested interval', () => {
    const rendered = render({ state: state({ requests: [request()] }) });
    expect(rendered).toMatch(/This is a request\. Your gym must approve it\./);
    expect(rendered).toMatch(/10\s+(?:Oct|October)|(?:Oct|October)\s+10/i);
    expect(rendered).toMatch(/17\s+(?:Oct|October)|(?:Oct|October)\s+17/i);
  });

  it('SLF-018 renders awaiting-desk-adoption, awaiting-approval, scheduled, paused, completed, cancelled, rejected and expired distinctly', () => {
    const rendered = render({
      state: state({
        requests: [
          request({ id: '81100000-0000-4000-8000-000000000002', status: 'requested' }),
          request({ id: '81100000-0000-4000-8000-000000000003', status: 'desk_submitted' }),
          request({ id: '81100000-0000-4000-8000-000000000004', status: 'approved', effective: 'scheduled' }),
          request({ id: '81100000-0000-4000-8000-000000000005', status: 'approved', effective: 'paused' }),
          request({ id: '81100000-0000-4000-8000-000000000006', status: 'approved', effective: 'completed' }),
          request({ id: '81100000-0000-4000-8000-000000000007', status: 'cancelled' }),
          request({ id: '81100000-0000-4000-8000-000000000008', status: 'rejected', decisionReason: 'Peak month' }),
          request({ id: '81100000-0000-4000-8000-000000000009', status: 'expired' }),
        ],
      }),
    });
    expect(rendered).toMatch(/Awaiting desk adoption/i);
    expect(rendered).toMatch(/Awaiting approval/i);
    expect(rendered).toMatch(/Scheduled/);
    expect(rendered).toMatch(/Paused/);
    expect(rendered).toMatch(/Completed/);
    expect(rendered).toMatch(/Cancelled/);
    expect(rendered).toMatch(/Rejected/);
    expect(rendered).toContain('Peak month');
    expect(rendered).toMatch(/Expired/);
  });

  it('SLF-002 a pending membership keeps reads but disables freeze and renewal with a desk path, and invents no member pending status', () => {
    const rendered = render({ state: state({ membership: { ...membership, status: 'pending' }, requests: [request()] }) });
    expect(rendered).toMatch(/desk|front office|contact your gym/i);
    expect(rendered).toContain('Monthly Unlimited');
    expect(rendered).not.toMatch(/account is pending/i);
  });

  it('SLF-017 offline shows last-good data with its fetched time and no queueing', () => {
    const rendered = render({ state: state({ offline: true, requests: [request({ status: 'desk_submitted' })] }) });
    expect(rendered).toMatch(/offline/i);
    expect(rendered).toMatch(/2026-10-03T09:00|fetched|last (loaded|updated)/i);
    expect(rendered).not.toMatch(/queued|will send when (back )?online/i);
  });

  // NAVC-012 cheap native copy, owner-approved 2026-10-06: the formerly
  // rendered internal route becomes friendly renewal help. The existing
  // contextual Buy destination is independently covered by NAVC-007/008.
  it('SLF-016 keeps friendly renewal and Buy help without leaking an internal route', () => {
    const rendered = render({});
    expect(rendered).toMatch(/renew|buy|purchase requests/i);
    expect(rendered).not.toMatch(/\/(?:member|api)\//);
  });

  it('bar 9: touch targets are at least 48dp and no tab chrome is rendered', () => {
    const tree = createElement(MemberFreezeBody as never, { state: state({ requests: [request()] }), copy, nouns, timeZone: 'Asia/Kolkata', onRetry: () => undefined });
    const sizes: Array<[number | undefined, number | undefined]> = [];
    const visit = (node: ReactNode): void => {
      if (Array.isArray(node)) { node.forEach(visit); return; }
      if (!isValidElement<Record<string, unknown>>(node)) return;
      if (typeof node.type === 'function') { visit((node.type as (props: unknown) => ReactNode)(node.props)); return; }
      const style = node.props.style;
      if (style && typeof style === 'object' && 'minHeight' in (style as Record<string, unknown>)) {
        sizes.push([(style as Record<string, unknown>).minWidth as number | undefined, (style as Record<string, unknown>).minHeight as number | undefined]);
      }
      visit(node.props.children as ReactNode);
    };
    visit(tree);
    for (const [width, height] of sizes) {
      if (width !== undefined) expect(width).toBeGreaterThanOrEqual(48);
      if (height !== undefined) expect(height).toBeGreaterThanOrEqual(48);
    }
    expect(text(tree)).not.toMatch(/^(Home|Classes|Shop|Activity|You)$/m);
  });
});
