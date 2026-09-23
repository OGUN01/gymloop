import { createCipheriv, createHash, randomBytes } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import {
  decryptProtectedArchive,
  runProtectedBackup,
} from '../../scripts/phase8-protected-backup.mjs'

const sourceProjectRef = 'pecxrpskmfeuyzngvewq'
const capturedAt = '2026-09-23T13:14:15.000Z'
const format = 'gymloop-cloud-logical-v1'
const magic = Buffer.from('GLBKP001', 'ascii')
const historySchema = Buffer.from('CREATE SCHEMA IF NOT EXISTS supabase_migrations;\n')
const historyData = Buffer.from('INSERT INTO supabase_migrations.schema_migrations VALUES (1);\n')

function sha256(bytes: Buffer) {
  return createHash('sha256').update(bytes).digest('hex')
}

function sourceParts() {
  return {
    roles: Buffer.from('CREATE ROLE HOLDOUT_PRIVATE_ROLE_X;\n'),
    schema: Buffer.from('CREATE TABLE public.holdout_private_x (id uuid);\n'),
    data: Buffer.from('COPY public.holdout_private_x FROM stdin;\nHOLDOUT_PRIVATE_MEMBER_X\n\\.\nCOPY auth.users FROM stdin;\nHOLDOUT_PRIVATE_AUTH_USER_X\n\\.\n'),
    migrations: Buffer.from(JSON.stringify({
      schema: historySchema.toString('base64'),
      data: historyData.toString('base64'),
    })),
  }
}

type Parts = ReturnType<typeof sourceParts>
type Header = {
  format: string
  sourceProjectRef: string
  capturedAt: string
  sourceHashes: Record<keyof Parts, string>
  lengths: Record<keyof Parts, number>
  [key: string]: unknown
}

function buildEncryptedObject(options: {
  key?: Buffer
  magic?: Buffer
  parts?: Parts
  changeHeader?: (header: Header) => void
  headerBytes?: Buffer
  declaredHeaderLength?: number
  appendPlaintext?: Buffer
  truncatePlaintextBytes?: number
} = {}) {
  const key = options.key ?? randomBytes(32)
  const parts = options.parts ?? sourceParts()
  const header: Header = {
    format,
    sourceProjectRef,
    capturedAt,
    sourceHashes: {
      roles: sha256(parts.roles),
      schema: sha256(parts.schema),
      data: sha256(parts.data),
      migrations: sha256(parts.migrations),
    },
    lengths: {
      roles: parts.roles.length,
      schema: parts.schema.length,
      data: parts.data.length,
      migrations: parts.migrations.length,
    },
  }
  options.changeHeader?.(header)
  const headerBytes = options.headerBytes ?? Buffer.from(JSON.stringify(header), 'utf8')
  const prefix = Buffer.alloc(4)
  prefix.writeUInt32BE(options.declaredHeaderLength ?? headerBytes.length)
  let plaintext = Buffer.concat([
    prefix,
    headerBytes,
    parts.roles,
    parts.schema,
    parts.data,
    parts.migrations,
    options.appendPlaintext ?? Buffer.alloc(0),
  ])
  if (options.truncatePlaintextBytes) plaintext = plaintext.subarray(0, -options.truncatePlaintextBytes)
  const envelopeMagic = options.magic ?? magic
  const iv = randomBytes(12)
  const cipher = createCipheriv('aes-256-gcm', key, iv)
  cipher.setAAD(envelopeMagic)
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()])
  const ciphertext = Buffer.concat([envelopeMagic, iv, cipher.getAuthTag(), encrypted])
  return { ciphertext, key, parts, header }
}

function expectRefusal(ciphertext: Buffer, key: Buffer, expectedRef = sourceProjectRef) {
  expect(typeof decryptProtectedArchive).toBe('function')
  let rejection: unknown
  try {
    decryptProtectedArchive(ciphertext, key, expectedRef)
  } catch (error) {
    rejection = error
  }
  expect(rejection).toBeInstanceOf(Error)
  const message = String(rejection)
  expect(message).not.toContain('HOLDOUT_PRIVATE_MEMBER_X')
  expect(message).not.toContain('HOLDOUT_PRIVATE_ROLE_X')
  expect(message).not.toContain(key.toString('hex'))
}

describe('HARD-007 authenticated archive extraction holdout', () => {
  it('returns exact four Buffer parts, source identity, source hashes and decoded history files', () => {
    const { ciphertext, key, parts, header } = buildEncryptedObject()
    const result = decryptProtectedArchive(ciphertext, key, sourceProjectRef)
    expect(result).toEqual({
      sourceProjectRef,
      capturedAt,
      sourceHashes: header.sourceHashes,
      parts,
      historySchema,
      historyData,
    })
    for (const item of Object.values(result.parts)) expect(Buffer.isBuffer(item)).toBe(true)
    expect(Buffer.isBuffer(result.historySchema)).toBe(true)
    expect(Buffer.isBuffer(result.historyData)).toBe(true)
  })

  it('reads a real writer-produced ciphertext object without changing any source bytes', async () => {
    const parts = sourceParts()
    const key = randomBytes(32)
    let uploaded: Buffer | undefined
    const receipt = await runProtectedBackup({
      expectedProjectRef: sourceProjectRef,
      bucket: 'gymloop-backups',
      objectKey: 'holdout/backup.enc',
      encryptionKey: key,
    }, {
      identifyLinkedProject: async () => sourceProjectRef,
      dumpRoles: async () => parts.roles,
      dumpSchema: async () => parts.schema,
      dumpData: async () => parts.data,
      dumpMigrations: async () => parts.migrations,
      uploadCiphertext: async (_bucket: string, _key: string, bytes: Buffer) => { uploaded = Buffer.from(bytes) },
      downloadCiphertext: async () => Buffer.from(uploaded!),
      now: async () => capturedAt,
    })
    expect(uploaded).toBeInstanceOf(Buffer)
    expect(receipt.verified).toBe(true)
    const extracted = decryptProtectedArchive(uploaded!, key, sourceProjectRef)
    expect(extracted.parts).toEqual(parts)
    expect(extracted.historySchema).toEqual(historySchema)
    expect(extracted.historyData).toEqual(historyData)
    expect(extracted.sourceHashes).toEqual(receipt.sourceHashes)
  })

  it('rejects the correct object for a foreign expected project', () => {
    const { ciphertext, key } = buildEncryptedObject()
    expectRefusal(ciphertext, key, 'foreign-project')
  })

  it.each([
    ['wrong 32-byte key', ({ ciphertext, key }: ReturnType<typeof buildEncryptedObject>) => ({ ciphertext, key: Buffer.from(key).fill(0) })],
    ['short key', ({ ciphertext }: ReturnType<typeof buildEncryptedObject>) => ({ ciphertext, key: Buffer.alloc(16) })],
    ['modified IV', ({ ciphertext, key }: ReturnType<typeof buildEncryptedObject>) => { const changed = Buffer.from(ciphertext); changed[8] ^= 1; return { ciphertext: changed, key } }],
    ['modified authentication tag', ({ ciphertext, key }: ReturnType<typeof buildEncryptedObject>) => { const changed = Buffer.from(ciphertext); changed[20] ^= 1; return { ciphertext: changed, key } }],
    ['modified encrypted body', ({ ciphertext, key }: ReturnType<typeof buildEncryptedObject>) => { const changed = Buffer.from(ciphertext); changed[changed.length - 1] ^= 1; return { ciphertext: changed, key } }],
    ['truncated object', ({ ciphertext, key }: ReturnType<typeof buildEncryptedObject>) => ({ ciphertext: ciphertext.subarray(0, -1), key })],
    ['appended object bytes', ({ ciphertext, key }: ReturnType<typeof buildEncryptedObject>) => ({ ciphertext: Buffer.concat([ciphertext, Buffer.from('extra')]), key })],
  ])('refuses %s before extracting bytes', (_label, mutate) => {
    const forged = mutate(buildEncryptedObject())
    expectRefusal(forged.ciphertext, forged.key)
  })

  it('rejects an unsupported but correctly authenticated magic/version', () => {
    const { ciphertext, key } = buildEncryptedObject({ magic: Buffer.from('GLBKP002', 'ascii') })
    expectRefusal(ciphertext, key)
  })

  it.each([
    ['header length larger than available bytes', { declaredHeaderLength: 65_535 }],
    ['zero header length', { declaredHeaderLength: 0 }],
    ['malformed header JSON', { headerBytes: Buffer.from('{broken') }],
    ['extra plaintext after four parts', { appendPlaintext: Buffer.from('extra') }],
    ['truncated fourth part', { truncatePlaintextBytes: 1 }],
  ])('refuses valid-GCM plaintext with %s', (_label, options) => {
    const { ciphertext, key } = buildEncryptedObject(options)
    expectRefusal(ciphertext, key)
  })

  it.each([
    ['wrong format', (header: Header) => { header.format = 'another-format' }],
    ['shifted part boundary', (header: Header) => { header.lengths.roles += 1; header.lengths.schema -= 1 }],
    ['negative part length', (header: Header) => { header.lengths.data = -1 }],
    ['missing part length', (header: Header) => { Reflect.deleteProperty(header.lengths, 'migrations') }],
    ['extra header field', (header: Header) => { header.extra = 'not in v1 header' }],
  ])('rejects a valid-GCM header with %s', (_label, changeHeader) => {
    const { ciphertext, key } = buildEncryptedObject({ changeHeader })
    expectRefusal(ciphertext, key)
  })

  it.each(['roles', 'schema', 'data', 'migrations'] as const)('rejects a mismatched %s hash under a valid GCM tag', (name) => {
    const { ciphertext, key } = buildEncryptedObject({
      changeHeader: (header) => { header.sourceHashes[name] = '0'.repeat(64) },
    })
    expectRefusal(ciphertext, key)
  })

  it('rejects a missing part even when its empty hash and GCM tag are consistent', () => {
    const parts = { ...sourceParts(), schema: Buffer.alloc(0) }
    const { ciphertext, key } = buildEncryptedObject({ parts })
    expectRefusal(ciphertext, key)
  })

  it.each([
    Buffer.from('not JSON'),
    Buffer.from(JSON.stringify({ schema: '', data: '' })),
    Buffer.from(JSON.stringify({ schema: historySchema.toString('base64') })),
    Buffer.from(JSON.stringify({ schema: '!!!!', data: historyData.toString('base64') })),
  ])('rejects a malformed or incomplete migration history pair', (migrations) => {
    const parts = { ...sourceParts(), migrations }
    const { ciphertext, key } = buildEncryptedObject({ parts })
    expectRefusal(ciphertext, key)
  })
})
