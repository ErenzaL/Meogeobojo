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

type C = { filters: [string, ...unknown[]][] }
const cols = (c: C) => String(c.filters.find((f) => f[0] === 'select')?.[1] ?? '')
const review = (over: Record<string, unknown>) => ({ id: 'r1', kakao_place_id: '1046337753', rating: 5, source: 'app', platform: null, source_rating: null, body: '학생 리뷰', moderation_status: 'visible', moderation_reason: null, created_at: '2026-11-09T00:00:00Z', ...over })
const LIST = [
  review({}),
  review({ id: 'r2', source: 'naver', rating: 5, source_rating: 4.5, body: '네이버 리뷰' }),
  review({ id: 'r3', source: 'naver', rating: null, body: '별점 없는 글' }),
  review({ id: 'r4', kakao_place_id: '382170960', source: 'lemong', platform: 'BAEMIN', rating: 4, body: '배달 리뷰', moderation_status: 'hidden', moderation_reason: '테스트' }),
]
// the two managed restaurants; 1구역 has no Kakao place id, so it can have no reviews
const RESTAURANTS = [
  { id: 'r1', name_ko: '15번가에비뉴', category: '카페', visibility: 'published', kakao_place_id: '1046337753', restaurant_university_links: [] },
  { id: 'r2', name_ko: '1구역', category: '식당', visibility: 'published', kakao_place_id: null, restaurant_university_links: [] },
  { id: 'r3', name_ko: '배달집', category: '식당', visibility: 'published', kakao_place_id: '382170960', restaurant_university_links: [] },
]

async function openReviews(role: string) {
  fake.signInAs(role)
  fake.respond('reports:select', { data: [] })
  fake.respond('universities:select', { data: [] })
  fake.respond('restaurant_overrides:select', (c: C) => {
    if (cols(c).includes('restaurant_university_links')) return { data: RESTAURANTS }
    // a lookup by place id: only 15번가에비뉴 has a record
    const only = [{ id: 'r1', kakao_place_id: '1046337753', name_ko: '15번가에비뉴' }]
    const eq = c.filters.find((f) => f[0] === 'eq' && f[1] === 'kakao_place_id')
    return { data: eq && eq[2] !== '1046337753' ? [] : only }
  })
  fake.respond('student_reviews:select', (c: C) => {
    if (cols(c) === 'kakao_place_id') return { data: LIST.map((r) => ({ kakao_place_id: r.kakao_place_id })) } // the per-restaurant counts
    let rows = LIST
    for (const [name, ...a] of c.filters) if (name === 'eq' && a[0] === 'kakao_place_id') rows = rows.filter((r) => r.kakao_place_id === a[1])
    return { data: rows, count: rows.length }
  })
  render(<MemoryRouter initialEntries={['/moderation']}><App client={makeQueryClient()} /></MemoryRouter>)
  await userEvent.click(await screen.findByRole('button', { name: '리뷰' }))
  await screen.findByText('네이버 리뷰')
}

beforeEach(() => {
  fake.reset(); vi.mocked(downloadText).mockClear()
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('리뷰 tab: the overall page', () => {
  it('opens on the reviews of every restaurant, with where each came from, the original half star and "별점 없음"', async () => {
    await openReviews('admin')
    expect(screen.getByLabelText('전체 리뷰')).toBeTruthy()
    expect(screen.getByText('★ 4.5')).toBeTruthy()
    expect(screen.getByText('별점 없음', { selector: 'div' })).toBeTruthy()
    expect(screen.getAllByText('네이버', { selector: 'span' })).toHaveLength(2) // two naver reviews (the filter option is not a badge)
    expect(screen.getByText('레몽 · BAEMIN')).toBeTruthy()
    expect(screen.getByText(/4개 중 4개 표시/)).toBeTruthy()
    expect(screen.getByRole('button', { name: '다시 공개' })).toBeTruthy() // the hidden imported review is moderated like any other
    expect(screen.queryByText(/모두 지우기/)).toBeNull()
  })

  it('shows the overall picture: every review and how many are public, hidden, removed or without stars', async () => {
    await openReviews('admin')
    const stats = within(await screen.findByLabelText('리뷰 현황'))
    expect(stats.getByText('4')).toBeTruthy()
    for (const w of ['공개', '숨김', '삭제됨', '별점 없음']) expect(stats.getByText(new RegExp(w))).toBeTruthy()
    const heads = fake.calls.filter((c) => c.table === 'student_reviews' && c.filters.some((f) => f[0] === 'select' && (f[2] as { head?: boolean } | undefined)?.head))
    expect(heads.some((c) => c.filters.some((f) => f[0] === 'eq' && f[1] === 'moderation_status' && f[2] === 'hidden'))).toBe(true)
    expect(heads.some((c) => c.filters.some((f) => f[0] === 'is' && f[1] === 'rating'))).toBe(true)
  })

  it('names each review\'s restaurant, linking to that restaurant\'s own page; a place with no record shows its id', async () => {
    await openReviews('admin')
    const links = screen.getAllByRole('link', { name: '15번가에비뉴' })
    expect(links).toHaveLength(3)
    expect(links[0].getAttribute('href')).toBe('/moderation/reviews/1046337753')
    expect(screen.getByRole('link', { name: '382170960' }).getAttribute('href')).toBe('/moderation/reviews/382170960')
  })

  it('sorts on the server: newest first by default, oldest, or by stars (reviews without stars last)', async () => {
    await openReviews('admin')
    const orders = () => fake.calls.filter((c) => c.table === 'student_reviews' && cols(c).includes('moderation_reason')).at(-1)!.filters.filter((f) => f[0] === 'order')
    expect(orders().some((f) => f[1] === 'created_at' && (f[2] as { ascending: boolean }).ascending === false)).toBe(true)
    await userEvent.selectOptions(screen.getByLabelText('정렬'), 'old')
    await waitFor(() => expect(orders().some((f) => f[1] === 'created_at' && (f[2] as { ascending: boolean }).ascending === true)).toBe(true))
    await userEvent.selectOptions(screen.getByLabelText('정렬'), 'high')
    await waitFor(() => expect(orders().some((f) => f[1] === 'rating' && JSON.stringify(f[2]) === JSON.stringify({ ascending: false, nullsFirst: false }))).toBe(true))
    await userEvent.selectOptions(screen.getByLabelText('정렬'), 'low')
    await waitFor(() => expect(orders().some((f) => f[1] === 'rating' && JSON.stringify(f[2]) === JSON.stringify({ ascending: true, nullsFirst: false }))).toBe(true))
  })

  it('filters on the server by source, stars, state, a Korean date range and text; 초기화 clears them', async () => {
    await openReviews('admin')
    const has = (name: string, ...args: unknown[]) => fake.calls.some((c) => c.table === 'student_reviews' && c.filters.some((f) => f[0] === name && args.every((a, i) => f[i + 1] === a)))
    await userEvent.selectOptions(screen.getByLabelText('리뷰 출처'), 'naver')
    await waitFor(() => expect(has('eq', 'source', 'naver')).toBe(true))
    await userEvent.selectOptions(screen.getByLabelText('별점'), '5')
    await waitFor(() => expect(has('eq', 'rating', 5)).toBe(true))
    await userEvent.selectOptions(screen.getByLabelText('별점'), 'none')
    await waitFor(() => expect(has('is', 'rating', null)).toBe(true))
    await userEvent.selectOptions(screen.getByLabelText('공개 상태'), 'hidden')
    await waitFor(() => expect(has('eq', 'moderation_status', 'hidden')).toBe(true))
    await userEvent.type(screen.getByLabelText('작성일 시작'), '2026-11-01')
    await waitFor(() => expect(has('gte', 'created_at', '2026-11-01T00:00:00+09:00')).toBe(true))
    await userEvent.type(screen.getByLabelText('작성일 끝'), '2026-11-30')
    await waitFor(() => expect(has('lte', 'created_at', '2026-11-30T23:59:59.999+09:00')).toBe(true))
    await userEvent.type(screen.getByLabelText('리뷰 검색'), '맛집')
    await waitFor(() => expect(has('ilike', 'body', '%맛집%')).toBe(true))
    await userEvent.click(screen.getByRole('button', { name: '초기화' }))
    await waitFor(() => expect((screen.getByLabelText('정렬') as HTMLSelectElement).value).toBe('new'))
    expect((screen.getByLabelText('리뷰 검색') as HTMLInputElement).value).toBe('')
    expect(screen.queryByRole('button', { name: '초기화' })).toBeNull()
  })

  it('says so when the filters match nothing', async () => {
    await openReviews('admin')
    fake.respond('student_reviews:select', (c: C) => cols(c).startsWith('id,') ? { data: [], count: 0 } : { data: [], count: 4 })
    await userEvent.selectOptions(screen.getByLabelText('별점'), '1')
    await screen.findByText('조건에 맞는 리뷰가 없어요.')
  })

  it('loads more reviews on request (50 at a time)', async () => {
    await openReviews('admin')
    fake.respond('student_reviews:select', (c: C) => cols(c) === 'kakao_place_id' ? { data: [] } : { data: LIST, count: 120 })
    await userEvent.type(screen.getByLabelText('리뷰 검색'), '글')
    await userEvent.click(await screen.findByRole('button', { name: '더 보기' }))
    await waitFor(() => expect(fake.calls.some((c) => c.filters.some((f) => f[0] === 'range' && f[1] === 0 && f[2] === 99))).toBe(true))
  })

  it('a moderator sees the list and the export but not the import button', async () => {
    await openReviews('moderator')
    expect(screen.queryByRole('button', { name: 'CSV 가져오기' })).toBeNull()
    expect(screen.getByRole('button', { name: 'CSV 내보내기' })).toBeTruthy()
  })
})

describe('리뷰 tab: one restaurant has its own page', () => {
  it('clicking a restaurant in the list opens its page: only its reviews, its own CSV tools, and a way back', async () => {
    await openReviews('admin')
    await userEvent.click(screen.getAllByRole('link', { name: '15번가에비뉴' })[0])
    expect(await screen.findByText('이 식당의 리뷰 CSV')).toBeTruthy()
    expect(screen.getByRole('heading', { name: '15번가에비뉴' })).toBeTruthy()
    expect(screen.getByText(/카카오 장소 ID 1046337753/)).toBeTruthy()
    await waitFor(() => expect(screen.getByText(/3개 중 3개 표시/)).toBeTruthy())
    expect(screen.queryByText('배달 리뷰')).toBeNull() // another restaurant's review
    expect(screen.queryByLabelText('전체 리뷰')).toBeNull()
    expect(fake.calls.some((c) => c.table === 'student_reviews' && c.filters.some((f) => f[0] === 'eq' && f[1] === 'kakao_place_id' && f[2] === '1046337753'))).toBe(true)
    expect(screen.getByRole('link', { name: '식당 정보 열기' }).getAttribute('href')).toBe('/restaurants/r1')
    // its own export is only its reviews
    await userEvent.click(screen.getByRole('button', { name: 'CSV 내보내기' }))
    await waitFor(() => expect(downloadText).toHaveBeenCalled())
    expect(vi.mocked(downloadText).mock.calls[0][0]).toMatch(/^reviews-1046337753-/)
    // back: the overall reviews again, not the reports
    await userEvent.click(screen.getByRole('link', { name: '전체 리뷰' }))
    expect(await screen.findByLabelText('전체 리뷰')).toBeTruthy()
  })

  it('a place with no restaurant record still opens, and says the reviews are kept', async () => {
    await openReviews('admin')
    await userEvent.click(screen.getByRole('link', { name: '382170960' }))
    expect(await screen.findByText(/이 장소는 아직 식당 정보에 없어요/)).toBeTruthy()
    expect(screen.queryByRole('link', { name: '식당 정보 열기' })).toBeNull()
  })

  it('식당별 보기: the restaurants with their review counts; picking one opens its page', async () => {
    await openReviews('admin')
    await userEvent.click(screen.getByRole('button', { name: '식당별 보기' }))
    const list = within(await screen.findByRole('group', { name: '식당 목록' }))
    expect(await list.findByText('리뷰 3개')).toBeTruthy() // 15번가에비뉴: 3 of the 4 reviews
    expect(list.getByText('리뷰 1개')).toBeTruthy() // 배달집
    expect(list.getAllByText('리뷰 없음')).toHaveLength(1) // 1구역
    await userEvent.type(screen.getByLabelText('식당 검색'), '배달')
    expect(list.queryByRole('button', { name: /15번가에비뉴/ })).toBeNull()
    await userEvent.click(list.getByRole('button', { name: /배달집/ }))
    expect(await screen.findByText(/카카오 장소 ID 382170960/)).toBeTruthy()
  })

  it('a restaurant without a Kakao place id says its reviews cannot be loaded, and stays on the list', async () => {
    await openReviews('admin')
    await userEvent.click(screen.getByRole('button', { name: '식당별 보기' }))
    await userEvent.click(await within(await screen.findByRole('group', { name: '식당 목록' })).findByRole('button', { name: /1구역/ }))
    expect(await screen.findByText(/카카오 장소 ID가 없는 식당은 리뷰를 불러올 수 없어요/)).toBeTruthy()
    expect(screen.queryByText('이 식당의 리뷰 CSV')).toBeNull()
  })
})
