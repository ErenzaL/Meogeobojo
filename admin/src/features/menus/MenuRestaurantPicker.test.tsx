import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import { fetchMenuCounts, fetchPickerRestaurants } from '../restaurants/picker/pickerData'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

type Call = { filters: [string, ...unknown[]][] }
type Row = { id: string; name_ko: string; category?: string | null; visibility: string; restaurant_university_links: { university_id: string }[] }
const row = (id: string, name: string, schools: string[], visibility = 'published', category: string | null = '한식'): Row =>
  ({ id, name_ko: name, category, visibility, restaurant_university_links: schools.map((university_id) => ({ university_id })) })

const UNIS = [{ id: 'u-sch', name_ko: '순천향대학교', is_active: true, latitude: null, longitude: null }, { id: 'u-ewha', name_ko: '가나대학교', is_active: true, latitude: null, longitude: null }]

/** Answers restaurant_overrides reads like the database: a range window over the rows. */
function serve(rows: Row[]) {
  fake.respond('restaurant_overrides:select', (c: Call) => {
    const r = c.filters.find((f) => f[0] === 'range') as [string, number, number] | undefined
    return { data: r ? rows.slice(r[1], r[2] + 1) : rows }
  })
}
function wire(rows: Row[], menus: { restaurant_id: string }[] = [], overview: unknown[] = []) {
  serve(rows)
  fake.respond('universities:select', { data: UNIS })
  fake.respond('restaurant_menus:select', (c: Call) => {
    const r = c.filters.find((f) => f[0] === 'range') as [string, number, number] | undefined
    return { data: r ? menus.slice(r[1], r[2] + 1) : menus }
  })
  fake.respond('rpc:cms_overview', { data: overview })
  fake.respond('rpc:cms_state', { data: { live: { items: [] }, live_version: 1, last_published: null, draft: null, jobs: [] } })
}
const open = () => render(<MemoryRouter initialEntries={['/menus']}><App client={makeQueryClient()} /></MemoryRouter>)
const list = () => screen.findByRole('group', { name: '식당 목록' })
const rowButtons = (root: HTMLElement) => within(root).getAllByRole('button').filter((b) => b.hasAttribute('aria-pressed'))

beforeEach(() => {
  fake.reset(); fake.signInAs('admin')
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('메뉴·가격: the restaurant list matches the 식당 page', () => {
  it('lists every managed restaurant, not a capped first 50', async () => {
    const rows = Array.from({ length: 167 }, (_, i) => row(`r${i}`, `식당${String(i).padStart(3, '0')}`, ['u-sch']))
    wire(rows)
    open()
    const box = await list()
    expect(rowButtons(box)).toHaveLength(167)
    expect(screen.getByText(/전체 167곳 중/)).toBeTruthy()
    expect(within(box).getByText('식당166')).toBeTruthy() // the last one is there, not cut off
    // the read asks for no row limit of its own
    const sel = fake.calls.find((c) => c.table === 'restaurant_overrides' && c.op === 'select')!
    expect(sel.filters.some((f) => f[0] === 'limit')).toBe(false)
  })

  it('lists restaurants of every status, with their status, like the 식당 page', async () => {
    wire([row('a', '초안집', ['u-sch'], 'draft'), row('b', '공개집', ['u-sch'], 'published'), row('c', '숨김집', ['u-sch'], 'hidden'), row('d', '보관집', ['u-sch'], 'archived')])
    open()
    const box = await list()
    expect(rowButtons(box)).toHaveLength(4)
    expect(within(screen.getByRole('button', { name: /초안집/ })).getByText('초안')).toBeTruthy()
    expect(within(screen.getByRole('button', { name: /공개집/ })).getByText('공개')).toBeTruthy()
    expect(within(screen.getByRole('button', { name: /숨김집/ })).getByText('숨김')).toBeTruthy()
    expect(within(screen.getByRole('button', { name: /보관집/ })).getByText('보관')).toBeTruthy()
    const sel = fake.calls.find((c) => c.table === 'restaurant_overrides' && c.op === 'select')!
    expect(sel.filters.some((f) => f[0] === 'eq' && f[1] === 'visibility')).toBe(false) // no status filter on the read
  })

  it('reads past the 1000-row limit of one request', async () => {
    serve(Array.from({ length: 2300 }, (_, i) => row(`r${i}`, `식당${i}`, [])))
    const all = await fetchPickerRestaurants()
    expect(all).toHaveLength(2300)
    expect(new Set(all.map((r) => r.id)).size).toBe(2300)
    expect(fake.calls.filter((c) => c.table === 'restaurant_overrides').length).toBe(3)
  })

  it('counts menus past the 1000-row limit too', async () => {
    fake.respond('restaurant_menus:select', (c: Call) => {
      const r = c.filters.find((f) => f[0] === 'range') as [string, number, number]
      const rows = Array.from({ length: 2500 }, (_, i) => ({ restaurant_id: i < 1800 ? 'big' : 'small' }))
      return { data: rows.slice(r[1], r[2] + 1) }
    })
    const counts = await fetchMenuCounts()
    expect(counts.get('big')).toBe(1800)
    expect(counts.get('small')).toBe(700)
  })

  it('a failed read says so, and retry loads the list', async () => {
    fake.respond('restaurant_overrides:select', { data: null, error: { message: '목록을 못 불러왔어요' } })
    fake.respond('universities:select', { data: UNIS })
    fake.respond('rpc:cms_overview', { data: [] })
    open()
    expect(await screen.findByText('목록을 못 불러왔어요', {}, { timeout: 4000 })).toBeTruthy() // the app retries a failed read once, after a second
    serve([row('a', '살아난집', ['u-sch'])])
    await userEvent.click(screen.getByRole('button', { name: '다시 시도' }))
    expect(await screen.findByRole('button', { name: /살아난집/ })).toBeTruthy()
  })

  it('no restaurants at all says what to do instead of showing an empty box', async () => {
    wire([])
    open()
    expect(await screen.findByText(/관리 중인 식당이 없어요/)).toBeTruthy()
  })
})

describe('메뉴·가격: organised by school', () => {
  const ROWS = [
    row('a', '순식당1', ['u-sch']), row('b', '순식당2', ['u-sch']), row('c', '가나식당', ['u-ewha']),
    row('d', '공유식당', ['u-sch', 'u-ewha']), row('e', '무소속식당', []),
  ]

  it('one section per school with its count, the shared restaurant under both, unassigned last', async () => {
    wire(ROWS, [{ restaurant_id: 'a' }, { restaurant_id: 'a' }, { restaurant_id: 'c' }])
    open()
    const box = await list()
    const sections = within(box).getAllByRole('region')
    expect(sections.map((s) => s.getAttribute('aria-label'))).toEqual(['가나대학교', '순천향대학교', '대학교 미지정'])
    expect(within(sections[1]).getByText(/3곳 · 메뉴 없음 2/)).toBeTruthy() // 순식당1 has menus; 순식당2 and 공유식당 do not
    expect(within(sections[0]).getByText('공유식당')).toBeTruthy()
    expect(within(sections[1]).getByText('공유식당')).toBeTruthy()
    expect(within(sections[2]).getByText('무소속식당')).toBeTruthy()
    // the school dropdown shows the real numbers
    expect(screen.getByRole('option', { name: '순천향대학교 (3)' })).toBeTruthy()
    expect(screen.getByRole('option', { name: '가나대학교 (2)' })).toBeTruthy()
    expect(screen.getByRole('option', { name: '대학교 미지정 (1)' })).toBeTruthy()
    expect(screen.getByRole('option', { name: '전체 대학교 (5)' })).toBeTruthy()
  })

  it('shows how many menus each restaurant has, and says when there are none', async () => {
    wire(ROWS, [{ restaurant_id: 'a' }, { restaurant_id: 'a' }])
    open()
    await list()
    expect(within(screen.getAllByRole('button', { name: /순식당1/ })[0]).getByText('메뉴 2개')).toBeTruthy()
    expect(within(screen.getAllByRole('button', { name: /순식당2/ })[0]).getByText('메뉴 없음')).toBeTruthy()
  })

  it('the school filter narrows the list to that school', async () => {
    wire(ROWS)
    open()
    await list()
    await userEvent.selectOptions(screen.getByLabelText('대학교'), 'u-ewha')
    const box = await list()
    expect(within(box).getAllByRole('region').map((s) => s.getAttribute('aria-label'))).toEqual(['가나대학교'])
    expect(rowButtons(box).map((b) => b.textContent)).toEqual([expect.stringContaining('가나식당'), expect.stringContaining('공유식당')])
    expect(screen.getByText(/전체 5곳 중/)).toBeTruthy()
    expect(screen.getByText('2곳', { selector: 'b' })).toBeTruthy()
  })

  it('the school filter can show only restaurants with no school', async () => {
    wire(ROWS)
    open()
    await list()
    await userEvent.selectOptions(screen.getByLabelText('대학교'), '__none')
    expect(rowButtons(await list()).map((b) => b.textContent)).toEqual([expect.stringContaining('무소속식당')])
  })

  it('the menu filter shows restaurants without menus (what still needs work)', async () => {
    wire(ROWS, [{ restaurant_id: 'a' }, { restaurant_id: 'c' }])
    open()
    await list()
    await userEvent.selectOptions(screen.getByLabelText('메뉴'), 'none')
    const names = rowButtons(await list()).map((b) => b.textContent ?? '')
    expect(names.some((n) => n.includes('순식당1'))).toBe(false)
    expect(names.some((n) => n.includes('순식당2'))).toBe(true)
    expect(names.some((n) => n.includes('가나식당'))).toBe(false)
    expect(names.some((n) => n.includes('무소속식당'))).toBe(true)
  })

  it('search filters by name and opens collapsed sections', async () => {
    wire(ROWS)
    open()
    await list()
    await userEvent.click(screen.getByRole('button', { name: '순천향대학교 접기' }))
    expect(screen.queryByText('순식당1')).toBeNull()
    await userEvent.type(screen.getByLabelText('식당 검색'), '순식당')
    expect(await screen.findByText('순식당1')).toBeTruthy() // searching shows matches even in a collapsed section
    expect(screen.queryByText('가나식당')).toBeNull()
    await userEvent.clear(screen.getByLabelText('식당 검색'))
    expect(screen.queryByText('순식당1')).toBeNull() // collapsed again
    await userEvent.click(screen.getByRole('button', { name: '순천향대학교 펼치기' }))
    expect(screen.getByText('순식당1')).toBeTruthy()
  })

  it('no match says so', async () => {
    wire(ROWS)
    open()
    await list()
    await userEvent.type(screen.getByLabelText('식당 검색'), '없는이름')
    expect(await screen.findByText('조건에 맞는 식당이 없어요.')).toBeTruthy()
  })

  it('draft / scheduled markers from the publishing overview show on the row', async () => {
    wire(ROWS, [], [
      { entity_id: 'a', has_draft: true, draft_updated_at: null, scheduled_at: null, failed_jobs: 0, live_version: 1, last_published_at: null },
      { entity_id: 'c', has_draft: true, draft_updated_at: null, scheduled_at: '2026-12-01T00:00:00Z', failed_jobs: 0, live_version: 1, last_published_at: null },
    ])
    open()
    await list()
    expect(await within(screen.getAllByRole('button', { name: /순식당1/ })[0]).findByText('초안 있음')).toBeTruthy()
    expect(within(screen.getAllByRole('button', { name: /가나식당/ })[0]).getByText('예약됨')).toBeTruthy()
  })
})

describe('메뉴·가격: choosing a restaurant', () => {
  it('opens that restaurant\'s menu and shows which school(s) it is in; the shared one opens from either section', async () => {
    wire([row('d', '공유식당', ['u-sch', 'u-ewha']), row('c', '가나식당', ['u-ewha'])])
    open()
    const box = await list()
    const second = within(within(box).getAllByRole('region')[1]).getByRole('button', { name: /공유식당/ }) // under 순천향대학교
    await userEvent.click(second)
    await screen.findByRole('heading', { name: '새 메뉴' })
    expect(fake.rpcs.filter((r) => r.name === 'cms_state').at(-1)!.args).toMatchObject({ p_id: 'd' })
    expect(screen.getByText(/선택한 식당:/).textContent).toContain('공유식당')
    expect(screen.getByText(/선택한 식당:/).textContent).toContain('순천향대학교, 가나대학교') // in the order the links are stored
    expect(screen.getAllByRole('button', { name: /공유식당/ }).every((b) => b.getAttribute('aria-pressed') === 'true')).toBe(true) // highlighted in both sections
    await userEvent.click(screen.getAllByRole('button', { name: /가나식당/ })[0])
    await waitFor(() => expect(fake.rpcs.filter((r) => r.name === 'cms_state').at(-1)!.args).toMatchObject({ p_id: 'c' }))
  })
})

describe('메뉴·가격: CSV export by school', () => {
  it('"선택한 대학교의 식당" exports that school\'s restaurants only', async () => {
    wire([row('a', '순식당', ['u-sch']), row('c', '가나식당', ['u-ewha'])])
    open()
    await list()
    // without a school chosen the option is off
    await userEvent.click(screen.getByRole('button', { name: /CSV 내보내기/ }))
    const dlg = await screen.findByRole('dialog', { hidden: true })
    expect((within(dlg).getByRole('radio', { name: /선택한 대학교의 식당/ }) as HTMLInputElement).disabled).toBe(true)
    await userEvent.click(within(dlg).getByRole('button', { name: '닫기' }))

    await userEvent.selectOptions(screen.getByLabelText('대학교'), 'u-ewha')
    await userEvent.click(screen.getByRole('button', { name: /CSV 내보내기/ }))
    const dlg2 = await screen.findByRole('dialog', { hidden: true })
    const radio = within(dlg2).getByRole('radio', { name: /선택한 대학교의 식당 \(가나대학교\)/ }) as HTMLInputElement
    expect(radio.disabled).toBe(false)
    expect(radio.checked).toBe(true) // the natural default once a school is chosen and no restaurant is
    URL.createObjectURL = vi.fn(() => 'blob:x'); URL.revokeObjectURL = vi.fn(); HTMLAnchorElement.prototype.click = vi.fn()
    fake.calls.length = 0
    await userEvent.click(within(dlg2).getByRole('button', { name: '내보내기' }))
    await waitFor(() => expect(within(dlg2).getByRole('status')).toBeTruthy())
    const q = fake.calls.find((c) => c.table === 'restaurant_overrides' && c.op === 'select')!
    expect(q.filters.some((f) => f[0] === 'eq' && f[1] === 'restaurant_university_links.university_id' && f[2] === 'u-ewha')).toBe(true)
  })
})
