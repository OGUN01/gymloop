import { describe, expect, it } from 'vitest';

const projectRef = 'pecxrpskmfeuyzngvewq';
const bucket = 'gymloop-backups';
const objectKey = 'test/auth-coverage.enc';
const capturedAt = '2026-09-23T12:00:00.000Z';
const encryptionKey = Buffer.alloc(32, 0x42);
const publicCopy = 'COPY public.members (id, full_name) FROM stdin;\n11111111-1111-4111-8111-111111111111\tSynthetic Member\n\\.\n';
const authUsersCopy = 'COPY auth.users (id, email) FROM stdin;\n22222222-2222-4222-8222-222222222222\tsynthetic@example.invalid\n\\.\n';
const quotedPublicCopy = 'COPY "public"."members" (id, full_name) FROM stdin;\n11111111-1111-4111-8111-111111111111\tSynthetic Member\n\\.\n';
const quotedAuthUsersCopy = 'COPY "auth"."users" (id, email) FROM stdin;\n22222222-2222-4222-8222-222222222222\tsynthetic@example.invalid\n\\.\n';
const dataWithBothSchemas = Buffer.from(`${publicCopy}${authUsersCopy}`);
const quotedDataWithBothSchemas = Buffer.from(`${quotedPublicCopy}${quotedAuthUsersCopy}`);
const historySchema = Buffer.from('CREATE TABLE supabase_migrations.schema_migrations (version text);\n');
const historyData = Buffer.from('COPY supabase_migrations.schema_migrations FROM stdin;\n20260923120000\n\\.\n');
const parts = {
  roles: Buffer.from('CREATE ROLE synthetic_backup_role;\n'),
  schema: Buffer.from('CREATE TABLE public.members (id uuid, full_name text);\n'),
  data: dataWithBothSchemas,
  migrations: Buffer.from(JSON.stringify({
    schema: historySchema.toString('base64'),
    data: historyData.toString('base64'),
  })),
};

function commandParts(args: unknown): string[] {
  expect(Array.isArray(args)).toBe(true);
  expect((args as unknown[]).every((value) => typeof value === 'string')).toBe(true);
  const words = args as string[];
  return words[0] === 'supabase' ? words.slice(1) : words;
}

function optionValue(args: string[], option: string): string | undefined {
  const index = args.indexOf(option);
  if (index !== -1) return args[index + 1];
  return args.find((argument) => argument.startsWith(`${option}=`))?.slice(option.length + 1);
}

function optionCount(args: string[], option: string): number {
  return args.filter((argument) => argument === option || argument.startsWith(`${option}=`)).length;
}

function fakePorts(data: Buffer) {
  let uploaded: Buffer | undefined;
  let uploadCount = 0;
  return {
    ports: {
      async identifyLinkedProject() { return projectRef; },
      async dumpRoles() { return Buffer.from(parts.roles); },
      async dumpSchema() { return Buffer.from(parts.schema); },
      async dumpData() { return Buffer.from(data); },
      async dumpMigrations() { return Buffer.from(parts.migrations); },
      async uploadCiphertext(actualBucket: string, actualKey: string, ciphertext: Buffer) {
        expect([actualBucket, actualKey]).toEqual([bucket, objectKey]);
        uploadCount += 1;
        uploaded = Buffer.from(ciphertext);
      },
      async downloadCiphertext(actualBucket: string, actualKey: string) {
        expect([actualBucket, actualKey]).toEqual([bucket, objectKey]);
        return uploaded && Buffer.from(uploaded);
      },
      async now() { return capturedAt; },
    },
    uploaded: () => uploaded,
    uploadCount: () => uploadCount,
  };
}

describe('HARD-007 actual linked Cloud dump arguments and Auth coverage', () => {
  it.each([
    ['publicData', 'public'],
    ['authData', 'auth'],
  ])('selects exactly %s in a separate linked data-only CLI command', async (kind, schema) => {
    const module = await import('../phase8-protected-backup.mjs');
    expect(typeof module.backupDumpArgs).toBe('function');
    const filePath = `private/${kind}.sql`;
    const args = commandParts(module.backupDumpArgs(kind, filePath));

    expect(args.slice(0, 2)).toEqual(['db', 'dump']);
    expect(args).toContain('--linked');
    expect(optionValue(args, '--file')).toBe(filePath);
    expect(args).toContain('--data-only');
    expect(args).toContain('--use-copy');
    expect(optionCount(args, '--schema')).toBe(1);
    expect(optionValue(args, '--schema')).toBe(schema);
    expect(args).not.toContain('--local');
    expect(args).not.toContain('--db-url');
  });

  it('keeps the other four captures linked and migration history scoped without changing the archive parts', async () => {
    const module = await import('../phase8-protected-backup.mjs');
    expect(typeof module.backupDumpArgs).toBe('function');
    for (const kind of ['roles', 'schema', 'historySchema', 'historyData'] as const) {
      const filePath = `private/${kind}.sql`;
      const args = commandParts(module.backupDumpArgs(kind, filePath));
      expect(args.slice(0, 2)).toEqual(['db', 'dump']);
      expect(args).toContain('--linked');
      expect(optionValue(args, '--file')).toBe(filePath);
      expect(args).not.toContain('--local');
      expect(args).not.toContain('--db-url');
      if (kind === 'roles') expect(args).toContain('--role-only');
      if (kind === 'schema') expect(args).not.toContain('--data-only');
      if (kind === 'historySchema' || kind === 'historyData') {
        expect(optionCount(args, '--schema')).toBe(1);
        expect(optionValue(args, '--schema')).toBe('supabase_migrations');
      }
    }
  });

  it('rejects the former combined-schema data command and unknown capture kinds', async () => {
    const module = await import('../phase8-protected-backup.mjs');
    for (const kind of ['data', 'unknown']) {
      expect(() => module.backupDumpArgs(kind, `private/${kind}.sql`)).toThrow();
    }
  });

  it.each([
    ['unquoted', dataWithBothSchemas],
    ['quoted', quotedDataWithBothSchemas],
  ])('encrypts and reads back four exact parts including %s application and Auth identity rows', async (_label, data) => {
    const module = await import('../phase8-protected-backup.mjs');
    const fake = fakePorts(data);
    const receipt = await module.runProtectedBackup({ expectedProjectRef: projectRef, bucket, objectKey, encryptionKey }, fake.ports);

    expect(receipt.verified).toBe(true);
    expect(fake.uploadCount()).toBe(1);
    expect(fake.uploaded()).toBeInstanceOf(Buffer);
    const recovered = module.decryptProtectedArchive(fake.uploaded(), encryptionKey, projectRef);
    expect(recovered.parts).toEqual({ ...parts, data });
    expect(recovered.historySchema).toEqual(historySchema);
    expect(recovered.historyData).toEqual(historyData);
  });

  it.each([
    ['missing public rows', Buffer.from(authUsersCopy)],
    ['missing the auth schema', Buffer.from(publicCopy)],
    ['auth table present but auth.users missing', Buffer.from(`${publicCopy}COPY auth.sessions (id) FROM stdin;\n\\.\n`)],
    ['auth.users appears only in a comment', Buffer.from(`${publicCopy}-- COPY auth.users (id) FROM stdin;\n`)],
    ['only a schema preamble', Buffer.from('CREATE TABLE public.members (id uuid);\nCREATE TABLE auth.users (id uuid);\n')],
    ['an empty Auth users table', Buffer.from(`${publicCopy}COPY auth.users (id, email) FROM stdin;\n\\.\n`)],
    ['an empty public table', Buffer.from(`COPY public.members (id, full_name) FROM stdin;\n\\.\n${authUsersCopy}`)],
  ])('refuses a data dump with %s before uploading', async (_label, data) => {
    const module = await import('../phase8-protected-backup.mjs');
    const fake = fakePorts(data);

    await expect(module.runProtectedBackup({ expectedProjectRef: projectRef, bucket, objectKey, encryptionKey }, fake.ports)).rejects.toThrow();
    expect(fake.uploadCount()).toBe(0);
  });
});
