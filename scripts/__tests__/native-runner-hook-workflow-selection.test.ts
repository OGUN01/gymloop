import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

// Authored from windows-prejob-workflow-selection.md before reading workflow data.
// The workflow is only an inert runtime fixture; failures expose booleans, not its body.
describe.each(['push', 'pull_request'])('[DBV-012] Windows pre-job workflow selection for %s', (event) => {
  const workflow = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
  const eventBlock = workflow.match(new RegExp(
    `^ {2}${event}:[ \\t]*\\r?\\n([\\s\\S]*?)(?=^ {2}[A-Za-z_][\\w-]*:|^[A-Za-z_][\\w-]*:|(?![\\s\\S]))`,
    'm',
  ))?.[1] ?? '';
  const pathBlock = eventBlock.match(
    /^ {4}paths:[ \t]*\r?\n([\s\S]*?)(?=^ {4}[A-Za-z_][\w-]*:|(?![\s\S]))/m,
  )?.[1] ?? '';
  const paths = Array.from(pathBlock.matchAll(
    /^ {6}-[ \t]+(?:'([^']+)'|"([^"]+)"|([^\s#]+))[ \t]*(?:#.*)?$/gm,
  ), (match) => match[1] ?? match[2] ?? match[3]);

  it('includes the exact supported PowerShell bridge in the existing event path filter', () => {
    expect(eventBlock.length > 0).toBe(true);
    expect(pathBlock.length > 0).toBe(true);
    expect(paths.includes('scripts/native-runner-hook.ps1')).toBe(true);
    expect(/^ {4}paths-ignore:/m.test(eventBlock)).toBe(false);
  });

  it('preserves the exact existing Node hook selector', () => {
    expect(pathBlock.length > 0).toBe(true);
    expect(paths.includes('scripts/native-runner-hook.mjs')).toBe(true);
  });

  it('does not add root catch-all, all-scripts, or UI selectors', () => {
    expect(pathBlock.length > 0).toBe(true);
    expect(paths.some((path) => /^(?:[*?]|scripts\/[*?])/.test(path))).toBe(false);
    expect(paths.some((path) => /^(?:apps(?:\/|$)|packages\/(?:ui|components)(?:\/|$))/.test(path))).toBe(false);
  });

  if (event === 'push') {
    it('preserves the main-only push restriction', () => {
      const branchSetting = eventBlock.match(
        /^ {4}branches:[ \t]*(?:\[([^\]\r\n]*)\][ \t]*(?:#.*)?$|\r?\n([\s\S]*?)(?=^ {4}[A-Za-z_][\w-]*:|(?![\s\S])))/m,
      );
      const branches = branchSetting?.[1] !== undefined
        ? branchSetting[1].split(',').map((branch) => branch.trim().replace(/^['"]|['"]$/g, ''))
        : Array.from((branchSetting?.[2] ?? '').matchAll(
          /^ {6}-[ \t]+(?:'([^']+)'|"([^"]+)"|([^\s#]+))[ \t]*(?:#.*)?$/gm,
        ), (match) => match[1] ?? match[2] ?? match[3]);

      expect(branches).toEqual(['main']);
      expect(/^ {4}branches-ignore:/m.test(eventBlock)).toBe(false);
    });
  }
});
