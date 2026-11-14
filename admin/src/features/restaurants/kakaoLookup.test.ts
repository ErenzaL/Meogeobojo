import { describe, expect, it, vi } from 'vitest'
import type { KakaoDoc } from './kakao'
import { createLimiter, lookupKakaoPlace, MAX_CALLS, toKakaoLive, type CampusCtx, type Searchers } from './kakaoLookup'
import type { CellOutcome, CellQuery } from './kakaoScan'

const CAMPUS: CampusCtx = { id: 'u1', latitude: 36.77, longitude: 126.93, radiusM: 1500 }
const OTHER: CampusCtx = { id: 'u2', latitude: 37.5, longitude: 127.0, radiusM: 1500 }
const doc = (id: string, name: string, over: Partial<KakaoDoc> = {}): KakaoDoc => ({ id, place_name: name, category_name: '음식점 > 한식', road_address_name: `도로 ${id}`, address_name: `지번 ${id}`, phone: '041-000-0000', x: '126.93', y: '36.77', place_url: `http://place.map.kakao.com/${id}`, ...over })
const ok = (docs: KakaoDoc[], nextPage: number | null = null): CellOutcome => ({ ok: true, docs, truncated: false, kakaoCalls: 1, total: docs.length, nextPage })
const pub = (docs: KakaoDoc[]) => vi.fn(async () => ({ data: { success: true, restaurants: docs }, error: null }))
const searchers = (p: ReturnType<typeof pub>, admin: Searchers['adminSearch'] = null): Searchers => ({ publicSearch: p, adminSearch: admin })
const input = (over: Record<string, unknown> = {}) => ({ placeId: '1', name: '어굿플레이스', campuses: [CAMPUS], ...over })

describe('lookupKakaoPlace: only the exact place id is accepted', () => {
  it('finds the place by id around the linked university', async () => {
    const p = pub([doc('2', '다른 곳'), doc('1', '카카오 이름')])
    const r = await lookupKakaoPlace(input(), searchers(p))
    expect(r.status).toBe('verified')
    if (r.status === 'verified') expect(r.place).toMatchObject({ placeId: '1', name: '카카오 이름', category: '음식점 > 한식', address: '도로 1', phone: '041-000-0000', latitude: 36.77, longitude: 126.93, mapUrl: 'https://place.map.kakao.com/1' })
    expect(p).toHaveBeenCalledWith({ query: '어굿플레이스', latitude: 36.77, longitude: 126.93 })
  })

  it('duplicate names with different ids: returns the one with the stored id, never the look-alike', async () => {
    const same = [doc('111', '맛집'), doc('222', '맛집')]
    const r = await lookupKakaoPlace(input({ placeId: '222', name: '맛집' }), searchers(pub(same)))
    expect(r.status === 'verified' && r.place.placeId).toBe('222')
    expect(r.status === 'verified' && r.place.address).toBe('도로 222')
  })

  it('a same-name place with another id is NOT accepted: not_found, nothing substituted', async () => {
    const r = await lookupKakaoPlace(input({ placeId: '999', name: '어굿플레이스' }), searchers(pub([doc('1', '어굿플레이스')])))
    expect(r.status).toBe('not_found')
    expect('place' in r).toBe(false)
  })

  it('a renamed restaurant is still found by id: the stored name is only a hint (found around its own coordinates)', async () => {
    const calls: CellQuery[] = []
    const admin = vi.fn(async (q: CellQuery) => { calls.push(q); return q.query ? ok([]) : ok([doc('1', '새 이름')]) })
    const r = await lookupKakaoPlace(input({ name: '옛날 이름', near: { latitude: 36.7705, longitude: 126.9301 } }), searchers(pub([]), admin))
    expect(r.status === 'verified' && r.via).toBe('nearby')
    expect(calls.some((c) => c.radiusM === 150 && !c.query)).toBe(true)
  })

  it('walks the admin search pages until the id is found, then stops', async () => {
    const admin = vi.fn(async (q: CellQuery) => (q.page === 1 ? ok([doc('7', 'a')], 2) : q.page === 2 ? ok([doc('1', '목표')], 3) : ok([])))
    const r = await lookupKakaoPlace(input(), searchers(pub([]), admin))
    expect(r.status === 'verified' && r.via).toBe('admin_name')
    expect(admin.mock.calls.map((c) => c[0].page)).toEqual([1, 2])
  })

  it('a restaurant linked to another university is searched around THAT university', async () => {
    const p = pub([doc('1', 'x')])
    await lookupKakaoPlace(input({ campuses: [OTHER] }), searchers(p))
    expect(p).toHaveBeenCalledWith({ query: '어굿플레이스', latitude: 37.5, longitude: 127 })
  })

  it('tries each linked university in turn and stops at the first match', async () => {
    const p = vi.fn(async (b: { latitude: number }) => ({ data: { success: true, restaurants: b.latitude === 37.5 ? [doc('1', '여기')] : [] }, error: null }))
    const r = await lookupKakaoPlace(input({ campuses: [CAMPUS, OTHER] }), searchers(p as unknown as ReturnType<typeof pub>))
    expect(r.status).toBe('verified')
    expect(p).toHaveBeenCalledTimes(2)
  })
})

describe('lookupKakaoPlace: not enough to search, or Kakao unavailable', () => {
  it('no university and no coordinates: no_context, and Kakao is not called', async () => {
    const p = pub([])
    expect(await lookupKakaoPlace(input({ campuses: [] }), searchers(p))).toEqual({ status: 'no_context' })
    expect(await lookupKakaoPlace(input({ placeId: '  ' }), searchers(p))).toEqual({ status: 'no_context' })
    expect(p).not.toHaveBeenCalled()
  })

  it('not found anywhere: not_found (and says when the admin search function is not deployed)', async () => {
    const admin = vi.fn(async (): Promise<CellOutcome> => ({ ok: false, kind: 'not_deployed', status: 404, message: 'x' }))
    const r = await lookupKakaoPlace(input(), searchers(pub([doc('2', 'a')]), admin))
    expect(r).toMatchObject({ status: 'not_found', adminSearch: 'unavailable' })
    expect(admin).toHaveBeenCalledTimes(1) // it does not keep hammering a function that is not there
  })

  it.each([[429, 'rate_limited'], [504, 'timeout'], [500, 'unavailable'], [403, 'forbidden']])('HTTP %i from the search function -> error "%s", no further calls', async (status, kind) => {
    const p = vi.fn(async () => ({ data: null, error: { message: 'boom', context: { status } } }))
    const r = await lookupKakaoPlace(input({ campuses: [CAMPUS, OTHER] }), searchers(p as unknown as ReturnType<typeof pub>))
    expect(r).toMatchObject({ status: 'error', kind })
    expect(p).toHaveBeenCalledTimes(1)
  })

  it('a thrown network error is reported as "network"; secrets never appear in the message', async () => {
    const p = vi.fn(async () => { throw new Error('failed KakaoAK abcdef123456 Bearer eyJabcdefgh.ijklmnopqr.stuvwx') })
    const r = await lookupKakaoPlace(input(), searchers(p as unknown as ReturnType<typeof pub>))
    expect(r.status === 'error' && r.kind).toBe('network')
    expect(JSON.stringify(r)).not.toMatch(/abcdef123456|eyJabcdefgh/)
  })

  it('an admin-search rate limit is an error, not "not found"', async () => {
    const admin = vi.fn(async (): Promise<CellOutcome> => ({ ok: false, kind: 'rate_limited', status: 429, message: 'slow down' }))
    expect(await lookupKakaoPlace(input(), searchers(pub([]), admin))).toMatchObject({ status: 'error', kind: 'rate_limited' })
  })

  it('never spends more than MAX_CALLS Kakao calls on one lookup', async () => {
    const admin = vi.fn(async () => ok([doc('9', 'z')], 2))
    const r = await lookupKakaoPlace(input({ campuses: [CAMPUS, OTHER], near: { latitude: 36.7701, longitude: 126.9301 } }), searchers(pub([]), admin as never))
    expect(r.status).toBe('not_found')
    expect((r as { calls: number }).calls).toBeLessThanOrEqual(MAX_CALLS)
  })

  it('stored coordinates outside the university circle are not used for a small-circle search (the function would refuse it)', async () => {
    const admin = vi.fn(async () => ok([]))
    await lookupKakaoPlace(input({ near: { latitude: 10, longitude: 10 } }), searchers(pub([]), admin as never))
    expect(admin.mock.calls.some((c) => (c as unknown as [CellQuery])[0].radiusM === 150)).toBe(false)
  })
})

describe('toKakaoLive: missing values stay missing', () => {
  it('missing phone / address / coordinates are null, never "" or 0', () => {
    const l = toKakaoLive({ id: '5', place_name: '이름', phone: '', road_address_name: '', address_name: '', x: '', y: undefined })
    expect(l).toMatchObject({ phone: null, address: null, latitude: null, longitude: null, category: null, mapUrl: null })
  })
  it('uses the road address, else the lot address; non-numeric coordinates are null', () => {
    expect(toKakaoLive(doc('1', 'a', { road_address_name: '', address_name: '지번 주소' })).address).toBe('지번 주소')
    expect(toKakaoLive(doc('1', 'a', { x: 'abc' })).longitude).toBeNull()
    expect(toKakaoLive(doc('1', 'a', { x: '0', y: '0' }))).toMatchObject({ latitude: 0, longitude: 0 }) // a real 0 is kept; only MISSING is null
  })
})

describe('createLimiter', () => {
  it('runs at most N tasks at once and finishes them all', async () => {
    const limit = createLimiter(3)
    let running = 0; let peak = 0
    const task = () => limit(async () => { running++; peak = Math.max(peak, running); await new Promise((r) => setTimeout(r, 5)); running-- })
    await Promise.all(Array.from({ length: 12 }, task))
    expect(peak).toBe(3)
    expect(running).toBe(0)
  })
})
