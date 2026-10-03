import { describe, expect, it } from 'vitest';
import { isValidElement, type ReactElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

type PublicAttributes = Record<string, unknown>;
type PublicElement = ReactElement<PublicAttributes>;
function descendants(node: ReactNode): PublicElement[] {
  if (Array.isArray(node)) return node.flatMap(descendants);
  if (!isValidElement<PublicAttributes>(node)) return [];
  if (typeof node.type === 'function') return descendants((node.type as (props: PublicAttributes) => ReactNode)(node.props));
  return [node, ...descendants(node.props.children as ReactNode)];
}
function words(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(words).join(' ');
  if (isValidElement<PublicAttributes>(node)) return words(node.props.children as ReactNode);
  return typeof node === 'string' || typeof node === 'number' ? String(node) : '';
}
function announced(node: ReactNode, hidden = false): PublicElement[] {
  if (Array.isArray(node)) return node.flatMap(child => announced(child, hidden));
  if (!isValidElement<PublicAttributes>(node)) return [];
  if (typeof node.type === 'function') return announced((node.type as (props: PublicAttributes) => ReactNode)(node.props), hidden);
  const excluded = hidden || node.props['aria-hidden'] === true || node.props['aria-hidden'] === 'true';
  const live = node.props.role === 'status' || node.props['aria-live'] === 'polite' || node.props['aria-live'] === 'assertive';
  return [...(!excluded && live ? [node] : []), ...announced(node.props.children as ReactNode, excluded)];
}
// SHP-Q10/States: structural evidence only. Computed geometry, theme contrast,
// enlarged text and reduced-motion behavior require the separate browser check.
describe('SHP actual route loading fallback contract', () => {
  it.each(['member', 'console'] as const)('%s announces an ongoing load separately from decorative shaped placeholders', async audience => {
    const { default: Loading } = audience === 'member' ? await import('../member/shop/loading') : await import('../(console)/shop/loading');
    const tree = Loading(); const all = descendants(tree); const html = renderToStaticMarkup(tree);
    const status = announced(tree);
    expect(status.length, 'Loading state is separately available to assistive technology').toBeGreaterThan(0);
    expect(status.map(node => words(node)).join(' ')).toMatch(/loading|please wait/i);
    const decorative = all.filter(node => node.props['aria-hidden'] === true || node.props['aria-hidden'] === 'true');
    expect(decorative.length, `${audience} route needs decorative ${audience === 'member' ? 'tile' : 'row'} skeleton structure beyond its loading sentence`).toBeGreaterThan(0);
    const structured = decorative.filter(node => {
      const shapes = descendants(node).filter(child => ['div', 'span', 'rect', 'circle', 'path'].includes(String(child.type)) && words(child).trim() === '' && (typeof child.props.className === 'string' || child.props.style !== undefined || child.props.width !== undefined || child.props.d !== undefined));
      return shapes.length > 1;
    });
    expect(structured.length, 'A shaped placeholder contains multiple empty visual surfaces, rather than only hidden prose').toBeGreaterThan(0);
    for (const node of decorative) {
      expect(words(node).trim(), 'Placeholders contain no fabricated names, prices or counts').toBe('');
      expect(descendants(node).some(child => ['button', 'input', 'select', 'a'].includes(String(child.type))), 'Decorative skeleton cannot contain controls or links').toBe(false);
      expect(descendants(node).some(child => child.type === 'img' || child.props.src !== undefined), 'Loading does not pretend a product photo is already known').toBe(false);
    }
    expect(html).not.toMatch(/₹|\bINR\b|\b(?:products? available|items? in stock|sold out|no products|no items)\b/i);
    expect(all.some(node => node.type === 'button' || node.type === 'input'), 'Loading offers no fabricated actionable product').toBe(false);
  });
});
