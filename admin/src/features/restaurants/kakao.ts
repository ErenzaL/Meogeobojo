import { redact, statusOf } from './kakaoDiag'
import { placeDistanceM } from './kakaoGeo'

/** Kakao Local keyword searches that reproduce what the Flutter app collects. */

/** Same Korean keywords the app sends (lib/features/restaurants/models/food_category.dart). */
export const KAKAO_QUERIES = [
  '음식점', '한식', '양식', '중식', '일식', '분식', '카페', '디저트', '치킨집', '양념치킨', '패스트푸드', '햄버거',
  '아시아음식', '베트남음식', '태국음식', '인도음식', '멕시칸', '튀르키예음식', '간식', '뷔페', '샐러드', '도시락',
] as const

export type KakaoDoc = {
  id: string; place_name: string; category_name?: string; category_group_code?: string; address_name?: string
  road_address_name?: string; phone?: string; x?: string; y?: string; distance?: string; place_url?: string
}
export type Invoke = (body: { query: string; latitude: number; longitude: number }) => PromiseLike<{ data: unknown; error: unknown }>
export type Campus = { latitude: number; longitude: number }

/** Food / cafe places only (the app lists nothing else). */
export const isFoodPlace = (d: KakaoDoc) => d.category_group_code === 'FD6' || d.category_group_code === 'CE7'

/**
 * LEGACY path (used only when the `admin_kakao_search` function is not deployed): runs every keyword around the campus (a few at a time) and merges the
 * results by Kakao place id. A keyword that fails is reported, not fatal.
 * Each search returns at most ~15 places, so this is "the nearest matches",
 * not a complete catalogue of the area.
 */
export async function collectKakaoPlaces(
  campus: Campus, invoke: Invoke, onProgress?: (done: number, total: number) => void,
  queries: readonly string[] = KAKAO_QUERIES, concurrency = 4,
): Promise<{ places: KakaoDoc[]; failed: string[]; lastError?: { status?: number; message: string } }> {
  const byId = new Map<string, KakaoDoc>()
  const failed: string[] = []
  let lastError: { status?: number; message: string } | undefined
  let next = 0; let done = 0
  const worker = async () => {
    while (next < queries.length) {
      const q = queries[next++]
      try {
        const { data, error } = await invoke({ query: q, latitude: campus.latitude, longitude: campus.longitude })
        const body = data as { success?: boolean; restaurants?: unknown } | null
        if (error || !body || body.success === false || !Array.isArray(body.restaurants)) throw error ?? new Error('bad response')
        for (const d of body.restaurants as KakaoDoc[]) if (d && d.id && isFoodPlace(d) && !byId.has(String(d.id))) byId.set(String(d.id), { ...d, id: String(d.id) })
      } catch (e) { failed.push(q); lastError = { status: statusOf(e), message: redact(e instanceof Error ? e.message : typeof e === 'object' && e && 'message' in e ? String((e as { message: unknown }).message) : 'bad response') } }
      onProgress?.(++done, queries.length)
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, queries.length) }, worker))
  const places = [...byId.values()].sort((a, b) => Number(a.distance ?? 1e9) - Number(b.distance ?? 1e9))
  return { places, failed, lastError }
}

/**
 * Keeps only the places inside the campus circle, with their real distance from the campus centre (Kakao's own
 * `distance` is measured from whatever point was searched, which is not the campus for a grid cell).
 */
export function withinRadius(
  places: KakaoDoc[], campus: { latitude: number; longitude: number; radiusM: number },
): { places: (KakaoDoc & { distanceM: number })[]; outside: number } {
  const kept: (KakaoDoc & { distanceM: number })[] = []
  let outside = 0
  for (const d of places) {
    const dist = placeDistanceM(d, { id: '', name: '', ...campus })
    if (dist == null) continue
    if (dist > campus.radiusM) { outside++; continue }
    kept.push({ ...d, distance: String(Math.round(dist)), distanceM: dist })
  }
  kept.sort((a, b) => a.distanceM - b.distanceM)
  return { places: kept, outside }
}

/** Splits [items] into chunks of at most [n]. */
export const chunk = <T,>(items: T[], n: number) => Array.from({ length: Math.ceil(items.length / n) }, (_, i) => items.slice(i * n, i * n + n))
