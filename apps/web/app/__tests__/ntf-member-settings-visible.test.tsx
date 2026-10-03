import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

// Implementation-blind NTF member web surface (NTF-016): category settings on
// You, web push explicitly unavailable, inbox untouched by push state.
// FROZEN CONTRACT: proposal.md NTF-016/NTF-015/NTF-002/NTF-013,
// pre-configuration-amendment.md (provider_unconfigured copy), serial
// declarations (readMemberPushSettings envelope: {preferences, devices}).
vi.mock('next-themes', () => ({ useTheme: () => ({ theme: 'light', setTheme: vi.fn() }) }));
vi.mock('next/link', () => ({ default: (props: Record<string, unknown>) => ({ type: 'a', props }) }));
const id = '78100000-0000-4000-8000-000000000001';
const nouns = { place: 'gym', plural: 'gyms', member: 'member', trainer: 'trainer', class: 'class' } as const;
const profile = { id, fullName: 'Fixture Member', phone: '+918000000000', memberSince: '2026-01-01', status: 'active' };
const membership = { planName: 'Monthly', statusText: 'Active', validUntil: '2026-12-01T00:00:00Z', gymId: id, gymName: 'Fixture Gym' };
let screen: () => unknown;
beforeEach(async () => {
  vi.resetModules();
  ({ default: screen } = await import('../member/you-settings'));
});
const html = () => renderToStaticMarkup(createElement(screen as never, { profile, membership, nouns } as never));

describe('NTF member web push settings section (red until built)', () => {
  it('renders a Notifications section with all seven DB categories and the missing-row default', () => {
    const page = html();
    expect(page).toMatch(/Notifications/i);
    for (const category of ['renewal', 'payment', 'fulfilment', 'promotion', 'motivation', 'class_update', 'announcement']) {
      expect(page).toContain(category);
    }
    expect(page).toMatch(/off by default|enabled by default|default/i);
  });
  it('never renders a device token, installation id or guardian contact', () => {
    const page = html().replace(new RegExp(id.replace(/-/g, '[-]?'), 'g'), 'UUID');
    expect(page).not.toMatch(/token|installation|guardian/i);
  });
  it('states web push is explicitly unavailable on this browser', () => {
    expect(html()).toMatch(/Web push isn't available|use the (FitCruxx|mobile) app/i);
  });
  it('only ever triggers a permission prompt from a member action, never on render', () => {
    const page = html();
    expect(page).toMatch(/Notifications/i);
    // No auto-prompt: the rendered output must carry the ask behind an explicit control.
    expect(page).toMatch(/(Enable|Turn on)[^<]{0,80}(notifications|permission)/i);
  });
  it('shows the unconfigured-provider truth, not a fake device state (pre-configuration amendment)', () => {
    expect(html()).toMatch(/Push isn't configured\. Updates remain in the app\./);
  });
  it('shows current devices with safe facts only (last seen, active)', () => {
    const page = html();
    expect(page).toMatch(/last\s*seen|Last seen/i);
    expect(page).toMatch(/active/i);
    expect(page.replace(new RegExp(id.replace(/-/g, '[-]?'), 'g'), 'UUID')).not.toMatch(/fcm|token/i);
  });
});
