import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import { addDays, weekStart } from './CafeteriaPage'

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
    expect(weekStart('2026-11-10')).toBe('2026-11-09') // Tuesday
    expect(weekStart('2026-11-09')).toBe('2026-11-09') // Monday
    expect(weekStart('2026-11-15')).toBe('2026-11-09') // Sunday belongs to the week that began Monday
    expect(weekStart('2026-12-01')).toBe('2026-11-30')
  })
  it('adds days across months and years', () => {
    expect(addDays('2026-11-30', 1)).toBe('2026-12-01')
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01')
    expect(addDays('2026-11-09', -7)).toBe('2026-11-02')
  })
})

const BASE = 'https://x.supabase.co/storage/v1/object/public/restaurant-images/'
const meal = (over: Record<string, unknown> = {}) => ({
  id: 'm1', cafeteria_id: 'c1', meal_date: '2026-11-10', meal_type: 'lunch', option_name: '', option_order: 0, menu_items: [{ name_ko: '김치찌개', kind: 'main' }],
  price_krw: 5500, start_time: '11:30:00', end_time: '13:30:00', badge: null, status: 'published', source_url: null, extra: {}, ...over,
})
const CAF = { id: 'c1', university_id: 'u1', kind: 'student', name_ko: '학생식당', name_en: null, name_zh: null, location_description: '학생회관 1층', sort_order: 0, status: 'active', operating_note: null, universities: { name_ko: '순천향대학교' } }
const STATE = (d: string, over: Record<string, unknown> = {}) => ({ live: meal({ meal_date: d, ...((over.liveExtra as object) ? { extra: over.liveExtra } : {}) }), live_version: 2, last_published: null, draft: null, jobs: [], ...over })
const DRAFT = (d: string) => ({ data: { ...meal({ meal_date: d }), price_krw: 6000 }, revision: 1, base_version: 2, created_by: 'u-1', updated_by: 'u-1', created_at: '2026-11-09T00:00:00Z', updated_at: '2026-11-10T01:00:00Z', stale: false, has_changes: true })
const JOB = () => ({ id: 7, entity_type: 'cafeteria_meal', entity_id: 'm1', action: 'publish', base_version: 2, run_at: '2098-12-31T22:00:00Z', unpublish_at: null, status: 'scheduled', reason: null, created_by: 'u-1', created_at: '2026-11-10T00:00:00Z', attempts: 0, last_error: null, executed_at: null, published_version: null, parent_job_id: null })
const UNIS = [{ id: 'u1', name_ko: '순천향대학교', is_active: true }, { id: 'u2', name_ko: '호서대학교', is_active: true }]
async function openPage(rows: unknown[], cafeterias: unknown[] = [CAF]) {
  fake.respond('universities:select', { data: UNIS })
  fake.respond('campus_cafeterias:select', { data: cafeterias })
  fake.respond('cafeteria_meals:select', { data: rows })
  render(<MemoryRouter initialEntries={['/cafeteria']}><App client={makeQueryClient()} /></MemoryRouter>)
  await waitFor(() => expect(screen.getByRole('option', { name: /학생식당/ })).toBeTruthy())
  await userEvent.selectOptions(screen.getByLabelText('학식 식당'), 'c1')
}

beforeEach(() => {
  fake.reset(); fake.signInAs('admin')
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('학식 관리', () => {
  it('shows the week with a card per day, and says when a day has nothing', async () => {
    const mon = weekStartOfToday(); const tue = addDays(mon, 1); const wed = addDays(mon, 2)
    await openPage([meal({ meal_date: tue })])
    expect((await screen.findByLabelText('표시 중인 주')).textContent).toBe(`${mon} ~ ${addDays(mon, 6)}`)
    const day = await screen.findByRole('region', { name: new RegExp(tue) })
    expect(within(day).getByText('김치찌개')).toBeTruthy()
    expect(within(day).getByText(/5,500원 · 11:30–13:30/)).toBeTruthy()
    expect(within(screen.getByRole('region', { name: new RegExp(wed) })).getByText(/등록된 식단 없음/)).toBeTruthy()
  })

  it('previous / next week move the queried range', async () => {
    await openPage([])
    const label = await screen.findByLabelText('표시 중인 주')
    const start = label.textContent!.slice(0, 10)
    await userEvent.click(screen.getByRole('button', { name: '다음 주' }))
    await waitFor(() => expect(screen.getByLabelText('표시 중인 주').textContent!.slice(0, 10)).toBe(addDays(start, 7)))
    const q = fake.last('cafeteria_meals', 'select')!
    expect(q.filters).toEqual(expect.arrayContaining([['gte', 'meal_date', addDays(start, 7)], ['lte', 'meal_date', addDays(start, 13)]]))
    await userEvent.click(screen.getByRole('button', { name: '이번 주' }))
    await waitFor(() => expect(screen.getByLabelText('표시 중인 주').textContent!.slice(0, 10)).toBe(start))
  })

  it('adds a new meal as a hidden DRAFT row, never published', async () => {
    fake.respond('cafeteria_meals:insert', { data: { id: 'new1' } })
    await openPage([])
    await userEvent.click((await screen.findAllByRole('button', { name: /이 날 식단 추가/ }))[0])
    expect(screen.queryByLabelText('게시할 때의 상태')).toBeNull() // new meals are always drafts
    await userEvent.type(screen.getByLabelText(/메뉴 \(한 줄/), '북엇국')
    await userEvent.click(screen.getByRole('button', { name: '초안으로 추가' }))
    await screen.findByText(/초안으로 만들었어요. 앱에는 아직 보이지 않아요/)
    const row = fake.last('cafeteria_meals', 'insert')!.payload as Record<string, unknown>
    expect(row).toMatchObject({ status: 'draft', meal_type: 'lunch', cafeteria_id: 'c1' })
    expect(row.menu_items).toEqual([{ name_ko: '북엇국', kind: 'main' }])
    expect(fake.last('cafeteria_meals', 'upsert')).toBeUndefined()
  })

  it('refuses the same date / meal / corner instead of overwriting it', async () => {
    fake.respond('cafeteria_meals:insert', { error: { code: '23505', message: 'duplicate key' } })
    await openPage([])
    await userEvent.click((await screen.findAllByRole('button', { name: /이 날 식단 추가/ }))[0])
    await userEvent.type(screen.getByLabelText(/메뉴 \(한 줄/), '북엇국')
    await userEvent.click(screen.getByRole('button', { name: '초안으로 추가' }))
    expect(await screen.findByText(/같은 날짜·식사·코너의 식단이 이미 있어요/)).toBeTruthy()
  })

  it('saving the editor stores a DRAFT through the server and never writes the live meal', async () => {
    const d = weekStartOfToday()
    fake.respond('rpc:cms_state', { data: STATE(d, { liveExtra: { photo_url: `${BASE}cafeteria/c1/a.jpg`, photo_path: 'cafeteria/c1/a.jpg' } }) })
    fake.respond('rpc:cms_save_draft', { data: { revision: 1, base_version: 2, updated_at: '2026-11-10T00:00:00Z' } })
    await openPage([meal({ meal_date: d, extra: { photo_url: `${BASE}cafeteria/c1/a.jpg`, photo_path: 'cafeteria/c1/a.jpg' } })])
    await userEvent.click(await screen.findByRole('button', { name: '수정' }))
    await userEvent.type(await screen.findByLabelText(/공지/), '방학 중 운영')
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/초안을 저장했어요. 앱에는 아직 보이지 않아요/)
    const args = fake.rpcs.find((r) => r.name === 'cms_save_draft')!.args as { p_type: string; p_id: string; p_data: Record<string, unknown>; p_expected_revision: number }
    expect(args).toMatchObject({ p_type: 'cafeteria_meal', p_id: 'm1', p_expected_revision: 0 })
    expect(args.p_data).toMatchObject({ status: 'published', price_krw: 5500 })
    expect(args.p_data.extra).toEqual({ photo_url: `${BASE}cafeteria/c1/a.jpg`, photo_path: 'cafeteria/c1/a.jpg', notice: '방학 중 운영' })
    for (const op of ['update', 'upsert', 'insert', 'delete']) expect(fake.last('cafeteria_meals', op)).toBeUndefined() // live untouched
  })

  it('schedules the saved draft for a Seoul time; the server runs it', async () => {
    const d = weekStartOfToday()
    fake.respond('rpc:cms_state', { data: STATE(d, { draft: DRAFT(d) }) })
    fake.respond('rpc:cms_schedule', { data: 9 })
    await openPage([meal({ meal_date: d })])
    await userEvent.click(await screen.findByRole('button', { name: '수정' }))
    await userEvent.click(await screen.findByRole('button', { name: '예약 게시' }))
    const dlg = await screen.findByRole('dialog', { name: '예약 게시' })
    await userEvent.type(within(dlg).getByLabelText('게시 날짜'), '2099-01-01')
    await userEvent.clear(within(dlg).getByLabelText('게시 시간')); await userEvent.type(within(dlg).getByLabelText('게시 시간'), '07:00')
    await userEvent.click(within(dlg).getByRole('button', { name: '예약하기' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_schedule')).toBe(true))
    expect(fake.rpcs.find((r) => r.name === 'cms_schedule')!.args).toMatchObject({ p_type: 'cafeteria_meal', p_id: 'm1', p_run_at: '2098-12-31T22:00:00.000Z' })
  })

  it('cancels a scheduled publication', async () => {
    const d = weekStartOfToday()
    fake.respond('rpc:cms_state', { data: STATE(d, { draft: DRAFT(d), jobs: [JOB()] }) })
    fake.respond('rpc:cms_cancel_job', { data: null })
    await openPage([meal({ meal_date: d })])
    await userEvent.click(await screen.findByRole('button', { name: '수정' }))
    await userEvent.click(await screen.findByRole('button', { name: '예약 취소' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_cancel_job')).toBe(true))
    expect(fake.rpcs.find((r) => r.name === 'cms_cancel_job')!.args).toMatchObject({ p_job: 7 })
  })

  it('a new photo is only part of the draft: nothing is removed or written until it is published', async () => {
    const d = weekStartOfToday()
    fake.respond('rpc:cms_state', { data: STATE(d, { liveExtra: { notice: '공지', photo_url: `${BASE}cafeteria/c1/old.jpg`, photo_path: 'cafeteria/c1/old.jpg' } }) })
    fake.respond('rpc:cms_save_draft', { data: { revision: 1, base_version: 2, updated_at: '2026-11-10T00:00:00Z' } })
    await openPage([meal({ meal_date: d, extra: { notice: '공지', photo_url: `${BASE}cafeteria/c1/old.jpg`, photo_path: 'cafeteria/c1/old.jpg' } })])
    await userEvent.click(await screen.findByRole('button', { name: '수정' }))
    await userEvent.upload(await screen.findByLabelText('이 식단 사진 올리기'), new File(['x'], 'p.jpg', { type: 'image/jpeg' }))
    await screen.findByText(/사진을 골랐어요/)
    expect(fake.uploads[0].path).toMatch(/^cafeteria\/c1\/[0-9a-f-]{36}\.jpg$/)
    expect(fake.removed).toEqual([]) // the published photo file stays (restorable)
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    const data = (fake.rpcs.find((r) => r.name === 'cms_save_draft')!.args as { p_data: { extra: Record<string, string> } }).p_data
    expect(data.extra.notice).toBe('공지') // the rest of `extra` is preserved
    expect(data.extra.photo_path).toBe(fake.uploads[0].path)
    expect(fake.removed).toEqual([])
    expect(fake.last('cafeteria_meals', 'update')).toBeUndefined()
  })

  it('duplicates a meal to the same weekday next week as a draft, saving nothing yet', async () => {
    const d = weekStartOfToday()
    await openPage([meal({ meal_date: d })])
    await userEvent.click(await screen.findByRole('button', { name: '다음 주로 복제' }))
    expect((screen.getByLabelText('날짜') as HTMLInputElement).value).toBe(addDays(d, 7))
    expect((screen.getByLabelText(/메뉴 \(한 줄/) as HTMLTextAreaElement).value).toBe('김치찌개')
    expect(fake.last('cafeteria_meals', 'insert')).toBeUndefined()
  })

  it('publishes a draft and hides a published one through the audited, versioned server call', async () => {
    const d = weekStartOfToday()
    fake.respond('rpc:cms_set_visibility', { data: 4 })
    await openPage([meal({ id: 'd', meal_date: d, status: 'draft' }), meal({ id: 'p', meal_date: d, meal_type: 'dinner', status: 'published' })])
    await userEvent.click(await screen.findByRole('button', { name: '바로 공개' }))
    const dlg = await screen.findByRole('dialog')
    await userEvent.type(within(dlg).getByLabelText(/사유/), '확인 완료')
    await userEvent.click(within(dlg).getByRole('button', { name: '공개' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_set_visibility')).toBe(true))
    const vis = () => fake.rpcs.filter((r) => r.name === 'cms_set_visibility')
    expect(vis()[0].args).toMatchObject({ p_type: 'cafeteria_meal', p_id: 'd', p_visibility: 'published' })
    await userEvent.click(screen.getByRole('button', { name: '비공개로' }))
    const dlg2 = await screen.findByRole('dialog')
    await userEvent.type(within(dlg2).getByLabelText(/사유/), '메뉴 변경')
    await userEvent.click(within(dlg2).getByRole('button', { name: '비공개로' }))
    await waitFor(() => expect(vis()).toHaveLength(2))
    expect(vis()[1].args).toMatchObject({ p_id: 'p', p_visibility: 'hidden' })
    expect(fake.last('cafeteria_meals', 'update')).toBeUndefined() // never a direct live write
  })

  it('shows unpublished changes, schedules and failures per meal', async () => {
    const d = weekStartOfToday()
    fake.respond('rpc:cms_overview', { data: [{ entity_id: 'm1', has_draft: true, draft_updated_at: '2026-11-10T00:00:00Z', scheduled_at: '2098-12-31T22:00:00Z', failed_jobs: 2, live_version: 1, last_published_at: null }] })
    await openPage([meal({ meal_date: d })])
    expect(await screen.findByText('게시되지 않은 수정 있음')).toBeTruthy()
    expect(screen.getByText('예약 2099.01.01 07:00 (KST)')).toBeTruthy()
    expect(screen.getByText('실패 2')).toBeTruthy()
  })

  it('only a draft meal can be deleted (with its photo); a published one is locked', async () => {
    const d = weekStartOfToday()
    await openPage([
      meal({ id: 'p', meal_date: d, meal_type: 'dinner' }),
      meal({ id: 'dr', meal_date: d, status: 'draft', extra: { photo_url: `${BASE}cafeteria/c1/a.jpg`, photo_path: 'cafeteria/c1/a.jpg' } }),
    ])
    const del = await screen.findAllByRole('button', { name: '삭제' })
    expect(del.map((b) => (b as HTMLButtonElement).disabled).sort()).toEqual([false, true])
    await userEvent.click(del.find((b) => !(b as HTMLButtonElement).disabled)!)
    await userEvent.click(screen.getAllByRole('button', { name: '삭제' }).at(-1)!)
    await waitFor(() => expect(fake.removed).toEqual(['cafeteria/c1/a.jpg']))
    expect(fake.last('cafeteria_meals', 'delete')).toBeTruthy()
  })

  it('still works on a database without the cafeteria-management columns, and says so', async () => {
    const d = weekStartOfToday()
    fake.respond('universities:select', { data: UNIS })
    let n = 0
    // first (full) select fails like production did: column campus_cafeterias.status does not exist
    fake.respond('campus_cafeterias:select', () => (n++ === 0
      ? { error: { code: '42703', message: 'column campus_cafeterias.status does not exist' } }
      : { data: [{ ...CAF, status: undefined, operating_note: undefined }] }))
    fake.respond('cafeteria_meals:select', { data: [meal({ meal_date: d })] })
    render(<MemoryRouter initialEntries={['/cafeteria']}><App client={makeQueryClient()} /></MemoryRouter>)
    expect(await screen.findByText(/20261113000100/)).toBeTruthy()
    await waitFor(() => expect(screen.getByRole('option', { name: /학생식당/ })).toBeTruthy())
    await userEvent.selectOptions(screen.getByLabelText('학식 식당'), 'c1')
    expect(await screen.findByText('김치찌개')).toBeTruthy()
    expect(screen.queryByRole('button', { name: /비활성화/ })).toBeNull()
  })
})

/** Monday of the current Seoul week: the page opens on it. */
function weekStartOfToday() {
  const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date())
  return weekStart(today)
}
