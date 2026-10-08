import { mkdir, mkdtemp, realpath, rename, rm, symlink, unlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

type WindowsCliInput = { platform: string; arch: string; path: string };
type WindowsCliResolver = (input: unknown) => Promise<string>;
type WindowsCliFixture = {
  root: string;
  shimDir: string;
  shim: string;
  packageRoot: string;
  packageJson: string;
  packageMetadata: Record<string, unknown>;
  launcher: string;
  optionalName: string;
  optionalRoot: string;
  optionalJson: string;
  optionalMetadata: Record<string, unknown>;
  executable: string;
};

const windowsCliModuleUrl = new URL('../native-database-validation.mjs', import.meta.url).href;
let windowsCliModule: Record<string, unknown> = {};
const windowsCliRoots: string[] = [];

beforeAll(async () => {
  // Execution is opaque: this author never reads the adapter source.
  windowsCliModule = await import(/* @vite-ignore */ windowsCliModuleUrl);
});

afterEach(async () => {
  for (const root of windowsCliRoots.splice(0)) {
    if (dirname(resolve(root)) !== resolve(tmpdir()) || !basename(root).startsWith('gymloop windows visible ')) {
      throw new Error('Refusing cleanup outside the author-owned temporary fixture root');
    }
    await rm(root, { recursive: true, force: true });
  }
});

function requireWindowsCliResolver(): WindowsCliResolver {
  if (typeof windowsCliModule.resolveNativeSupabaseExecutable !== 'function') {
    throw new Error('Frozen resolver contract export resolveNativeSupabaseExecutable is absent');
  }
  return windowsCliModule.resolveNativeSupabaseExecutable as WindowsCliResolver;
}

function windowsCliInput(path: string, platform = 'win32', arch = 'x64'): WindowsCliInput {
  return { platform, arch, path };
}

async function windowsCliWriteJson(file: string, metadata: unknown): Promise<void> {
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(metadata), { mode: NATIVE_DB_VALIDATION.privateFileMode });
}

async function windowsCliFixture(
  layout: 'local' | 'global' = 'local',
  placement: 'nested' | 'hoisted' = 'nested',
): Promise<WindowsCliFixture> {
  const root = await mkdtemp(join(tmpdir(), 'gymloop windows visible '));
  windowsCliRoots.push(root);
  const modules = join(root, 'node_modules');
  const shimDir = layout === 'local' ? join(modules, '.bin') : root;
  const packageRoot = join(modules, NATIVE_DB_VALIDATION.nativeCommand);
  const optionalName = '@supabase/cli-windows-x64';
  const optionalRoot = join(placement === 'nested' ? join(packageRoot, 'node_modules') : modules, optionalName);
  const fixture: WindowsCliFixture = {
    root,
    shimDir,
    shim: join(shimDir, 'supabase.cmd'),
    packageRoot,
    packageJson: join(packageRoot, 'package.json'),
    packageMetadata: {
      name: NATIVE_DB_VALIDATION.nativeCommand,
      version: NATIVE_DB_VALIDATION.cliVersion,
      bin: { supabase: 'dist/supabase.js' },
      optionalDependencies: { [optionalName]: NATIVE_DB_VALIDATION.cliVersion },
    },
    launcher: join(packageRoot, 'dist', 'supabase.js'),
    optionalName,
    optionalRoot,
    optionalJson: join(optionalRoot, 'package.json'),
    optionalMetadata: {
      name: optionalName,
      version: NATIVE_DB_VALIDATION.cliVersion,
      main: 'bin/supabase.exe',
      os: ['win32'],
      cpu: ['x64'],
    },
    executable: join(optionalRoot, 'bin', 'supabase.exe'),
  };
  await mkdir(shimDir, { recursive: true });
  await mkdir(dirname(fixture.launcher), { recursive: true });
  await mkdir(dirname(fixture.executable), { recursive: true });
  await windowsCliWriteJson(fixture.packageJson, fixture.packageMetadata);
  await windowsCliWriteJson(fixture.optionalJson, fixture.optionalMetadata);
  await writeFile(fixture.shim, 'Harmless inert shim fixture; this is deliberately not a command script.\n');
  await writeFile(fixture.launcher, 'throw new Error("The inert fixture launcher must never execute");\n');
  await writeFile(fixture.executable, 'Inert native binary fixture; never invoked.\n');
  return fixture;
}

async function windowsCliRefuse(input: unknown): Promise<void> {
  const resolver = requireWindowsCliResolver();
  await expect(resolver(input)).rejects.toThrow();
}

describe('native Supabase executable portable input contract', () => {
  it('exports the frozen asynchronous resolver', () => {
    expect(typeof windowsCliModule.resolveNativeSupabaseExecutable).toBe('function');
  });

  it('returns the unchanged hosted command without consulting an unusable filesystem path', async () => {
    const resolver = requireWindowsCliResolver();
    const result = resolver(Object.freeze(windowsCliInput('\0not a filesystem path', 'linux', 'arm64')));
    expect(result).toBeInstanceOf(Promise);
    await expect(result).resolves.toBe(NATIVE_DB_VALIDATION.nativeCommand);
  });

  it('preserves the command on a second non-Windows platform with an empty inherited PATH', async () => {
    const resolver = requireWindowsCliResolver();
    await expect(resolver(windowsCliInput('', 'darwin'))).resolves.toBe(NATIVE_DB_VALIDATION.nativeCommand);
  });

  it.each([
    ['missing path', { platform: 'linux', arch: 'x64' }],
    ['extra own key', { platform: 'linux', arch: 'x64', path: '', shell: true }],
    ['empty platform', { platform: '', arch: 'x64', path: '' }],
    ['empty architecture', { platform: 'linux', arch: '', path: '' }],
    ['non-string path', { platform: 'linux', arch: 'x64', path: [] }],
    ['array record', ['linux', 'x64', '']],
    ['null record', null],
    ['custom prototype', Object.assign(Object.create({ inherited: true }), windowsCliInput('', 'linux'))],
    ['symbol key', { ...windowsCliInput('', 'linux'), [Symbol('unapproved')]: true }],
    ['hidden data key', Object.defineProperty(windowsCliInput('', 'linux'), 'hidden', { value: true })],
    ['hidden required field', Object.defineProperty({ platform: 'linux', arch: 'x64' }, 'path', { value: '' })],
  ])('refuses an unsafe exact-input record: %s', async (_label, input) => {
    await windowsCliRefuse(input);
  });

  it('rejects an accessor without invoking its getter', async () => {
    let getterCalls = 0;
    const input = Object.defineProperty({ platform: 'linux', arch: 'x64' }, 'path', {
      enumerable: true,
      get() {
        getterCalls += 1;
        return '';
      },
    });
    await windowsCliRefuse(input);
    expect(getterCalls).toBe(0);
  });

  it('turns hostile record reflection into a refusal', async () => {
    const input = new Proxy(windowsCliInput('', 'linux'), {
      ownKeys() {
        throw new Error('Inert hostile reflection fixture');
      },
    });
    await windowsCliRefuse(input);
  });
});

// The platform gate is evaluated before fixture creation or Windows filesystem
// operations. Linux still discovers and executes the portable contract above.
describe.skipIf(process.platform !== 'win32')('native Windows Supabase executable filesystem transport', () => {
  it('resolves a nested local npm package through a PATH containing spaces', async () => {
    const fixture = await windowsCliFixture();
    const resolver = requireWindowsCliResolver();
    await expect(resolver(windowsCliInput(fixture.shimDir))).resolves.toBe(await realpath(fixture.executable));
  });

  it('resolves the hoisted optional package from the adjacent local package', async () => {
    const fixture = await windowsCliFixture('local', 'hoisted');
    const resolver = requireWindowsCliResolver();
    await expect(resolver(windowsCliInput(fixture.shimDir))).resolves.toBe(await realpath(fixture.executable));
  });

  it('supports the npm global shim and hoisted package layout', async () => {
    const fixture = await windowsCliFixture('global', 'hoisted');
    const resolver = requireWindowsCliResolver();
    await expect(resolver(windowsCliInput(fixture.shimDir))).resolves.toBe(await realpath(fixture.executable));
  });

  it('preserves an ordinary native executable in an absolute PATH directory', async () => {
    const fixture = await windowsCliFixture();
    const nativeDir = join(fixture.root, 'ordinary native executable');
    const executable = join(nativeDir, 'supabase.exe');
    await mkdir(nativeDir);
    await writeFile(executable, 'Inert standalone native fixture; never invoked.\n');
    const resolver = requireWindowsCliResolver();
    await expect(resolver(windowsCliInput(nativeDir))).resolves.toBe(await realpath(executable));
  });

  it('keeps native executable selection when an earlier npm shim is present', async () => {
    const fixture = await windowsCliFixture();
    const nativeDir = join(fixture.root, 'native later in PATH');
    const executable = join(nativeDir, 'supabase.exe');
    await mkdir(nativeDir);
    await writeFile(executable, 'Inert standalone native fixture; never invoked.\n');
    const resolver = requireWindowsCliResolver();
    await expect(resolver(windowsCliInput(`${fixture.shimDir};${nativeDir}`))).resolves.toBe(await realpath(executable));
  });

  it('refuses an unsupported Windows architecture even with an ordinary native executable', async () => {
    const fixture = await windowsCliFixture();
    await writeFile(join(fixture.shimDir, 'supabase.exe'), 'Inert standalone native fixture; never invoked.\n');
    await windowsCliRefuse(windowsCliInput(fixture.shimDir, 'win32', 'arm64'));
  });

  it('refuses an empty PATH and a relative PATH entry', async () => {
    await windowsCliRefuse(windowsCliInput(''));
    await windowsCliRefuse(windowsCliInput('relative npm bin'));
  });

  it('does not fall through an invalid first shim to a later valid installation', async () => {
    const first = await windowsCliFixture();
    const later = await windowsCliFixture('global', 'hoisted');
    await windowsCliWriteJson(first.packageJson, { ...first.packageMetadata, version: `${NATIVE_DB_VALIDATION.cliVersion}-unapproved` });
    await windowsCliRefuse(windowsCliInput(`${first.shimDir};${later.shimDir}`));
  });

  it('does not borrow a later package when the first shim has no adjacent package metadata', async () => {
    const first = await windowsCliFixture();
    const later = await windowsCliFixture();
    await unlink(first.packageJson);
    await windowsCliRefuse(windowsCliInput(`${first.shimDir};${later.shimDir}`));
  });

  it.each([
    ['wrong parent package name', async (fixture: WindowsCliFixture) => windowsCliWriteJson(fixture.packageJson, { ...fixture.packageMetadata, name: 'other-cli' })],
    ['wrong parent package version', async (fixture: WindowsCliFixture) => windowsCliWriteJson(fixture.packageJson, { ...fixture.packageMetadata, version: `${NATIVE_DB_VALIDATION.cliVersion}-unapproved` })],
    ['wrong launcher mapping', async (fixture: WindowsCliFixture) => windowsCliWriteJson(fixture.packageJson, { ...fixture.packageMetadata, bin: { supabase: 'dist/other.js' } })],
    ['wrong optional dependency pin', async (fixture: WindowsCliFixture) => windowsCliWriteJson(fixture.packageJson, { ...fixture.packageMetadata, optionalDependencies: { [fixture.optionalName]: `${NATIVE_DB_VALIDATION.cliVersion}-unapproved` } })],
    ['malformed parent metadata', async (fixture: WindowsCliFixture) => writeFile(fixture.packageJson, '{')],
    ['missing optional package metadata', async (fixture: WindowsCliFixture) => unlink(fixture.optionalJson)],
    ['wrong optional package name', async (fixture: WindowsCliFixture) => windowsCliWriteJson(fixture.optionalJson, { ...fixture.optionalMetadata, name: '@supabase/cli-linux-x64' })],
    ['wrong optional package version', async (fixture: WindowsCliFixture) => windowsCliWriteJson(fixture.optionalJson, { ...fixture.optionalMetadata, version: `${NATIVE_DB_VALIDATION.cliVersion}-unapproved` })],
    ['missing native executable', async (fixture: WindowsCliFixture) => unlink(fixture.executable)],
  ])('refuses incompatible package material: %s', async (_label, mutate) => {
    const fixture = await windowsCliFixture();
    await mutate(fixture);
    await windowsCliRefuse(windowsCliInput(fixture.shimDir));
  });

  it('rejects an adjacent package directory junction', async () => {
    const fixture = await windowsCliFixture();
    const ordinaryPackage = join(fixture.root, 'ordinary package');
    await rename(fixture.packageRoot, ordinaryPackage);
    await symlink(ordinaryPackage, fixture.packageRoot, 'junction');
    await windowsCliRefuse(windowsCliInput(fixture.shimDir));
  });

  it('rejects a junction inside the optional native binary path', async () => {
    const fixture = await windowsCliFixture();
    const ordinaryBin = join(fixture.optionalRoot, 'ordinary bin');
    await rename(dirname(fixture.executable), ordinaryBin);
    await symlink(ordinaryBin, dirname(fixture.executable), 'junction');
    await windowsCliRefuse(windowsCliInput(fixture.shimDir));
  });

  it('rejects a native executable reached through a PATH directory junction', async () => {
    const fixture = await windowsCliFixture();
    const ordinaryDir = join(fixture.root, 'ordinary native');
    const aliasDir = join(fixture.root, 'native alias');
    await mkdir(ordinaryDir);
    await writeFile(join(ordinaryDir, 'supabase.exe'), 'Inert standalone native fixture; never invoked.\n');
    await symlink(ordinaryDir, aliasDir, 'junction');
    await windowsCliRefuse(windowsCliInput(aliasDir));
  });
});
