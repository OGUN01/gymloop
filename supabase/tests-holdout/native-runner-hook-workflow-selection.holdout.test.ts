import { readFileSync } from 'node:fs';
import { beforeAll, describe, expect, it } from 'vitest';

describe.each(['push', 'pull_request'])('held pre-job workflow selection: %s', (event) => {
  let paths: string[] = [];

  beforeAll(() => {
    const workflow = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
    const lines = workflow.split(/\r?\n/u);
    const eventHeader = new RegExp(`^\\s+${event}:\\s*(?:#.*)?$`, 'u');
    const start = lines.findIndex((line) => eventHeader.test(line));
    expect(start >= 0).toBe(true);
    const eventIndent = lines[start].match(/^\s*/u)?.[0].length ?? 0;
    const tail = lines.slice(start + 1);
    const end = tail.findIndex((line) => (
      line.trim().length > 0
      && !line.trimStart().startsWith('#')
      && (line.match(/^\s*/u)?.[0].length ?? 0) <= eventIndent
    ));
    const eventLines = end < 0 ? tail : tail.slice(0, end);
    const pathStart = eventLines.findIndex((line) => /^\s+paths:\s*(?:#.*)?$/u.test(line));
    expect(pathStart >= 0).toBe(true);
    const pathIndent = eventLines[pathStart].match(/^\s*/u)?.[0].length ?? 0;
    const pathTail = eventLines.slice(pathStart + 1);
    const pathEnd = pathTail.findIndex((line) => (
      line.trim().length > 0
      && !line.trimStart().startsWith('#')
      && (line.match(/^\s*/u)?.[0].length ?? 0) <= pathIndent
    ));
    const pathLines = pathEnd < 0 ? pathTail : pathTail.slice(0, pathEnd);
    paths = pathLines.flatMap((line) => {
      const entry = line.match(/^\s*-\s+(?:'([^']*)'|"([^"]*)"|([^#]*?))(?:\s+#.*)?\s*$/u);
      return entry ? [entry[1] ?? entry[2] ?? entry[3].trim()] : [];
    });
    expect(paths.length > 0).toBe(true);
  });

  it('selects the supported entry through its exact path once', () => {
    expect(paths.filter((path) => path === 'scripts/native-runner-hook.ps1').length === 1).toBe(true);
  });

  it('retains the existing approved Node hook selection', () => {
    expect(paths.includes('scripts/native-runner-hook.mjs')).toBe(true);
  });

  it('retains narrow harness selection without catch-all or UI coverage', () => {
    const broadOrUi = [
      '*', '**', '**/*', 'scripts/*', 'scripts/**', 'scripts/**/*',
      'apps/*', 'apps/**', 'apps/**/*',
      'apps/web/*', 'apps/web/**', 'apps/web/**/*',
      'apps/mobile/*', 'apps/mobile/**', 'apps/mobile/**/*',
      'packages/ui/*', 'packages/ui/**', 'packages/ui/**/*',
    ];
    const selections = paths.filter((path) => !path.startsWith('!'));
    expect(selections.every((path) => (
      !broadOrUi.includes(path)
      && !/^apps\/(?:web|mobile)\/(?:app|components)(?:\/|$)/u.test(path)
    ))).toBe(true);
  });
});
