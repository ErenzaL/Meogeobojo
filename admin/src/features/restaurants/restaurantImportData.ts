import { cmsSaveDraft, cmsState, type PhotoItem, type Snapshot } from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import { chunk } from './kakao'
import type { Existing, ImportDeps } from './restaurantImport'

const LIVE_FIELDS = 'id,kakao_place_id,name_ko,name_en,category,address,phone,latitude,longitude,description,image_url,visibility'
type Live = { id: string; kakao_place_id: string; name_ko: string; name_en: string | null; category: string | null; address: string | null; phone: string | null; latitude: number | null; longitude: number | null; description: string | null; image_url: string | null; visibility: string }
const PHOTO_FIELDS = 'id,restaurant_id,kind,storage_path,url,caption,sort_order,status,source,credit,width,height,bytes'

const snapshotOf = (r: Live): Snapshot => ({ name_ko: r.name_ko, name_en: r.name_en, category: r.category, address: r.address, phone: r.phone, latitude: r.latitude, longitude: r.longitude, description: r.description })

/**
 * What the preview needs, read in a few bulk queries (nothing is written): the restaurants with these Kakao place ids,
 * their pending drafts, and their photos. The apply step re-reads every restaurant through the publishing functions.
 */
export async function fetchExistingForPreview(kakaoIds: string[]): Promise<Map<string, Existing>> {
  const out = new Map<string, Existing>()
  const rows: Live[] = []
  for (const part of chunk([...new Set(kakaoIds)], 200)) {
    const { data, error } = await supabase.from('restaurant_overrides').select(LIVE_FIELDS).in('kakao_place_id', part)
    if (error) throw error
    rows.push(...(data as Live[]))
  }
  const ids = rows.map((r) => r.id)
  const drafts = new Map<string, { data: Snapshot; revision: number }>()
  const photos = new Map<string, PhotoItem[]>()
  for (const part of chunk(ids, 200)) {
    const d = await supabase.from('content_drafts').select('entity_id,entity_type,revision,data').in('entity_type', ['restaurant', 'restaurant_photos']).in('entity_id', part)
    if (d.error) throw d.error
    for (const r of d.data as { entity_id: string; entity_type: string; revision: number; data: Snapshot }[]) drafts.set(`${r.entity_type}:${r.entity_id}`, { data: r.data, revision: r.revision })
    const p = await supabase.from('restaurant_photos').select(PHOTO_FIELDS).in('restaurant_id', part)
    if (p.error) throw p.error
    for (const r of p.data as (PhotoItem & { restaurant_id: string })[]) photos.set(r.restaurant_id, [...(photos.get(r.restaurant_id) ?? []), r])
  }
  for (const r of rows) {
    const rd = drafts.get(`restaurant:${r.id}`)
    const pd = drafts.get(`restaurant_photos:${r.id}`)
    out.set(r.kakao_place_id, {
      id: r.id, kakaoPlaceId: r.kakao_place_id, visibility: r.visibility, name: r.name_ko,
      base: { ...snapshotOf(r), ...(rd?.data ?? {}) }, hasDraft: !!rd, revision: rd?.revision ?? 0,
      photos: { items: (pd?.data.photos as PhotoItem[] | undefined) ?? photos.get(r.id) ?? [], revision: pd?.revision ?? 0, hasDraft: !!pd, coverUrlOnRestaurant: r.image_url },
    })
  }
  return out
}

/** One restaurant as the publishing functions see it right now (used when applying, so a stale preview cannot overwrite anything). */
async function getExisting(kakaoPlaceId: string): Promise<Existing | null> {
  const { data, error } = await supabase.from('restaurant_overrides').select(LIVE_FIELDS).eq('kakao_place_id', kakaoPlaceId).maybeSingle()
  if (error) throw error
  const r = data as Live | null
  if (!r) return null
  const [rs, ps] = await Promise.all([cmsState('restaurant', r.id), cmsState('restaurant_photos', r.id)])
  const photos = ((ps.draft?.data ?? ps.live).photos as PhotoItem[] | undefined) ?? []
  return {
    id: r.id, kakaoPlaceId, visibility: r.visibility, name: r.name_ko,
    base: rs.draft?.data ?? rs.live, hasDraft: !!rs.draft, revision: rs.draft?.revision ?? 0,
    photos: { items: photos, revision: ps.draft?.revision ?? 0, hasDraft: !!ps.draft, coverUrlOnRestaurant: r.image_url },
  }
}

/** Is the picture reachable? 'unknown' when the browser cannot tell (network / CORS): that never blocks an import. */
async function checkImage(url: string): Promise<'ok' | 'bad' | 'unknown'> {
  const ctl = new AbortController()
  const timer = setTimeout(() => ctl.abort(), 6000)
  try {
    const res = await fetch(url, { method: 'HEAD', signal: ctl.signal })
    return res.ok ? 'ok' : [400, 401, 403, 404, 410].includes(res.status) ? 'bad' : 'unknown'
  } catch { return 'unknown' } finally { clearTimeout(timer) }
}

export const importDeps: ImportDeps = {
  insertRestaurants: async (rows) => {
    // ON CONFLICT DO NOTHING on the unique Kakao id: a place registered meanwhile (another admin, a repeat click) is left out
    const { data, error } = await supabase.from('restaurant_overrides').upsert(rows, { onConflict: 'kakao_place_id', ignoreDuplicates: true }).select('id,kakao_place_id')
    if (error) throw error
    return (data ?? []) as { id: string; kakao_place_id: string }[]
  },
  getExisting,
  saveRestaurantDraft: async (id, snapshot, rev) => { await cmsSaveDraft('restaurant', id, snapshot, rev) },
  savePhotoDraft: async (id, photos, rev) => { await cmsSaveDraft('restaurant_photos', id, { photos }, rev) },
  checkImage,
}

export const ownSupabaseHost = (): string | null => {
  try { return new URL((import.meta.env as Record<string, string | undefined>).VITE_SUPABASE_URL ?? '').host } catch { return null }
}
