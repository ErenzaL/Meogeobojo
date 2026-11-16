/**
 * What the recommendation actually runs on, per restaurant, as the admin can see it: the stored hours and amenities
 * (`recommendation_demo_features`) next to the published menus that decide the budget. Read-only.
 */
export type FeatureRow = {
  kakao_place_id: string; name_ko: string | null; open_time: string | null; last_order_time: string | null; break_time: string | null
  no_break_time: boolean | null; parking: boolean | null; local_currency: boolean | null; fast_turnover: boolean | null
  takeout: boolean | null; open_late: boolean | null; source: string | null
}
export type RestaurantLite = { id: string; kakao_place_id: string | null; name_ko: string; visibility: string }
export type MenuLite = { restaurant_id: string; category: string | null; price_krw: number | null; status: string; available: boolean | null }

/** The menu categories the recommendation counts as a full meal for one (식사 / 면류 / 분식). */
export const MEAL_CATEGORIES = ['식사', '면류', '분식']

export type MenuStats = { active: number; categorized: number; meals: number; cheapestMeal: number | null }
export type InputRow = {
  kakaoPlaceId: string
  name: string
  /** null when the stored row matches no restaurant in the list. */
  visibility: string | null
  features: FeatureRow | null
  menus: MenuStats
}

const empty: MenuStats = { active: 0, categorized: 0, meals: 0, cheapestMeal: null }

export function menuStats(menus: MenuLite[]): Map<string, MenuStats> {
  const out = new Map<string, MenuStats>()
  for (const m of menus) {
    if (m.status !== 'active') continue
    const s = out.get(m.restaurant_id) ?? { ...empty }
    s.active++
    if ((m.category ?? '').trim() !== '') s.categorized++
    if (MEAL_CATEGORIES.includes(m.category ?? '') && m.price_krw != null && m.available !== false) {
      s.meals++
      s.cheapestMeal = s.cheapestMeal == null ? m.price_krw : Math.min(s.cheapestMeal, m.price_krw)
    }
    out.set(m.restaurant_id, s)
  }
  return out
}

export function buildInputRows(features: FeatureRow[], restaurants: RestaurantLite[], menus: MenuLite[]): InputRow[] {
  const stats = menuStats(menus)
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
    budgetReady: published.filter((r) => r.menus.meals > 0).length,
  }
}

export const yesNo = (v: boolean | null | undefined) => (v === true ? '있음' : v === false ? '없음' : '미확인')
export const hhmm = (t: string | null | undefined) => (t ? t.slice(0, 5) : '')
