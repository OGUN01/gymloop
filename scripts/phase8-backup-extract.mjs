import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { join, resolve, sep } from 'node:path';
import { backupKeyEnv } from '../packages/shared/src/config/env.ts';
import { PHASE8_BACKUP_LIMITS } from '../packages/shared/src/config/constants.ts';
import { decryptProtectedArchive } from './phase8-protected-backup.mjs';

const SOURCE_REF = 'pecxrpskmfeuyzngvewq';

async function extract() {
  const [objectFile, outputParent, expectedHash] = process.argv.slice(PHASE8_BACKUP_LIMITS.cliArgumentStart);
  if (!objectFile || !outputParent || !/^[0-9a-f]{64}$/.test(expectedHash ?? '')) {
    throw new Error('Usage: node scripts/phase8-backup-extract.mjs <encrypted-object> <private-output-parent> <receipt-ciphertext-sha256>');
  }
  const key = Buffer.from(backupKeyEnv().BACKUP_ENCRYPTION_KEY_B64, 'base64');
  if (key.length !== PHASE8_BACKUP_LIMITS.keyBytes) throw new Error('Protected backup key is invalid.');
  const ciphertext = await readFile(resolve(objectFile));
  const actualHash = createHash('sha256').update(ciphertext).digest('hex');
  if (actualHash !== expectedHash) throw new Error('Encrypted object does not match the recorded receipt.');
  const archive = decryptProtectedArchive(ciphertext, key, SOURCE_REF);
  const parent = resolve(outputParent);
  const output = await mkdtemp(join(parent, 'gymloop-recovery-'));
  if (!output.startsWith(`${parent}${sep}`)) throw new Error('Recovery output escaped its private parent.');
  try {
    const files = {
      'roles.sql': archive.parts.roles,
      'schema.sql': archive.parts.schema,
      'data.sql': archive.parts.data,
      'history_schema.sql': archive.historySchema,
      'history_data.sql': archive.historyData,
    };
    for (const [name, bytes] of Object.entries(files)) {
      await writeFile(join(output, name), bytes, { flag: 'wx', mode: PHASE8_BACKUP_LIMITS.privateFileMode });
    }
    process.stdout.write(`${JSON.stringify({ output, sourceProjectRef: archive.sourceProjectRef,
      capturedAt: archive.capturedAt, sourceHashes: archive.sourceHashes,
      ciphertextSha256: actualHash })}\n`);
  } catch {
    await rm(output, { recursive: true, force: true });
    throw new Error('Private recovery extraction failed.');
  } finally {
    key.fill(0);
  }
}

extract().catch(() => {
  process.stderr.write('Protected backup extraction failed; no usable SQL output was confirmed.\n');
  process.exitCode = 1;
});
