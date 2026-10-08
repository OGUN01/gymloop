import { afterEach, describe, expect, it } from 'vitest';
import {
  mkdirSync, mkdtempSync, realpathSync, renameSync, rmSync, symlinkSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, isAbsolute, join, relative } from 'node:path';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

const heldWindowsCliOptionalName = '@supabase/cli-windows-x64';
const heldWindowsCliRoots: { root: string; parent: string }[] = [];
const heldWindowsCliWindowsTest = process.platform === 'win32' ? it : it.skip;

async function heldWindowsCliResolver() {
  // Opaque import execution only: this author never reads the adapter source.
  const adapter = await import('../../scripts/native-database-validation.mjs');
  const resolve = Reflect.get(adapter, 'resolveNativeSupabaseExecutable');
  expect(typeof resolve).toBe('function');
  return resolve as (input: unknown) => Promise<string>;
}

function heldWindowsCliFixture(layout: 'local' | 'global', placement: 'nested' | 'hoisted') {
  const parent = realpathSync(tmpdir());
  const root = mkdtempSync(join(parent, 'gymloop held Windows CLI '));
  heldWindowsCliRoots.push({ root, parent });
  const modules = join(root, 'node_modules');
  const pathDirectory = layout === 'local' ? join(modules, '.bin') : root;
  const packageDirectory = join(modules, 'supabase');
  const optionalDirectory = join(
    placement === 'nested' ? join(packageDirectory, 'node_modules') : modules,
    '@supabase', 'cli-windows-x64',
  );
  const packageJson = join(packageDirectory, 'package.json');
  const optionalJson = join(optionalDirectory, 'package.json');
  const javascriptBin = join(packageDirectory, 'dist', 'supabase.js');
  const executable = join(optionalDirectory, 'bin', 'supabase.exe');
  const commandShim = join(pathDirectory, 'supabase.cmd');
  const packageMetadata = {
    name: 'supabase', version: NATIVE_DB_VALIDATION.cliVersion,
    bin: { supabase: 'dist/supabase.js' },
    optionalDependencies: { [heldWindowsCliOptionalName]: NATIVE_DB_VALIDATION.cliVersion },
  };
  const optionalMetadata = {
    name: heldWindowsCliOptionalName, version: NATIVE_DB_VALIDATION.cliVersion,
    main: 'bin/supabase.exe',
  };
  mkdirSync(pathDirectory, { recursive: true });
  mkdirSync(dirname(javascriptBin), { recursive: true });
  mkdirSync(dirname(executable), { recursive: true });
  writeFileSync(packageJson, JSON.stringify(packageMetadata));
  writeFileSync(optionalJson, JSON.stringify(optionalMetadata));
  writeFileSync(javascriptBin, '// inert fixture, never evaluated\n');
  writeFileSync(executable, 'inert bytes; this file must never be launched\n');
  writeFileSync(commandShim, '@echo off\r\nexit /b 1\r\n');
  return {
    root, pathDirectory, packageDirectory, optionalDirectory, packageJson, optionalJson,
    javascriptBin, executable, commandShim, packageMetadata, optionalMetadata,
  };
}

afterEach(() => {
  for (const fixture of heldWindowsCliRoots.splice(0)) {
    // Every recursive cleanup is confined to this author's create-new fixture root.
    if (dirname(fixture.root) !== fixture.parent
      || !basename(fixture.root).startsWith('gymloop held Windows CLI ')) {
      throw new Error('Fixture cleanup containment failed');
    }
    rmSync(fixture.root, { recursive: true, force: true });
  }
});

describe('held Windows native executable contract — portable boundary', () => {
  it('provides the frozen async testable resolver export', async () => {
    expect(await heldWindowsCliResolver()).toBeTypeOf('function');
  });

  it.each(['linux', 'darwin'])('retains the hosted command on %s without path filesystem work', async platform => {
    const resolve = await heldWindowsCliResolver();
    // A valid string that cannot be passed to filesystem APIs still takes the hosted branch.
    await expect(resolve({ platform, arch: 'arm64', path: '\0' }))
      .resolves.toBe(NATIVE_DB_VALIDATION.nativeCommand);
  });

  it.each([
    null,
    [],
    { platform: '', arch: 'x64', path: '' },
    { platform: 'linux', arch: '', path: '' },
    { platform: 'linux', arch: 'x64', path: null },
    { platform: 'linux', arch: 'x64', path: '', unexpected: true },
  ])('rejects a non-exact inert input record', async input => {
    const resolve = await heldWindowsCliResolver();
    await expect(resolve(input)).rejects.toThrow();
  });

  it('refuses an accessor without evaluating it', async () => {
    const resolve = await heldWindowsCliResolver();
    let reads = 0;
    const input = Object.defineProperty({ arch: 'x64', path: '' }, 'platform', {
      enumerable: true, get: () => { reads += 1; return 'linux'; },
    });
    await expect(resolve(input)).rejects.toThrow();
    expect(reads).toBe(0);
  });

  it('refuses hidden data descriptors and symbol extras', async () => {
    const resolve = await heldWindowsCliResolver();
    const hidden = Object.defineProperty({ platform: 'linux', arch: 'x64' }, 'path', {
      value: '', enumerable: false,
    });
    await expect(resolve(hidden)).rejects.toThrow();
    await expect(resolve({ platform: 'linux', arch: 'x64', path: '', [Symbol('extra')]: true }))
      .rejects.toThrow();
  });

  it('refuses a record with an application-defined prototype', async () => {
    const resolve = await heldWindowsCliResolver();
    const input = Object.assign(Object.create({ inherited: true }), {
      platform: 'linux', arch: 'x64', path: '',
    });
    await expect(resolve(input)).rejects.toThrow();
  });
});

describe('held Windows native executable contract — harmless actual filesystem', () => {
  // On hosted non-Windows systems these callbacks are skipped before fixture creation.
  heldWindowsCliWindowsTest.each([
    { layout: 'local' as const, placement: 'nested' as const },
    { layout: 'local' as const, placement: 'hoisted' as const },
    { layout: 'global' as const, placement: 'hoisted' as const },
  ])('binds the pinned $layout/$placement package with spaces and never launches a shim', async ({ layout, placement }) => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture(layout, placement);
    await expect(resolve({ platform: 'win32', arch: 'x64', path: fixture.pathDirectory }))
      .resolves.toBe(realpathSync(fixture.executable));
  });

  heldWindowsCliWindowsTest('preserves an ordinary native exe before examining npm metadata', async () => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture('local', 'nested');
    const native = join(fixture.pathDirectory, 'supabase.exe');
    writeFileSync(native, 'ordinary inert native fixture');
    writeFileSync(fixture.packageJson, 'malformed and intentionally unconsumable');
    await expect(resolve({ platform: 'win32', arch: 'x64', path: fixture.pathDirectory }))
      .resolves.toBe(realpathSync(native));
  });

  heldWindowsCliWindowsTest('does not fall through the first unbound cmd to a later valid install', async () => {
    const resolve = await heldWindowsCliResolver();
    const invalid = heldWindowsCliFixture('global', 'nested');
    const valid = heldWindowsCliFixture('local', 'hoisted');
    rmSync(invalid.packageJson);
    await expect(resolve({ platform: 'win32', arch: 'x64', path: `${invalid.pathDirectory};${valid.pathDirectory}` }))
      .rejects.toThrow();
  });

  heldWindowsCliWindowsTest('requires absolute PATH directories rather than resolving a cwd alias', async () => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture('local', 'nested');
    const cwdRelative = relative(process.cwd(), fixture.pathDirectory);
    expect(isAbsolute(cwdRelative)).toBe(false);
    await expect(resolve({ platform: 'win32', arch: 'x64', path: cwdRelative })).rejects.toThrow();
  });

  heldWindowsCliWindowsTest('refuses missing commands and non-x64 Windows architecture', async () => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture('global', 'hoisted');
    rmSync(fixture.commandShim);
    await expect(resolve({ platform: 'win32', arch: 'x64', path: fixture.pathDirectory })).rejects.toThrow();
    await expect(resolve({ platform: 'win32', arch: 'arm64', path: '\0' })).rejects.toThrow();
  });

  heldWindowsCliWindowsTest('refuses malformed supabase package JSON', async () => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture('local', 'nested');
    writeFileSync(fixture.packageJson, '{unclosed');
    await expect(resolve({ platform: 'win32', arch: 'x64', path: fixture.pathDirectory })).rejects.toThrow();
  });

  heldWindowsCliWindowsTest.each([
    { field: 'name', value: 'a-different-package' },
    { field: 'version', value: 'not-the-pinned-version' },
    { field: 'bin', value: { supabase: 'other-script.js' } },
    { field: 'optionalDependencies', value: { [heldWindowsCliOptionalName]: 'not-an-exact-pin' } },
  ])('refuses non-pinned supabase $field metadata', async ({ field, value }) => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture('local', 'nested');
    writeFileSync(fixture.packageJson, JSON.stringify({ ...fixture.packageMetadata, [field]: value }));
    await expect(resolve({ platform: 'win32', arch: 'x64', path: fixture.pathDirectory })).rejects.toThrow();
  });

  heldWindowsCliWindowsTest.each([
    { field: 'name', value: '@supabase/a-different-binary' },
    { field: 'version', value: 'not-the-pinned-version' },
  ])('refuses optional package $field metadata mismatch', async ({ field, value }) => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture('local', 'hoisted');
    writeFileSync(fixture.optionalJson, JSON.stringify({ ...fixture.optionalMetadata, [field]: value }));
    await expect(resolve({ platform: 'win32', arch: 'x64', path: fixture.pathDirectory })).rejects.toThrow();
  });

  heldWindowsCliWindowsTest('requires optional package metadata even when an exe file exists', async () => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture('global', 'nested');
    rmSync(fixture.optionalJson);
    await expect(resolve({ platform: 'win32', arch: 'x64', path: fixture.pathDirectory })).rejects.toThrow();
  });

  heldWindowsCliWindowsTest('requires the declared ordinary JavaScript bin to exist', async () => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture('local', 'nested');
    rmSync(fixture.javascriptBin);
    await expect(resolve({ platform: 'win32', arch: 'x64', path: fixture.pathDirectory })).rejects.toThrow();
  });

  heldWindowsCliWindowsTest('requires the optional package native binary to be an ordinary file', async () => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture('global', 'hoisted');
    rmSync(fixture.executable);
    await expect(resolve({ platform: 'win32', arch: 'x64', path: fixture.pathDirectory })).rejects.toThrow();
    mkdirSync(fixture.executable);
    await expect(resolve({ platform: 'win32', arch: 'x64', path: fixture.pathDirectory })).rejects.toThrow();
  });

  heldWindowsCliWindowsTest('refuses an inherited PATH directory junction alias', async () => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture('local', 'hoisted');
    const alias = join(fixture.root, 'path alias');
    symlinkSync(fixture.pathDirectory, alias, 'junction');
    await expect(resolve({ platform: 'win32', arch: 'x64', path: alias })).rejects.toThrow();
  });

  heldWindowsCliWindowsTest('refuses a package metadata file reached through a package junction', async () => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture('global', 'nested');
    const target = join(fixture.root, 'ordinary package');
    renameSync(fixture.packageDirectory, target);
    symlinkSync(target, fixture.packageDirectory, 'junction');
    await expect(resolve({ platform: 'win32', arch: 'x64', path: fixture.pathDirectory })).rejects.toThrow();
  });

  heldWindowsCliWindowsTest('refuses optional package metadata behind a hoisted junction', async () => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture('local', 'hoisted');
    const target = join(fixture.root, 'ordinary optional package');
    renameSync(fixture.optionalDirectory, target);
    symlinkSync(target, fixture.optionalDirectory, 'junction');
    await expect(resolve({ platform: 'win32', arch: 'x64', path: fixture.pathDirectory })).rejects.toThrow();
  });

  heldWindowsCliWindowsTest('refuses a canonical executable file hidden behind a bin junction', async () => {
    const resolve = await heldWindowsCliResolver();
    const fixture = heldWindowsCliFixture('local', 'nested');
    const originalBin = dirname(fixture.executable);
    const target = join(fixture.root, 'ordinary native bin');
    renameSync(originalBin, target);
    symlinkSync(target, originalBin, 'junction');
    await expect(resolve({ platform: 'win32', arch: 'x64', path: fixture.pathDirectory })).rejects.toThrow();
  });
});
