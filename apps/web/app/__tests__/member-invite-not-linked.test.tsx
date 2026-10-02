import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

/**
 * INV (web /not-linked, plus the one /privacy sentence INV-023 adds): the
 * not-linked page keeps every sentence it already had and gains exactly one
 * more — open the invite link your gym sent you, then sign in — with no input
 * field. The forbidden-phrase and identifier lists are the ones
 * `phase9-android-not-linked-legal.test.ts` pins for the Android screen: a
 * not-linked page must not say whether an account or a link exists, and must
 * not print identity details.
 */

const state = vi.hoisted(() => ({
  signedIn: true,
  identity: { kind: 'unlinked' } as Record<string, unknown>,
}));

vi.mock('next/cache', () => ({ revalidatePath: vi.fn() }));
vi.mock('next/navigation', () => ({
  redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); },
}));
vi.mock('next/headers', () => ({
  headers: async () => new Headers(),
  cookies: async () => ({ get: () => undefined, has: () => false, getAll: () => [] }),
}));
vi.mock('next/image', () => ({
  default: (props: { src?: string; alt?: string }) => createElement('img', { src: props.src, alt: props.alt ?? '' }),
}));
vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: async () => ({
    auth: { signOut: async () => ({ error: null }) },
    from: () => { throw new Error('not-linked reads no tables'); },
    rpc: () => { throw new Error('not-linked calls no functions'); },
  }),
}));
vi.mock('../../lib/identity-session', () => ({
  readIdentity: async () => ({
    signedIn: state.signedIn,
    authenticatedUser: state.signedIn,
    identity: state.signedIn ? state.identity : { kind: 'unlinked' },
  }),
}));

const decode = (value: string) => value
  .replace(/&#x27;|&#39;|&apos;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const textOf = (html: string) => decode(
  html
    .replace(/<(script|style)\b[\s\S]*?<\/\1>/g, '')
    .replace(/<\/?(?:p|div|h[1-6]|li|ul|ol|section|main|header|footer|form|button|label|dl|dt|dd|br|a|nav|small)\b[^>]*>/g, ' ')
    .replace(/<[^>]+>/g, ''),
).replace(/\s+/g, ' ').trim();
const sentences = (text: string) => text.split(/(?<=[.!?])\s+/).map((sentence) => sentence.trim()).filter(Boolean);

type Page = () => Promise<ReactNode>;
const pageModule = async () => await import('../not-linked/page') as unknown as { default: Page };
async function show() {
  const { default: Page } = await pageModule();
  const html = renderToStaticMarkup(await Page());
  return { html, text: textOf(html) };
}

beforeEach(() => {
  state.signedIn = true;
  state.identity = { kind: 'unlinked' };
});

describe('INV web /not-linked keeps every existing pinned string', () => {
  it('still names the product, the state, both sentences and the sign-out control', async () => {
    const { html, text } = await show();
    expect(text).toContain('FitCruxx');
    expect(/<h1\b[^>]*>([\s\S]*?)<\/h1>/.exec(html)?.[1]).toBe('This account is not linked to a gym');
    expect(text).toContain('You are signed in, but this account has no complete active gym or platform identity.');
    expect(text).toContain('Ask your gym or platform administrator to check your access, then sign in again.');
    expect(html).toMatch(/<button\b[^>]*type="submit"[^>]*>Sign out<\/button>/);
  });

  it('still bounces a signed-out visitor to sign-in and a linked identity to its own home', async () => {
    state.signedIn = false;
    await expect(show()).rejects.toThrow('REDIRECT:/sign-in');
    state.signedIn = true;
    state.identity = { kind: 'member', userId: 'a7800000-0000-4000-8000-000000000001', tenantId: 'a7800000-0000-4000-8000-000000000002', memberId: 'a7800000-0000-4000-8000-000000000003' };
    await expect(show()).rejects.toThrow('REDIRECT:/member');
  });
});

describe('INV web /not-linked adds one sentence about the invite link and no input', () => {
  it('has exactly one sentence that sends the person to the invite link their gym sent, then to sign in', async () => {
    const { text } = await show();
    const mentioning = sentences(text).filter((sentence) => /invite link/i.test(sentence));
    expect(mentioning, 'exactly one new sentence').toHaveLength(1);
    expect(mentioning[0]).toMatch(/gym sent/i);
    expect(mentioning[0]).toMatch(/sign in/i);
    expect(mentioning[0]).toMatch(/\bopen\b/i);
  });

  it('adds no input of any kind (the only form is sign-out) and no code-entry affordance', async () => {
    const { html, text } = await show();
    expect(html).not.toMatch(/<input\b(?![^>]*type="hidden")/);
    expect(html).not.toMatch(/<(textarea|select)\b/);
    expect((html.match(/<form\b/g) ?? []).length).toBe(1);
    expect(text).not.toMatch(/enter (your |the )?(invite )?(code|token)|paste/i);
  });

  it('says nothing about whether an account, a link or a member exists, and prints no identity detail', async () => {
    const { html, text } = await show();
    expect(text).not.toMatch(/does not exist|no account|not found|no such account|invalid account/i);
    expect(html).not.toMatch(/memberId|tenantId|staffId|fullName|Verified member|data\.member|data\.gym|planName/i);
    for (const refusal of ['email_mismatch', 'identity_unverified', 'account_already_linked', 'rate_limited', 'invite_unavailable']) {
      expect(html).not.toContain(refusal);
    }
  });
});

describe('INV-023 /privacy gains a sentence on invite-based account linking', () => {
  it('says that accepting a gym invite links the person\'s Google account to their membership record at that gym', async () => {
    const { default: Privacy } = await import('../(public)/privacy/page') as unknown as { default: Page };
    const text = textOf(renderToStaticMarkup(await Privacy()));
    const linking = sentences(text).filter((sentence) => /\binvite/i.test(sentence) && /\blink/i.test(sentence));
    expect(linking.length, 'a sentence about linking through an invite').toBeGreaterThan(0);
    const joined = linking.join(' ');
    expect(joined).toMatch(/google/i);
    expect(joined).toMatch(/\bgym\b/i);
    expect(joined).toMatch(/member/i);
  });
});
