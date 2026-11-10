import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})
// jsdom has no image decoder: stand in for the resize step (its maths is tested in images.test.ts).
vi.mock('@/lib/images', async (orig) => ({
  ...(await orig<typeof import('@/lib/images')>()),
  prepareImage: async (f: File) => ({ blob: f, type: f.type, width: 1200, height: 900, bytes: f.size }),
}))

const open = () => render(<MemoryRouter initialEntries={['/photos']}><App client={makeQueryClient()} /></MemoryRouter>)
const URL_BASE = 'https://x.supabase.co/storage/v1/object/public/restaurant-images/'
const photo = (over: Record<string, unknown> = {}) => ({
  id: 'p1', restaurant_id: 'r1', kind: 'gallery', storage_path: 'restaurants/r1/a.jpg', url: `${URL_BASE}restaurants/r1/a.jpg`, caption: null,
  sort_order: 1, status: 'published', source: 'admin', credit: null, ...over,
})

const restaurant = (visibility = 'published') => fake.respond('restaurant_overrides:select', { data: [{ id: 'r1', name_ko: '온기식당', visibility }] })
async function choose() {
  await screen.findByText('식당을 선택하면 사진이 보여요.')
  await waitFor(() => expect(screen.getByRole('option', { name: '온기식당' })).toBeTruthy())
  await userEvent.selectOptions(screen.getByLabelText('식당 선택'), 'r1')
}

beforeEach(() => {
  fake.reset()
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
  fake.signInAs('admin')
  restaurant()
})

describe('사진 관리', () => {
  it('is in the sidebar for admins and shows what the app shows', async () => {
    fake.respond('restaurant_photos:select', { data: [photo({ id: 'c1', kind: 'cover', sort_order: 0, storage_path: 'restaurants/r1/c.jpg', url: `${URL_BASE}restaurants/r1/c.jpg` }), photo({ id: 'g1', caption: '입구' }), photo({ id: 'g2', status: 'archived', sort_order: 2 })] })
    open()
    expect(await screen.findByRole('link', { name: /사진 관리/ })).toBeTruthy()
    await choose()
    expect(await screen.findByAltText('현재 대표 사진')).toBeTruthy()
    expect(screen.getByText('앱에 표시 중')).toBeTruthy()
    expect(screen.getByText(/1장 공개 중/)).toBeTruthy()
    expect(screen.getByText('보관된 사진')).toBeTruthy()
  })

  it('shows a clear missing-image state', async () => {
    fake.respond('restaurant_photos:select', { data: [] })
    open(); await choose()
    expect(await screen.findByText(/대표 사진 없음/)).toBeTruthy()
    expect(screen.getByText('갤러리 사진이 없어요.')).toBeTruthy()
  })

  it('uploads gallery photos to the bucket and records them', async () => {
    fake.respond('restaurant_photos:select', { data: [photo()] })
    open(); await choose()
    await screen.findByText(/1장 공개 중/)
    const file = new File(['x'], 'menu.jpg', { type: 'image/jpeg' })
    await userEvent.upload(screen.getByLabelText('갤러리 사진 올리기'), file)
    await screen.findByText('1장을 올렸어요.')
    expect(fake.uploads[0].bucket).toBe('restaurant-images')
    expect(fake.uploads[0].path).toMatch(/^restaurants\/r1\/[0-9a-f-]+\.jpg$/)
    const ins = fake.last('restaurant_photos', 'insert')!.payload as Record<string, unknown>
    expect(ins).toMatchObject({ restaurant_id: 'r1', kind: 'gallery', sort_order: 2, width: 1200, height: 900, source: 'admin' })
    expect(String(ins.url)).toContain('/restaurant-images/restaurants/r1/')
  })

  it('records the credit of a student photo', async () => {
    fake.respond('restaurant_photos:select', { data: [] })
    open(); await choose()
    await screen.findByText('갤러리 사진이 없어요.')
    await userEvent.type(screen.getByLabelText(/사진 제공자/), '민수')
    await userEvent.upload(screen.getByLabelText('갤러리 사진 올리기'), new File(['x'], 'a.png', { type: 'image/png' }))
    await screen.findByText('1장을 올렸어요.')
    expect(fake.last('restaurant_photos', 'insert')!.payload).toMatchObject({ source: 'student', credit: '민수' })
  })

  it('replaces the cover: archives the old one, adds the new one, then deletes the old file', async () => {
    fake.respond('restaurant_photos:select', { data: [photo({ id: 'c1', kind: 'cover', sort_order: 0, storage_path: 'restaurants/r1/old.jpg', url: `${URL_BASE}restaurants/r1/old.jpg` })] })
    open(); await choose()
    await screen.findByAltText('현재 대표 사진')
    await userEvent.upload(screen.getByLabelText('대표 사진 올리기'), new File(['x'], 'new.jpg', { type: 'image/jpeg' }))
    await screen.findByText(/대표 사진을 바꿨어요/)
    const ops = fake.calls.filter((c) => c.table === 'restaurant_photos' && c.op !== 'select').map((c) => c.op)
    expect(ops).toEqual(['update', 'insert', 'delete']) // order matters: one live cover at a time
    expect(fake.last('restaurant_photos', 'update')!.payload).toEqual({ status: 'archived' })
    expect(fake.last('restaurant_photos', 'insert')!.payload).toMatchObject({ kind: 'cover' })
    expect(fake.removed).toEqual(['restaurants/r1/old.jpg'])
  })

  it('cleans up the uploaded file when the database refuses the row', async () => {
    fake.respond('restaurant_photos:select', { data: [] })
    fake.respond('restaurant_photos:insert', { error: { message: 'new row violates row-level security policy' } })
    open(); await choose()
    await screen.findByText('갤러리 사진이 없어요.')
    await userEvent.upload(screen.getByLabelText('갤러리 사진 올리기'), new File(['x'], 'a.jpg', { type: 'image/jpeg' }))
    await screen.findByText(/실패했어요/)
    expect(fake.removed).toEqual([fake.uploads[0].path]) // no orphan left behind
  })

  it('deleting a photo removes the row and its file; archiving keeps the file', async () => {
    fake.respond('restaurant_photos:select', { data: [photo()] })
    open(); await choose()
    await screen.findByText(/1장 공개 중/)
    await userEvent.click(screen.getByRole('button', { name: '보관' }))
    await screen.findByText(/보관했어요/)
    expect(fake.last('restaurant_photos', 'update')!.payload).toEqual({ status: 'archived' })
    expect(fake.removed).toEqual([])
    await userEvent.click(screen.getByRole('button', { name: '삭제' }))
    await userEvent.click(await screen.findByRole('button', { name: '삭제', hidden: true }).catch(() => screen.getAllByRole('button', { name: '삭제' }).at(-1)!))
    await screen.findByText('사진을 삭제했어요.')
    expect(fake.last('restaurant_photos', 'delete')).toBeTruthy()
    expect(fake.removed).toEqual(['restaurants/r1/a.jpg'])
  })

  it('warns that an unpublished restaurant shows no photos in the app', async () => {
    fake.respond('restaurant_photos:select', { data: [] })
    restaurant('draft'); open(); await choose()
    expect(await screen.findByText(/앱에 사진이 보이지 않아요/)).toBeTruthy()
  })

  it('moderators cannot open it', async () => {
    fake.signInAs('moderator')
    open()
    expect(await screen.findByText('이 페이지를 볼 권한이 없어요.')).toBeTruthy()
  })
})
