import type { MenuItem } from '@/lib/cms'
import { type CsvRow, normalizeText } from './menuCsv'
import { sortItems } from './menu'

/**
 * Turning CSV rows into menu DRAFTS. Pure planning (`buildPlan`, `planRestaurant`) + bounded, retried saving (`applyPlan`)
 * + the optional publish step (`publishSaved`).
 *
 * Safety rules, all enforced here:
 *  - Restaurants are matched by KAKAO PLACE ID only, never by name. A name that differs from the database's is a
 *    warning and the row is left out unless the admin opts in.
 *  - A menu id must belong to the SAME restaurant; an id of another restaurant (or an unknown one) is an error.
 *  - Without an id a menu matches an existing one by its exact normalized name; two existing menus with that name is
 *    ambiguous: flagged, never guessed.
 *  - Existing menus are never deleted or archived by an import; menus not in the file are left exactly as they are.
 *  - Only the fields the file states are changed ("blank = leave as is" when updating): photos, 대표/추천 flags,
 *    sort order of existing lines are kept. A blank price of a NEW menu stays NULL (unknown), never 0.
 *  - An import never sets a "price verified" date, and if it changes a price the old date is cleared (it vouched for
 *    the OLD price).
 *  - The result is saved as a DRAFT through `cms_save_draft`. Nothing is published, and restaurant visibility is
 *    never touched.
 */
export type ImportMode = 'append' | 'update'
export type ImportScope = 'file' | 'selected'
export type RestaurantRef = { id: string; name_ko: string; kakao_place_id: string }
/** What the editor shows for a restaurant: its draft if it has one, else the live list. */
export type MenuState = { items: MenuItem[]; revision: number; hasDraft: boolean }

export type RowAction = 'add' | 'update' | 'unchanged' | 'duplicate' | 'invalid' | 'unmatched' | 'name_mismatch'
export type FieldChange = { field: string; from: string; to: string }
export type PlanRow = {
  line: number
  action: RowAction
  messages: string[]
  restaurantId: string | null
  restaurantName: string
  menuName: string
  csv: CsvRow
  changes: FieldChange[]
}
export type RestaurantPlan = {
  restaurant: RestaurantRef
  hasDraft: boolean
  baseRevision: number
  existing: number
  adds: number
  updates: number
  /** The whole merged menu list to save as the draft (existing lines kept). Only meaningful when adds + updates > 0. */
  items: MenuItem[]
  rows: PlanRow[]
}
export type PlanCounts = {
  rows: number
  add: number
  update: number
  unchanged: number
  duplicate: number
  invalid: number
  unmatched: number
  nameMismatch: number
  matchedRestaurants: number
  unmatchedRestaurants: number
  /** Restaurants that will receive a draft. */
  restaurantsToSave: number
}
export type Plan = { rows: PlanRow[]; restaurants: RestaurantPlan[]; unmatchedIds: { kakaoPlaceId: string; lines: number[] }[]; counts: PlanCounts }

export type PlanOptions = {
  mode: ImportMode
  scope: ImportScope
  /** The restaurant chosen on the page (used when scope is 'selected'). */
  selected: RestaurantRef | null
  /** Import rows whose restaurant_name differs from the database's name for that place id. */
  allowNameMismatch: boolean
  newId?: () => string
}

const money = (n: number | null) => (n == null ? '가격 미정' : `${n.toLocaleString('ko-KR')}원`)
const flag = (b: boolean) => (b ? '판매 중' : '품절')

/** Rows of ONE restaurant, in file order, against that restaurant's current menu list. */
export function planRestaurant(
  restaurant: RestaurantRef, state: MenuState, csvRows: { row: CsvRow; messages: string[] }[], menuOwners: Map<string, string>, opts: PlanOptions,
): RestaurantPlan {
  const newId = opts.newId ?? (() => crypto.randomUUID())
  const items = state.items.map((i) => ({ ...i }))
  const byId = new Map(items.map((i) => [i.id, i]))
  const byName = new Map<string, MenuItem[]>()
  const indexName = (i: MenuItem) => { const k = normalizeText(i.name_ko); byName.set(k, [...(byName.get(k) ?? []), i]) }
  items.forEach(indexName)
  let nextSort = (items.reduce((m, i) => Math.max(m, i.sort_order), 0)) + 1
  const touched = new Set<string>() // menu lines already used by an earlier row of the file
  const out: PlanRow[] = []
  let adds = 0
  let updates = 0

  for (const { row, messages: carry } of csvRows) {
    const base = { line: row.line, restaurantId: restaurant.id, restaurantName: restaurant.name_ko, menuName: row.menuName, csv: row }
    const fail = (action: RowAction, ...msg: string[]) => out.push({ ...base, action, messages: [...carry, ...msg], changes: [] })

    // 1. which existing line (if any) does the row mean?
    let match: MenuItem | null = null
    if (row.menuId) {
      match = byId.get(row.menuId) ?? null
      if (!match) {
        const owner = menuOwners.get(row.menuId)
        fail('invalid', owner && owner !== restaurant.id ? '이 menu_id는 다른 식당의 메뉴예요. 다른 식당에 넣지 않았어요' : '이 식당에 없는 menu_id예요. 새 메뉴라면 menu_id 칸을 비워 주세요')
        continue
      }
    } else {
      const same = byName.get(normalizeText(row.menuName)) ?? []
      if (same.length > 1) { fail('invalid', `같은 이름의 메뉴가 ${same.length}개 있어 어느 것인지 알 수 없어요. menu_id를 적어 주세요`); continue }
      match = same[0] ?? null
    }

    // 2. the same line twice in one file: the first row wins
    const key = match ? `id:${match.id}` : `new:${normalizeText(row.menuName)}`
    if (touched.has(key)) { fail('duplicate', '파일 안에서 같은 메뉴가 또 나와서 건너뛰었어요 (앞의 줄을 사용해요)'); continue }
    touched.add(key)

    // 3. append: only new lines. update: matched lines change, the rest are added.
    if (match && opts.mode === 'append') { fail('duplicate', '이미 있는 메뉴라서 건너뛰었어요 (바꾸려면 “갱신” 모드로 가져오세요)'); continue }
    if (match && match.status === 'archived') { fail('invalid', '보관된 메뉴예요. 메뉴 화면에서 복원한 뒤 가져와 주세요'); continue }

    if (!match) {
      const item: MenuItem = {
        id: newId(), name_ko: row.menuName, description_ko: row.description || null, price_krw: row.price, category: row.category || null,
        price_verified_on: null, available: row.available ?? true, representative: false, recommended: false, status: 'active', sort_order: nextSort++, image_url: null,
      }
      items.push(item); byId.set(item.id, item); indexName(item)
      touched.add(`id:${item.id}`) // a later row for the line just added is a duplicate, not an update of it
      adds++
      out.push({ ...base, action: 'add', messages: [...carry, row.price == null ? '가격 미정으로 추가돼요' : '새 메뉴로 추가돼요'], changes: [] })
      continue
    }

    // update: only what the file states; blank = leave as it is
    const changes: FieldChange[] = []
    const next: MenuItem = { ...match }
    if (row.menuId && normalizeText(row.menuName) !== normalizeText(match.name_ko)) { changes.push({ field: '이름', from: match.name_ko, to: row.menuName }); next.name_ko = row.menuName }
    if (row.price != null && row.price !== match.price_krw) {
      changes.push({ field: '가격', from: money(match.price_krw), to: money(row.price) }); next.price_krw = row.price
      if (match.price_verified_on) { changes.push({ field: '가격 확인일', from: match.price_verified_on, to: '비움 (새 가격은 확인되지 않았어요)' }); next.price_verified_on = null }
    }
    if (row.category && row.category !== (match.category ?? '')) { changes.push({ field: '분류', from: match.category ?? '없음', to: row.category }); next.category = row.category }
    if (row.description && row.description !== (match.description_ko ?? '')) { changes.push({ field: '설명', from: match.description_ko ?? '없음', to: row.description }); next.description_ko = row.description }
    if (row.available != null && row.available !== match.available) { changes.push({ field: '판매', from: flag(match.available), to: flag(row.available) }); next.available = row.available }
    if (changes.length === 0) { out.push({ ...base, action: 'unchanged', messages: [...carry, '바뀐 내용이 없어요'], changes }); continue }
    const at = items.findIndex((i) => i.id === match!.id)
    items[at] = next; byId.set(next.id, next)
    byName.clear(); items.forEach(indexName)
    updates++
    out.push({ ...base, action: 'update', messages: carry, changes })
  }

  return { restaurant, hasDraft: state.hasDraft, baseRevision: state.revision, existing: state.items.length, adds, updates, items: sortItems(items), rows: out }
}

/**
 * Resolves every row to a restaurant (by Kakao place id), then plans each restaurant. [states] must hold the current menu
 * state of every restaurant that could be matched; [restaurants] maps Kakao place id -> restaurant.
 */
export function buildPlan(rows: CsvRow[], restaurants: Map<string, RestaurantRef>, states: Map<string, MenuState>, menuOwners: Map<string, string>, opts: PlanOptions): Plan {
  const resolved = new Map<string, { restaurant: RestaurantRef; list: { row: CsvRow; messages: string[] }[] }>()
  const loose: PlanRow[] = []
  const unmatched = new Map<string, number[]>()
  const skeleton = (row: CsvRow, action: RowAction, ...messages: string[]): PlanRow => ({ line: row.line, action, messages, restaurantId: null, restaurantName: row.restaurantName, menuName: row.menuName, csv: row, changes: [] })

  for (const row of rows) {
    if (row.errors.length > 0) { loose.push(skeleton(row, 'invalid', ...row.errors)); continue }
    let restaurant: RestaurantRef | undefined
    if (opts.scope === 'selected') {
      const sel = opts.selected
      if (!sel) { loose.push(skeleton(row, 'invalid', '가져올 식당이 선택되지 않았어요')); continue }
      if (row.kakaoPlaceId && row.kakaoPlaceId !== sel.kakao_place_id) { loose.push(skeleton(row, 'invalid', `선택한 식당(${sel.name_ko})의 장소 ID와 달라서 가져오지 않았어요`)); continue }
      restaurant = sel
    } else {
      if (!row.kakaoPlaceId) { loose.push(skeleton(row, 'invalid', 'kakao_place_id가 비어 있어요. 식당 이름만으로는 연결하지 않아요')); continue }
      restaurant = restaurants.get(row.kakaoPlaceId)
      if (!restaurant) { unmatched.set(row.kakaoPlaceId, [...(unmatched.get(row.kakaoPlaceId) ?? []), row.line]); loose.push(skeleton(row, 'unmatched', `장소 ID ${row.kakaoPlaceId} 식당이 관리 목록에 없어요`)); continue }
    }
    const carry: string[] = []
    if (row.restaurantName && normalizeText(row.restaurantName) !== normalizeText(restaurant.name_ko)) {
      if (!opts.allowNameMismatch) {
        loose.push({ ...skeleton(row, 'name_mismatch', `파일의 식당 이름 “${row.restaurantName}”이(가) 이 장소 ID의 식당 “${restaurant.name_ko}”과 달라요. 맞는지 확인하세요`), restaurantId: restaurant.id, restaurantName: restaurant.name_ko })
        continue
      }
      carry.push(`이름이 다르지만(“${row.restaurantName}” ≠ “${restaurant.name_ko}”) 장소 ID 기준으로 가져와요`)
    }
    const bucket = resolved.get(restaurant.id) ?? { restaurant, list: [] }
    bucket.list.push({ row, messages: carry })
    resolved.set(restaurant.id, bucket)
  }

  const plans: RestaurantPlan[] = []
  for (const { restaurant, list } of resolved.values()) {
    const state = states.get(restaurant.id) ?? { items: [], revision: 0, hasDraft: false }
    plans.push(planRestaurant(restaurant, state, list, menuOwners, opts))
  }
  const all = [...loose, ...plans.flatMap((p) => p.rows)].sort((a, b) => a.line - b.line)
  const n = (a: RowAction) => all.filter((r) => r.action === a).length
  return {
    rows: all, restaurants: plans,
    unmatchedIds: [...unmatched].map(([kakaoPlaceId, lines]) => ({ kakaoPlaceId, lines })),
    counts: {
      rows: all.length, add: n('add'), update: n('update'), unchanged: n('unchanged'), duplicate: n('duplicate'), invalid: n('invalid'), unmatched: n('unmatched'), nameMismatch: n('name_mismatch'),
      matchedRestaurants: plans.length, unmatchedRestaurants: unmatched.size, restaurantsToSave: plans.filter((p) => p.adds + p.updates > 0).length,
    },
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// saving drafts
// ---------------------------------------------------------------------------------------------------------------------
export type SaveDeps = {
  /** The restaurant's current menu state (draft if any, else live) and the draft revision. */
  getState: (restaurantId: string) => Promise<MenuState>
  /** `cms_save_draft('restaurant_menus', id, {items}, expectedRevision)`; returns the new revision. */
  saveDraft: (restaurantId: string, items: MenuItem[], expectedRevision: number) => Promise<{ revision: number }>
  sleep?: (ms: number) => Promise<void>
}
export type SavedRestaurant = { restaurantId: string; name: string; added: number; updated: number; revision: number; hadDraft: boolean }
export type SaveFailure = { restaurantId: string; name: string; message: string; code?: string }
export type SaveResult = { saved: SavedRestaurant[]; failed: SaveFailure[]; untouched: number; stoppedBy: 'cancelled' | 'forbidden' | null }
export type SaveProgress = { done: number; total: number; saved: number; failed: number }

const errCode = (e: unknown) => (typeof e === 'object' && e && 'code' in e ? String((e as { code: unknown }).code) : undefined)
const errMsg = (e: unknown) => (e instanceof Error ? e.message : typeof e === 'object' && e && 'message' in e ? String((e as { message: unknown }).message) : '알 수 없는 오류')

/**
 * Saves one draft per restaurant that has something to add or change. Each restaurant is re-read first and its rows are
 * planned again against what is there NOW (someone may have edited since the preview), so nothing is overwritten and a
 * repeat of the same import is a no-op. A conflict (another admin saved first) is re-planned and retried; a failure of
 * one restaurant never affects the others; a permission error stops the run.
 */
export async function applyPlan(plan: Plan, opts: PlanOptions, menuOwners: Map<string, string>, deps: SaveDeps, run: { concurrency?: number; signal?: AbortSignal; onProgress?: (p: SaveProgress) => void; only?: Set<string> } = {}): Promise<SaveResult> {
  const sleep = deps.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)))
  const targets = plan.restaurants.filter((p) => (!run.only || run.only.has(p.restaurant.id)) && p.rows.length > 0)
  const res: SaveResult = { saved: [], failed: [], untouched: 0, stoppedBy: null }
  let next = 0
  let done = 0
  let fatal = false
  const tick = () => run.onProgress?.({ done, total: targets.length, saved: res.saved.length, failed: res.failed.length })
  tick()

  const one = async (rp: RestaurantPlan) => {
    const rows = rp.rows.map((r) => ({ row: r.csv, messages: r.messages.filter((m) => m.startsWith('이름이 다르지만')) }))
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const state = await deps.getState(rp.restaurant.id)
        const fresh = planRestaurant(rp.restaurant, state, rows, menuOwners, opts)
        if (fresh.adds + fresh.updates === 0) { res.untouched++; return }
        const { revision } = await deps.saveDraft(rp.restaurant.id, fresh.items, state.revision)
        res.saved.push({ restaurantId: rp.restaurant.id, name: rp.restaurant.name_ko, added: fresh.adds, updated: fresh.updates, revision, hadDraft: state.hasDraft })
        return
      } catch (e) {
        if (errCode(e) === '42501') { fatal = true; res.failed.push({ restaurantId: rp.restaurant.id, name: rp.restaurant.name_ko, message: errMsg(e), code: '42501' }); return }
        const conflict = errCode(e) === '40001'
        const transient = errCode(e) === undefined
        if ((conflict || transient) && attempt < 2) { await sleep(conflict ? 100 : 400 * (attempt + 1)); continue }
        res.failed.push({ restaurantId: rp.restaurant.id, name: rp.restaurant.name_ko, message: errMsg(e), code: errCode(e) })
        return
      }
    }
  }
  const worker = async () => {
    while (!fatal && !run.signal?.aborted) {
      const rp = targets[next++]
      if (!rp) return
      await one(rp)
      done++
      tick()
    }
  }
  await Promise.all(Array.from({ length: Math.min(run.concurrency ?? 2, targets.length) }, worker))
  if (fatal) res.stoppedBy = 'forbidden'
  else if (run.signal?.aborted) res.stoppedBy = 'cancelled'
  return res
}

// ---------------------------------------------------------------------------------------------------------------------
// optional: publish what was imported (only through the existing publishing function)
// ---------------------------------------------------------------------------------------------------------------------
export type PublishDeps = { publish: (restaurantId: string, expectedRevision: number, reason: string) => Promise<unknown> }
export type PublishResult = { published: string[]; failed: SaveFailure[]; stoppedBy: 'cancelled' | 'forbidden' | null }

/**
 * `cms_publish` for each saved draft, with the revision this import saved (so it publishes exactly that draft, and refuses
 * with a conflict if someone edited it since). One restaurant failing does not stop the others.
 */
export async function publishSaved(saved: SavedRestaurant[], reason: string, deps: PublishDeps, run: { concurrency?: number; signal?: AbortSignal } = {}): Promise<PublishResult> {
  const res: PublishResult = { published: [], failed: [], stoppedBy: null }
  let next = 0
  let fatal = false
  const worker = async () => {
    while (!fatal && !run.signal?.aborted) {
      const s = saved[next++]
      if (!s) return
      try { await deps.publish(s.restaurantId, s.revision, reason); res.published.push(s.restaurantId) }
      catch (e) {
        if (errCode(e) === '42501') fatal = true
        res.failed.push({ restaurantId: s.restaurantId, name: s.name, message: errMsg(e), code: errCode(e) })
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(run.concurrency ?? 2, saved.length) }, worker))
  if (fatal) res.stoppedBy = 'forbidden'
  else if (run.signal?.aborted) res.stoppedBy = 'cancelled'
  return res
}
