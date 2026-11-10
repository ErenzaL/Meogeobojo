/** Pure logic of the weekly menu editor: one cafeteria x one Monday-based week as ONE value.
 *  Everything here returns new arrays (no mutation) so the editor can keep a working copy and
 *  save it as a single draft. The server validates again; these checks only give early, readable errors. */
import { addDays, DAY, MEAL_TYPES, seoulToday, THOUSAND_WON_BADGE, weekStart } from './meal'

export type MealPeriod = (typeof MEAL_TYPES)[number]
export type MenuLine = { name_ko: string; kind?: string }
export type WeekExtra = { description?: string; notice?: string; sold_out?: boolean; photo_url?: string; photo_path?: string; [k: string]: unknown }
export type MealStatus = 'published' | 'closed' | 'no_menu'
export type WeekMeal = {
  date: string; meal_type: MealPeriod; option_name: string; option_order: number; menu_items: MenuLine[]
  price_krw: number | null; start_time: string | null; end_time: string | null; status: MealStatus
  badge: string | null; source_url: string | null; verified_at: string; extra: WeekExtra
}
export type WeekSnapshot = { meals: WeekMeal[] }

export const mondayOf = weekStart
export const slotKey = (m: Pick<WeekMeal, 'date' | 'meal_type' | 'option_name'>) => `${m.date}|${m.meal_type}|${m.option_name}`
export const dayName = (iso: string) => DAY[(new Date(`${iso}T00:00:00Z`).getUTCDay() + 6) % 7]
/** Monday to Friday, plus Saturday and Sunday when [weekend] (a cafeteria that opens at weekends). */
export const weekDates = (monday: string, weekend: boolean) => Array.from({ length: weekend ? 7 : 5 }, (_, i) => addDays(monday, i))
export const isWeekend = (iso: string) => ['토', '일'].includes(dayName(iso))

const rank = (t: string) => MEAL_TYPES.indexOf(t as MealPeriod)
/** The database's canonical order, so an unchanged week compares equal to what is live. */
export const sortMeals = (ms: WeekMeal[]) =>
  [...ms].sort((a, b) => a.date.localeCompare(b.date) || rank(a.meal_type) - rank(b.meal_type) || a.option_order - b.option_order || (a.option_name < b.option_name ? -1 : a.option_name > b.option_name ? 1 : 0))
/** Option order is 0, 1, 2 ... within every (date, meal) in the current order: unique and stable, so renaming an option can never
 *  reorder the options or change which card is which. */
export function normalizeOrders(ms: WeekMeal[]): WeekMeal[] {
  const seen = new Map<string, number>()
  return sortMeals(ms).map((m) => { const k = `${m.date}|${m.meal_type}`; const n = seen.get(k) ?? 0; seen.set(k, n + 1); return m.option_order === n ? m : { ...m, option_order: n } })
}
export const mealsIn = (ms: WeekMeal[], date: string, type: MealPeriod) => sortMeals(ms.filter((m) => m.date === date && m.meal_type === type))

export const parseLines = (text: string): MenuLine[] =>
  text.split('\n').map((l) => l.trim()).filter(Boolean).map((name_ko, i) => ({ name_ko, kind: i === 0 ? 'main' : 'side' }))
export const linesToText = (items: MenuLine[]) => items.map((i) => i.name_ko).join('\n')

const stamp = (today = seoulToday()) => `${today}T00:00:00+09:00`

/** A new, still blank option for a slot. The first option has an empty name, the next ones get a free "옵션 N" name. */
export function newOption(ms: WeekMeal[], date: string, type: MealPeriod, today = seoulToday()): WeekMeal {
  const here = ms.filter((m) => m.date === date && m.meal_type === type)
  let name = ''
  for (let n = 2; here.some((m) => m.option_name === name); n++) name = `옵션 ${n}`
  const prev = sortMeals(here).at(-1)
  return {
    date, meal_type: type, option_name: name, option_order: here.length, menu_items: [], price_krw: null,
    start_time: prev?.start_time ?? null, end_time: prev?.end_time ?? null, status: 'published', badge: null, source_url: null, verified_at: stamp(today), extra: {},
  }
}

export const addOption = (ms: WeekMeal[], date: string, type: MealPeriod, today?: string) => [...ms, newOption(ms, date, type, today)]
export const updateMeal = (ms: WeekMeal[], key: string, patch: Partial<WeekMeal>) => ms.map((m) => (slotKey(m) === key ? { ...m, ...patch } : m))
export const updateExtra = (ms: WeekMeal[], key: string, patch: Partial<WeekExtra>) =>
  ms.map((m) => {
    if (slotKey(m) !== key) return m
    const extra = { ...m.extra, ...patch }
    for (const k of Object.keys(extra)) if (extra[k] === undefined || extra[k] === '' || extra[k] === false) delete extra[k]
    return { ...m, extra }
  })
export const removeMeal = (ms: WeekMeal[], key: string) => ms.filter((m) => slotKey(m) !== key)

/** Renaming an option must not collide with another option of the same slot. */
export const renameOption = (ms: WeekMeal[], key: string, name: string) => {
  const me = ms.find((m) => slotKey(m) === key)
  if (!me) return ms
  if (ms.some((m) => m !== me && m.date === me.date && m.meal_type === me.meal_type && m.option_name === name)) return ms
  return updateMeal(ms, key, { option_name: name })
}

/** Copies one day's menus onto other days. By default only EMPTY slots of the target are filled; [overwrite] replaces the
 *  target day's menus (the caller asks for confirmation first). The 천원의 아침밥 programme and its source belong to a date, so
 *  they are not copied; sold-out flags and photos are not copied either. */
export function copyDay(ms: WeekMeal[], from: string, to: string[], opts: { overwrite?: boolean; today?: string } = {}): WeekMeal[] {
  const source = sortMeals(ms.filter((m) => m.date === from))
  let out = ms
  for (const target of to.filter((t) => t !== from)) {
    if (opts.overwrite) out = out.filter((m) => m.date !== target)
    for (const type of MEAL_TYPES) {
      if (out.some((m) => m.date === target && m.meal_type === type)) continue
      for (const s of source.filter((m) => m.meal_type === type)) {
        const { photo_url: _p, photo_path: _pp, sold_out: _s, ...extra } = s.extra
        void _p; void _pp; void _s
        out = [...out, { ...s, date: target, badge: null, source_url: null, verified_at: stamp(opts.today), extra }]
      }
    }
  }
  return out
}

/** Copies a whole earlier (or later) week onto [thisMonday], shifting every date. Fills empty slots unless [overwrite]. */
export function copyWeek(ms: WeekMeal[], other: WeekMeal[], otherMonday: string, thisMonday: string, opts: { overwrite?: boolean; today?: string } = {}): WeekMeal[] {
  const shift = Math.round((new Date(`${thisMonday}T00:00:00Z`).getTime() - new Date(`${otherMonday}T00:00:00Z`).getTime()) / 86400000)
  let out = opts.overwrite ? [] : ms
  for (const s of sortMeals(other)) {
    const date = addDays(s.date, shift)
    if (out.some((m) => m.date === date && m.meal_type === s.meal_type)) continue
    const { photo_url: _p, photo_path: _pp, sold_out: _s, ...extra } = s.extra
    void _p; void _pp; void _s
    out = [...out, { ...s, date, badge: null, source_url: null, verified_at: stamp(opts.today), extra }]
  }
  return out
}

/** One serving time for the chosen weekdays and meal periods (blank on either side clears nothing). */
export function applyHours(ms: WeekMeal[], dates: string[], periods: MealPeriod[], start: string, end: string): WeekMeal[] {
  return ms.map((m) => (dates.includes(m.date) && periods.includes(m.meal_type) ? { ...m, start_time: start, end_time: end } : m))
}
export const bulkPatch = (ms: WeekMeal[], keys: string[], patch: Partial<WeekMeal>) => ms.map((m) => (keys.includes(slotKey(m)) ? { ...m, ...patch } : m))

/** What leaves the editor: brand-new options that were never filled in are dropped (a blank cell changes nothing); an EXISTING
 *  option that was emptied is an error until the admin removes it explicitly. */
export function prepareForSave(ms: WeekMeal[], liveKeys: Set<string>): { meals: WeekMeal[]; errors: { key: string; message: string }[] } {
  const errors: { key: string; message: string }[] = []
  const meals = ms.filter((m) => {
    const blank = m.status === 'published' && m.menu_items.length === 0
    if (blank && !liveKeys.has(slotKey(m))) return false
    if (blank) errors.push({ key: slotKey(m), message: `${m.date} ${mealWord(m.meal_type)}: 메뉴를 비우려면 '이 메뉴 삭제'를 눌러 주세요` })
    return true
  })
  return { meals: sortMeals(meals), errors }
}
const mealWord = (t: string) => ({ breakfast: '조식', lunch: '중식', dinner: '석식' })[t] ?? t

const TIME = /^([01]\d|2[0-3]):[0-5]\d$/
export function validateWeek(ms: WeekMeal[]): { key: string; message: string }[] {
  const out: { key: string; message: string }[] = []
  const seen = new Set<string>()
  for (const m of ms) {
    const key = slotKey(m)
    const where = `${m.date} ${mealWord(m.meal_type)}${m.option_name ? ` (${m.option_name})` : ''}`
    if (seen.has(key)) out.push({ key, message: `${where}: 같은 옵션 이름이 두 번 있어요` })
    seen.add(key)
    if (m.option_name.length > 40) out.push({ key, message: `${where}: 옵션 이름은 40자 이하여야 해요` })
    if (m.status === 'published' && m.menu_items.length === 0) out.push({ key, message: `${where}: 공개하려면 메뉴를 한 줄 이상 적어 주세요` })
    if (m.price_krw != null && (!Number.isInteger(m.price_krw) || m.price_krw < 0)) out.push({ key, message: `${where}: 가격은 0 이상의 정수여야 해요` })
    if ((m.start_time && !TIME.test(m.start_time)) || (m.end_time && !TIME.test(m.end_time))) out.push({ key, message: `${where}: 시간은 HH:MM 형식이에요` })
    else if (m.start_time && m.end_time && m.start_time >= m.end_time) out.push({ key, message: `${where}: 종료는 시작보다 늦어야 해요` })
    else if (!!m.start_time !== !!m.end_time) out.push({ key, message: `${where}: 시작과 종료 시간을 함께 적어 주세요` })
    if (m.source_url && !/^https:\/\//.test(m.source_url)) out.push({ key, message: `${where}: 출처 주소는 https:// 로 시작해야 해요` })
    if (m.badge === THOUSAND_WON_BADGE) {
      if (m.meal_type !== 'breakfast') out.push({ key, message: `${where}: 천원의 아침밥은 조식에만 쓸 수 있어요` })
      if (!m.source_url) out.push({ key, message: `${where}: 천원의 아침밥은 공식 출처 주소가 필요해요` })
    }
  }
  return out
}

/** Dates whose menus differ between the live week and the draft (the default selection of "게시할 날짜"). */
export function changedDates(live: WeekMeal[], draft: WeekMeal[]): string[] {
  const group = (ms: WeekMeal[]) => {
    const g = new Map<string, string>()
    for (const d of new Set(ms.map((m) => m.date))) g.set(d, JSON.stringify(sortMeals(ms.filter((m) => m.date === d))))
    return g
  }
  const a = group(live), b = group(draft)
  return [...new Set([...a.keys(), ...b.keys()])].filter((d) => a.get(d) !== b.get(d)).sort()
}

export const weekCounts = (ms: WeekMeal[]) => ({
  menus: ms.length,
  days: new Set(ms.map((m) => m.date)).size,
  slots: new Set(ms.map((m) => `${m.date}|${m.meal_type}`)).size,
  thousandWon: ms.filter((m) => m.badge === THOUSAND_WON_BADGE).length,
})
