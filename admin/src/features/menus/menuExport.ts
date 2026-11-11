import type { MenuItem } from '@/lib/cms'
import { sortItems } from './menu'

export type ExportRestaurant = { id: string; kakao_place_id: string | null; name_ko: string }
export type ExportSource = 'editing' | 'published'

/**
 * The CSV rows of a set of restaurants. A restaurant's [items] are what the editor shows (its draft if it has one) or the
 * published list, decided by the caller. Prices are kept exactly (null stays an empty cell), the menu id and status are
 * included so the file can be imported again to update the same lines, and archived lines are left out unless asked for.
 */
export function exportRows(restaurants: ExportRestaurant[], itemsByRestaurant: Map<string, MenuItem[]>, includeArchived: boolean) {
  const out: Record<string, string | number | boolean | null>[] = []
  for (const r of restaurants) {
    for (const i of sortItems(itemsByRestaurant.get(r.id) ?? [])) {
      if (i.status === 'archived' && !includeArchived) continue
      out.push({
        kakao_place_id: r.kakao_place_id ?? '', restaurant_name: r.name_ko, menu_name: i.name_ko, price_krw: i.price_krw, menu_category: i.category ?? '',
        description: i.description_ko ?? '', is_available: i.available, menu_id: i.id, menu_status: i.status,
      })
    }
  }
  return out
}
