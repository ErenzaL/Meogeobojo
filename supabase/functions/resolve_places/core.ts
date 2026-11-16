/**
 * resolve_places: the live Kakao details (coordinates, category path, address, phone, map link) of a LIST of managed
 * restaurants, for the app. One request, one invocation, however many restaurants.
 *
 * Why it exists: the restaurant list shown to students comes from the published Supabase records (the Admin is the
 * source of truth), but Kakao policy means those records do not store Kakao's coordinates or category. The app still
 * needs them (distance, map markers, category filters). Kakao has no "get place by id", so each place is searched by
 * its stored name around its university and accepted ONLY when the returned document's id equals the stored Kakao
 * place id. Doing that for ~100 places from the phone would be ~100 function calls; here it is one.
 *
 *   POST { universityId, places: [{ id: "<kakao place id>", name: "<stored name>" }, ...] }   (<= MAX_PLACES)
 *   ->   { success: true, places: [<Kakao document>...], unresolved: ["<id>"...], partial: boolean }
 *
 * Not a general Kakao proxy: the search area is the university's own circle (read from the database), the queries are
 * the stored restaurant names, and only documents whose id was asked for are returned.
 * Kakao's terms: results are for real-time use. Documents are kept only in this isolate's memory for MEMO_TTL_MS
 * (the same 5 minutes the app's own cache uses), never written anywhere and never logged (only counts are).
 *
 * No Deno-specific API here (`fetch` and the environment are arguments), so the same code is tested with `deno test`.
 */

export const KAKAO_KEYWORD = 'https://dapi.kakao.com/v2/local/search/keyword.json'
export const MAX_PLACES = 200
export const MAX_NAME = 80
export const CONCURRENCY = 8
export const MEMO_TTL_MS = 5 * 60_000
const DEFAULT_RADIUS_M = 1500
const MAX_RADIUS_M = 20_000

export interface Env { supabaseUrl: string; anonKey: string; kakaoKey: string }
export interface Deps {
  env: Env
  fetch: typeof fetch
  now?: () => number
  timeoutMs?: number
}

const JSON_HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, x-client-info, apikey, content-type',
  'access-control-allow-methods': 'POST, OPTIONS',
}
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: JSON_HEADERS })

export interface KakaoDoc {
  id: string
  place_name: string
  category_name?: string
  category_group_code?: string
  address_name?: string
  road_address_name?: string
  phone?: string
  place_url?: string
  x?: string
  y?: string
  distance?: string
}
const slim = (d: KakaoDoc): KakaoDoc => ({
  id: String(d.id), place_name: d.place_name, category_name: d.category_name, category_group_code: d.category_group_code,
  address_name: d.address_name, road_address_name: d.road_address_name, phone: d.phone, place_url: d.place_url, x: d.x, y: d.y, distance: d.distance,
})

export interface PlaceRef { id: string; name: string }
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const KAKAO_ID = /^\d{1,20}$/

/** Validates the body. A string is the reason it was refused. */
export function parseRequest(raw: unknown): { universityId: string; places: PlaceRef[] } | string {
  const b = raw as { universityId?: unknown; places?: unknown } | null
  if (!b || typeof b !== 'object') return 'body must be an object'
  if (typeof b.universityId !== 'string' || !UUID.test(b.universityId)) return 'universityId must be a uuid'
  if (!Array.isArray(b.places) || b.places.length === 0) return 'places must be a non-empty array'
  if (b.places.length > MAX_PLACES) return `at most ${MAX_PLACES} places per request`
  const seen = new Set<string>()
  const places: PlaceRef[] = []
  for (const p of b.places as { id?: unknown; name?: unknown }[]) {
    if (!p || typeof p.id !== 'string' || !KAKAO_ID.test(p.id)) return 'every place needs a numeric Kakao id'
    if (typeof p.name !== 'string' || p.name.trim() === '' || p.name.length > MAX_NAME) return `every place needs a name of 1..${MAX_NAME} characters`
    if (!seen.has(p.id)) { seen.add(p.id); places.push({ id: p.id, name: p.name.trim() }) }
  }
  return { universityId: b.universityId, places }
}

export interface Campus { id: string; lat: number; lng: number; radiusM: number }
export async function loadCampus(id: string, deps: Deps): Promise<Campus | null> {
  const res = await deps.fetch(`${deps.env.supabaseUrl}/rest/v1/universities?id=eq.${encodeURIComponent(id)}&select=id,latitude,longitude,search_radius_m`, {
    headers: { apikey: deps.env.anonKey, Authorization: `Bearer ${deps.env.anonKey}` },
  })
  if (!res.ok) return null
  const r = ((await res.json()) as { id: string; latitude: number | null; longitude: number | null; search_radius_m: number | null }[])[0]
  if (!r || r.latitude == null || r.longitude == null) return null
  return { id: r.id, lat: Number(r.latitude), lng: Number(r.longitude), radiusM: Math.min(MAX_RADIUS_M, Number(r.search_radius_m ?? DEFAULT_RADIUS_M)) }
}

export class KakaoError extends Error {
  constructor(public kind: 'rate_limited' | 'unavailable' | 'rejected', message: string) { super(message) }
}
export function classifyKakaoFailure(status: number, body: unknown): KakaoError {
  const code = (body as { code?: unknown } | null)?.code
  if (status === 429 || code === -10) return new KakaoError('rate_limited', `Kakao ${status}`)
  if (status >= 500 || status === 408) return new KakaoError('unavailable', `Kakao ${status}`)
  return new KakaoError('rejected', `Kakao ${status}`)
}

/** One keyword search around the campus; the document whose id is [id], or null. */
async function findPlace(p: PlaceRef, c: Campus, deps: Deps): Promise<KakaoDoc | null> {
  const params = new URLSearchParams({ query: p.name, x: String(c.lng), y: String(c.lat), radius: String(c.radiusM), size: '15', sort: 'distance' })
  const ctl = new AbortController()
  const timer = setTimeout(() => ctl.abort(), deps.timeoutMs ?? 8000)
  let res: Response
  try {
    res = await deps.fetch(`${KAKAO_KEYWORD}?${params}`, { headers: { Authorization: `KakaoAK ${deps.env.kakaoKey}` }, signal: ctl.signal })
  } catch { throw new KakaoError('unavailable', 'Kakao did not answer in time') } finally { clearTimeout(timer) }
  let body: unknown = null
  try { body = await res.json() } catch { /* handled below */ }
  if (!res.ok) throw classifyKakaoFailure(res.status, body)
  const docs = (body as { documents?: unknown } | null)?.documents
  if (!Array.isArray(docs)) throw new KakaoError('unavailable', 'unexpected Kakao response')
  const hit = (docs as KakaoDoc[]).find((d) => d && d.id != null && String(d.id) === p.id)
  return hit ? slim(hit) : null
}

// The only state: a short in-memory memo per isolate (never persisted), so a burst of app starts costs Kakao once.
const memo = new Map<string, { at: number; doc: KakaoDoc | null }>()
export const clearMemo = () => memo.clear()

export interface Resolved { places: KakaoDoc[]; unresolved: string[]; partial: boolean; kakaoCalls: number }

export async function resolvePlaces(places: PlaceRef[], campus: Campus, deps: Deps): Promise<Resolved> {
  const now = deps.now ?? Date.now
  const found: KakaoDoc[] = []
  const unresolved: string[] = []
  const todo: PlaceRef[] = []
  for (const p of places) {
    const hit = memo.get(`${campus.id}|${p.id}`)
    if (hit && now() - hit.at < MEMO_TTL_MS) { if (hit.doc) found.push(hit.doc); else unresolved.push(p.id) } else todo.push(p)
  }
  let partial = false
  let calls = 0
  let next = 0
  let stop: KakaoError | null = null
  const worker = async () => {
    while (!stop) {
      const p = todo[next++]
      if (!p) return
      try {
        calls++
        const doc = await findPlace(p, campus, deps)
        memo.set(`${campus.id}|${p.id}`, { at: now(), doc })
        if (doc) found.push(doc); else unresolved.push(p.id)
      } catch (e) {
        if (e instanceof KakaoError && e.kind !== 'rejected') { stop = e; partial = true; unresolved.push(p.id) } else { unresolved.push(p.id) }
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(CONCURRENCY, todo.length) }, worker))
  // places nobody got to because the run stopped (quota / outage) are unresolved too, and the answer is marked partial
  for (let i = next; i < todo.length; i++) unresolved.push(todo[i].id)
  if (stop) partial = true
  return { places: found, unresolved: [...new Set(unresolved)], partial, kakaoCalls: calls }
}

export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: JSON_HEADERS })
  if (req.method !== 'POST') return json(405, { success: false, error: 'Use POST' })
  if (!deps.env.kakaoKey) return json(500, { success: false, error: 'server_misconfigured' })
  let raw: unknown
  try { raw = await req.json() } catch { return json(400, { success: false, error: 'body must be JSON' }) }
  const parsed = parseRequest(raw)
  if (typeof parsed === 'string') return json(400, { success: false, error: parsed })
  const campus = await loadCampus(parsed.universityId, deps)
  if (!campus) return json(404, { success: false, error: 'unknown_university_or_no_coordinates' })
  try {
    const out = await resolvePlaces(parsed.places, campus, deps)
    console.log(JSON.stringify({ fn: 'resolve_places', asked: parsed.places.length, found: out.places.length, kakao_calls: out.kakaoCalls, partial: out.partial }))
    return json(200, { success: true, places: out.places, unresolved: out.unresolved, partial: out.partial })
  } catch {
    console.log(JSON.stringify({ fn: 'resolve_places', error: 'internal' }))
    return json(500, { success: false, error: 'internal' })
  }
}
