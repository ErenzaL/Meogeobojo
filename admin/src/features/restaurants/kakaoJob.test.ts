import { describe, expect, it, vi } from 'vitest'
import type { KakaoDoc } from './kakao'
import { describeError, probeFunction, redact } from './kakaoDiag'
import { clearJob, hasUnfinishedWork, jobMatchesCampus, jobSummary, loadJob, saveJob } from './kakaoJobStore'
import { haversineM, type Campus } from './kakaoGeo'
import { type CellOutcome, type CellQuery, type FailKind, type JobState, makeSupabaseSearch, newJob, newMemory, runJob, scanCampus, type SearchCell } from './kakaoScan'

const CAMPUS: Campus = { id: 'u1', name: '순천향대학교', latitude: 36.7699, longitude: 126.9315, radiusM: 3000 }
const M_PER_DEG_LAT = 111_195
const at = (eastM: number, northM: number) => ({
  lat: CAMPUS.latitude + northM / M_PER_DEG_LAT,
  lng: CAMPUS.longitude + eastM / (M_PER_DEG_LAT * Math.cos((CAMPUS.latitude * Math.PI) / 180)),
})
function prng(seed: number) { let a = seed >>> 0; return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296 } }

type SimPlace = { id: string; lat: number; lng: number; group: 'FD6' | 'CE7'; name: string }
function city(n: number, spreadM: number, seed = 1): SimPlace[] {
  const r = prng(seed)
  return Array.from({ length: n }, (_, i) => {
    const ang = r() * 2 * Math.PI
    const dist = Math.sqrt(r()) * spreadM
    return { id: `p${i}`, ...at(Math.cos(ang) * dist, Math.sin(ang) * dist), group: (i % 5 === 0 ? 'CE7' : 'FD6') as 'FD6' | 'CE7', name: `비밀식당이름${i}` }
  })
}
const inRadius = (ps: SimPlace[]) => ps.filter((p) => haversineM(CAMPUS.latitude, CAMPUS.longitude, p.lat, p.lng) <= CAMPUS.radiusM)
const toDoc = (p: SimPlace): KakaoDoc => ({ id: p.id, place_name: p.name, category_group_code: p.group, x: String(p.lng), y: String(p.lat), address_name: `주소 ${p.id}` })

/** Kakao as the function serves it: ONE PAGE (15) per request, at most 45 reachable, cursor in `nextPage`. */
function sim(places: SimPlace[], hooks: { fail?: (q: CellQuery, n: number) => CellOutcome | null } = {}) {
  const queries: CellQuery[] = []
  let n = 0
  let inflight = 0
  let maxInflight = 0
  const search: SearchCell = async (q) => {
    n++
    queries.push(q)
    inflight++; maxInflight = Math.max(maxInflight, inflight)
    await Promise.resolve()
    inflight--
    const injected = hooks.fail?.(q, n)
    if (injected) return injected
    const hits = places
      .filter((p) => p.group === q.group && haversineM(q.lat, q.lng, p.lat, p.lng) <= q.radiusM)
      .sort((a, b) => haversineM(q.lat, q.lng, a.lat, a.lng) - haversineM(q.lat, q.lng, b.lat, b.lng))
    const accessible = Math.min(hits.length, 45)
    const from = (q.page - 1) * 15
    return {
      ok: true, docs: hits.slice(from, Math.min(from + 15, accessible)).map(toDoc), truncated: hits.length >= 45, kakaoCalls: 1, total: hits.length,
      nextPage: q.page * 15 < accessible ? q.page + 1 : null,
    }
  }
  return { search, queries, stats: () => ({ calls: n, maxInflight }) }
}
const fast = { sleep: async () => undefined, baseDelayMs: 1 }
const fail = (kind: FailKind, status?: number, code?: string): CellOutcome => ({ ok: false, kind, status, code, message: code ?? kind })
/** A search that never answers and ignores its abort signal: the worst case for timeouts and cancellation. */
const hang: SearchCell = () => new Promise(() => undefined)
const reload = (j: JobState): JobState => JSON.parse(JSON.stringify(j)) as JobState

describe('why the import failed: a missing function must be diagnosed, not retried', () => {
  it('a status-less fetch error for a function that is not deployed is reported as such, at once, without retries', async () => {
    // exactly what a browser reports for a missing function: the CORS preflight is a 404, so there is no HTTP status
    const invoke = vi.fn(async () => ({ data: null, error: { name: 'FunctionsFetchError', message: 'Failed to send a request to the Edge Function', context: new TypeError('Failed to fetch') } }))
    const probe = vi.fn(async () => ({ state: 'not_deployed' as const, status: 404 }))
    const res = await scanCampus(CAMPUS, makeSupabaseSearch(invoke as never, probe), { ...fast, concurrency: 1 })
    expect(res.stoppedBy).toBe('not_deployed')
    expect(res.progress.invocations).toBe(1) // not "transient": no backoff, no 3 retries per root square
    expect(res.progress.retries).toBe(0)
    expect(res.errors[0]).toMatchObject({ kind: 'not_deployed', status: 404, code: 'NOT_FOUND', stage: 'grid_search' })
    expect(res.warnings.join(' ')).toMatch(/배포되어 있지 않아요/)
    expect(probe).toHaveBeenCalledTimes(1)
  })

  it('the probe runs once per search function, however many requests fail', async () => {
    const probe = vi.fn(async () => ({ state: 'unreachable' as const }))
    const invoke = vi.fn(async () => ({ data: null, error: { name: 'FunctionsFetchError', message: 'x' } }))
    const search = makeSupabaseSearch(invoke as never, probe)
    const q = { campusId: 'u1', lat: 36.77, lng: 126.93, radiusM: 4300, group: 'FD6' as const, page: 1 }
    const a = await search(q, new AbortController().signal)
    await search(q, new AbortController().signal)
    expect(probe).toHaveBeenCalledTimes(1)
    expect(a).toMatchObject({ ok: false, kind: 'network' })
    expect(a.ok === false && a.message).toMatch(/HTTP 상태 없음/)
  })

  it('without a probe the old behaviour stays: a status-less error is a transient network failure', async () => {
    const invoke = vi.fn(async () => ({ data: null, error: { name: 'FunctionsFetchError', message: 'offline' } }))
    const out = await makeSupabaseSearch(invoke as never)({ campusId: 'u1', lat: 36.77, lng: 126.93, radiusM: 4300, group: 'FD6', page: 1 }, new AbortController().signal)
    expect(out).toMatchObject({ ok: false, kind: 'network' })
  })

  it('probeFunction: a simple GET (no custom headers, key in the query); 404 = not deployed, any other status = deployed', async () => {
    const calls: { url: string; init?: RequestInit }[] = []
    const mk = (status: number): typeof fetch => (async (url: string | URL | Request, init?: RequestInit) => { calls.push({ url: String(url), init }); return new Response('{}', { status }) }) as typeof fetch
    expect(await probeFunction('https://x.supabase.co/', 'admin_kakao_search', 'KEY123', mk(404))).toEqual({ state: 'not_deployed', status: 404 })
    expect(await probeFunction('https://x.supabase.co', 'admin_kakao_search', 'KEY123', mk(405))).toEqual({ state: 'deployed', status: 405 })
    expect(await probeFunction('https://x.supabase.co', 'admin_kakao_search', 'KEY123', mk(401))).toEqual({ state: 'deployed', status: 401 })
    expect(calls[0].url).toBe('https://x.supabase.co/functions/v1/admin_kakao_search?apikey=KEY123')
    expect(calls[0].init?.method).toBe('GET')
    expect(calls[0].init?.headers).toBeUndefined() // custom headers would trigger the very preflight that hides the status
  })

  it('probeFunction: no answer, or a hang, is "unreachable"', async () => {
    expect(await probeFunction('https://x', 'f', 'k', (async () => { throw new TypeError('Failed to fetch') }) as typeof fetch)).toEqual({ state: 'unreachable' })
    const slow = ((_u: string, init?: RequestInit) => new Promise((_r, rej) => init?.signal?.addEventListener('abort', () => rej(new DOMException('a', 'AbortError'))))) as unknown as typeof fetch
    expect(await probeFunction('https://x', 'f', 'k', slow, 20)).toEqual({ state: 'unreachable' })
  })
})

describe('Admin errors: stage, HTTP status, no secrets', () => {
  it('redacts Kakao keys, bearer tokens, JWTs, apikey params and long opaque tokens', () => {
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk'
    for (const [input, secret] of [
      ['Kakao said: Authorization: KakaoAK 0123456789abcdef0123456789abcdef', '0123456789abcdef0123456789abcdef'],
      ['header Authorization: Bearer abc.def-GHI_123', 'abc.def-GHI_123'],
      ['GET /functions/v1/x?apikey=sb_publishable_AbCdEfGhIj123456&page=1', 'sb_publishable_AbCdEfGhIj123456'],
      [`token ${jwt} leaked`, jwt],
      ['key sb_secret_ZZZZZZZZZZZZZZ', 'sb_secret_ZZZZZZZZZZZZZZ'],
      ['opaque ' + 'A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8S9t0U1v2', 'A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8S9t0U1v2'],
    ]) {
      const out = redact(input)
      expect(out).not.toContain(secret)
      expect(out).toContain('***')
    }
    expect(redact('HTTP 502 kakao_unavailable')).toBe('HTTP 502 kakao_unavailable') // ordinary text is untouched
  })

  it('describeError names the stage, the status, the code and the job', () => {
    const t = describeError({ stage: 'grid_search', status: 502, code: 'kakao_unavailable', message: 'Kakao 503 KakaoAK secretsecretsecret', jobId: '1234abcd-5678-90ef' })
    expect(t).toContain('단계: 구역 검색')
    expect(t).toContain('HTTP 502')
    expect(t).toContain('kakao_unavailable')
    expect(t).toContain('작업 ID 1234abcd')
    expect(t).not.toContain('secretsecretsecret')
    expect(describeError({ stage: 'function_check', message: 'x' })).toContain('HTTP 상태 없음')
  })

  it('error messages stored in a failed square are redacted too', async () => {
    const res = await scanCampus(CAMPUS, async () => ({ ok: false, kind: 'rejected', status: 400, message: 'bad Bearer abc.def.ghi and KakaoAK 0123456789abcdef0123456789abcdef' }), { ...fast, concurrency: 1, rejectedStop: 99 })
    const text = JSON.stringify(res.job) + JSON.stringify(res.errors)
    expect(text).not.toContain('abc.def.ghi')
    expect(text).not.toContain('0123456789abcdef')
  })
})

describe('timeouts', () => {
  it('a request that never answers is cancelled and retried, then that square is marked failed (the scan does not hang)', async () => {
    const res = await scanCampus(CAMPUS, hang, { ...fast, timeoutMs: 15, retries: 1, concurrency: 1, rejectedStop: 99, rateLimitStop: 99 })
    expect(res.failedCells).toHaveLength(2) // both root squares (FD6, CE7)
    expect(res.failedCells[0]).toMatchObject({ kind: 'timeout' })
    expect(res.progress.invocations).toBe(4) // each: first try + one retry
    expect(res.errors[0].message).toMatch(/응답이 없었어요/)
    expect(res.job.status).toBe('partial')
  })

  it('a slow answer that arrives within the timeout is fine; one timeout followed by success recovers', async () => {
    let n = 0
    const base = sim(city(20, 1000, 4))
    const search: SearchCell = (q, s) => (n++ === 0 ? hang(q, s) : base.search(q, s))
    const res = await scanCampus(CAMPUS, search, { ...fast, timeoutMs: 15, concurrency: 1 })
    expect(res.complete).toBe(true)
    expect(res.progress.retries).toBe(1)
    expect(res.places.length).toBe(inRadius(city(20, 1000, 4)).length)
  })

  it('the timeout aborts the in-flight request through its signal', async () => {
    let seen: AbortSignal | undefined
    const search: SearchCell = (_q, s) => { seen = s; return new Promise(() => undefined) }
    await scanCampus(CAMPUS, search, { ...fast, timeoutMs: 10, retries: 0, concurrency: 1, groups: ['FD6'] })
    expect(seen?.aborted).toBe(true)
  })
})

describe('cancellation', () => {
  it('stops at once even if the request ignores its signal, and keeps the job resumable with its cursors', async () => {
    const ctl = new AbortController()
    const t0 = Date.now()
    setTimeout(() => ctl.abort(), 20)
    const res = await scanCampus(CAMPUS, hang, { ...fast, signal: ctl.signal, timeoutMs: 60_000, concurrency: 2 })
    expect(Date.now() - t0).toBeLessThan(1000) // did not wait for the 60 s timeout
    expect(res.stoppedBy).toBe('cancelled')
    expect(res.job.status).toBe('cancelled')
    expect(res.job.tasks.every((t) => t.status === 'pending')).toBe(true) // nothing was lost: all still to do
    expect(hasUnfinishedWork(res.job)).toBe(true)
    expect(res.failedCells).toEqual([]) // cancelling is not a failure
  })

  it('a cancelled scan can be continued and finishes', async () => {
    const ps = city(300, 2500, 3)
    const s = sim(ps)
    const ctl = new AbortController()
    let seen = 0
    const search: SearchCell = async (q, sg) => { if (++seen === 3) ctl.abort(); return s.search(q, sg) }
    const memory = newMemory()
    const first = await scanCampus(CAMPUS, search, { ...fast, signal: ctl.signal, memory, concurrency: 1 })
    expect(first.stoppedBy).toBe('cancelled')
    const second = await runJob(first.job, s.search, { ...fast, memory })
    expect(second.complete).toBe(true)
    expect(second.places.map((p) => p.id).sort()).toEqual(inRadius(ps).map((p) => p.id).sort())
  })
})

describe('retries and rate limits', () => {
  it('a 429 lowers the concurrency (never below 1) and says so', async () => {
    let limited = 0
    const s = sim(city(400, 3000, 6), { fail: () => (limited++ < 3 ? fail('rate_limited', 429, 'kakao_rate_limited') : null) })
    const res = await scanCampus(CAMPUS, s.search, { ...fast, concurrency: 3 })
    expect(res.progress.concurrency).toBeLessThan(3)
    expect(res.progress.concurrency).toBeGreaterThanOrEqual(1)
    expect(res.warnings.join(' ')).toMatch(/동시 요청을 \d개로 줄여서/)
    expect(res.complete).toBe(true)
  })

  it('persistent rate limiting stops the run but keeps everything found and everything still to do', async () => {
    const ps = city(200, 2500, 2)
    const s = sim(ps)
    let n = 0
    const search: SearchCell = (q, sg) => (n++ < 6 ? s.search(q, sg) : Promise.resolve(fail('rate_limited', 429, 'kakao_rate_limited')))
    const res = await scanCampus(CAMPUS, search, { ...fast, concurrency: 1, retries: 1, rateLimitStop: 2 })
    expect(res.stoppedBy).toBe('rate_limited')
    expect(res.places.length).toBeGreaterThan(0)
    expect(res.job.status).toBe('stopped')
    expect(hasUnfinishedWork(res.job)).toBe(true)
  })

  it('refusals (HTTP 4xx) of single squares do not stop the others; a run of them does', async () => {
    const ps = city(150, 2500, 7)
    const s = sim(ps, { fail: (q) => (q.group === 'CE7' ? fail('rejected', 400, 'cell_outside_university_area') : null) })
    const some = await scanCampus(CAMPUS, s.search, { ...fast, concurrency: 1 }) // default: stops only after 3 refusals IN A ROW
    expect(some.failedCells).toHaveLength(1) // the one refused square (CE7 root) ...
    expect(some.places.length).toBe(inRadius(ps).filter((p) => p.group === 'FD6').length) // ... and every FD6 place is still found
    expect(some.stoppedBy).toBeNull()
    const all = await scanCampus(CAMPUS, async () => fail('rejected', 400, 'bad'), { ...fast, concurrency: 1, rejectedStop: 2 })
    expect(all.stoppedBy).toBe('rejected')
    expect(all.progress.invocations).toBeLessThanOrEqual(4)
  })
})

describe('partial success is preserved and marked', () => {
  it('one failing square costs only that square', async () => {
    const ps = city(500, 3000, 8)
    // fail every request for one specific quarter of the FD6 grid (permanently)
    const target = { dx: 1500, dy: 1500 }
    const s = sim(ps, { fail: (q) => (q.group === 'FD6' && Math.abs(q.lat - at(target.dx, target.dy).lat) < 1e-4 && Math.abs(q.lng - at(target.dx, target.dy).lng) < 2e-4 ? fail('unavailable', 502, 'kakao_unavailable') : null) })
    const res = await scanCampus(CAMPUS, s.search, { ...fast, retries: 1 })
    expect(res.failedCells.length).toBeGreaterThan(0)
    expect(res.failedCells.every((f) => f.group === 'FD6')).toBe(true)
    expect(res.complete).toBe(false)
    expect(res.job.status).toBe('partial')
    expect(res.errors[0]).toMatchObject({ kind: 'unavailable', status: 502, code: 'kakao_unavailable', stage: 'grid_search' })
    const missing = inRadius(ps).length - res.places.length
    expect(missing).toBeGreaterThan(0) // that quarter's FD6 places
    expect(res.places.length).toBeGreaterThan(inRadius(ps).length / 2) // but the rest is kept
    expect(res.warnings.join(' ')).toMatch(/성공한 구역의 결과는 그대로/)
  })

  it('retrying only the failed squares fills the gap and does not search the finished ones again', async () => {
    const ps = city(500, 3000, 8)
    let broken = true
    const s = sim(ps, { fail: (q) => (broken && q.group === 'FD6' && q.lat > CAMPUS.latitude + 0.01 && q.lng > CAMPUS.longitude + 0.01 ? fail('unavailable', 502, 'kakao_unavailable') : null) })
    const memory = newMemory()
    const first = await scanCampus(CAMPUS, s.search, { ...fast, retries: 0, memory })
    expect(first.failedCells.length).toBeGreaterThan(0)
    const doneKeys = new Set(first.job.tasks.filter((t) => t.status === 'done').map((t) => t.key))
    const before = s.queries.length
    broken = false
    const second = await runJob(first.job, s.search, { ...fast, memory }) // same session: results kept, failed squares retried
    const retried = s.queries.slice(before)
    expect(second.complete).toBe(true)
    expect(second.places.map((p) => p.id).sort()).toEqual(inRadius(ps).map((p) => p.id).sort())
    expect(retried.length).toBeLessThan(before) // a fraction of the work, not the whole scan again
    // none of the squares that had finished was requested again: their page counters did not move
    expect(second.job.tasks.filter((t) => doneKeys.has(t.key)).every((t) => t.pages === first.job.tasks.find((f) => f.key === t.key)!.pages)).toBe(true)
  })
})

describe('pagination cursor', () => {
  it('walks the pages of a square and records the cursor; a failure on page 2 resumes at page 2, not page 1', async () => {
    const ps = city(200, 600, 4).map((p, i) => ({ ...p, group: 'FD6' as const, id: `c${i}` })) // a crowded centre: > 15 in one square
    let failPage2 = true
    const s = sim(ps, { fail: (q) => (failPage2 && q.page === 2 ? fail('unavailable', 502, 'kakao_unavailable') : null) })
    const first = await scanCampus(CAMPUS, s.search, { ...fast, retries: 0, concurrency: 1, groups: ['FD6'], keywords: [] })
    const failed = first.job.tasks.filter((t) => t.status === 'failed')
    expect(failed.length).toBeGreaterThan(0)
    expect(failed.every((t) => t.page === 2 && t.pages === 1)).toBe(true) // page 1 was read, the cursor sits on page 2
    const before = s.queries.length
    failPage2 = false
    const second = await runJob(first.job, s.search, { ...fast, concurrency: 1, memory: newMemory() })
    const resumedFirstRequests = s.queries.slice(before).filter((q) => failed.some((t) => t.key.startsWith('FD6||0|0|0') && q.page === 1 && q.lat === CAMPUS.latitude))
    expect(resumedFirstRequests).toHaveLength(0) // the root square's page 1 was not requested again
    expect(second.job.tasks.find((t) => t.key.startsWith('FD6||0|'))?.status).toBe('done')
  })

  it('never asks for a page beyond what the server offered', async () => {
    const ps = city(300, 800, 9).map((p, i) => ({ ...p, group: 'FD6' as const, id: `d${i}` }))
    const s = sim(ps)
    await scanCampus(CAMPUS, s.search, { ...fast, groups: ['FD6'] })
    expect(Math.max(...s.queries.map((q) => q.page))).toBeLessThanOrEqual(3)
    expect(Math.min(...s.queries.map((q) => q.page))).toBe(1)
  })
})

describe('resuming a search', () => {
  it('a run that hits its request allowance stops with the rest still pending; resuming continues only that', async () => {
    const ps = city(600, 3000, 5)
    const s = sim(ps)
    const memory = newMemory()
    const first = await scanCampus(CAMPUS, s.search, { ...fast, maxInvocations: 12, memory })
    expect(first.stoppedBy).toBe('budget')
    expect(first.job.status).toBe('stopped')
    expect(first.unsearchedCells).toBeGreaterThan(0)
    const requestedBefore = s.queries.length
    const doneBefore = first.job.tasks.filter((t) => t.status === 'done').map((t) => t.key)
    const second = await runJob(first.job, s.search, { ...fast, memory, maxInvocations: 5000 }) // a fresh allowance for the new run
    expect(second.complete).toBe(true)
    expect(second.places.map((p) => p.id).sort()).toEqual(inRadius(ps).map((p) => p.id).sort())
    // finished squares were not searched again (a full rescan would repeat all of the first run's requests)
    const repeated = s.queries.slice(requestedBefore).filter((q) => s.queries.slice(0, requestedBefore).some((o) => o.page === q.page && o.group === q.group && !o.query === !q.query && o.lat === q.lat && o.lng === q.lng && o.radiusM === q.radiusM))
    expect(repeated).toHaveLength(0)
    expect(doneBefore.length).toBeGreaterThan(0)
  })

  it('a job survives a page reload (JSON + storage) and continues without a restart', async () => {
    const ps = city(500, 3000, 12)
    const s = sim(ps)
    const store = new Map<string, string>()
    const storage = { getItem: (k: string) => store.get(k) ?? null, setItem: (k: string, v: string) => void store.set(k, v), removeItem: (k: string) => void store.delete(k) }
    const first = await scanCampus(CAMPUS, s.search, { ...fast, maxInvocations: 20, onCheckpoint: (j) => saveJob(j, storage) })
    expect(first.stoppedBy).toBe('budget')

    const stored = loadJob('u1', storage)!
    expect(stored.id).toBe(first.job.id) // trackable by job id
    expect(jobMatchesCampus(stored, CAMPUS)).toBe(true)
    expect(jobSummary(stored)).toMatchObject({ jobId: first.job.id, radiusM: 3000 })
    const calls = s.queries.length
    const resumed = await runJob(stored, s.search, { ...fast, memory: newMemory(), onCheckpoint: (j) => (j.status === 'complete' ? clearJob('u1', storage) : saveJob(j, storage)) })
    expect(resumed.job.id).toBe(first.job.id)
    expect(resumed.job.status).toBe('complete')
    expect(loadJob('u1', storage)).toBeNull() // finished jobs are not kept
    expect(s.queries.length - calls).toBeLessThan(calls + 200)
    // after a reload the places found before it are NOT restored (nothing from Kakao is stored)
    expect(resumed.places.length).toBeLessThan(inRadius(ps).length)
    expect(resumed.places.length).toBeGreaterThan(0)
  })

  it('a stored job holds no place data: no names, addresses, coordinates or ids of places', async () => {
    const ps = city(200, 2500, 3)
    const res = await scanCampus(CAMPUS, sim(ps).search, { ...fast, maxInvocations: 10 })
    const text = JSON.stringify(res.job)
    for (const p of ps.slice(0, 50)) { expect(text).not.toContain(p.name); expect(text).not.toContain(`주소 ${p.id}`); expect(text).not.toContain(String(p.lat)) }
    expect(text).not.toMatch(/place_name|address_name|phone|place_url/)
  })

  it('failed squares are retried on resume, with their cursor', async () => {
    const ps = city(200, 2500, 3)
    let broken = true
    const s = sim(ps, { fail: (q) => (broken && q.group === 'CE7' ? fail('unavailable', 503) : null) })
    const first = await scanCampus(CAMPUS, s.search, { ...fast, retries: 0 })
    expect(first.failedCells.length).toBeGreaterThan(0)
    broken = false
    const second = await runJob(reload(first.job), s.search, { ...fast, memory: newMemory() })
    expect(second.job.status).toBe('complete')
    expect(second.failedCells).toEqual([])
  })

  it('a job is not reused if the university\'s centre or radius changed (the grid would be different)', () => {
    const job = newJob(CAMPUS)
    expect(jobMatchesCampus(job, { latitude: CAMPUS.latitude, longitude: CAMPUS.longitude, radiusM: 3000 })).toBe(true)
    expect(jobMatchesCampus(job, { latitude: CAMPUS.latitude, longitude: CAMPUS.longitude, radiusM: 1500 })).toBe(false)
    expect(jobMatchesCampus(job, { latitude: 36.8, longitude: CAMPUS.longitude, radiusM: 3000 })).toBe(false)
  })

  it('the store ignores corrupt or foreign data and survives a broken storage', () => {
    const store = new Map<string, string>()
    const storage = { getItem: (k: string) => store.get(k) ?? null, setItem: (k: string, v: string) => void store.set(k, v), removeItem: (k: string) => void store.delete(k) }
    store.set('kakao-import-job:u1', '{not json')
    expect(loadJob('u1', storage)).toBeNull()
    store.set('kakao-import-job:u1', JSON.stringify({ v: 2 }))
    expect(loadJob('u1', storage)).toBeNull()
    store.set('kakao-import-job:u1', JSON.stringify({ ...newJob(CAMPUS), tasks: [{ key: 1 }] }))
    expect(loadJob('u1', storage)).toBeNull()
    store.set('kakao-import-job:u1', JSON.stringify(newJob({ ...CAMPUS, id: 'other' })))
    expect(loadJob('u1', storage)).toBeNull() // a different university's job
    const broken = { getItem: () => { throw new Error('blocked') }, setItem: () => { throw new Error('full') }, removeItem: () => { throw new Error('blocked') } }
    expect(() => saveJob(newJob(CAMPUS), broken)).not.toThrow()
    expect(loadJob('u1', broken)).toBeNull()
    expect(() => clearJob('u1', broken)).not.toThrow()
  })
})

describe('duplicates and bounded work', () => {
  it('a place seen on several pages, squares, groups, keywords and resumed runs counts once', async () => {
    const ps = city(300, 2500, 5)
    const s = sim(ps)
    const dup: SearchCell = async (q, sg) => { const o = await s.search(q, sg); return o.ok ? { ...o, docs: [...o.docs, ...o.docs] } : o }
    const memory = newMemory()
    const first = await scanCampus(CAMPUS, dup, { ...fast, maxInvocations: 8, memory })
    const second = await runJob(first.job, dup, { ...fast, memory })
    const ids = second.places.map((p) => p.id)
    expect(new Set(ids).size).toBe(ids.length)
    expect(ids.length).toBe(inRadius(ps).length)
  })

  it('never more searches in flight than the (conservative) default of 3', async () => {
    const s = sim(city(600, 3000, 4))
    await scanCampus(CAMPUS, s.search, fast)
    expect(s.stats().maxInflight).toBeLessThanOrEqual(3)
  })

  it('checkpoints every batch of squares and at the end', async () => {
    const saved: number[] = []
    await scanCampus(CAMPUS, sim(city(300, 2500, 2)).search, { ...fast, batchSize: 5, onCheckpoint: (j) => saved.push(j.tasks.filter((t) => t.status === 'done').length) })
    expect(saved.length).toBeGreaterThan(2)
    expect(saved[saved.length - 1]).toBeGreaterThanOrEqual(Math.max(...saved))
  })
})
