import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import { KAKAO_QUERIES } from './kakao'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const doc = (id: string, name: string, distance = '100') => ({ id, place_name: name, category_group_code: 'FD6', category_name: '음식점 > 한식', road_address_name: `도로 ${id}`, distance, x: '126.93', y: '36.77' })
const UNI = { id: 'u1', name_ko: '순천향대학교', is_active: true, latitude: 36.76999, longitude: 126.9315, search_radius_m: 3000 }
const row = (over: Record<string, unknown> = {}) => ({ id: 'r1', kakao_place_id: '1776574318', name_ko: '어굿플레이스', category: '한식', address: '관리자가 입력한 주소', visibility: 'draft', updated_at: '2026-11-10T00:00:00Z', description: null, restaurant_university_links: [{ universities: { name_ko: '순천향대학교' } }], ...over })

function open() {
  return render(<MemoryRouter initialEntries={['/restaurants']}><App client={makeQueryClient()} /></MemoryRouter>)
}
async function pickUniversity() {
  const select = await screen.findByLabelText('카카오 식당 불러오기 · 대학교')
  await waitFor(() => expect(within(select).getByRole('option', { name: /순천향대학교/ })).toBeTruthy())
  await userEvent.selectOptions(select, 'u1')
}

beforeEach(() => {
  fake.reset(); fake.signInAs('admin')
  fake.respond('universities:select', { data: [UNI] })
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('식당 목록', () => {
  it('shows name, category, university, address, Kakao ID and publication status', async () => {
    fake.respond('restaurant_overrides:select', { data: [row()], count: 1 })
    open()
    expect(await screen.findByText('어굿플레이스')).toBeTruthy()
    expect(screen.getByText('Kakao ID 1776574318')).toBeTruthy()
    expect(screen.getByText('한식')).toBeTruthy()
    expect(screen.getByText('관리자가 입력한 주소')).toBeTruthy()
    expect(screen.getAllByText('초안').length).toBeGreaterThan(1) // the status badge (and the filter option)
    expect(screen.getAllByText('순천향대학교').length).toBeGreaterThan(0)
  })

  it('an empty catalog points at the Kakao import instead of a dead end', async () => {
    fake.respond('restaurant_overrides:select', { data: [], count: 0 })
    open()
    expect(await screen.findByText(/카카오 식당 불러오기/)).toBeTruthy()
  })
})

/** What the server answers for ONE searched circle: places near the campus; the root circle is "full" (truncated). */
const cellAnswer = (body: unknown, opts: { fullAbove?: number; docs?: ReturnType<typeof doc>[] } = {}) => {
  const b = body as { cell: { radius_m: number } }
  const docs = opts.docs ?? [doc('1', '가'), doc('2', '나', '50'), doc('3', '다', '70')]
  const truncated = opts.fullAbove != null && b.cell.radius_m > opts.fullAbove
  return { data: { success: true, documents: docs, meta: { total_count: docs.length, pageable_count: docs.length, returned: docs.length, truncated, kakao_calls: 1 }, university: { id: 'u1', search_radius_m: 3000 } } }
}
const httpError = (status: number, body: unknown, name = 'FunctionsHttpError') => ({ name, message: 'x', context: { status, json: async () => body } })
const search = async () => { await userEvent.click(screen.getByRole('button', { name: /카카오에서 찾기/ })) }
/** The list query and the fresh per-university read are both `universities:select`; tell them apart by the id filter. */
const universities = (fresh: Record<string, unknown>) =>
  fake.respond('universities:select', (c: { filters: [string, ...unknown[]][] }) => ({ data: [c.filters.some((f) => f[0] === 'eq') ? { ...UNI, ...fresh } : UNI] }))

describe('카카오 식당 불러오기', () => {
  it('reads the university\'s radius from Supabase at search time and searches that area (not a stale list value)', async () => {
    universities({ search_radius_m: 3000 }) // the dropdown list still says 1500: the fresh read wins
    fake.respond('universities:select', (c: { filters: [string, ...unknown[]][] }) => ({ data: [c.filters.some((f) => f[0] === 'eq') ? { ...UNI, search_radius_m: 3000 } : { ...UNI, search_radius_m: 1500 }] }))
    fake.respond('restaurant_overrides:select', { data: [], count: 0 })
    fake.respond('fn:admin_kakao_search', cellAnswer)
    open(); await pickUniversity()
    await search()
    const list = await screen.findByRole('group', { name: '찾은 식당' })
    expect(within(list).getAllByRole('status')[0].textContent).toContain('반경 3000m 안에서')
    const first = fake.invokes[0]
    expect(first.name).toBe('admin_kakao_search')
    const body = first.body as { university_id: string; category_group_code: string; cell: { lat: number; lng: number; radius_m: number } }
    expect(body.university_id).toBe('u1')
    expect(body.cell.lat).toBeCloseTo(36.76999, 6)
    expect(body.cell.lng).toBeCloseTo(126.9315, 6)
    expect(body.cell.radius_m).toBeGreaterThanOrEqual(Math.ceil(3000 * Math.SQRT2)) // 3000, not 1500 (which would be ~2122)
    expect(fake.calls.some((c) => c.table === 'universities' && c.filters.some((f) => f[0] === 'eq' && f[1] === 'id' && f[2] === 'u1'))).toBe(true)
    expect(new Set(fake.invokes.map((i) => (i.body as { category_group_code: string }).category_group_code))).toEqual(new Set(['FD6', 'CE7']))
  })

  it('a different radius changes what is searched (1500 vs 3000)', async () => {
    universities({ search_radius_m: 1500 })
    fake.respond('restaurant_overrides:select', { data: [], count: 0 })
    fake.respond('fn:admin_kakao_search', cellAnswer)
    open(); await pickUniversity(); await search()
    await screen.findByRole('group', { name: '찾은 식당' })
    const r = (fake.invokes[0].body as { cell: { radius_m: number } }).cell.radius_m
    expect(r).toBeLessThan(Math.ceil(3000 * Math.SQRT2))
    expect(r).toBeGreaterThanOrEqual(Math.ceil(1500 * Math.SQRT2))
  })

  it('splits a full area and reports what it did', async () => {
    universities({ search_radius_m: 3000 })
    fake.respond('restaurant_overrides:select', { data: [], count: 0 })
    fake.respond('fn:admin_kakao_search', (body: unknown) => cellAnswer(body, { fullAbove: 3500 }))
    open(); await pickUniversity(); await search()
    const report = await screen.findByLabelText('검색 범위 보고')
    expect(fake.invokes).toHaveLength(10) // (1 root + 4 quarters) x FD6 / CE7
    expect(report.textContent).toContain('검색한 구역 10개')
    expect(report.textContent).toContain('실패한 검색 0건')
    expect(report.textContent).toContain('모든 구역을 카카오 노출 한도 안에서 끝까지 읽었어요')
    expect(report.textContent).toContain('카카오가 API로 알려주지 않는 장소는 찾을 수 없어요') // never claims a census
  })

  it('places beyond the radius are dropped and counted; the distance shown is from the university', async () => {
    universities({ search_radius_m: 3000 })
    fake.respond('restaurant_overrides:select', { data: [], count: 0 })
    fake.respond('fn:admin_kakao_search', (b: unknown) => cellAnswer(b, { docs: [doc('1', '가까운 곳'), { ...doc('9', '반경 밖'), x: '126.9315', y: '36.80', distance: '12' }] }))
    open(); await pickUniversity(); await search()
    const list = await screen.findByRole('group', { name: '찾은 식당' })
    expect(within(list).getAllByRole('status')[0].textContent).toContain('1곳을 찾았어요')
    expect(within(list).queryByText('반경 밖')).toBeNull()
    expect(screen.getByLabelText('검색 범위 보고').textContent).toContain('반경 밖이라 제외 1곳')
    expect(within(list).queryByText(/· 12m/)).toBeNull() // Kakao's own distance is not shown
  })

  it('lists which places are already managed and registers only the ticked new ones', async () => {
    universities({ search_radius_m: 3000 })
    fake.respond('restaurant_overrides:select', { data: [{ kakao_place_id: '1', visibility: 'published' }], count: 0 })
    fake.respond('fn:admin_kakao_search', cellAnswer)
    fake.respond('rpc:admin_register_kakao_places', { data: { added: 1, already_managed: 0, skipped: 0 } })
    open(); await pickUniversity(); await search()
    const list = await screen.findByRole('group', { name: '찾은 식당' })
    expect(within(list).getByText(/3곳/)).toBeTruthy()
    expect(within(list).getByText(/이미 관리 중 1곳, 새 식당 2곳/)).toBeTruthy()
    expect(within(list).getByText('관리 중 · 공개')).toBeTruthy()
    expect((within(list).getByLabelText('가 선택') as HTMLInputElement).disabled).toBe(true) // already managed: cannot be picked again
    expect(fake.rpcs.filter((r) => r.name !== 'cms_overview')).toHaveLength(0) // nothing is stored before the admin chooses

    expect((within(list).getByRole('button', { name: '0곳 등록하기' }) as HTMLButtonElement).disabled).toBe(true)
    await userEvent.click(within(list).getByLabelText('나 선택'))
    await userEvent.click(within(list).getByRole('button', { name: '1곳 등록하기' }))
    expect(await screen.findByText(/1곳을 초안으로 등록했어요/)).toBeTruthy()
    const args = fake.rpcs.find((r) => r.name === 'admin_register_kakao_places')!.args as { p_university: string; p_places: Record<string, unknown>[] }
    expect(args.p_university).toBe('u1')
    expect(args.p_places.map((p) => p.id)).toEqual(['2']) // the managed place '1' is never sent: its edits stay untouched
    // only what the server needs to validate and label: no address, phone or category path is sent for storage
    expect(Object.keys(args.p_places[0]).sort()).toEqual(['category_group_code', 'id', 'place_name', 'x', 'y'])
  })

  it('a repeat import shows what was registered as managed and offers nothing new to register', async () => {
    universities({ search_radius_m: 3000 })
    fake.respond('restaurant_overrides:select', { data: [{ kakao_place_id: '1', visibility: 'draft' }, { kakao_place_id: '2', visibility: 'draft' }, { kakao_place_id: '3', visibility: 'published' }], count: 0 })
    fake.respond('fn:admin_kakao_search', cellAnswer)
    open(); await pickUniversity(); await search()
    const list = await screen.findByRole('group', { name: '찾은 식당' })
    expect(within(list).getByText(/이미 관리 중 3곳, 새 식당 0곳/)).toBeTruthy()
    await userEvent.click(within(list).getByRole('button', { name: '새 식당 모두 선택' }))
    expect((within(list).getByRole('button', { name: '0곳 등록하기' }) as HTMLButtonElement).disabled).toBe(true)
    expect(fake.rpcs.filter((r) => r.name === 'admin_register_kakao_places')).toHaveLength(0)
  })

  it('"새 식당 모두 선택" ticks every unmanaged place', async () => {
    universities({ search_radius_m: 3000 })
    fake.respond('restaurant_overrides:select', { data: [{ kakao_place_id: '1', visibility: 'draft' }], count: 0 })
    fake.respond('fn:admin_kakao_search', cellAnswer)
    open(); await pickUniversity(); await search()
    await userEvent.click(await screen.findByRole('button', { name: '새 식당 모두 선택' }))
    expect(screen.getByRole('button', { name: '2곳 등록하기' })).toBeTruthy()
  })

  it('explains clearly when the migration has not been applied', async () => {
    universities({ search_radius_m: 3000 })
    fake.respond('restaurant_overrides:select', { data: [], count: 0 })
    fake.respond('fn:admin_kakao_search', (b: unknown) => cellAnswer(b, { docs: [doc('1', '가')] }))
    fake.respond('rpc:admin_register_kakao_places', { error: { message: 'Could not find the function public.admin_register_kakao_places(p_places, p_university) in the schema cache' } })
    open(); await pickUniversity(); await search()
    await userEvent.click(await screen.findByLabelText('가 선택'))
    await userEvent.click(screen.getByRole('button', { name: '1곳 등록하기' }))
    expect(await screen.findByText(/마이그레이션 20261111000100을 먼저 적용/)).toBeTruthy()
  })

  it('refuses to search without a valid radius, and asks nothing of Kakao', async () => {
    universities({ search_radius_m: null })
    open(); await pickUniversity(); await search()
    expect(await screen.findByText(/검색 반경\(search_radius_m\)을 읽지 못했어요/)).toBeTruthy()
    expect(fake.invokes).toHaveLength(0)
  })

  it('says so when the search is not allowed or fails, and stores nothing', async () => {
    universities({ search_radius_m: 3000 })
    fake.respond('fn:admin_kakao_search', { error: httpError(403, { success: false, error: 'admin_only' }) })
    open(); await pickUniversity(); await search()
    expect(await screen.findByText(/카카오 검색에 실패했거나 중단됐어요/)).toBeTruthy()
    expect(fake.invokes.length).toBeLessThanOrEqual(2) // only the two first searches (FD6, CE7) were in flight: a refusal is not retried
    expect(fake.rpcs.filter((r) => r.name !== 'cms_overview')).toHaveLength(0)
  })

  it('falls back to the old keyword search when the new function is not deployed, and says the result is partial', async () => {
    universities({ search_radius_m: 3000 })
    fake.respond('restaurant_overrides:select', { data: [], count: 0 })
    fake.respond('fn:admin_kakao_search', { error: httpError(404, { code: 'NOT_FOUND' }, 'FunctionsRelayError') })
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: [doc('1', '가'), { ...doc('7', '반경 밖'), x: '126.9315', y: '36.80' }] } })
    open(); await pickUniversity(); await search()
    const list = await screen.findByRole('group', { name: '찾은 식당' })
    expect(within(list).getAllByRole('status')[0].textContent).toContain('1곳을 찾았어요')
    expect(list.textContent).toContain('구역 검색 함수(admin_kakao_search)가 이 프로젝트에 아직 배포되지 않아')
    expect(list.textContent).toContain('일부만 찾은 결과예요')
    expect(list.textContent).toContain('반경 3000m 밖 1곳은 제외')
    expect(fake.invokes[0].name).toBe('admin_kakao_search')
    expect(fake.invokes.filter((i) => i.name === 'search_restaurants')).toHaveLength(KAKAO_QUERIES.length)
    expect(fake.invokes.filter((i) => i.name === 'admin_kakao_search').length).toBeLessThanOrEqual(2) // not retried
    expect(within(list).queryByText(/모든 구역을 카카오 노출 한도 안에서/)).toBeNull() // never claims full coverage
  })

  it('moderators cannot reach the restaurants page', async () => {
    fake.signInAs('moderator')
    open()
    expect(await screen.findByText('이 페이지를 볼 권한이 없어요.')).toBeTruthy()
  })
})

describe('카카오 실시간 정보', () => {
  const editPage = () => {
    fake.respond('restaurant_overrides:select', { data: [{ id: 'r1', kakao_place_id: '1', name_ko: '수정된 이름', visibility: 'draft', image_url: null }] })
    fake.respond('restaurant_university_links:select', { data: [{ university_id: 'u1', universities: { latitude: 36.77, longitude: 126.93 } }] })
    fake.respond('rpc:cms_state', { data: { live: { name_ko: '수정된 이름', visibility: 'draft', featured: false, university_ids: [], dining_purposes: [], opening_hours: {} }, live_version: 0, last_published: null, draft: null, jobs: [] } })
    render(<MemoryRouter initialEntries={['/restaurants/r1']}><App client={makeQueryClient()} /></MemoryRouter>)
  }
  it('fetches the Kakao original LIVE around the linked campus and shows it read-only, separate from the editable values', async () => {
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: [{ ...doc('1', '카카오 원래 이름'), place_url: 'http://place.map.kakao.com/1' }, doc('2', '다른 곳')] } })
    editPage()
    const card = await screen.findByLabelText('카카오 실시간 정보')
    expect(await within(card).findByText('카카오 원래 이름')).toBeTruthy()
    expect(within(card).getByText('36.77 / 126.93')).toBeTruthy()
    expect(within(card).getByRole('link', { name: '장소 페이지' }).getAttribute('href')).toBe('https://place.map.kakao.com/1')
    expect(fake.invokes[0]).toMatchObject({ name: 'search_restaurants', body: { query: '수정된 이름', latitude: 36.77, longitude: 126.93 } })
    expect(await screen.findByDisplayValue('수정된 이름')).toBeTruthy()
    // nothing from Kakao was written anywhere
    expect(fake.calls.filter((c) => c.op !== 'select')).toHaveLength(0)
    expect(fake.rpcs.filter((r) => r.name !== 'cms_state')).toHaveLength(0)
  })
  it('says so when Kakao no longer returns the place', async () => {
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: [doc('9', '없는 곳')] } })
    editPage()
    expect(await screen.findByText(/카카오에서 이 장소를 지금 찾지 못했어요/)).toBeTruthy()
  })
})
