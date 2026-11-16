import { assertEquals } from 'jsr:@std/assert@1'
import { clearMemo, handle, parseRequest, type Deps, type KakaoDoc } from './core.ts'

const U = '5c0a8f3e-0001-4a6e-9b1d-000000000001'
const CAMPUS = { id: U, latitude: 36.77, longitude: 126.93, search_radius_m: 3000 }
const doc = (id: string, name: string): KakaoDoc => ({ id, place_name: name, category_name: '음식점 > 한식', road_address_name: `도로 ${id}`, x: '126.931', y: '36.771', distance: '120' })

/** A fake network: the universities table and a Kakao that knows [places]. Counts the Kakao calls. */
function net(places: KakaoDoc[], opts: { campus?: unknown; kakaoStatus?: number; kakaoAfter?: number } = {}) {
  const log = { kakao: 0, queries: [] as string[] }
  const fetch: typeof globalThis.fetch = (input) => {
    const url = String(input)
    if (url.includes('/rest/v1/universities')) return Promise.resolve(new Response(JSON.stringify(opts.campus === undefined ? [CAMPUS] : opts.campus), { status: 200 }))
    log.kakao++
    const q = new URL(url).searchParams.get('query') ?? ''
    log.queries.push(q)
    if (opts.kakaoStatus && log.kakao > (opts.kakaoAfter ?? 0)) return Promise.resolve(new Response('{}', { status: opts.kakaoStatus }))
    // Kakao answers with the places whose name contains the query (distractors included)
    return Promise.resolve(new Response(JSON.stringify({ documents: places.filter((p) => p.place_name.includes(q)) }), { status: 200 }))
  }
  const deps: Deps = { env: { supabaseUrl: 'https://x.test', anonKey: 'a', kakaoKey: 'k' }, fetch }
  return { deps, log }
}

const post = (deps: Deps, body: unknown) => handle(new Request('https://f.test', { method: 'POST', body: JSON.stringify(body) }), deps)

Deno.test('validation: ids must be numeric Kakao ids, names present, at most 200, duplicates folded', () => {
  assertEquals(typeof parseRequest({ universityId: 'x', places: [] }), 'string')
  assertEquals(typeof parseRequest({ universityId: U, places: [{ id: 'abc', name: 'n' }] }), 'string')
  assertEquals(typeof parseRequest({ universityId: U, places: [{ id: '1', name: '' }] }), 'string')
  assertEquals(typeof parseRequest({ universityId: U, places: Array.from({ length: 201 }, (_, i) => ({ id: String(i), name: 'n' })) }), 'string')
  const ok = parseRequest({ universityId: U, places: [{ id: '1', name: ' 국수집 ' }, { id: '1', name: '국수집' }] })
  assertEquals(typeof ok === 'string' ? ok : ok.places, [{ id: '1', name: '국수집' }])
})

Deno.test('accepts a document ONLY when its id equals the id asked for (a similar name is not enough)', async () => {
  clearMemo()
  const { deps } = net([doc('999', '국수집 본점'), doc('1', '국수집')])
  const res = await post(deps, { universityId: U, places: [{ id: '1', name: '국수집' }, { id: '2', name: '국수집' }] })
  const body = await res.json()
  assertEquals(res.status, 200)
  assertEquals(body.places.map((p: KakaoDoc) => p.id), ['1'])
  assertEquals(body.unresolved, ['2'])
  assertEquals(body.partial, false)
})

Deno.test('one invocation resolves many places, and a repeat inside the memo window does not call Kakao again', async () => {
  clearMemo()
  const all = Array.from({ length: 30 }, (_, i) => doc(String(i + 1), `식당${i + 1}`))
  const { deps, log } = net(all)
  const places = all.map((d) => ({ id: d.id, name: d.place_name }))
  const first = await (await post(deps, { universityId: U, places })).json()
  assertEquals(first.places.length, 30)
  assertEquals(log.kakao, 30)
  await post(deps, { universityId: U, places })
  assertEquals(log.kakao, 30) // served from the in-memory memo
})

Deno.test('only the documents asked for are returned, with the fields the app needs and nothing else', async () => {
  clearMemo()
  const { deps } = net([{ ...doc('1', '국수집'), secret: 'x' } as KakaoDoc])
  const body = await (await post(deps, { universityId: U, places: [{ id: '1', name: '국수집' }] })).json()
  const allowed = new Set(['address_name', 'category_group_code', 'category_name', 'distance', 'id', 'phone', 'place_name', 'place_url', 'road_address_name', 'x', 'y'])
  assertEquals(Object.keys(body.places[0]).every((k) => allowed.has(k)), true)
  assertEquals('secret' in body.places[0], false)
})

Deno.test('a Kakao quota / outage stops the run: partial answer, the rest reported unresolved, never an invented place', async () => {
  clearMemo()
  const all = Array.from({ length: 20 }, (_, i) => doc(String(i + 1), `식당${i + 1}`))
  const { deps } = net(all, { kakaoStatus: 429, kakaoAfter: 3 })
  const body = await (await post(deps, { universityId: U, places: all.map((d) => ({ id: d.id, name: d.place_name })) })).json()
  assertEquals(body.partial, true)
  assertEquals(body.places.length + body.unresolved.length, 20)
  assertEquals(body.places.length <= 3 + 8, true)
})

Deno.test('unknown university -> 404; bad body -> 400; GET -> 405; OPTIONS -> 204', async () => {
  const { deps } = net([], { campus: [] })
  assertEquals((await post(deps, { universityId: U, places: [{ id: '1', name: 'n' }] })).status, 404)
  assertEquals((await post(deps, { universityId: U, places: [] })).status, 400)
  assertEquals((await handle(new Request('https://f.test'), deps)).status, 405)
  assertEquals((await handle(new Request('https://f.test', { method: 'OPTIONS' }), deps)).status, 204)
})

Deno.test('searches only inside the university: the query is the stored name and the area comes from the database', async () => {
  clearMemo()
  let seen = ''
  const base = net([doc('1', '국수집')])
  const deps: Deps = { ...base.deps, fetch: (input, i) => { const u = String(input); if (u.includes('keyword.json')) seen = u; return base.deps.fetch(input, i) } }
  await post(deps, { universityId: U, places: [{ id: '1', name: '국수집' }] })
  const p = new URL(seen).searchParams
  assertEquals([p.get('x'), p.get('y'), p.get('radius'), p.get('query')], ['126.93', '36.77', '3000', '국수집'])
})
