import { QueryClientProvider } from '@tanstack/react-query'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import FIXTURE from './__fixtures__/reviews_sample.csv?raw'
import ReviewCsvTools from './ReviewCsvTools'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})
vi.mock('../menus/MenuCsvTools', () => ({ downloadText: vi.fn() }))
import { downloadText } from '../menus/MenuCsvTools'

type Args = { p_rows: { line: number }[]; p_dry_run: boolean }
const file = (text: string) => new File([text], 'restaurants_reviews.csv', { type: 'text/csv' })
const renderIt = (canImport = true, placeId?: string) => render(<QueryClientProvider client={makeQueryClient()}><ReviewCsvTools canImport={canImport} placeId={placeId} /></QueryClientProvider>)

beforeEach(() => {
  // jsdom has no <dialog>.showModal: without it the dialog stays closed (and hidden)
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
  fake.reset(); fake.signInAs('admin'); vi.mocked(downloadText).mockClear()
  fake.respond('restaurant_overrides:select', { data: [{ kakao_place_id: '1046337753' }] })
  // the server's answer: every row is new
  fake.respond('rpc:admin_import_reviews', (a: unknown) => {
    const { p_rows, p_dry_run } = a as Args
    return { data: { total: p_rows.length, new: p_rows.length, existing: 0, duplicate: 0, empty: 0, failed: 0, undated: 0, errors: [], dry_run: p_dry_run } }
  })
})

describe('the review CSV tools', () => {
  it('previews the file like the spreadsheet, asks the server for a dry run, and writes nothing until confirmed', async () => {
    renderIt()
    await userEvent.upload(screen.getByTestId('review-csv-input'), file(FIXTURE))
    const s = await screen.findByLabelText('리뷰 가져오기 미리보기')
    await waitFor(() => expect(s.textContent).toMatch(/서버 확인: 새로 저장 7/))
    expect(s.textContent).toMatch(/전체 10줄/)
    expect(s.textContent).toMatch(/가져올 수 있는 리뷰 7 \(2곳\)/)
    expect(s.textContent).toMatch(/파일 안 중복 1/)
    expect(s.textContent).toMatch(/식당 정보만 있는 줄 1/)
    expect(s.textContent).toMatch(/연도 없는 날짜.*2개/)
    expect(s.textContent).toMatch(/식당 정보에 없는 장소 1곳/)
    expect(s.textContent).toContain('불친절. 1인 2시간이라')
    expect(fake.rpcs.map((r) => (r.args as Args).p_dry_run)).toEqual([true])
    expect(fake.calls.filter((c) => c.op !== 'select')).toHaveLength(0)
  })

  it('saves through admin_import_reviews only (never a direct insert), the duplicate and skipped rows are not sent', async () => {
    renderIt()
    await userEvent.upload(screen.getByTestId('review-csv-input'), file(FIXTURE))
    await userEvent.click(await screen.findByRole('button', { name: '리뷰 7개 저장' }))
    await waitFor(() => expect(screen.getByText(/리뷰 7개를 저장했어요/)).toBeTruthy())
    const real = fake.rpcs.filter((r) => !(r.args as Args).p_dry_run)
    expect(real).toHaveLength(1)
    expect((real[0].args as Args).p_rows.map((r) => r.line)).toEqual([2, 3, 5, 6, 7, 8, 9])
    expect(fake.calls.filter((c) => c.op !== 'select')).toHaveLength(0)
  })

  it('sends a big file in chunks of 500 and tells the admin how many the server already had', async () => {
    fake.respond('rpc:admin_import_reviews', (a: unknown) => {
      const { p_rows } = a as Args
      return { data: { total: p_rows.length, new: p_rows.length - 1, existing: 1, duplicate: 0, empty: 0, failed: 0, undated: 0, errors: [], dry_run: true } }
    })
    const lines = ['kakao_place_id,source,rating,review_text,review_date', ...Array.from({ length: 1200 }, (_, i) => `1,naver,5,글 ${i},`)]
    renderIt()
    await userEvent.upload(screen.getByTestId('review-csv-input'), file(lines.join('\n')))
    const s = await screen.findByLabelText('리뷰 가져오기 미리보기')
    await waitFor(() => expect(s.textContent).toMatch(/서버 확인: 새로 저장 1,197 · 이미 있음 3/))
    expect(fake.rpcs.map((r) => (r.args as Args).p_rows.length)).toEqual([500, 500, 200])
  })

  it('shows what the server refused, by file line, and a file that is not a review file is refused up front', async () => {
    fake.respond('rpc:admin_import_reviews', { data: { total: 7, new: 6, existing: 0, duplicate: 0, empty: 0, failed: 1, undated: 0, errors: [{ line: 6, error: '날짜가 범위를 벗어났어요' }], dry_run: true } })
    renderIt()
    await userEvent.upload(screen.getByTestId('review-csv-input'), file(FIXTURE))
    await screen.findByText(/6줄 \(서버\): 날짜가 범위를 벗어났어요/)
    await userEvent.upload(screen.getByTestId('review-csv-input'), file('name\nA\n'))
    await screen.findByText(/kakao_place_id 열이 없어요/)
  })

  it('a moderator can export but not import; the export is the whole table', async () => {
    fake.respond('student_reviews:select', { data: [{ kakao_place_id: '1', source: 'naver', platform: null, rating: 5, source_rating: 4.5, body: '좋아요', created_at: '2025-12-07T15:00:00Z', source_review_id: null, moderation_status: 'visible' }], count: 1 })
    renderIt(false)
    expect(screen.queryByRole('button', { name: 'CSV 가져오기' })).toBeNull()
    await userEvent.click(screen.getByRole('button', { name: 'CSV 내보내기' }))
    await waitFor(() => expect(downloadText).toHaveBeenCalled())
    const [name, csv] = vi.mocked(downloadText).mock.calls[0]
    expect(name).toMatch(/^reviews-\d{4}-\d{2}-\d{2}\.csv$/)
    expect(csv).toContain('2025-12-08T00:00:00+09:00')
    await screen.findByText(/리뷰 1개를 CSV로 내려받았어요/)
  })

  it('for ONE restaurant: only its lines are sent, the export is only its reviews, and there is no delete button anywhere', async () => {
    fake.respond('student_reviews:select', { data: [{ kakao_place_id: '382170960', source: 'lemong', platform: 'BAEMIN', rating: 5, source_rating: 5, body: '배달 빨라요', created_at: '2026-06-30T03:27:00Z', source_review_id: null, moderation_status: 'visible' }], count: 1 })
    renderIt(true, '382170960')
    expect(screen.getByText('이 식당의 리뷰 CSV')).toBeTruthy()
    expect(screen.queryByText(/모두 지우기/)).toBeNull()
    await userEvent.upload(screen.getByTestId('review-csv-input'), file(FIXTURE))
    const s = await screen.findByLabelText('리뷰 가져오기 미리보기')
    await waitFor(() => expect(s.textContent).toMatch(/서버 확인: 새로 저장 2/))
    expect(s.textContent).toMatch(/다른 식당의 줄 6/)
    expect(fake.rpcs.flatMap((r) => (r.args as Args).p_rows.map((x) => x.line))).toEqual([8, 9])
    await userEvent.click(screen.getByRole('button', { name: 'CSV 내보내기' }))
    await waitFor(() => expect(downloadText).toHaveBeenCalled())
    expect(vi.mocked(downloadText).mock.calls[0][0]).toMatch(/^reviews-382170960-\d{4}-\d{2}-\d{2}\.csv$/)
    expect(fake.calls.some((c) => c.table === 'student_reviews' && c.filters.some((f) => f[0] === 'eq' && f[1] === 'kakao_place_id' && f[2] === '382170960'))).toBe(true)
  })
})
