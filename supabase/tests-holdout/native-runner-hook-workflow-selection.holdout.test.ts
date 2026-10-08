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

describe('held complete native-input classification', () => {
  let grepRunner: typeof import('node:child_process').spawnSync;
  let grepExecutable = '';
  let nativeExpression = '';
  let exclusionExpression = '';
  let exclusionOptions: string[] = [];
  let runBound = 0;

  beforeAll(async () => {
    ({ spawnSync: grepRunner } = await import('node:child_process'));
    const { NATIVE_DB_VALIDATION } = await import('../../packages/shared/src/config/constants');
    runBound = NATIVE_DB_VALIDATION.processStopGraceMs;
    grepExecutable = process.platform === 'win32' ? 'C:/Program Files/Git/usr/bin/grep.exe' : 'grep';
    const opaqueWorkflow = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
    const nativeCandidates = Array.from(
      opaqueWorkflow.matchAll(/\bgrep[\t ]+-(?:qE|Eq)[\t ]+(['"])([^\r\n]*?)\1/gu),
      (match) => match[2],
    );
    const selectedNative = nativeCandidates.filter((candidate) => [
      'scripts/native-runner-hook.mjs',
      'scripts/native-runner-guard.mjs',
      'scripts/native-database-validation.mjs',
      'packages/shared/src/config/constants.ts',
      '.github/workflows/db.yml',
    ].every((input) => grepRunner(grepExecutable, ['-qE', candidate], {
      input: input + '\n', encoding: 'utf8', timeout: runBound,
    }).status === 0));
    expect(selectedNative.length === 1).toBe(true);
    nativeExpression = selectedNative[0];

    const exclusionCandidates = Array.from(
      opaqueWorkflow.matchAll(/\bgrep[\t ]+(-vE|-Ev|-v(?:[\t ]+-E)?)[\t ]+(['"])([^\r\n]*?)\2/gu),
      (match) => ({ options: match[1].split(/\s+/u), expression: match[3] }),
    );
    const selectedExclusion = exclusionCandidates.filter((candidate) => {
      const removed = grepRunner(grepExecutable, [...candidate.options, candidate.expression], {
        input: 'packages/db/types/database.ts\n', encoding: 'utf8', timeout: runBound,
      });
      const retained = grepRunner(grepExecutable, [...candidate.options, candidate.expression], {
        input: 'scripts/native-runner-hook.mjs\n', encoding: 'utf8', timeout: runBound,
      });
      return removed.status === 1 && removed.stdout.length === 0
        && retained.status === 0 && retained.stdout.trim() === 'scripts/native-runner-hook.mjs';
    });
    expect(selectedExclusion.length === 1).toBe(true);
    exclusionExpression = selectedExclusion[0].expression;
    exclusionOptions = selectedExclusion[0].options;
  });

  it.each([
    ['scripts/native-runner-hook.ps1', true],
    ['scripts/native-runner-hook.mjs', true],
    ['scripts/native-runner-guard.mjs', true],
    ['scripts/native-database-validation.mjs', true],
    ['scripts/pgtap/native.mjs', true],
    ['packages/shared/src/config/constants.ts', true],
    ['.github/workflows/db.yml', true],
    ['apps/web/app/page.tsx', false],
    ['apps/mobile/app/index.tsx', false],
    ['docs/domain-rules.md', false],
    ['README.md', false],
    ['packages/db/types/database.ts', false],
    ['scripts/unrelated-prejob.ps1', false],
    ['scripts/native-runner-hook.ps1.bak', false],
    ['scripts/native-runner-hooker.ps1', false],
    ['packages/db/types/database.ts\napps/web/app/page.tsx', false],
    ['packages/db/types/database.ts\nscripts/native-runner-hook.ps1', true],
  ] as const)('classifies controlled changed input %s', (changedPaths, shouldValidate) => {
    const filtered = grepRunner(grepExecutable, [...exclusionOptions, exclusionExpression], {
      input: changedPaths + '\n', encoding: 'utf8', timeout: runBound,
    });
    expect(filtered.error === undefined).toBe(true);
    expect(filtered.status === 0 || filtered.status === 1).toBe(true);
    let requiresNative = false;
    if (filtered.stdout.length > 0) {
      const classified = grepRunner(grepExecutable, ['-qE', nativeExpression], {
        input: filtered.stdout, encoding: 'utf8', timeout: runBound,
      });
      expect(classified.error === undefined).toBe(true);
      expect(classified.status === 0 || classified.status === 1).toBe(true);
      requiresNative = classified.status === 0;
    }
    expect(requiresNative).toBe(shouldValidate);
  });
});
