/**
 * What the recommendation actually runs on, per restaurant, as the admin can see it: the stored hours and amenities
 * (`recommendation_demo_features`) next to the published menus that decide the budget. Read-only.
 */
export type FeatureRow = {
  kakao_place_id: string; name_ko: string | null; open_time: string | null; last_order_time: string | null; break_time: string | null
  no_break_time: boolean | null; parking: boolean | null; local_currency: boolean | null; fast_turnover: boolean | null
  takeout: boolean | null; open_late: boolean | null; source: string | null
}
export type RestaurantLite = { id: string; kakao_place_id: string | null; name_ko: string; visibility: string; category?: string | null }
export type MenuLite = { restaurant_id: string; category: string | null; price_krw: number | null; status: string; available: boolean | null }

/** The menu categories that are a full meal for one (식사 / 면류 / 분식). */
export const MEAL_CATEGORIES = ['식사', '면류', '분식']

/**
 * What the app offers as a dish at a place (the same rule as the app's `MenuLine.isOffered`): at a restaurant every
 * category except drinks (음료) and add-on sides (사이드), so a 안주, a 기타 platter or a dessert counts and a drink never
 * sets the price; at a cafe the drinks count too (they are what a cafe sells). A line with no category counts as nothing.
 */
export function isOffered(category: string | null | undefined, cafe: boolean): boolean {
  const c = (category ?? '').trim()
  return c !== '' && c !== '사이드' && (cafe || c !== '음료')
}

/** A cafe: its category says 카페, or drinks are at least 70% of its menu and it is not a bar (주점·호프·포차). */
export function cafeIds(restaurants: RestaurantLite[], menus: MenuLite[]): Set<string> {
  const total = new Map<string, number>(); const drinks = new Map<string, number>()
  for (const m of menus) {
    if (m.status !== 'active') continue
    total.set(m.restaurant_id, (total.get(m.restaurant_id) ?? 0) + 1)
    if ((m.category ?? '').trim() === '음료') drinks.set(m.restaurant_id, (drinks.get(m.restaurant_id) ?? 0) + 1)
  }
  const out = new Set<string>()
  for (const r of restaurants) {
    const n = total.get(r.id) ?? 0
    const cat = r.category ?? ''
    if (cat.includes('카페') || (n > 0 && (drinks.get(r.id) ?? 0) / n >= 0.7 && !/주점|술집|호프|포차|바\(/.test(cat))) out.add(r.id)
  }
  return out
}

/** `offered` = dishes the recommendation can use for a budget (priced, in stock, per [isOffered]); `meals` of them are full meals. */
export type MenuStats = { active: number; categorized: number; offered: number; meals: number; cheapest: number | null; cafe: boolean }
export type InputRow = {
  kakaoPlaceId: string
  name: string
  /** null when the stored row matches no restaurant in the list. */
  visibility: string | null
  features: FeatureRow | null
  menus: MenuStats
}

const empty: MenuStats = { active: 0, categorized: 0, offered: 0, meals: 0, cheapest: null, cafe: false }

export function menuStats(menus: MenuLite[], cafes: Set<string> = new Set()): Map<string, MenuStats> {
  const out = new Map<string, MenuStats>()
  for (const m of menus) {
    if (m.status !== 'active') continue
    const cafe = cafes.has(m.restaurant_id)
    const s = out.get(m.restaurant_id) ?? { ...empty, cafe }
    s.active++
    if ((m.category ?? '').trim() !== '') s.categorized++
    if (m.price_krw != null && m.available !== false) {
      if (MEAL_CATEGORIES.includes(m.category ?? '')) s.meals++
      if (isOffered(m.category, cafe)) {
        s.offered++
        s.cheapest = s.cheapest == null ? m.price_krw : Math.min(s.cheapest, m.price_krw)
      }
    }
    out.set(m.restaurant_id, s)
  }
  return out
}

export function buildInputRows(features: FeatureRow[], restaurants: RestaurantLite[], menus: MenuLite[]): InputRow[] {
  const stats = menuStats(menus, cafeIds(restaurants, menus))
  const byKakao = new Map(features.map((f) => [f.kakao_place_id, f]))
  const rows: InputRow[] = []
  const seen = new Set<string>()
  for (const r of restaurants) {
    const key = r.kakao_place_id ?? `id:${r.id}`
    seen.add(key)
    rows.push({ kakaoPlaceId: r.kakao_place_id ?? '', name: r.name_ko, visibility: r.visibility, features: r.kakao_place_id ? byKakao.get(r.kakao_place_id) ?? null : null, menus: stats.get(r.id) ?? { ...empty } })
  }
  for (const f of features) if (!seen.has(f.kakao_place_id)) rows.push({ kakaoPlaceId: f.kakao_place_id, name: f.name_ko ?? f.kakao_place_id, visibility: null, features: f, menus: { ...empty } })
  return rows.sort((a, b) => a.name.localeCompare(b.name, 'ko'))
}

export type InputSummary = { total: number; published: number; withFeatures: number; withHours: number; withMenus: number; budgetReady: number }
export function summarize(rows: InputRow[]): InputSummary {
  const published = rows.filter((r) => r.visibility === 'published')
  return {
    total: rows.length,
    published: published.length,
    withFeatures: published.filter((r) => r.features).length,
    withHours: published.filter((r) => r.features?.open_time && r.features.last_order_time).length,
    withMenus: published.filter((r) => r.menus.active > 0).length,
    budgetReady: published.filter((r) => r.menus.offered > 0).length,
  }
}

export const yesNo = (v: boolean | null | undefined) => (v === true ? '있음' : v === false ? '없음' : '미확인')
export const hhmm = (t: string | null | undefined) => (t ? t.slice(0, 5) : '')
