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
vi.mock('../menus/MenuCsvTools', () => ({ downloadText: vi.fn() }))
import { downloadText } from '../menus/MenuCsvTools'

const LIVE = { name_ko: '15번가에비뉴', name_en: null, category: null, address: null, latitude: null, longitude: null, phone: null, description: null, opening_hours: {}, break_time: null, last_order_time: null, business_status: null, price_min_krw: null, price_max_krw: null, avg_cost_krw: null, dining_purposes: [], visibility: 'published', featured: false, display_order: null, university_ids: [] }
const STATE = { live: LIVE, live_version: 1, last_published: null, draft: null, jobs: [] }
const review = (over: Record<string, unknown>) => ({ id: 'r1', kakao_place_id: 'k1', rating: 5, source: 'naver', platform: null, source_rating: 4.5, body: '커피가 좋아요', moderation_status: 'visible', moderation_reason: null, created_at: '2026-06-13T00:00:00Z', ...over })

function openRestaurant(placeId: string | null) {
  fake.signInAs('admin')
  fake.respond('restaurant_overrides:select', { data: [{ id: 'r1', kakao_place_id: placeId, image_url: null }] })
  fake.respond('rpc:cms_state', { data: STATE })
  fake.respond('universities:select', { data: [] })
  fake.respond('student_reviews:select', { data: [review({}), review({ id: 'r2', rating: null, source_rating: null, body: '별점 없는 글' })], count: 2 })
  return render(<MemoryRouter initialEntries={['/restaurants/r1']}><App client={makeQueryClient()} /></MemoryRouter>)
}

beforeEach(() => {
  fake.reset(); vi.mocked(downloadText).mockClear()
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('a restaurant\'s own reviews (its edit page)', () => {
  it('lists only that restaurant\'s reviews, with moderation, and no restaurant filter or links', async () => {
    openRestaurant('k1')
    const section = within(await screen.findByLabelText('이 식당의 리뷰'))
    await section.findByText('커피가 좋아요')
    expect(section.getByText('★ 4.5')).toBeTruthy()
    expect(section.getByText('별점 없음', { selector: 'div' })).toBeTruthy()
    expect(section.getAllByRole('button', { name: '숨기기' })).toHaveLength(2)
    expect(section.queryByLabelText('식당 검색')).toBeNull()
    expect(section.getByText('이 식당의 리뷰 CSV')).toBeTruthy()
    expect(fake.calls.some((c) => c.table === 'student_reviews' && c.filters.some((f) => f[0] === 'eq' && f[1] === 'kakao_place_id' && f[2] === 'k1'))).toBe(true)
    // no query for the reviews of any other place
    expect(fake.calls.filter((c) => c.table === 'student_reviews' && !c.filters.some((f) => f[0] === 'eq' && f[1] === 'kakao_place_id' && f[2] === 'k1'))).toHaveLength(0)
  })

  it('exports only this restaurant and offers the import', async () => {
    openRestaurant('k1')
    const section = within(await screen.findByLabelText('이 식당의 리뷰'))
    expect(section.getByRole('button', { name: 'CSV 가져오기' })).toBeTruthy()
    await userEvent.click(section.getByRole('button', { name: 'CSV 내보내기' }))
    await waitFor(() => expect(downloadText).toHaveBeenCalled())
    expect(vi.mocked(downloadText).mock.calls[0][0]).toMatch(/^reviews-k1-/)
  })

  it('typing in the review search never touches the restaurant\'s own form or draft', async () => {
    openRestaurant('k1')
    const section = within(await screen.findByLabelText('이 식당의 리뷰'))
    await userEvent.type(await section.findByLabelText('리뷰 검색'), '커피{enter}')
    expect(fake.rpcs.filter((r) => r.name === 'cms_save_draft')).toHaveLength(0)
  })

  it('a restaurant without a Kakao place id says reviews cannot be loaded, and asks for none', async () => {
    openRestaurant(null)
    const section = within(await screen.findByLabelText('이 식당의 리뷰'))
    expect(section.getByText(/카카오 장소 ID가 없는 식당은 리뷰를 불러올 수 없어요/)).toBeTruthy()
    expect(section.queryByRole('button', { name: 'CSV 내보내기' })).toBeNull()
    expect(fake.calls.filter((c) => c.table === 'student_reviews')).toHaveLength(0)
  })
})
