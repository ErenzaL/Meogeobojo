import { supabase } from '@/lib/supabase'
import { readAll } from '../restaurants/picker/pickerData'
import { toPickerRestaurant, type PickerRestaurant, type RawPickerRow } from '../restaurants/picker/pickerLogic'

/** A restaurant of the picker, with the Kakao place id its reviews are stored under (null: a hand-made place has none). */
export type ReviewRestaurant = PickerRestaurant & { kakaoPlaceId: string | null }

/** Every managed restaurant (the same rows as the 식당 page, as in the 메뉴·사진 pages) plus its Kakao place id. */
export async function fetchReviewRestaurants(): Promise<ReviewRestaurant[]> {
  const rows = await readAll<RawPickerRow & { kakao_place_id?: string | null }>((from, to) => supabase.from('restaurant_overrides')
    .select('id,name_ko,category,visibility,kakao_place_id,restaurant_university_links(university_id)').order('name_ko').order('id').range(from, to), 20000)
  return rows.map((r) => ({ ...toPickerRestaurant(r), kakaoPlaceId: r.kakao_place_id ?? null }))
}

/** How many reviews each Kakao place has (every review: students' and imported, whatever its state). */
export async function fetchReviewCounts(): Promise<Map<string, number>> {
  const rows = await readAll<{ kakao_place_id: string | null }>((from, to) => supabase.from('student_reviews')
    .select('kakao_place_id').order('id').range(from, to), 200000)
  const out = new Map<string, number>()
  for (const r of rows) if (r.kakao_place_id) out.set(r.kakao_place_id, (out.get(r.kakao_place_id) ?? 0) + 1)
  return out
}
