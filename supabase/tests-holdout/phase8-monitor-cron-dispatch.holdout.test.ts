import { readFile } from 'node:fs/promises'
import { afterEach, describe, expect, it, vi } from 'vitest'

const approvedCron = '*/5 * * * *'
const dispatchToken = 'HOLDOUT_PRIVATE_DISPATCH_TOKEN_X'
const dispatchPath = '/repos/OGUN01/gymloop/actions/workflows/phase8-production-monitor.yml/dispatches'
const watchdogPath = /^\/repos\/OGUN01\/gymloop\/actions\/workflows\/[^/]*watchdog[^/]*\/dispatches$/

type ScheduledWorker = {
  scheduled: (event: { cron: string }, env: { GITHUB_ACTIONS_DISPATCH_TOKEN?: string }) => Promise<unknown>
  fetch?: unknown
}

async function loadWorker(): Promise<ScheduledWorker> {
  const module = await import('../../workers/phase8-monitor-dispatch.mjs')
  return module.default as ScheduledWorker
}

function captureLogs() {
  const records: unknown[][] = []
  for (const method of ['log', 'info', 'warn', 'error'] as const) {
    vi.spyOn(console, method).mockImplementation((...args: unknown[]) => { records.push(args) })
  }
  return () => JSON.stringify(records)
}

function captureFetch(response: Response | Error | ((request: Request) => Response | Error)) {
  const requests: Request[] = []
  const fake = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const request = new Request(input, init)
    requests.push(request)
    const outcome = typeof response === 'function' ? response(request) : response
    if (outcome instanceof Error) throw outcome
    return outcome
  })
  vi.stubGlobal('fetch', fake)
  return { fake, requests }
}

function parseJsonc(raw: string): unknown {
  let withoutComments = ''
  let quoted = false
  let escaped = false
  for (let index = 0; index < raw.length; index += 1) {
    const char = raw[index]
    const next = raw[index + 1]
    if (quoted) {
      withoutComments += char
      if (escaped) escaped = false
      else if (char === '\\') escaped = true
      else if (char === '"') quoted = false
    } else if (char === '"') {
      quoted = true
      withoutComments += char
    } else if (char === '/' && next === '/') {
      while (index < raw.length && raw[index] !== '\n') index += 1
      withoutComments += '\n'
    } else if (char === '/' && next === '*') {
      index += 2
      while (index < raw.length && !(raw[index] === '*' && raw[index + 1] === '/')) index += 1
      index += 1
    } else {
      withoutComments += char
    }
  }
  return JSON.parse(withoutComments.replace(/,\s*([}\]])/g, '$1'))
}

afterEach(() => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe('HARD-005 independent Cron dispatch holdout', () => {
  it('configures the five-minute Cloudflare Cron trigger without public routing', async () => {
    const raw = await readFile(new URL('../../wrangler.phase8-monitor.jsonc', import.meta.url), 'utf8')
    const config = parseJsonc(raw) as { triggers?: { crons?: string[] }; routes?: unknown; route?: unknown }
    expect(config.triggers?.crons).toContain(approvedCron)
    expect(config.routes).toBeUndefined()
    expect(config.route).toBeUndefined()
  })

  it('retains a five-minute GitHub schedule and manual workflow dispatch as fallback', async () => {
    const raw = await readFile(new URL('../../.github/workflows/phase8-production-monitor.yml', import.meta.url), 'utf8')
    expect(/\bschedule:/.test(raw)).toBe(true)
    expect(/\bcron:\s*['"]?\*\/5 \* \* \* \*['"]?/.test(raw)).toBe(true)
    expect(/\bworkflow_dispatch:/.test(raw)).toBe(true)
  })

  it('exports only a scheduled handler and dispatches both production workflows on main', async () => {
    const worker = await loadWorker()
    expect(typeof worker.scheduled).toBe('function')
    expect(Object.hasOwn(worker, 'fetch')).toBe(false)
    const { fake, requests } = captureFetch(new Response(null, { status: 204 }))

    await worker.scheduled({ cron: approvedCron }, { GITHUB_ACTIONS_DISPATCH_TOKEN: dispatchToken })

    expect(fake).toHaveBeenCalledTimes(2)
    expect(requests).toHaveLength(2)
    const paths = requests.map((request) => new URL(request.url).pathname)
    expect(paths).toContain(dispatchPath)
    expect(paths.some((path) => watchdogPath.test(path))).toBe(true)
    for (const request of requests) {
      const url = new URL(request.url)
      expect(url.origin).toBe('https://api.github.com')
      expect(url.search).toBe('')
      expect(request.method).toBe('POST')
      expect(request.headers.get('authorization')).toBe(`Bearer ${dispatchToken}`)
      const body = JSON.parse(await request.text()) as { ref?: unknown; inputs?: Record<string, unknown> }
      expect(Object.keys(body).sort()).toEqual(['inputs', 'ref'])
      expect(body.ref).toBe('main')
      if (url.pathname === dispatchPath) {
        expect(Object.keys(body.inputs ?? {})).toEqual(['force_test_alert'])
        expect(String(body.inputs?.force_test_alert)).toBe('false')
      } else {
        expect(Object.keys(body.inputs ?? {})).toEqual(['force_test_missing'])
        expect(String(body.inputs?.force_test_missing)).toBe('false')
      }
      expect(request.url).not.toContain(dispatchToken)
    }
  })

  it.each(['* * * * *', '*/10 * * * *', '', '0 */5 * * *'])('refuses unapproved Cron event %s without dispatch', async (cron) => {
    const worker = await loadWorker()
    const { fake } = captureFetch(new Response(null, { status: 204 }))
    await expect(worker.scheduled({ cron }, { GITHUB_ACTIONS_DISPATCH_TOKEN: dispatchToken })).rejects.toThrow()
    expect(fake).not.toHaveBeenCalled()
  })

  it.each([undefined, '', '   '])('refuses missing or blank dispatch token without making a request', async (token) => {
    const worker = await loadWorker()
    const { fake } = captureFetch(new Response(null, { status: 204 }))
    await expect(worker.scheduled({ cron: approvedCron }, { GITHUB_ACTIONS_DISPATCH_TOKEN: token })).rejects.toThrow()
    expect(fake).not.toHaveBeenCalled()
  })

  it.each([200, 201, 202, 401, 429, 500])('requires HTTP 204, refusing status %i', async (status) => {
    const worker = await loadWorker()
    const logs = captureLogs()
    const { fake } = captureFetch(new Response('HOLDOUT_PRIVATE_RESPONSE_X', { status, statusText: 'HOLDOUT_PRIVATE_STATUS_X' }))
    let error: unknown
    try {
      await worker.scheduled({ cron: approvedCron }, { GITHUB_ACTIONS_DISPATCH_TOKEN: dispatchToken })
    } catch (caught) {
      error = caught
    }
    expect(fake).toHaveBeenCalledTimes(2)
    expect(error).toBeInstanceOf(Error)
    const exposed = `${String(error)} ${logs()}`
    expect(logs().length).toBeGreaterThan(2)
    expect(exposed).not.toContain(dispatchToken)
    expect(exposed).not.toContain('HOLDOUT_PRIVATE_RESPONSE_X')
    expect(exposed).not.toContain('HOLDOUT_PRIVATE_STATUS_X')
  })

  it('logs and throws a generic failure when the transport error contains a secret', async () => {
    const worker = await loadWorker()
    const logs = captureLogs()
    const { fake } = captureFetch(new Error(`HOLDOUT_PRIVATE_NETWORK_X ${dispatchToken}`))
    let error: unknown
    try {
      await worker.scheduled({ cron: approvedCron }, { GITHUB_ACTIONS_DISPATCH_TOKEN: dispatchToken })
    } catch (caught) {
      error = caught
    }
    expect(fake).toHaveBeenCalledTimes(2)
    expect(error).toBeInstanceOf(Error)
    const exposed = `${String(error)} ${logs()}`
    expect(logs().length).toBeGreaterThan(2)
    expect(exposed).not.toContain(dispatchToken)
    expect(exposed).not.toContain('HOLDOUT_PRIVATE_NETWORK_X')
  })

  it.each(['monitor', 'watchdog'])('attempts both dispatches when the %s request fails', async (failed) => {
    const worker = await loadWorker()
    const { requests } = captureFetch((request) => {
      const path = new URL(request.url).pathname
      const isMonitor = path === dispatchPath
      return new Response(null, { status: (failed === 'monitor') === isMonitor ? 500 : 204 })
    })
    await expect(worker.scheduled({ cron: approvedCron }, { GITHUB_ACTIONS_DISPATCH_TOKEN: dispatchToken })).rejects.toThrow()
    expect(requests).toHaveLength(2)
    const paths = requests.map((request) => new URL(request.url).pathname)
    expect(paths).toContain(dispatchPath)
    expect(paths.some((path) => watchdogPath.test(path))).toBe(true)
  })
})
