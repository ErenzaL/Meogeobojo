import type { Visibility } from '../schema'

/**
 * The restaurant list of the 메뉴·가격 and 사진 관리 pages: EVERY managed restaurant (the same rows as the 식당 page), organised by school.
 * Pure functions only; the page fetches the rows and this decides what is listed and how it is grouped.
 *
 *  - A restaurant that belongs to several schools is listed under each of them (it is one restaurant: selecting it from any
 *    group opens the same restaurant).
 *  - A restaurant with no school link is listed under "대학교 미지정" instead of disappearing.
 *  - "Has content" (a menu, a photo) comes from the live rows: something that only exists in a draft does not count.
 *    The page passes the per-restaurant counts, so this module does not care what is being counted.
 */
export const NO_UNIVERSITY = '__none'
export const UNASSIGNED_LABEL = '대학교 미지정'

export type PickerRestaurant = { id: string; name_ko: string; category: string | null; visibility: Visibility | null; universityIds: string[] }
export type PickerUniversity = { id: string; name_ko: string }
export type CountFilter = '' | 'none' | 'has'
export type PickerFilters = { search: string; university: string; has: CountFilter }
export type PickerGroup = { key: string; name: string; restaurants: PickerRestaurant[]; withMenu: number }
export type PickerView = { groups: PickerGroup[]; ids: string[]; total: number; withMenu: number; withoutMenu: number }

/** A row as the database returns it (the school links are an embedded list); every field may be missing. */
export type RawPickerRow = {
  id: string; name_ko?: string | null; category?: string | null; visibility?: string | null
  restaurant_university_links?: { university_id?: string | null }[] | null
}
const VIS = ['draft', 'published', 'hidden', 'archived']

export function toPickerRestaurant(r: RawPickerRow): PickerRestaurant {
  const ids = (r.restaurant_university_links ?? []).map((l) => l.university_id).filter((x): x is string => !!x)
  return {
    id: r.id, name_ko: r.name_ko ?? '', category: r.category ?? null,
    visibility: r.visibility && VIS.includes(r.visibility) ? (r.visibility as Visibility) : null,
    universityIds: [...new Set(ids)],
  }
}

const byName = (a: { name_ko: string }, b: { name_ko: string }) => a.name_ko.localeCompare(b.name_ko, 'ko')

/** The schools a restaurant is really linked to (a link to a school that is not in the list counts for nothing). */
const knownSchools = (r: PickerRestaurant, schools: Set<string>) => r.universityIds.filter((id) => schools.has(id))

/** How many restaurants each school has (unfiltered), and how many have none: the numbers in the school dropdown. */
export function universityCounts(restaurants: PickerRestaurant[], universities: PickerUniversity[]) {
  const schools = new Set(universities.map((u) => u.id))
  const byUniversity = new Map<string, number>(universities.map((u) => [u.id, 0]))
  let unassigned = 0
  for (const r of restaurants) {
    const own = knownSchools(r, schools)
    if (own.length === 0) unassigned++
    for (const id of own) byUniversity.set(id, (byUniversity.get(id) ?? 0) + 1)
  }
  return { byUniversity, unassigned }
}

export function buildView(restaurants: PickerRestaurant[], universities: PickerUniversity[], menuCounts: Map<string, number>, f: PickerFilters): PickerView {
  const needle = f.search.trim().toLowerCase()
  const schools = new Set(universities.map((u) => u.id))
  const hasMenu = (r: PickerRestaurant) => (menuCounts.get(r.id) ?? 0) > 0

  const listed = restaurants.filter((r) => {
    if (needle && !`${r.name_ko} ${r.category ?? ''}`.toLowerCase().includes(needle)) return false
    if (f.has === 'has' && !hasMenu(r)) return false
    if (f.has === 'none' && hasMenu(r)) return false
    const own = knownSchools(r, schools)
    if (f.university === NO_UNIVERSITY) return own.length === 0
    if (f.university) return own.includes(f.university)
    return true
  })

  const groups: PickerGroup[] = []
  const place = (key: string, name: string, rows: PickerRestaurant[]) => {
    if (rows.length === 0) return
    const sorted = [...rows].sort(byName)
    groups.push({ key, name, restaurants: sorted, withMenu: sorted.filter(hasMenu).length })
  }
  for (const u of [...universities].sort(byName)) {
    if (f.university && f.university !== u.id) continue
    place(u.id, u.name_ko, listed.filter((r) => knownSchools(r, schools).includes(u.id)))
  }
  if (!f.university || f.university === NO_UNIVERSITY) place(NO_UNIVERSITY, UNASSIGNED_LABEL, listed.filter((r) => knownSchools(r, schools).length === 0))

  const withMenu = listed.filter(hasMenu).length
  return { groups, ids: listed.map((r) => r.id), total: listed.length, withMenu, withoutMenu: listed.length - withMenu }
}
