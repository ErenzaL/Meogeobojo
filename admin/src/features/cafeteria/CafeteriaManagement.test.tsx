import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import { cafeteriaRow, cafeteriaTitle, emptyCafeteriaForm, nextSortOrder, periodsOf, daysOf, validateCafeteria } from './model'

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
    expect(cafeteriaRow(f)).toMatchObject({ university_id: 'u1', kind: 'dormitory', name_ko: null, name_en: null, name_zh: null, location_description: null, operating_note: null })
  })
  it('a new cafeteria starts INACTIVE: students see nothing until an admin switches it on', () => {
    expect(emptyCafeteriaForm('u1').status).toBe('inactive')
  })
  it('does not assume every meal or weekday: at least one of each is required, and the order is canonical', () => {
    const f = emptyCafeteriaForm('u1')
    expect(validateCafeteria({ ...f, meal_periods: [] }).meal_periods).toBeTruthy()
    expect(validateCafeteria({ ...f, operating_days: [] }).operating_days).toBeTruthy()
    expect(cafeteriaRow({ ...f, meal_periods: ['dinner', 'lunch'], operating_days: [6, 1, 3] })).toMatchObject({ meal_periods: ['lunch', 'dinner'], operating_days: [1, 3, 6] })
  })
  it('a database without the weekly columns reports Monday-Friday and all three meals', () => {
    expect(periodsOf({})).toEqual(['breakfast', 'lunch', 'dinner'])
    expect(daysOf({})).toEqual([1, 2, 3, 4, 5])
    expect(periodsOf({ meal_periods: ['lunch'] })).toEqual(['lunch'])
  })
  it('trims, bounds and validates', () => {
    const f = { ...emptyCafeteriaForm('u1'), name_ko: ' 학생식당 ', sort_order: ' 3 ', location: ' 1층 ' }
    expect(cafeteriaRow(f)).toMatchObject({ name_ko: '학생식당', sort_order: 3, location_description: '1층' })
    expect(validateCafeteria({ ...f, name_ko: '가'.repeat(61), operating_note: '가'.repeat(301), sort_order: 'x' })).toMatchObject({ name_ko: expect.any(String), operating_note: expect.any(String), sort_order: expect.any(String) })
  })
  it('a new cafeteria is ordered after the university\'s others, so it never takes the first place', () => {
    const c = (university_id: string, sort_order: number, status = 'active') => ({ university_id, sort_order, status }) as never
    expect(nextSortOrder([], 'u1')).toBe('0')
    expect(nextSortOrder([c('u1', 1)], 'u1')).toBe('2')
    expect(nextSortOrder([c('u1', 1), c('u1', 4), c('u2', 9)], 'u1')).toBe('5')
    expect(nextSortOrder([c('u1', 7, 'archived')], 'u1')).toBe('0')
  })
  it('an unnamed cafeteria is labelled by its kind, not a made-up name', () => {
    expect(cafeteriaTitle({ name_ko: null, kind: 'student' })).toBe('학생식당 (이름 미확인)')
    expect(cafeteriaTitle({ name_ko: '교직원식당', kind: 'staff' })).toBe('교직원식당')
  })
})

const CAF = (over: Record<string, unknown> = {}) => ({ id: 'c1', university_id: 'u1', kind: 'student', name_ko: '학생식당', name_en: null, name_zh: null, location_description: null, sort_order: 0, status: 'active', operating_note: null, meal_periods: ['breakfast', 'lunch', 'dinner'], operating_days: [1, 2, 3, 4, 5], photo_url: null, photo_path: null, universities: { name_ko: '순천향대학교' }, ...over })
const UNIS = [{ id: 'u1', name_ko: '순천향대학교', is_active: true }, { id: 'u2', name_ko: '호서대학교', is_active: true }]

async function open(cafeterias: unknown[] = [CAF()], weeks: unknown[] = [], overview: unknown[] = []) {
  fake.respond('universities:select', { data: UNIS })
  fake.respond('campus_cafeterias:select', { data: cafeterias })
  fake.respond('cafeteria_weeks:select', { data: weeks })
  fake.respond('rpc:cms_overview', { data: overview })
  fake.respond('rpc:cafeteria_week_entity', { data: 'w1' })
  fake.respond('rpc:cms_state', { data: { live: { meals: [] }, live_version: 0, last_published: null, draft: null, jobs: [] } })
  render(<MemoryRouter initialEntries={['/cafeteria']}><App client={makeQueryClient()} /></MemoryRouter>)
  await screen.findByRole('button', { name: /학식 식당 추가/ })
  await waitFor(() => expect(fake.calls.some((c) => c.table === 'campus_cafeterias')).toBe(true))
}
const list = () => screen.getByLabelText('학식 식당 목록')
const names = () => within(list()).queryAllByRole('button', { name: /메뉴 관리$/ }).map((b) => b.getAttribute('aria-label')!.replace(' 메뉴 관리', ''))
const openCaf = async (name = '학생식당') => userEvent.click(await screen.findByRole('button', { name: `${name} 메뉴 관리` }))

beforeEach(() => {
  fake.reset(); fake.signInAs('admin')
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('학식 식당 추가 / 수정', () => {
  it('creates a cafeteria with only the confirmed information, INACTIVE, and selects it', async () => {
    fake.respond('campus_cafeterias:insert', { data: [{ id: 'new1' }] })
    await open([])
    expect(await screen.findByText(/등록된 학식 식당이 없어요/)).toBeTruthy()
    await userEvent.click(screen.getByRole('button', { name: /학식 식당 추가/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 추가' })
    expect((within(modal).getByLabelText('대학교') as HTMLSelectElement).value).toBe('u1')
    await userEvent.selectOptions(within(modal).getByLabelText('대학교'), '')
    await userEvent.click(within(modal).getByRole('button', { name: '추가' }))
    expect(await within(modal).findByText('대학교를 선택해 주세요')).toBeTruthy()
    expect(fake.last('campus_cafeterias', 'insert')).toBeUndefined()
    await userEvent.selectOptions(within(modal).getByLabelText('대학교'), 'u1')
    await userEvent.type(within(modal).getByLabelText(/이름 \(한국어\)/), '학생식당')
    await userEvent.type(within(modal).getByLabelText(/위치/), '학생회관 1층')
    await userEvent.click(within(modal).getByLabelText('운영 식사 석식')) // this cafeteria does not serve dinner
    await userEvent.click(within(modal).getByLabelText('운영 요일 토'))   // but opens on Saturdays
    await userEvent.click(within(modal).getByRole('button', { name: '추가' }))
    await screen.findByText(/학식 식당을 만들었어요/)
    expect(fake.last('campus_cafeterias', 'insert')!.payload).toEqual({
      university_id: 'u1', kind: 'student', name_ko: '학생식당', name_en: null, name_zh: null, location_description: '학생회관 1층', sort_order: 0, status: 'inactive', operating_note: null,
      meal_periods: ['breakfast', 'lunch'], operating_days: [1, 2, 3, 4, 5, 6], photo_url: null, photo_path: null,
    })
  })

  it('a second cafeteria is ordered after the first and must be told apart by name', async () => {
    await open([CAF({ sort_order: 1 })])
    await userEvent.click(screen.getByRole('button', { name: /학식 식당 추가/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 추가' })
    expect((within(modal).getByLabelText('표시 순서', { exact: false }) as HTMLInputElement).value).toBe('2')
    // the campus already has one: a nameless second one could not be told apart in the app
    expect(within(modal).getByText(/여러 곳이에요/)).toBeTruthy()
    await userEvent.type(within(modal).getByLabelText(/이름 \(한국어\)/), '학생회관식당')
    expect(within(modal).queryByText(/여러 곳이에요/)).toBeNull()
  })

  it('the first cafeteria of a campus needs no such reminder, and the order follows the chosen university', async () => {
    await open([CAF({ sort_order: 3 })])
    await userEvent.click(screen.getByRole('button', { name: /학식 식당 추가/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 추가' })
    const order = () => (within(modal).getByLabelText('표시 순서', { exact: false }) as HTMLInputElement).value
    expect(order()).toBe('4')
    await userEvent.selectOptions(within(modal).getByLabelText('대학교'), 'u2')
    expect(order()).toBe('0')
    expect(within(modal).queryByText(/여러 곳이에요/)).toBeNull()
    // an order typed by hand is kept when the university changes afterwards
    await userEvent.clear(within(modal).getByLabelText('표시 순서', { exact: false }))
    await userEvent.type(within(modal).getByLabelText('표시 순서', { exact: false }), '8')
    await userEvent.selectOptions(within(modal).getByLabelText('대학교'), 'u1')
    expect(order()).toBe('8')
  })

  it('editing a cafeteria never asks for a name just because it has no siblings, and only counts the others', async () => {
    await open([CAF({ name_ko: null })]); await openCaf('학생식당 (이름 미확인)')
    await userEvent.click(screen.getByRole('button', { name: /식당 정보 수정/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 수정' })
    expect(within(modal).queryByText(/여러 곳이에요/)).toBeNull()
  })

  it('refuses a cafeteria that serves no meal at all', async () => {
    await open([])
    await userEvent.click(screen.getByRole('button', { name: /학식 식당 추가/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 추가' })
    for (const m of ['조식', '중식', '석식']) await userEvent.click(within(modal).getByLabelText(`운영 식사 ${m}`))
    await userEvent.click(within(modal).getByRole('button', { name: '추가' }))
    expect(await within(modal).findByText('운영하는 식사를 하나 이상 골라 주세요')).toBeTruthy()
    expect(fake.last('campus_cafeterias', 'insert')).toBeUndefined()
  })

  it('says clearly when the same cafeteria already exists on that campus', async () => {
    fake.respond('campus_cafeterias:insert', { error: { code: '23505', message: 'duplicate key value violates unique constraint "campus_cafeterias_unique_name"' } })
    await open([])
    await userEvent.click(screen.getByRole('button', { name: /학식 식당 추가/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 추가' })
    await userEvent.type(within(modal).getByLabelText(/이름 \(한국어\)/), '학생식당')
    await userEvent.click(within(modal).getByRole('button', { name: '추가' }))
    expect(await within(modal).findByText(/같은 이름의 학식 식당이 이미 있어요/)).toBeTruthy()
  })

  it('edits a cafeteria in place, keeping its id', async () => {
    await open(); await openCaf()
    await userEvent.click(screen.getByRole('button', { name: /식당 정보 수정/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 수정' })
    await userEvent.type(within(modal).getByLabelText(/운영 안내/), '평일 11:30~13:30')
    await userEvent.click(within(modal).getByRole('button', { name: '저장' }))
    await screen.findByText(/정보를 저장했어요/)
    expect(fake.last('campus_cafeterias', 'update')!.payload).toMatchObject({ name_ko: '학생식당', operating_note: '평일 11:30~13:30', university_id: 'u1' })
    expect(fake.last('campus_cafeterias', 'update')!.filters).toEqual(expect.arrayContaining([['eq', 'id', 'c1']]))
  })

  it('moving a cafeteria to another university needs a second, explicit confirmation', async () => {
    await open(); await openCaf()
    await userEvent.click(screen.getByRole('button', { name: /식당 정보 수정/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 수정' })
    await userEvent.selectOptions(within(modal).getByLabelText('대학교'), 'u2')
    expect(within(modal).getByText(/다른 대학교로 옮기면/)).toBeTruthy()
    await userEvent.click(within(modal).getByRole('button', { name: '저장' }))
    expect(await screen.findByText('다른 대학교로 옮길까요?')).toBeTruthy()
    expect(fake.last('campus_cafeterias', 'update')).toBeUndefined()
    await userEvent.click(screen.getByRole('button', { name: '옮기고 저장' }))
    await waitFor(() => expect(fake.last('campus_cafeterias', 'update')).toBeTruthy())
    expect(fake.last('campus_cafeterias', 'update')!.payload).toMatchObject({ university_id: 'u2' })
  })

  it('uploads a cafeteria photo; replacing it on save removes the old file, cancelling removes the new one', async () => {
    const BASE = 'https://x.supabase.co/storage/v1/object/public/restaurant-images/'
    await open([CAF({ photo_url: `${BASE}cafeterias/old.jpg`, photo_path: 'cafeterias/old.jpg' })]); await openCaf()
    await userEvent.click(screen.getByRole('button', { name: /식당 정보 수정/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 수정' })
    expect((within(modal).getByAltText('식당 사진') as HTMLImageElement).src).toContain('cafeterias/old.jpg')
    await userEvent.upload(within(modal).getByLabelText('식당 사진 올리기'), new File(['x'], 'p.jpg', { type: 'image/jpeg' }))
    await waitFor(() => expect(fake.uploads).toHaveLength(1))
    expect(fake.uploads[0].path).toMatch(/^cafeterias\/[0-9a-f-]{36}\.jpg$/)
    expect(fake.removed).toEqual([])
    await userEvent.click(within(modal).getByRole('button', { name: '저장' }))
    await waitFor(() => expect(fake.removed).toEqual(['cafeterias/old.jpg']))
    expect((fake.last('campus_cafeterias', 'update')!.payload as { photo_path: string }).photo_path).toBe(fake.uploads[0].path)
  })
  it('cancelling the dialog deletes a photo that was uploaded but never saved', async () => {
    await open(); await openCaf()
    await userEvent.click(screen.getByRole('button', { name: /식당 정보 수정/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 수정' })
    await userEvent.upload(within(modal).getByLabelText('식당 사진 올리기'), new File(['x'], 'p.jpg', { type: 'image/jpeg' }))
    await waitFor(() => expect(fake.uploads).toHaveLength(1))
    await userEvent.click(within(modal).getByRole('button', { name: '취소' }))
    await waitFor(() => expect(fake.removed).toEqual([fake.uploads[0].path]))
  })

  it('on a database without the weekly migration the new fields are disabled and not sent', async () => {
    fake.respond('campus_cafeterias:select', (c: { filters: [string, ...unknown[]][] }) => ({ data: [CAF()], error: JSON.stringify(c.filters).includes('meal_periods') ? { code: '42703', message: 'column campus_cafeterias.meal_periods does not exist' } : null }))
    fake.respond('universities:select', { data: UNIS })
    fake.respond('campus_cafeterias:insert', { data: [{ id: 'n' }] })
    render(<MemoryRouter initialEntries={['/cafeteria']}><App client={makeQueryClient()} /></MemoryRouter>)
    expect(await screen.findByText(/20261118000100/)).toBeTruthy()
    await userEvent.click(screen.getByRole('button', { name: /학식 식당 추가/ }))
    const modal = await screen.findByRole('dialog', { name: '학식 식당 추가' })
    await userEvent.type(within(modal).getByLabelText(/이름 \(한국어\)/), '새 식당')
    await userEvent.click(within(modal).getByRole('button', { name: '추가' }))
    await waitFor(() => expect(fake.last('campus_cafeterias', 'insert')).toBeTruthy())
    const row = fake.last('campus_cafeterias', 'insert')!.payload as Record<string, unknown>
    expect(row).not.toHaveProperty('meal_periods'); expect(row).not.toHaveProperty('operating_days'); expect(row).not.toHaveProperty('photo_url')
  })
})

describe('활성화 · 비활성화 · 보관', () => {
  it('deactivating asks first, then hides the cafeteria from students without deleting anything', async () => {
    await open(); await openCaf()
    await userEvent.click(screen.getByRole('button', { name: /비활성화/ }))
    expect(await screen.findByText(/비활성화할까요/)).toBeTruthy()
    expect(fake.last('campus_cafeterias', 'update')).toBeUndefined()
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: '비활성화' }))
    await screen.findByText(/비활성으로 바꿨어요/)
    expect(fake.last('campus_cafeterias', 'update')!.payload).toEqual({ status: 'inactive' })
    expect(fake.last('campus_cafeterias', 'delete')).toBeUndefined()
  })
  it('archiving is a status change, never a delete; an inactive one can be switched back on', async () => {
    await open([CAF({ status: 'inactive' })]); await openCaf()
    expect(screen.getByText(/앱에 보이지 않아요/)).toBeTruthy()
    await userEvent.click(screen.getByRole('button', { name: /운영 중으로/ }))
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: '운영 중으로' }))
    await waitFor(() => expect(fake.last('campus_cafeterias', 'update')!.payload).toEqual({ status: 'active' }))
    await userEvent.click(await screen.findByRole('button', { name: /^보관$|보관/ }))
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: '보관' }))
    await waitFor(() => expect(fake.last('campus_cafeterias', 'update')!.payload).toEqual({ status: 'archived' }))
    expect(fake.last('campus_cafeterias', 'delete')).toBeUndefined()
  })
  it('the status filter hides archived ones by default and can show each state', async () => {
    await open([CAF({ id: 'a', name_ko: '운영식당' }), CAF({ id: 'b', name_ko: '비활성식당', status: 'inactive' }), CAF({ id: 'c', name_ko: '보관식당', status: 'archived' })])
    expect(names()).toEqual(['운영식당', '비활성식당'])
    await userEvent.selectOptions(screen.getByLabelText('상태'), 'archived')
    expect(names()).toEqual(['보관식당'])
    await userEvent.selectOptions(screen.getByLabelText('상태'), 'active')
    expect(names()).toEqual(['운영식당'])
    await userEvent.selectOptions(screen.getByLabelText('상태'), 'all')
    expect(names()).toHaveLength(3)
  })
})

describe('대학교별 관리 · 검색', () => {
  const list2 = [CAF(), CAF({ id: 'c2', name_ko: '기숙사 식당', kind: 'dormitory', location_description: '생활관 1층' }), CAF({ id: 'c3', university_id: 'u2', name_ko: '호서 학생식당', universities: { name_ko: '호서대학교' } })]
  it('always manages ONE university: only its cafeterias are listed, and there is no "all universities"', async () => {
    await open(list2)
    expect(names()).toEqual(['학생식당', '기숙사 식당'])
    expect(within(screen.getByLabelText('대학교')).queryByRole('option', { name: /전체|모든/ })).toBeNull()
    await userEvent.selectOptions(screen.getByLabelText('대학교'), 'u2')
    expect(names()).toEqual(['호서 학생식당'])
  })
  it('shows how many cafeterias each university has and a status summary', async () => {
    await open(list2)
    expect(within(screen.getByLabelText('대학교')).getByRole('option', { name: /순천향대학교 \(학식 2곳\)/ })).toBeTruthy()
    expect(within(screen.getByLabelText('대학교')).getByRole('option', { name: /호서대학교 \(학식 1곳\)/ })).toBeTruthy()
    expect(within(screen.getByLabelText('대학교 현황')).getByText('2')).toBeTruthy()
  })
  it('a university with no cafeteria says so by name and offers to add one', async () => {
    await open([CAF()])
    await userEvent.selectOptions(screen.getByLabelText('대학교'), 'u2')
    expect(await screen.findByText(/호서대학교에 등록된 학식 식당이 없어요/)).toBeTruthy()
    await userEvent.click(screen.getByRole('button', { name: /학식 식당 추가/ }))
    expect((within(await screen.findByRole('dialog', { name: '학식 식당 추가' })).getByLabelText('대학교') as HTMLSelectElement).value).toBe('u2')
  })
  it('searches by name and location within the university only', async () => {
    await open(list2)
    await userEvent.type(screen.getByLabelText('식당 검색'), '생활관')
    expect(names()).toEqual(['기숙사 식당'])
    await userEvent.clear(screen.getByLabelText('식당 검색')); await userEvent.type(screen.getByLabelText('식당 검색'), '호서')
    expect(screen.getByText('조건에 맞는 학식 식당이 없어요.')).toBeTruthy()
  })
  it('each card shows which meals it serves, whether it opens at weekends, and its status', async () => {
    await open([CAF({ meal_periods: ['lunch'], operating_days: [1, 2, 3, 4, 5, 6] })])
    const card = within(list())
    expect(card.getByText('중식')).toBeTruthy(); expect(card.queryByText('조식')).toBeNull(); expect(card.getByText('주말 운영')).toBeTruthy(); expect(card.getByText('운영 중')).toBeTruthy()
  })
  it('cards show the publishing state per cafeteria (draft weeks, scheduled, failed)', async () => {
    await open([CAF()], [{ id: 'w1', cafeteria_id: 'c1', week_start: '2026-11-09' }, { id: 'w2', cafeteria_id: 'c1', week_start: '2026-11-16' }],
      [{ entity_id: 'w1', has_draft: true, draft_updated_at: null, scheduled_at: null, failed_jobs: 0, live_version: 1, last_published_at: null }, { entity_id: 'w2', has_draft: false, draft_updated_at: null, scheduled_at: '2098-12-31T22:00:00Z', failed_jobs: 1, live_version: 1, last_published_at: null }])
    expect(await screen.findByText('게시 전 초안 1주')).toBeTruthy()
    expect(screen.getByText('예약 1주')).toBeTruthy(); expect(screen.getByText('실패 1주')).toBeTruthy()
  })
})

describe('식당 정보 · 게시 이력 탭', () => {
  it('the info tab lists the configuration; the history tab lists every publication of the cafeteria', async () => {
    fake.respond('content_versions:select', { data: [{ id: 5, entity_id: 'w1', version: 2, kind: 'publish', reason: '11월 2주차', published_at: '2026-11-09T22:00:00Z', published_by: null, rolled_back_from: null }] })
    await open([CAF({ meal_periods: ['lunch', 'dinner'], operating_days: [1, 2, 3, 4, 5, 6] })], [{ id: 'w1', cafeteria_id: 'c1', week_start: '2026-11-09' }]); await openCaf()
    await userEvent.click(screen.getByRole('tab', { name: '식당 정보' }))
    const info = screen.getByLabelText('식당 정보')
    expect(info.textContent).toMatch(/중식 · 석식/); expect(info.textContent).toMatch(/월 화 수 목 금 토/)
    await userEvent.click(screen.getByRole('tab', { name: '게시 이력' }))
    const hist = await screen.findByLabelText('식당 게시 이력')
    expect(within(hist).getByText(/v2 · 게시/)).toBeTruthy(); expect(within(hist).getByText(/11월 2주차/)).toBeTruthy()
    await userEvent.click(within(hist).getByRole('button', { name: '이 주 열기' }))
    expect(await screen.findByLabelText('주간 식단표')).toBeTruthy()
  })
})
