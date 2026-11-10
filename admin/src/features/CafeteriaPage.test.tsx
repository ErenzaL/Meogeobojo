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
async function openPage(rows: unknown[]) {
  fake.respond('campus_cafeterias:select', { data: [{ id: 'c1', name_ko: '학생식당', kind: 'student', universities: { name_ko: '순천향대학교' } }] })
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

  it('saves a meal as a draft with a notice, keeping the existing photo', async () => {
    await openPage([meal({ meal_date: weekStartOfToday(), extra: { photo_url: `${BASE}cafeteria/c1/a.jpg`, photo_path: 'cafeteria/c1/a.jpg' } })])
    await userEvent.click(await screen.findByRole('button', { name: '수정' }))
    await userEvent.selectOptions(screen.getByLabelText('상태'), 'draft')
    await userEvent.type(screen.getByLabelText(/공지/), '방학 중 운영')
    await userEvent.click(screen.getByRole('button', { name: '저장' }))
    await screen.findByText(/초안으로 저장했어요/)
    const row = fake.last('cafeteria_meals', 'upsert')!.payload as Record<string, unknown>
    expect(row).toMatchObject({ status: 'draft', meal_type: 'lunch', price_krw: 5500 })
    expect(row.extra).toEqual({ photo_url: `${BASE}cafeteria/c1/a.jpg`, photo_path: 'cafeteria/c1/a.jpg', notice: '방학 중 운영' })
  })

  it('duplicates a meal to the same weekday next week as a draft, saving nothing yet', async () => {
    const d = weekStartOfToday()
    await openPage([meal({ meal_date: d })])
    await userEvent.click(await screen.findByRole('button', { name: '다음 주로 복제' }))
    expect((screen.getByLabelText('날짜') as HTMLInputElement).value).toBe(addDays(d, 7))
    expect((screen.getByLabelText('상태') as HTMLSelectElement).value).toBe('draft')
    expect((screen.getByLabelText(/메뉴 \(한 줄/) as HTMLTextAreaElement).value).toBe('김치찌개')
    expect(fake.last('cafeteria_meals', 'upsert')).toBeUndefined()
  })

  it('publishes a draft and hides a published one', async () => {
    const d = weekStartOfToday()
    await openPage([meal({ id: 'd', meal_date: d, status: 'draft' }), meal({ id: 'p', meal_date: d, meal_type: 'dinner', status: 'published' })])
    await userEvent.click(await screen.findByRole('button', { name: '공개' }))
    await waitFor(() => expect(fake.last('cafeteria_meals', 'update')!.payload).toMatchObject({ status: 'published' }))
    await userEvent.click(screen.getByRole('button', { name: '비공개로' }))
    await waitFor(() => expect(fake.last('cafeteria_meals', 'update')!.payload).toEqual({ status: 'draft' }))
  })

  it('uploads a meal photo into the bucket and stores its URL in extra; replacing deletes the old file', async () => {
    const d = weekStartOfToday()
    await openPage([meal({ meal_date: d, extra: { notice: '공지', photo_url: `${BASE}cafeteria/c1/old.jpg`, photo_path: 'cafeteria/c1/old.jpg' } })])
    await screen.findByText('김치찌개')
    await userEvent.upload(screen.getByLabelText(`${d} 중식 사진 올리기`), new File(['x'], 'p.jpg', { type: 'image/jpeg' }))
    await waitFor(() => expect(fake.removed).toEqual(['cafeteria/c1/old.jpg']))
    expect(fake.uploads[0].path).toMatch(/^cafeteria\/c1\/[0-9a-f-]{36}\.jpg$/)
    const extra = (fake.last('cafeteria_meals', 'update')!.payload as { extra: Record<string, string> }).extra
    expect(extra.notice).toBe('공지') // the rest of `extra` is preserved
    expect(extra.photo_path).toBe(fake.uploads[0].path)
  })

  it('deleting a meal also removes its photo file', async () => {
    await openPage([meal({ meal_date: weekStartOfToday(), extra: { photo_url: `${BASE}cafeteria/c1/a.jpg`, photo_path: 'cafeteria/c1/a.jpg' } })])
    await userEvent.click(await screen.findByRole('button', { name: '삭제' }))
    await userEvent.click(screen.getAllByRole('button', { name: '삭제' }).at(-1)!)
    await waitFor(() => expect(fake.removed).toEqual(['cafeteria/c1/a.jpg']))
    expect(fake.last('cafeteria_meals', 'delete')).toBeTruthy()
  })
})

/** Monday of the current Seoul week: the page opens on it. */
function weekStartOfToday() {
  const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date())
  return weekStart(today)
}
