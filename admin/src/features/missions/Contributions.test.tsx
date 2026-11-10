import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const UID = '11111111-1111-4111-8111-111111111111'
const photo = (over: Record<string, unknown> = {}) => ({
  id: 'k1', user_id: UID, kind: 'restaurant_photo', kakao_place_id: 'kp-1', status: 'pending', created_at: '2026-11-10T01:00:00Z',
  payload: { path: `${UID}/a.jpg`, caption: '입구', consent: true }, ...over,
})
const PLACE = { id: 'r1', name_ko: '온기식당', kakao_place_id: 'kp-1' }

async function open(rows: unknown[], places: unknown[] = [PLACE]) {
  fake.respond('user_contributions:select', { data: rows })
  fake.respond('restaurant_overrides:select', { data: places })
  fake.respond('restaurant_photos:select', { data: [{ sort_order: 4 }] })
  render(<MemoryRouter initialEntries={['/missions']}><App client={makeQueryClient()} /></MemoryRouter>)
  await userEvent.click(await screen.findByRole('tab', { name: '기여 검토' }))
}

beforeEach(() => {
  fake.reset(); fake.signInAs('admin')
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
  vi.stubGlobal('fetch', vi.fn(async () => ({ ok: true, blob: async () => new Blob(['img'], { type: 'image/jpeg' }) })))
})
afterEach(() => vi.unstubAllGlobals())

describe('기여 검토: student photos', () => {
  it('shows the private photo through a signed link, with the restaurant name and consent', async () => {
    await open([photo()])
    const img = await screen.findByAltText('식당 사진 제출 사진')
    expect(img.getAttribute('src')).toBe(`https://signed.example/contribution-photos/${UID}/a.jpg`)
    expect(screen.getByText('온기식당')).toBeTruthy()
    expect(screen.getByText('입구')).toBeTruthy()
    expect(screen.getByText('게시 동의함')).toBeTruthy()
  })

  it('publishes to the gallery as a student photo, then approves, then drops the private copy', async () => {
    fake.respond('rpc:admin_review_contribution', { data: null })
    await open([photo()])
    await screen.findByAltText('식당 사진 제출 사진') // the signed link has loaded
    const publish = await screen.findByRole('button', { name: '사진 관리로 보내고 승인' })
    await waitFor(() => expect((publish as HTMLButtonElement).disabled).toBe(false)) // the place has loaded
    await userEvent.click(publish)
    await screen.findByText(/승인했어요. 사진은 숨김 상태로/)
    // public copy first, in the right place
    expect(fake.uploads[0].bucket).toBe('restaurant-images')
    expect(fake.uploads[0].path).toMatch(/^restaurants\/r1\/[0-9a-f-]{36}\.jpg$/)
    expect(fake.last('restaurant_photos', 'insert')!.payload).toMatchObject({ restaurant_id: 'r1', kind: 'gallery', source: 'student', credit: '학생 제공', caption: '입구', sort_order: 5, status: 'archived' })
    const reviews = fake.rpcs.filter((r) => r.name === 'admin_review_contribution')
    expect(reviews).toHaveLength(1)
    expect(reviews[0].args).toMatchObject({ p_id: 'k1', p_status: 'approved' })
    expect(fake.removed).toEqual([`${UID}/a.jpg`]) // the private original is removed after publishing
  })

  it('rolls the gallery copy back when the approval fails', async () => {
    fake.respond('rpc:admin_review_contribution', { error: { message: 'insufficient privileges' } })
    await open([photo()])
    await screen.findByAltText('식당 사진 제출 사진')
    const publish = await screen.findByRole('button', { name: '사진 관리로 보내고 승인' })
    await waitFor(() => expect((publish as HTMLButtonElement).disabled).toBe(false)) // the place has loaded
    await userEvent.click(publish)
    await screen.findByText(/insufficient privileges/)
    expect(fake.last('restaurant_photos', 'delete')).toBeTruthy()
    expect(fake.removed).toEqual([fake.uploads[0].path]) // only the public copy; the private original stays for another try
  })

  it('a photo for a place that is not managed cannot be published, with a clear reason', async () => {
    await open([photo()], [])
    expect((await screen.findByRole('button', { name: '사진 관리로 보내고 승인' }) as HTMLButtonElement).disabled).toBe(true)
    expect(screen.getByText('관리 목록에 없음')).toBeTruthy()
    // approving for the mission is still possible
    expect((screen.getByRole('button', { name: '승인만 (미션 반영)' }) as HTMLButtonElement).disabled).toBe(false)
  })

  it('approve-only counts for the mission but publishes nothing', async () => {
    fake.respond('rpc:admin_review_contribution', { data: null })
    await open([photo({ kind: 'menu_photo' })])
    await userEvent.click(await screen.findByRole('button', { name: '승인만 (미션 반영)' }))
    await screen.findByText(/미션 진행도에 바로 반영/)
    expect(fake.uploads).toHaveLength(0)
    expect(fake.last('restaurant_photos', 'insert')).toBeUndefined()
    expect(fake.removed).toEqual([])
  })

  it('rejecting needs a reason and deletes the private photo', async () => {
    fake.respond('rpc:admin_review_contribution', { data: null })
    await open([photo()])
    await userEvent.click(await screen.findByRole('button', { name: '반려' }))
    const dlg = await screen.findByRole('dialog', { name: undefined, hidden: true }).catch(() => document.querySelector('dialog')!)
    await userEvent.type(within(dlg as HTMLElement).getByLabelText('사유 (필수)'), '음식과 관계없는 사진')
    await userEvent.click(within(dlg as HTMLElement).getByRole('button', { name: '반려' }))
    await screen.findByText(/반려했어요/)
    expect(fake.rpcs.find((r) => r.name === 'admin_review_contribution')!.args).toMatchObject({ p_status: 'rejected', p_note: '음식과 관계없는 사진' })
    expect(fake.removed).toEqual([`${UID}/a.jpg`])
  })

  it('shows recent decisions so moderation is traceable', async () => {
    await open([])
    fake.respond('user_contributions:select', (c: { filters: unknown[][] }) => ({ data: c.filters.some((f) => f[0] === 'neq') ? [photo({ id: 'h1', status: 'rejected', reviewed_at: '2026-11-09T01:00:00Z', review_note: '중복' })] : [] }))
    await userEvent.click(await screen.findByRole('button', { name: '최근 처리 내역 보기' }))
    const list = await screen.findByLabelText('처리 내역')
    await waitFor(() => expect(within(list).getByText(/반려/)).toBeTruthy())
    expect(within(list).getByText(/중복/)).toBeTruthy()
  })
})
