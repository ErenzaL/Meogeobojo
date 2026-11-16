import { QueryClientProvider } from '@tanstack/react-query'
import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import RecommendationInputs from './RecommendationInputs'
import { buildInputRows, menuStats, summarize, yesNo, type FeatureRow, type MenuLite, type RestaurantLite } from './inputs'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const feat = (id: string, over: Partial<FeatureRow> = {}): FeatureRow => ({ kakao_place_id: id, name_ko: `식당${id}`, open_time: '11:00:00', last_order_time: '20:30:00', break_time: null, no_break_time: true, parking: true, local_currency: false, fast_turnover: null, takeout: true, open_late: false, source: 'synthetic demo dataset', ...over })
const rest = (n: number, vis = 'published'): RestaurantLite => ({ id: `r${n}`, kakao_place_id: String(n), name_ko: `식당${n}`, visibility: vis })
const menu = (rid: string, category: string | null, price: number | null, over: Partial<MenuLite> = {}): MenuLite => ({ restaurant_id: rid, category, price_krw: price, status: 'active', available: true, ...over })

describe('what the recommendation runs on', () => {
  it('menu stats count only active lines; a meal needs a meal category AND a price; the cheapest meal is the minimum', () => {
    const s = menuStats([menu('r1', '식사', 9000), menu('r1', '면류', 7000), menu('r1', '사이드', 1000), menu('r1', null, 5000), menu('r1', '식사', null), menu('r1', '식사', 4000, { status: 'archived' }), menu('r1', '분식', 3000, { available: false })])
    expect(s.get('r1')).toEqual({ active: 6, categorized: 5, meals: 2, cheapestMeal: 7000 })
  })

  it('joins features, restaurants and menus by Kakao id; a stored row with no restaurant is still listed (visibility unknown)', () => {
    const rows = buildInputRows([feat('1'), feat('99', { name_ko: '목록에 없음' })], [rest(1), rest(2)], [menu('r1', '식사', 8000)])
    expect(rows.map((r) => [r.name, r.visibility, r.features?.kakao_place_id ?? null, r.menus.meals])).toEqual([['목록에 없음', null, '99', 0], ['식당1', 'published', '1', 1], ['식당2', 'published', null, 0]])
  })

  it('the summary counts published restaurants only, and "budget ready" means a priced meal line exists', () => {
    const rows = buildInputRows([feat('1'), feat('2', { open_time: null }), feat('3')], [rest(1), rest(2), rest(3, 'draft'), rest(4)], [menu('r1', '식사', 8000), menu('r2', null, 5000), menu('r3', '식사', 8000)])
    expect(summarize(rows)).toEqual({ total: 4, published: 3, withFeatures: 2, withHours: 1, withMenus: 2, budgetReady: 1 })
  })

  it('unknown is shown as 미확인, never as 없음', () => {
    expect([yesNo(true), yesNo(false), yesNo(null), yesNo(undefined)]).toEqual(['있음', '없음', '미확인', '미확인'])
  })
})

describe('the 추천 page table', () => {
  beforeEach(() => {
    fake.reset(); fake.signInAs('admin')
    fake.respond('recommendation_demo_features:select', { data: [feat('1', { parking: true }), feat('2', { parking: false, break_time: '15:00-17:00', no_break_time: false })] })
    fake.respond('restaurant_overrides:select', { data: [rest(1), rest(2), rest(3), rest(4, 'draft')] })
    fake.respond('restaurant_menus:select', { data: [menu('r1', '식사', 8500), menu('r1', '사이드', 1500), menu('r2', null, 6000)] })
  })
  const renderIt = () => render(<QueryClientProvider client={makeQueryClient()}><RecommendationInputs /></QueryClientProvider>)

  it('shows each published restaurant with its hours, amenities, menus and the cheapest meal', async () => {
    renderIt()
    const sum = await screen.findByLabelText('추천 정보 요약')
    expect(sum.textContent).toMatch(/공개 식당3곳/)
    expect(sum.textContent).toMatch(/영업시간·편의 정보가 있는 곳2곳/)
    expect(sum.textContent).toMatch(/예산을 판정할 수 있는 곳1곳/)
    const table = screen.getByRole('table', { name: '추천 입력 정보' })
    const row1 = within(table).getByText('식당1').closest('tr')!
    expect(row1.textContent).toMatch(/11:00 ~ 20:30/)
    expect(row1.textContent).toMatch(/8,500원/)
    expect(row1.textContent).toMatch(/2개/)
    const row2 = within(table).getByText('식당2').closest('tr')!
    expect(row2.textContent).toMatch(/15:00-17:00/)
    expect(row2.textContent).toMatch(/없음/) // no parking
    const row3 = within(table).getByText('식당3').closest('tr')!
    expect(row3.textContent).toMatch(/미확인/) // no stored hours: unknown, not "none"
    expect(table.textContent).not.toContain('식당4') // a draft is hidden by the default filter
  })

  it('filters by status, by budget readiness and by name', async () => {
    renderIt()
    await screen.findByLabelText('추천 정보 요약')
    await userEvent.selectOptions(screen.getByLabelText('공개 상태 보기'), 'draft')
    expect(screen.getByRole('table', { name: '추천 입력 정보' }).textContent).toContain('식당4')
    await userEvent.selectOptions(screen.getByLabelText('공개 상태 보기'), 'published')
    await userEvent.selectOptions(screen.getByLabelText('예산 판정 보기'), 'ready')
    let t = screen.getByRole('table', { name: '추천 입력 정보' }).textContent!
    expect(t).toContain('식당1'); expect(t).not.toContain('식당2')
    await userEvent.selectOptions(screen.getByLabelText('예산 판정 보기'), '')
    await userEvent.type(screen.getByLabelText('추천 정보 검색'), '식당3')
    t = screen.getByRole('table', { name: '추천 입력 정보' }).textContent!
    expect(t).toContain('식당3'); expect(t).not.toContain('식당1')
  })

  it('is read-only: it writes nothing', async () => {
    renderIt()
    await screen.findByLabelText('추천 정보 요약')
    expect(fake.calls.filter((c) => c.op !== 'select')).toHaveLength(0)
    expect(fake.rpcs).toHaveLength(0)
  })

  it('a missing feature table does not break the page: the restaurants and menus still show', async () => {
    fake.respond('recommendation_demo_features:select', { data: null, error: { message: 'relation does not exist' } })
    renderIt()
    const sum = await screen.findByLabelText('추천 정보 요약')
    expect(sum.textContent).toMatch(/공개 식당3곳/)
    expect(sum.textContent).toMatch(/영업시간·편의 정보가 있는 곳0곳/)
  })
})
