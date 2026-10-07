import { readFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS } from '../../packages/shared/src/config/constants';

async function executeHeldUploaderAcknowledgment(options: {
  identifier?: string;
  digest?: string;
  lineEnding?: '\n' | '\r\n';
  missingField?: 'id' | 'digest';
  receipt?: string | null;
  completed?: boolean;
  exitCode?: number;
  creationRefused?: boolean;
  collision?: boolean;
  distributionFile?: boolean;
  runtime?: Record<string, string>;
} = {}) {
  const source = readFileSync(resolve('scripts/native-database-validation.mjs'), 'utf8');
  const start = source.indexOf('async function uploadArtifact(');
  const end = source.indexOf('\n}', start);
  if (start === -1 || end === -1) throw new Error('The frozen private port was not found');
  const isolatedSource = source.slice(start, end + '\n}'.length);
  const directory = resolve('held-synthetic-private-directory');
  const payload = join(directory, 'retained-evidence.zip');
  const output = join(directory, `upload-${'01'.repeat(PHASE8_BACKUP_LIMITS.ivBytes)}.txt`);
  const runtime = {
    GITHUB_ACTIONS: 'true',
    ACTIONS_RUNTIME_TOKEN: 'held-synthetic-runtime-token',
    ACTIONS_RESULTS_URL: 'https://held.invalid/results',
    RUNNER_WORKSPACE: resolve('held-synthetic-workspace'),
    ...options.runtime,
  };
  const inherited = { ...runtime, HELD_INHERITED_VALUE: 'opaque-parent-value' };
  const distribution = resolve(runtime.RUNNER_WORKSPACE, '..', '_actions/actions/upload-artifact/v5/dist/upload/index.js');
  const identifier = options.identifier ?? '812300045678901234567890';
  const digest = options.digest ?? 'a'.repeat(NATIVE_DB_VALIDATION.digestHexLength);
  const lineEnding = options.lineEnding ?? '\n';
  const fields = [
    ...(options.missingField === 'digest' ? [] : ['artifact-digest<<HELD_DIGEST_END', digest, 'HELD_DIGEST_END']),
    ...(options.missingField === 'id' ? [] : ['artifact-id<<HELD_ID_END', identifier, 'HELD_ID_END']),
    '',
  ];
  const childReceipt = options.receipt === undefined ? fields.join(lineEnding) : options.receipt;
  const files = new Map<string, Buffer>();
  if (options.collision) files.set(output, Buffer.from('preexisting-private-file'));
  const events: string[] = [];
  const writes: { path: string; bytes: Buffer }[] = [];
  const captures: {
    command: string;
    args: string[];
    cwd: string;
    env: Record<string, string>;
    timeoutMs: number;
    maxBytes: number;
    existedBeforeChild: boolean;
    bytesBeforeChild: Buffer | undefined;
  }[] = [];
  const reads: { path: string; encoding: string }[] = [];
  const removals: string[] = [];
  const randomLengths: number[] = [];
  const ports = {
    resolve,
    join,
    NATIVE_DB_VALIDATION,
    PHASE8_BACKUP_LIMITS,
    process: { execPath: 'held-node-process', cwd: () => 'held-child-working-directory' },
    nativeDatabaseProcessEnv: () => inherited,
    refuse: (code: string) => Object.assign(new Error(code), { code }),
    stat: async (path: string) => {
      events.push('distribution');
      if (path !== distribution) throw new Error('Unexpected distribution path');
      return { isFile: () => options.distributionFile !== false };
    },
    randomBytes: (length: number) => {
      randomLengths.push(length);
      return Buffer.alloc(length, 1);
    },
    privateWrite: async (path: string, bytes: Buffer) => {
      events.push('private-create');
      writes.push({ path, bytes: Buffer.from(bytes) });
      if (options.creationRefused || files.has(path)) {
        throw Object.assign(new Error('Synthetic exclusive creation refused'), { code: 'EEXIST' });
      }
      files.set(path, Buffer.from(bytes));
    },
    capture: async (command: string, args: string[], invocation: {
      cwd: string;
      env: Record<string, string>;
      timeoutMs: number;
      maxBytes: number;
    }) => {
      events.push('child');
      const bytesBeforeChild = files.get(invocation.env.GITHUB_OUTPUT);
      const existedBeforeChild = bytesBeforeChild !== undefined;
      captures.push({
        command,
        args,
        ...invocation,
        existedBeforeChild,
        bytesBeforeChild: bytesBeforeChild && Buffer.from(bytesBeforeChild),
      });
      if (!existedBeforeChild) {
        return { completed: true, exitCode: 1, stdout: '', stderr: 'Synthetic official output-file prerequisite refused', signal: null };
      }
      if (childReceipt !== null) {
        files.set(invocation.env.GITHUB_OUTPUT, Buffer.concat([bytesBeforeChild, Buffer.from(childReceipt)]));
      }
      return { completed: options.completed ?? true, exitCode: options.exitCode ?? 0, stdout: '', stderr: '', signal: null };
    },
    readFile: async (path: string, encoding: string) => {
      events.push('read');
      reads.push({ path, encoding });
      const bytes = files.get(path);
      if (!bytes || encoding !== 'utf8') throw new Error('Synthetic output file unavailable');
      return bytes.toString('utf8');
    },
    rm: async (path: string) => {
      events.push('remove');
      removals.push(path);
      files.delete(path);
    },
  };
  const uploader = new Function('ports', `
    const { resolve, join, NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS, process,
      nativeDatabaseProcessEnv, refuse, stat, randomBytes, privateWrite, capture, readFile, rm } = ports;
    ${isolatedSource}
    return uploadArtifact;
  `)(ports) as (runtime: Record<string, string>, name: string, path: string, directory: string) => Promise<{ id: string; digest: string }>;
  let receipt: { id: string; digest: string } | undefined;
  let error: unknown;
  try {
    receipt = await uploader(runtime, 'held-custody-artifact', payload, directory);
  } catch (failure) {
    error = failure;
  }
  return { receipt, error, files, events, writes, captures, reads, removals, randomLengths, output, directory, payload, distribution, inherited };
}

describe('frozen held uploader acknowledgment contract', () => {
  it('satisfies the official child output-file existence prerequisite before accepting the acknowledgment', async () => {
    const result = await executeHeldUploaderAcknowledgment();
    expect(result.captures[0]?.existedBeforeChild).toBe(true);
    expect(result.error).toBeUndefined();
    expect(result.receipt).toEqual({ id: '812300045678901234567890', digest: 'a'.repeat(NATIVE_DB_VALIDATION.digestHexLength) });
  });

  it('creates the private channel through privateWrite with empty bytes before the child starts', async () => {
    const result = await executeHeldUploaderAcknowledgment();
    expect(result.writes).toEqual([{ path: result.output, bytes: Buffer.alloc(0) }]);
    expect(result.captures[0]?.bytesBeforeChild).toEqual(Buffer.alloc(0));
    expect(result.events.indexOf('private-create')).toBeLessThan(result.events.indexOf('child'));
  });

  it('does not start the child when exclusive creation is refused', async () => {
    const result = await executeHeldUploaderAcknowledgment({ creationRefused: true });
    expect(result.error).toBeDefined();
    expect(result.writes).toHaveLength(1);
    expect(result.captures).toHaveLength(0);
    expect(result.reads).toHaveLength(0);
  });

  it('cannot overwrite a private output channel that already exists', async () => {
    const result = await executeHeldUploaderAcknowledgment({ collision: true });
    expect(result.error).toBeDefined();
    expect(result.captures).toHaveLength(0);
    expect(result.files.get(result.output)).toEqual(Buffer.from('preexisting-private-file'));
  });

  it('returns the canonical identifier and digest actually emitted by the child', async () => {
    const digest = 'f'.repeat(NATIVE_DB_VALIDATION.digestHexLength);
    const result = await executeHeldUploaderAcknowledgment({ identifier: '947123456789012345678901', digest });
    expect(result.error).toBeUndefined();
    expect(result.receipt).toEqual({ id: '947123456789012345678901', digest });
  });

  it('accepts the existing multiline output protocol with CRLF endings', async () => {
    const result = await executeHeldUploaderAcknowledgment({ identifier: '9', lineEnding: '\r\n' });
    expect(result.error).toBeUndefined();
    expect(result.receipt?.id).toBe('9');
  });

  it('preserves the official v5 process, inherited inputs, bounds, and no-overwrite settings', async () => {
    const result = await executeHeldUploaderAcknowledgment();
    expect(result.captures).toHaveLength(1);
    expect(result.captures[0]).toMatchObject({
      command: 'held-node-process',
      args: [result.distribution],
      cwd: 'held-child-working-directory',
      timeoutMs: NATIVE_DB_VALIDATION.nativeCleanupReserveMs,
      maxBytes: NATIVE_DB_VALIDATION.timeoutQueryMaxBytes,
      env: {
        ...result.inherited,
        INPUT_NAME: 'held-custody-artifact',
        INPUT_PATH: result.payload,
        'INPUT_IF-NO-FILES-FOUND': 'error',
        'INPUT_RETENTION-DAYS': String(NATIVE_DB_VALIDATION.artifactRetentionDays),
        'INPUT_COMPRESSION-LEVEL': '0',
        INPUT_OVERWRITE: 'false',
        'INPUT_INCLUDE-HIDDEN-FILES': 'false',
        GITHUB_OUTPUT: result.output,
      },
    });
    expect(result.randomLengths).toEqual([PHASE8_BACKUP_LIMITS.ivBytes]);
    expect(basename(result.output)).toBe(`upload-${'01'.repeat(PHASE8_BACKUP_LIMITS.ivBytes)}.txt`);
    expect(result.writes[0]?.path).toBe(join(result.directory, basename(result.output)));
  });

  it('refuses a non-file official distribution before any uploader starts', async () => {
    const result = await executeHeldUploaderAcknowledgment({ distributionFile: false });
    expect(result.error).toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
    expect(result.captures).toHaveLength(0);
  });

  it('refuses a non-Actions runtime before any uploader starts', async () => {
    const result = await executeHeldUploaderAcknowledgment({ runtime: { GITHUB_ACTIONS: 'false' } });
    expect(result.error).toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
    expect(result.captures).toHaveLength(0);
  });

  it.each(['ACTIONS_RUNTIME_TOKEN', 'ACTIONS_RESULTS_URL'])('refuses an absent required runtime input: %s', async (field) => {
    const result = await executeHeldUploaderAcknowledgment({ runtime: { [field]: '' } });
    expect(result.error).toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
    expect(result.captures).toHaveLength(0);
  });

  it('does not accept valid outputs after a nonzero child exit', async () => {
    const result = await executeHeldUploaderAcknowledgment({ exitCode: 1 });
    expect(result.error).toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
    expect(result.receipt).toBeUndefined();
    expect(result.reads).toHaveLength(0);
    expect(result.removals).toHaveLength(0);
  });

  it('does not accept valid outputs from an incomplete child even with exit zero', async () => {
    const result = await executeHeldUploaderAcknowledgment({ completed: false, exitCode: 0 });
    expect(result.error).toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
    expect(result.receipt).toBeUndefined();
    expect(result.reads).toHaveLength(0);
    expect(result.removals).toHaveLength(0);
  });

  it('refuses an empty output file after the child reports success', async () => {
    const result = await executeHeldUploaderAcknowledgment({ receipt: null });
    expect(result.captures[0]?.existedBeforeChild).toBe(true);
    expect(result.error).toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
    expect(result.receipt).toBeUndefined();
    expect(result.removals).toHaveLength(0);
  });

  it.each(['id', 'digest'] as const)('refuses the acknowledgment when the %s field is missing', async (missingField) => {
    const result = await executeHeldUploaderAcknowledgment({ missingField });
    expect(result.captures[0]?.existedBeforeChild).toBe(true);
    expect(result.error).toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
    expect(result.receipt).toBeUndefined();
    expect(result.removals).toHaveLength(0);
  });

  it.each(['0', '-7', '08', '9.1', ' 9', '9 ', ''])('refuses the noncanonical artifact identifier %j', async (identifier) => {
    const result = await executeHeldUploaderAcknowledgment({ identifier });
    expect(result.captures[0]?.existedBeforeChild).toBe(true);
    expect(result.error).toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
    expect(result.receipt).toBeUndefined();
    expect(result.removals).toHaveLength(0);
  });

  it.each(['uppercase', 'short', 'long', 'nonhex', 'empty'])('refuses a malformed SHA256 digest: %s', async (form) => {
    const valid = 'a'.repeat(NATIVE_DB_VALIDATION.digestHexLength);
    const digest = form === 'uppercase' ? valid.toUpperCase()
      : form === 'short' ? valid.slice(1)
        : form === 'long' ? `${valid}a`
          : form === 'nonhex' ? `g${valid.slice(1)}` : '';
    const result = await executeHeldUploaderAcknowledgment({ digest });
    expect(result.captures[0]?.existedBeforeChild).toBe(true);
    expect(result.error).toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
    expect(result.receipt).toBeUndefined();
    expect(result.removals).toHaveLength(0);
  });

  it('requires the matching actual multiline delimiter for each output field', async () => {
    const result = await executeHeldUploaderAcknowledgment({
      receipt: ['artifact-id<<HELD_ID_END', '9', 'OTHER_END', 'artifact-digest<<HELD_DIGEST_END', 'a'.repeat(NATIVE_DB_VALIDATION.digestHexLength), 'HELD_DIGEST_END', ''].join('\n'),
    });
    expect(result.captures[0]?.existedBeforeChild).toBe(true);
    expect(result.error).toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
    expect(result.receipt).toBeUndefined();
  });

  it('reads the actual child file and removes only that channel after accepted decoding', async () => {
    const result = await executeHeldUploaderAcknowledgment();
    expect(result.error).toBeUndefined();
    expect(result.reads).toEqual([{ path: result.output, encoding: 'utf8' }]);
    expect(result.removals).toEqual([result.output]);
    expect(result.events.indexOf('child')).toBeLessThan(result.events.indexOf('read'));
    expect(result.events.indexOf('read')).toBeLessThan(result.events.indexOf('remove'));
    expect(result.files.has(result.output)).toBe(false);
  });
});
