import { supabase } from '@/lib/supabase'
import { toPickerRestaurant, type PickerRestaurant, type RawPickerRow } from './pickerLogic'

const PAGE = 1000

/** Every row of a query, page by page (the API answers at most 1000 rows per request), up to [cap] rows. */
export async function readAll<T>(page: (from: number, to: number) => PromiseLike<{ data: unknown; error: unknown }>, cap: number): Promise<T[]> {
  const out: T[] = []
  for (let from = 0; from < cap; from += PAGE) {
    const { data, error } = await page(from, from + PAGE - 1)
    if (error) throw error
    const rows = (data ?? []) as T[]
    out.push(...rows)
    if (rows.length < PAGE) break
  }
  return out
}

/** All managed restaurants (the same table the 식당 page lists) with the schools they belong to. */
export async function fetchPickerRestaurants(): Promise<PickerRestaurant[]> {
  const rows = await readAll<RawPickerRow>((from, to) => supabase.from('restaurant_overrides')
    .select('id,name_ko,category,visibility,restaurant_university_links(university_id)').order('name_ko').order('id').range(from, to), 20000)
  return rows.map(toPickerRestaurant)
}

function tally(rows: { restaurant_id: string | null }[]) {
  const out = new Map<string, number>()
  for (const r of rows) if (r.restaurant_id) out.set(r.restaurant_id, (out.get(r.restaurant_id) ?? 0) + 1)
  return out
}

/** How many active published menu lines each restaurant has. */
export async function fetchMenuCounts(): Promise<Map<string, number>> {
  return tally(await readAll<{ restaurant_id: string | null }>((from, to) => supabase.from('restaurant_menus')
    .select('restaurant_id').eq('status', 'active').order('id').range(from, to), 100000))
}

/** How many published photos (the cover and the gallery) each restaurant has. */
export async function fetchPhotoCounts(): Promise<Map<string, number>> {
  return tally(await readAll<{ restaurant_id: string | null }>((from, to) => supabase.from('restaurant_photos')
    .select('restaurant_id').eq('status', 'published').order('id').range(from, to), 100000))
}
