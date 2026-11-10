import { describe, expect, it } from 'vitest'
import { normalizeOrders, addOption, applyHours, bulkPatch, changedDates, copyDay, copyWeek, mealsIn, mondayOf, newOption, prepareForSave, removeMeal, renameOption, slotKey, sortMeals, updateExtra, updateMeal, validateWeek, weekCounts, weekDates, type WeekMeal } from './week'

const TODAY = '2026-11-10'
const meal = (date: string, type: WeekMeal['meal_type'], over: Partial<WeekMeal> = {}): WeekMeal => ({
  date, meal_type: type, option_name: '', option_order: 0, menu_items: [{ name_ko: `${type} ${date}`, kind: 'main' }], price_krw: 5500,
  start_time: '11:30', end_time: '13:30', status: 'published', badge: null, source_url: null, verified_at: '2026-11-09T00:00:00+09:00', extra: {}, ...over,
})
const WEEK = ['2026-11-09', '2026-11-10', '2026-11-11', '2026-11-12', '2026-11-13']
const full = () => WEEK.flatMap((d) => (['breakfast', 'lunch', 'dinner'] as const).map((t) => meal(d, t)))

describe('week geometry', () => {
  it('a week is Monday-based, Monday-Friday by default, seven days for a cafeteria that opens at weekends', () => {
    expect(mondayOf('2026-11-15')).toBe('2026-11-09') // a Sunday belongs to the Monday before
    expect(weekDates('2026-11-09', false)).toEqual(WEEK)
    expect(weekDates('2026-11-09', true)).toEqual([...WEEK, '2026-11-14', '2026-11-15'])
  })
  it('15 slots for 5 days x 3 meal periods', () => {
    const c = weekCounts(full())
    expect(c).toMatchObject({ menus: 15, days: 5, slots: 15, thousandWon: 0 })
  })
  it('keeps the database order (date, breakfast-lunch-dinner, option order, name)', () => {
    const shuffled = [meal('2026-11-10', 'dinner'), meal('2026-11-09', 'lunch', { option_name: 'B', option_order: 1 }), meal('2026-11-09', 'lunch'), meal('2026-11-09', 'breakfast')]
    expect(sortMeals(shuffled).map(slotKey)).toEqual(['2026-11-09|breakfast|', '2026-11-09|lunch|', '2026-11-09|lunch|B', '2026-11-10|dinner|'])
  })
})

describe('option order', () => {
  it('is renumbered 0, 1, 2 per (date, meal) so a rename never reorders the options', () => {
    const ms = [meal('2026-11-09', 'lunch', { option_name: 'Z', option_order: 5 }), meal('2026-11-09', 'lunch', { option_name: 'A', option_order: 5 }), meal('2026-11-09', 'dinner', { option_order: 3 })]
    const out = normalizeOrders(ms)
    expect(out.filter((m) => m.meal_type === 'lunch').map((m) => [m.option_name, m.option_order])).toEqual([['A', 0], ['Z', 1]])
    expect(out.find((m) => m.meal_type === 'dinner')!.option_order).toBe(0)
    const renamed = normalizeOrders(out.map((m) => (m.option_name === 'A' ? { ...m, option_name: 'ZZ' } : m)))
    expect(renamed.filter((m) => m.meal_type === 'lunch').map((m) => m.option_name)).toEqual(['ZZ', 'Z']) // same positions: A stayed first
  })
})

describe('options', () => {
  it('several options for one meal never overwrite each other', () => {
    let ms = [meal('2026-11-09', 'lunch')]
    ms = addOption(ms, '2026-11-09', 'lunch', TODAY)
    ms = addOption(ms, '2026-11-09', 'lunch', TODAY)
    expect(mealsIn(ms, '2026-11-09', 'lunch').map((m) => m.option_name)).toEqual(['', '옵션 2', '옵션 3'])
    expect(mealsIn(ms, '2026-11-09', 'lunch').map((m) => m.option_order)).toEqual([0, 1, 2])
  })
  it('a new option inherits the previous option\'s serving time and starts blank (and unpublishable until filled)', () => {
    const o = newOption([meal('2026-11-09', 'lunch')], '2026-11-09', 'lunch', TODAY)
    expect(o).toMatchObject({ start_time: '11:30', end_time: '13:30', menu_items: [], price_krw: null, badge: null })
    expect(validateWeek([o]).map((e) => e.message).join()).toMatch(/메뉴를 한 줄 이상/)
  })
  it('renaming refuses a name that is already taken in the same slot', () => {
    const ms = [meal('2026-11-09', 'lunch'), meal('2026-11-09', 'lunch', { option_name: 'B', option_order: 1 })]
    expect(renameOption(ms, '2026-11-09|lunch|', 'B')).toBe(ms)
    expect(renameOption(ms, '2026-11-09|lunch|B', 'C').map((m) => m.option_name)).toEqual(['', 'C'])
  })
  it('updates and removes exactly one option', () => {
    const ms = full()
    expect(updateMeal(ms, '2026-11-10|lunch|', { price_krw: 6000 }).filter((m) => m.price_krw === 6000)).toHaveLength(1)
    expect(removeMeal(ms, '2026-11-10|lunch|')).toHaveLength(14)
  })
  it('extra: empty values are dropped, not stored', () => {
    const ms = updateExtra([meal('2026-11-09', 'lunch')], '2026-11-09|lunch|', { notice: '품절 주의', sold_out: true, description: '' })
    expect(ms[0].extra).toEqual({ notice: '품절 주의', sold_out: true })
    expect(updateExtra(ms, '2026-11-09|lunch|', { sold_out: false, notice: '' })[0].extra).toEqual({})
  })
})

describe('copy and bulk tools', () => {
  it('copies one day onto other days, filling only EMPTY slots by default', () => {
    const ms = [...WEEK.slice(0, 1).flatMap((d) => (['breakfast', 'lunch', 'dinner'] as const).map((t) => meal(d, t))), meal('2026-11-10', 'lunch', { menu_items: [{ name_ko: '기존 점심' }] })]
    const out = copyDay(ms, '2026-11-09', ['2026-11-10', '2026-11-11'], { today: TODAY })
    expect(mealsIn(out, '2026-11-10', 'lunch')[0].menu_items[0].name_ko).toBe('기존 점심') // not overwritten
    expect(mealsIn(out, '2026-11-10', 'breakfast')).toHaveLength(1)
    expect(out.filter((m) => m.date === '2026-11-11')).toHaveLength(3)
  })
  it('overwrite replaces the target day (the editor asks for confirmation first)', () => {
    const ms = [meal('2026-11-09', 'lunch'), meal('2026-11-10', 'dinner')]
    const out = copyDay(ms, '2026-11-09', ['2026-11-10'], { overwrite: true, today: TODAY })
    expect(out.filter((m) => m.date === '2026-11-10').map((m) => m.meal_type)).toEqual(['lunch'])
  })
  it('does not copy the 천원의 아침밥 programme, its source, sold-out flags or photos: they belong to one date', () => {
    const src = meal('2026-11-09', 'breakfast', { badge: '천원의 아침밥', source_url: 'https://e.org/a', price_krw: 1000, extra: { sold_out: true, photo_url: 'https://x/p.jpg', photo_path: 'a', notice: '공지' } })
    const out = copyDay([src], '2026-11-09', ['2026-11-10'], { today: TODAY })
    const copy = mealsIn(out, '2026-11-10', 'breakfast')[0]
    expect(copy).toMatchObject({ badge: null, source_url: null, price_krw: 1000, verified_at: '2026-11-10T00:00:00+09:00' })
    expect(copy.extra).toEqual({ notice: '공지' })
  })
  it('copies a previous week forward, shifting every date by seven days', () => {
    const prev = [meal('2026-11-02', 'lunch'), meal('2026-11-06', 'dinner'), meal('2026-11-07', 'lunch')]
    const out = copyWeek([], prev, '2026-11-02', '2026-11-09', { today: TODAY })
    expect(out.map(slotKey)).toEqual(['2026-11-09|lunch|', '2026-11-13|dinner|', '2026-11-14|lunch|'])
  })
  it('copy-week keeps what is already there unless told to overwrite', () => {
    const here = [meal('2026-11-09', 'lunch', { menu_items: [{ name_ko: '이번 주 점심' }] })]
    const keep = copyWeek(here, [meal('2026-11-02', 'lunch'), meal('2026-11-03', 'lunch')], '2026-11-02', '2026-11-09', { today: TODAY })
    expect(keep).toHaveLength(2)
    expect(mealsIn(keep, '2026-11-09', 'lunch')[0].menu_items[0].name_ko).toBe('이번 주 점심')
    expect(copyWeek(here, [meal('2026-11-03', 'dinner')], '2026-11-02', '2026-11-09', { overwrite: true, today: TODAY }).map(slotKey)).toEqual(['2026-11-10|dinner|'])
  })
  it('applies common operating hours to the chosen weekdays and meal periods only', () => {
    const out = applyHours(full(), WEEK.slice(0, 3), ['lunch'], '12:00', '14:00')
    expect(out.filter((m) => m.start_time === '12:00')).toHaveLength(3)
    expect(out.filter((m) => m.start_time === '12:00').every((m) => m.meal_type === 'lunch' && WEEK.slice(0, 3).includes(m.date))).toBe(true)
  })
  it('bulk-edits the selected cells only', () => {
    const out = bulkPatch(full(), ['2026-11-09|lunch|', '2026-11-10|lunch|'], { price_krw: 6500 })
    expect(out.filter((m) => m.price_krw === 6500)).toHaveLength(2)
  })
})

describe('blank cells never erase; the editor asks explicitly', () => {
  it('a brand-new blank option is simply not saved', () => {
    const ms = [meal('2026-11-09', 'lunch'), { ...newOption([], '2026-11-10', 'lunch', TODAY) }]
    const { meals, errors } = prepareForSave(ms, new Set(['2026-11-09|lunch|']))
    expect(meals.map(slotKey)).toEqual(['2026-11-09|lunch|'])
    expect(errors).toEqual([])
  })
  it('an EXISTING menu that was emptied is an error until it is removed explicitly', () => {
    const ms = [meal('2026-11-09', 'lunch', { menu_items: [] })]
    const { errors } = prepareForSave(ms, new Set(['2026-11-09|lunch|']))
    expect(errors[0].message).toMatch(/이 메뉴 삭제/)
  })
  it('marking a meal closed needs no items (it is an explicit state)', () => {
    expect(validateWeek([meal('2026-11-09', 'lunch', { status: 'closed', menu_items: [] })])).toEqual([])
  })
})

describe('validation (mirrors the server)', () => {
  const bad = (over: Partial<WeekMeal>) => validateWeek([meal('2026-11-09', 'breakfast', over)]).map((e) => e.message).join('|')
  it('prices, times and sources', () => {
    expect(bad({ price_krw: -1 })).toMatch(/가격/)
    expect(bad({ price_krw: 1.5 })).toMatch(/가격/)
    expect(bad({ start_time: '25:00', end_time: '26:00' })).toMatch(/HH:MM/)
    expect(bad({ start_time: '10:00', end_time: '09:00' })).toMatch(/종료는 시작보다/)
    expect(bad({ start_time: '10:00', end_time: null })).toMatch(/함께/)
    expect(bad({ source_url: 'http://x' })).toMatch(/https/)
  })
  it('천원의 아침밥: breakfast only, and only with an official source', () => {
    expect(bad({ badge: '천원의 아침밥' })).toMatch(/출처/)
    expect(bad({ badge: '천원의 아침밥', source_url: 'https://e.org' })).toBe('')
    expect(validateWeek([meal('2026-11-09', 'lunch', { badge: '천원의 아침밥', source_url: 'https://e.org' })]).map((e) => e.message).join()).toMatch(/조식에만/)
  })
  it('duplicate options and long names', () => {
    expect(validateWeek([meal('2026-11-09', 'lunch'), meal('2026-11-09', 'lunch')]).map((e) => e.message).join()).toMatch(/두 번/)
    expect(bad({ option_name: 'x'.repeat(41) })).toMatch(/40자/)
  })
  it('Korean text is fine, a full week with 천원의 아침밥 on ONE date is valid', () => {
    const ms = full().map((m) => (m.date === '2026-11-09' && m.meal_type === 'breakfast' ? { ...m, badge: '천원의 아침밥', source_url: 'https://e.org/1000', price_krw: 1000 } : m))
    expect(validateWeek(ms)).toEqual([])
    expect(weekCounts(ms).thousandWon).toBe(1)
  })
})

describe('which days changed', () => {
  it('lists only the dates whose menus differ (the default selection for publishing selected days)', () => {
    const live = full()
    const draft = updateMeal(updateMeal(live, '2026-11-10|lunch|', { price_krw: 6000 }), '2026-11-12|dinner|', { price_krw: 6100 })
    expect(changedDates(live, draft)).toEqual(['2026-11-10', '2026-11-12'])
    expect(changedDates(live, live)).toEqual([])
    expect(changedDates(live, removeMeal(live, '2026-11-13|breakfast|'))).toEqual(['2026-11-13'])
  })
})
