import { describe, expect, it, vi } from 'vitest'
import { cellWithinCampus, haversineM as serverHaversine } from '../../../../supabase/functions/admin_kakao_search/core'
import type { KakaoDoc } from './kakao'
import { cellCentre, cellRadiusM, cellTouchesCampus, childCells, haversineM, type Campus, type Cell, rootCell } from './kakaoGeo'
import { type CellOutcome, type CellQuery, makeSupabaseSearch, scanCampus, type SearchCell } from './kakaoScan'

const CAMPUS: Campus = { id: 'u1', name: '순천향대학교', latitude: 36.7699, longitude: 126.9315, radiusM: 3000 }
const M_PER_DEG_LAT = 111_195

/** Deterministic PRNG so the simulated map is the same on every run. */
function prng(seed: number) { let a = seed >>> 0; return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296 } }

type SimPlace = { id: string; lat: number; lng: number; group: 'FD6' | 'CE7'; name: string }
const at = (c: Campus, dEastM: number, dNorthM: number) => ({
  lat: c.latitude + dNorthM / M_PER_DEG_LAT,
  lng: c.longitude + dEastM / (M_PER_DEG_LAT * Math.cos((c.latitude * Math.PI) / 180)),
})
const toDoc = (p: SimPlace): KakaoDoc => ({ id: p.id, place_name: p.name, category_group_code: p.group, x: String(p.lng), y: String(p.lat), distance: '5' /* bogus: must be ignored */ })

/** A map of places spread over a disc of `spreadM` around the campus (some beyond the radius on purpose). */
function city(n: number, spreadM: number, seed = 1, campus = CAMPUS): SimPlace[] {
  const r = prng(seed)
  return Array.from({ length: n }, (_, i) => {
    const ang = r() * 2 * Math.PI
    const dist = Math.sqrt(r()) * spreadM
    return { id: `p${i}`, ...at(campus, Math.cos(ang) * dist, Math.sin(ang) * dist), group: (i % 5 === 0 ? 'CE7' : 'FD6') as 'FD6' | 'CE7', name: `집${i}` }
  })
}

/** A faithful stand-in for the server + Kakao: circle query, nearest first, 15 per page, at most 45 reachable. */
function simulate(places: SimPlace[], opts: { fail?: (q: CellQuery, n: number) => CellOutcome | null; keywords?: Record<string, (p: SimPlace) => boolean> } = {}) {
  const queries: CellQuery[] = []
  let inflight = 0
  let maxInflight = 0
  let n = 0
  const search: SearchCell = async (q) => {
    n++
    queries.push(q)
    inflight++
    maxInflight = Math.max(maxInflight, inflight)
    await Promise.resolve()
    inflight--
    const injected = opts.fail?.(q, n)
    if (injected) return injected
    const hits = places
      .filter((p) => p.group === q.group && haversineM(q.lat, q.lng, p.lat, p.lng) <= q.radiusM)
      .filter((p) => !q.query || (opts.keywords?.[q.query]?.(p) ?? false))
      .sort((a, b) => haversineM(q.lat, q.lng, a.lat, a.lng) - haversineM(q.lat, q.lng, b.lat, b.lng))
    const accessible = Math.min(hits.length, 45)
    return { ok: true, docs: hits.slice(0, accessible).map(toDoc), truncated: hits.length >= 45, kakaoCalls: Math.max(1, Math.ceil(accessible / 15)), total: hits.length }
  }
  return { search, queries, stats: () => ({ maxInflight, calls: n }) }
}
const fast = { sleep: async () => undefined, baseDelayMs: 1 }
const inRadius = (ps: SimPlace[], c = CAMPUS) => ps.filter((p) => haversineM(c.latitude, c.longitude, p.lat, p.lng) <= c.radiusM)

describe('radius propagation', () => {
  it('searches the radius it is given: the root circle covers the whole bounding square, nothing is hard-coded', async () => {
    for (const radiusM of [500, 1500, 3000, 5000]) {
      const campus = { ...CAMPUS, radiusM }
      const sim = simulate([])
      const res = await scanCampus(campus, sim.search, fast)
      expect(res.progress.radiusM).toBe(radiusM)
      const first = sim.queries[0]
      expect(first.campusId).toBe('u1')
      expect(first.lat).toBeCloseTo(campus.latitude, 9)
      expect(first.lng).toBeCloseTo(campus.longitude, 9)
      // the circle through the corners of the (2R x 2R) square: R*sqrt2, never less
      expect(first.radiusM).toBeGreaterThanOrEqual(Math.ceil(radiusM * Math.SQRT2))
      expect(first.radiusM).toBeLessThanOrEqual(Math.ceil(radiusM * Math.SQRT2 * 1.01) + 1)
      expect(first.radiusM).toBeLessThanOrEqual(20000)
    }
  })

  it('a bigger radius finds places a smaller one does not (3000 vs 1500)', async () => {
    const ps = city(400, 3000, 7)
    const small = await scanCampus({ ...CAMPUS, radiusM: 1500 }, simulate(ps).search, fast)
    const big = await scanCampus({ ...CAMPUS, radiusM: 3000 }, simulate(ps).search, fast)
    expect(small.places.length).toBe(inRadius(ps, { ...CAMPUS, radiusM: 1500 }).length)
    expect(big.places.length).toBe(inRadius(ps).length)
    expect(big.places.length).toBeGreaterThan(small.places.length)
  })
})

describe('spatial coverage and pagination', () => {
  it('finds every place in the radius, far more than 15 per query (800 places, caps of 45 per search)', async () => {
    const ps = city(800, 3300, 3) // spread past the radius: some are outside
    const sim = simulate(ps)
    const res = await scanCampus(CAMPUS, sim.search, fast)
    const expected = inRadius(ps)
    expect(expected.length).toBeGreaterThan(400)
    expect(res.places.map((p) => p.id).sort()).toEqual(expected.map((p) => p.id).sort())
    expect(res.complete).toBe(true)
    expect(res.saturatedCells).toEqual([])
    expect(res.failedCells).toEqual([])
    // and the cap really did force subdivision (a single search could only ever return 45)
    expect(sim.queries.length).toBeGreaterThan(10)
  })

  it('a naive single query would have missed most of them (what the old import did)', async () => {
    const ps = city(800, 3000, 3)
    const one = await simulate(ps).search({ campusId: 'u1', lat: CAMPUS.latitude, lng: CAMPUS.longitude, radiusM: 4243, group: 'FD6' }, new AbortController().signal)
    expect(one.ok && one.docs.length).toBe(45)
  })

  it('no place is missed wherever it sits: dense cluster, edge of the circle, centre', async () => {
    const r = prng(11)
    const ps: SimPlace[] = []
    for (let i = 0; i < 120; i++) ps.push({ id: `c${i}`, ...at(CAMPUS, 1800 + r() * 150, -1200 + r() * 150), group: 'FD6', name: 'x' }) // a crowded block
    for (let i = 0; i < 40; i++) { const a = r() * 6.28; ps.push({ id: `e${i}`, ...at(CAMPUS, Math.cos(a) * 2990, Math.sin(a) * 2990), group: 'FD6', name: 'edge' }) }
    ps.push({ id: 'centre', ...at(CAMPUS, 0, 0), group: 'CE7', name: 'centre' })
    const res = await scanCampus(CAMPUS, simulate(ps).search, fast)
    expect(new Set(res.places.map((p) => p.id))).toEqual(new Set(inRadius(ps).map((p) => p.id)))
  })

  it('squares that cannot touch the circle are never searched', async () => {
    const sim = simulate([], { fail: () => null })
    // every search reports truncation, so the grid is refined to the maximum depth
    const alwaysFull: SearchCell = async (q, s) => { const o = await sim.search(q, s); return o.ok ? { ...o, truncated: true } : o }
    const maxDepth = 3
    const res = await scanCampus(CAMPUS, alwaysFull, { ...fast, maxDepth, keywords: [], maxInvocations: 100000, maxKakaoCalls: 100000 })
    // independent enumeration of the squares that touch the circle, per depth
    const expected: number[] = []
    for (let d = 0; d <= maxDepth; d++) {
      const side = 2 ** d
      const half = CAMPUS.radiusM / side
      let count = 0
      for (let i = 0; i < side; i++) for (let j = 0; j < side; j++) {
        const dx = -CAMPUS.radiusM + half * (2 * i + 1)
        const dy = -CAMPUS.radiusM + half * (2 * j + 1)
        if (cellTouchesCampus({ dx, dy, half, depth: d }, CAMPUS)) count++
      }
      expected.push(count)
    }
    expect(expected[3]).toBeLessThan(64) // the corners really are skipped
    const total = expected.reduce((a, b) => a + b, 0) * 2 // two food groups
    expect(res.progress.invocations).toBe(total)
    expect(res.saturatedCells.length).toBe(expected[maxDepth] * 2)
  })

  it('the quarters tile their parent and every circle covers its whole square (several latitudes and radii)', () => {
    for (const lat of [34, 36.77, 37.6]) for (const radiusM of [100, 1500, 3000, 5000]) {
      const campus: Campus = { ...CAMPUS, latitude: lat, radiusM }
      const stack: Cell[] = [rootCell(campus)]
      while (stack.length) {
        const c = stack.pop()!
        const centre = cellCentre(c, campus)
        const r = cellRadiusM(c)
        for (const sx of [-1, 1]) for (const sy of [-1, 1]) {
          const corner = cellCentre({ ...c, dx: c.dx + sx * c.half, dy: c.dy + sy * c.half }, campus)
          expect(haversineM(centre.lat, centre.lng, corner.lat, corner.lng)).toBeLessThanOrEqual(r)
        }
        if (c.depth < 4) {
          const kids = childCells(c)
          expect(kids).toHaveLength(4)
          expect(kids.reduce((a, k) => a + (2 * k.half) ** 2, 0)).toBeCloseTo((2 * c.half) ** 2, 6)
          for (const k of kids) expect(Math.abs(k.dx - c.dx)).toBeCloseTo(c.half / 2, 9)
          stack.push(...kids)
        }
      }
    }
  })

  it('what the grid asks for is always accepted by the server-side area check, and both haversines agree', () => {
    for (const radiusM of [100, 1000, 3000, 5000]) {
      const campus: Campus = { ...CAMPUS, radiusM }
      const stack: Cell[] = [rootCell(campus)]
      while (stack.length) {
        const c = stack.pop()!
        const { lat, lng } = cellCentre(c, campus)
        expect(cellWithinCampus({ lat, lng, radiusM: cellRadiusM(c) }, { lat: campus.latitude, lng: campus.longitude, radiusM })).toBe(true)
        if (c.depth < 6) stack.push(...childCells(c).filter((k) => cellTouchesCampus(k, campus)))
      }
    }
    for (const [a, b, c, d] of [[36.77, 126.93, 36.8, 126.99], [33, 124, 39, 132], [36, 127, 36, 127]]) expect(serverHaversine(a, b, c, d)).toBeCloseTo(haversineM(a, b, c, d), 6)
  })
})

describe('distance filter and deduplication', () => {
  it('measures each place from the ORIGINAL university coordinates, ignoring Kakao\'s own distance', async () => {
    const ps: SimPlace[] = [
      { id: 'in', ...at(CAMPUS, 2990, 0), group: 'FD6', name: 'in' },
      { id: 'out', ...at(CAMPUS, 3015, 0), group: 'FD6', name: 'out' },
      { id: 'near', ...at(CAMPUS, 10, 10), group: 'FD6', name: 'near' },
    ]
    const res = await scanCampus(CAMPUS, simulate(ps).search, fast)
    expect(res.places.map((p) => p.id)).toEqual(['near', 'in'])
    for (const p of res.places) {
      expect(p.distanceM).toBeCloseTo(haversineM(CAMPUS.latitude, CAMPUS.longitude, Number(p.y), Number(p.x)), 6)
      expect(p.distance).toBe(String(Math.round(p.distanceM)))
      expect(p.distance).not.toBe('5')
    }
    expect(res.progress.outside).toBe(1)
  })

  it('drops non-food places and places without usable coordinates', async () => {
    const search: SearchCell = async () => ({
      ok: true, truncated: false, kakaoCalls: 1, total: 4, docs: [
        { id: '1', place_name: 'ok', category_group_code: 'FD6', x: '126.9315', y: '36.77' },
        { id: '2', place_name: 'shop', category_group_code: 'CS2', x: '126.9315', y: '36.77' },
        { id: '3', place_name: 'nocoord', category_group_code: 'FD6' },
        { id: '4', place_name: 'badcoord', category_group_code: 'FD6', x: 'abc', y: '36.77' },
      ],
    })
    const res = await scanCampus(CAMPUS, search, { ...fast, groups: ['FD6'] })
    expect(res.places.map((p) => p.id)).toEqual(['1'])
  })

  it('the same place found by several cells, groups and keywords counts once', async () => {
    const ps = city(300, 2500, 5)
    const dup: SearchCell = async (q, s) => {
      const o = await simulate(ps).search(q, s)
      return o.ok ? { ...o, docs: [...o.docs, ...o.docs] } : o // every document twice
    }
    const res = await scanCampus(CAMPUS, dup, fast)
    const ids = res.places.map((p) => p.id)
    expect(new Set(ids).size).toBe(ids.length)
    expect(ids.length).toBe(inRadius(ps).length)
  })

  it('scanning again gives exactly the same places in the same order (repeat imports)', async () => {
    const ps = city(500, 3000, 9)
    const a = await scanCampus(CAMPUS, simulate(ps).search, fast)
    const b = await scanCampus(CAMPUS, simulate(ps).search, fast)
    expect(b.places.map((p) => p.id)).toEqual(a.places.map((p) => p.id))
  })
})

describe('bounds: depth, requests, concurrency', () => {
  const alwaysFull = (sim: ReturnType<typeof simulate>): SearchCell => async (q, s) => { const o = await sim.search(q, s); return o.ok ? { ...o, truncated: true } : o }

  it('never goes deeper than maxDepth and reports the squares it could not resolve', async () => {
    const sim = simulate([])
    const res = await scanCampus(CAMPUS, alwaysFull(sim), { ...fast, maxDepth: 2, keywords: [], maxInvocations: 100000, maxKakaoCalls: 100000 })
    expect(res.saturatedCells.length).toBeGreaterThan(0)
    expect(res.complete).toBe(false)
    expect(res.warnings.join(' ')).toMatch(/노출 한도/)
    const smallest = Math.min(...sim.queries.map((q) => q.radiusM))
    expect(smallest).toBeGreaterThanOrEqual(Math.ceil((CAMPUS.radiusM / 4) * Math.SQRT2))
  })

  it('stops at the request ceiling and says so', async () => {
    const sim = simulate([])
    const res = await scanCampus(CAMPUS, alwaysFull(sim), { ...fast, maxInvocations: 40, maxDepth: 6, keywords: [] })
    expect(res.stoppedBy).toBe('budget')
    expect(res.progress.invocations).toBeLessThanOrEqual(40)
    expect(sim.stats().calls).toBeLessThanOrEqual(40)
    expect(res.unsearchedCells).toBeGreaterThan(0)
    expect(res.complete).toBe(false)
    expect(res.warnings.join(' ')).toMatch(/한도/)
  })

  it('stops at the Kakao-call ceiling too', async () => {
    const sim = simulate(city(600, 3000, 2))
    const res = await scanCampus(CAMPUS, sim.search, { ...fast, maxKakaoCalls: 6 })
    expect(res.stoppedBy).toBe('budget')
    expect(res.progress.kakaoCalls).toBeLessThan(6 + 4 * 3 + 1)
  })

  it('never has more searches in flight than the concurrency limit', async () => {
    const sim = simulate(city(600, 3000, 4))
    await scanCampus(CAMPUS, sim.search, { ...fast, concurrency: 3 })
    expect(sim.stats().maxInflight).toBeLessThanOrEqual(3)
    expect(sim.stats().maxInflight).toBeGreaterThan(1)
  })

  it('keywords run only inside squares the grid could not resolve, and add places the cap hid', async () => {
    // 80 places stacked at one spot: no amount of subdividing separates them
    const spot = at(CAMPUS, 500, 500)
    const ps: SimPlace[] = Array.from({ length: 80 }, (_, i) => ({ id: `s${i}`, ...spot, group: 'FD6' as const, name: `s${i}` }))
    const sim = simulate(ps, { keywords: { 한식: (p) => Number(p.id.slice(1)) < 40, 중식: (p) => Number(p.id.slice(1)) >= 40 } })
    const res = await scanCampus(CAMPUS, sim.search, { ...fast, maxDepth: 3, keywords: ['한식', '중식'] })
    expect(res.places.length).toBe(80) // 45 from the grid + the rest through keywords
    expect(res.saturatedCells.length).toBeGreaterThan(0)
    expect(sim.queries.some((q) => q.query === '한식')).toBe(true)
    // keyword searches stay inside the squares that were saturated: none for places elsewhere
    expect(sim.queries.filter((q) => q.query).every((q) => haversineM(q.lat, q.lng, spot.lat, spot.lng) < 1500)).toBe(true)
  })

  it('a sparse area finishes complete with no keyword searches', async () => {
    const sim = simulate(city(30, 2000, 6))
    const res = await scanCampus(CAMPUS, sim.search, fast)
    expect(res.complete).toBe(true)
    expect(sim.queries.filter((q) => q.query)).toHaveLength(0)
  })
})

describe('failures, backoff, cancellation', () => {
  it('retries a transient rate limit with exponential backoff, then succeeds', async () => {
    const sleeps: number[] = []
    let failures = 0
    const sim = simulate(city(20, 1000, 1), { fail: () => (failures++ < 2 ? { ok: false, kind: 'rate_limited', status: 429, message: 'slow' } : null) })
    const res = await scanCampus(CAMPUS, sim.search, { baseDelayMs: 500, random: () => 0.5, sleep: async (ms) => { sleeps.push(ms) }, concurrency: 1 })
    expect(sleeps.slice(0, 2)).toEqual([500, 1000])
    expect(res.progress.retries).toBe(2)
    expect(res.failedCells).toEqual([])
    expect(res.complete).toBe(true)
  })

  it('a cell that keeps failing is reported, not hidden, and the rest of the scan still counts', async () => {
    const ps = city(200, 2500, 8)
    const sim = simulate(ps, { fail: (q) => (q.group === 'CE7' ? { ok: false, kind: 'unavailable', status: 502, message: 'down' } : null) })
    const res = await scanCampus(CAMPUS, sim.search, { ...fast, retries: 2 })
    expect(res.failedCells.length).toBeGreaterThan(0)
    expect(res.failedCells[0]).toMatchObject({ group: 'CE7', kind: 'unavailable' })
    expect(res.complete).toBe(false)
    expect(res.progress.failed).toBe(res.failedCells.length)
    expect(res.places.length).toBe(inRadius(ps).filter((p) => p.group === 'FD6').length)
    expect(res.warnings.join(' ')).toMatch(/실패/)
  })

  it('gives up cleanly when Kakao keeps rate limiting', async () => {
    const sim = simulate([], { fail: () => ({ ok: false, kind: 'rate_limited', status: 429, message: 'slow' }) })
    const res = await scanCampus(CAMPUS, sim.search, { ...fast, retries: 1, rateLimitStop: 2, concurrency: 1 })
    expect(res.stoppedBy).toBe('rate_limited')
    expect(res.progress.invocations).toBeLessThan(10)
    expect(res.warnings.join(' ')).toMatch(/429/)
  })

  it('a function that is not deployed, or a forbidden caller, stops at once without retries', async () => {
    for (const kind of ['not_deployed', 'forbidden'] as const) {
      const sim = simulate([], { fail: () => ({ ok: false, kind, message: kind }) })
      const res = await scanCampus(CAMPUS, sim.search, { ...fast, concurrency: 1 })
      expect(res.stoppedBy).toBe(kind)
      expect(res.progress.invocations).toBe(1)
    }
  })

  it('cancelling keeps what was found, marks the result partial, and stops further requests', async () => {
    const ps = city(600, 3000, 12)
    const ctl = new AbortController()
    const base = simulate(ps)
    let seen = 0
    const search: SearchCell = async (q, s) => { if (++seen === 3) ctl.abort(); return base.search(q, s) }
    const res = await scanCampus(CAMPUS, search, { ...fast, signal: ctl.signal, concurrency: 1 })
    expect(res.stoppedBy).toBe('cancelled')
    expect(res.complete).toBe(false)
    expect(base.stats().calls).toBeLessThanOrEqual(4)
    expect(res.places.length).toBeGreaterThan(0)
    expect(res.warnings.join(' ')).toMatch(/중단/)
  })

  it('an already-cancelled scan makes no request at all', async () => {
    const ctl = new AbortController(); ctl.abort()
    const sim = simulate(city(10, 500, 1))
    const res = await scanCampus(CAMPUS, sim.search, { ...fast, signal: ctl.signal })
    expect(sim.stats().calls).toBe(0)
    expect(res.stoppedBy).toBe('cancelled')
  })

  it('reports progress as it goes', async () => {
    const seen: number[] = []
    await scanCampus(CAMPUS, simulate(city(300, 2500, 2)).search, { ...fast, onProgress: (p) => seen.push(p.invocations) })
    expect(seen.length).toBeGreaterThan(3)
    expect(seen[seen.length - 1]).toBeGreaterThanOrEqual(Math.max(...seen))
  })
})

describe('makeSupabaseSearch: what the Edge Function answered', () => {
  const run = (invoke: (...a: never[]) => unknown) => makeSupabaseSearch(invoke as never)({ campusId: 'u1', lat: 36.77, lng: 126.93, radiusM: 4300, group: 'FD6' }, new AbortController().signal)
  const httpError = (status: number, body: unknown, name = 'FunctionsHttpError') => ({ name, message: 'x', context: { status, json: async () => body } })

  it('sends only the university id, the group and the cell (the radius is validated server-side)', async () => {
    const invoke = vi.fn(async () => ({ data: { success: true, documents: [], meta: { truncated: false, kakao_calls: 1, total_count: 0 } }, error: null }))
    await makeSupabaseSearch(invoke as never)({ campusId: 'u1', lat: 36.77, lng: 126.93, radiusM: 4300, group: 'CE7', query: '카페' }, new AbortController().signal)
    expect(invoke).toHaveBeenCalledWith('admin_kakao_search', expect.objectContaining({ body: { university_id: 'u1', category_group_code: 'CE7', query: '카페', cell: { lat: 36.77, lng: 126.93, radius_m: 4300 } } }))
  })
  it('maps a good answer', async () => {
    const out = await run(async () => ({ data: { success: true, documents: [{ id: '1' }], meta: { truncated: true, kakao_calls: 3, total_count: 90 }, university: { search_radius_m: 3000 } }, error: null }))
    expect(out).toEqual({ ok: true, docs: [{ id: '1' }], truncated: true, kakaoCalls: 3, total: 90, universityRadiusM: 3000 })
  })
  it('classifies failures', async () => {
    expect(await run(async () => ({ data: null, error: httpError(404, { code: 'NOT_FOUND' }, 'FunctionsRelayError') }))).toMatchObject({ ok: false, kind: 'not_deployed' })
    expect(await run(async () => ({ data: null, error: httpError(404, { success: false, error: 'unknown_university_or_no_coordinates' }) }))).toMatchObject({ ok: false, kind: 'rejected' })
    expect(await run(async () => ({ data: null, error: httpError(403, { error: 'admin_only' }) }))).toMatchObject({ ok: false, kind: 'forbidden' })
    expect(await run(async () => ({ data: null, error: httpError(401, {}) }))).toMatchObject({ ok: false, kind: 'forbidden' })
    expect(await run(async () => ({ data: null, error: httpError(429, { error: 'kakao_rate_limited' }) }))).toMatchObject({ ok: false, kind: 'rate_limited' })
    expect(await run(async () => ({ data: null, error: httpError(502, { error: 'kakao_unavailable' }) }))).toMatchObject({ ok: false, kind: 'unavailable' })
    expect(await run(async () => ({ data: null, error: httpError(400, { error: 'cell_outside_university_area' }) }))).toMatchObject({ ok: false, kind: 'rejected' })
    expect(await run(async () => ({ data: null, error: { name: 'FunctionsFetchError', message: 'offline' } }))).toMatchObject({ ok: false, kind: 'network' })
    expect(await run(async () => { throw new Error('boom') })).toMatchObject({ ok: false, kind: 'network' })
    expect(await run(async () => ({ data: null, error: null }))).toMatchObject({ ok: false, kind: 'not_deployed' })
    expect(await run(async () => ({ data: { success: false }, error: null }))).toMatchObject({ ok: false, kind: 'unavailable' })
  })
})
