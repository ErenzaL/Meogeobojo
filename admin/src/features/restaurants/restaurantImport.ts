import { storagePathFromUrl } from '@/lib/images'
import type { PhotoItem, Snapshot } from '@/lib/cms'
import { CSV_COLUMNS, parseRestaurantCsv, type ParsedRow } from './csv'
import { toRow, type RestaurantForm } from './schema'
import Papa from 'papaparse'

/**
 * Smart restaurant CSV import: an existing restaurant is UPDATED with what the file adds (never rejected as a duplicate),
 * a new one is created, and nothing is guessed.
 *
 *  - Matching is by Kakao place id only (never by name). A row without a valid id is set aside for review.
 *  - Three modes: fill (default: only empty fields, never erases), update (non-empty file values replace stored ones),
 *    new_only (existing restaurants are skipped without an error).
 *  - An empty cell never erases anything. The restaurant's id, its publication state (visibility, featured, order),
 *    its university links and everything related to it are never touched.
 *  - Live restaurant content can only change through the draft + publish workflow (a database guard enforces it), so an
 *    update is saved as the restaurant's DRAFT; the admin publishes it with the existing controls. New restaurants are
 *    inserted as drafts. Nothing here publishes.
 *  - The main photo follows the photo workflow (a draft of the restaurant's photo set), only for pictures in OUR
 *    storage bucket. Kakao or any other outside image is never imported. An existing photo is never replaced, deleted
 *    or duplicated.
 */
export type ImportMode = 'fill' | 'update' | 'new_only'

export const MODE_LABEL: Record<ImportMode, string> = {
  fill: '빈 정보만 채우기', update: 'CSV 값으로 업데이트', new_only: '신규 식당만 추가',
}

/** Columns of the current 식당 정보 that this import writes (the id, the visibility and the photo are handled separately). */
const TEXT_FIELDS = ['name_ko', 'name_en', 'category', 'address', 'phone', 'description'] as const
type TextField = (typeof TEXT_FIELDS)[number]
/** The hours the app checks "지금 주문 가능" with, each with how a stored snapshot holds it (open time: opening_hours.open). */
const HOURS_FIELDS = {
  open_time: (s: Snapshot) => (s.opening_hours as Record<string, unknown> | null | undefined)?.open,
  last_order_time: (s: Snapshot) => s.last_order_time,
  break_time: (s: Snapshot) => s.break_time,
} as const
const LABEL: Record<string, string> = {
  name_ko: '이름', name_en: '영어 이름', category: '카테고리', address: '주소', phone: '전화번호', description: '설명', coords: '위도·경도', image: '대표 사진',
  open_time: '영업 시작', last_order_time: '주문 마감', break_time: '브레이크타임',
}

/** Columns an older file may still have: read nowhere, reported in the preview with the reason. */
export const LEGACY_COLUMNS: Record<string, string> = {
  business_status: '식당 정보 화면에서 더 이상 관리하지 않는 항목이에요',
  avg_cost_krw: '식당 정보 화면에서 더 이상 관리하지 않는 항목이에요',
  dining_purposes: '식당 정보 화면에서 더 이상 관리하지 않는 항목이에요',
  price_min_krw: '식당 전체의 최저 가격이에요. 메뉴별 가격이 아니라서 읽지 않았어요. 메뉴 가격은 메뉴·가격 화면(또는 메뉴 CSV)에서 관리해요',
  price_max_krw: '식당 전체의 최고 가격이에요. 메뉴별 가격이 아니라서 읽지 않았어요. 메뉴 가격은 메뉴·가격 화면(또는 메뉴 CSV)에서 관리해요',
}
const NOT_APPLIED: Record<string, string> = { visibility: '읽지만 적용하지 않아요 (공개 상태는 가져오기로 바꾸지 않아요. 새 식당은 항상 초안이에요)' }

export type ColumnReport = { used: string[]; notApplied: { column: string; reason: string }[]; legacy: { column: string; reason: string }[]; unknown: string[] }

export function reportColumns(text: string): ColumnReport {
  const src = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text
  const head = (Papa.parse<string[]>(src, { preview: 1 }).data[0] ?? []).map((h) => h.trim()).filter(Boolean)
  const current = new Set<string>(CSV_COLUMNS)
  return {
    used: head.filter((h) => current.has(h) && !(h in NOT_APPLIED)),
    notApplied: head.filter((h) => h in NOT_APPLIED).map((column) => ({ column, reason: NOT_APPLIED[column] })),
    legacy: head.filter((h) => h in LEGACY_COLUMNS).map((column) => ({ column, reason: LEGACY_COLUMNS[column] })),
    unknown: head.filter((h) => !current.has(h) && !(h in LEGACY_COLUMNS)),
  }
}

// ---------------------------------------------------------------------------------------------------------------------
const norm = (s: unknown) => (s == null ? '' : String(s)).normalize('NFC').replace(/\s+/g, ' ').trim()
const nameKey = (s: string) => norm(s).toLowerCase()
const KAKAO_ID = /^\d{1,20}$/
const SCIENTIFIC = /^[+-]?\d+(\.\d+)?e[+-]?\d+$/i

/** A Kakao place id, or why the row cannot be matched (blank, exponent form from a spreadsheet, not numeric). */
export function normalizePlaceId(raw: string): { id: string | null; problem?: string } {
  const v = raw.trim()
  if (v === '') return { id: null, problem: 'kakao_place_id가 비어 있어요. 이름만으로는 같은 식당인지 알 수 없어서 따로 검토가 필요해요' }
  if (SCIENTIFIC.test(v)) return { id: null, problem: `kakao_place_id가 지수 형식으로 바뀌었어요 (“${v}”). 엑셀에서 이 열을 텍스트로 지정해 주세요` }
  if (!KAKAO_ID.test(v)) return { id: null, problem: `kakao_place_id 형식이 올바르지 않아요 (“${v}”). 숫자여야 해요` }
  return { id: v }
}

/** What an existing restaurant currently has, as an import sees it: its draft over its live record. */
export type Existing = {
  id: string
  kakaoPlaceId: string
  visibility: string
  name: string
  /** The snapshot a saved draft is built on: the draft's data if there is one, else the live snapshot. */
  base: Snapshot
  hasDraft: boolean
  revision: number
  photos: { items: PhotoItem[]; revision: number; hasDraft: boolean; coverUrlOnRestaurant: string | null }
}

export type FieldChange = { field: string; label: string; from: string; to: string }
export type ImagePlan =
  | { action: 'none' }
  | { action: 'add' | 'replace'; url: string; storagePath: string }
  | { action: 'same' | 'keep' }
  | { action: 'skip'; reason: string }

export type RowKind = 'create' | 'update' | 'unchanged' | 'skipped_existing' | 'invalid' | 'review' | 'duplicate'
export type PlanRow = {
  line: number
  kind: RowKind
  kakaoPlaceId: string
  name: string
  restaurantId: string | null
  visibility: string | null
  changes: FieldChange[]
  image: ImagePlan
  notes: string[]
  errors: string[]
  values: RestaurantForm | null
}
export type PlanCounts = {
  rows: number; matched: number; created: number; withUpdates: number; unchanged: number; skippedExisting: number
  invalid: number; review: number; duplicate: number; conflicts: number
}
export type ImportPlan = { rows: PlanRow[]; counts: PlanCounts }

export type PlanOptions = { mode: ImportMode; /** The Supabase project's host: only photos stored in OUR bucket are imported. */ ownHost: string | null }

/** Only a picture in this project's own public bucket (the photo workflow's storage). Anything else is never imported. */
export function ownImage(url: string, ownHost: string | null): { path: string } | { reason: string } {
  let host: string
  try { host = new URL(url).host } catch { return { reason: '사진 주소가 올바르지 않아요' } }
  if (/kakao|daum/i.test(host)) return { reason: '카카오 사진은 정책상 가져오지 않아요' }
  const path = storagePathFromUrl(url)
  if (!path || (ownHost && host !== ownHost)) return { reason: '이 서비스의 사진 저장소에 있는 사진이 아니라서 가져오지 않았어요 (사진 관리에서 올려 주세요)' }
  return { path }
}

const sameNumber = (a: number | null, b: number | null) => (a == null || b == null ? a === b : Math.abs(a - b) < 1e-7)
const num = (s: string) => (s.trim() === '' ? null : Number(s))
const snapNum = (v: unknown) => (typeof v === 'number' ? v : v == null || v === '' ? null : Number(v))

/** Compares one CSV row with the restaurant it matched: which fields change, what happens to the photo. */
export function planExisting(v: RestaurantForm, ex: Existing, mode: Exclude<ImportMode, 'new_only'>, ownHost: string | null): { changes: FieldChange[]; set: Snapshot; image: ImagePlan } {
  const changes: FieldChange[] = []
  const set: Snapshot = {}
  for (const f of TEXT_FIELDS) {
    const incoming = norm(v[f as TextField])
    if (incoming === '') continue // an empty cell never erases
    const stored = norm(ex.base[f])
    if (stored === incoming) continue
    if (mode === 'fill' && stored !== '') continue // fill keeps what is there
    changes.push({ field: f, label: LABEL[f], from: stored || '비어 있음', to: incoming })
    set[f] = incoming
  }
  for (const [f, read] of Object.entries(HOURS_FIELDS)) {
    const incoming = norm(v[f as keyof typeof HOURS_FIELDS])
    if (incoming === '') continue
    const raw = norm(read(ex.base))
    const stored = f === 'break_time' ? raw : raw.slice(0, 5) // a time column comes back as "21:30:00"
    if (stored === incoming || (mode === 'fill' && stored !== '')) continue
    changes.push({ field: f, label: LABEL[f], from: stored || '비어 있음', to: incoming })
    if (f === 'open_time') set.opening_hours = { ...((ex.base.opening_hours as Record<string, unknown> | null | undefined) ?? {}), open: incoming }
    else set[f] = incoming
  }
  // coordinates change together or not at all
  const inLat = num(v.latitude), inLng = num(v.longitude)
  if (inLat != null && inLng != null) {
    const curLat = snapNum(ex.base.latitude), curLng = snapNum(ex.base.longitude)
    const differs = !sameNumber(curLat, inLat) || !sameNumber(curLng, inLng)
    const empty = curLat == null && curLng == null
    if (differs && (mode === 'update' || empty)) {
      changes.push({ field: 'coords', label: LABEL.coords, from: curLat != null && curLng != null ? `${curLat}, ${curLng}` : '비어 있음', to: `${inLat}, ${inLng}` })
      set.latitude = inLat; set.longitude = inLng
    }
  }
  return { changes, set, image: planImage(v.image_url, ex, mode, ownHost) }
}

export function planImage(raw: string, ex: Existing, mode: Exclude<ImportMode, 'new_only'>, ownHost: string | null): ImagePlan {
  const url = raw.trim()
  if (url === '') return { action: 'none' }
  const own = ownImage(url, ownHost)
  if ('reason' in own) return { action: 'skip', reason: own.reason }
  // the same file is already one of this restaurant's photos (published, archived or still a draft): nothing to add
  if (ex.photos.items.some((p) => p.storage_path === own.path || p.url === url)) return { action: 'same' }
  const hasCover = ex.photos.items.some((p) => p.kind === 'cover' && p.status === 'published') || !!ex.photos.coverUrlOnRestaurant
  if (!hasCover) return { action: 'add', url, storagePath: own.path }
  return mode === 'update' ? { action: 'replace', url, storagePath: own.path } : { action: 'keep' }
}

// ---------------------------------------------------------------------------------------------------------------------
export function buildImportPlan(parsed: ParsedRow[], existing: Map<string, Existing>, opts: PlanOptions): ImportPlan {
  const rows: PlanRow[] = []
  const seen = new Map<string, number>()
  const names = new Map<string, string[]>() // normalised name -> place ids using it in this file
  for (const p of parsed) if (p.values) { const k = nameKey(p.values.name_ko); names.set(k, [...(names.get(k) ?? []), p.values.kakao_place_id]) }

  for (const p of parsed) {
    const base = { line: p.line, kakaoPlaceId: '', name: p.values?.name_ko ?? '', restaurantId: null as string | null, visibility: null as string | null, changes: [] as FieldChange[], image: { action: 'none' } as ImagePlan, notes: [] as string[], errors: [] as string[], values: p.values }
    if (!p.values) { rows.push({ ...base, kind: 'invalid', errors: p.errors }); continue }
    const v = p.values
    const id = normalizePlaceId(v.kakao_place_id)
    if (!id.id) { rows.push({ ...base, kind: 'review', kakaoPlaceId: v.kakao_place_id, notes: [id.problem!] }); continue }
    const row = { ...base, kakaoPlaceId: id.id }
    const first = seen.get(id.id)
    if (first != null) { rows.push({ ...row, kind: 'duplicate', notes: [`${first}줄과 같은 장소 ID라서 건너뛰었어요 (앞의 줄을 사용해요)`] }); continue }
    seen.set(id.id, p.line)
    const sameName = (names.get(nameKey(v.name_ko)) ?? []).filter((x) => x !== id.id && x !== '')
    const notes = sameName.length > 0 ? [`같은 이름의 다른 장소 ID가 파일에 있어요 (${sameName.slice(0, 3).join(', ')}). 서로 다른 식당으로 다뤄요`] : []

    const ex = existing.get(id.id)
    if (!ex) {
      const image: ImagePlan = v.image_url.trim() === '' ? { action: 'none' } : (() => { const o = ownImage(v.image_url.trim(), opts.ownHost); return 'reason' in o ? { action: 'skip', reason: o.reason } : { action: 'add', url: v.image_url.trim(), storagePath: o.path } })()
      rows.push({ ...row, kind: 'create', visibility: 'draft', image, notes: [...notes, '새 식당이에요. 초안으로 추가돼요'] })
      continue
    }
    const withId = { ...row, restaurantId: ex.id, visibility: ex.visibility }
    const conflict = norm(ex.name) !== '' && nameKey(ex.name) !== nameKey(v.name_ko) ? [`저장된 이름 “${ex.name}”과 파일의 이름 “${v.name_ko}”이 달라요${opts.mode === 'update' ? ' (이름도 파일 값으로 바뀌어요)' : ' (저장된 이름을 그대로 둬요)'}`] : []
    if (opts.mode === 'new_only') { rows.push({ ...withId, kind: 'skipped_existing', notes: [...notes, '이미 등록된 식당이라 건너뛰었어요'] }); continue }
    const { changes, image } = planExisting(v, ex, opts.mode, opts.ownHost)
    const writes = changes.length > 0 || image.action === 'add' || image.action === 'replace'
    rows.push({ ...withId, kind: writes ? 'update' : 'unchanged', changes, image, notes: [...notes, ...conflict] })
  }

  const n = (k: RowKind) => rows.filter((r) => r.kind === k).length
  return {
    rows,
    counts: {
      rows: rows.length, matched: rows.filter((r) => r.restaurantId != null).length, created: n('create'), withUpdates: n('update'), unchanged: n('unchanged'),
      skippedExisting: n('skipped_existing'), invalid: n('invalid'), review: n('review'), duplicate: n('duplicate'),
      conflicts: rows.filter((r) => r.notes.some((m) => m.includes('같은 이름') || m.includes('달라요'))).length,
    },
  }
}

export function parseImport(text: string): ParsedRow[] { return parseRestaurantCsv(text) }

// ---------------------------------------------------------------------------------------------------------------------
// applying
// ---------------------------------------------------------------------------------------------------------------------
export type ImportDeps = {
  /** Inserts new restaurants (drafts) and returns the ones that were really inserted: a place registered meanwhile is left out, never duplicated. */
  insertRestaurants: (rows: Record<string, unknown>[]) => Promise<{ id: string; kakao_place_id: string }[]>
  getExisting: (kakaoPlaceId: string) => Promise<Existing | null>
  saveRestaurantDraft: (id: string, snapshot: Snapshot, expectedRevision: number) => Promise<void>
  savePhotoDraft: (id: string, photos: PhotoItem[], expectedRevision: number) => Promise<void>
  checkImage: (url: string) => Promise<'ok' | 'bad' | 'unknown'>
  newId?: () => string
  sleep?: (ms: number) => Promise<void>
}
export type Outcome = { line: number; kakaoPlaceId: string; name: string; restaurantId: string | null; result: 'created' | 'updated' | 'unchanged' | 'skipped' | 'failed'; message: string; changes: FieldChange[] }
export type ApplyResult = { outcomes: Outcome[]; counts: Record<Outcome['result'], number>; stoppedBy: 'forbidden' | 'cancelled' | null }

const errCode = (e: unknown) => (typeof e === 'object' && e && 'code' in e ? String((e as { code: unknown }).code) : undefined)
const errMsg = (e: unknown) => (e instanceof Error ? e.message : typeof e === 'object' && e && 'message' in e ? String((e as { message: unknown }).message) : '알 수 없는 오류')

function photoItem(url: string, path: string, kind: 'cover' | 'gallery', order: number, id: string): PhotoItem {
  return { id, kind, storage_path: path, url, caption: null, sort_order: order, status: 'published', source: 'admin', credit: null, width: null, height: null, bytes: null }
}
/** The photo list after adding [plan]'s picture as the cover. A replaced cover is archived (kept for a rollback), never deleted. */
export function withCover(items: PhotoItem[], plan: { url: string; storagePath: string }, id: string): PhotoItem[] {
  const next = items.map((p) => (p.kind === 'cover' && p.status === 'published' ? { ...p, status: 'archived' as const } : p))
  return [...next, photoItem(plan.url, plan.storagePath, 'cover', 0, id)]
}

export async function applyImportPlan(plan: ImportPlan, opts: PlanOptions, deps: ImportDeps, run: { signal?: AbortSignal; concurrency?: number; onProgress?: (done: number, total: number) => void } = {}): Promise<ApplyResult> {
  const sleep = deps.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)))
  const newId = deps.newId ?? (() => crypto.randomUUID())
  const outcomes: Outcome[] = []
  const out = (r: PlanRow, result: Outcome['result'], message: string, changes: FieldChange[] = []) =>
    outcomes.push({ line: r.line, kakaoPlaceId: r.kakaoPlaceId, name: r.name, restaurantId: r.restaurantId, result, message, changes })
  let stoppedBy: ApplyResult['stoppedBy'] = null
  const todo = plan.rows.filter((r) => r.kind === 'create' || r.kind === 'update')
  let done = 0
  const total = todo.length
  const tick = () => run.onProgress?.(done, total)

  for (const r of plan.rows) {
    if (r.kind === 'invalid') out(r, 'failed', r.errors.join(' / ') || '올바르지 않은 줄이에요')
    else if (r.kind === 'review') out(r, 'skipped', r.notes.join(' '))
    else if (r.kind === 'duplicate') out(r, 'skipped', r.notes.join(' '))
    else if (r.kind === 'skipped_existing') out(r, 'skipped', '이미 등록된 식당이에요 (신규 식당만 추가)')
    else if (r.kind === 'unchanged') out(r, 'unchanged', '바뀐 내용이 없어요')
  }

  /** The photo step of one restaurant, reported separately: a bad picture never undoes the restaurant's other updates. */
  const photoStep = async (restaurantId: string, ex: Existing | null, img: ImagePlan): Promise<string> => {
    if (img.action === 'skip') return `사진은 가져오지 않았어요 (${img.reason})`
    if (img.action !== 'add' && img.action !== 'replace') return ''
    const check = await deps.checkImage(img.url)
    if (check === 'bad') return '사진 주소에 접근할 수 없어서 사진은 가져오지 않았어요'
    const items = ex?.photos.items ?? []
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const rev = ex?.photos.revision ?? 0
        await deps.savePhotoDraft(restaurantId, withCover(items, img, newId()), rev)
        return img.action === 'replace' ? '대표 사진을 바꾸는 초안을 저장했어요 (이전 사진은 보관돼요)' : '대표 사진을 초안으로 저장했어요'
      } catch (e) {
        if (errCode(e) === '40001' && attempt < 2) { await sleep(100); const fresh = await deps.getExisting(ex?.kakaoPlaceId ?? ''); if (fresh) { ex = fresh; items.splice(0, items.length, ...fresh.photos.items) } continue }
        return `사진을 저장하지 못했어요 (${errMsg(e)})`
      }
    }
    return ''
  }

  // 1. new restaurants: ONE insert per chunk that ignores places registered in the meantime (never a duplicate)
  const creates = todo.filter((r) => r.kind === 'create')
  for (let i = 0; i < creates.length && !stoppedBy; i += 100) {
    if (run.signal?.aborted) { stoppedBy = 'cancelled'; break }
    const chunk = creates.slice(i, i + 100)
    let inserted: { id: string; kakao_place_id: string }[]
    try {
      inserted = await deps.insertRestaurants(chunk.map((r) => ({ ...toRow(r.values!), kakao_place_id: r.kakaoPlaceId, visibility: 'draft', featured: false, image_url: null })))
    } catch (e) {
      if (errCode(e) === '42501') stoppedBy = 'forbidden'
      for (const r of chunk) out(r, 'failed', errMsg(e))
      done += chunk.length; tick(); continue
    }
    const byKakao = new Map(inserted.map((x) => [x.kakao_place_id, x.id]))
    for (const r of chunk) {
      const id = byKakao.get(r.kakaoPlaceId)
      if (!id) { out(r, 'skipped', '그 사이 다른 곳에서 먼저 등록돼서 새로 만들지 않았어요'); continue }
      const note = await photoStep(id, null, r.image)
      outcomes.push({ line: r.line, kakaoPlaceId: r.kakaoPlaceId, name: r.name, restaurantId: id, result: 'created', message: `초안으로 추가했어요${note ? `. ${note}` : ''}`, changes: [] })
    }
    done += chunk.length; tick()
  }

  // 2. existing restaurants: re-read each one, plan again against what is there NOW, save drafts (revision-checked)
  const updates = stoppedBy ? [] : todo.filter((r) => r.kind === 'update')
  let next = 0
  let fatal = false
  const one = async (r: PlanRow) => {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const ex = await deps.getExisting(r.kakaoPlaceId)
        if (!ex) return out(r, 'failed', '식당을 찾을 수 없어요 (그 사이 삭제됐을 수 있어요)')
        if (opts.mode === 'new_only') return out(r, 'skipped', '이미 등록된 식당이에요')
        const fresh = planExisting(r.values!, ex, opts.mode, opts.ownHost)
        const imgWrites = fresh.image.action === 'add' || fresh.image.action === 'replace'
        if (fresh.changes.length === 0 && !imgWrites) return out(r, fresh.image.action === 'skip' ? 'unchanged' : 'unchanged', fresh.image.action === 'skip' ? `바뀐 내용이 없어요. 사진은 가져오지 않았어요 (${fresh.image.reason})` : '바뀐 내용이 없어요')
        if (fresh.changes.length > 0) await deps.saveRestaurantDraft(ex.id, { ...ex.base, ...fresh.set }, ex.revision)
        const note = await photoStep(ex.id, ex, fresh.image)
        const text = [fresh.changes.length > 0 ? `${fresh.changes.map((c) => c.label).join(', ')} 초안을 저장했어요` : '', note].filter(Boolean).join('. ')
        return out({ ...r, restaurantId: ex.id }, 'updated', text, fresh.changes)
      } catch (e) {
        if (errCode(e) === '42501') { fatal = true; return out(r, 'failed', errMsg(e)) }
        const conflict = errCode(e) === '40001'
        const transient = errCode(e) === undefined
        if ((conflict || transient) && attempt < 2) { await sleep(conflict ? 100 : 400 * (attempt + 1)); continue }
        return out(r, 'failed', errMsg(e))
      }
    }
  }
  const worker = async () => {
    while (!fatal && !run.signal?.aborted) {
      const r = updates[next++]
      if (!r) return
      await one(r)
      done++; tick()
    }
  }
  await Promise.all(Array.from({ length: Math.min(run.concurrency ?? 3, updates.length) }, worker))
  if (fatal) stoppedBy = 'forbidden'
  else if (run.signal?.aborted) stoppedBy = 'cancelled'
  outcomes.sort((a, b) => a.line - b.line)
  const counts: ApplyResult['counts'] = { created: 0, updated: 0, unchanged: 0, skipped: 0, failed: 0 }
  for (const o of outcomes) counts[o.result]++
  return { outcomes, counts, stoppedBy }
}
