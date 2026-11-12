import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import { addDays, weekStart } from './CafeteriaPage'
import type { WeekMeal } from './cafeteria/week'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})
vi.mock('@/lib/images', async (orig) => ({
  ...(await orig<typeof import('@/lib/images')>()),
  prepareImage: async (f: File) => ({ blob: f, type: f.type, width: 800, height: 600, bytes: f.size }),
}))

describe('week maths', () => {
  it('finds the Monday of any day, including Sundays and month ends', () => {
    expect(weekStart('2026-11-10')).toBe('2026-11-09')
    expect(weekStart('2026-11-09')).toBe('2026-11-09')
    expect(weekStart('2026-11-15')).toBe('2026-11-09')
    expect(weekStart('2026-12-01')).toBe('2026-11-30')
  })
  it('adds days across months and years', () => {
    expect(addDays('2026-11-30', 1)).toBe('2026-12-01')
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01')
  })
})

const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date())
const MON = weekStart(today)
const d = (n: number) => addDays(MON, n)
const FIVE = [0, 1, 2, 3, 4].map(d)
const CAF = (over: Record<string, unknown> = {}) => ({
  id: 'c1', university_id: 'u1', kind: 'student', name_ko: '학생식당', name_en: null, name_zh: null, location_description: '학생회관 1층', sort_order: 0, status: 'active', operating_note: null,
  meal_periods: ['breakfast', 'lunch', 'dinner'], operating_days: [1, 2, 3, 4, 5], photo_url: null, photo_path: null, universities: { name_ko: '순천향대학교' }, ...over,
})
const UNIS = [{ id: 'u1', name_ko: '순천향대학교', is_active: true }, { id: 'u2', name_ko: '호서대학교', is_active: true }]
const meal = (date: string, type: WeekMeal['meal_type'], over: Partial<WeekMeal> = {}): WeekMeal => ({
  date, meal_type: type, option_name: '', option_order: 0, menu_items: [{ name_ko: `${type} ${date}`, kind: 'main' }], price_krw: 5500, start_time: '11:30', end_time: '13:30',
  status: 'published', badge: null, source_url: null, verified_at: '2026-11-09T00:00:00+09:00', extra: {}, ...over,
})
const fullWeek = () => FIVE.flatMap((date) => (['breakfast', 'lunch', 'dinner'] as const).map((t) => meal(date, t)))
const DRAFT = (meals: WeekMeal[], over: Record<string, unknown> = {}) => ({ data: { meals }, revision: 1, base_version: 1, created_by: 'u-1', updated_by: 'u-1', created_at: '2026-11-09T00:00:00Z', updated_at: '2026-11-10T01:00:00Z', stale: false, has_changes: true, ...over })
const JOB = { id: 7, entity_type: 'cafeteria_week', entity_id: `w-${MON}`, action: 'publish', base_version: 1, run_at: '2098-12-31T22:00:00Z', unpublish_at: null, status: 'scheduled', reason: null, created_by: 'u-1', created_at: '2026-11-10T00:00:00Z', attempts: 0, last_error: null, executed_at: null, published_version: null, parent_job_id: null }

const states = new Map<string, unknown>()
const stateOf = (liveMeals: WeekMeal[], draft: unknown = null, jobs: unknown[] = []) => ({ live: { meals: liveMeals }, live_version: liveMeals.length ? 1 : 0, last_published: null, draft, jobs })
const saved = () => fake.rpcs.filter((r) => r.name === 'cms_save_draft').at(-1)!.args as { p_type: string; p_id: string; p_data: { meals: WeekMeal[] }; p_expected_revision: number }
const liveWrites = () => { for (const op of ['insert', 'update', 'upsert', 'delete']) expect(fake.last('cafeteria_meals', op)).toBeUndefined() }

async function openWeek(opts: { caf?: Record<string, unknown>; live?: WeekMeal[]; draft?: unknown; jobs?: unknown[] } = {}) {
  states.clear()
  fake.signInAs('admin')
  fake.respond('universities:select', { data: UNIS })
  fake.respond('campus_cafeterias:select', { data: [CAF(opts.caf)] })
  fake.respond('cafeteria_weeks:select', { data: [] })
  fake.respond('rpc:cms_overview', { data: [] })
  fake.respond('rpc:cafeteria_week_entity', (a: unknown) => ({ data: `w-${(a as { p_week: string }).p_week}` }))
  fake.respond('rpc:cms_state', (a: unknown) => ({ data: states.get((a as { p_id: string }).p_id) ?? stateOf([]) }))
  fake.respond('rpc:cms_save_draft', { data: { revision: 1, base_version: 0, updated_at: '2026-11-10T00:00:00Z' } })
  states.set(`w-${MON}`, stateOf(opts.live ?? [], opts.draft ?? null, opts.jobs ?? []))
  render(<MemoryRouter initialEntries={['/cafeteria']}><App client={makeQueryClient()} /></MemoryRouter>)
  await userEvent.click(await screen.findByRole('button', { name: '학생식당 메뉴 관리' }))
  await screen.findByLabelText('주간 식단표')
}
const user = () => userEvent.setup({ delay: null })
/** Click "+ 추가" in a cell and type the menu. */
async function fill(date: string, meal: string, menu: string, price?: string) {
  const u = user()
  const cell = screen.getByLabelText(`${date} ${meal}`, { selector: 'td' })
  await u.click(within(cell).getByRole('button', { name: new RegExp(`${meal} 추가$`) }))
  await u.type(screen.getByLabelText(`${date} ${meal} 메뉴`), menu)
  if (price) await u.type(screen.getByLabelText(`${date} ${meal} 가격`), price)
}

beforeEach(() => {
  fake.reset()
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('주간 식단표: Monday-Friday x breakfast / lunch / dinner', () => {
  it('shows five weekdays and three meal periods as a 15-slot grid, no weekend by default', async () => {
    await openWeek()
    const grid = screen.getByLabelText('주간 식단표')
    for (const date of FIVE) expect(within(grid).getByLabelText(`${date} 중식`, { selector: 'td' })).toBeTruthy()
    for (const meal of ['조식', '중식', '석식']) expect(within(grid).getByRole('rowheader', { name: meal })).toBeTruthy()
    expect(within(grid).queryByLabelText(`${d(5)} 중식`)).toBeNull()
    expect(within(grid).getAllByRole('columnheader')).toHaveLength(6) // the corner + 5 days
    expect(screen.getByText(/^0칸 입력/)).toBeTruthy()
  })

  it('"토·일도 편집" adds Saturday and Sunday; a cafeteria that opens at weekends shows them from the start', async () => {
    await openWeek()
    await user().click(screen.getByLabelText('주말 표시'))
    expect(screen.getByLabelText(`${d(5)} 중식`, { selector: 'td' })).toBeTruthy()
    expect(screen.getByLabelText(`${d(6)} 석식`, { selector: 'td' })).toBeTruthy()
    expect(screen.getByText(/^0칸 입력/)).toBeTruthy()
  })
  it('opens with Saturday when the cafeteria operates on Saturdays', async () => {
    await openWeek({ caf: { operating_days: [1, 2, 3, 4, 5, 6] } })
    expect(screen.getByLabelText(`${d(5)} 중식`, { selector: 'td' })).toBeTruthy()
  })

  it('does not assume every cafeteria serves every meal: only the configured meal periods have rows', async () => {
    await openWeek({ caf: { meal_periods: ['lunch'] } })
    const grid = screen.getByLabelText('주간 식단표')
    expect(within(grid).getByRole('rowheader', { name: '중식' })).toBeTruthy()
    expect(within(grid).queryByRole('rowheader', { name: '조식' })).toBeNull()
    expect(within(grid).queryByRole('rowheader', { name: '석식' })).toBeNull()
    expect(screen.getByText(/중식만 운영하도록 설정/)).toBeTruthy()
  })
  it('a meal that already has a menu keeps its row even if the cafeteria is not set up for it', async () => {
    await openWeek({ caf: { meal_periods: ['lunch'] }, live: [meal(d(0), 'dinner')] })
    expect(within(screen.getByLabelText('주간 식단표')).getByRole('rowheader', { name: '석식' })).toBeTruthy()
  })

  it('shows the saved DRAFT (not live) and says there are unpublished changes', async () => {
    await openWeek({ live: [meal(d(0), 'lunch', { menu_items: [{ name_ko: '게시된 점심' }] })], draft: DRAFT([meal(d(0), 'lunch', { menu_items: [{ name_ko: '초안 점심' }] })]) })
    expect((screen.getByLabelText(`${d(0)} 중식 메뉴`) as HTMLTextAreaElement).value).toBe('초안 점심')
    expect(screen.getByText('초안 있음')).toBeTruthy()
  })
})

describe('한 번에 한 주: bulk weekly editing, one save', () => {
  it('fills breakfast, lunch and dinner for all five weekdays in one session and saves them in ONE draft call', async () => {
    await openWeek()
    for (const date of FIVE) {
      await fill(date, '조식', `조식 ${date}`, '3000')
      await fill(date, '중식', `중식 ${date}`, '5500')
      await fill(date, '석식', `석식 ${date}`, '6000')
    }
    expect(screen.getByText(/^15칸 입력 · 메뉴 15개/)).toBeTruthy()
    await user().click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/한 주 전체를 초안으로 저장했어요/)
    expect(fake.rpcs.filter((r) => r.name === 'cms_save_draft')).toHaveLength(1)
    const call = saved()
    expect(call).toMatchObject({ p_type: 'cafeteria_week', p_id: `w-${MON}`, p_expected_revision: 0 })
    expect(call.p_data.meals).toHaveLength(15)
    expect(new Set(call.p_data.meals.map((m) => m.date))).toEqual(new Set(FIVE))
    expect(new Set(call.p_data.meals.map((m) => m.meal_type))).toEqual(new Set(['breakfast', 'lunch', 'dinner']))
    expect(call.p_data.meals.find((m) => m.date === d(2) && m.meal_type === 'dinner')).toMatchObject({ price_krw: 6000, status: 'published', menu_items: [{ name_ko: `석식 ${d(2)}`, kind: 'main' }] })
    liveWrites() // not one live menu was written
  }, 30000)

  it('several menu options in one meal: each keeps its own name and price', async () => {
    await openWeek()
    const u = user()
    await fill(d(1), '중식', '제육볶음', '5500')
    await u.click(within(screen.getByLabelText(`${d(1)} 중식`, { selector: 'td' })).getByRole('button', { name: /옵션 추가$/ }))
    await u.type(screen.getByLabelText(`${d(1)} 중식 (옵션 2) 메뉴`), '돈까스')
    await u.type(screen.getByLabelText(`${d(1)} 중식 (옵션 2) 가격`), '6500')
    await u.clear(screen.getByLabelText(`${d(1)} 중식 (옵션 2) 옵션 이름`)); await u.type(screen.getByLabelText(`${d(1)} 중식 (옵션 2) 옵션 이름`), 'B코너')
    await u.click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/초안으로 저장했어요/)
    const lunch = saved().p_data.meals.filter((m) => m.date === d(1) && m.meal_type === 'lunch')
    expect(lunch.map((m) => [m.option_name, m.price_krw, m.menu_items[0].name_ko])).toEqual([['', 5500, '제육볶음'], ['B코너', 6500, '돈까스']])
  })

  it('천원의 아침밥 is set per breakfast date, needs an official source, and is never assumed for the other days', async () => {
    await openWeek()
    const u = user()
    await fill(d(0), '조식', '계란토스트', '3000')
    await fill(d(1), '조식', '샌드위치', '3000')
    await u.click(screen.getByLabelText(`${d(0)} 조식 천원의 아침밥`))
    expect((screen.getByLabelText(`${d(0)} 조식 가격`) as HTMLInputElement).value).toBe('3000') // an existing price is not overwritten
    expect(screen.queryByLabelText(`${d(1)} 조식 출처 주소`)).toBeNull()
    await u.click(screen.getByRole('button', { name: '초안 저장' }))
    expect((await screen.findAllByText(/천원의 아침밥은 공식 출처 주소가 필요해요/)).length).toBeGreaterThan(0)
    expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(false)
    await u.type(screen.getByLabelText(`${d(0)} 조식 출처 주소`), 'https://example.org/1000')
    await u.click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/초안으로 저장했어요/)
    const [mon, tue] = saved().p_data.meals
    expect(mon).toMatchObject({ date: d(0), badge: '천원의 아침밥', source_url: 'https://example.org/1000' })
    expect(tue).toMatchObject({ date: d(1), badge: null, source_url: null })
  })
  it('천원의 아침밥 is only offered for breakfast', async () => {
    await openWeek()
    await fill(d(0), '중식', '제육볶음')
    expect(screen.queryByLabelText(`${d(0)} 중식 천원의 아침밥`)).toBeNull()
  })

  it('weekend menus can be added for a cafeteria that opens on Saturday', async () => {
    await openWeek({ caf: { operating_days: [1, 2, 3, 4, 5, 6] } })
    await fill(d(5), '중식', '토요 특식', '5000')
    await user().click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/초안으로 저장했어요/)
    expect(saved().p_data.meals).toEqual([expect.objectContaining({ date: d(5), meal_type: 'lunch' })])
  })

  it('saving an existing week sends the current revision (so a concurrent edit is noticed)', async () => {
    await openWeek({ live: [meal(d(0), 'lunch')], draft: DRAFT([meal(d(0), 'lunch')]) })
    await user().type(screen.getByLabelText(`${d(0)} 중식 공지`), '한정')
    await user().click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/초안으로 저장했어요/)
    expect(saved().p_expected_revision).toBe(1)
  })
  it('a conflicting save tells the admin and offers the latest draft', async () => {
    await openWeek({ live: [meal(d(0), 'lunch')] })
    fake.respond('rpc:cms_save_draft', { error: { code: '40001', message: '다른 관리자가 이 초안을 먼저 저장했어요.' } })
    await user().type(screen.getByLabelText(`${d(0)} 중식 공지`), 'x')
    await user().click(screen.getByRole('button', { name: '초안 저장' }))
    expect((await screen.findAllByText(/다른 관리자가/)).length).toBeGreaterThan(0)
  })
})

describe('복사 · 공통 시간 · 일괄 수정', () => {
  it('copies one day onto other days, filling only empty slots (existing menus are kept)', async () => {
    await openWeek({ live: [meal(d(0), 'breakfast'), meal(d(0), 'lunch'), meal(d(0), 'dinner'), meal(d(1), 'lunch', { menu_items: [{ name_ko: '기존 점심' }] })] })
    const u = user()
    await u.click(screen.getByRole('button', { name: '요일 복사' }))
    const dlg = await screen.findByRole('dialog', { name: '요일 복사' })
    await u.click(within(dlg).getByLabelText(`붙여넣을 요일 ${d(1)}`))
    await u.click(within(dlg).getByLabelText(`붙여넣을 요일 ${d(2)}`))
    await u.click(within(dlg).getByRole('button', { name: '복사' }))
    expect((screen.getByLabelText(`${d(1)} 중식 메뉴`) as HTMLTextAreaElement).value).toBe('기존 점심')
    expect((screen.getByLabelText(`${d(1)} 조식 메뉴`) as HTMLTextAreaElement).value).toBe(`breakfast ${d(0)}`)
    expect((screen.getByLabelText(`${d(2)} 석식 메뉴`) as HTMLTextAreaElement).value).toBe(`dinner ${d(0)}`)
    liveWrites(); expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(false) // nothing saved until 초안 저장
    expect(screen.getAllByText(/저장하지 않은 수정/).length).toBeGreaterThan(0)
  })
  it('overwriting an existing day asks for confirmation first', async () => {
    await openWeek({ live: [meal(d(0), 'lunch'), meal(d(1), 'lunch', { menu_items: [{ name_ko: '기존 점심' }] })] })
    const u = user()
    await u.click(screen.getByRole('button', { name: '요일 복사' }))
    const dlg = await screen.findByRole('dialog', { name: '요일 복사' })
    await u.click(within(dlg).getByLabelText(`붙여넣을 요일 ${d(1)}`))
    await u.click(within(dlg).getByLabelText(/덮어써요/))
    await u.click(within(dlg).getByRole('button', { name: '복사' }))
    expect(await screen.findByText('그 요일의 메뉴를 덮어쓸까요?')).toBeTruthy()
    expect((screen.getByLabelText(`${d(1)} 중식 메뉴`) as HTMLTextAreaElement).value).toBe('기존 점심') // not yet
    await u.click(screen.getByRole('button', { name: '덮어쓰기' }))
    expect((screen.getByLabelText(`${d(1)} 중식 메뉴`) as HTMLTextAreaElement).value).toBe(`lunch ${d(0)}`)
  })
  it('copying a day does not copy the 천원의 아침밥 programme to another date', async () => {
    await openWeek({ live: [meal(d(0), 'breakfast', { badge: '천원의 아침밥', source_url: 'https://e.org', price_krw: 1000 })] })
    const u = user()
    await u.click(screen.getByRole('button', { name: '요일 복사' }))
    const dlg = await screen.findByRole('dialog', { name: '요일 복사' })
    await u.click(within(dlg).getByLabelText(`붙여넣을 요일 ${d(1)}`))
    await u.click(within(dlg).getByRole('button', { name: '복사' }))
    expect((screen.getByLabelText(`${d(1)} 조식 천원의 아침밥`) as HTMLInputElement).checked).toBe(false)
    expect((screen.getByLabelText(`${d(0)} 조식 천원의 아침밥`) as HTMLInputElement).checked).toBe(true)
  })

  it('copies the previous week forward (dates shifted by seven days)', async () => {
    await openWeek()
    states.set(`w-${addDays(MON, -7)}`, stateOf([meal(addDays(d(0), -7), 'lunch', { menu_items: [{ name_ko: '지난주 점심' }] }), meal(addDays(d(3), -7), 'dinner')]))
    const u = user()
    await u.click(screen.getByRole('button', { name: '다른 주 복사' }))
    const dlg = await screen.findByRole('dialog', { name: '다른 주 복사' })
    await u.click(within(dlg).getByRole('button', { name: '가져오기' }))
    await waitFor(() => expect((screen.getByLabelText(`${d(0)} 중식 메뉴`) as HTMLTextAreaElement).value).toBe('지난주 점심'))
    expect((screen.getByLabelText(`${d(3)} 석식 메뉴`) as HTMLTextAreaElement).value).toBe(`dinner ${addDays(d(3), -7)}`)
    expect(await screen.findByText(/식단 2개를 가져왔어요/)).toBeTruthy()
  })
  it('says so when the other week has nothing to copy', async () => {
    await openWeek()
    const u = user()
    await u.click(screen.getByRole('button', { name: '다른 주 복사' }))
    await u.click(within(await screen.findByRole('dialog', { name: '다른 주 복사' })).getByRole('button', { name: '가져오기' }))
    expect(await screen.findByText(/가져올 식단이 없어요/)).toBeTruthy()
  })

  it('applies one common serving time to the chosen weekdays and meals only', async () => {
    await openWeek({ live: fullWeek() })
    const u = user()
    await u.click(screen.getByRole('button', { name: '공통 운영 시간' }))
    const dlg = await screen.findByRole('dialog', { name: '공통 운영 시간 적용' })
    expect((within(dlg).getByRole('button', { name: '적용' }) as HTMLButtonElement).disabled).toBe(true) // no meal chosen yet
    await u.click(within(dlg).getByLabelText('적용할 식사 중식'))
    await u.click(within(dlg).getByLabelText('적용할 요일 ' + d(3))); await u.click(within(dlg).getByLabelText('적용할 요일 ' + d(4)))
    const start = within(dlg).getByLabelText('시작'); const end = within(dlg).getByLabelText('종료')
    await u.clear(start); await u.type(start, '12:00'); await u.clear(end); await u.type(end, '14:00')
    await u.click(within(dlg).getByRole('button', { name: '적용' }))
    expect((screen.getByLabelText(`${d(0)} 중식 시작`) as HTMLInputElement).value).toBe('12:00')
    expect((screen.getByLabelText(`${d(2)} 중식 종료`) as HTMLInputElement).value).toBe('14:00')
    expect((screen.getByLabelText(`${d(3)} 중식 시작`) as HTMLInputElement).value).toBe('11:30') // unchecked day untouched
    expect((screen.getByLabelText(`${d(0)} 석식 시작`) as HTMLInputElement).value).toBe('11:30') // other meals untouched
  })

  it('bulk-edits the selected menus (price and sold-out), leaving the rest alone', async () => {
    await openWeek({ live: fullWeek() })
    const u = user()
    await u.click(screen.getByLabelText(`${d(0)} 중식 선택`)); await u.click(screen.getByLabelText(`${d(1)} 중식 선택`))
    await u.click(screen.getByRole('button', { name: /일괄 수정 \(2\)/ }))
    const dlg = await screen.findByRole('dialog', { name: /일괄 수정/ })
    await u.type(within(dlg).getByLabelText('가격 (원)'), '6500')
    await u.selectOptions(within(dlg).getByLabelText('품절 표시'), 'yes')
    await u.click(within(dlg).getByRole('button', { name: '적용' }))
    expect((screen.getByLabelText(`${d(0)} 중식 가격`) as HTMLInputElement).value).toBe('6500')
    expect((screen.getByLabelText(`${d(1)} 중식 품절`) as HTMLInputElement).checked).toBe(true)
    expect((screen.getByLabelText(`${d(2)} 중식 가격`) as HTMLInputElement).value).toBe('5500')
  })
})

describe('빈 칸은 지우지 않아요 · 지울 때는 확인', () => {
  it('a brand-new blank option is not saved (a blank cell changes nothing)', async () => {
    await openWeek({ live: [meal(d(0), 'lunch')] })
    const u = user()
    await u.click(within(screen.getByLabelText(`${d(1)} 중식`, { selector: 'td' })).getByRole('button', { name: /중식 추가$/ })) // opened but never filled in
    await u.type(screen.getByLabelText(`${d(0)} 중식 공지`), '변경')
    await u.click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/초안으로 저장했어요/)
    expect(saved().p_data.meals.map((m) => m.date)).toEqual([d(0)])
  })
  it('emptying an existing menu is refused until it is removed explicitly', async () => {
    await openWeek({ live: [meal(d(0), 'lunch')] })
    const u = user()
    await u.clear(screen.getByLabelText(`${d(0)} 중식 메뉴`))
    await u.click(screen.getByRole('button', { name: '초안 저장' }))
    expect((await screen.findAllByText(/이 메뉴 삭제/)).length).toBeGreaterThan(0)
    expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(false)
  })
  it('removing a published menu asks first, and the removal is only in the draft until published', async () => {
    await openWeek({ live: [meal(d(0), 'lunch'), meal(d(1), 'lunch')] })
    const u = user()
    await u.click(screen.getByRole('button', { name: `${d(0)} 중식 삭제` }))
    expect(await screen.findByText(/메뉴를 삭제할까요\?/)).toBeTruthy()
    expect(screen.getByLabelText(`${d(0)} 중식 메뉴`)).toBeTruthy() // still there
    await u.click(screen.getByRole('button', { name: '삭제' }))
    expect(screen.queryByLabelText(`${d(0)} 중식 메뉴`)).toBeNull()
    await u.click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/초안으로 저장했어요/)
    expect(saved().p_data.meals.map((m) => m.date)).toEqual([d(1)])
    liveWrites()
  })
  it('marking a published meal "운영 안 함" asks for confirmation; a new one does not', async () => {
    await openWeek({ live: [meal(d(0), 'lunch')] })
    const u = user()
    await u.selectOptions(screen.getByLabelText(`${d(0)} 중식 상태`), 'closed')
    expect(await screen.findByText(/운영 안 함으로 바꿀까요/)).toBeTruthy()
    expect((screen.getByLabelText(`${d(0)} 중식 상태`) as HTMLSelectElement).value).toBe('published')
    await u.click(screen.getByRole('button', { name: '바꾸기' }))
    expect((screen.getByLabelText(`${d(0)} 중식 상태`) as HTMLSelectElement).value).toBe('closed')
    expect(screen.queryByLabelText(`${d(0)} 중식 메뉴`)).toBeNull() // a closed meal needs no menu
  })

  it('invalid values stop the save with a readable reason, and mark the cell', async () => {
    await openWeek({ live: [meal(d(0), 'lunch')] })
    const u = user()
    await u.clear(screen.getByLabelText(`${d(0)} 중식 시작`)); await u.type(screen.getByLabelText(`${d(0)} 중식 시작`), '15:00')
    await u.click(screen.getByRole('button', { name: '초안 저장' }))
    expect((await screen.findAllByText(/종료는 시작보다 늦어야 해요/)).length).toBeGreaterThan(0)
    expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(false)
  })
})

describe('게시: 한 주 전체 · 선택한 날 · 예약 · 중단', () => {
  const draftWeek = () => DRAFT(fullWeek().map((m) => (m.date === d(1) && m.meal_type === 'lunch' ? { ...m, price_krw: 6000 } : m.date === d(3) && m.meal_type === 'dinner' ? { ...m, price_krw: 6100 } : m)))

  it('previews all five days with breakfast / lunch / dinner and exactly what changes', async () => {
    await openWeek({ live: fullWeek(), draft: draftWeek() })
    await user().click(screen.getByRole('button', { name: '미리보기' }))
    const prev = await screen.findByLabelText('앱 주간 식단 미리보기')
    expect(within(prev).getAllByRole('columnheader')).toHaveLength(6)
    expect(within(prev).getAllByText(/lunch/).length).toBeGreaterThanOrEqual(5)
    const diff = await screen.findByLabelText('달라지는 항목')
    expect(diff.textContent).toMatch(/중식 · 가격/)
    expect(diff.textContent).toMatch(/석식 · 가격/)
    expect(diff.textContent).toMatch(/5,500|5500/)
  })

  it('publishes the WHOLE week with one server call (atomic)', async () => {
    fake.respond('rpc:cms_publish', { data: 2 })
    await openWeek({ live: fullWeek(), draft: draftWeek() })
    const u = user()
    await u.click(await screen.findByRole('button', { name: '지금 게시' }))
    await u.click(within(await screen.findByRole('dialog')).getByRole('button', { name: '지금 게시' }))
    await waitFor(() => expect(fake.rpcs.filter((r) => r.name === 'cms_publish')).toHaveLength(1))
    expect(fake.rpcs.find((r) => r.name === 'cms_publish')!.args).toMatchObject({ p_type: 'cafeteria_week', p_id: `w-${MON}`, p_expected_revision: 1 })
    liveWrites()
  })

  it('publishes only the selected days, preselecting the days that changed', async () => {
    fake.respond('rpc:cms_publish_week_days', { data: 2 })
    await openWeek({ live: fullWeek(), draft: draftWeek() })
    const u = user()
    await u.click(screen.getByRole('button', { name: '선택한 날만 게시' }))
    const dlg = await screen.findByRole('dialog', { name: '선택한 날만 게시' })
    expect((within(dlg).getByLabelText(`게시할 날짜 ${d(1)}`) as HTMLInputElement).checked).toBe(true)
    expect((within(dlg).getByLabelText(`게시할 날짜 ${d(3)}`) as HTMLInputElement).checked).toBe(true)
    expect((within(dlg).getByLabelText(`게시할 날짜 ${d(0)}`) as HTMLInputElement).checked).toBe(false)
    await u.click(within(dlg).getByLabelText(`게시할 날짜 ${d(3)}`)) // only Tuesday
    await u.click(within(dlg).getByRole('button', { name: '1일 게시' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_publish_week_days')).toBe(true))
    expect(fake.rpcs.find((r) => r.name === 'cms_publish_week_days')!.args).toMatchObject({ p_id: `w-${MON}`, p_expected_revision: 1, p_days: [d(1)] })
    expect(await screen.findByText(/나머지 날의 수정은 초안에 남아 있어요/)).toBeTruthy()
  })
  it('"선택한 날만 게시" needs a saved draft with changes and no unsaved edits', async () => {
    await openWeek({ live: fullWeek() })
    const b = screen.getByRole('button', { name: '선택한 날만 게시' }) as HTMLButtonElement
    expect(b.disabled).toBe(true)
  })
  it('a failed batch publish reports the reason and leaves the screen consistent', async () => {
    fake.respond('rpc:cms_publish_week_days', { error: { code: '22023', message: '게시할 날짜를 골라 주세요' } })
    await openWeek({ live: fullWeek(), draft: draftWeek() })
    const u = user()
    await u.click(screen.getByRole('button', { name: '선택한 날만 게시' }))
    await u.click(within(await screen.findByRole('dialog', { name: '선택한 날만 게시' })).getByRole('button', { name: /일 게시/ }))
    expect(await screen.findByText('게시할 날짜를 골라 주세요')).toBeTruthy()
  })

  it('schedules the week for a Seoul time (the server runs it)', async () => {
    fake.respond('rpc:cms_schedule', { data: 5 })
    await openWeek({ live: fullWeek(), draft: draftWeek() })
    const u = user()
    await u.click(await screen.findByRole('button', { name: '예약 게시' }))
    const dlg = await screen.findByRole('dialog', { name: '예약 게시' })
    await u.type(within(dlg).getByLabelText('게시 날짜'), '2099-01-01')
    await u.clear(within(dlg).getByLabelText('게시 시간')); await u.type(within(dlg).getByLabelText('게시 시간'), '07:00')
    await u.click(within(dlg).getByRole('button', { name: '예약하기' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_schedule')).toBe(true))
    expect(fake.rpcs.find((r) => r.name === 'cms_schedule')!.args).toMatchObject({ p_type: 'cafeteria_week', p_id: `w-${MON}`, p_run_at: '2098-12-31T22:00:00.000Z' })
  })
  it('cancels a scheduled week', async () => {
    fake.respond('rpc:cms_cancel_job', { data: null })
    await openWeek({ live: fullWeek(), draft: draftWeek(), jobs: [JOB] })
    await user().click(await screen.findByRole('button', { name: '예약 취소' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_cancel_job')).toBe(true))
    expect(fake.rpcs.find((r) => r.name === 'cms_cancel_job')!.args).toMatchObject({ p_job: 7 })
  })
  it('unpublishes the whole week (hidden, nothing deleted) through the server', async () => {
    fake.respond('rpc:cms_unpublish', { data: 3 })
    await openWeek({ live: fullWeek() })
    const u = user()
    await u.click(await screen.findByRole('button', { name: '게시 중단' }))
    const dlg = await screen.findByRole('dialog')
    await u.type(within(dlg).getByLabelText(/사유|메모/), '점검')
    await u.click(within(dlg).getByRole('button', { name: /게시 중단|중단/ }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_unpublish')).toBe(true))
    expect(fake.rpcs.find((r) => r.name === 'cms_unpublish')!.args).toMatchObject({ p_type: 'cafeteria_week', p_id: `w-${MON}` })
    liveWrites()
  })
  it('opens the week history (versions with restore)', async () => {
    await openWeek({ live: fullWeek() })
    states.set(`w-${MON}`, { ...(states.get(`w-${MON}`) as object), live_version: 2 })
    fake.respond('content_versions:select', { data: [{ id: 2, version: 2, kind: 'publish', data: { meals: [] }, reason: '둘째 게시', rolled_back_from: null, published_by: null, published_at: '2026-11-10T00:00:00Z', job_id: null }, { id: 1, version: 1, kind: 'publish', data: { meals: [] }, reason: '첫 게시', rolled_back_from: null, published_by: null, published_at: '2026-11-09T00:00:00Z', job_id: null }] })
    await user().click(screen.getByRole('button', { name: '게시 이력' }))
    expect(await screen.findByRole('button', { name: /이 버전으로 복원/ })).toBeTruthy()
  })
})

describe('이동 · 마이그레이션 안내', () => {
  it('moving to another week with unsaved edits asks first', async () => {
    await openWeek({ live: [meal(d(0), 'lunch')] })
    const u = user()
    await u.type(screen.getByLabelText(`${d(0)} 중식 공지`), 'x')
    await u.click(screen.getByRole('button', { name: '다음 주' }))
    expect(await screen.findByText('저장하지 않은 수정이 있어요')).toBeTruthy()
    expect(screen.getByLabelText('표시 중인 주').textContent).toContain(MON)
    await u.click(screen.getByRole('button', { name: '수정을 버리고 이동' }))
    await waitFor(() => expect(screen.getByLabelText('표시 중인 주').textContent).toContain(addDays(MON, 7)))
  })
  it('moves between weeks freely when nothing is unsaved, asking the server for each week', async () => {
    await openWeek()
    await user().click(screen.getByRole('button', { name: '다음 주' }))
    await waitFor(() => expect(screen.getByLabelText('표시 중인 주').textContent).toContain(addDays(MON, 7)))
    expect(fake.rpcs.filter((r) => r.name === 'cafeteria_week_entity').map((r) => (r.args as { p_week: string }).p_week)).toContain(addDays(MON, 7))
  })
  it('says so when migration 20261118000100 is not applied (instead of failing)', async () => {
    fake.signInAs('admin')
    fake.respond('universities:select', { data: UNIS }); fake.respond('campus_cafeterias:select', { data: [CAF()] }); fake.respond('cafeteria_weeks:select', { data: [] }); fake.respond('rpc:cms_overview', { data: [] })
    fake.respond('rpc:cafeteria_week_entity', { error: { code: 'PGRST202', message: 'Could not find the function public.cafeteria_week_entity' } })
    render(<MemoryRouter initialEntries={['/cafeteria']}><App client={makeQueryClient()} /></MemoryRouter>)
    await userEvent.click(await screen.findByRole('button', { name: '학생식당 메뉴 관리' }))
    expect(await screen.findByText(/20261118000100/)).toBeTruthy()
  })
})

describe('실제 식단표 형식: several dishes per meal, shared dishes, origin and labels', () => {
  const MONDAY_LUNCH = '치즈닭갈비볶음밥\n새우튀김*타르타르\n참나물무침\n햄감자채볶음\n파래무침\n계란국'

  it('keeps every dish as its own structured item with a guessed category, and a category change survives further typing', async () => {
    await openWeek()
    const u = user()
    await fill(d(0), '중식', MONDAY_LUNCH)
    await u.click(screen.getByText(/분류·공통·순서 \(6개 메뉴\)/))
    expect((screen.getByLabelText(`${d(0)} 중식 치즈닭갈비볶음밥 분류`) as HTMLSelectElement).value).toBe('main')
    expect((screen.getByLabelText(`${d(0)} 중식 계란국 분류`) as HTMLSelectElement).value).toBe('soup')
    expect((screen.getByLabelText(`${d(0)} 중식 파래무침 분류`) as HTMLSelectElement).value).toBe('side')
    await u.selectOptions(screen.getByLabelText(`${d(0)} 중식 파래무침 분류`), 'salad')
    await u.type(screen.getByLabelText(`${d(0)} 중식 메뉴`), '\n쌀밥') // typing more must not reset the category chosen above
    expect((screen.getByLabelText(`${d(0)} 중식 파래무침 분류`) as HTMLSelectElement).value).toBe('salad')
    expect((screen.getByLabelText(`${d(0)} 중식 쌀밥 분류`) as HTMLSelectElement).value).toBe('rice')
    await u.click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/한 주 전체를 초안으로 저장했어요/)
    const items = saved().p_data.meals[0].menu_items
    expect(items).toEqual([
      { name_ko: '치즈닭갈비볶음밥', kind: 'main' }, { name_ko: '새우튀김*타르타르', kind: 'side' }, { name_ko: '참나물무침', kind: 'side' },
      { name_ko: '햄감자채볶음', kind: 'side' }, { name_ko: '파래무침', kind: 'salad' }, { name_ko: '계란국', kind: 'soup' }, { name_ko: '쌀밥', kind: 'rice' },
    ])
    liveWrites()
  }, 30000)

  it('applies the shared row (rice / kimchi / salad), the origin statement and the notice to several days at once, without touching empty cells', async () => {
    await openWeek({ live: FIVE.flatMap((date) => [meal(date, 'breakfast'), meal(date, 'lunch')]) })   // no dinner at all
    const u = user()
    await u.click(screen.getByRole('button', { name: '공통 메뉴·공지' }))
    const dlg = await screen.findByRole('dialog', { name: '공통 메뉴·공지 적용' })
    expect((within(dlg).getByRole('button', { name: '적용' }) as HTMLButtonElement).disabled).toBe(true) // nothing typed yet
    await u.type(within(dlg).getByLabelText('조식 공통 메뉴'), '아산쌀밥/김치/샐러드')
    await u.type(within(dlg).getByLabelText('중식 공통 메뉴'), '김치/샐러드/후식차')
    await u.type(within(dlg).getByLabelText('석식 공통 메뉴'), '김치/샐러드')
    await u.type(within(dlg).getByLabelText('원산지 표시사항 (선택)'), '쌀:국내산 / 배추김치:중국산')
    await u.type(within(dlg).getByLabelText('안내 문구 (선택)'), '재료수급상황에 따라 변경될 수 있습니다')
    await u.click(within(dlg).getByLabelText(`적용할 요일 ${d(4)}`)) // Friday off: Monday-Thursday only
    await u.click(within(dlg).getByRole('button', { name: '적용' }))
    expect(await screen.findByText(/8개 식사에 공통 내용을 적용했어요/)).toBeTruthy()   // 4 days x (breakfast + lunch), each counted once
    await u.click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/한 주 전체를 초안으로 저장했어요/)
    const meals = saved().p_data.meals
    const monLunch = meals.find((m) => m.date === d(0) && m.meal_type === 'lunch')!
    expect(monLunch.menu_items.map((i) => i.name_ko)).toEqual([`lunch ${d(0)}`, '김치', '샐러드', '후식차'])
    expect(monLunch.menu_items.slice(1)).toEqual([{ name_ko: '김치', kind: 'kimchi', shared: true }, { name_ko: '샐러드', kind: 'salad', shared: true }, { name_ko: '후식차', kind: 'dessert', shared: true }])
    expect(meals.find((m) => m.date === d(0) && m.meal_type === 'breakfast')!.menu_items.map((i) => i.name_ko)).toContain('아산쌀밥')
    expect(monLunch.extra).toMatchObject({ origin: '쌀:국내산 / 배추김치:중국산', notice: '재료수급상황에 따라 변경될 수 있습니다' })
    const friLunch = meals.find((m) => m.date === d(4) && m.meal_type === 'lunch')!
    expect(friLunch.menu_items).toHaveLength(1)                    // an unchecked day is untouched
    expect(friLunch.extra.origin).toBeUndefined()
    expect(meals.some((m) => m.meal_type === 'dinner')).toBe(false) // no cell was created for the shared dinner row
    liveWrites()
  }, 30000)

  it('applying the same shared dishes twice does not duplicate them, and "제거" removes only what was added as shared', async () => {
    await openWeek({ live: [meal(d(0), 'lunch', { menu_items: [{ name_ko: '제육볶음', kind: 'main' }, { name_ko: '김치', kind: 'kimchi' }] })] })
    const u = user()
    const apply = async (text: string, remove = false) => {
      await u.click(screen.getByRole('button', { name: '공통 메뉴·공지' }))
      const dlg = await screen.findByRole('dialog', { name: '공통 메뉴·공지 적용' })
      await u.type(within(dlg).getByLabelText('중식 공통 메뉴'), text)
      if (remove) await u.click(within(dlg).getByLabelText(/^제거/))
      await u.click(within(dlg).getByRole('button', { name: '적용' }))
    }
    await apply('김치/샐러드')   // 김치 is already on the menu (not shared): it is not added a second time
    const box = screen.getByLabelText(`${d(0)} 중식 메뉴`) as HTMLTextAreaElement
    expect(box.value).toBe('제육볶음\n김치\n샐러드')
    await apply('김치/샐러드')   // nothing left to add
    expect(await screen.findByText(/적용할 메뉴가 없었어요/)).toBeTruthy()
    await apply('김치/샐러드', true)   // removes only the shared 샐러드; the typed-in 김치 was never shared
    expect((screen.getByLabelText(`${d(0)} 중식 메뉴`) as HTMLTextAreaElement).value).toBe('제육볶음\n김치')
  }, 30000)

  it('HALAL is stored together with its confirmation, and unticking removes both', async () => {
    await openWeek({ live: [meal(d(4), 'lunch')] })
    const u = user()
    await u.click(screen.getByLabelText(`${d(4)} 중식 HALAL`))
    await u.click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/한 주 전체를 초안으로 저장했어요/)
    expect(saved().p_data.meals[0].extra).toMatchObject({ labels: ['HALAL'], labels_verified: true })
  }, 30000)

  it('unticking HALAL removes the label and its confirmation from the saved week', async () => {
    await openWeek({ live: [meal(d(4), 'lunch', { extra: { labels: ['HALAL'], labels_verified: true, notice: '유지' } })] })
    const u = user()
    expect((screen.getByLabelText(`${d(4)} 중식 HALAL`) as HTMLInputElement).checked).toBe(true)
    await u.click(screen.getByLabelText(`${d(4)} 중식 HALAL`))
    await u.click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/한 주 전체를 초안으로 저장했어요/)
    expect(saved().p_data.meals[0].extra).toEqual({ notice: '유지' })
  }, 30000)
})
