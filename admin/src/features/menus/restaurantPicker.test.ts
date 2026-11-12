import { describe, expect, it } from 'vitest'
import { buildView, NO_UNIVERSITY, toPickerRestaurant, universityCounts, UNASSIGNED_LABEL, type PickerFilters, type PickerRestaurant } from './restaurantPicker'

const U = [{ id: 'u2', name_ko: '한국대학교' }, { id: 'u1', name_ko: '가나대학교' }]
const R = (id: string, name: string, universityIds: string[], over: Partial<PickerRestaurant> = {}): PickerRestaurant =>
  ({ id, name_ko: name, category: null, visibility: 'draft', universityIds, ...over })
const none: PickerFilters = { search: '', university: '', menu: '' }
const names = (v: ReturnType<typeof buildView>, key: string) => v.groups.find((g) => g.key === key)?.restaurants.map((r) => r.name_ko)

const LIST = [
  R('a', '다식당', ['u1']), R('b', '가식당', ['u1']), R('c', '나식당', ['u2']),
  R('d', '둘다식당', ['u1', 'u2']), R('e', '무소속식당', []),
]

describe('toPickerRestaurant', () => {
  it('reads the embedded school links, drops blanks and duplicates, and tolerates missing fields', () => {
    expect(toPickerRestaurant({ id: 'x', name_ko: '집', category: '한식', visibility: 'published', restaurant_university_links: [{ university_id: 'u1' }, { university_id: 'u1' }, { university_id: null }, {}] }))
      .toEqual({ id: 'x', name_ko: '집', category: '한식', visibility: 'published', universityIds: ['u1'] })
    expect(toPickerRestaurant({ id: 'y' })).toEqual({ id: 'y', name_ko: '', category: null, visibility: null, universityIds: [] })
    expect(toPickerRestaurant({ id: 'z', visibility: 'weird', restaurant_university_links: null }).visibility).toBeNull()
  })
})

describe('buildView: organised by school', () => {
  it('groups by school in name order, restaurants by name, and unassigned ones last', () => {
    const v = buildView(LIST, U, new Map(), none)
    expect(v.groups.map((g) => g.name)).toEqual(['가나대학교', '한국대학교', UNASSIGNED_LABEL])
    expect(names(v, 'u1')).toEqual(['가식당', '다식당', '둘다식당'])
    expect(names(v, 'u2')).toEqual(['나식당', '둘다식당'])
    expect(names(v, NO_UNIVERSITY)).toEqual(['무소속식당'])
  })

  it('lists every restaurant once in the total even when it appears under two schools; none is lost', () => {
    const v = buildView(LIST, U, new Map(), none)
    expect(v.total).toBe(5)
    expect(v.ids.sort()).toEqual(['a', 'b', 'c', 'd', 'e'])
    expect(v.groups.flatMap((g) => g.restaurants).length).toBe(6) // 둘다식당 twice
  })

  it('a link to a school that is not in the list does not hide the restaurant: it counts as unassigned', () => {
    const v = buildView([R('z', '고아식당', ['gone'])], U, new Map(), none)
    expect(names(v, NO_UNIVERSITY)).toEqual(['고아식당'])
    expect(universityCounts([R('z', '고아식당', ['gone'])], U).unassigned).toBe(1)
  })

  it('no schools at all: everything is under unassigned', () => {
    const v = buildView(LIST, [], new Map(), none)
    expect(v.groups.map((g) => g.key)).toEqual([NO_UNIVERSITY])
    expect(v.total).toBe(5)
  })

  it('an empty list gives an empty view', () => {
    expect(buildView([], U, new Map(), none)).toEqual({ groups: [], ids: [], total: 0, withMenu: 0, withoutMenu: 0 })
  })
})

describe('buildView: filters', () => {
  it('one school: only its restaurants, including the shared one', () => {
    const v = buildView(LIST, U, new Map(), { ...none, university: 'u2' })
    expect(v.groups.map((g) => g.key)).toEqual(['u2'])
    expect(v.ids.sort()).toEqual(['c', 'd'])
  })

  it('unassigned only', () => {
    const v = buildView(LIST, U, new Map(), { ...none, university: NO_UNIVERSITY })
    expect(v.ids).toEqual(['e'])
  })

  it('search matches the name or the category, ignoring case and spaces around it', () => {
    const list = [R('a', 'Burger House', ['u1'], { category: '양식' }), R('b', '김밥천국', ['u1'], { category: '분식' })]
    expect(buildView(list, U, new Map(), { ...none, search: '  burger ' }).ids).toEqual(['a'])
    expect(buildView(list, U, new Map(), { ...none, search: '분식' }).ids).toEqual(['b'])
    expect(buildView(list, U, new Map(), { ...none, search: '없는이름' }).total).toBe(0)
  })

  it('menu filter: with / without active menus; the counts add up', () => {
    const counts = new Map([['a', 2], ['c', 1]])
    const all = buildView(LIST, U, counts, none)
    expect([all.withMenu, all.withoutMenu]).toEqual([2, 3])
    expect(buildView(LIST, U, counts, { ...none, menu: 'has' }).ids.sort()).toEqual(['a', 'c'])
    expect(buildView(LIST, U, counts, { ...none, menu: 'none' }).ids.sort()).toEqual(['b', 'd', 'e'])
    expect(all.groups.find((g) => g.key === 'u1')!.withMenu).toBe(1)
  })

  it('a zero count means no menu', () => {
    expect(buildView([R('a', '가', ['u1'])], U, new Map([['a', 0]]), { ...none, menu: 'none' }).total).toBe(1)
  })

  it('filters combine', () => {
    const v = buildView(LIST, U, new Map([['a', 1]]), { search: '식당', university: 'u1', menu: 'none' })
    expect(v.ids.sort()).toEqual(['b', 'd'])
  })
})

describe('universityCounts', () => {
  it('counts per school (a shared restaurant counts for both) and the unassigned ones', () => {
    const c = universityCounts(LIST, U)
    expect(c.byUniversity.get('u1')).toBe(3)
    expect(c.byUniversity.get('u2')).toBe(2)
    expect(c.unassigned).toBe(1)
  })
  it('a school with no restaurants shows 0', () => {
    expect(universityCounts([], U).byUniversity.get('u1')).toBe(0)
  })
})
