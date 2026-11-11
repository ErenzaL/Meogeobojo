/**
 * admin_kakao_search: a narrow, admin-only window onto the Kakao Local API for the Admin "카카오 식당 불러오기"
 * scan. NOT the app's `search_restaurants` function (that one is deployed separately, is not in this repo and is
 * left untouched).
 *
 * One request = ONE search area (a circle) for ONE food group (+ optionally one keyword), all of its accessible
 * pages. The Admin app decides which areas to ask for (an adaptive grid over the university's radius); this function
 * only
 *   - keeps the Kakao REST key server-side (secret `KAKAO_REST_API_KEY`),
 *   - requires a signed-in ADMIN (checked in the database with the caller's own token, `has_role('admin')`),
 *   - reads the university (centre + `search_radius_m`) from the database itself, and refuses areas outside it, so it
 *     cannot be used as a general Kakao proxy,
 *   - pages through the results (size 15, as many pages as Kakao says are accessible) and tells the caller whether
 *     the area was TRUNCATED (more places exist than Kakao will hand out), so the caller can split it,
 *   - maps Kakao rate-limit / outage answers to distinct statuses so the caller can back off.
 *
 * Kakao's terms: results are for real-time use. Nothing here is stored, cached or logged (only counts are logged).
 *
 * This file has no Deno-specific API (it takes `fetch` and the environment as arguments), so the same code is tested
 * with `deno test` and is bundled by `index.ts`.
 */

export const KAKAO_BASE = 'https://dapi.kakao.com/v2/local/search'
export const PAGE_SIZE = 15 // Kakao: size 1..15
export const MAX_PAGES = 3 // Kakao: pageable_count is at most 45 = 3 pages of 15
export const MAX_ACCESSIBLE = 45
export const GROUPS = ['FD6', 'CE7'] as const
export type Group = (typeof GROUPS)[number]

export interface Env {
  supabaseUrl: string
  anonKey: string
  kakaoKey: string
}
export interface Deps {
  env: Env
  fetch: typeof fetch
  /** milliseconds; injectable for tests */
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

// ---------------------------------------------------------------------------------------------------------------
// geometry (metres on the WGS84 sphere; the same formula the Admin app uses)
// ---------------------------------------------------------------------------------------------------------------
const EARTH_RADIUS_M = 6371008.8
const rad = (d: number) => (d * Math.PI) / 180
export function haversineM(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const dLat = rad(bLat - aLat)
  const dLng = rad(bLng - aLng)
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(aLat)) * Math.cos(rad(bLat)) * Math.sin(dLng / 2) ** 2
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)))
}

// ---------------------------------------------------------------------------------------------------------------
// request validation
// ---------------------------------------------------------------------------------------------------------------
export interface CellRequest {
  universityId: string
  lat: number
  lng: number
  radiusM: number
  group: Group
  query: string | null
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const finite = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v)

export function parseRequest(raw: unknown): CellRequest | string {
  if (!raw || typeof raw !== 'object') return 'body must be a JSON object'
  const b = raw as Record<string, unknown>
  if (typeof b.university_id !== 'string' || !UUID.test(b.university_id)) return 'university_id must be a uuid'
  const cell = b.cell as Record<string, unknown> | undefined
  if (!cell || !finite(cell.lat) || !finite(cell.lng) || !finite(cell.radius_m)) return 'cell needs numeric lat, lng, radius_m'
  if (cell.lat < 33 || cell.lat > 39 || cell.lng < 124 || cell.lng > 132) return 'cell is outside Korea'
  if (cell.radius_m < 10 || cell.radius_m > 20000) return 'cell.radius_m must be 10..20000 (Kakao allows at most 20000)'
  if (!GROUPS.includes(b.category_group_code as Group)) return 'category_group_code must be FD6 or CE7'
  let query: string | null = null
  if (b.query !== undefined && b.query !== null) {
    if (typeof b.query !== 'string') return 'query must be a string'
    const q = b.query.trim()
    if (q.length === 0 || q.length > 30) return 'query must be 1..30 characters'
    query = q
  }
  return {
    universityId: b.university_id,
    lat: cell.lat,
    lng: cell.lng,
    radiusM: Math.round(cell.radius_m),
    group: b.category_group_code as Group,
    query,
  }
}

/**
 * The scan asks for the circle that circumscribes each grid square. Every such circle lies inside the circle that
 * circumscribes the university's bounding square (radius R*sqrt(2) around the centre). Anything beyond that, with a
 * little slack for rounding, is not part of a legitimate scan.
 */
export function cellWithinCampus(c: { lat: number; lng: number; radiusM: number }, campus: { lat: number; lng: number; radiusM: number }): boolean {
  const reach = campus.radiusM * Math.SQRT2
  return haversineM(campus.lat, campus.lng, c.lat, c.lng) + c.radiusM <= reach * 1.02 + 25
}

// ---------------------------------------------------------------------------------------------------------------
// Kakao
// ---------------------------------------------------------------------------------------------------------------
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
}
interface KakaoMeta { total_count: number; pageable_count: number; is_end: boolean }

export class KakaoError extends Error {
  constructor(public kind: 'rate_limited' | 'unavailable' | 'rejected', message: string) { super(message) }
}

/** Kakao signals "too many calls / quota" with HTTP 429, or code -10 ("API limit has been exceeded", HTTP 400 or 429). */
export function classifyKakaoFailure(status: number, body: unknown): KakaoError {
  const code = (body as { errorType?: unknown; code?: unknown } | null)?.code
  if (status === 429 || code === -10) return new KakaoError('rate_limited', `Kakao ${status}`)
  if (status >= 500 || status === 408) return new KakaoError('unavailable', `Kakao ${status}`)
  return new KakaoError('rejected', `Kakao ${status}`)
}

async function kakaoPage(req: CellRequest, page: number, deps: Deps): Promise<{ docs: KakaoDoc[]; meta: KakaoMeta }> {
  const params = new URLSearchParams({
    category_group_code: req.group,
    x: String(req.lng),
    y: String(req.lat),
    radius: String(req.radiusM),
    page: String(page),
    size: String(PAGE_SIZE),
    sort: 'distance',
  })
  let path = 'category.json'
  if (req.query) {
    path = 'keyword.json'
    params.set('query', req.query)
  }
  const ctl = new AbortController()
  const timer = setTimeout(() => ctl.abort(), deps.timeoutMs ?? 8000)
  let res: Response
  try {
    res = await deps.fetch(`${KAKAO_BASE}/${path}?${params}`, {
      headers: { Authorization: `KakaoAK ${deps.env.kakaoKey}` },
      signal: ctl.signal,
    })
  } catch {
    throw new KakaoError('unavailable', 'Kakao did not answer in time')
  } finally {
    clearTimeout(timer)
  }
  let body: unknown = null
  try { body = await res.json() } catch { /* handled below */ }
  if (!res.ok) throw classifyKakaoFailure(res.status, body)
  const b = body as { documents?: unknown; meta?: Partial<KakaoMeta> } | null
  if (!b || !Array.isArray(b.documents) || !b.meta) throw new KakaoError('unavailable', 'unexpected Kakao response')
  const meta: KakaoMeta = {
    total_count: Number(b.meta.total_count ?? 0),
    pageable_count: Number(b.meta.pageable_count ?? 0),
    is_end: b.meta.is_end !== false,
  }
  return { docs: b.documents as KakaoDoc[], meta }
}

/** Pages 1..N of one area. `truncated` = Kakao has more places here than it will let anyone read. */
export async function searchCell(req: CellRequest, deps: Deps) {
  const docs: KakaoDoc[] = []
  let calls = 0
  const first = await kakaoPage(req, 1, deps)
  calls++
  docs.push(...first.docs)
  const accessible = Math.min(first.meta.pageable_count, MAX_ACCESSIBLE)
  const pages = Math.min(MAX_PAGES, Math.ceil(accessible / PAGE_SIZE))
  let isEnd = first.meta.is_end
  for (let p = 2; p <= pages && !isEnd; p++) {
    const next = await kakaoPage(req, p, deps)
    calls++
    docs.push(...next.docs)
    isEnd = next.meta.is_end
  }
  // pageable_count tops out at 45: reaching it means we cannot tell whether more exist.
  const truncated = first.meta.total_count > first.meta.pageable_count || first.meta.pageable_count >= MAX_ACCESSIBLE
  return {
    documents: docs.map(slim),
    meta: {
      total_count: first.meta.total_count,
      pageable_count: first.meta.pageable_count,
      returned: docs.length,
      truncated,
      kakao_calls: calls,
    },
  }
}

/** Only what the Admin preview and the registration need. */
const slim = (d: KakaoDoc): KakaoDoc => ({
  id: String(d.id),
  place_name: d.place_name,
  category_name: d.category_name,
  category_group_code: d.category_group_code,
  address_name: d.address_name,
  road_address_name: d.road_address_name,
  phone: d.phone,
  place_url: d.place_url,
  x: d.x,
  y: d.y,
})

// ---------------------------------------------------------------------------------------------------------------
// database checks, with the CALLER's own token (never a service key)
// ---------------------------------------------------------------------------------------------------------------
async function rest(path: string, init: RequestInit, token: string, deps: Deps): Promise<Response> {
  return await deps.fetch(`${deps.env.supabaseUrl}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: deps.env.anonKey, Authorization: `Bearer ${token}`, 'content-type': 'application/json', ...(init.headers ?? {}) },
  })
}

export async function callerIsAdmin(token: string, deps: Deps): Promise<boolean> {
  const res = await rest('rpc/has_role', { method: 'POST', body: JSON.stringify({ p_min: 'admin' }) }, token, deps)
  if (!res.ok) return false
  return (await res.json()) === true
}

export interface Campus { id: string; lat: number; lng: number; radiusM: number }
export async function loadCampus(id: string, token: string, deps: Deps): Promise<Campus | null> {
  const res = await rest(`universities?id=eq.${encodeURIComponent(id)}&select=id,latitude,longitude,search_radius_m`, { method: 'GET' }, token, deps)
  if (!res.ok) return null
  const rows = (await res.json()) as { id: string; latitude: number | null; longitude: number | null; search_radius_m: number | null }[]
  const r = rows[0]
  if (!r || r.latitude == null || r.longitude == null || r.search_radius_m == null) return null
  return { id: r.id, lat: Number(r.latitude), lng: Number(r.longitude), radiusM: Number(r.search_radius_m) }
}

// ---------------------------------------------------------------------------------------------------------------
// handler
// ---------------------------------------------------------------------------------------------------------------
export async function handle(req: Request, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: JSON_HEADERS })
  if (req.method !== 'POST') return json(405, { success: false, error: 'Use POST' })
  if (!deps.env.kakaoKey) return json(500, { success: false, error: 'server_misconfigured' })

  const auth = req.headers.get('authorization') ?? ''
  const token = auth.toLowerCase().startsWith('bearer ') ? auth.slice(7).trim() : ''
  if (!token) return json(401, { success: false, error: 'sign_in_required' })

  let raw: unknown
  try { raw = await req.json() } catch { return json(400, { success: false, error: 'body must be JSON' }) }
  const parsed = parseRequest(raw)
  if (typeof parsed === 'string') return json(400, { success: false, error: parsed })

  if (!(await callerIsAdmin(token, deps))) return json(403, { success: false, error: 'admin_only' })

  const campus = await loadCampus(parsed.universityId, token, deps)
  if (!campus) return json(404, { success: false, error: 'unknown_university_or_no_coordinates' })
  if (!cellWithinCampus(parsed, campus)) return json(400, { success: false, error: 'cell_outside_university_area' })

  try {
    const out = await searchCell(parsed, deps)
    console.log(JSON.stringify({ fn: 'admin_kakao_search', group: parsed.group, kw: !!parsed.query, ...out.meta }))
    return json(200, {
      success: true,
      university: { id: campus.id, latitude: campus.lat, longitude: campus.lng, search_radius_m: campus.radiusM },
      ...out,
    })
  } catch (e) {
    if (e instanceof KakaoError) {
      console.log(JSON.stringify({ fn: 'admin_kakao_search', error: e.kind }))
      if (e.kind === 'rate_limited') return json(429, { success: false, error: 'kakao_rate_limited' })
      if (e.kind === 'unavailable') return json(502, { success: false, error: 'kakao_unavailable' })
      return json(400, { success: false, error: 'kakao_rejected' })
    }
    console.log(JSON.stringify({ fn: 'admin_kakao_search', error: 'internal' }))
    return json(500, { success: false, error: 'internal' })
  }
}
