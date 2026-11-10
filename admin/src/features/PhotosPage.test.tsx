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
const STATE = (photos: unknown[], over: Record<string, unknown> = {}) => ({ live: { photos }, live_version: 1, last_published: null, draft: null, jobs: [], ...over })
const livePhotos = (photos: unknown[], over: Record<string, unknown> = {}) => {
  fake.respond('rpc:cms_state', { data: STATE(photos, over) })
  fake.respond('rpc:cms_save_draft', { data: { revision: 1, base_version: 1, updated_at: '2026-11-10T00:00:00Z' } })
  fake.respond('rpc:cms_overview', { data: [] })
}
const saved = () => (fake.rpcs.filter((r) => r.name === 'cms_save_draft').at(-1)!.args as { p_type: string; p_id: string; p_data: { photos: Record<string, unknown>[] }; p_expected_revision: number })
const noLiveWrites = () => { for (const op of ['insert', 'update', 'upsert', 'delete']) expect(fake.last('restaurant_photos', op)).toBeUndefined() }
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

describe('사진 관리 (초안 → 게시)', () => {
  it('is in the sidebar for admins and shows what the app shows', async () => {
    livePhotos([photo({ id: 'c1', kind: 'cover', sort_order: 0, storage_path: 'restaurants/r1/c.jpg', url: `${URL_BASE}restaurants/r1/c.jpg` }), photo({ id: 'g1', caption: '입구' }), photo({ id: 'g2', status: 'archived', sort_order: 2 })])
    open()
    expect(await screen.findByRole('link', { name: /사진 관리/ })).toBeTruthy()
    await choose()
    expect(await screen.findByAltText('현재 대표 사진')).toBeTruthy()
    expect(screen.getByText('앱에 표시 중')).toBeTruthy()
    expect(screen.getByText('1장')).toBeTruthy()
    expect(screen.getByText('보관된 사진')).toBeTruthy()
  })

  it('shows a clear missing-image state', async () => {
    livePhotos([])
    open(); await choose()
    expect(await screen.findByText(/대표 사진 없음/)).toBeTruthy()
    expect(screen.getByText('갤러리 사진이 없어요.')).toBeTruthy()
  })

  it('an uploaded gallery photo lives in the draft only: not live until published', async () => {
    livePhotos([photo()])
    open(); await choose()
    await screen.findByText('1장')
    await userEvent.upload(screen.getByLabelText('갤러리 사진 올리기'), new File(['x'], 'menu.jpg', { type: 'image/jpeg' }))
    await screen.findByText(/1장을 초안에 담았어요/)
    expect(fake.uploads[0].bucket).toBe('restaurant-images')
    expect(fake.uploads[0].path).toMatch(/^restaurants\/r1\/[0-9a-f-]+\.jpg$/)
    expect(screen.getByText(/저장하지 않은 수정/)).toBeTruthy()
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    expect(saved()).toMatchObject({ p_type: 'restaurant_photos', p_id: 'r1', p_expected_revision: 0 })
    expect(saved().p_data.photos).toHaveLength(2)
    expect(saved().p_data.photos[1]).toMatchObject({ kind: 'gallery', sort_order: 2, width: 1200, height: 900, source: 'admin', status: 'published' })
    expect(String(saved().p_data.photos[1].url)).toContain('/restaurant-images/restaurants/r1/')
    noLiveWrites()
  })

  it('records the credit of a student photo', async () => {
    livePhotos([])
    open(); await choose()
    await screen.findByText('갤러리 사진이 없어요.')
    await userEvent.type(screen.getByLabelText(/사진 제공자/), '민수')
    await userEvent.upload(screen.getByLabelText('갤러리 사진 올리기'), new File(['x'], 'a.png', { type: 'image/png' }))
    await screen.findByText(/1장을 초안에 담았어요/)
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    expect(saved().p_data.photos[0]).toMatchObject({ source: 'student', credit: '민수' })
  })

  it('replacing the cover archives the old one in the draft and deletes no file', async () => {
    livePhotos([photo({ id: 'c1', kind: 'cover', sort_order: 0, storage_path: 'restaurants/r1/old.jpg', url: `${URL_BASE}restaurants/r1/old.jpg` })])
    open(); await choose()
    await screen.findByAltText('현재 대표 사진')
    await userEvent.upload(screen.getByLabelText('대표 사진 올리기'), new File(['x'], 'new.jpg', { type: 'image/jpeg' }))
    await screen.findByText(/새 대표 사진을 초안에 담았어요/)
    expect(fake.removed).toEqual([])
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    const ps = saved().p_data.photos
    expect(ps.find((p) => p.id === 'c1')).toMatchObject({ kind: 'cover', status: 'archived' })
    expect(ps.filter((p) => p.kind === 'cover' && p.status === 'published')).toHaveLength(1) // exactly one live cover
    expect(fake.removed).toEqual([])
    noLiveWrites()
  })

  it('makes a gallery photo the cover and archives the previous cover', async () => {
    livePhotos([photo({ id: 'c1', kind: 'cover', sort_order: 0, storage_path: 'restaurants/r1/c.jpg' }), photo({ id: 'g1', storage_path: 'restaurants/r1/g.jpg' })])
    open(); await choose()
    await userEvent.click(await screen.findByRole('button', { name: /대표로/ }))
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    const ps = saved().p_data.photos
    expect(ps.find((p) => p.id === 'g1')).toMatchObject({ kind: 'cover', status: 'published', sort_order: 0 })
    expect(ps.find((p) => p.id === 'c1')).toMatchObject({ status: 'archived' })
  })

  it('a failed upload leaves nothing in the draft', async () => {
    livePhotos([])
    open(); await choose()
    await screen.findByText('갤러리 사진이 없어요.')
    fake.respond('storage:upload', { error: { message: 'bucket full' } })
    await userEvent.upload(screen.getByLabelText('갤러리 사진 올리기'), new File(['x'], 'a.jpg', { type: 'image/jpeg' }))
    expect(await screen.findByText(/실패했어요/)).toBeTruthy()
    expect(screen.queryByText(/저장하지 않은 수정/)).toBeNull()
  })

  it('archiving keeps the file; removing from the list archives on publish and never deletes a file', async () => {
    livePhotos([photo()])
    open(); await choose()
    await screen.findByText('1장')
    await userEvent.click(screen.getByRole('button', { name: '보관' }))
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    expect(saved().p_data.photos[0]).toMatchObject({ id: 'p1', status: 'archived' })
    expect(fake.removed).toEqual([])
    noLiveWrites()
  })

  it('removing a photo from the list never deletes the published file', async () => {
    livePhotos([photo(), photo({ id: 'p2', storage_path: 'restaurants/r1/b.jpg', sort_order: 2 })])
    open(); await choose()
    await userEvent.click((await screen.findAllByRole('button', { name: '목록에서 제거' }))[0])
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    expect(saved().p_data.photos.map((p) => p.id)).toEqual(['p2'])
    expect(fake.removed).toEqual([])
    noLiveWrites()
  })

  it('shows the saved draft instead of live, with the new photo marked as not yet published', async () => {
    const draft = { data: { photos: [photo(), photo({ id: 'g9', storage_path: 'restaurants/r1/n.jpg', sort_order: 2, caption: '새 사진' })] }, revision: 1, base_version: 1, created_by: 'u-1', updated_by: 'u-1', created_at: '2026-11-09T00:00:00Z', updated_at: '2026-11-10T01:00:00Z', stale: false, has_changes: true }
    livePhotos([photo()], { draft })
    open(); await choose()
    expect(await screen.findByText('게시 전')).toBeTruthy()
    await userEvent.click(screen.getByRole('button', { name: '미리보기' }))
    const list = await screen.findByLabelText('달라지는 항목')
    expect(list.textContent).toMatch(/사진 공개/)
  })

  it('publishes through the server, not by writing the photo rows', async () => {
    fake.respond('rpc:cms_publish', { data: 2 })
    const draft = { data: { photos: [photo({ caption: '입구' })] }, revision: 1, base_version: 1, created_by: 'u-1', updated_by: 'u-1', created_at: '2026-11-09T00:00:00Z', updated_at: '2026-11-10T01:00:00Z', stale: false, has_changes: true }
    livePhotos([photo()], { draft })
    open(); await choose()
    await userEvent.click(await screen.findByRole('button', { name: '지금 게시' }))
    const dlg = await screen.findByRole('dialog')
    await userEvent.click((await import('@testing-library/react')).within(dlg).getByRole('button', { name: '지금 게시' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_publish')).toBe(true))
    expect(fake.rpcs.find((r) => r.name === 'cms_publish')!.args).toMatchObject({ p_type: 'restaurant_photos', p_id: 'r1', p_expected_revision: 1 })
    noLiveWrites()
  })

  it('warns that an unpublished restaurant shows no photos in the app', async () => {
    livePhotos([])
    restaurant('draft'); open(); await choose()
    expect(await screen.findByText(/앱에 사진이 보이지 않아요/)).toBeTruthy()
  })

  it('moderators cannot open it', async () => {
    fake.signInAs('moderator')
    open()
    expect(await screen.findByText('이 페이지를 볼 권한이 없어요.')).toBeTruthy()
  })
})
