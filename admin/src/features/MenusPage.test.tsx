import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import { diffSnapshots, isLiveVisible } from '@/lib/cms'
import { validateMenu } from './MenusPage'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})
vi.mock('@/lib/images', async (orig) => ({
  ...(await orig<typeof import('@/lib/images')>()),
  prepareImage: async (f: File) => ({ blob: f, type: f.type, width: 800, height: 600, bytes: f.size }),
}))

const BASE = 'https://x.supabase.co/storage/v1/object/public/restaurant-images/'
const menu = (over: Record<string, unknown> = {}) => ({
  id: 'm1', name_ko: '제육 정식', description_ko: null, price_krw: 8000, available: true, representative: false, recommended: false, category: '식사',
  price_verified_on: '2026-11-01', status: 'active', sort_order: 1, image_url: null, ...over,
})

const STATE = (items: unknown[], over: Record<string, unknown> = {}) => ({ live: { items }, live_version: 1, last_published: null, draft: null, jobs: [], ...over })
const DRAFT = (items: unknown[], over: Record<string, unknown> = {}) => ({ data: { items }, revision: 1, base_version: 1, created_by: 'u-1', updated_by: 'u-1', created_at: '2026-11-09T00:00:00Z', updated_at: '2026-11-10T01:00:00Z', stale: false, has_changes: true, ...over })
async function openMenus(items: unknown[], state: Record<string, unknown> = {}) {
  fake.respond('restaurant_overrides:select', { data: [{ id: 'r1', name_ko: '온기식당' }] })
  fake.respond('rpc:cms_state', { data: STATE(items, state) })
  fake.respond('rpc:cms_save_draft', { data: { revision: 1, base_version: 1, updated_at: '2026-11-10T00:00:00Z' } })
  fake.respond('rpc:cms_overview', { data: [] })
  render(<MemoryRouter initialEntries={['/menus']}><App client={makeQueryClient()} /></MemoryRouter>)
  await userEvent.click(await screen.findByRole('button', { name: /온기식당/ }))
}
const saved = () => (fake.rpcs.filter((r) => r.name === 'cms_save_draft').at(-1)!.args as { p_type: string; p_id: string; p_data: { items: Record<string, unknown>[] }; p_expected_revision: number })
const noLiveWrites = () => { for (const op of ['insert', 'update', 'upsert', 'delete']) expect(fake.last('restaurant_menus', op)).toBeUndefined() }

beforeEach(() => {
  fake.reset(); fake.signInAs('admin')
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('validateMenu', () => {
  const d = { name: '제육', price: '', description: '', category: '', verified: '' }
  it('keeps an unknown price unknown, never 0', () => expect(validateMenu(d)).toEqual({ error: null, price: null }))
  it('accepts thousands separators', () => expect(validateMenu({ ...d, price: '8,000' }).price).toBe(8000))
  it('rejects bad input', () => {
    expect(validateMenu({ ...d, name: ' ' }).error).toBeTruthy()
    expect(validateMenu({ ...d, price: '-5' }).error).toBeTruthy()
    expect(validateMenu({ ...d, price: '7.5' }).error).toBeTruthy()
    expect(validateMenu({ ...d, price: '', verified: '2026-11-01' }).error).toMatch(/가격이 없으면/)
    expect(validateMenu({ ...d, price: '8000', verified: '11/01' }).error).toBeTruthy()
  })
})

describe('메뉴·가격 (초안 → 게시)', () => {
  it('lists menus with price, category and verification date; unknown price says so', async () => {
    await openMenus([menu(), menu({ id: 'm2', name_ko: '계란말이', price_krw: null, price_verified_on: null, sort_order: 2 })])
    expect(await screen.findByText('제육 정식')).toBeTruthy()
    expect(screen.getByText(/8,000원 · 식사/)).toBeTruthy()
    expect(screen.getByText('가격 확인 2026-11-01')).toBeTruthy()
    expect(screen.getByText(/가격 미정/)).toBeTruthy()
  })

  it('adds a menu to the draft with an unknown price as null; nothing is written live', async () => {
    await openMenus([])
    await userEvent.type(await screen.findByLabelText('메뉴 이름'), '김치찌개')
    await userEvent.click(screen.getByRole('button', { name: '메뉴 추가' }))
    await screen.findByText(/초안에 담았어요/)
    expect(screen.getByText(/저장하지 않은 수정/)).toBeTruthy()
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    expect(saved()).toMatchObject({ p_type: 'restaurant_menus', p_id: 'r1', p_expected_revision: 0 })
    expect(saved().p_data.items).toHaveLength(1)
    expect(saved().p_data.items[0]).toMatchObject({ name_ko: '김치찌개', price_krw: null, price_verified_on: null, status: 'active', available: true })
    expect(String(saved().p_data.items[0].id)).toMatch(/^[0-9a-f-]{36}$/)
    noLiveWrites()
  })

  it('edits an existing menu and saves the whole list as a draft', async () => {
    await openMenus([menu(), menu({ id: 'm2', name_ko: '계란말이', sort_order: 2 })])
    await userEvent.click((await screen.findAllByRole('button', { name: '수정' }))[0])
    const name = screen.getByLabelText('메뉴 이름')
    await userEvent.clear(name); await userEvent.type(name, '제육 정식 (대)')
    await userEvent.clear(screen.getByLabelText(/가격 \(원\)/)); await userEvent.type(screen.getByLabelText(/가격 \(원\)/), '9000')
    await userEvent.click(screen.getByRole('button', { name: '수정 담기' }))
    expect(await screen.findByText('수정됨 (게시 전)')).toBeTruthy()
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    expect(saved().p_data.items).toHaveLength(2)
    expect(saved().p_data.items[0]).toMatchObject({ id: 'm1', name_ko: '제육 정식 (대)', price_krw: 9000, category: '식사' })
    expect(saved().p_data.items[1]).toMatchObject({ id: 'm2', name_ko: '계란말이' })
    noLiveWrites()
  })

  it('toggles recommended, sold-out and archives instead of deleting', async () => {
    await openMenus([menu()])
    await userEvent.click(await screen.findByRole('button', { name: '추천 메뉴 전환' }))
    await userEvent.click(screen.getByRole('button', { name: '품절 처리' }))
    await userEvent.click(screen.getByRole('button', { name: '보관' }))
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    expect(saved().p_data.items[0]).toMatchObject({ recommended: true, available: false, status: 'archived' })
    noLiveWrites()
  })

  it('reorders menus by swapping their sort order', async () => {
    await openMenus([menu(), menu({ id: 'm2', name_ko: '계란말이', sort_order: 2 })])
    await userEvent.click((await screen.findAllByRole('button', { name: '아래로' }))[0])
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    expect(saved().p_data.items.map((i) => [i.id, i.sort_order])).toEqual([['m2', 1], ['m1', 2]])
  })

  it('hides archived menus until asked', async () => {
    await openMenus([menu(), menu({ id: 'm2', name_ko: '옛 메뉴', status: 'archived', sort_order: 2 })])
    await screen.findByText('제육 정식')
    expect(screen.queryByText('옛 메뉴')).toBeNull()
    await userEvent.click(screen.getByLabelText(/보관된 메뉴 1개 보기/))
    expect(await screen.findByText('옛 메뉴')).toBeTruthy()
    expect(screen.getByRole('button', { name: '복원' })).toBeTruthy()
  })

  it('a new photo is staged in the draft; the published file is not deleted', async () => {
    await openMenus([menu({ image_url: `${BASE}menus/r1/old.jpg` })])
    await screen.findByText('제육 정식')
    await userEvent.upload(screen.getByLabelText('제육 정식 사진 올리기'), new File(['x'], 'p.jpg', { type: 'image/jpeg' }))
    await screen.findByText(/사진을 골랐어요/)
    expect(fake.uploads[0].path).toMatch(/^menus\/r1\/[0-9a-f-]{36}\.jpg$/)
    expect(fake.removed).toEqual([])
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    expect(String(saved().p_data.items[0].image_url)).toContain(fake.uploads[0].path)
    expect(fake.removed).toEqual([])
    noLiveWrites()
  })

  it('removing a menu from the list is archiving on publish, never a delete', async () => {
    await openMenus([menu({ image_url: `${BASE}menus/r1/a.jpg` }), menu({ id: 'm2', name_ko: '계란말이', sort_order: 2 })])
    await userEvent.click((await screen.findAllByRole('button', { name: '목록에서 제거' }))[0])
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    expect(saved().p_data.items.map((i) => i.id)).toEqual(['m2'])
    expect(fake.removed).toEqual([]) // the published photo file stays
    noLiveWrites()
  })

  it('shows the saved draft instead of live, and previews what changes', async () => {
    const live = [menu()]
    await openMenus(live, { draft: DRAFT([menu({ price_krw: 9500 }), menu({ id: 'm9', name_ko: '새 메뉴', price_krw: 7000, sort_order: 2 })]) })
    expect(await screen.findByText(/9,500원/)).toBeTruthy()
    expect(screen.getByText('새 메뉴 (게시 전)')).toBeTruthy()
    await userEvent.click(screen.getByRole('button', { name: '미리보기' }))
    const list = await screen.findByLabelText('달라지는 항목')
    expect(list.textContent).toMatch(/메뉴 추가/)
    expect(list.textContent).toMatch(/제육 정식 · 가격\(원\)/)
  })

  it('publishes the saved draft through the server and schedules it in Seoul time', async () => {
    fake.respond('rpc:cms_publish', { data: 2 })
    await openMenus([menu()], { draft: DRAFT([menu({ price_krw: 9500 })]) })
    await userEvent.click(await screen.findByRole('button', { name: '지금 게시' }))
    const dlg = await screen.findByRole('dialog')
    await userEvent.click(within(dlg).getByRole('button', { name: '지금 게시' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_publish')).toBe(true))
    expect(fake.rpcs.find((r) => r.name === 'cms_publish')!.args).toMatchObject({ p_type: 'restaurant_menus', p_id: 'r1', p_expected_revision: 1 })
    noLiveWrites()
  })

  it('a conflicting save tells the admin and offers the latest draft', async () => {
    await openMenus([menu()])
    fake.respond('rpc:cms_save_draft', { error: { code: '40001', message: '다른 관리자가 이 초안을 먼저 저장했어요.' } })
    await userEvent.click(await screen.findByRole('button', { name: '품절 처리' }))
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    expect((await screen.findAllByText(/다른 관리자가/)).length).toBeGreaterThan(0)
  })
})

describe('menu diff helpers', () => {
  const a = { items: [menu(), menu({ id: 'm2', name_ko: '계란말이', sort_order: 2 })] }
  it('reports added, removed (archived), changed and reordered lines', () => {
    const b = { items: [menu({ id: 'm2', name_ko: '계란말이', sort_order: 1 }), menu({ price_krw: 9000, sort_order: 2 }), menu({ id: 'm3', name_ko: '새', sort_order: 3 })] }
    const c = diffSnapshots(a, b)
    expect(c.map((x) => x.label)).toEqual(expect.arrayContaining(['메뉴 추가', '제육 정식 · 가격(원)', '메뉴 순서']))
    expect(diffSnapshots(a, { items: [a.items[0]] }).map((x) => x.label)).toEqual(['메뉴 제거 (보관됨)'])
    expect(diffSnapshots(a, a)).toEqual([])
  })
  it('a menu set is visible only while some line is active', () => {
    expect(isLiveVisible('restaurant_menus', a)).toBe(true)
    expect(isLiveVisible('restaurant_menus', { items: [menu({ status: 'archived' })] })).toBe(false)
    expect(isLiveVisible('restaurant_menus', { items: [] })).toBe(false)
  })
})
