import { describe, expect, it } from 'vitest'
import type { PhotoItem, Snapshot } from '@/lib/cms'
import FIXTURE from './__fixtures__/restaurants_168.csv?raw'
import { parseRestaurantCsv } from './csv'
import { applyImportPlan, buildImportPlan, normalizePlaceId, ownImage, reportColumns, type Existing, type ImportDeps, type ImportMode } from './restaurantImport'

const HOST = 'jnnofemlolwdyonfhzje.supabase.co'
const IMG = (n: string) => `https://${HOST}/storage/v1/object/public/restaurant-images/restaurants/r/${n}.png`
const HEAD = 'kakao_place_id,name_ko,name_en,category,address,phone,latitude,longitude,description,image_url,visibility'
const csv = (...lines: string[]) => [HEAD, ...lines].join('\n')

type Rec = { id: string; kakao: string; name: string; visibility: string; fields: Snapshot; revision: number; hasDraft: boolean; photos: PhotoItem[]; photoRev: number; legacyCover: string | null }
const photo = (id: string, path: string, over: Partial<PhotoItem> = {}): PhotoItem => ({ id, kind: 'cover', storage_path: path, url: `https://${HOST}/storage/v1/object/public/restaurant-images/${path}`, caption: null, sort_order: 0, status: 'published', source: 'admin', credit: null, width: null, height: null, bytes: null, ...over })

/** A tiny in-memory stand-in for the database + publishing functions. */
function world(recs: Rec[], opts: { imageCheck?: (u: string) => 'ok' | 'bad' | 'unknown'; failSave?: (id: string) => unknown } = {}) {
  const log = { restaurantDrafts: [] as { id: string; snapshot: Snapshot; rev: number }[], photoDrafts: [] as { id: string; photos: PhotoItem[]; rev: number }[], inserts: [] as Record<string, unknown>[], publishes: 0 }
  const byKakao = () => new Map(recs.map((r) => [r.kakao, r]))
  const toExisting = (r: Rec): Existing => ({
    id: r.id, kakaoPlaceId: r.kakao, visibility: r.visibility, name: r.name, base: { ...r.fields }, hasDraft: r.hasDraft, revision: r.revision,
    photos: { items: r.photos.map((p) => ({ ...p })), revision: r.photoRev, hasDraft: r.photoRev > 0, coverUrlOnRestaurant: r.legacyCover },
  })
  const existing = () => new Map(recs.map((r) => [r.kakao, toExisting(r)]))
  let seq = 0
  const deps: ImportDeps = {
    insertRestaurants: async (rows) => {
      log.inserts.push(...rows)
      const out: { id: string; kakao_place_id: string }[] = []
      for (const row of rows) {
        const k = String(row.kakao_place_id)
        if (byKakao().has(k)) continue // ON CONFLICT DO NOTHING
        const id = `new-${++seq}`
        recs.push({ id, kakao: k, name: String(row.name_ko), visibility: String(row.visibility), fields: { name_ko: row.name_ko, name_en: row.name_en, category: row.category, address: row.address, phone: row.phone, latitude: row.latitude, longitude: row.longitude, description: row.description }, revision: 0, hasDraft: false, photos: [], photoRev: 0, legacyCover: null })
        out.push({ id, kakao_place_id: k })
      }
      return out
    },
    getExisting: async (k) => { const r = byKakao().get(k); return r ? toExisting(r) : null },
    saveRestaurantDraft: async (id, snapshot, rev) => {
      const r = recs.find((x) => x.id === id)!
      const fail = opts.failSave?.(id); if (fail) throw fail
      if (rev !== r.revision) throw Object.assign(new Error('다른 관리자가 먼저 저장했어요'), { code: '40001' })
      log.restaurantDrafts.push({ id, snapshot, rev }); r.fields = snapshot; r.revision++; r.hasDraft = true
    },
    savePhotoDraft: async (id, photos, rev) => {
      const r = recs.find((x) => x.id === id)!
      if (rev !== r.photoRev) throw Object.assign(new Error('다른 관리자가 먼저 저장했어요'), { code: '40001' })
      log.photoDrafts.push({ id, photos, rev }); r.photos = photos; r.photoRev++
    },
    checkImage: async (u) => (opts.imageCheck ?? (() => 'ok'))(u),
    newId: (() => { let n = 0; return () => `photo-${++n}` })(),
    sleep: async () => {},
  }
  return { deps, log, existing, recs }
}
const rec = (kakao: string, name: string, over: Partial<Rec> & { fields?: Snapshot } = {}): Rec => ({
  id: `id-${kakao}`, kakao, name, visibility: 'published', revision: 0, hasDraft: false, photos: [], photoRev: 0, legacyCover: null,
  ...over, fields: { name_ko: name, name_en: null, category: null, address: null, phone: null, latitude: null, longitude: null, description: null, ...(over.fields ?? {}) },
})
const plan = (text: string, existing: Map<string, Existing>, mode: ImportMode = 'fill') => buildImportPlan(parseRestaurantCsv(text), existing, { mode, ownHost: HOST })
const run = (p: ReturnType<typeof plan>, w: ReturnType<typeof world>, mode: ImportMode = 'fill') => applyImportPlan(p, { mode, ownHost: HOST }, w.deps)

describe('the uploaded 168-row file', () => {
  const rows = parseRestaurantCsv(FIXTURE)
  it('parses: 168 rows, all valid, every id a usable Kakao place id', () => {
    expect(rows).toHaveLength(168)
    expect(rows.filter((r) => !r.values).length).toBe(0)
    expect(rows.every((r) => normalizePlaceId(r.values!.kakao_place_id).id)).toBe(true)
    expect(new Set(rows.map((r) => r.values!.kakao_place_id)).size).toBe(168)
    expect(rows.filter((r) => r.values!.image_url).length).toBe(123)
  })
  it('reports its columns: current ones are read, visibility is read-but-not-applied, 7 old ones are listed with the reason', () => {
    const c = reportColumns(FIXTURE)
    expect(c.used).toEqual(['kakao_place_id', 'name_ko', 'name_en', 'category', 'address', 'phone', 'latitude', 'longitude', 'description', 'image_url'])
    expect(c.notApplied.map((x) => x.column)).toEqual(['visibility'])
    expect(c.legacy.map((x) => x.column).sort()).toEqual(['avg_cost_krw', 'break_time', 'business_status', 'dining_purposes', 'last_order_time', 'price_max_krw', 'price_min_krw'])
    expect(c.legacy.find((x) => x.column === 'price_min_krw')!.reason).toMatch(/메뉴별 가격이 아니라/)
    expect(c.unknown).toEqual([])
  })
  it('into an empty database: 168 new restaurants, all DRAFTS, photos added only from our own bucket, no price columns stored', async () => {
    const w = world([])
    const p = plan(FIXTURE, w.existing())
    expect(p.counts).toMatchObject({ rows: 168, created: 168, matched: 0, invalid: 0, review: 0, duplicate: 0 })
    const res = await run(p, w)
    expect(res.counts).toEqual({ created: 168, updated: 0, unchanged: 0, skipped: 0, failed: 0 })
    expect(w.recs).toHaveLength(168)
    expect(w.log.inserts.every((r) => r.visibility === 'draft' && r.featured === false && r.image_url === null)).toBe(true) // the CSV's published/draft is never applied
    expect(w.log.inserts.every((r) => r.price_min_krw === null && r.price_max_krw === null && r.avg_cost_krw === null)).toBe(true)
    expect(w.log.photoDrafts).toHaveLength(123)
    expect(w.log.photoDrafts.every((d) => d.photos.length === 1 && d.photos[0].kind === 'cover' && d.photos[0].status === 'published')).toBe(true)
    expect(w.log.publishes).toBe(0)
  })
  it('running the SAME file again changes nothing: no duplicates, no new drafts', async () => {
    const w = world([])
    await run(plan(FIXTURE, w.existing()), w)
    const before = JSON.stringify(w.recs)
    const second = plan(FIXTURE, w.existing())
    expect(second.counts).toMatchObject({ created: 0, matched: 168, withUpdates: 0, unchanged: 168 })
    const res = await run(second, w)
    expect(res.counts).toEqual({ created: 0, updated: 0, unchanged: 168, skipped: 0, failed: 0 })
    expect(w.recs).toHaveLength(168)
    expect(JSON.stringify(w.recs)).toBe(before)
  })
  it('against a database that already has all 168 (with their photos): the ONLY thing to fill is the one row that carries a category, address and coordinates', () => {
    const recsAll = rows.map((r) => {
      const v = r.values!
      const path = v.image_url ? v.image_url.split('/restaurant-images/')[1] : null
      return rec(v.kakao_place_id, v.name_ko, { visibility: v.visibility, photos: path ? [photo(`p-${v.kakao_place_id}`, path)] : [] })
    })
    const p = plan(FIXTURE, world(recsAll).existing())
    expect(p.counts).toMatchObject({ matched: 168, created: 0, unchanged: 167, withUpdates: 1, invalid: 0, review: 0 })
    const one = p.rows.find((r) => r.kind === 'update')!
    expect(one.name).toBe('대학자장 (학생회관)')
    expect(one.changes.map((c) => c.field).sort()).toEqual(['address', 'category', 'coords'])
    expect(one.image.action).toBe('none')
    expect(p.rows.filter((r) => r.kind !== 'update').every((r) => r.kind === 'unchanged')).toBe(true) // nobody is rejected as a duplicate
  })
})

describe('fill mode (default): only empty fields, never erases, never overwrites', () => {
  const existing = () => [rec('1', '국수집', { fields: { category: '음식점 > 한식', description: '내가 쓴 설명' } })]
  it('fills a missing category/address/coordinates/description and the main photo; keeps what is stored; a blank cell erases nothing', async () => {
    const w = world(existing())
    const p = plan(csv(`1,국수집,,음식점 > 중식,충남 아산시 1,,36.77,126.93,CSV 설명,${IMG('a')},published`), w.existing())
    expect(p.rows[0].kind).toBe('update')
    expect(p.rows[0].changes.map((c) => c.field).sort()).toEqual(['address', 'coords'])
    expect(p.rows[0].image).toMatchObject({ action: 'add' })
    const res = await run(p, w)
    expect(res.counts).toMatchObject({ updated: 1, failed: 0 })
    const snap = w.log.restaurantDrafts[0].snapshot
    expect(snap).toMatchObject({ category: '음식점 > 한식', description: '내가 쓴 설명', address: '충남 아산시 1', latitude: 36.77, longitude: 126.93 })
    expect(snap.name_en).toBeNull() // the CSV's empty cell did not write anything
    expect(w.recs[0].photos).toHaveLength(1)
    expect(w.recs[0].photos[0]).toMatchObject({ kind: 'cover', storage_path: 'restaurants/r/a.png' })
  })
  it('keeps the restaurant id, its visibility and everything not in the file', async () => {
    const w = world([rec('1', '국수집', { id: 'KEEP-ID', visibility: 'published', fields: { featured: true, display_order: 3, visibility: 'published', university_ids: ['u1'] } })])
    await run(plan(csv(`1,국수집,,,주소,,,,,,draft`), w.existing()), w) // the CSV says "draft": ignored
    expect(w.recs[0].id).toBe('KEEP-ID')
    expect(w.recs[0].visibility).toBe('published')
    expect(w.log.restaurantDrafts[0].snapshot).toMatchObject({ visibility: 'published', featured: true, display_order: 3, university_ids: ['u1'] })
  })
  it('does not replace an existing main photo, and does not add the same file twice (even an archived or draft one)', async () => {
    const w = world([rec('1', 'A', { photos: [photo('p1', 'restaurants/r/old.png')] }), rec('2', 'B', { photos: [photo('p2', 'restaurants/r/b.png', { status: 'archived' })] }), rec('3', 'C', { legacyCover: IMG('legacy') })])
    const p = plan(csv(`1,A,,,,,,,,${IMG('new')},`, `2,B,,,,,,,,${IMG('b')},`, `3,C,,,,,,,,${IMG('x')},`), w.existing())
    expect(p.rows.map((r) => r.image.action)).toEqual(['keep', 'same', 'keep'])
    expect(p.counts.withUpdates).toBe(0)
    await run(p, w)
    expect(w.log.photoDrafts).toHaveLength(0)
  })
  it('never imports a Kakao or other outside picture', async () => {
    const w = world([rec('1', 'A'), rec('2', 'B')])
    const p = plan(csv('1,A,,,,,,,,https://t1.kakaocdn.net/x.jpg,', '2,B,,,,,,,,https://example.com/x.png,'), w.existing())
    expect(p.rows.map((r) => r.image.action)).toEqual(['skip', 'skip'])
    expect((p.rows[0].image as { reason: string }).reason).toMatch(/카카오/)
    expect(p.counts.withUpdates).toBe(0)
  })
  it('a picture that cannot be reached is skipped and reported, while the restaurant\'s other updates are still saved', async () => {
    const w = world([rec('1', 'A')], { imageCheck: () => 'bad' })
    const res = await run(plan(csv(`1,A,,음식점 > 한식,,,,,,${IMG('gone')},`), w.existing()), w)
    expect(res.counts.updated).toBe(1)
    expect(res.outcomes[0].message).toMatch(/카테고리 초안을 저장했어요/)
    expect(res.outcomes[0].message).toMatch(/사진은 가져오지 않았어요/)
    expect(w.recs[0].photos).toHaveLength(0)
    expect(w.recs[0].fields.category).toBe('음식점 > 한식')
  })
})

describe('update mode: non-empty CSV values replace stored ones, with a preview of the change', () => {
  it('shows from -> to for every changed field; empty cells still erase nothing; the name is a proposed change', async () => {
    const w = world([rec('1', '옛 이름', { fields: { category: '음식점 > 한식', address: '옛 주소', phone: '041-1' } })])
    const p = plan(csv(`1,새 이름,,음식점 > 중식,,041-1,,,,,`), w.existing(), 'update')
    expect(p.rows[0].changes.map((c) => [c.field, c.from, c.to])).toEqual([['name_ko', '옛 이름', '새 이름'], ['category', '음식점 > 한식', '음식점 > 중식']])
    expect(p.counts.conflicts).toBe(1) // the stored and the file name differ
    await run(p, w, 'update')
    expect(w.recs[0].fields).toMatchObject({ name_ko: '새 이름', category: '음식점 > 중식', address: '옛 주소', phone: '041-1' })
    expect(w.recs[0].id).toBe('id-1')
    expect(w.recs[0].visibility).toBe('published')
  })
  it('a different photo becomes the main one; the old photo is kept (archived), never deleted', async () => {
    const w = world([rec('1', 'A', { photos: [photo('p1', 'restaurants/r/old.png')] })])
    await run(plan(csv(`1,A,,,,,,,,${IMG('new')},`), w.existing(), 'update'), w, 'update')
    const photos = w.recs[0].photos
    expect(photos).toHaveLength(2)
    expect(photos.find((p) => p.id === 'p1')).toMatchObject({ status: 'archived', storage_path: 'restaurants/r/old.png' })
    expect(photos.find((p) => p.id !== 'p1')).toMatchObject({ kind: 'cover', status: 'published', storage_path: 'restaurants/r/new.png' })
  })
  it('compares against a pending draft, not only the live record, so it does not undo what is waiting to be published', () => {
    const r = rec('1', 'A', { hasDraft: true, revision: 4, fields: { address: '초안 주소' } })
    const p = plan(csv(`1,A,,,초안 주소,,,,,,`), world([r]).existing(), 'update')
    expect(p.rows[0].kind).toBe('unchanged')
  })
})

describe('new restaurants only', () => {
  it('skips existing ones without an error and adds the rest as drafts', async () => {
    const w = world([rec('1', '있는 식당')])
    const p = plan(csv('1,있는 식당,,,,,,,,,', '2,새 식당,,음식점 > 한식,,,,,,,published'), w.existing(), 'new_only')
    expect(p.counts).toMatchObject({ skippedExisting: 1, created: 1, invalid: 0 })
    const res = await run(p, w, 'new_only')
    expect(res.counts).toMatchObject({ created: 1, skipped: 1, failed: 0 })
    expect(w.recs.find((r) => r.kakao === '2')!.visibility).toBe('draft') // never published by an import
  })
})

describe('matching and review', () => {
  it('matches by Kakao id only: two restaurants with the same name stay two restaurants', () => {
    const w = world([rec('1', '국수집')])
    const p = plan(csv('1,국수집,,,,,,,,,', '2,국수집,,,,,,,,,'), w.existing())
    expect(p.rows.map((r) => r.kind)).toEqual(['unchanged', 'create'])
    expect(p.rows.every((r) => r.notes.some((n) => n.includes('같은 이름의 다른 장소 ID')))).toBe(true)
  })
  it('a row without a usable Kakao id is set aside for review (never matched by name); a repeated id is flagged', () => {
    const p = plan(csv(',이름만,,,,,,,,,', '1.23E+12,지수,,,,,,,,,', 'abc,글자,,,,,,,,,', '5,A,,,,,,,,,', '5,B,,,,,,,,,'), new Map())
    expect(p.rows.map((r) => r.kind)).toEqual(['review', 'review', 'review', 'create', 'duplicate'])
    expect(p.rows[1].notes[0]).toMatch(/지수 형식/)
    expect(p.counts).toMatchObject({ review: 3, duplicate: 1, created: 1 })
  })
  it('invalid rows (no name, bad coordinates) are errors with the reason, and nothing from them is applied', async () => {
    const w = world([])
    const p = plan(csv('7,,,,,,,,,,', '8,A,,,,,99,200,,,'), w.existing())
    expect(p.counts.invalid).toBe(2)
    const res = await run(p, w)
    expect(res.counts).toMatchObject({ failed: 2, created: 0 })
    expect(w.recs).toHaveLength(0)
  })
  it('the helper types: ownImage accepts only our bucket', () => {
    expect(ownImage(IMG('a'), HOST)).toEqual({ path: 'restaurants/r/a.png' })
    expect('reason' in ownImage(`https://other.supabase.co/storage/v1/object/public/restaurant-images/x.png`, HOST)).toBe(true)
  })
})

describe('applying safely', () => {
  it('plans again against what is there NOW: a value another admin filled after the preview is not overwritten', async () => {
    const w = world([rec('1', 'A')])
    const p = plan(csv(`1,A,,음식점 > 한식,,,,,,,`), w.existing())
    expect(p.rows[0].changes[0].field).toBe('category')
    w.recs[0].fields.category = '음식점 > 일식' // someone filled it after the preview
    const res = await run(p, w)
    expect(res.counts).toMatchObject({ unchanged: 1, updated: 0 })
    expect(w.recs[0].fields.category).toBe('음식점 > 일식')
  })
  it('a conflict (another admin saved a draft first) is retried against the newest draft', async () => {
    const w = world([rec('1', 'A')])
    const p = plan(csv(`1,A,,,주소,,,,,,`), w.existing())
    const original = w.deps.getExisting
    let first = true
    w.deps.getExisting = async (k) => { const e = await original(k); if (first && e) { first = false; w.recs[0].revision = 7 } return e } // the draft moves on after our read
    const res = await run(p, w)
    expect(res.counts.updated).toBe(1)
    expect(w.recs[0].fields.address).toBe('주소')
  })
  it('a place registered meanwhile is skipped, never duplicated', async () => {
    const w = world([])
    const p = plan(csv('9,새 식당,,,,,,,,,'), w.existing())
    w.recs.push(rec('9', '다른 곳에서 먼저 등록')) // after the preview
    const res = await run(p, w)
    expect(res.counts).toMatchObject({ skipped: 1, created: 0 })
    expect(w.recs).toHaveLength(1)
  })
  it('a permission error stops the run and is reported', async () => {
    const w = world([rec('1', 'A'), rec('2', 'B')], { failSave: () => Object.assign(new Error('permission denied'), { code: '42501' }) })
    const res = await run(plan(csv('1,A,,,x,,,,,,', '2,B,,,y,,,,,,'), w.existing()), w)
    expect(res.stoppedBy).toBe('forbidden')
    expect(res.counts.failed).toBeGreaterThanOrEqual(1)
    expect(w.recs.every((r) => !r.hasDraft)).toBe(true)
  })
  it('one failing restaurant does not undo the others', async () => {
    const w = world([rec('1', 'A'), rec('2', 'B')], { failSave: (id) => (id === 'id-1' ? Object.assign(new Error('boom'), { code: 'XX000' }) : null) })
    const res = await run(plan(csv('1,A,,,x,,,,,,', '2,B,,,y,,,,,,'), w.existing()), w)
    expect(res.counts).toMatchObject({ failed: 1, updated: 1 })
    expect(w.recs[1].fields.address).toBe('y')
  })
})
