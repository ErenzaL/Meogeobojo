import { cmsPublish, cmsSaveDraft, cmsState, type MenuItem } from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import { chunk } from '../restaurants/kakao'
import { sortItems } from './menu'
import type { ExportRestaurant, ExportSource } from './menuExport'
import type { MenuState, RestaurantRef, SaveDeps, PublishDeps } from './menuImport'

const TYPE = 'restaurant_menus' as const
const clean = (s: string) => s.replace(/[%,()*\\]/g, ' ').trim()

/** Restaurants by Kakao place id (exact). Ids that are not managed are simply absent from the result. */
export async function fetchRestaurantsByPlaceIds(placeIds: string[]): Promise<Map<string, RestaurantRef>> {
  const out = new Map<string, RestaurantRef>()
  for (const part of chunk([...new Set(placeIds)], 200)) {
    const { data, error } = await supabase.from('restaurant_overrides').select('id,name_ko,kakao_place_id').in('kakao_place_id', part)
    if (error) throw error
    for (const r of data as RestaurantRef[]) if (r.kakao_place_id) out.set(r.kakao_place_id, r)
  }
  return out
}

export async function fetchRestaurantById(id: string): Promise<RestaurantRef | null> {
  const { data, error } = await supabase.from('restaurant_overrides').select('id,name_ko,kakao_place_id').eq('id', id).maybeSingle()
  if (error) throw error
  return (data as RestaurantRef | null) ?? null
}

/** What the menu editor shows for a restaurant: its draft if it has one, else the live list (the database's own snapshot). */
export async function fetchMenuState(id: string): Promise<MenuState> {
  const s = await cmsState(TYPE, id)
  const base = s.draft?.data ?? s.live
  return { items: sortItems((base.items as MenuItem[] | undefined) ?? []), revision: s.draft?.revision ?? 0, hasDraft: !!s.draft }
}

/** Which restaurant each of these (live) menu ids belongs to, so an id of another restaurant can be refused with a clear message. */
export async function fetchMenuOwners(menuIds: string[]): Promise<Map<string, string>> {
  const out = new Map<string, string>()
  for (const part of chunk([...new Set(menuIds)], 200)) {
    const { data, error } = await supabase.from('restaurant_menus').select('id,restaurant_id').in('id', part)
    if (error) throw error
    for (const m of data as { id: string; restaurant_id: string | null }[]) if (m.restaurant_id) out.set(m.id, m.restaurant_id)
  }
  return out
}

/** The existing admin functions, as the dependencies of the import: read the state, save a draft, publish a draft. */
export const saveDeps: SaveDeps = {
  getState: fetchMenuState,
  saveDraft: async (id, items, expected) => { const r = await cmsSaveDraft(TYPE, id, { items }, expected); return { revision: r.revision } },
}
export const publishDeps: PublishDeps = { publish: (id, rev, reason) => cmsPublish(TYPE, id, rev, reason) }

// ---- export --------------------------------------------------------------------------------------------------------
export type ExportScopeArg = { restaurantId: string } | { search: string } | { universityId: string } | 'all'

export async function fetchExportRestaurants(scope: ExportScopeArg): Promise<ExportRestaurant[]> {
  const out: ExportRestaurant[] = []
  for (let from = 0; from < 5000; from += 1000) {
    const bySchool = scope !== 'all' && 'universityId' in scope
    let q = supabase.from('restaurant_overrides').select(bySchool ? 'id,kakao_place_id,name_ko,restaurant_university_links!inner(university_id)' : 'id,kakao_place_id,name_ko')
    if (scope !== 'all' && 'restaurantId' in scope) q = q.eq('id', scope.restaurantId)
    else if (scope !== 'all' && 'universityId' in scope) q = q.eq('restaurant_university_links.university_id', scope.universityId)
    else if (scope !== 'all' && 'search' in scope && scope.search.trim()) q = q.ilike('name_ko', `%${clean(scope.search)}%`)
    const { data, error } = await q.order('name_ko').range(from, from + 999)
    if (error) throw error
    out.push(...(data as unknown as ExportRestaurant[]))
    if (data.length < 1000) break
  }
  return out
}

/** Menu lines per restaurant: the draft (if any) or the live rows ('editing'), or the live rows only ('published'). */
export async function fetchExportItems(restaurantIds: string[], source: ExportSource): Promise<Map<string, MenuItem[]>> {
  const live = new Map<string, MenuItem[]>()
  const drafts = new Map<string, MenuItem[]>()
  for (const part of chunk(restaurantIds, 200)) {
    const m = await supabase.from('restaurant_menus').select('id,restaurant_id,name_ko,description_ko,price_krw,category,price_verified_on,available,representative,recommended,status,sort_order,image_url').in('restaurant_id', part)
    if (m.error) throw m.error
    for (const r of m.data as (MenuItem & { restaurant_id: string })[]) live.set(r.restaurant_id, [...(live.get(r.restaurant_id) ?? []), r])
    if (source === 'editing') {
      const d = await supabase.from('content_drafts').select('entity_id,data').eq('entity_type', TYPE).in('entity_id', part)
      if (d.error) throw d.error
      for (const r of d.data as { entity_id: string; data: { items?: MenuItem[] } }[]) drafts.set(r.entity_id, r.data.items ?? [])
    }
  }
  return new Map(restaurantIds.map((id) => [id, drafts.get(id) ?? live.get(id) ?? []]))
}
