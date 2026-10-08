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

import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmdirSync, unlinkSync, writeFileSync } from 'node:fs';
import { platform, tmpdir } from 'node:os';
import { join } from 'node:path';

// Append-only independent cases from the frozen internal-classification clause.
// Execute the actual opaque grep pipeline; do not translate or display its source.
describe('[DBV-012] Windows pre-job internal native-input classification', () => {
  const workflow = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
  const nativeCommands = workflow.split(/\r?\n/).filter((line) => (
    /\bgrep[ \t]+-qE[ \t]+/.test(line) && line.includes('native-runner')
  ));
  const nativeExpressions = Array.from(nativeCommands.join('\n').matchAll(
    /\bgrep[ \t]+-qE[ \t]+(['"])([^\r\n]*?)\1/g,
  ), (match) => match[2]).filter((expression) => expression.includes('native-runner'));
  const generatedTypesExclusions = Array.from(nativeCommands.join('\n').matchAll(
    /\bgrep[ \t]+-vE[ \t]+(['"])([^\r\n]*?)\1/g,
  ), (match) => match[2]).filter((expression) => expression.includes('packages/db/types'));

  it('probes one existing native-input grep pipeline with its generated-types exclusion', () => {
    expect(nativeCommands.length).toBe(1);
    expect(nativeExpressions.length).toBe(1);
    expect(generatedTypesExclusions.length).toBe(1);
  });

  it.each([
    { changedPath: 'scripts/native-runner-hook.ps1', requiresNative: true },
    { changedPath: 'scripts/native-runner-hook.mjs', requiresNative: true },
    { changedPath: 'scripts/native-runner-guard.mjs', requiresNative: true },
    { changedPath: 'scripts/native-database-validation.mjs', requiresNative: true },
    { changedPath: 'scripts/pgtap/native.mjs', requiresNative: true },
    { changedPath: 'packages/shared/src/config/constants.ts', requiresNative: true },
    { changedPath: '.github/workflows/db.yml', requiresNative: true },
    { changedPath: 'apps/web/app/page.tsx', requiresNative: false },
    { changedPath: 'apps/mobile/app/(member)/index.tsx', requiresNative: false },
    { changedPath: 'packages/ui/button.tsx', requiresNative: false },
    { changedPath: 'docs/architecture.md', requiresNative: false },
    { changedPath: 'packages/db/types/database.ts', requiresNative: false },
    { changedPath: 'scripts/unrelated-hook.ps1', requiresNative: false },
    { changedPath: 'scripts/nested/native-runner-hook.ps1', requiresNative: false },
    { changedPath: 'scripts/native-runner-hookXps1', requiresNative: false },
    { changedPath: 'scripts/native-runner-hook.ps10', requiresNative: false },
    { changedPath: 'scripts/native-runner-hook.ps1.bak', requiresNative: false },
  ])('classifies $changedPath with requiresNative=$requiresNative', ({ changedPath, requiresNative }) => {
    expect(nativeCommands.length).toBe(1);
    expect(nativeExpressions.length).toBe(1);
    expect(generatedTypesExclusions.length).toBe(1);
    const patternDirectory = mkdtempSync(join(tmpdir(), 'gymloop-visible-classifier-pattern-'));
    const generatedTypesPatternPath = join(patternDirectory, 'generated-types.pattern').replaceAll('\\', '/');
    const nativeInputPatternPath = join(patternDirectory, 'native-input.pattern').replaceAll('\\', '/');
    try {
      writeFileSync(generatedTypesPatternPath, `${generatedTypesExclusions[0] ?? '^$'}\n`, { encoding: 'utf8', flag: 'wx' });
      writeFileSync(nativeInputPatternPath, `${nativeExpressions[0] ?? '^$'}\n`, { encoding: 'utf8', flag: 'wx' });
      const retainedInputs = spawnSync(
        platform() === 'win32' ? 'C:/Program Files/Git/usr/bin/grep.exe' : 'grep',
        ['-vE', '-f', generatedTypesPatternPath, '--'],
        { input: `${changedPath}\n`, encoding: 'utf8' },
      );
      expect(retainedInputs.error === undefined).toBe(true);
      expect(retainedInputs.signal === null).toBe(true);
      expect(retainedInputs.status === 0 || retainedInputs.status === 1).toBe(true);

      const classification = spawnSync(
        platform() === 'win32' ? 'C:/Program Files/Git/usr/bin/grep.exe' : 'grep',
        ['-qE', '-f', nativeInputPatternPath, '--'],
        { input: retainedInputs.stdout, encoding: 'utf8' },
      );

      expect(classification.error === undefined).toBe(true);
      expect(classification.signal === null).toBe(true);
      expect(classification.status).toBe(requiresNative ? 0 : 1);
    } finally {
      for (const patternPath of [generatedTypesPatternPath, nativeInputPatternPath]) {
        if (existsSync(patternPath)) unlinkSync(patternPath);
      }
      rmdirSync(patternDirectory);
    }
  });
});
