import { describe, expect, it } from 'vitest';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import MemberShopLoading from '../../apps/web/app/member/shop/loading';
import ConsoleShopLoading from '../../apps/web/app/(console)/shop/loading';

// Actual React markup, independently inspected as a tree. These assertions prove
// structural loading contracts only; they do not substitute for visual/runtime QA.
type Tag = { name: string; attrs: string; children: Tag[]; text: string; parent: Tag | null };
function markupTree(html: string): Tag {
  const root: Tag = { name: 'root', attrs: '', children: [], text: '', parent: null };
  let current = root;
  for (const token of html.matchAll(/<[^>]*>|[^<]+/g)) {
    const fragment = token[0];
    if (fragment.startsWith('</')) { current = current.parent ?? root; continue; }
    if (fragment.startsWith('<!--') || fragment.startsWith('<!')) continue;
    if (!fragment.startsWith('<')) { current.text += fragment; continue; }
    const parts = /^<([a-z][a-z0-9-]*)([^>]*)>/i.exec(fragment);
    if (!parts?.[1]) continue;
    const node: Tag = { name: parts[1], attrs: parts[2] ?? '', children: [], text: '', parent: current };
    current.children.push(node);
    if (!/^(?:img|input|br|hr|meta|link|source|wbr)$/i.test(node.name) && !fragment.endsWith('/>')) current = node;
  }
  return root;
}
function all(node: Tag): Tag[] { return [node, ...node.children.flatMap(all)]; }
function hidden(node: Tag): boolean { return /\baria-hidden="true"/.test(node.attrs) || (node.parent !== null && hidden(node.parent)); }
function words(node: Tag): string { return [node.text, ...node.children.map(words)].join(' ').trim(); }
function boxedLeaves(node: Tag): Tag[] {
  return all(node).filter(child => child.children.length === 0 && /^(?:div|span|i)$/i.test(child.name) && /\b(?:class|style)="[^"]+"/.test(child.attrs));
}
const routes = [
  { audience: 'member', shape: 'tiles', component: MemberShopLoading },
  { audience: 'console', shape: 'rows', component: ConsoleShopLoading },
];

describe('SHP States / Q10 held route fallback rendered structure', () => {
  it.each(routes)('$audience renders shaped skeleton $shape rather than only a loading sentence', ({ component }) => {
    const root = markupTree(renderToStaticMarkup(createElement(component)));
    const decoration = all(root).filter(node => /\baria-hidden="true"/.test(node.attrs));
    expect(decoration.length, 'A decorative skeleton group must be excluded from accessibility').toBeGreaterThan(0);
    // A tile/row has multiple spatial regions. A sentence, a lone bar or a
    // spinner is insufficient. No number of repeated tiles/rows is prescribed.
    expect(decoration.some(group => boxedLeaves(group).length > 1), 'The skeleton must contain separate shaped regions for the future content').toBe(true);
    expect(all(root).some(node => /\bclass="[^"]*\bcl-/.test(node.attrs)), 'Use the existing Chalkline kit').toBe(true);
  });

  it.each(routes)('$audience announces ongoing loading separately from decorative placeholders', ({ component }) => {
    const root = markupTree(renderToStaticMarkup(createElement(component)));
    const announcements = all(root).filter(node => !hidden(node) && (/\brole="status"/.test(node.attrs) || /\baria-live="(?:polite|assertive)"/.test(node.attrs)));
    expect(announcements.some(node => /loading/i.test(words(node))), 'A separately accessible status must announce the ongoing load').toBe(true);
    expect(all(root).filter(node => hidden(node)).every(node => !/\brole="status"|\baria-live="(?:polite|assertive)"/.test(node.attrs))).toBe(true);
  });

  it.each(routes)('$audience uses data-free noninteractive placeholders without fabricated product facts', ({ component }) => {
    const html = renderToStaticMarkup(createElement(component));
    const root = markupTree(html);
    const decoration = all(root).filter(node => /\baria-hidden="true"/.test(node.attrs));
    expect(decoration.length).toBeGreaterThan(0);
    for (const group of decoration) {
      expect(words(group)).toBe('');
      expect(all(group).some(node => /^(?:img|picture|button|input|select|textarea|a)$/i.test(node.name))).toBe(false);
      expect(all(group).some(node => /\b(?:src|href|tabindex|aria-label)="/.test(node.attrs))).toBe(false);
    }
    expect(words(root)).not.toMatch(/₹|\bINR\b|\bRs\.?\b|\d/);
    expect(html).not.toMatch(/\bstyle="[^"]*(?:#[0-9a-f]{3,8}\b|rgb\s*\()/i);
  });
});
