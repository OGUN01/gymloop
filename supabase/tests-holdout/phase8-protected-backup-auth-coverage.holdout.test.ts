import { createHash } from 'node:crypto';
import { Buffer } from 'node:buffer';
import { describe, expect, it, vi } from 'vitest';

import * as backupModule from '../../scripts/phase8-protected-backup.mjs';

type BackupKind = 'roles' | 'schema' | 'publicData' | 'authData' | 'historySchema' | 'historyData';
type DumpArgs = (kind: BackupKind, filePath: string) => string[];

const backupDumpArgs = (backupModule as unknown as { backupDumpArgs?: DumpArgs }).backupDumpArgs;
const { runProtectedBackup, decryptProtectedArchive } = backupModule;
const PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const OUTPUT_PATH = '/private space/data.sql';

function optionValue(args: string[], name: string): string | undefined {
  const index = args.indexOf(name);
  return index === -1 ? undefined : args[index + 1];
}

describe('HARD-007 independent Auth-inclusive backup holdout', () => {
  it('constructs separate linked data-only commands for public and auth', () => {
    expect(backupDumpArgs).toBeTypeOf('function');
    for (const [kind, selectedSchema] of [
      ['publicData', 'public'],
      ['authData', 'auth'],
    ] as const) {
      const args = backupDumpArgs!(kind, OUTPUT_PATH);
      expect(args.slice(0, 2)).toEqual(['db', 'dump']);
      expect(args).toContain('--linked');
      expect(args).toContain('--data-only');
      expect(args).toContain('--use-copy');
      expect(optionValue(args, '--file')).toBe(OUTPUT_PATH);
      expect(args.filter((part) => part === '--schema')).toHaveLength(1);
      expect(optionValue(args, '--schema')).toBe(selectedSchema);
      expect(args).not.toContain('--local');
      expect(args).not.toContain('--db-url');
      expect(args).not.toContain('--role-only');
      expect(args.join(' ')).not.toMatch(/--exclude(?:=|\s+)auth\.users(?:\s|$)/);
    }
  });

  it('keeps roles, default schema, and the two migration-history captures separate', () => {
    expect(backupDumpArgs).toBeTypeOf('function');

    const roles = backupDumpArgs!('roles', OUTPUT_PATH);
    const schema = backupDumpArgs!('schema', OUTPUT_PATH);
    const historySchema = backupDumpArgs!('historySchema', OUTPUT_PATH);
    const historyData = backupDumpArgs!('historyData', OUTPUT_PATH);
    for (const args of [roles, schema, historySchema, historyData]) {
      expect(args.slice(0, 2)).toEqual(['db', 'dump']);
      expect(args).toContain('--linked');
      expect(optionValue(args, '--file')).toBe(OUTPUT_PATH);
      expect(args).not.toContain('--local');
      expect(args).not.toContain('--db-url');
    }
    expect(roles).toContain('--role-only');
    expect(roles).not.toContain('--data-only');
    expect(schema).not.toContain('--role-only');
    expect(schema).not.toContain('--data-only');
    expect(schema).not.toContain('--schema');
    expect(optionValue(historySchema, '--schema')).toBe('supabase_migrations');
    expect(historySchema).not.toContain('--data-only');
    expect(optionValue(historyData, '--schema')).toBe('supabase_migrations');
    expect(historyData).toContain('--data-only');
  });

  it('preserves both public and Auth rows inside the four-part encrypted archive without disclosing SQL', async () => {
    const data = Buffer.from(
      'COPY "public"."members" FROM stdin;\nPUBLIC_MEMBER_SENTINEL\n\\.\n' +
      'COPY "auth"."users" FROM stdin;\nAUTH_USER_SENTINEL\n\\.\n',
    );
    const migrations = Buffer.from(JSON.stringify({
      schema: Buffer.from('CREATE TABLE supabase_migrations.schema_migrations ();').toString('base64'),
      data: Buffer.from('COPY supabase_migrations.schema_migrations FROM stdin;').toString('base64'),
    }));
    const parts = {
      roles: Buffer.from('CREATE ROLE holdout_role;'),
      schema: Buffer.from('CREATE TABLE public.members ();'),
      data,
      migrations,
    };
    const key = Buffer.alloc(32, 91);
    let uploaded: Buffer | undefined;
    const uploadCiphertext = vi.fn(async (_bucket: string, _objectKey: string, bytes: Buffer) => {
      uploaded = Buffer.from(bytes);
    });
    const downloadCiphertext = vi.fn(async () => Buffer.from(uploaded!));

    const receipt = await runProtectedBackup({
      expectedProjectRef: PROJECT_REF,
      bucket: 'gymloop-backups',
      objectKey: 'holdout/identity-coverage.enc',
      encryptionKey: key,
    }, {
      identifyLinkedProject: async () => PROJECT_REF,
      dumpRoles: async () => parts.roles,
      dumpSchema: async () => parts.schema,
      dumpData: async () => parts.data,
      dumpMigrations: async () => parts.migrations,
      uploadCiphertext,
      downloadCiphertext,
      now: () => '2026-09-23T00:00:00.000Z',
    });

    expect(uploadCiphertext).toHaveBeenCalledOnce();
    expect(downloadCiphertext).toHaveBeenCalledExactlyOnceWith('gymloop-backups', 'holdout/identity-coverage.enc');
    expect(uploaded?.subarray(0, 8).toString('ascii')).toBe('GLBKP001');
    expect(uploaded?.toString('utf8')).not.toContain('PUBLIC_MEMBER_SENTINEL');
    expect(uploaded?.toString('utf8')).not.toContain('AUTH_USER_SENTINEL');
    expect(JSON.stringify(receipt)).not.toContain('PUBLIC_MEMBER_SENTINEL');
    expect(JSON.stringify(receipt)).not.toContain('AUTH_USER_SENTINEL');
    expect(receipt.verified).toBe(true);
    expect(receipt.sourceHashes.data).toBe(createHash('sha256').update(data).digest('hex'));

    const restored = decryptProtectedArchive(uploaded!, key, PROJECT_REF);
    expect(Object.keys(restored.parts).sort()).toEqual(['data', 'migrations', 'roles', 'schema']);
    expect(restored.parts.data.equals(data)).toBe(true);
    expect(restored.parts.roles.equals(parts.roles)).toBe(true);
    expect(restored.parts.schema.equals(parts.schema)).toBe(true);
    expect(restored.parts.migrations.equals(parts.migrations)).toBe(true);
  });

  it.each([
    ['no public rows', 'COPY auth.users FROM stdin;\nAUTH_USER_SENTINEL\n\\.\n'],
    ['no Auth users', 'COPY public.members FROM stdin;\nPUBLIC_MEMBER_SENTINEL\n\\.\n'],
    ['Auth schema without users', 'COPY public.members FROM stdin;\nPUBLIC_MEMBER_SENTINEL\n\\.\nCOPY auth.sessions FROM stdin;\nAUTH_SESSION_SENTINEL\n\\.\n'],
    ['comment-only claims', '-- COPY public.members FROM stdin;\n-- COPY auth.users FROM stdin;\n'],
    ['empty Auth users table', 'COPY public.members FROM stdin;\nPUBLIC_MEMBER_SENTINEL\n\\.\nCOPY auth.users FROM stdin;\n\\.\n'],
  ])('refuses %s before uploading the archive', async (_case, sql) => {
    const uploadCiphertext = vi.fn();
    await expect(runProtectedBackup({
      expectedProjectRef: PROJECT_REF,
      bucket: 'gymloop-backups',
      objectKey: 'holdout/incomplete-identity.enc',
      encryptionKey: Buffer.alloc(32, 91),
    }, {
      identifyLinkedProject: async () => PROJECT_REF,
      dumpRoles: async () => Buffer.from('CREATE ROLE holdout_role;'),
      dumpSchema: async () => Buffer.from('CREATE TABLE public.members ();'),
      dumpData: async () => Buffer.from(sql),
      dumpMigrations: async () => Buffer.from(JSON.stringify({
        schema: Buffer.from('CREATE SCHEMA supabase_migrations;').toString('base64'),
        data: Buffer.from('COPY supabase_migrations.schema_migrations FROM stdin;').toString('base64'),
      })),
      uploadCiphertext,
      downloadCiphertext: async () => Buffer.alloc(0),
      now: () => '2026-09-23T00:00:00.000Z',
    })).rejects.toThrow();
    expect(uploadCiphertext).not.toHaveBeenCalled();
  });
});
