/** Cafeteria meal definitions shared by the page, the editor and the tests. */
export const MEAL_TYPES = ['breakfast', 'lunch', 'dinner'] as const
export const MEAL_LABEL: Record<(typeof MEAL_TYPES)[number], string> = { breakfast: '조식', lunch: '중식', dinner: '석식' }
export const THOUSAND_WON_BADGE = '천원의 아침밥'

export type MealForm = { date: string; type: (typeof MEAL_TYPES)[number]; option: string; items: string; price: string; start: string; end: string; badge: string; status: 'draft' | 'published' | 'closed' | 'no_menu'; source: string; notice: string; verified: string }

/** One menu item per line; the first line is the main dish. Returns the jsonb stored in menu_items. */
export const parseItems = (text: string) =>
  text.split('\n').map((l) => l.trim()).filter(Boolean).map((name, i) => ({ name_ko: name, kind: i === 0 ? 'main' : 'side' }))

export function validateMeal(f: MealForm): Record<string, string> {
  const e: Record<string, string> = {}
  if (!/^\d{4}-\d{2}-\d{2}$/.test(f.date)) e.date = '날짜를 선택해 주세요'
  if (f.status === 'published' && parseItems(f.items).length === 0) e.items = '공개하려면 메뉴를 한 줄 이상 입력해 주세요'
  if (f.price !== '' && !/^\d+$/.test(f.price)) e.price = '가격은 0 이상의 정수여야 해요'
  const t = /^([01]\d|2[0-3]):[0-5]\d$/
  if (f.start && !t.test(f.start)) e.start = 'HH:MM'
  if (f.end && !t.test(f.end)) e.end = 'HH:MM'
  if (f.start && f.end && t.test(f.start) && t.test(f.end) && f.start >= f.end) e.end = '종료는 시작보다 늦어야 해요'
  if (f.source && !/^https:\/\//.test(f.source)) e.source = 'https:// 로 시작해야 해요'
  if (f.badge.trim() === THOUSAND_WON_BADGE && !f.source.trim()) e.source = '천원의 아침밥은 공식 출처 주소가 있어야 표시할 수 있어요'
  if (f.badge.trim() === THOUSAND_WON_BADGE && f.type !== 'breakfast') e.badge = '천원의 아침밥은 조식에만 쓸 수 있어요'
  if (!/^\d{4}-\d{2}-\d{2}$/.test(f.verified)) e.verified = '확인한 날짜를 입력해 주세요'
  return e
}

export type Extra = { photo_url?: string; photo_path?: string; notice?: string; [k: string]: unknown }
export type Meal = { id: string; meal_date: string; meal_type: (typeof MEAL_TYPES)[number]; option_name: string; menu_items: { name_ko: string; kind?: string }[]; price_krw: number | null; start_time: string | null; end_time: string | null; badge: string | null; status: string; source_url: string | null; verified_at: string | null; extra: Extra | null }

/** Seoul calendar date (YYYY-MM-DD): the app and the cafeteria menus use Korean dates. */
export const seoulToday = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date())
export const addDays = (iso: string, n: number) => { const d = new Date(`${iso}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10) }
/** Monday of the week containing [iso]. */
export const weekStart = (iso: string) => { const dow = new Date(`${iso}T00:00:00Z`).getUTCDay(); return addDays(iso, -((dow + 6) % 7)) }
export const seoulDateOf = (iso: string | null) => (iso ? new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date(iso)) : seoulToday())
export const DAY = ['월', '화', '수', '목', '금', '토', '일']
export const MEAL_STATUS_LABEL: Record<string, string> = { draft: '초안 (앱에 안 보임)', published: '메뉴 공개', closed: '운영 안 함 (출처 확인)', no_menu: '메뉴 비공개 (출처 확인)' }
export const emptyForm = (date = seoulToday()): MealForm => ({ date, type: 'lunch', option: '', items: '', price: '', start: '', end: '', badge: '', status: 'published', source: '', notice: '', verified: seoulToday() })


/** The snapshot (publishable content) of a meal from the form: the base snapshot
 *  with the form-managed fields on top. Identity (cafeteria, date, meal, corner)
 *  is never part of it. [photo]: undefined keeps the base photo, null removes it. */
export function snapshotFromMealForm(f: MealForm, base: Record<string, unknown>, photo?: { url: string; path: string } | null): Record<string, unknown> {
  const extra: Extra = { ...((base.extra as Extra | null) ?? {}) }
  if (f.notice.trim()) extra.notice = f.notice.trim(); else delete extra.notice
  if (photo === null) { delete extra.photo_url; delete extra.photo_path } else if (photo) { extra.photo_url = photo.url; extra.photo_path = photo.path }
  return {
    ...base, menu_items: parseItems(f.items), price_krw: f.price === '' ? null : Number(f.price), start_time: f.start || null, end_time: f.end || null,
    status: f.status, badge: f.badge.trim() || null, source_url: f.source.trim() || null, verified_at: `${f.verified}T00:00:00+09:00`, extra,
  }
}

/** Form values from a snapshot (+ the meal's fixed identity). */
export function mealFormFromSnapshot(snap: Record<string, unknown>, id: { meal_date: string; meal_type: (typeof MEAL_TYPES)[number]; option_name: string }): MealForm {
  const items = (snap.menu_items as { name_ko: string }[] | undefined) ?? []
  const extra = (snap.extra as Extra | null) ?? {}
  return {
    date: id.meal_date, type: id.meal_type, option: id.option_name, items: items.map((i) => i.name_ko).join('\n'),
    price: snap.price_krw == null ? '' : String(snap.price_krw), start: ((snap.start_time as string | null) ?? '').slice(0, 5), end: ((snap.end_time as string | null) ?? '').slice(0, 5),
    badge: (snap.badge as string | null) ?? '', status: (snap.status === 'draft' ? 'published' : snap.status) as MealForm['status'], source: (snap.source_url as string | null) ?? '',
    notice: extra.notice ?? '', verified: seoulDateOf((snap.verified_at as string | null) ?? null),
  }
}
