import { describe, expect, it } from 'vitest'
import type { MenuItem } from '@/lib/cms'
import { buildPlan, applyPlan, planRestaurant, publishSaved, type MenuState, type PlanOptions, type RestaurantRef } from './menuImport'
import { parseMenuCsv } from './menuCsv'

const HEAD = 'kakao_place_id,restaurant_name,menu_name,price_krw,menu_category,description,is_available,menu_id'
const rows = (...lines: string[]) => parseMenuCsv([HEAD, ...lines].join('\n')).rows
const R1: RestaurantRef = { id: 'r1', name_ko: '어굿플레이스', kakao_place_id: '1001' }
const R2: RestaurantRef = { id: 'r2', name_ko: '라멘집', kakao_place_id: '1002' }
const A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const C = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'

const item = (id: string, name: string, over: Partial<MenuItem> = {}): MenuItem => ({
  id, name_ko: name, description_ko: null, price_krw: null, category: null, price_verified_on: null, available: true, representative: false, recommended: false,
  status: 'active', sort_order: 1, image_url: null, ...over,
})
const restaurants = new Map([[R1.kakao_place_id, R1], [R2.kakao_place_id, R2]])
let seq = 0
const newId = () => `new-${++seq}`
const opts = (over: Partial<PlanOptions> = {}): PlanOptions => ({ mode: 'update', scope: 'file', selected: null, allowNameMismatch: false, newId, ...over })
const empty: MenuState = { items: [], revision: 0, hasDraft: false }
const plan = (csv: ReturnType<typeof rows>, states: Record<string, MenuState> = {}, o: Partial<PlanOptions> = {}, owners: Record<string, string> = {}) =>
  buildPlan(csv, restaurants, new Map(Object.entries(states)), new Map(Object.entries(owners)), opts(o))

describe('new menus', () => {
  it('adds them as active lines; a blank price stays NULL (never 0); nothing is marked price-verified', () => {
    const p = plan(rows('1001,어굿플레이스,제육 정식,9000,식사,든든한 한 끼,true,', '1001,어굿플레이스,김치찌개,,식사,,,'))
    const items = p.restaurants[0].items
    expect(items.map((i) => [i.name_ko, i.price_krw, i.status, i.available, i.price_verified_on])).toEqual([
      ['제육 정식', 9000, 'active', true, null],
      ['김치찌개', null, 'active', true, null],
    ])
    expect(items[1].price_krw).toBeNull()
    expect(items.every((i) => i.image_url === null && !i.representative && !i.recommended)).toBe(true)
    expect(p.counts).toMatchObject({ rows: 2, add: 2, update: 0, invalid: 0, matchedRestaurants: 1, unmatchedRestaurants: 0, restaurantsToSave: 1 })
    expect(p.rows[1].messages.join(' ')).toMatch(/가격 미정/)
  })

  it('is_available is optional: blank = on sale, "false" = sold out', () => {
    const p = plan(rows('1001,,국수,5000,,,,', '1001,,우동,6000,,,false,'))
    expect(p.restaurants[0].items.map((i) => i.available)).toEqual([true, false])
  })

  it('new lines go after the existing ones and keep the file order', () => {
    const p = plan(rows('1001,,새1,,,,,', '1001,,새2,,,,,'), { r1: { items: [item(A, '기존', { sort_order: 5 })], revision: 2, hasDraft: true } })
    expect(p.restaurants[0].items.map((i) => [i.name_ko, i.sort_order])).toEqual([['기존', 5], ['새1', 6], ['새2', 7]])
  })

  it('new menus get new ids; ids already in the list are never reused', () => {
    const p = plan(rows('1001,,새1,,,,,'), { r1: { items: [item('new-1', '기존')], revision: 0, hasDraft: false } })
    expect(new Set(p.restaurants[0].items.map((i) => i.id)).size).toBe(2)
  })
})

describe('several restaurants in one file', () => {
  it('rows go to the restaurant of their Kakao place id, each with its own list', () => {
    const p = plan(rows('1001,,국수,5000,,,,', '1002,,돈코츠,9000,,,,', '1001,,우동,6000,,,,'))
    expect(p.restaurants.map((r) => [r.restaurant.id, r.items.map((i) => i.name_ko)])).toEqual([['r1', ['국수', '우동']], ['r2', ['돈코츠']]])
    expect(p.counts.matchedRestaurants).toBe(2)
  })
  it('an unknown place id is reported with its lines, imports nothing, and does not stop the others', () => {
    const p = plan(rows('9999,유령식당,국수,5000,,,,', '1001,,우동,6000,,,,', '9999,유령식당,김밥,3000,,,,'))
    expect(p.unmatchedIds).toEqual([{ kakaoPlaceId: '9999', lines: [2, 4] }])
    expect(p.counts).toMatchObject({ unmatched: 2, unmatchedRestaurants: 1, add: 1, matchedRestaurants: 1 })
    expect(p.rows.filter((r) => r.action === 'unmatched')).toHaveLength(2)
  })
})

describe('matching restaurants: by Kakao place id, never by name', () => {
  it('a WRONG place id with the name of a real restaurant is not matched to that restaurant (the id decides, never the name)', () => {
    const p = plan(rows('9999,어굿플레이스,국수,5000,,,,', '9999,라멘집,우동,6000,,,,'))
    expect(p.counts).toMatchObject({ unmatched: 2, add: 0, matchedRestaurants: 0 })
    expect(p.restaurants).toEqual([]) // nothing was put on 어굿플레이스 or 라멘집
    expect(p.unmatchedIds).toEqual([{ kakaoPlaceId: '9999', lines: [2, 3] }])
  })
  it('a row with a name but no id is refused', () => {
    const p = plan(rows(',어굿플레이스,국수,5000,,,,'))
    expect(p.counts.invalid).toBe(1)
    expect(p.rows[0].messages.join(' ')).toMatch(/이름만으로는 연결하지 않아요/)
    expect(p.restaurants).toEqual([])
  })
  it('a name that differs from the restaurant of that id is held back by default, and allowed on request', () => {
    const csv = rows('1001,라멘집,국수,5000,,,,') // 1001 is 어굿플레이스, not 라멘집
    const held = plan(csv)
    expect(held.counts).toMatchObject({ nameMismatch: 1, add: 0 })
    expect(held.rows[0].messages.join(' ')).toMatch(/어굿플레이스/)
    expect(held.restaurants).toEqual([])
    const allowed = plan(csv, {}, { allowNameMismatch: true })
    expect(allowed.counts).toMatchObject({ nameMismatch: 0, add: 1 })
    expect(allowed.restaurants[0].restaurant.id).toBe('r1')
  })
  it('names compare ignoring case, spacing and Unicode form (no false alarms)', () => {
    expect(plan(rows('1001, 어굿플레이스 ,국수,5000,,,,')).counts.nameMismatch).toBe(0)
    expect(plan(rows('1001,어굿 플레이스,국수,5000,,,,')).counts.nameMismatch).toBe(1) // a space INSIDE the name is a different name
    expect(plan(rows(`1001,${'어굿플레이스'.normalize('NFD')},국수,5000,,,,`)).counts.nameMismatch).toBe(0)
    expect(plan(rows('1001,,국수,5000,,,,')).counts.nameMismatch).toBe(0) // no name given: nothing to compare
  })
})

describe('scope: the selected restaurant only', () => {
  const sel = { scope: 'selected' as const, selected: R1 }
  it('rows without a place id belong to the selected restaurant', () => {
    const p = plan(rows(',,국수,5000,,,,', '1001,,우동,6000,,,,'), {}, sel)
    expect(p.restaurants).toHaveLength(1)
    expect(p.restaurants[0].restaurant.id).toBe('r1')
    expect(p.counts.add).toBe(2)
  })
  it('a row for ANOTHER restaurant is refused, never put on the selected one', () => {
    const p = plan(rows('1002,,돈코츠,9000,,,,', ',,국수,5000,,,,'), {}, sel)
    expect(p.counts).toMatchObject({ invalid: 1, add: 1 })
    expect(p.rows[0].messages.join(' ')).toMatch(/장소 ID와 달라서/)
    expect(p.restaurants.map((r) => r.restaurant.id)).toEqual(['r1'])
  })
})

describe('append mode', () => {
  const state = { r1: { items: [item(A, '제육 정식', { price_krw: 8000, sort_order: 1 })], revision: 3, hasDraft: true } }
  it('adds new menus only; a menu that already exists is skipped as a duplicate, even with a different price', () => {
    const p = plan(rows('1001,,제육 정식,9500,,,,', '1001,,우동,6000,,,,'), state, { mode: 'append' })
    expect(p.counts).toMatchObject({ add: 1, duplicate: 1, update: 0 })
    expect(p.rows[0].action).toBe('duplicate')
    const items = p.restaurants[0].items
    expect(items.find((i) => i.id === A)!.price_krw).toBe(8000) // untouched
    expect(items.map((i) => i.name_ko)).toEqual(['제육 정식', '우동'])
  })
  it('a menu_id of an existing menu is also a duplicate in append mode', () => {
    const p = plan(rows(`1001,,바뀐 이름,1,,,,${A}`), state, { mode: 'append' })
    expect(p.counts.duplicate).toBe(1)
    expect(p.restaurants[0].adds + p.restaurants[0].updates).toBe(0)
  })
})

describe('update mode', () => {
  const live = item(A, '제육 정식', { price_krw: 8000, price_verified_on: '2026-10-01', category: '식사', description_ko: '옛 설명', available: true, representative: true, recommended: true, sort_order: 3, image_url: 'https://x/p.png' })
  const state = { r1: { items: [live, item(B, '김치찌개', { price_krw: 7000, sort_order: 4 })], revision: 5, hasDraft: false } }

  it('changes only what the file states; photo, flags and order stay', () => {
    const p = plan(rows(`1001,,제육 정식,9000,,,,${A}`), state)
    const i = p.restaurants[0].items.find((x) => x.id === A)!
    expect(i).toMatchObject({ price_krw: 9000, category: '식사', description_ko: '옛 설명', available: true, representative: true, recommended: true, sort_order: 3, image_url: 'https://x/p.png' })
    expect(p.counts).toMatchObject({ update: 1, add: 0 })
    expect(p.rows[0].changes.map((c) => c.field)).toContain('가격')
  })

  it('a blank cell means "leave as it is": blank price does NOT clear a price, blank text does not erase', () => {
    const p = plan(rows(`1001,,제육 정식,,,,,${A}`), state)
    expect(p.counts).toMatchObject({ unchanged: 1, update: 0 })
    expect(p.restaurants[0].items.find((x) => x.id === A)!.price_krw).toBe(8000)
  })

  it('a changed price clears the old "price verified" date (it vouched for the OLD price); an unchanged price keeps it', () => {
    const changed = plan(rows(`1001,,제육 정식,9000,,,,${A}`), state)
    expect(changed.restaurants[0].items.find((x) => x.id === A)!.price_verified_on).toBeNull()
    expect(changed.rows[0].changes.map((c) => c.field)).toContain('가격 확인일')
    const same = plan(rows(`1001,,제육 정식,8000,식사,,,${A}`), state)
    expect(same.counts.unchanged).toBe(1)
    expect(same.restaurants[0].items.find((x) => x.id === A)!.price_verified_on).toBe('2026-10-01')
  })

  it('updates category, description and availability when stated', () => {
    const p = plan(rows(`1001,,제육 정식,,면류,새 설명,false,${A}`), state)
    expect(p.restaurants[0].items.find((x) => x.id === A)).toMatchObject({ category: '면류', description_ko: '새 설명', available: false, price_krw: 8000 })
    expect(p.rows[0].changes.map((c) => c.field).sort()).toEqual(['분류', '설명', '판매'])
  })

  it('without an id, a menu is matched by its exact name (case, spaces and Unicode form ignored)', () => {
    const p = plan(rows(`1001,,${'제육  정식'.normalize('NFD')},9100,,,,`), state)
    expect(p.counts).toMatchObject({ update: 1, add: 0 })
    expect(p.restaurants[0].items.find((x) => x.id === A)!.price_krw).toBe(9100)
  })

  it('a menu_id may rename a menu; a name match never renames', () => {
    const p = plan(rows(`1001,,돼지불백,,,,,${A}`), state)
    expect(p.restaurants[0].items.find((x) => x.id === A)!.name_ko).toBe('돼지불백')
    expect(p.rows[0].changes.map((c) => c.field)).toEqual(['이름'])
  })

  it('menus of the same restaurant that are not in the file stay exactly as they are (nothing is deleted or archived)', () => {
    const p = plan(rows(`1001,,제육 정식,9000,,,,${A}`), state)
    const items = p.restaurants[0].items
    expect(items).toHaveLength(2)
    expect(items.find((x) => x.id === B)).toEqual(state.r1.items[1])
    expect(items.every((x) => x.status === 'active')).toBe(true)
  })

  it('a menu that does not exist yet is added', () => {
    const p = plan(rows('1001,,우동,6000,,,,'), state)
    expect(p.counts).toMatchObject({ add: 1, update: 0 })
  })

  it('an ambiguous name (two menus with the same name) is flagged, not guessed', () => {
    const dup = { r1: { items: [item(A, '국수', { sort_order: 1 }), item(B, '국수', { sort_order: 2 })], revision: 1, hasDraft: false } }
    const p = plan(rows('1001,,국수,5000,,,,'), dup)
    expect(p.counts.invalid).toBe(1)
    expect(p.rows[0].messages.join(' ')).toMatch(/어느 것인지 알 수 없어요/)
    expect(p.restaurants[0].adds + p.restaurants[0].updates).toBe(0)
    // with the id it is unambiguous
    expect(plan(rows(`1001,,국수,5000,,,,${B}`), dup).counts.update).toBe(1)
  })

  it('an unknown menu_id is an error (it never creates a line with an arbitrary id)', () => {
    const p = plan(rows(`1001,,국수,5000,,,,${C}`), state)
    expect(p.counts.invalid).toBe(1)
    expect(p.rows[0].messages.join(' ')).toMatch(/이 식당에 없는 menu_id/)
    expect(p.restaurants[0].adds).toBe(0)
  })

  it('a menu_id that belongs to ANOTHER restaurant is refused and named as such (menus cannot be moved by import)', () => {
    const p = plan(rows(`1001,,돈코츠,9000,,,,${C}`), state, {}, { [C]: 'r2' })
    expect(p.counts.invalid).toBe(1)
    expect(p.rows[0].messages.join(' ')).toMatch(/다른 식당의 메뉴/)
    expect(p.restaurants[0].items.map((i) => i.id)).toEqual([A, B])
  })

  it('an archived menu is not changed by an import', () => {
    const arch = { r1: { items: [item(A, '단종 메뉴', { status: 'archived', price_krw: 1 })], revision: 1, hasDraft: false } }
    const p = plan(rows(`1001,,단종 메뉴,5000,,,,${A}`), arch)
    expect(p.counts.invalid).toBe(1)
    expect(p.rows[0].messages.join(' ')).toMatch(/보관된 메뉴/)
  })
})

describe('duplicates and invalid rows', () => {
  it('the same menu twice in one file: the first row counts, the second is a duplicate', () => {
    const p = plan(rows('1001,,국수,5000,,,,', '1001,,국수,6000,,,,', '1001,,  국수 ,7000,,,,'))
    expect(p.counts).toMatchObject({ add: 1, duplicate: 2 })
    expect(p.restaurants[0].items).toHaveLength(1)
    expect(p.restaurants[0].items[0].price_krw).toBe(5000)
  })
  it('the same name in two DIFFERENT restaurants is not a duplicate', () => {
    expect(plan(rows('1001,,국수,5000,,,,', '1002,,국수,5500,,,,')).counts).toMatchObject({ add: 2, duplicate: 0 })
  })
  it('a menu_id twice, or an id and a name pointing at the same line, are duplicates', () => {
    const s = { r1: { items: [item(A, '국수', { price_krw: 1 })], revision: 1, hasDraft: false } }
    const p = plan(rows(`1001,,국수,100,,,,${A}`, `1001,,국수,200,,,,${A}`, '1001,,국수,300,,,,'), s)
    expect(p.counts).toMatchObject({ update: 1, duplicate: 2 })
    expect(p.restaurants[0].items[0].price_krw).toBe(100)
  })
  it('invalid rows (bad price, missing name, bad id) are listed with the reason and import nothing; valid rows still import', () => {
    const p = plan(rows('1001,,국수,5000,,,,', '1001,,우동,abc,,,,', '1001,,,5000,,,,', '1001,,김밥,3000,,,maybe,', '1001,,라면,3000,,,,zzz'))
    expect(p.counts).toMatchObject({ rows: 5, add: 1, invalid: 4 })
    expect(p.restaurants[0].items.map((i) => i.name_ko)).toEqual(['국수'])
    expect(p.rows.filter((r) => r.action === 'invalid').every((r) => r.messages.length > 0)).toBe(true)
  })
  it('rows keep their file line numbers in the plan', () => {
    const p = plan(rows('1001,,국수,5000,,,,', '9999,,x,1,,,,', '1001,,우동,abc,,,,'))
    expect(p.rows.map((r) => [r.line, r.action])).toEqual([[2, 'add'], [3, 'unmatched'], [4, 'invalid']])
  })
})

// ---------------------------------------------------------------------------------------------------------------------
describe('saving drafts', () => {
  /** An in-memory stand-in for cms_state / cms_save_draft with a revision counter per restaurant. */
  function store(initial: Record<string, MenuState>, hooks: { failSave?: (id: string, n: number) => unknown; beforeSave?: (id: string) => void } = {}) {
    const state = new Map(Object.entries(initial).map(([k, v]) => [k, { ...v, items: v.items.map((i) => ({ ...i })) }]))
    const saves: { id: string; items: MenuItem[]; expected: number }[] = []
    const attempts = new Map<string, number>()
    const reads: string[] = []
    return {
      state, saves, reads, calls: { publish: 0 },
      deps: {
        sleep: async () => undefined,
        getState: async (id: string): Promise<MenuState> => { reads.push(id); const s = state.get(id) ?? { items: [], revision: 0, hasDraft: false }; return { ...s, items: s.items.map((i) => ({ ...i })) } },
        saveDraft: async (id: string, items: MenuItem[], expected: number) => {
          const n = (attempts.get(id) ?? 0) + 1; attempts.set(id, n)
          hooks.beforeSave?.(id)
          const f = hooks.failSave?.(id, n)
          if (f) throw f
          const cur = state.get(id) ?? { items: [], revision: 0, hasDraft: false }
          if (expected !== cur.revision) throw Object.assign(new Error('다른 관리자가 먼저 저장했어요'), { code: '40001' })
          saves.push({ id, items, expected })
          state.set(id, { items: items.map((i) => ({ ...i })), revision: cur.revision + 1, hasDraft: true })
          return { revision: cur.revision + 1 }
        },
      },
    }
  }
  const run = (csv: ReturnType<typeof rows>, st: ReturnType<typeof store>, o: Partial<PlanOptions> = {}, extra: Record<string, unknown> = {}) => {
    const initial: Record<string, MenuState> = {}
    for (const [k, v] of st.state) initial[k] = v
    const pl = plan(csv, initial, o)
    return { pl, go: () => applyPlan(pl, opts(o), new Map(), st.deps, extra as never) }
  }

  it('saves ONE draft per restaurant with the merged list, against the current draft revision', async () => {
    const st = store({ r1: { items: [item(A, '기존', { price_krw: 1 })], revision: 4, hasDraft: true } })
    const { go } = run(rows('1001,,새 메뉴,,,,,', '1002,,돈코츠,9000,,,,'), st)
    const res = await go()
    expect(res.failed).toEqual([])
    expect(res.saved.map((s) => [s.restaurantId, s.added, s.updated, s.revision])).toEqual([['r1', 1, 0, 5], ['r2', 1, 0, 1]])
    expect(st.saves.find((s) => s.id === 'r1')!.expected).toBe(4)
    expect(st.saves.find((s) => s.id === 'r1')!.items.map((i) => i.name_ko)).toEqual(['기존', '새 메뉴']) // existing kept
    expect(st.saves.find((s) => s.id === 'r2')!.expected).toBe(0)
  })

  it('writes nothing for restaurants without changes, and nothing for invalid rows', async () => {
    const st = store({ r1: { items: [item(A, '국수', { price_krw: 5000 })], revision: 1, hasDraft: false } })
    const { go } = run(rows('1001,,국수,5000,,,,', '1001,,우동,abc,,,,'), st)
    const res = await go()
    expect(st.saves).toEqual([])
    expect(res.saved).toEqual([])
    expect(res.untouched).toBe(1)
  })

  it('a failure of one restaurant (validation) does not stop the others; the failure names the restaurant and the reason', async () => {
    const bad = Object.assign(new Error('메뉴 이름이 너무 길어요'), { code: '22023' })
    const st = store({}, { failSave: (id) => (id === 'r1' ? bad : null) })
    const { go } = run(rows('1001,,국수,5000,,,,', '1002,,돈코츠,9000,,,,'), st)
    const res = await go()
    expect(res.saved.map((s) => s.restaurantId)).toEqual(['r2'])
    expect(res.failed).toEqual([{ restaurantId: 'r1', name: '어굿플레이스', message: '메뉴 이름이 너무 길어요', code: '22023' }])
  })

  it('a conflict (another admin saved first) is re-planned against THEIR draft and retried: their menus survive', async () => {
    let once = true
    const st = store({ r1: { items: [item(A, '기존')], revision: 1, hasDraft: true } }, {
      beforeSave: (id) => { if (once && id === 'r1') { once = false; st.state.set('r1', { items: [item(A, '기존'), item(B, '동료가 방금 추가', { sort_order: 2 })], revision: 2, hasDraft: true }) } },
    })
    const { go } = run(rows('1001,,내 메뉴,,,,,'), st)
    const res = await go()
    expect(res.failed).toEqual([])
    const names = st.state.get('r1')!.items.map((i) => i.name_ko)
    expect(names).toEqual(['기존', '동료가 방금 추가', '내 메뉴'])
    expect(st.state.get('r1')!.revision).toBe(3)
  })

  it('repeating the same import changes nothing (no second copy of any menu)', async () => {
    const st = store({})
    const csv = rows('1001,,국수,5000,,,,', '1001,,우동,,,,,')
    const first = await run(csv, st).go()
    expect(first.saved[0].added).toBe(2)
    const again = await run(csv, st).go() // the lists now contain those menus
    expect(again.saved).toEqual([])
    expect(again.untouched).toBe(1)
    expect(st.state.get('r1')!.items).toHaveLength(2)
    // and in append mode the repeat is all duplicates
    const append = run(csv, st, { mode: 'append' })
    expect(append.pl.counts).toMatchObject({ duplicate: 2, add: 0 })
  })

  it('a dropped connection is retried, then succeeds', async () => {
    const st = store({}, { failSave: (_id, n) => (n === 1 ? new TypeError('Failed to fetch') : null) })
    const res = await run(rows('1001,,국수,5000,,,,'), st).go()
    expect(res.saved).toHaveLength(1)
    expect(res.failed).toEqual([])
  })

  it('a permission error stops the whole run', async () => {
    const denied = Object.assign(new Error('permission denied'), { code: '42501' })
    const st = store({}, { failSave: () => denied })
    const csv = rows('1001,,국수,5000,,,,', '1002,,돈코츠,9000,,,,')
    const res = await run(csv, st).go()
    expect(res.stoppedBy).toBe('forbidden')
    expect(res.saved).toEqual([])
    expect(res.failed.length).toBeGreaterThan(0)
  })

  it('retrying only the failed restaurants leaves the saved ones alone', async () => {
    let broken = true
    const st = store({}, { failSave: (id) => (broken && id === 'r2' ? Object.assign(new Error('x'), { code: '22023' }) : null) })
    const { pl } = run(rows('1001,,국수,5000,,,,', '1002,,돈코츠,9000,,,,'), st)
    const first = await applyPlan(pl, opts(), new Map(), st.deps)
    expect(first.failed.map((f) => f.restaurantId)).toEqual(['r2'])
    broken = false
    const before = st.saves.length
    const second = await applyPlan(pl, opts(), new Map(), st.deps, { only: new Set(['r2']) })
    expect(second.saved.map((s) => s.restaurantId)).toEqual(['r2'])
    expect(st.saves.length - before).toBe(1)
  })

  it('cancelling stops before the next restaurant', async () => {
    const ctl = new AbortController()
    const st = store({}, { beforeSave: () => ctl.abort() })
    const res = await run(rows('1001,,국수,5000,,,,', '1002,,돈코츠,9000,,,,'), st).go.call(null).then(() => applyPlan(plan(rows('1001,,a,,,,,', '1002,,b,,,,,')), opts(), new Map(), store({}, { beforeSave: () => ctl.abort() }).deps, { signal: ctl.signal, concurrency: 1 }))
    expect(res.stoppedBy).toBe('cancelled')
    expect(res.saved.length).toBeLessThan(2)
  })

  it('never publishes and never touches a restaurant: the only calls are reading the state and saving a draft', async () => {
    const st = store({})
    const touched: string[] = []
    const deps = { ...st.deps, getState: async (id: string) => { touched.push(`get:${id}`); return st.deps.getState(id) }, saveDraft: async (id: string, items: MenuItem[], r: number) => { touched.push(`save:${id}`); return st.deps.saveDraft(id, items, r) } }
    const pl = plan(rows('1001,,국수,5000,,,,'))
    await applyPlan(pl, opts(), new Map(), deps)
    expect(touched).toEqual(['get:r1', 'save:r1'])
  })
})

describe('publishing what was imported (optional, via the existing publish function only)', () => {
  const saved = [
    { restaurantId: 'r1', name: '어굿플레이스', added: 1, updated: 0, revision: 5, hadDraft: false },
    { restaurantId: 'r2', name: '라멘집', added: 2, updated: 1, revision: 2, hadDraft: true },
  ]
  it('publishes each saved draft at the revision this import saved, with the reason', async () => {
    const calls: [string, number, string][] = []
    const res = await publishSaved(saved, '개강 메뉴', { publish: async (id, rev, reason) => { calls.push([id, rev, reason]) } })
    expect(res.published.sort()).toEqual(['r1', 'r2'])
    expect(calls.sort()).toEqual([['r1', 5, '개강 메뉴'], ['r2', 2, '개강 메뉴']])
  })
  it('a conflict on one restaurant (its draft changed since) fails only that one', async () => {
    const res = await publishSaved(saved, 'x', { publish: async (id) => { if (id === 'r2') throw Object.assign(new Error('초안이 바뀌었어요'), { code: '40001' }) } })
    expect(res.published).toEqual(['r1'])
    expect(res.failed).toEqual([{ restaurantId: 'r2', name: '라멘집', message: '초안이 바뀌었어요', code: '40001' }])
  })
  it('a permission error stops the run', async () => {
    const res = await publishSaved(saved, 'x', { publish: async () => { throw Object.assign(new Error('denied'), { code: '42501' }) } }, { concurrency: 1 })
    expect(res.stoppedBy).toBe('forbidden')
    expect(res.published).toEqual([])
  })
})

describe('planRestaurant is deterministic for a given state (what makes a retry safe)', () => {
  it('same rows against the same list give the same merged list', () => {
    const csv = rows('1001,,국수,5000,,,,', '1001,,우동,,,,,').map((row) => ({ row, messages: [] as string[] }))
    const a = planRestaurant(R1, empty, csv, new Map(), opts({ newId: () => 'id' }))
    const b = planRestaurant(R1, empty, csv, new Map(), opts({ newId: () => 'id' }))
    expect(a.items).toEqual(b.items)
  })
})
