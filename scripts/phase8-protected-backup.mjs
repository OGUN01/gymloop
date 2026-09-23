import { createCipheriv, createDecipheriv, createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { Buffer } from 'node:buffer';
import { execFile } from 'node:child_process';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { promisify } from 'node:util';
import { pathToFileURL } from 'node:url';
import { GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { backupEnv } from '../packages/shared/src/config/env.ts';
import { PHASE8_BACKUP_LIMITS } from '../packages/shared/src/config/constants.ts';

const execFileAsync = promisify(execFile);
const SOURCE_REF = 'pecxrpskmfeuyzngvewq';
const BACKUP_BUCKET = 'gymloop-backups';
const ARCHIVE_MAGIC = Buffer.from('GLBKP001');
const { ivBytes: IV_BYTES, tagBytes: TAG_BYTES, keyBytes: HASH_BYTES,
  maxSourceBytes: MAX_SOURCE_BYTES } = PHASE8_BACKUP_LIMITS;
const PARTS = Object.freeze([
  ['roles', 'dumpRoles'],
  ['schema', 'dumpSchema'],
  ['data', 'dumpData'],
  ['migrations', 'dumpMigrations'],
]);
const DUMP_COMMAND = Object.freeze({ binary: 'supabase', args: ['db', 'dump'] });

const DUMP_OPTIONS = Object.freeze({
  roles: ['--role-only'],
  schema: [],
  data: ['--use-copy', '--data-only', '--schema', 'public,auth', '-x', 'storage.buckets_vectors', '-x', 'storage.vector_indexes'],
  historySchema: ['--schema', 'supabase_migrations'],
  historyData: ['--use-copy', '--data-only', '--schema', 'supabase_migrations'],
});

export function backupDumpArgs(kind, filePath) {
  if (!Object.hasOwn(DUMP_OPTIONS, kind) || typeof filePath !== 'string' || filePath.length === 0) {
    throw safeReceiptError();
  }
  return [...DUMP_COMMAND.args, '--linked', '--file', filePath, ...DUMP_OPTIONS[kind]];
}

function digest(value) {
  return createHash('sha256').update(value).digest('hex');
}

function hasCopyStatement(data, prefix) {
  const marker = Buffer.from(prefix);
  let cursor = 0;
  while (cursor < data.length) {
    const found = data.indexOf(marker, cursor);
    if (found < 0) return false;
    if (found === 0 || data.subarray(found - 1, found).toString() === '\n') {
      const end = data.indexOf('\n', found);
      const line = data.subarray(found, end < 0 ? data.length : end).toString('utf8');
      if (line.endsWith(' FROM stdin;')) return true;
    }
    cursor = found + marker.length;
  }
  return false;
}

function safeReceiptError() {
  return new Error('Protected Cloud backup failed; no verified receipt was produced.');
}

function packArchive(sourceProjectRef, capturedAt, sourceHashes, sources) {
  const header = Buffer.from(JSON.stringify({ format: 'gymloop-cloud-logical-v1', sourceProjectRef, capturedAt,
    sourceHashes, lengths: Object.fromEntries(PARTS.map(([name]) => [name, sources[name].length])) }), 'utf8');
  const size = Buffer.alloc(PHASE8_BACKUP_LIMITS.archiveHeaderBytes);
  size.writeUInt32BE(header.length);
  return Buffer.concat([size, header, ...PARTS.map(([name]) => sources[name])]);
}

function encrypt(plaintext, key) {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  cipher.setAAD(ARCHIVE_MAGIC);
  const body = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([ARCHIVE_MAGIC, iv, cipher.getAuthTag(), body]);
}

function decrypt(ciphertext, key) {
  const minimum = ARCHIVE_MAGIC.length + IV_BYTES + TAG_BYTES + 1;
  if (ciphertext.length < minimum || !ciphertext.subarray(0, ARCHIVE_MAGIC.length).equals(ARCHIVE_MAGIC)) {
    throw safeReceiptError();
  }
  const ivStart = ARCHIVE_MAGIC.length;
  const tagStart = ivStart + IV_BYTES;
  const bodyStart = tagStart + TAG_BYTES;
  const decipher = createDecipheriv('aes-256-gcm', key, ciphertext.subarray(ivStart, tagStart));
  decipher.setAAD(ARCHIVE_MAGIC);
  decipher.setAuthTag(ciphertext.subarray(tagStart, bodyStart));
  return Buffer.concat([decipher.update(ciphertext.subarray(bodyStart)), decipher.final()]);
}

function exactFields(value, keys) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}

function validTimestamp(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) &&
    !Number.isNaN(Date.parse(value));
}

function canonicalBase64(value) {
  if (typeof value !== 'string' || value.length === 0) throw safeReceiptError();
  const bytes = Buffer.from(value, 'base64');
  if (bytes.length === 0 || bytes.toString('base64') !== value) throw safeReceiptError();
  return bytes;
}

export function decryptProtectedArchive(ciphertext, encryptionKey, expectedProjectRef) {
  try {
    if (!Buffer.isBuffer(ciphertext) || !Buffer.isBuffer(encryptionKey) ||
      encryptionKey.length !== HASH_BYTES || expectedProjectRef !== SOURCE_REF) throw safeReceiptError();
    const plaintext = decrypt(ciphertext, encryptionKey);
    if (plaintext.length < PHASE8_BACKUP_LIMITS.archiveHeaderBytes) throw safeReceiptError();
    const headerBytes = plaintext.readUInt32BE();
    if (headerBytes === 0 || headerBytes > PHASE8_BACKUP_LIMITS.maxHeaderBytes ||
      PHASE8_BACKUP_LIMITS.archiveHeaderBytes + headerBytes >= plaintext.length) throw safeReceiptError();
    const headerStart = PHASE8_BACKUP_LIMITS.archiveHeaderBytes;
    const header = JSON.parse(plaintext.subarray(headerStart, headerStart + headerBytes).toString('utf8'));
    if (!exactFields(header, ['format', 'sourceProjectRef', 'capturedAt', 'sourceHashes', 'lengths']) ||
      header.format !== 'gymloop-cloud-logical-v1' || header.sourceProjectRef !== expectedProjectRef ||
      !validTimestamp(header.capturedAt) ||
      !exactFields(header.sourceHashes, PARTS.map(([name]) => name)) ||
      !exactFields(header.lengths, PARTS.map(([name]) => name))) throw safeReceiptError();
    const parts = {};
    let cursor = headerStart + headerBytes;
    for (const [name] of PARTS) {
      const length = header.lengths[name];
      const hash = header.sourceHashes[name];
      if (!Number.isSafeInteger(length) || length <= 0 || length > MAX_SOURCE_BYTES ||
        typeof hash !== 'string' || !/^[0-9a-f]{64}$/.test(hash) ||
        cursor + length > plaintext.length) throw safeReceiptError();
      const part = plaintext.subarray(cursor, cursor + length);
      if (digest(part) !== hash) throw safeReceiptError();
      parts[name] = part;
      cursor += length;
    }
    if (cursor !== plaintext.length) throw safeReceiptError();
    const history = JSON.parse(parts.migrations.toString('utf8'));
    if (!exactFields(history, ['schema', 'data'])) throw safeReceiptError();
    const historySchema = canonicalBase64(history.schema);
    const historyData = canonicalBase64(history.data);
    return { sourceProjectRef: header.sourceProjectRef, capturedAt: header.capturedAt,
      sourceHashes: header.sourceHashes, parts, historySchema, historyData };
  } catch {
    throw safeReceiptError();
  }
}

export async function runProtectedBackup(config, ports) {
  try {
    if (config?.expectedProjectRef !== SOURCE_REF || config?.bucket !== BACKUP_BUCKET ||
      typeof config.objectKey !== 'string' || !/^[a-zA-Z0-9._/-]+$/.test(config.objectKey) ||
      config.objectKey.startsWith('/') || config.objectKey.includes('..') ||
      !Buffer.isBuffer(config.encryptionKey) || config.encryptionKey.length !== HASH_BYTES) {
      throw safeReceiptError();
    }
    const linkedRef = await ports.identifyLinkedProject();
    if (linkedRef !== config.expectedProjectRef) throw safeReceiptError();

    const sources = {};
    const sourceHashes = {};
    for (const [name, port] of PARTS) {
      const bytes = await ports[port]();
      if (!Buffer.isBuffer(bytes) || bytes.length === 0 || bytes.length > MAX_SOURCE_BYTES) throw safeReceiptError();
      if (name === 'data' && (!hasCopyStatement(bytes, 'COPY public.') ||
        !hasCopyStatement(bytes, 'COPY auth.users '))) throw safeReceiptError();
      sources[name] = bytes;
      sourceHashes[name] = digest(bytes);
    }
    const capturedAt = await ports.now();
    if (typeof capturedAt !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(capturedAt) ||
      Number.isNaN(Date.parse(capturedAt))) throw safeReceiptError();

    const plaintext = packArchive(linkedRef, capturedAt, sourceHashes, sources);
    const plaintextSha256 = digest(plaintext);
    const ciphertext = encrypt(plaintext, config.encryptionKey);
    const ciphertextSha256 = digest(ciphertext);
    await ports.uploadCiphertext(config.bucket, config.objectKey, ciphertext);
    const readback = await ports.downloadCiphertext(config.bucket, config.objectKey);
    if (!Buffer.isBuffer(readback) || readback.length !== ciphertext.length ||
      !timingSafeEqual(createHash('sha256').update(readback).digest(), createHash('sha256').update(ciphertext).digest())) {
      throw safeReceiptError();
    }
    const recovered = decrypt(readback, config.encryptionKey);
    if (digest(recovered) !== plaintextSha256 || !recovered.equals(plaintext)) throw safeReceiptError();
    return {
      sourceProjectRef: linkedRef,
      bucket: config.bucket,
      objectKey: config.objectKey,
      capturedAt,
      sourceHashes,
      plaintextSha256,
      ciphertextSha256,
      ciphertextBytes: ciphertext.length,
      verified: true,
    };
  } catch {
    throw safeReceiptError();
  }
}

async function runCommand(binary, args) {
  await execFileAsync(binary, args, { maxBuffer: PHASE8_BACKUP_LIMITS.commandOutputBytes,
    timeout: PHASE8_BACKUP_LIMITS.commandTimeoutMs });
}

async function runCloudBackup() {
  const runtime = backupEnv();
  const bucketClient = new S3Client({
    region: 'auto',
    endpoint: 'https://03b0a2097c32f21fc6f4598e1d6b1f1e.r2.cloudflarestorage.com',
    credentials: {
      accessKeyId: runtime.BACKUP_R2_ACCESS_KEY_ID,
      secretAccessKey: runtime.BACKUP_R2_SECRET_ACCESS_KEY,
    },
  });
  const encryptionKey = Buffer.from(runtime.BACKUP_ENCRYPTION_KEY_B64, 'base64');
  if (encryptionKey.length !== HASH_BYTES || encryptionKey.toString('base64') !== runtime.BACKUP_ENCRYPTION_KEY_B64) {
    throw safeReceiptError();
  }
  const root = resolve(import.meta.dirname, '..');
  const temp = await mkdtemp(join(tmpdir(), 'gymloop-protected-backup-'));
  const objectKey = `${new Date().toISOString().slice(0, PHASE8_BACKUP_LIMITS.isoDateLength)}/gymloop-cloud-${runtime.GITHUB_RUN_ID}-${runtime.GITHUB_RUN_ATTEMPT}.enc`;
  const dump = async (kind, filename) => {
    const file = join(temp, filename);
    process.stderr.write(`Protected Cloud backup stage: ${kind} dump started.\n`);
    await runCommand(DUMP_COMMAND.binary, backupDumpArgs(kind, file));
    process.stderr.write(`Protected Cloud backup stage: ${kind} dump completed.\n`);
    return readFile(file);
  };
  try {
    const receipt = await runProtectedBackup({ expectedProjectRef: SOURCE_REF, bucket: BACKUP_BUCKET,
      objectKey, encryptionKey }, {
      async identifyLinkedProject() {
        const linked = (await readFile(join(root, 'supabase', '.temp', 'project-ref'), 'utf8')).trim();
        return linked;
      },
      dumpRoles: () => dump('roles', 'roles.sql'),
      dumpSchema: () => dump('schema', 'schema.sql'),
      dumpData: () => dump('data', 'data.sql'),
      async dumpMigrations() {
        const schema = await dump('historySchema', 'history-schema.sql');
        const data = await dump('historyData', 'history-data.sql');
        return Buffer.from(JSON.stringify({ schema: schema.toString('base64'), data: data.toString('base64') }));
      },
      uploadCiphertext: async (bucket, key, body) => {
        process.stderr.write('Protected Cloud backup stage: encrypted upload started.\n');
        await bucketClient.send(new PutObjectCommand({
          Bucket: bucket, Key: key, Body: body, ContentType: 'application/octet-stream',
        }));
        process.stderr.write('Protected Cloud backup stage: encrypted upload completed.\n');
      },
      downloadCiphertext: async (bucket, key) => {
        process.stderr.write('Protected Cloud backup stage: encrypted readback started.\n');
        const object = await bucketClient.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
        if (!object.Body) throw safeReceiptError();
        const bytes = Buffer.from(await object.Body.transformToByteArray());
        process.stderr.write('Protected Cloud backup stage: encrypted readback completed.\n');
        return bytes;
      },
      now: () => new Date().toISOString(),
    });
    process.stdout.write(`${JSON.stringify(receipt)}\n`);
  } finally {
    encryptionKey.fill(0);
    bucketClient.destroy();
    await rm(temp, { recursive: true, force: true });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  runCloudBackup().catch(() => {
    process.stderr.write('Protected Cloud backup failed; no verified receipt was produced.\n');
    process.exitCode = 1;
  });
}
