import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import { probeFunction } from './kakaoDiag'

// nothing here may reach the network: the "is admin_kakao_search deployed?" probe is replaced
vi.mock('./kakaoDiag', async (orig) => ({ ...(await orig<typeof import('./kakaoDiag')>()), probeFunction: vi.fn() }))
vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const UNI = { id: 'u1', name_ko: '순천향대학교', is_active: true, latitude: 36.77, longitude: 126.93, search_radius_m: 1500 }
const UNI2 = { id: 'u2', name_ko: '다른대학교', is_active: true, latitude: 37.5, longitude: 127.0, search_radius_m: 1500 }
const kdoc = (id: string, name: string, over: Record<string, unknown> = {}) => ({ id, place_name: name, category_group_code: 'FD6', category_name: '음식점 > 한식', road_address_name: `카카오 도로 ${id}`, address_name: `지번 ${id}`, phone: '041-111-2222', x: '126.931', y: '36.771', place_url: `http://place.map.kakao.com/${id}`, ...over })
const LIVE = { name_ko: '내 식당', name_en: null, category: null, address: null, phone: null, latitude: null, longitude: null, description: null, opening_hours: {}, visibility: 'draft', featured: false, university_ids: ['u1'], dining_purposes: [] }
const state = (live: Record<string, unknown> = {}, draft: unknown = null) => ({ live: { ...LIVE, ...live }, live_version: 0, last_published: null, draft, jobs: [] })
const lookups = () => fake.invokes.filter((i) => i.name === 'search_restaurants')

type Over = { placeId?: string | null; links?: unknown[]; live?: Record<string, unknown>; place?: unknown; fn?: unknown; admin?: unknown }
function editPage(o: Over = {}) {
  fake.respond('restaurant_overrides:select', { data: [{ id: 'r1', kakao_place_id: 'placeId' in o ? o.placeId : '1', name_ko: '내 식당', image_url: null, latitude: null, longitude: null }] })
  fake.respond('restaurant_university_links:select', { data: o.links ?? [{ universities: UNI }] })
  fake.respond('rpc:cms_state', { data: state(o.live) })
  fake.respond('fn:search_restaurants', (o.fn ?? { data: { success: true, restaurants: [kdoc('1', '카카오 이름')] } }) as never)
  if (o.admin) fake.respond('fn:admin_kakao_search', o.admin as never)
  return render(<MemoryRouter initialEntries={['/restaurants/r1']}><App client={makeQueryClient()} /></MemoryRouter>)
}
const writes = () => fake.calls.filter((c) => c.op !== 'select')
const nothingStored = () => { expect(writes()).toHaveLength(0); expect(fake.rpcs.filter((r) => r.name !== 'cms_state')).toHaveLength(0) }

beforeEach(() => {
  vi.stubEnv('VITE_SUPABASE_URL', 'https://test.invalid'); vi.stubEnv('VITE_SUPABASE_ANON_KEY', 'test-key')
  vi.mocked(probeFunction).mockReset().mockResolvedValue({ state: 'not_deployed', status: 404 })
  fake.reset(); fake.signInAs('admin')
  fake.respond('universities:select', { data: [UNI, UNI2] })
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})
afterEach(() => { vi.unstubAllEnvs() })

describe('edit page: empty fields show the live Kakao value, labelled, and nothing is stored', () => {
  it('an existing restaurant with a valid Kakao id: empty category / address / phone / coordinates show "Kakao Live"; the form stays clean', async () => {
    editPage()
    const card = await screen.findByLabelText('카카오 실시간 정보')
    expect(await within(card).findByText('장소 ID로 확인됨')).toBeTruthy()
    const notes = await screen.findAllByTestId('kakao-live-note')
    expect(notes).toHaveLength(5) // category, address, phone, latitude, longitude
    expect(notes[0].textContent).toMatch(/Kakao Live.*음식점 > 한식/)
    expect((screen.getByLabelText('카테고리') as HTMLInputElement).placeholder).toBe('음식점 > 한식')
    expect((screen.getByLabelText('주소') as HTMLInputElement).placeholder).toBe('카카오 도로 1')
    expect((screen.getByLabelText('위도') as HTMLInputElement).placeholder).toBe('36.771')
    // the inputs themselves are still empty: nothing was put into the form
    for (const l of ['카테고리', '주소', '전화번호', '위도', '경도']) expect((screen.getByLabelText(l) as HTMLInputElement).value).toBe('')
    // loading Kakao data must not look like an unsaved edit
    expect(screen.queryByText('저장하지 않은 수정')).toBeNull()
    expect((screen.getByRole('button', { name: '초안 저장' }) as HTMLButtonElement).disabled).toBe(false) // (no draft yet, so saving is allowed)
    nothingStored()
  })

  it('the managed value always wins: it is shown as "Meogeobojo 관리", kept in the field, and the Kakao value is only mentioned', async () => {
    editPage({ live: { category: '내가 쓴 카테고리', address: '내가 쓴 주소' } })
    await screen.findAllByTestId('kakao-live-note')
    expect((screen.getByLabelText('카테고리') as HTMLInputElement).value).toBe('내가 쓴 카테고리')
    expect((screen.getByLabelText('카테고리') as HTMLInputElement).placeholder).toBe('')
    const differs = await screen.findAllByTestId('kakao-differs')
    expect(differs.map((d) => d.textContent).join(' ')).toMatch(/음식점 > 한식/)
    expect(screen.getAllByText('Meogeobojo 관리').length).toBeGreaterThanOrEqual(3)
    expect((screen.getByLabelText('주소') as HTMLInputElement).value).toBe('내가 쓴 주소')
  })

  it('saving a draft does not carry any Kakao value (the empty fields stay empty in the draft)', async () => {
    fake.respond('rpc:cms_save_draft', { data: { revision: 1, base_version: 0, updated_at: '2026-11-10T00:00:00Z' } })
    editPage()
    await screen.findAllByTestId('kakao-live-note')
    await userEvent.type(screen.getByLabelText('설명'), '직접 쓴 설명')
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    const data = (fake.rpcs.find((r) => r.name === 'cms_save_draft')!.args as { p_data: Record<string, unknown> }).p_data
    expect(data.description).toBe('직접 쓴 설명')
    for (const k of ['category', 'address', 'phone', 'latitude', 'longitude']) expect(data[k] ?? null).toBeNull()
    expect(JSON.stringify(data)).not.toMatch(/카카오 도로|041-111-2222|음식점 > 한식|36\.771/)
  })

  it('a missing phone / address in Kakao is simply not shown (no empty line, no 0)', async () => {
    editPage({ fn: { data: { success: true, restaurants: [kdoc('1', '이름만', { phone: '', road_address_name: '', address_name: '', x: '', y: '' })] } } })
    const card = await screen.findByLabelText('카카오 실시간 정보')
    expect(await within(card).findByText('이름만')).toBeTruthy()
    expect(within(card).queryByText('전화')).toBeNull()
    expect(within(card).queryByText('주소')).toBeNull()
    expect(within(card).queryByText(/위도/)).toBeNull()
    expect(screen.queryAllByTestId('kakao-live-note').map((n) => n.textContent).join('')).not.toMatch(/\b0\b/)
  })
})

describe('edit page: refresh while the admin is typing', () => {
  it('"카카오 정보 새로고침" looks the place up again and never touches what was typed', async () => {
    editPage()
    await screen.findAllByTestId('kakao-live-note')
    await userEvent.type(screen.getByLabelText('전화번호'), '010-9999-0000')
    expect(screen.getByText('저장하지 않은 수정')).toBeTruthy()
    const before = lookups().length
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: [kdoc('1', '카카오 이름', { category_name: '음식점 > 일식' })] } })
    await userEvent.click(screen.getByRole('button', { name: '카카오 정보 새로고침' }))
    await waitFor(() => expect(lookups().length).toBe(before + 1))
    expect((await screen.findAllByText(/음식점 > 일식/)).length).toBeGreaterThan(0) // the new live value
    expect((screen.getByLabelText('전화번호') as HTMLInputElement).value).toBe('010-9999-0000') // my edit survived
    expect(screen.getByText('저장하지 않은 수정')).toBeTruthy() // still dirty because of MY edit only
    nothingStored()
  })

  it('opening the page again does not call Kakao again within the cache time', async () => {
    editPage()
    await screen.findAllByTestId('kakao-live-note')
    expect(lookups()).toHaveLength(1)
  })

  it('live data alone never marks the form as changed', async () => {
    editPage()
    await screen.findAllByTestId('kakao-live-note')
    await userEvent.click(screen.getByRole('button', { name: '카카오 정보 새로고침' }))
    await waitFor(() => expect(lookups().length).toBeGreaterThan(1))
    expect(screen.queryByText('저장하지 않은 수정')).toBeNull()
  })
})

describe('edit page: when Kakao cannot confirm the place', () => {
  it('a restaurant without a Kakao id (hand-made): no Kakao panel, no Kakao call, normal manual editing', async () => {
    editPage({ placeId: null })
    await screen.findByLabelText('이름 (한국어)')
    expect(screen.queryByLabelText('카카오 실시간 정보')).toBeNull()
    expect(lookups()).toHaveLength(0)
    expect(screen.queryAllByTestId('kakao-live-note')).toHaveLength(0)
  })

  it('an id Kakao does not return: says so, shows nothing from a look-alike, and the fields stay manual', async () => {
    editPage({ placeId: '999', fn: { data: { success: true, restaurants: [kdoc('1', '내 식당과 이름이 같은 다른 곳')] } } })
    expect(await screen.findByText(/카카오에서 이 장소 ID로 등록된 곳을 확인하지 못했어요/)).toBeTruthy()
    expect(screen.queryByText('내 식당과 이름이 같은 다른 곳')).toBeNull()
    expect(screen.queryAllByTestId('kakao-live-note')).toHaveLength(0)
  })

  it('a restaurant with no linked university (and no coordinates) cannot be searched: says why, no call', async () => {
    editPage({ links: [] })
    expect(await screen.findByText(/연결된 대학교\(또는 식당 좌표\)가 없어/)).toBeTruthy()
    expect(lookups()).toHaveLength(0)
  })

  it.each([[504, /응답이 늦어져서/], [429, /요청 한도/], [500, /응답하지 않아요/]])('Kakao timeout / quota / outage (HTTP %i) shows a readable message and keeps the page usable', async (status, text) => {
    editPage({ fn: { data: null, error: { message: 'x', context: { status } } } })
    expect(await screen.findByText(text)).toBeTruthy()
    expect(screen.getByRole('button', { name: '카카오 정보 새로고침' })).toBeTruthy()
    expect((screen.getByLabelText('설명') as HTMLTextAreaElement).disabled).toBe(false)
  })

  it('a restaurant linked to another university is searched around that university', async () => {
    editPage({ links: [{ universities: UNI2 }] })
    await screen.findAllByTestId('kakao-live-note')
    expect(lookups()[0].body).toMatchObject({ latitude: 37.5, longitude: 127 })
  })

  it('a newly imported restaurant works the same way: id + linked university is all it needs', async () => {
    editPage({ placeId: '1776574318', fn: { data: { success: true, restaurants: [kdoc('1776574318', '방금 불러온 식당')] } } })
    expect(await within(await screen.findByLabelText('카카오 실시간 정보')).findByText('방금 불러온 식당')).toBeTruthy()
  })
})

describe('new restaurant: check the Kakao id BEFORE saving', () => {
  const newPage = () => render(<MemoryRouter initialEntries={['/restaurants/new']}><App client={makeQueryClient()} /></MemoryRouter>)
  const fill = async (id: string) => {
    await userEvent.type(await screen.findByLabelText('이름 (한국어)'), '새 식당')
    await userEvent.type(screen.getByLabelText('카카오 장소 ID'), id)
    await userEvent.click(await screen.findByText('순천향대학교'))
  }

  it('shows what the id is (verified) and does NOT fill the form from it', async () => {
    fake.respond('restaurant_overrides:select', { data: [] })
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: [kdoc('1', '카카오 이름')] } })
    newPage(); await fill('1')
    expect(lookups()).toHaveLength(0) // nothing is looked up until asked
    await userEvent.click(screen.getByRole('button', { name: '카카오에서 확인하기' }))
    const card = await screen.findByLabelText('카카오 장소 확인')
    expect(await within(card).findByText('카카오 이름')).toBeTruthy()
    expect(within(card).getByText('장소 ID로 확인됨')).toBeTruthy()
    expect((screen.getByLabelText('카테고리') as HTMLInputElement).value).toBe('')
    expect((screen.getByLabelText('이름 (한국어)') as HTMLInputElement).value).toBe('새 식당')
    nothingStored()
  })

  it('an id Kakao cannot verify gets a warning (and no other place is attached); creating stays possible', async () => {
    fake.respond('restaurant_overrides:select', { data: [] })
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: [kdoc('1', '다른 곳')] } })
    newPage(); await fill('999')
    await userEvent.click(screen.getByRole('button', { name: '카카오에서 확인하기' }))
    const card = await screen.findByLabelText('카카오 장소 확인')
    expect(await within(card).findByRole('alert')).toBeTruthy()
    expect(within(card).queryByText('다른 곳')).toBeNull()
    expect((screen.getByRole('button', { name: '초안으로 만들기' }) as HTMLButtonElement).disabled).toBe(false)
  })

  it('warns when the id is already registered, so it is not created twice', async () => {
    fake.respond('restaurant_overrides:select', { data: [{ id: 'r9', name_ko: '이미 있는 식당' }] })
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: [kdoc('1', '카카오 이름')] } })
    newPage(); await fill('1')
    await userEvent.click(screen.getByRole('button', { name: '카카오에서 확인하기' }))
    expect(await screen.findByText(/이미 등록된 카카오 장소 ID예요/)).toBeTruthy()
    expect(screen.getByText('이미 있는 식당')).toBeTruthy()
  })

  it('no id typed: no check panel; the manual flow is unchanged', async () => {
    newPage()
    await screen.findByLabelText('이름 (한국어)')
    expect(screen.queryByLabelText('카카오 장소 확인')).toBeNull()
  })
})

describe('list: live Kakao info is lazy, cached and limited', () => {
  const rows = (n: number) => Array.from({ length: n }, (_, i) => ({
    id: `r${i}`, kakao_place_id: `${i + 1}`, name_ko: `식당${i + 1}`, category: null, address: null, visibility: 'draft', updated_at: '2026-11-10T00:00:00Z', description: null, image_url: null,
    latitude: null, longitude: null, restaurant_university_links: [{ university_id: 'u1', universities: { name_ko: '순천향대학교' } }],
  }))
  const openList = (n: number, docs?: unknown[]) => {
    fake.respond('restaurant_overrides:select', { data: rows(n), count: n })
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: docs ?? Array.from({ length: n }, (_, i) => kdoc(String(i + 1), `카카오${i + 1}`)) } })
    return render(<MemoryRouter initialEntries={['/restaurants']}><App client={makeQueryClient()} /></MemoryRouter>)
  }

  it('makes no Kakao request until "카카오 실시간 정보 보기" is switched on', async () => {
    openList(20)
    await screen.findByText('식당1')
    await new Promise((r) => setTimeout(r, 30))
    expect(lookups()).toHaveLength(0)
  })

  it('switched on: one lookup per visible restaurant with a Kakao id (not per render), shown with its live category and address', async () => {
    openList(20)
    await screen.findByText('식당1')
    await userEvent.click(screen.getByLabelText(/카카오 실시간 정보 보기/))
    await waitFor(() => expect(lookups()).toHaveLength(20), { timeout: 4000 })
    expect((await screen.findAllByText('음식점 > 한식')).length).toBe(20)
    await new Promise((r) => setTimeout(r, 50))
    expect(lookups()).toHaveLength(20) // re-renders did not call again
  })

  it('switching it off and on again reuses the cache (no new requests)', async () => {
    openList(5)
    await screen.findByText('식당1')
    const toggle = screen.getByLabelText(/카카오 실시간 정보 보기/)
    await userEvent.click(toggle)
    await waitFor(() => expect(lookups()).toHaveLength(5))
    await userEvent.click(toggle); await userEvent.click(toggle)
    await screen.findAllByText('음식점 > 한식')
    expect(lookups()).toHaveLength(5)
  })

  it('never has more than 3 lookups in flight at once, however long the page is', async () => {
    let inFlight = 0; let peak = 0
    fake.respond('restaurant_overrides:select', { data: rows(20), count: 20 })
    fake.respond('fn:search_restaurants', (() => { inFlight++; peak = Math.max(peak, inFlight); queueMicrotask(() => { inFlight-- }); return { data: { success: true, restaurants: [] } } }) as never)
    render(<MemoryRouter initialEntries={['/restaurants']}><App client={makeQueryClient()} /></MemoryRouter>)
    await screen.findByText('식당1')
    await userEvent.click(screen.getByLabelText(/카카오 실시간 정보 보기/))
    await waitFor(() => expect(lookups()).toHaveLength(20), { timeout: 4000 })
    expect(peak).toBeLessThanOrEqual(3)
  })

  it('a restaurant Kakao cannot confirm is marked as such; a hand-made one says it has no Kakao id', async () => {
    const r = rows(2); r[1].kakao_place_id = null as never
    fake.respond('restaurant_overrides:select', { data: r, count: 2 })
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: [] } })
    render(<MemoryRouter initialEntries={['/restaurants']}><App client={makeQueryClient()} /></MemoryRouter>)
    await screen.findByText('식당1')
    await userEvent.click(screen.getByLabelText(/카카오 실시간 정보 보기/))
    expect(await screen.findByText('카카오에서 확인 못 함')).toBeTruthy()
    expect(screen.getByText('Kakao ID 없음')).toBeTruthy()
    expect(lookups()).toHaveLength(1)
    expect(writes()).toHaveLength(0)
  })
})
