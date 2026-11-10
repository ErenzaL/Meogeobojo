import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
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
async function openMenus(rows: unknown[]) {
  fake.respond('restaurant_overrides:select', { data: [{ id: 'r1', name_ko: '온기식당' }] })
  fake.respond('restaurant_menus:select', { data: rows })
  render(<MemoryRouter initialEntries={['/menus']}><App client={makeQueryClient()} /></MemoryRouter>)
  await waitFor(() => expect(screen.getByRole('option', { name: '온기식당' })).toBeTruthy())
  await userEvent.selectOptions(screen.getByLabelText('식당 선택'), 'r1')
}

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

describe('메뉴·가격', () => {
  it('lists menus with price, category and verification date; unknown price says so', async () => {
    await openMenus([menu(), menu({ id: 'm2', name_ko: '계란말이', price_krw: null, price_verified_on: null, sort_order: 2 })])
    expect(await screen.findByText('제육 정식')).toBeTruthy()
    expect(screen.getByText(/8,000원 · 식사/)).toBeTruthy()
    expect(screen.getByText('가격 확인 2026-11-01')).toBeTruthy()
    expect(screen.getByText(/가격 미정/)).toBeTruthy()
  })

  it('adds a menu with an unknown price as null and no fabricated value', async () => {
    await openMenus([])
    await userEvent.type(await screen.findByLabelText('메뉴 이름'), '김치찌개')
    await userEvent.click(screen.getByRole('button', { name: '메뉴 추가' }))
    await waitFor(() => expect(fake.last('restaurant_menus', 'insert')).toBeTruthy())
    expect(fake.last('restaurant_menus', 'insert')!.payload).toMatchObject({ restaurant_id: 'r1', name_ko: '김치찌개', price_krw: null, price_verified_on: null, source: 'admin' })
  })

  it('edits an existing menu in place', async () => {
    await openMenus([menu()])
    await userEvent.click(await screen.findByRole('button', { name: '수정' }))
    const name = screen.getByLabelText('메뉴 이름')
    await userEvent.clear(name); await userEvent.type(name, '제육 정식 (대)')
    await userEvent.clear(screen.getByLabelText(/가격 \(원\)/)); await userEvent.type(screen.getByLabelText(/가격 \(원\)/), '9000')
    await userEvent.click(screen.getByRole('button', { name: '저장' }))
    await waitFor(() => expect(fake.last('restaurant_menus', 'update')).toBeTruthy())
    expect(fake.last('restaurant_menus', 'update')!.payload).toMatchObject({ name_ko: '제육 정식 (대)', price_krw: 9000, category: '식사' })
  })

  it('toggles recommended, sold-out and archives instead of deleting', async () => {
    await openMenus([menu()])
    await userEvent.click(await screen.findByRole('button', { name: '추천 메뉴 전환' }))
    await waitFor(() => expect(fake.last('restaurant_menus', 'update')!.payload).toEqual({ recommended: true }))
    await userEvent.click(screen.getByRole('button', { name: '품절 처리' }))
    await waitFor(() => expect(fake.last('restaurant_menus', 'update')!.payload).toEqual({ available: false }))
    await userEvent.click(screen.getByRole('button', { name: '보관' }))
    await waitFor(() => expect(fake.last('restaurant_menus', 'update')!.payload).toEqual({ status: 'archived' }))
  })

  it('hides archived menus until asked', async () => {
    await openMenus([menu(), menu({ id: 'm2', name_ko: '옛 메뉴', status: 'archived', sort_order: 2 })])
    await screen.findByText('제육 정식')
    expect(screen.queryByText('옛 메뉴')).toBeNull()
    await userEvent.click(screen.getByLabelText(/보관된 메뉴 1개 보기/))
    expect(await screen.findByText('옛 메뉴')).toBeTruthy()
    expect(screen.getByRole('button', { name: '복원' })).toBeTruthy()
  })

  it('compresses + uploads a photo, saves its URL, and deletes the replaced file', async () => {
    await openMenus([menu({ image_url: `${BASE}menus/r1/old.jpg` })])
    await screen.findByText('제육 정식')
    await userEvent.upload(screen.getByLabelText('제육 정식 사진 올리기'), new File(['x'], 'p.jpg', { type: 'image/jpeg' }))
    await waitFor(() => expect(fake.removed).toEqual(['menus/r1/old.jpg']))
    expect(fake.uploads[0].path).toMatch(/^menus\/r1\/[0-9a-f-]{36}\.jpg$/)
    expect(String((fake.last('restaurant_menus', 'update')!.payload as { image_url: string }).image_url)).toContain(fake.uploads[0].path)
  })

  it('deleting a menu also deletes its photo file', async () => {
    await openMenus([menu({ image_url: `${BASE}menus/r1/a.jpg` })])
    await userEvent.click(await screen.findByRole('button', { name: '삭제' }))
    await userEvent.click(screen.getAllByRole('button', { name: '삭제' }).at(-1)!)
    await waitFor(() => expect(fake.removed).toEqual(['menus/r1/a.jpg']))
    expect(fake.last('restaurant_menus', 'delete')).toBeTruthy()
  })
})
