import { createCipheriv, createHash, randomBytes } from 'node:crypto';
import { beforeAll, describe, expect, it } from 'vitest';

const PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const OTHER_REF = 'another-cloud-project';
const CAPTURED_AT = '2026-09-23T12:00:00.000Z';
const KEY = Buffer.alloc(32, 0x39);
const MAGIC = Buffer.from('GLBKP001', 'ascii');
const HISTORY_SCHEMA = Buffer.from('CREATE TABLE supabase_migrations.schema_migrations (version text);\n');
const HISTORY_DATA = Buffer.from('COPY supabase_migrations.schema_migrations FROM stdin;\n20260923120000\n\\.\n');
const PARTS = {
  roles: Buffer.from('CREATE ROLE synthetic_restore_role;\n'),
  schema: Buffer.from('CREATE TABLE synthetic_restore_table (id uuid);\n'),
  data: Buffer.from('COPY synthetic_restore_table FROM stdin;\n11111111-2222-4333-8444-555555555555\n\\.\n'),
  migrations: Buffer.from(JSON.stringify({
    schema: HISTORY_SCHEMA.toString('base64'),
    data: HISTORY_DATA.toString('base64'),
  })),
};
const PART_NAMES = ['roles', 'schema', 'data', 'migrations'] as const;
const sha256 = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');
const sourceHashes = Object.fromEntries(PART_NAMES.map((name) => [name, sha256(PARTS[name])])) as Record<typeof PART_NAMES[number], string>;
const lengths = Object.fromEntries(PART_NAMES.map((name) => [name, PARTS[name].length])) as Record<typeof PART_NAMES[number], number>;
const header = () => ({
  format: 'gymloop-cloud-logical-v1',
  sourceProjectRef: PROJECT_REF,
  capturedAt: CAPTURED_AT,
  sourceHashes: { ...sourceHashes },
  lengths: { ...lengths },
});
const encodePlaintext = (metadata: Record<string, unknown> = header(), parts = PARTS) => {
  const json = Buffer.from(JSON.stringify(metadata));
  const headerSize = Buffer.alloc(4);
  headerSize.writeUInt32BE(json.length);
  return Buffer.concat([headerSize, json, ...PART_NAMES.map((name) => parts[name])]);
};
const seal = (plaintext: Buffer) => {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', KEY, iv);
  cipher.setAAD(MAGIC);
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([MAGIC, iv, cipher.getAuthTag(), encrypted]);
};
const archive = (metadata: Record<string, unknown> = header(), parts = PARTS) => seal(encodePlaintext(metadata, parts));

type Extracted = {
  sourceProjectRef: string;
  capturedAt: string;
  sourceHashes: typeof sourceHashes;
  parts: typeof PARTS;
  historySchema: Buffer;
  historyData: Buffer;
};
let decryptProtectedArchive: ((ciphertext: Buffer, encryptionKey: Buffer, expectedProjectRef: string) => Extracted) | undefined;
let runProtectedBackup: ((config: Record<string, unknown>, ports: Record<string, unknown>) => Promise<unknown>) | undefined;
const extract = (ciphertext: Buffer, key = KEY, expectedRef = PROJECT_REF) => {
  if (!decryptProtectedArchive) throw new Error('Protected archive reader is unavailable');
  return decryptProtectedArchive(ciphertext, key, expectedRef);
};

describe('HARD-007 authenticated protected archive extraction', () => {
  beforeAll(async () => {
    const module = await import('../phase8-protected-backup.mjs');
    expect(typeof module.decryptProtectedArchive).toBe('function');
    decryptProtectedArchive = module.decryptProtectedArchive;
    runProtectedBackup = module.runProtectedBackup;
  });

  it('decodes four exact Buffer parts and both migration history files from an independently sealed archive', () => {
    const ciphertext = archive();
    const original = Buffer.from(ciphertext);
    const result = extract(ciphertext);
    expect(result).toEqual({
      sourceProjectRef: PROJECT_REF,
      capturedAt: CAPTURED_AT,
      sourceHashes,
      parts: PARTS,
      historySchema: HISTORY_SCHEMA,
      historyData: HISTORY_DATA,
    });
    expect(ciphertext).toEqual(original);
  });

  it('reads the exact ciphertext produced by the backup runner and retrieved from its fake R2 port', async () => {
    expect(typeof runProtectedBackup).toBe('function');
    let uploaded: Buffer | undefined;
    const ports = {
      async identifyLinkedProject() { return PROJECT_REF; },
      async dumpRoles() { return Buffer.from(PARTS.roles); },
      async dumpSchema() { return Buffer.from(PARTS.schema); },
      async dumpData() { return Buffer.from(PARTS.data); },
      async dumpMigrations() { return Buffer.from(PARTS.migrations); },
      async uploadCiphertext(bucket: string, objectKey: string, bytes: Buffer) {
        expect([bucket, objectKey]).toEqual(['gymloop-backups', 'synthetic/archive.enc']);
        uploaded = Buffer.from(bytes);
      },
      async downloadCiphertext(bucket: string, objectKey: string) {
        expect([bucket, objectKey]).toEqual(['gymloop-backups', 'synthetic/archive.enc']);
        return Buffer.from(uploaded!);
      },
      async now() { return CAPTURED_AT; },
    };
    await runProtectedBackup!({
      expectedProjectRef: PROJECT_REF,
      bucket: 'gymloop-backups',
      objectKey: 'synthetic/archive.enc',
      encryptionKey: KEY,
    }, ports);
    expect(uploaded).toBeInstanceOf(Buffer);
    expect(extract(uploaded!)).toEqual({
      sourceProjectRef: PROJECT_REF,
      capturedAt: CAPTURED_AT,
      sourceHashes,
      parts: PARTS,
      historySchema: HISTORY_SCHEMA,
      historyData: HISTORY_DATA,
    });
  });

  it('rejects a foreign expected project and an authenticated foreign-source header', () => {
    expect(() => extract(archive(), KEY, OTHER_REF)).toThrow();
    expect(() => extract(archive({ ...header(), sourceProjectRef: OTHER_REF }))).toThrow();
  });

  it('rejects wrong keys, altered authenticated bytes, missing envelope bytes and trailing bytes', () => {
    const valid = archive();
    const changedTag = Buffer.from(valid);
    changedTag[MAGIC.length + 12] ^= 1;
    const changedBody = Buffer.from(valid);
    changedBody[changedBody.length - 1] ^= 1;
    for (const bytes of [
      Buffer.alloc(0),
      Buffer.from('roles.sql is plaintext'),
      valid.subarray(0, MAGIC.length - 1),
      valid.subarray(0, MAGIC.length + 12),
      valid.subarray(0, valid.length - 1),
      Buffer.concat([valid, Buffer.from([0])]),
      Buffer.concat([Buffer.from('BADMAGIC'), valid.subarray(MAGIC.length)]),
      changedTag,
      changedBody,
    ]) {
      expect(() => extract(bytes)).toThrow();
    }
    expect(() => extract(valid, Buffer.alloc(32, 0x38))).toThrow();
    for (const badKey of [Buffer.alloc(0), Buffer.alloc(31), Buffer.alloc(33)]) {
      expect(() => extract(valid, badKey)).toThrow();
    }
  });

  it('rejects authenticated malformed headers and exact-length violations', () => {
    for (const badHeader of [
      { ...header(), format: 'unknown-format' },
      { ...header(), sourceProjectRef: '' },
      { ...header(), capturedAt: 'not-utc' },
      { ...header(), unexpected: true },
      { ...header(), lengths: { ...lengths, roles: 0 } },
      { ...header(), lengths: { ...lengths, data: lengths.data + 1 } },
      { ...header(), lengths: { ...lengths, migrations: lengths.migrations - 1 } },
    ]) {
      expect(() => extract(archive(badHeader))).toThrow();
    }
    const zeroHeaderLength = encodePlaintext();
    zeroHeaderLength.writeUInt32BE(0);
    expect(() => extract(seal(zeroHeaderLength))).toThrow();
    const oversizedHeaderLength = encodePlaintext();
    oversizedHeaderLength.writeUInt32BE(oversizedHeaderLength.length + 1);
    expect(() => extract(seal(oversizedHeaderLength))).toThrow();
    expect(() => extract(seal(encodePlaintext().subarray(0, -1)))).toThrow();
    expect(() => extract(seal(Buffer.concat([encodePlaintext(), Buffer.from([0])])))).toThrow();
  });

  it('rejects an authenticated part whose bytes or recorded SHA-256 have changed', () => {
    const changedParts = { ...PARTS, schema: Buffer.from('CREATE TABLE changed (id uuid);\n') };
    expect(() => extract(archive(header(), changedParts))).toThrow();
    for (const name of PART_NAMES) {
      const badHashes = { ...sourceHashes, [name]: '0'.repeat(64) };
      expect(() => extract(archive({ ...header(), sourceHashes: badHashes }))).toThrow();
      const missingHashes = { ...sourceHashes } as Record<string, string>;
      delete missingHashes[name];
      expect(() => extract(archive({ ...header(), sourceHashes: missingHashes }))).toThrow();
    }
  });

  it('rejects malformed, incomplete or noncanonical migration-history encoding', () => {
    for (const migrations of [
      Buffer.alloc(0),
      Buffer.from('history_schema.sql only'),
      Buffer.from(JSON.stringify({ schema: HISTORY_SCHEMA.toString('base64') })),
      Buffer.from(JSON.stringify({ schema: '%%%', data: HISTORY_DATA.toString('base64') })),
      Buffer.from(JSON.stringify({ schema: HISTORY_SCHEMA.toString('base64'), data: '' })),
      Buffer.from(JSON.stringify({ schema: HISTORY_SCHEMA.toString('base64'), data: HISTORY_DATA.toString('base64'), extra: true })),
    ]) {
      const parts = { ...PARTS, migrations };
      const metadata = {
        ...header(),
        lengths: { ...lengths, migrations: migrations.length },
        sourceHashes: { ...sourceHashes, migrations: sha256(migrations) },
      };
      expect(() => extract(archive(metadata, parts))).toThrow();
    }
  });

  it('keeps credential and SQL bytes out of failure messages', () => {
    const invalid = Buffer.concat([archive(), Buffer.from('synthetic-secret-should-not-print')]);
    let caught: unknown;
    try { extract(invalid); } catch (error) { caught = error; }
    expect(caught).toBeInstanceOf(Error);
    for (const secret of [KEY.toString('hex'), PARTS.data.toString(), 'synthetic-secret-should-not-print']) {
      expect(String(caught)).not.toContain(secret);
    }
  });
});
