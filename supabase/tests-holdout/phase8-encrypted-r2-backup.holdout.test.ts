import { createHash, randomBytes } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { runProtectedBackup } from '../../scripts/phase8-protected-backup.mjs'

const linkedRef = 'pecxrpskmfeuyzngvewq'
const capturedAt = '2026-09-23T12:34:56.000Z'
const sourceParts = {
  roles: Buffer.from('-- roles dump HOLDOUT_PRIVATE_ROLE_X\n'),
  schema: Buffer.from('-- schema dump HOLDOUT_PRIVATE_SCHEMA_X\n'),
  data: Buffer.from('-- data dump HOLDOUT_PRIVATE_MEMBER_X\n'),
  migrations: Buffer.from('-- migration history HOLDOUT_PRIVATE_HISTORY_X\n'),
}

function sha256(bytes: Buffer) {
  return createHash('sha256').update(bytes).digest('hex')
}

function configuration() {
  return {
    expectedProjectRef: linkedRef,
    bucket: 'gymloop-backups',
    objectKey: 'pilot/2026-09-23/backup.enc',
    encryptionKey: randomBytes(32),
  }
}

type PortState = {
  calls: string[]
  uploaded: Buffer | undefined
  uploadedBucket: string | undefined
  uploadedKey: string | undefined
  downloadedBucket: string | undefined
  downloadedKey: string | undefined
}

type Overrides = {
  identifyLinkedProject?: () => string | Promise<string>
  dumpRoles?: () => Buffer | Promise<Buffer>
  dumpSchema?: () => Buffer | Promise<Buffer>
  dumpData?: () => Buffer | Promise<Buffer>
  dumpMigrations?: () => Buffer | Promise<Buffer>
  uploadCiphertext?: (state: PortState, ciphertext: Buffer) => void | Promise<void>
  downloadCiphertext?: (state: PortState) => Buffer | Promise<Buffer>
}

function fakePorts(overrides: Overrides = {}) {
  const state: PortState = {
    calls: [],
    uploaded: undefined,
    uploadedBucket: undefined,
    uploadedKey: undefined,
    downloadedBucket: undefined,
    downloadedKey: undefined,
  }
  const ports = {
    async identifyLinkedProject() {
      state.calls.push('identifyLinkedProject')
      return overrides.identifyLinkedProject ? await overrides.identifyLinkedProject() : linkedRef
    },
    async dumpRoles() {
      state.calls.push('dumpRoles')
      return overrides.dumpRoles ? await overrides.dumpRoles() : sourceParts.roles
    },
    async dumpSchema() {
      state.calls.push('dumpSchema')
      return overrides.dumpSchema ? await overrides.dumpSchema() : sourceParts.schema
    },
    async dumpData() {
      state.calls.push('dumpData')
      return overrides.dumpData ? await overrides.dumpData() : sourceParts.data
    },
    async dumpMigrations() {
      state.calls.push('dumpMigrations')
      return overrides.dumpMigrations ? await overrides.dumpMigrations() : sourceParts.migrations
    },
    async uploadCiphertext(bucket: string, objectKey: string, bytes: Buffer) {
      state.calls.push('uploadCiphertext')
      state.uploadedBucket = bucket
      state.uploadedKey = objectKey
      state.uploaded = Buffer.from(bytes)
      await overrides.uploadCiphertext?.(state, bytes)
    },
    async downloadCiphertext(bucket: string, objectKey: string) {
      state.calls.push('downloadCiphertext')
      state.downloadedBucket = bucket
      state.downloadedKey = objectKey
      return overrides.downloadCiphertext ? await overrides.downloadCiphertext(state) : Buffer.from(state.uploaded!)
    },
    async now() {
      state.calls.push('now')
      return capturedAt
    },
  }
  return { ports, state }
}

async function expectFailure(action: () => Promise<unknown>, forbidden: string[] = []) {
  let failure: unknown
  try {
    await action()
  } catch (error) {
    failure = error
  }
  expect(failure).toBeInstanceOf(Error)
  for (const privateValue of forbidden) expect(String(failure).includes(privateValue)).toBe(false)
}

describe('HARD-007 protected R2 backup holdout', () => {
  it('captures four distinct source parts, encrypts before upload, reads back the exact object and returns safe hashes', async () => {
    const config = configuration()
    const { ports, state } = fakePorts()
    const receipt = await runProtectedBackup(config, ports)
    expect(state.calls[0]).toBe('identifyLinkedProject')
    for (const part of ['dumpRoles', 'dumpSchema', 'dumpData', 'dumpMigrations']) {
      expect(state.calls.filter((call) => call === part)).toHaveLength(1)
      expect(state.calls.indexOf(part)).toBeLessThan(state.calls.indexOf('uploadCiphertext'))
    }
    expect(state.calls.indexOf('uploadCiphertext')).toBeLessThan(state.calls.indexOf('downloadCiphertext'))
    expect(state.uploaded).toBeInstanceOf(Buffer)
    expect(state.uploaded!.length).toBeGreaterThan(0)
    expect(state.uploadedBucket).toBe(config.bucket)
    expect(state.downloadedBucket).toBe(config.bucket)
    expect(state.uploadedKey).toBe(config.objectKey)
    expect(state.downloadedKey).toBe(config.objectKey)
    for (const part of Object.values(sourceParts)) {
      expect(state.uploaded!.includes(part)).toBe(false)
      expect(state.uploaded!.includes(part.toString('utf8'))).toBe(false)
    }
    expect(state.uploaded!.includes(config.encryptionKey)).toBe(false)
    expect(receipt.sourceHashes).toEqual({
      roles: sha256(sourceParts.roles),
      schema: sha256(sourceParts.schema),
      data: sha256(sourceParts.data),
      migrations: sha256(sourceParts.migrations),
    })
    const safe = JSON.stringify(receipt)
    expect(safe).toContain(linkedRef)
    expect(safe).toContain(config.objectKey)
    expect(safe).toContain(capturedAt)
    expect(safe).toContain(sha256(state.uploaded!))
    expect(Object.values(receipt).some((value) => value === state.uploaded!.length)).toBe(true)
    expect(Object.values(receipt).some((value) => value === true || value === 'verified' || value === 'passed')).toBe(true)
    expect(safe).not.toContain(config.encryptionKey.toString('hex'))
    expect(safe).not.toContain(config.encryptionKey.toString('base64'))
    expect(safe).not.toMatch(/HOLDOUT_PRIVATE_(ROLE|SCHEMA|MEMBER|HISTORY)_X/)
  })

  it.each([
    ['wrong linked project', { identifyLinkedProject: () => 'foreign-project' }],
    ['unobserved linked project', { identifyLinkedProject: () => '' }],
  ])('refuses %s before any export or upload', async (_case, overrides) => {
    const { ports, state } = fakePorts(overrides)
    await expectFailure(() => runProtectedBackup(configuration(), ports))
    expect(state.calls).toEqual(['identifyLinkedProject'])
    expect(state.uploaded).toBeUndefined()
  })

  it('refuses a caller-configured project other than the linked Cloud project', async () => {
    const config = { ...configuration(), expectedProjectRef: 'foreign-project' }
    const { ports, state } = fakePorts({ identifyLinkedProject: () => 'foreign-project' })
    await expectFailure(() => runProtectedBackup(config, ports))
    expect(state.calls).not.toContain('dumpRoles')
    expect(state.calls).not.toContain('uploadCiphertext')
  })

  it('refuses the media bucket and an invalid encryption key before upload', async () => {
    const media = configuration()
    media.bucket = 'gymloop-media'
    const first = fakePorts()
    await expectFailure(() => runProtectedBackup(media, first.ports))
    expect(first.state.uploaded).toBeUndefined()
    const weakKey = configuration()
    weakKey.encryptionKey = Buffer.alloc(16)
    const second = fakePorts()
    await expectFailure(() => runProtectedBackup(weakKey, second.ports))
    expect(second.state.uploaded).toBeUndefined()
  })

  it.each([
    ['roles', { dumpRoles: () => Buffer.alloc(0) }],
    ['schema', { dumpSchema: () => Buffer.alloc(0) }],
    ['data', { dumpData: () => Buffer.alloc(0) }],
    ['migration history', { dumpMigrations: () => Buffer.alloc(0) }],
  ])('does not upload when %s is missing', async (_case, overrides) => {
    const { ports, state } = fakePorts(overrides)
    await expectFailure(() => runProtectedBackup(configuration(), ports))
    expect(state.uploaded).toBeUndefined()
  })

  it('does not upload a partial archive after a failed export', async () => {
    const { ports, state } = fakePorts({
      dumpData: () => { throw new Error(`export failed: ${sourceParts.data.toString('utf8')}`) },
    })
    await expectFailure(() => runProtectedBackup(configuration(), ports), ['HOLDOUT_PRIVATE_MEMBER_X'])
    expect(state.calls).not.toContain('uploadCiphertext')
  })

  it('fails when ciphertext upload or exact R2 read-back fails', async () => {
    const upload = fakePorts({ uploadCiphertext: () => { throw new Error('R2 write denied') } })
    await expectFailure(() => runProtectedBackup(configuration(), upload.ports))
    expect(upload.state.calls).not.toContain('downloadCiphertext')
    const download = fakePorts({ downloadCiphertext: () => { throw new Error('R2 read denied') } })
    await expectFailure(() => runProtectedBackup(configuration(), download.ports))
    expect(download.state.calls).toContain('downloadCiphertext')
  })

  it.each([
    ['one changed byte', (bytes: Buffer) => { const changed = Buffer.from(bytes); changed[changed.length - 1] ^= 1; return changed }],
    ['truncated object', (bytes: Buffer) => bytes.subarray(0, bytes.length - 1)],
    ['empty object', () => Buffer.alloc(0)],
  ])('refuses %s from the exact uploaded object', async (_case, corrupt) => {
    const { ports, state } = fakePorts({ downloadCiphertext: (current) => corrupt(current.uploaded!) })
    await expectFailure(() => runProtectedBackup(configuration(), ports))
    expect(state.calls).toContain('uploadCiphertext')
    expect(state.calls).toContain('downloadCiphertext')
  })

  it('changes source hashes when a source part changes, regardless of randomized ciphertext', async () => {
    const first = await runProtectedBackup(configuration(), fakePorts().ports)
    const changedData = Buffer.from('-- data dump HOLDOUT_PRIVATE_MEMBER_Y\n')
    const second = await runProtectedBackup(configuration(), fakePorts({ dumpData: () => changedData }).ports)
    expect(first.sourceHashes.data).toBe(sha256(sourceParts.data))
    expect(second.sourceHashes.data).toBe(sha256(changedData))
    expect(second.sourceHashes.data).not.toBe(first.sourceHashes.data)
    expect(second.sourceHashes.roles).toBe(first.sourceHashes.roles)
  })
})

describe('HARD-007 custody and cadence evidence holdout', () => {
  it('runs manually and on a recorded schedule with separate key and R2 writer secrets', () => {
    const workflow = readFileSync(resolve('.github/workflows/phase8-protected-backup.yml'), 'utf8')
    expect(workflow).toMatch(/workflow_dispatch/)
    expect(workflow).toMatch(/schedule\s*:/)
    expect(workflow).toMatch(/cron\s*:/)
    expect(workflow).toContain('gymloop-backups')
    const secretNames = [...workflow.matchAll(/secrets\.([A-Z0-9_]+)/g)].map((match) => match[1])
    const encryptionSecrets = secretNames.filter((name) => /ENCRYPT|ARCHIVE_KEY/.test(name))
    const writerSecrets = secretNames.filter((name) => /R2|WRITER|ACCESS_KEY/.test(name))
    expect(encryptionSecrets.length).toBeGreaterThan(0)
    expect(writerSecrets.length).toBeGreaterThan(0)
    expect(encryptionSecrets.some((name) => writerSecrets.includes(name))).toBe(false)
  })

  it('names a backup owner and a concrete cadence while leaving restore evidence open', () => {
    const runbook = readFileSync(resolve('docs/runbooks/backup-and-restore.md'), 'utf8')
    expect(runbook).toMatch(/backup owner\s*:/i)
    expect(runbook).toMatch(/(?:daily|weekly|every\s+\d+\s+(?:hours|days))/i)
    expect(runbook).toMatch(/restore.*(?:unperformed|not.*performed|external)/is)
  })
})
