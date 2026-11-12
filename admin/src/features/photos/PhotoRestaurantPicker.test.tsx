import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import { fetchPhotoCounts } from '../restaurants/picker/pickerData'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

type Call = { filters: [string, ...unknown[]][] }
type Row = { id: string; name_ko: string; category: string | null; visibility: string; restaurant_university_links: { university_id: string }[] }
const row = (id: string, name: string, schools: string[], visibility = 'published'): Row =>
  ({ id, name_ko: name, category: '한식', visibility, restaurant_university_links: schools.map((university_id) => ({ university_id })) })
const UNIS = [{ id: 'u-sch', name_ko: '순천향대학교', is_active: true, latitude: null, longitude: null }, { id: 'u-ewha', name_ko: '가나대학교', is_active: true, latitude: null, longitude: null }]

function wire(rows: Row[], photos: { restaurant_id: string }[] = []) {
  fake.respond('restaurant_overrides:select', (c: Call) => {
    const r = c.filters.find((f) => f[0] === 'range') as [string, number, number] | undefined
    return { data: r ? rows.slice(r[1], r[2] + 1) : rows }
  })
  fake.respond('universities:select', { data: UNIS })
  fake.respond('restaurant_photos:select', (c: Call) => {
    const r = c.filters.find((f) => f[0] === 'range') as [string, number, number] | undefined
    return { data: r ? photos.slice(r[1], r[2] + 1) : photos }
  })
  fake.respond('rpc:cms_overview', { data: [] })
  fake.respond('rpc:cms_state', { data: { live: { photos: [] }, live_version: 1, last_published: null, draft: null, jobs: [] } })
}
const open = () => render(<MemoryRouter initialEntries={['/photos']}><App client={makeQueryClient()} /></MemoryRouter>)
const list = () => screen.findByRole('group', { name: '식당 목록' })
const rowButtons = (root: HTMLElement) => within(root).getAllByRole('button').filter((b) => b.hasAttribute('aria-pressed'))

beforeEach(() => { fake.reset(); fake.signInAs('admin') })

describe('사진 관리: the restaurant list matches the 식당 page', () => {
  it('lists every managed restaurant, not a capped first 50, of any status', async () => {
    const rows = Array.from({ length: 167 }, (_, i) => row(`r${i}`, `식당${String(i).padStart(3, '0')}`, ['u-sch'], i % 4 === 0 ? 'draft' : 'published'))
    wire(rows)
    open()
    expect(rowButtons(await list())).toHaveLength(167)
    expect(screen.getByText(/전체 167곳 중/)).toBeTruthy()
    const sel = fake.calls.find((c) => c.table === 'restaurant_overrides' && c.op === 'select')!
    expect(sel.filters.some((f) => f[0] === 'limit')).toBe(false)
    expect(sel.filters.some((f) => f[0] === 'eq' && f[1] === 'visibility')).toBe(false)
  })

  it('is organised by school; a shared restaurant is under both, an unassigned one is kept', async () => {
    wire([row('a', '순식당', ['u-sch']), row('c', '가나식당', ['u-ewha']), row('d', '공유식당', ['u-sch', 'u-ewha']), row('e', '무소속식당', [])])
    open()
    const sections = within(await list()).getAllByRole('region')
    expect(sections.map((s) => s.getAttribute('aria-label'))).toEqual(['가나대학교', '순천향대학교', '대학교 미지정'])
    expect(within(sections[0]).getByText('공유식당')).toBeTruthy()
    expect(within(sections[1]).getByText('공유식당')).toBeTruthy()
    expect(screen.getByRole('option', { name: '순천향대학교 (2)' })).toBeTruthy()
  })

  it('shows photo counts (published only) and says when a restaurant has no photo', async () => {
    wire([row('a', '사진있는집', ['u-sch']), row('b', '사진없는집', ['u-sch'])], [{ restaurant_id: 'a' }, { restaurant_id: 'a' }, { restaurant_id: 'a' }])
    open()
    await list()
    expect(within(screen.getByRole('button', { name: /사진있는집/ })).getByText('사진 3장')).toBeTruthy()
    expect(within(screen.getByRole('button', { name: /사진없는집/ })).getByText('사진 없음')).toBeTruthy()
    expect(screen.getByText(/사진 있음 1 \/ 없음 1/)).toBeTruthy()
    const q = fake.calls.find((c) => c.table === 'restaurant_photos' && c.op === 'select')!
    expect(q.filters.some((f) => f[0] === 'eq' && f[1] === 'status' && f[2] === 'published')).toBe(true) // archived photos do not count
  })

  it('the photo filter finds the restaurants that still need photos', async () => {
    wire([row('a', '사진있는집', ['u-sch']), row('b', '사진없는집', ['u-sch'])], [{ restaurant_id: 'a' }])
    open()
    await list()
    await userEvent.selectOptions(screen.getByLabelText('사진'), 'none')
    const box = await list()
    expect(rowButtons(box).map((b) => b.textContent)).toEqual([expect.stringContaining('사진없는집')])
  })

  it('counts photos past the 1000-row limit of one request', async () => {
    fake.respond('restaurant_photos:select', (c: Call) => {
      const r = c.filters.find((f) => f[0] === 'range') as [string, number, number]
      return { data: Array.from({ length: 1500 }, () => ({ restaurant_id: 'x' })).slice(r[1], r[2] + 1) }
    })
    expect((await fetchPhotoCounts()).get('x')).toBe(1500)
  })

  it('choosing a restaurant (from any school) opens its photos', async () => {
    wire([row('d', '공유식당', ['u-sch', 'u-ewha'])])
    open()
    const box = await list()
    await userEvent.click(within(within(box).getAllByRole('region')[1]).getByRole('button', { name: /공유식당/ }))
    await screen.findByRole('heading', { name: /대표 사진/ })
    expect(fake.rpcs.filter((r) => r.name === 'cms_state').at(-1)!.args).toMatchObject({ p_id: 'd' })
    expect(screen.getByText(/선택한 식당:/).textContent).toContain('공유식당')
  })

  it('an unpublished restaurant still warns that its photos are not visible in the app', async () => {
    wire([row('a', '초안식당', ['u-sch'], 'draft')])
    open()
    await userEvent.click(await screen.findByRole('button', { name: /초안식당/ }))
    expect(await screen.findByText(/앱에 사진이 보이지 않아요/)).toBeTruthy()
  })
})
