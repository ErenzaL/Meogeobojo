import type { KakaoDoc } from './kakao'
import { haversineM } from './kakaoGeo'
import { redact, statusOf } from './kakaoDiag'
import type { CellOutcome, FailKind, Group, SearchCell } from './kakaoScan'

/**
 * Live Kakao lookup for ONE restaurant, by its immutable Kakao place id.
 *
 * Kakao has no "get place by id" call in the Local API, so the place is searched for (around the linked
 * university, and around the restaurant's own coordinates when it has them) and accepted ONLY when a returned
 * document's `id` equals the stored `kakao_place_id`. A similar name is never enough, and nothing here ever
 * returns a different place than the id asked for.
 *
 * What comes back is transient display data. Nothing in this module saves it anywhere (Kakao allows results in
 * real time, not as a permanent cache).
 */

/** What the admin shows for a place Kakao says exists. Missing values are null, never 0 or ''. */
export type KakaoLive = {
  placeId: string; name: string | null; category: string | null; address: string | null; phone: string | null
  latitude: number | null; longitude: number | null; mapUrl: string | null
}

/** A linked university: the centre and radius the lookup may search inside. */
export type CampusCtx = { id: string; latitude: number; longitude: number; radiusM: number }
export type LookupInput = {
  placeId: string
  /** The stored (Meogeobojo) name. It is a search hint only; the match is by id. */
  name: string
  campuses: CampusCtx[]
  /** The restaurant's own stored coordinates, when it has them. */
  near?: { latitude: number; longitude: number } | null
}

export type LookupFailKind = Extract<FailKind, 'rate_limited' | 'unavailable' | 'timeout' | 'network' | 'forbidden'>
export type LookupResult =
  | { status: 'verified'; place: KakaoLive; calls: number; via: 'name' | 'name_near' | 'admin_name' | 'nearby' }
  /** Searched, and no returned place had this id. */
  | { status: 'not_found'; calls: number; adminSearch: 'used' | 'unavailable' | 'skipped' }
  /** No linked university and no coordinates: there is nowhere to search. */
  | { status: 'no_context' }
  | { status: 'error'; kind: LookupFailKind; message: string; calls: number }

export type PublicSearch = (body: { query: string; latitude: number; longitude: number }) => PromiseLike<{ data: unknown; error: unknown }>
export type Searchers = { publicSearch: PublicSearch; adminSearch: SearchCell | null }

/** Most Kakao calls one lookup may spend. A lookup stops at the first match. */
export const MAX_CALLS = 12
const MAX_CAMPUSES = 3
const NEARBY_RADIUS_M = 150
const MAX_PAGES = 3

const num = (v: unknown): number | null => {
  if (v == null || v === '') return null
  const n = Number(v)
  return Number.isFinite(n) ? n : null
}
const text = (v: unknown): string | null => (typeof v === 'string' && v.trim() ? v.trim() : null)

/** Kakao document -> display model. Coordinates that are missing or not numbers stay null. */
export function toKakaoLive(d: KakaoDoc): KakaoLive {
  return {
    placeId: String(d.id), name: text(d.place_name), category: text(d.category_name),
    address: text(d.road_address_name) ?? text(d.address_name), phone: text(d.phone),
    latitude: num(d.y), longitude: num(d.x), mapUrl: text(d.place_url)?.replace(/^http:/, 'https:') ?? null,
  }
}

const findExact = (docs: unknown, placeId: string): KakaoDoc | null =>
  (Array.isArray(docs) ? (docs as KakaoDoc[]) : []).find((d) => d && d.id != null && String(d.id) === placeId) ?? null

function failKindOf(e: unknown): { kind: LookupFailKind; message: string } {
  const status = statusOf(e)
  const message = redact(e instanceof Error ? e.message : typeof e === 'object' && e && 'message' in e ? String((e as { message: unknown }).message) : 'error')
  if (status === 429) return { kind: 'rate_limited', message }
  if (status === 408 || status === 504) return { kind: 'timeout', message }
  if (status === 401 || status === 403) return { kind: 'forbidden', message }
  if (status !== undefined && status >= 500) return { kind: 'unavailable', message }
  return { kind: status === undefined ? 'network' : 'unavailable', message }
}

const inside = (c: CampusCtx, lat: number, lng: number) => haversineM(c.latitude, c.longitude, lat, lng) <= c.radiusM

export async function lookupKakaoPlace(input: LookupInput, s: Searchers, signal: AbortSignal = new AbortController().signal): Promise<LookupResult> {
  const placeId = input.placeId.trim()
  const campuses = input.campuses.filter((c) => Number.isFinite(c.latitude) && Number.isFinite(c.longitude)).slice(0, MAX_CAMPUSES)
  const near = input.near && Number.isFinite(input.near.latitude) && Number.isFinite(input.near.longitude) ? input.near : null
  if (!placeId || (campuses.length === 0 && !near)) return { status: 'no_context' }
  let calls = 0
  let adminState: 'used' | 'unavailable' | 'skipped' = 'skipped'
  const verified = (d: KakaoDoc, via: Extract<LookupResult, { status: 'verified' }>['via']): LookupResult => ({ status: 'verified', place: toKakaoLive(d), calls, via })
  const fail = (e: unknown): LookupResult => ({ status: 'error', ...failKindOf(e), calls })

  // 1. the app's own search function (exists on every project): the stored name around each linked campus, then around the restaurant
  const centres = [
    ...campuses.map((c) => ({ latitude: c.latitude, longitude: c.longitude, via: 'name' as const })),
    ...(near ? [{ ...near, via: 'name_near' as const }] : []),
  ]
  const tried = new Set<string>()
  for (const c of centres) {
    const key = `${c.latitude.toFixed(4)},${c.longitude.toFixed(4)}`
    if (tried.has(key) || !input.name.trim()) continue
    tried.add(key)
    if (calls >= MAX_CALLS || signal.aborted) break
    calls++
    try {
      const { data, error } = await s.publicSearch({ query: input.name.trim(), latitude: c.latitude, longitude: c.longitude })
      const body = data as { success?: boolean; restaurants?: unknown } | null
      if (error) return fail(error)
      if (!body || body.success === false || !Array.isArray(body.restaurants)) return { status: 'error', kind: 'unavailable', message: 'unexpected response', calls }
      const hit = findExact(body.restaurants, placeId)
      if (hit) return verified(hit, c.via)
    } catch (e) { return fail(e) }
  }

  // 2. the admin search (pages, categories, small circles). Only when it is deployed; it is limited to a university's own circle
  if (s.adminSearch) {
    const groups: Group[] = ['FD6', 'CE7']
    const plans: { campus: CampusCtx; lat: number; lng: number; radiusM: number; query?: string; via: 'admin_name' | 'nearby' }[] = []
    for (const c of campuses) plans.push({ campus: c, lat: c.latitude, lng: c.longitude, radiusM: c.radiusM, query: input.name.trim() || undefined, via: 'admin_name' })
    if (near) for (const c of campuses) if (inside(c, near.latitude, near.longitude)) { plans.push({ campus: c, lat: near.latitude, lng: near.longitude, radiusM: NEARBY_RADIUS_M, via: 'nearby' }); break }
    for (const p of plans) {
      if (!p.query && p.via === 'admin_name') continue
      for (const group of groups) {
        let page = 1
        while (page <= MAX_PAGES) {
          if (calls >= MAX_CALLS || signal.aborted) return { status: 'not_found', calls, adminSearch: adminState }
          calls++
          const out: CellOutcome = await s.adminSearch({ campusId: p.campus.id, lat: p.lat, lng: p.lng, radiusM: p.radiusM, group, query: p.query, page }, signal)
          if (!out.ok) {
            if (out.kind === 'not_deployed' || out.kind === 'forbidden') { adminState = 'unavailable'; break }
            if (out.kind === 'rejected') break // this circle is not allowed (outside the university): try the next plan
            if (out.kind === 'aborted') return { status: 'not_found', calls, adminSearch: adminState }
            return { status: 'error', kind: out.kind === 'rate_limited' || out.kind === 'timeout' || out.kind === 'network' ? out.kind : 'unavailable', message: redact(out.message), calls }
          }
          adminState = 'used'
          const hit = findExact(out.docs, placeId)
          if (hit) return verified(hit, p.via)
          if (!out.nextPage) break
          page = out.nextPage
        }
        if (adminState === 'unavailable') break
      }
      if (adminState === 'unavailable') break
    }
  }
  return { status: 'not_found', calls, adminSearch: adminState }
}

/** Runs at most [max] tasks at once. Shared by every lookup on the page, so a long list cannot flood Kakao. */
export function createLimiter(max: number) {
  let running = 0
  const queue: (() => void)[] = []
  const next = () => { running--; queue.shift()?.() }
  return <T,>(task: () => Promise<T>): Promise<T> =>
    new Promise<T>((resolve, reject) => {
      const start = () => { running++; task().then(resolve, reject).finally(next) }
      if (running < max) start(); else queue.push(start)
    })
}
