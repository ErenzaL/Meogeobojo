import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import { addDays, weekStart } from '../CafeteriaPage'
import { cafeteriaRow, cafeteriaTitle, emptyCafeteriaForm, validateCafeteria } from './model'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})
vi.mock('@/lib/images', async (orig) => ({
  ...(await orig<typeof import('@/lib/images')>()),
  prepareImage: async (f: File) => ({ blob: f, type: f.type, width: 800, height: 600, bytes: f.size }),
}))

describe('cafeteria form logic', () => {
  it('needs a university; names stay empty unless confirmed (never invented)', () => {
    expect(validateCafeteria(emptyCafeteriaForm()).university_id).toBeTruthy()
    const f = { ...emptyCafeteriaForm('u1'), kind: 'dormitory' as const }
    expect(validateCafeteria(f)).toEqual({})
    expect(cafeteriaRow(f)).toMatchObject({ university_id: 'u1', kind: 'dormitory', name_ko: null, name_en: null, name_zh: null, location_description: null, operating_note: null, status: 'active' })
  })
  it('trims, bounds and validates', () => {
    const f = { ...emptyCafeteriaForm('u1'), name_ko: ' 학생식당 ', sort_order: ' 3 ', location: ' 1층 ' }
    expect(cafeteriaRow(f)).toMatchObject({ name_ko: '학생식당', sort_order: 3, location_description: '1층' })
    expect(validateCafeteria({ ...f, name_ko: '가'.repeat(61), operating_note: '가'.repeat(301), sort_order: 'x' })).toMatchObject({ name_ko: expect.any(String), operating_note: expect.any(String), sort_order: expect.any(String) })
  })
  it('an unnamed cafeteria is labelled by its kind, not a made-up name', () => {
    expect(cafeteriaTitle({ name_ko: null, kind: 'student' })).toBe('학생식당 (이름 미확인)')
    expect(cafeteriaTitle({ name_ko: '교직원식당', kind: 'staff' })).toBe('교직원식당')
  })
})

const CAF = (over: Record<string, unknown> = {}) => ({ id: 'c1', university_id: 'u1', kind: 'student', name_ko: '학생식당', name_en: null, name_zh: null, location_description: null, sort_order: 0, status: 'active', operating_note: null, universities: { name_ko: '순천향대학교' }, ...over })
const UNIS = [{ id: 'u1', name_ko: '순천향대학교', is_active: true }, { id: 'u2', name_ko: '호서대학교', is_active: true }]
const MON = () => weekStart(new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date()))

async function open(cafeterias: unknown[] = [CAF()], meals: unknown[] = []) {
  fake.respond('universities:select', { data: UNIS })
  fake.respond('campus_cafeterias:select', { data: cafeterias })
  fake.respond('cafeteria_meals:select', { data: meals })
  render(<MemoryRouter initialEntries={['/cafeteria']}><App client={makeQueryClient()} /></MemoryRouter>)
  await screen.findByRole('button', { name: /학식 식당 추가/ })
  const active = (cafeterias as { status: string; university_id: string }[]).filter((c) => c.status === 'active' && c.university_id === 'u1').length
  if (active > 0) await waitFor(() => expect(within(screen.getByLabelText('학식 식당')).getAllByRole('option').length).toBeGreaterThanOrEqual(active + 1))
  else await waitFor(() => expect(fake.calls.some((c) => c.table === 'campus_cafeterias')).toBe(true))
}

beforeEach(() => {
  fake.reset(); fake.signInAs('admin')
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('학식 식당 추가 / 수정', () => {
  it('creates a cafeteria with only the confirmed information and selects it', async () => {
    fake.respond('campus_cafeterias:insert', { data: [{ id: 'new1' }] })
    await open([])
    expect(await screen.findByText(/등록된 학식 식당이 없어요/)).toBeTruthy()
    await userEvent.click(screen.getByRole('button', { name: /학식 식당 추가/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 추가' })
    // the university being managed is preselected; clearing it must block saving
    expect((within(modal).getByLabelText('대학교') as HTMLSelectElement).value).toBe('u1')
    await userEvent.selectOptions(within(modal).getByLabelText('대학교'), '')
    await userEvent.click(within(modal).getByRole('button', { name: '추가' }))
    expect(await within(modal).findByText('대학교를 선택해 주세요')).toBeTruthy() // university is required
    expect(fake.last('campus_cafeterias', 'insert')).toBeUndefined()
    await userEvent.selectOptions(within(modal).getByLabelText('대학교'), 'u1')
    await userEvent.type(within(modal).getByLabelText(/이름 \(한국어\)/), '학생식당')
    await userEvent.type(within(modal).getByLabelText(/위치/), '학생회관 1층')
    await userEvent.click(within(modal).getByRole('button', { name: '추가' }))
    await screen.findByText(/학식 식당을 만들었어요/)
    expect(fake.last('campus_cafeterias', 'insert')!.payload).toEqual({
      university_id: 'u1', kind: 'student', name_ko: '학생식당', name_en: null, name_zh: null, location_description: '학생회관 1층', sort_order: 0, status: 'active', operating_note: null,
    })
  })

  it('says clearly when the same cafeteria already exists on that campus', async () => {
    fake.respond('campus_cafeterias:insert', { error: { code: '23505', message: 'duplicate key value violates unique constraint "campus_cafeterias_unique_name"' } })
    await open([])
    await userEvent.click(screen.getByRole('button', { name: /학식 식당 추가/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 추가' })
    await userEvent.selectOptions(within(modal).getByLabelText('대학교'), 'u1')
    await userEvent.type(within(modal).getByLabelText(/이름 \(한국어\)/), '학생식당')
    await userEvent.click(within(modal).getByRole('button', { name: '추가' }))
    expect(await within(modal).findByText(/같은 이름의 학식 식당이 이미 있어요/)).toBeTruthy()
  })

  it('edits a cafeteria in place; the university cannot be moved', async () => {
    await open()
    await userEvent.selectOptions(screen.getByLabelText('학식 식당'), 'c1')
    await userEvent.click(screen.getByRole('button', { name: /식당 정보 수정/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 수정' })
    expect((within(modal).getByLabelText('대학교') as HTMLSelectElement).disabled).toBe(true)
    const note = within(modal).getByLabelText(/운영 안내/)
    await userEvent.type(note, '평일 11:30~13:30')
    await userEvent.click(within(modal).getByRole('button', { name: '저장' }))
    await screen.findByText(/정보를 저장했어요/)
    expect(fake.last('campus_cafeterias', 'update')!.payload).toMatchObject({ name_ko: '학생식당', operating_note: '평일 11:30~13:30' })
  })
})

describe('활성화 · 비활성화 · 보관', () => {
  it('deactivating asks first, then hides the cafeteria from students without deleting anything', async () => {
    await open()
    await userEvent.selectOptions(screen.getByLabelText('학식 식당'), 'c1')
    await userEvent.click(screen.getByRole('button', { name: /비활성화/ }))
    expect(fake.last('campus_cafeterias', 'update')).toBeUndefined() // nothing before the confirmation
    await userEvent.click(await screen.findByRole('button', { name: '비활성화', hidden: true }).catch(() => screen.getAllByRole('button', { name: '비활성화' }).at(-1)!))
    await screen.findByText(/비활성으로 바꿨어요/)
    expect(fake.last('campus_cafeterias', 'update')!.payload).toEqual({ status: 'inactive' })
    expect(fake.last('cafeteria_meals', 'delete')).toBeUndefined()
  })

  it('archiving is a status change, never a delete; an inactive one can be restored', async () => {
    await open([CAF({ status: 'inactive' })])
    await userEvent.click(screen.getByLabelText(/비활성·보관된 식당도 보기/))
    await userEvent.selectOptions(screen.getByLabelText('학식 식당'), 'c1')
    await userEvent.click(screen.getByRole('button', { name: /운영 중으로/ }))
    await userEvent.click(screen.getAllByRole('button', { name: '운영 중으로' }).at(-1)!)
    await screen.findByText(/다시 운영 중으로 바꿨어요/)
    expect(fake.last('campus_cafeterias', 'update')!.payload).toEqual({ status: 'active' })
    expect(fake.last('campus_cafeterias', 'delete')).toBeUndefined()
  })

  it('inactive and archived cafeterias are hidden from the picker until asked', async () => {
    await open([CAF(), CAF({ id: 'c2', name_ko: '옛 식당', status: 'archived' })])
    const picker = screen.getByLabelText('학식 식당')
    expect(within(picker).queryByRole('option', { name: /옛 식당/ })).toBeNull()
    await userEvent.click(screen.getByLabelText(/비활성·보관된 식당도 보기/))
    expect(within(picker).getByRole('option', { name: /옛 식당 \(보관\)/ })).toBeTruthy()
  })
})

describe('대학교별 관리 · 검색', () => {
  const list = [CAF(), CAF({ id: 'c2', university_id: 'u2', name_ko: '호서 식당', universities: { name_ko: '호서대학교' } }), CAF({ id: 'c3', name_ko: '기숙사 식당', location_description: '생활관' })]
  const names = () => within(screen.getByLabelText('학식 식당')).getAllByRole('option').map((o) => o.textContent)
  it('always manages ONE university: only its cafeterias are listed, and there is no "all universities"', async () => {
    await open(list)
    expect(within(screen.getByLabelText('대학교')).queryByRole('option', { name: /모든 대학교/ })).toBeNull()
    expect((screen.getByLabelText('대학교') as HTMLSelectElement).value).toBe('u1')
    expect(names()).toEqual(['선택하세요', '학생식당', '기숙사 식당'])
    await userEvent.selectOptions(screen.getByLabelText('대학교'), 'u2')
    expect(names()).toEqual(['선택하세요', '호서 식당'])
    expect(screen.getByLabelText('대학교 현황').textContent).toContain('호서대학교: 학식 식당 1곳 운영 중')
  })
  it('shows how many cafeterias each university has', async () => {
    await open(list)
    const opts = within(screen.getByLabelText('대학교')).getAllByRole('option').map((o) => o.textContent)
    expect(opts).toEqual(['순천향대학교 (학식 2곳)', '호서대학교 (학식 1곳)'])
  })
  it('opens the first live cafeteria of the chosen university and queries only its meals', async () => {
    await open(list)
    await waitFor(() => expect((screen.getByLabelText('학식 식당') as HTMLSelectElement).value).toBe('c1'))
    await userEvent.selectOptions(screen.getByLabelText('대학교'), 'u2')
    await waitFor(() => expect((screen.getByLabelText('학식 식당') as HTMLSelectElement).value).toBe('c2'))
    await waitFor(() => {
      const q = [...fake.calls].reverse().find((c) => c.table === 'cafeteria_meals' && c.op === 'select')
      expect(q!.filters).toEqual(expect.arrayContaining([['eq', 'cafeteria_id', 'c2']]))
    })
  })
  it('a university with no cafeteria says so by name and offers to add one', async () => {
    await open([CAF()])
    await userEvent.selectOptions(screen.getByLabelText('대학교'), 'u2')
    expect(await screen.findByText(/호서대학교에 등록된 학식 식당이 없어요/)).toBeTruthy()
    await userEvent.click(screen.getByRole('button', { name: /학식 식당 추가/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 추가' })
    expect((within(modal).getByLabelText('대학교') as HTMLSelectElement).value).toBe('u2') // new ones start in the university being managed
  })
  it('searches by name and location within the university', async () => {
    await open(list)
    await userEvent.type(screen.getByLabelText('식당 검색'), '생활관')
    expect(names()).toEqual(['선택하세요', '기숙사 식당'])
    await userEvent.clear(screen.getByLabelText('식당 검색'))
    await userEvent.type(screen.getByLabelText('식당 검색'), '호서')
    expect(names()).toEqual(['식당 없음']) // another university's cafeteria never matches here
  })
})

describe('식사별 구간 · 확인 정보', () => {
  const meal = (over: Record<string, unknown> = {}) => ({
    id: 'm1', cafeteria_id: 'c1', meal_date: addDays(MON(), 1), meal_type: 'lunch', option_name: '', option_order: 0, menu_items: [{ name_ko: '김치찌개', kind: 'main' }],
    price_krw: 5500, start_time: '11:30:00', end_time: '13:30:00', badge: null, status: 'published', source_url: 'https://example.org/menu', verified_at: '2026-11-09T00:00:00+09:00', extra: {}, ...over,
  })
  async function pick() { await userEvent.selectOptions(screen.getByLabelText('학식 식당'), 'c1') }

  it('shows 조식 / 중식 / 석식 separately; a missing meal says so and creates nothing', async () => {
    await open([CAF()], [meal()])
    await pick()
    const day = await screen.findByRole('region', { name: new RegExp(addDays(MON(), 1)) })
    expect(within(day).getByRole('group', { name: /중식/ })).toBeTruthy()
    expect(within(day).getByText('조식 · 등록 안 함')).toBeTruthy()
    expect(within(day).getByText('석식 · 등록 안 함')).toBeTruthy()
    expect(fake.last('cafeteria_meals', 'upsert')).toBeUndefined()
    await userEvent.click(within(day).getByRole('button', { name: '+ 조식 추가' }))
    expect((screen.getByLabelText('식사') as HTMLSelectElement).value).toBe('breakfast')
    expect((screen.getByLabelText('날짜') as HTMLInputElement).value).toBe(addDays(MON(), 1))
    expect(fake.last('cafeteria_meals', 'upsert')).toBeUndefined() // still nothing saved
  })

  it('a day with no meals at all is one honest empty line, not three invented slots', async () => {
    await open([CAF()], [])
    await pick()
    const day = await screen.findByRole('region', { name: new RegExp(MON()) })
    expect(within(day).getByText(/등록된 식단 없음/)).toBeTruthy()
    expect(within(day).queryByText(/등록 안 함/)).toBeNull()
  })

  it('shows when and where the information was verified', async () => {
    await open([CAF()], [meal(), meal({ id: 'm2', meal_type: 'dinner', source_url: null })])
    await pick()
    expect(await screen.findAllByText(/확인 2026-11-09/)).toHaveLength(2)
    expect(screen.getByRole('link', { name: '출처' }).getAttribute('href')).toBe('https://example.org/menu')
    expect(screen.getByText(/출처 없음/)).toBeTruthy()
  })

  it('saves the verified date and a 천원의 아침밥 only with an official source', async () => {
    await open([CAF()], [])
    await pick()
    await userEvent.click(await screen.findByRole('button', { name: '천원의 아침밥' }))
    await userEvent.type(screen.getByLabelText(/메뉴 \(한 줄/), '북엇국')
    await userEvent.click(screen.getByRole('button', { name: '저장' }))
    expect(await screen.findByText(/공식 출처 주소가 있어야/)).toBeTruthy() // blocked: no source
    expect(fake.last('cafeteria_meals', 'upsert')).toBeUndefined()
    await userEvent.type(screen.getByLabelText('출처 주소'), 'https://example.org/morning')
    const verified = screen.getByLabelText('확인한 날짜')
    await userEvent.clear(verified); await userEvent.type(verified, '2026-11-09')
    await userEvent.click(screen.getByRole('button', { name: '저장' }))
    await waitFor(() => expect(fake.last('cafeteria_meals', 'upsert')).toBeTruthy())
    expect(fake.last('cafeteria_meals', 'upsert')!.payload).toMatchObject({ meal_type: 'breakfast', badge: '천원의 아침밥', price_krw: 1000, source_url: 'https://example.org/morning', verified_at: '2026-11-09T00:00:00+09:00', cafeteria_id: 'c1' })
  })

  it('two corners of the same meal are two rows, never one overwriting the other', async () => {
    await open([CAF()], [meal(), meal({ id: 'm3', option_name: 'B코너', option_order: 1, menu_items: [{ name_ko: '돈까스', kind: 'main' }] })])
    await pick()
    const lunch = await screen.findByRole('group', { name: new RegExp(`${addDays(MON(), 1)} 중식`) })
    expect(within(lunch).getByText('김치찌개')).toBeTruthy()
    expect(within(lunch).getByText('돈까스')).toBeTruthy()
    await userEvent.click(within(lunch).getAllByRole('button', { name: '수정' })[1])
    await userEvent.click(screen.getByRole('button', { name: '저장' }))
    await waitFor(() => expect(fake.last('cafeteria_meals', 'upsert')).toBeTruthy())
    expect(fake.last('cafeteria_meals', 'upsert')!.payload).toMatchObject({ option_name: 'B코너' }) // keyed by (cafeteria, date, type, corner)
    expect(fake.calls.find((c) => c.table === 'cafeteria_meals' && c.op === 'upsert')!.filters).toBeDefined()
  })

  it('the edit form shows the current photo and can replace it', async () => {
    const BASE = 'https://x.supabase.co/storage/v1/object/public/restaurant-images/'
    await open([CAF()], [meal({ extra: { photo_url: `${BASE}cafeteria/c1/a.jpg`, photo_path: 'cafeteria/c1/a.jpg' } })])
    await pick()
    await userEvent.click(await screen.findByRole('button', { name: '수정' }))
    expect((await screen.findByAltText('현재 음식 사진')).getAttribute('src')).toBe(`${BASE}cafeteria/c1/a.jpg`)
    await userEvent.upload(screen.getByLabelText('이 식단 사진 올리기'), new File(['x'], 'p.jpg', { type: 'image/jpeg' }))
    await waitFor(() => expect(fake.removed).toEqual(['cafeteria/c1/a.jpg']))
  })
})
