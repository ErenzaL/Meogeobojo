import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1'
import { cellWithinCampus, classifyKakaoFailure, type Deps, handle, haversineM, parseRequest } from './core.ts'

const UNI = '5c0a8f3e-0001-4a6e-9b1d-000000000001'
const CAMPUS = { latitude: 36.7699, longitude: 126.9315, search_radius_m: 3000 }
const KEY = 'SECRET-KAKAO-REST-KEY'

type KakaoScript = (u: URL, n: number) => { status?: number; body: unknown } | 'timeout'
interface World {
  admin: boolean
  campus: typeof CAMPUS | null
  kakao: KakaoScript
  calls: { url: URL; headers: Headers }[]
  restCalls: { path: string; auth: string | null }[]
}
function world(over: Partial<World> = {}): World & { deps: Deps } {
  const w: World = {
    admin: true,
    campus: CAMPUS,
    kakao: () => ({ body: { documents: [], meta: { total_count: 0, pageable_count: 0, is_end: true } } }),
    calls: [],
    restCalls: [],
    ...over,
  }
  let n = 0
  const fakeFetch = (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url)
    const headers = new Headers(init?.headers)
    if (url.host === 'dapi.kakao.com') {
      w.calls.push({ url, headers })
      const r = w.kakao(url, ++n)
      if (r === 'timeout') return Promise.reject(new DOMException('aborted', 'AbortError'))
      return Promise.resolve(new Response(JSON.stringify(r.body), { status: r.status ?? 200 }))
    }
    w.restCalls.push({ path: url.pathname.replace('/rest/v1/', ''), auth: headers.get('authorization') })
    if (url.pathname.endsWith('/rpc/has_role')) return Promise.resolve(new Response(JSON.stringify(w.admin)))
    if (url.pathname.endsWith('/universities')) {
      return Promise.resolve(new Response(JSON.stringify(w.campus ? [{ id: UNI, ...w.campus }] : [])))
    }
    return Promise.resolve(new Response('nope', { status: 404 }))
  }
  return { ...w, deps: { env: { supabaseUrl: 'https://x.supabase.co', anonKey: 'anon', kakaoKey: KEY }, fetch: fakeFetch, timeoutMs: 50 }, ...{ calls: w.calls, restCalls: w.restCalls } }
}

const cell = { lat: 36.7699, lng: 126.9315, radius_m: 4243 }
const post = (body: unknown, token: string | null = 'user-jwt') =>
  new Request('https://f/', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  })
const good = { university_id: UNI, category_group_code: 'FD6', cell }
const doc = (i: number) => ({ id: String(i), place_name: `식당${i}`, category_group_code: 'FD6', x: '126.93', y: '36.77', distance: '12' })
const docs = (from: number, n: number) => Array.from({ length: n }, (_, i) => doc(from + i))

Deno.test('parseRequest: accepts a well-formed cell, rejects the rest', () => {
  const ok = parseRequest(good)
  assert(typeof ok !== 'string')
  if (typeof ok !== 'string') { assertEquals(ok.radiusM, 4243); assertEquals(ok.query, null) }
  for (const bad of [
    null, 'x', {}, { ...good, university_id: 'nope' },
    { ...good, cell: { ...cell, lat: 50 } }, { ...good, cell: { ...cell, lng: 100 } },
    { ...good, cell: { ...cell, radius_m: 5 } }, { ...good, cell: { ...cell, radius_m: 20001 } },
    { ...good, cell: { lat: '36', lng: 126, radius_m: 100 } },
    { ...good, category_group_code: 'CS2' }, { ...good, query: '' }, { ...good, query: 'x'.repeat(31) }, { ...good, query: 5 },
  ]) assertEquals(typeof parseRequest(bad), 'string', JSON.stringify(bad))
})

Deno.test('cellWithinCampus: the root circle and any grid circle fit, a far one does not', () => {
  const campus = { lat: 36.7699, lng: 126.9315, radiusM: 3000 }
  assert(cellWithinCampus({ ...campus, radiusM: 3000 * Math.SQRT2 }, campus))
  // the corner-most child of the root square reaches exactly as far as the root circle
  const off = (3000 / 2) / 111_000
  assert(cellWithinCampus({ lat: campus.lat + off, lng: campus.lng + off / Math.cos((36.77 * Math.PI) / 180), radiusM: 3000 / Math.SQRT2 }, campus))
  assertFalse(cellWithinCampus({ lat: campus.lat + 0.2, lng: campus.lng, radiusM: 500 }, campus))
  assertFalse(cellWithinCampus({ ...campus, radiusM: 12000 }, campus))
})

Deno.test('haversine: ~111 km per degree of latitude', () => {
  const d = haversineM(36, 127, 37, 127)
  assert(d > 111_000 && d < 111_400, String(d))
})

Deno.test('auth: method, token, admin role, university, area', async () => {
  const w = world()
  assertEquals((await handle(new Request('https://f/', { method: 'OPTIONS' }), w.deps)).status, 204)
  assertEquals((await handle(new Request('https://f/', { method: 'GET' }), w.deps)).status, 405)
  assertEquals((await handle(post(good, null), w.deps)).status, 401)
  assertEquals((await handle(post({ ...good, university_id: 'x' }), w.deps)).status, 400)
  const notAdmin = world({ admin: false })
  assertEquals((await handle(post(good), notAdmin.deps)).status, 403)
  assertEquals(notAdmin.calls.length, 0, 'a non-admin never reaches Kakao')
  const noUni = world({ campus: null })
  assertEquals((await handle(post(good), noUni.deps)).status, 404)
  const far = world()
  assertEquals((await handle(post({ ...good, cell: { lat: 37.5, lng: 127, radius_m: 500 } }), far.deps)).status, 400)
  assertEquals(far.calls.length, 0, 'an area outside the university never reaches Kakao')
  const noKey = world()
  noKey.deps.env.kakaoKey = ''
  assertEquals((await handle(post(good), noKey.deps)).status, 500)
})

Deno.test('database checks use the CALLER token, never a privileged key', async () => {
  const w = world()
  await handle(post(good, 'the-callers-jwt'), w.deps)
  assert(w.restCalls.length >= 2)
  for (const c of w.restCalls) assertEquals(c.auth, 'Bearer the-callers-jwt')
})

Deno.test('Kakao request: category search with x/y/radius/size 15/page, key only in the header', async () => {
  const w = world()
  const res = await handle(post({ ...good, category_group_code: 'CE7' }), w.deps)
  assertEquals(res.status, 200)
  const u = w.calls[0].url
  assertEquals(u.pathname, '/v2/local/search/category.json')
  assertEquals(u.searchParams.get('category_group_code'), 'CE7')
  assertEquals(u.searchParams.get('x'), '126.9315')
  assertEquals(u.searchParams.get('y'), '36.7699')
  assertEquals(u.searchParams.get('radius'), '4243')
  assertEquals(u.searchParams.get('size'), '15')
  assertEquals(u.searchParams.get('page'), '1')
  assertEquals(w.calls[0].headers.get('authorization'), `KakaoAK ${KEY}`)
  assertFalse(u.href.includes(KEY))
  const text = await res.clone().text()
  assertFalse(text.includes(KEY), 'the key never leaves the server')
  assertEquals(res.headers.get('cache-control'), 'no-store')
})

Deno.test('keyword search keeps the group filter', async () => {
  const w = world()
  await handle(post({ ...good, query: '치킨집' }), w.deps)
  const u = w.calls[0].url
  assertEquals(u.pathname, '/v2/local/search/keyword.json')
  assertEquals(u.searchParams.get('query'), '치킨집')
  assertEquals(u.searchParams.get('category_group_code'), 'FD6')
})

const pagesOf = (total: number, pageable: number) => (u: URL) => {
  const p = Number(u.searchParams.get('page'))
  const here = Math.max(0, Math.min(15, pageable - (p - 1) * 15))
  return { body: { documents: docs((p - 1) * 15, here), meta: { total_count: total, pageable_count: pageable, is_end: p * 15 >= pageable } } }
}
const postPage = (page: number | undefined, extra: Record<string, unknown> = {}) => post({ ...good, ...(page === undefined ? {} : { page }), ...extra })

Deno.test('one request = one Kakao page; the cursor walks 1 -> 2 -> 3 -> null and truncation is flagged', async () => {
  // 100 places exist, Kakao will only hand out 45 (3 pages of 15)
  const w = world({ kakao: pagesOf(100, 45) })
  const seen: unknown[] = []
  let page: number | null = 1
  while (page !== null) {
    const body = await (await handle(postPage(page), w.deps)).json()
    assertEquals(body.documents.length, 15)
    assertEquals(body.meta.page, page)
    assertEquals(body.meta.kakao_calls, 1)
    assertEquals(body.meta.truncated, true)
    seen.push(body.meta.next_page)
    page = body.meta.next_page
  }
  assertEquals(seen, [2, 3, null])
  assertEquals(w.calls.map((c) => c.url.searchParams.get('page')), ['1', '2', '3'], 'exactly one Kakao call per request')
  assertEquals(w.calls.every((c) => c.url.searchParams.get('size') === '15'), true)
})

Deno.test('page defaults to 1 and is validated (1..3)', async () => {
  const w = world({ kakao: pagesOf(20, 20) })
  assertEquals((await (await handle(postPage(undefined), w.deps)).json()).meta.page, 1)
  for (const bad of [0, 4, 1.5, '2', -1]) assertEquals((await handle(postPage(bad as number), w.deps)).status, 400, String(bad))
  assertEquals(w.calls.length, 1, 'a bad page never reaches Kakao')
})

Deno.test('a small area ends on its last page with no next page and is not truncated', async () => {
  const w = world({ kakao: pagesOf(20, 20) })
  const p1 = await (await handle(postPage(1), w.deps)).json()
  assertEquals([p1.meta.next_page, p1.meta.truncated, p1.documents.length], [2, false, 15])
  const p2 = await (await handle(postPage(2), w.deps)).json()
  assertEquals([p2.meta.next_page, p2.meta.truncated, p2.documents.length], [null, false, 5])
})

Deno.test('a single page area: next_page is null at once', async () => {
  const w = world({ kakao: () => ({ body: { documents: docs(0, 7), meta: { total_count: 7, pageable_count: 7, is_end: true } } }) })
  const body = await (await handle(postPage(1), w.deps)).json()
  assertEquals(body.meta.next_page, null)
  assertEquals(body.meta.truncated, false)
  assertEquals(w.calls.length, 1)
})

Deno.test('exactly 45 accessible cannot be told apart from "more": reported truncated', async () => {
  const w = world({ kakao: pagesOf(45, 45) })
  assertEquals((await (await handle(postPage(1), w.deps)).json()).meta.truncated, true)
})

Deno.test('documents are slimmed to what the admin needs', async () => {
  const w = world({ kakao: () => ({ body: { documents: [{ ...doc(1), distance: '9', extra: 'x' }], meta: { total_count: 1, pageable_count: 1, is_end: true } } }) })
  const body = await (await handle(post(good), w.deps)).json()
  assertEquals(Object.keys(body.documents[0]).includes('distance'), false)
  assertEquals(Object.keys(body.documents[0]).includes('extra'), false)
  assertEquals(body.documents[0].id, '1')
})

Deno.test('failures: rate limit, quota code, outage, timeout, rejection map to distinct statuses', async () => {
  const run = async (script: KakaoScript) => (await handle(post(good), world({ kakao: script }).deps)).status
  assertEquals(await run(() => ({ status: 429, body: { message: 'slow down' } })), 429)
  assertEquals(await run(() => ({ status: 400, body: { errorType: 'RequestThrottled', code: -10, msg: 'API limit has been exceeded.' } })), 429)
  assertEquals(await run(() => ({ status: 503, body: {} })), 502)
  assertEquals(await run(() => 'timeout'), 502)
  assertEquals(await run(() => ({ status: 400, body: { code: -2, msg: 'bad' } })), 400)
  assertEquals(await run(() => ({ status: 200, body: { nope: true } })), 502)
  assertEquals(classifyKakaoFailure(429, null).kind, 'rate_limited')
  assertEquals(classifyKakaoFailure(500, null).kind, 'unavailable')
})

Deno.test('a failure on page 2 does not touch page 1: each page is its own retryable request', async () => {
  const w = world({ kakao: (u) => (u.searchParams.get('page') === '2' ? { status: 429, body: {} } : pagesOf(40, 40)(u)) })
  assertEquals((await handle(postPage(1), w.deps)).status, 200)
  assertEquals((await handle(postPage(2), w.deps)).status, 429)
  assertEquals((await handle(postPage(2), w.deps)).status, 429, 'asking for the same page again is a clean retry')
})
