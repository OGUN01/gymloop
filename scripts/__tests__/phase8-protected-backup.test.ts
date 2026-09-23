import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { beforeAll, describe, expect, it } from 'vitest';

const PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const BUCKET = 'gymloop-backups';
const OBJECT_KEY = '2026-09-23/gymloop-cloud-120000.enc';
const CAPTURED_AT = '2026-09-23T12:00:00.000Z';
const ENCRYPTION_KEY = Buffer.alloc(32, 0x4b);
const WORKFLOW_PATH = new URL('../../.github/workflows/phase8-protected-backup.yml', import.meta.url);
const RUNNER_PATH = new URL('../phase8-protected-backup.mjs', import.meta.url);
const RUNBOOK_PATH = new URL('../../docs/runbooks/backup-and-restore.md', import.meta.url);
const SQL = {
  roles: Buffer.from('CREATE ROLE synthetic_backup_role;\n'),
  schema: Buffer.from('CREATE TABLE synthetic_backup_table (id uuid);\n'),
  data: Buffer.from('COPY synthetic_backup_table FROM stdin;\nsynthetic-member@example.invalid\n\\.\n'),
  migrations: Buffer.from('COPY supabase_migrations.schema_migrations FROM stdin;\n20260923120000\n\\.\n'),
};
const sha256 = (value: Buffer) => createHash('sha256').update(value).digest('hex');
const config = () => ({
  expectedProjectRef: PROJECT_REF,
  bucket: BUCKET,
  objectKey: OBJECT_KEY,
  encryptionKey: Buffer.from(ENCRYPTION_KEY),
});
const fakePorts = (overrides: Record<string, unknown> = {}) => {
  const calls: string[] = [];
  let uploaded: Buffer | undefined;
  const ports = {
    async identifyLinkedProject() { calls.push('identify'); return PROJECT_REF; },
    async dumpRoles() { calls.push('roles'); return Buffer.from(SQL.roles); },
    async dumpSchema() { calls.push('schema'); return Buffer.from(SQL.schema); },
    async dumpData() { calls.push('data'); return Buffer.from(SQL.data); },
    async dumpMigrations() { calls.push('migrations'); return Buffer.from(SQL.migrations); },
    async uploadCiphertext(bucket: string, objectKey: string, body: Buffer) {
      calls.push('upload');
      expect(bucket).toBe(BUCKET);
      expect(objectKey).toBe(OBJECT_KEY);
      expect(Buffer.isBuffer(body)).toBe(true);
      uploaded = Buffer.from(body);
    },
    async downloadCiphertext(bucket: string, objectKey: string) {
      calls.push('download');
      expect(bucket).toBe(BUCKET);
      expect(objectKey).toBe(OBJECT_KEY);
      return uploaded && Buffer.from(uploaded);
    },
    async now() { calls.push('now'); return CAPTURED_AT; },
    ...overrides,
  };
  return { ports, calls, uploaded: () => uploaded };
};
type Receipt = {
  sourceProjectRef: string;
  bucket: string;
  objectKey: string;
  capturedAt: string;
  sourceHashes: Record<keyof typeof SQL, string>;
  plaintextSha256: string;
  ciphertextSha256: string;
  ciphertextBytes: number;
  verified: boolean;
};
let backupRunner: ((options: ReturnType<typeof config>, ports: ReturnType<typeof fakePorts>['ports']) => Promise<Receipt>) | undefined;
const run = (options: ReturnType<typeof config>, ports: ReturnType<typeof fakePorts>['ports']) => {
  if (!backupRunner) throw new Error('Protected backup entry point is unavailable');
  return backupRunner(options, ports);
};

describe('HARD-007 protected Cloud export and R2 read-back', () => {
  beforeAll(async () => {
    const module = await import('../phase8-protected-backup.mjs');
    expect(typeof module.runProtectedBackup).toBe('function');
    backupRunner = module.runProtectedBackup;
  });

  it('rejects a foreign or missing linked project before any export or upload', async () => {
    for (const source of ['', 'another-cloud-project']) {
      const fake = fakePorts({ async identifyLinkedProject() { fake.calls.push('identify'); return source; } });
      await expect(run(config(), fake.ports)).rejects.toThrow();
      expect(fake.calls).toEqual(['identify']);
    }
  });

  it('captures all four sources, encrypts before upload, reads the exact object, and returns safe hashes', async () => {
    const fake = fakePorts();
    const receipt = await run(config(), fake.ports);
    const ciphertext = fake.uploaded();
    expect(ciphertext).toBeInstanceOf(Buffer);
    expect(ciphertext!.length).toBeGreaterThan(0);
    for (const part of Object.values(SQL)) expect(ciphertext!.includes(part)).toBe(false);
    expect(ciphertext!.toString('utf8')).not.toContain('synthetic-member@example.invalid');
    expect(fake.calls[0]).toBe('identify');
    for (const part of ['roles', 'schema', 'data', 'migrations']) {
      expect(fake.calls.indexOf(part)).toBeGreaterThan(0);
      expect(fake.calls.indexOf(part)).toBeLessThan(fake.calls.indexOf('upload'));
    }
    expect(fake.calls.indexOf('download')).toBeGreaterThan(fake.calls.indexOf('upload'));
    expect(receipt).toMatchObject({
      sourceProjectRef: PROJECT_REF,
      bucket: BUCKET,
      objectKey: OBJECT_KEY,
      capturedAt: CAPTURED_AT,
      ciphertextSha256: sha256(ciphertext!),
      ciphertextBytes: ciphertext!.length,
      verified: true,
      sourceHashes: {
        roles: sha256(SQL.roles),
        schema: sha256(SQL.schema),
        data: sha256(SQL.data),
        migrations: sha256(SQL.migrations),
      },
    });
    expect(receipt.plaintextSha256).toMatch(/^[0-9a-f]{64}$/);
    const publicReceipt = JSON.stringify(receipt);
    for (const secret of ['synthetic-member@example.invalid', SQL.schema.toString(), ENCRYPTION_KEY.toString('hex')]) {
      expect(publicReceipt).not.toContain(secret);
    }
  });

  it('binds the archive hash to every source part and reproduces it for identical source bytes', async () => {
    const first = await run(config(), fakePorts().ports);
    const replay = await run(config(), fakePorts().ports);
    expect(replay.plaintextSha256).toBe(first.plaintextSha256);
    for (const part of ['roles', 'schema', 'data', 'migrations'] as const) {
      const fake = fakePorts({
        [`dump${part[0].toUpperCase()}${part.slice(1)}`]: async () => Buffer.concat([SQL[part], Buffer.from('--changed\n')]),
      });
      const changed = await run(config(), fake.ports);
      expect(changed.plaintextSha256).not.toBe(first.plaintextSha256);
    }
  });

  it('fails closed on missing or failed exports before upload', async () => {
    for (const part of ['Roles', 'Schema', 'Data', 'Migrations']) {
      for (const failure of [Buffer.alloc(0), undefined, new Error('export failed')]) {
        const fake = fakePorts({
          [`dump${part}`]: async () => {
            fake.calls.push(part.toLowerCase());
            if (failure instanceof Error) throw failure;
            return failure;
          },
        });
        await expect(run(config(), fake.ports)).rejects.toThrow();
        expect(fake.calls).not.toContain('upload');
      }
    }
  });

  it('fails when the exact R2 object cannot be read back or ciphertext is altered', async () => {
    for (const response of ['missing', 'tampered', 'retrieval-error'] as const) {
      const fake = fakePorts({
        async downloadCiphertext(bucket: string, objectKey: string) {
          fake.calls.push('download');
          expect([bucket, objectKey]).toEqual([BUCKET, OBJECT_KEY]);
          if (response === 'retrieval-error') throw new Error('R2 read failed');
          if (response === 'missing') return undefined;
          const bytes = Buffer.from(fake.uploaded()!);
          bytes[bytes.length - 1] ^= 1;
          return bytes;
        },
      });
      await expect(run(config(), fake.ports)).rejects.toThrow();
      expect(fake.calls).toContain('upload');
      expect(fake.calls).toContain('download');
    }
  });

  it('rejects media bucket, absent key and failed upload without leaking credentials or data', async () => {
    const badBucket = fakePorts();
    await expect(run({ ...config(), bucket: 'gymloop-media' }, badBucket.ports)).rejects.toThrow();
    expect(badBucket.calls).not.toContain('upload');
    for (const badKey of [Buffer.alloc(0), Buffer.alloc(31), Buffer.alloc(33)]) {
      await expect(run({ ...config(), encryptionKey: badKey }, fakePorts().ports)).rejects.toThrow();
    }
    const secret = 'synthetic-member@example.invalid';
    const failed = fakePorts({ async uploadCiphertext() { throw new Error(`private ${secret}`); } });
    let caught: unknown;
    try { await run(config(), failed.ports); } catch (error) { caught = error; }
    expect(caught).toBeInstanceOf(Error);
    expect(String(caught)).not.toContain(secret);
    expect(failed.calls).not.toContain('download');
  });
});

describe('HARD-007 scheduled and manual backup delivery', () => {
  const workflow = existsSync(WORKFLOW_PATH) ? readFileSync(WORKFLOW_PATH, 'utf8') : '';
  const runnerSource = existsSync(RUNNER_PATH) ? readFileSync(RUNNER_PATH, 'utf8') : '';
  const runbook = readFileSync(RUNBOOK_PATH, 'utf8');

  it('offers both a scheduled cadence and a manual dispatch', () => {
    expect(workflow).toMatch(/workflow_dispatch\s*:/);
    expect(workflow).toMatch(/schedule\s*:\s*\r?\n\s*-\s*cron\s*:/);
    expect(workflow).toMatch(/permissions\s*:\s*\r?\n\s+contents\s*:\s*read/);
  });

  it('fixes the Cloud source and off-project backup bucket and invokes the official four-part CLI export', () => {
    expect(workflow).toContain(PROJECT_REF);
    expect(workflow).toContain(BUCKET);
    expect(workflow).toMatch(/phase8-protected-backup\.mjs/);
    expect(runnerSource).toMatch(/supabase[\s\S]{0,200}db[\s\S]{0,200}dump/);
    expect(runnerSource).toContain('--linked');
    expect(runnerSource).toContain('--role-only');
    expect(runnerSource).toContain('--data-only');
    expect(runnerSource).toContain('--use-copy');
    expect(runnerSource).toContain('supabase_migrations');
    expect(runnerSource).not.toMatch(/--local/);
  });

  it('uses separate backup encryption and bucket writer secrets without publishing SQL artifacts', () => {
    const secrets = [...workflow.matchAll(/secrets\.([A-Z0-9_]+)/g)].map((match) => match[1]);
    const encryptionKey = secrets.find((name) => /BACKUP.*ENCRYPT.*KEY|ENCRYPT.*BACKUP.*KEY/.test(name));
    const accessKeyId = secrets.find((name) => /BACKUP.*(?:R2|BUCKET).*ACCESS_KEY_ID/.test(name));
    const writerSecret = secrets.find((name) => /BACKUP.*(?:R2|BUCKET).*SECRET_ACCESS_KEY/.test(name));
    expect(encryptionKey).toBeTruthy();
    expect(accessKeyId).toBeTruthy();
    expect(writerSecret).toBeTruthy();
    expect(new Set([encryptionKey, accessKeyId, writerSecret]).size).toBe(3);
    expect(workflow).not.toMatch(/secrets\.(?:R2_ACCESS_KEY_ID|R2_SECRET_ACCESS_KEY)\b/);
    expect(workflow).not.toMatch(/actions\/upload-artifact[\s\S]{0,300}(?:roles|schema|data|history)\.sql/i);
  });

  it('names a responsible backup operator, cadence and dedicated bucket credential', () => {
    expect(/backup owner\s*:\s*(?:production owner|platform operator)/i.test(runbook)).toBe(true);
    expect(/(?:backup )?cadence\s*:\s*(?:daily|weekly|every\s+\d+\s+hours?)/i.test(runbook)).toBe(true);
    expect(/bucket.scoped/i.test(runbook)).toBe(true);
  });
});
