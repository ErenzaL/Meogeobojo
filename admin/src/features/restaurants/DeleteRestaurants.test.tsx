import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

type Vis = 'draft' | 'published' | 'hidden' | 'archived'
type R = { id: string; kakao_place_id: string; name_ko: string; category: string; address: string; visibility: Vis; updated_at: string; description: string | null; image_url: string | null; restaurant_university_links: unknown[] }
const pad = (n: number) => String(n).padStart(2, '0')

/** 25 restaurants. 03 is published, 04 hidden, 05 archived, 06 has a scheduled publish, the rest are drafts. */
let db: R[] = []
let menus: { id: string; restaurant_id: string }[] = []
let photos: { id: string; restaurant_id: string }[] = []
let scheduled: string[] = []
let rlsAllowsDelete = true
let deleteFail: Record<string, { code?: string; message: string }> = {}
let deleteCalls: string[] = []

function seed() {
  db = Array.from({ length: 25 }, (_, i) => {
    const n = i + 1
    return {
      id: `id-${pad(n)}`, kakao_place_id: `kp${pad(n)}`, name_ko: `식당${pad(n)}`, category: '한식', address: `주소 ${n}`,
      visibility: (n === 3 ? 'published' : n === 4 ? 'hidden' : n === 5 ? 'archived' : 'draft') as Vis,
      updated_at: new Date(2026, 10, 10, 12, 0, 45 - n).toISOString(), description: null, image_url: null, restaurant_university_links: [],
    }
  })
  menus = [{ id: 'm1', restaurant_id: 'id-01' }, { id: 'm2', restaurant_id: 'id-01' }, { id: 'm3', restaurant_id: 'id-02' }]
  photos = [{ id: 'p1', restaurant_id: 'id-01' }]
  scheduled = ['id-06']
  rlsAllowsDelete = true; deleteFail = {}; deleteCalls = []
}

type Call = { filters: [string, ...unknown[]][] }
function wire() {
  fake.respond('restaurant_overrides:select', (c: Call) => {
    const get = (n: string) => c.filters.filter((x) => x[0] === n)
    const cols = String(get('select')[0]?.[1] ?? '')
    let rows = [...db]
    for (const e of get('eq')) if (e[1] === 'id') rows = rows.filter((r) => r.id === e[2])
    for (const e of get('in')) if (e[1] === 'id') rows = rows.filter((r) => (e[2] as string[]).includes(r.id))
    const total = rows.length
    const range = get('range')[0]
    if (range) rows = rows.slice(Number(range[1]), Number(range[2]) + 1)
    if (cols.startsWith('id,image_url,visibility')) return { data: rows.map((r) => ({ id: r.id, image_url: r.image_url, visibility: r.visibility })), count: total }
    if (cols.startsWith('id,name_ko,visibility')) return { data: rows.map((r) => ({ id: r.id, name_ko: r.name_ko, visibility: r.visibility })), count: total }
    if (cols.startsWith('kakao_place_id,image_url')) return { data: rows.map((r) => ({ kakao_place_id: r.kakao_place_id, image_url: r.image_url })), count: total }
    if (cols.startsWith('id')) return { data: rows.map((r) => ({ id: r.id })), count: total }
    return { data: rows, count: total }
  })
  fake.respond('restaurant_overrides:delete', (c: Call) => {
    const id = String(c.filters.find((x) => x[0] === 'eq' && x[1] === 'id')?.[2])
    deleteCalls.push(id)
    if (deleteFail[id]) return { error: deleteFail[id] }
    if (!rlsAllowsDelete) return { data: [] } // row-level security: no error, nothing deleted
    const before = db.length
    db = db.filter((r) => r.id !== id)
    return { data: db.length < before ? [{ id }] : [] }
  })
  const byRest = (rows: { id: string; restaurant_id: string }[]) => (c: Call) => {
    const inn = c.filters.find((x) => x[0] === 'in' && x[1] === 'restaurant_id')
    return { data: rows.filter((r) => !inn || (inn[2] as string[]).includes(r.restaurant_id)).map((r) => ({ id: r.id, restaurant_id: r.restaurant_id })) }
  }
  fake.respond('restaurant_menus:select', (c: Call) => byRest(menus)(c))
  fake.respond('restaurant_photos:select', (c: Call) => byRest(photos)(c))
  fake.respond('rpc:cms_overview', () => ({ data: scheduled.map((id) => ({ entity_id: id, has_draft: false, draft_updated_at: null, scheduled_at: '2099-01-01T00:00:00Z', failed_jobs: 0, live_version: 0, last_published_at: null })) }))
  fake.respond('universities:select', { data: [] })
}

const dialog = async () => await screen.findByRole('dialog', { hidden: true })
const click = (el: HTMLElement) => userEvent.click(el)
const delCalls = () => deleteCalls
function open(path = '/restaurants') { return render(<MemoryRouter initialEntries={[path]}><App client={makeQueryClient()} /></MemoryRouter>) }
async function ready(role: 'super_admin' | 'admin' = 'super_admin') {
  fake.signInAs(role); wire()
  open()
  await screen.findByText('식당01')
}
async function typeConfirm(d: HTMLElement, word = '삭제') { await userEvent.type(within(d).getByLabelText(/을 입력해 주세요|를 입력해 주세요/), word) }

beforeEach(() => {
  fake.reset(); seed()
  localStorage.clear()
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('who sees it', () => {
  it('only super admins get delete buttons (row and bulk); admins keep 숨기기 and the rest', async () => {
    await ready('admin')
    expect(screen.queryByRole('button', { name: '식당01 삭제' })).toBeNull()
    expect(screen.queryByRole('button', { name: '선택한 식당 삭제' })).toBeNull()
    expect(screen.getAllByRole('button', { name: '공개' }).length).toBeGreaterThan(0)
  })
  it('a super admin sees them; a published restaurant\'s delete button is disabled with the reason', async () => {
    await ready()
    expect(screen.getByRole('button', { name: '식당01 삭제' })).toBeTruthy()
    expect(screen.getByRole('button', { name: '선택한 식당 삭제' })).toBeTruthy()
    const published = screen.getByRole('button', { name: '식당03 삭제' }) as HTMLButtonElement
    expect(published.disabled).toBe(true)
    expect(published.title).toContain('먼저 숨기기')
    expect((screen.getByRole('button', { name: '식당01 삭제' }) as HTMLButtonElement).disabled).toBe(false)
  })
})

describe('deleting one restaurant', () => {
  it('asks first: what goes with it, that it can not be undone, and needs the word 삭제; nothing is deleted before', async () => {
    await ready()
    await click(screen.getByRole('button', { name: '식당01 삭제' }))
    const d = await dialog()
    expect(await within(d).findByRole('heading', { name: /“식당01”을\(를\) 삭제할까요/ })).toBeTruthy()
    const list = within(d).getByLabelText('삭제 내용')
    expect(list.textContent).toContain('삭제할 식당 1곳')
    expect(list.textContent).toContain('메뉴 2개, 사진 정보 1개')
    expect(within(d).getByLabelText('삭제 주의').textContent).toContain('되돌릴 수 없어요')
    expect(within(d).getByLabelText('삭제 주의').textContent).toContain('숨기기')
    const go = within(d).getByRole('button', { name: '1곳 삭제' }) as HTMLButtonElement
    expect(go.disabled).toBe(true)
    await typeConfirm(d, '지우기')
    expect(go.disabled).toBe(true) // the wrong word
    expect(delCalls()).toHaveLength(0)
  })

  it('deletes only that restaurant, shows the result, then refreshes the list and the counts', async () => {
    await ready()
    expect(screen.getByLabelText('사진·메뉴 현황').textContent).toContain('관리 중 25곳')
    await click(screen.getByRole('button', { name: '식당01 삭제' }))
    const d = await dialog()
    await within(d).findByLabelText('삭제 내용')
    await typeConfirm(d)
    await click(within(d).getByRole('button', { name: '1곳 삭제' }))
    expect((await within(d).findByLabelText('삭제 결과')).textContent).toContain('삭제 1곳')
    expect(delCalls()).toEqual(['id-01'])
    await click(within(d).getByRole('button', { name: '닫기' }))
    expect(await screen.findByText(/1곳을 삭제했어요/)).toBeTruthy()
    await waitFor(() => expect(screen.queryByText('식당01')).toBeNull())
    expect(screen.getByText('식당02')).toBeTruthy()
    await waitFor(() => expect(screen.getByLabelText('사진·메뉴 현황').textContent).toContain('관리 중 24곳'))
  })

  it('cancel deletes nothing', async () => {
    await ready()
    await click(screen.getByRole('button', { name: '식당02 삭제' }))
    const d = await dialog()
    await click(await within(d).findByRole('button', { name: '취소' }))
    expect(delCalls()).toHaveLength(0)
    expect(screen.getByText('식당02')).toBeTruthy()
  })

  it('a hidden or archived restaurant needs an extra acknowledgement: deleting it can bring it back in the app', async () => {
    await ready()
    await click(screen.getByRole('button', { name: '식당04 삭제' })) // hidden
    const d = await dialog()
    await within(d).findByLabelText('삭제 내용')
    expect(d.textContent).toContain('다시 카카오 정보 그대로 보일 수 있다')
    await typeConfirm(d)
    const go = within(d).getByRole('button', { name: '1곳 삭제' }) as HTMLButtonElement
    expect(go.disabled).toBe(true) // typed the word but did not acknowledge
    await click(within(d).getByRole('checkbox'))
    expect(go.disabled).toBe(false)
    await click(go)
    await within(d).findByLabelText('삭제 결과')
    expect(delCalls()).toEqual(['id-04'])
  })

  it('a draft restaurant needs no such acknowledgement (it was never hidden from anyone)', async () => {
    await ready()
    await click(screen.getByRole('button', { name: '식당02 삭제' }))
    const d = await dialog()
    await within(d).findByLabelText('삭제 내용')
    expect(within(d).queryByRole('checkbox')).toBeNull()
  })

  it('a restaurant with a scheduled publish can not be deleted: it says to cancel the schedule first', async () => {
    await ready()
    await click(screen.getByRole('button', { name: '식당06 삭제' }))
    const d = await dialog()
    const list = await within(d).findByLabelText('삭제 내용')
    expect(list.textContent).toContain('예약 게시가 있는 식당 1곳')
    expect(list.textContent).toContain('예약을 먼저 취소')
    expect((within(d).getByRole('button', { name: '삭제할 수 있는 식당이 없어요' }) as HTMLButtonElement).disabled).toBe(true)
    expect(delCalls()).toHaveLength(0)
  })
})

describe('deleting several', () => {
  async function selectAndOpen(...names: string[]) {
    await ready()
    for (const n of names) await click(screen.getByLabelText(`${n} 선택`))
    await click(screen.getByRole('button', { name: '선택한 식당 삭제' }))
    return await dialog()
  }

  it('counts exactly: published and scheduled are left out, the rest is deleted', async () => {
    const d = await selectAndOpen('식당01', '식당02', '식당03', '식당06', '식당07')
    const list = await within(d).findByLabelText('삭제 내용')
    expect(list.textContent).toContain('선택한 식당 5곳')
    expect(list.textContent).toContain('공개 중 1곳') // 03
    expect(list.textContent).toContain('예약 게시가 있는 식당 1곳') // 06
    expect(list.textContent).toContain('삭제할 식당 3곳')
    expect(list.textContent).toContain('메뉴 3개, 사진 정보 1개')
    expect(within(d).getByLabelText('삭제할 식당').textContent).toContain('식당01')
    await typeConfirm(d)
    await click(within(d).getByRole('button', { name: '3곳 삭제' }))
    const res = await within(d).findByLabelText('삭제 결과')
    expect(res.textContent).toContain('삭제 3곳')
    expect(res.textContent).toContain('건너뜀 0곳') // nothing had to be skipped at that point: the dialog had already left them out
    expect(delCalls().sort()).toEqual(['id-01', 'id-02', 'id-07'])
    expect(db.find((r) => r.id === 'id-03')).toBeTruthy() // the published one is untouched
    expect(db.find((r) => r.id === 'id-06')).toBeTruthy()
    await click(within(d).getByRole('button', { name: '닫기' }))
    expect(await screen.findByText(/3곳을 삭제했어요/)).toBeTruthy()
    await waitFor(() => expect(screen.getByLabelText('선택 현황').textContent).toContain('선택한 식당 2곳')) // the two that were not deleted stay selected
  })

  it('"전체 선택" then delete: nothing published or scheduled is deleted, everything else is', async () => {
    await ready()
    await click(screen.getByRole('button', { name: /^전체 선택 \(/ }))
    await waitFor(() => expect(screen.getByLabelText('선택 현황').textContent).toContain('선택한 식당 25곳'))
    await click(screen.getByRole('button', { name: '선택한 식당 삭제' }))
    const d = await dialog()
    const list = await within(d).findByLabelText('삭제 내용')
    expect(list.textContent).toContain('삭제할 식당 23곳') // 25 - published (03) - scheduled (06)
    await typeConfirm(d)
    await click(within(d).getByRole('checkbox')) // 04 hidden, 05 archived are included
    await click(within(d).getByRole('button', { name: '23곳 삭제' }))
    expect((await within(d).findByLabelText('삭제 결과')).textContent).toContain('삭제 23곳')
    expect(db.map((r) => r.id).sort()).toEqual(['id-03', 'id-06'])
  })

  it('a refusal for one restaurant fails alone; the others go; the failure can be retried', async () => {
    deleteFail = { 'id-02': { code: '23503', message: '다른 곳에서 쓰고 있어요' } }
    const d = await selectAndOpen('식당01', '식당02', '식당07')
    await within(d).findByLabelText('삭제 내용')
    await typeConfirm(d)
    await click(within(d).getByRole('button', { name: '3곳 삭제' }))
    const res = await within(d).findByLabelText('삭제 결과')
    expect(res.textContent).toContain('삭제 2곳')
    expect(res.textContent).toContain('실패 1곳')
    const failed = within(d).getByLabelText('삭제하지 못한 식당')
    expect(failed.textContent).toContain('식당02')
    expect(failed.textContent).toContain('ID id-02')
    expect(failed.textContent).toContain('다른 곳에서 쓰고 있어요')
    deleteFail = {}
    const before = delCalls().length
    await click(within(d).getByRole('button', { name: /다시 시도 \(1\)/ }))
    await waitFor(() => expect(within(d).getByLabelText('삭제 결과').textContent).toContain('삭제 1곳'))
    expect(delCalls().slice(before)).toEqual(['id-02'])
    expect(db.some((r) => r.id === 'id-02')).toBe(false)
  })

  it('if the database silently refuses (row-level security: nothing deleted, no error) it is NOT reported as success', async () => {
    rlsAllowsDelete = false
    const d = await selectAndOpen('식당01', '식당02')
    await within(d).findByLabelText('삭제 내용')
    await typeConfirm(d)
    await click(within(d).getByRole('button', { name: '2곳 삭제' }))
    expect(await within(d).findByText('중간에 멈췄어요')).toBeTruthy()
    expect(within(d).getByRole('alert').textContent).toContain('최고 관리자만')
    expect(within(d).getByLabelText('삭제 결과').textContent).toContain('삭제 0곳')
    expect(db).toHaveLength(25)
    await click(within(d).getByRole('button', { name: '닫기' }))
    expect(screen.queryByText(/곳을 삭제했어요/)).toBeNull() // no success message
  })
})

describe('on the restaurant edit page', () => {
  async function openEdit(role: 'super_admin' | 'admin', id = 'id-02') {
    fake.signInAs(role); wire()
    const row = db.find((r) => r.id === id)!
    fake.respond('rpc:cms_state', { data: { live: { name_ko: row.name_ko, name_en: null, category: '한식', address: null, phone: null, latitude: null, longitude: null, description: null, opening_hours: {}, break_time: null, last_order_time: null, business_status: null, price_min_krw: null, price_max_krw: null, avg_cost_krw: null, dining_purposes: [], visibility: row.visibility, featured: false, display_order: null, university_ids: [] }, live_version: 0, last_published: null, draft: null, jobs: [] } })
    render(<MemoryRouter initialEntries={[`/restaurants/${id}`]}><App client={makeQueryClient()} /></MemoryRouter>)
    await screen.findByDisplayValue(row.name_ko)
  }

  it('shows a delete section to super admins only', async () => {
    await openEdit('admin')
    expect(screen.queryByLabelText('위험 구역')).toBeNull()
  })

  it('deleting from the edit page uses the same checks, then returns to the list', async () => {
    await openEdit('super_admin')
    const zone = await screen.findByLabelText('위험 구역')
    await click(within(zone).getByRole('button', { name: /이 식당 삭제/ }))
    const d = await dialog()
    await within(d).findByLabelText('삭제 내용')
    await typeConfirm(d)
    await click(within(d).getByRole('button', { name: '1곳 삭제' }))
    await within(d).findByLabelText('삭제 결과')
    expect(delCalls()).toEqual(['id-02'])
    await click(within(d).getByRole('button', { name: '닫기' }))
    expect(await screen.findByRole('heading', { name: '식당' })).toBeTruthy() // back on the list
    await waitFor(() => expect(screen.queryByText('식당02')).toBeNull())
  })

  it('a published restaurant can not be deleted from here either (hide it first)', async () => {
    await openEdit('super_admin', 'id-03')
    await click(within(await screen.findByLabelText('위험 구역')).getByRole('button', { name: /이 식당 삭제/ }))
    const d = await dialog()
    const list = await within(d).findByLabelText('삭제 내용')
    expect(list.textContent).toContain('공개 중 1곳')
    expect((within(d).getByRole('button', { name: '삭제할 수 있는 식당이 없어요' }) as HTMLButtonElement).disabled).toBe(true)
    expect(delCalls()).toHaveLength(0)
  })
})
