import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { conditionChips } from '@/features/ChatHistoryPage'
import { fake } from '@/test/fakeSupabase'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const turn = (over: Record<string, unknown> = {}) => ({
  id: 10, created_at: '2026-11-25T03:00:00Z', user_id: 'u1', nickname: '국밥러', client_id: 'c8000000-0000-4000-8000-00000000c001', language: 'ko',
  question: '8000원 이하 국밥 추천해줘', intent: 'search',
  prefs: { hard: { max_price_krw: 8000, dish_keywords: ['국밥'], cuisines: ['korean'], max_walk_minutes: 10, open_now: true, avoid_spicy: false }, soft: { cheap: true, dish_keywords: [] } },
  outcome: 'answered', ai_status: 'ok', reply: '든든 국밥의 순대국밥(8,000원)이 도보 4분으로 제일 잘 맞아요.',
  restaurants: [{ id: '111', name: '든든 국밥', reason: '순대국밥 8,000원' }, { id: '222', name: '차이나 하우스' }], failure: null, notes: [], ...over,
})
const STATS = { turns: 12, askers: 5, signed_in_turns: 4, answered: 8, no_result: 2, chitchat: 1, errors: 1, ai_issues: 3 }

type Args = { p_limit: number; p_before: number | null; p_days: number; p_search: string | null; p_outcome: string | null; p_language: string | null; p_only_users: boolean }
const turnCalls = () => fake.rpcs.filter((r) => r.name === 'admin_chat_turns').map((r) => r.args as Args)

function open(rows: unknown[] | ((a: Args) => unknown[]) = [turn()], role: 'admin' | 'moderator' = 'admin', path = '/chat-history') {
  fake.signInAs(role)
  fake.respond('rpc:admin_chat_stats', { data: [STATS] })
  fake.respond('rpc:admin_chat_turns', ((a: Args) => ({ data: typeof rows === 'function' ? rows(a) : rows })) as never)
  fake.respond('rpc:cms_overview', { data: [] })
  render(<MemoryRouter initialEntries={[path]}><App client={makeQueryClient()} /></MemoryRouter>)
}

beforeEach(() => fake.reset())

describe('챗봇 기록', () => {
  it('has its own entry in the sidebar for admins and shows the question, how it was understood and the answer', async () => {
    open()
    const nav = await screen.findByRole('link', { name: '챗봇 기록' })
    expect(nav.getAttribute('href')).toBe('/chat-history')
    expect(await screen.findByRole('heading', { name: '챗봇 기록' })).toBeTruthy()
    const card = await screen.findByTestId('chat-turn')
    const c = within(card)
    expect(c.getByText('8000원 이하 국밥 추천해줘')).toBeTruthy()
    expect(c.getByText('국밥러')).toBeTruthy()
    expect(c.getByText('추천함')).toBeTruthy()
    expect(c.getByText('AI 정상')).toBeTruthy()
    // understood conditions, in words
    for (const chip of ['메뉴: 국밥', '한식', '8,000원 이하', '도보 10분 이내', '지금 영업 중', '저렴하게']) expect(c.getByText(chip)).toBeTruthy()
    expect(c.getByText(/새 추천 요청/)).toBeTruthy()
    // the answer and the restaurants in the order shown
    expect(c.getByText('든든 국밥의 순대국밥(8,000원)이 도보 4분으로 제일 잘 맞아요.')).toBeTruthy()
    expect(c.getByText('추천한 식당 2곳')).toBeTruthy()
    const items = c.getAllByRole('listitem').map((li) => li.textContent)
    expect(items[0]).toContain('든든 국밥')
    expect(items[0]).toContain('순대국밥 8,000원')
    expect(items[1]).toContain('차이나 하우스')
  })

  it('shows the totals and warns that this is text people typed', async () => {
    open()
    expect(await screen.findByText('질문 수')).toBeTruthy()
    expect(screen.getByText('12')).toBeTruthy()
    expect(screen.getByText('로그인 사용자 4건')).toBeTruthy()
    expect(screen.getByText('맞는 곳을 못 찾음')).toBeTruthy()
    expect(screen.getByText(/사용자가 직접 입력한 글이에요/)).toBeTruthy()
    expect(screen.getByText(/이메일과 IP 주소는 저장하지 않아요/)).toBeTruthy()
  })

  it('a guest shows as 게스트 with only the short device number; app-written lines and errors are put into words', async () => {
    open([
      turn({ id: 3, user_id: null, nickname: null, outcome: 'no_result', ai_status: 'busy', reply: null, restaurants: [], notes: ['aiBusy', 'noneRaiseBudget'], prefs: null, intent: 'search' }),
      turn({ id: 2, user_id: null, nickname: null, outcome: 'error', ai_status: 'down', reply: null, restaurants: [], notes: ['rateLimited'], failure: 'rateLimited', prefs: null, intent: null, language: 'en', question: 'hello' }),
    ])
    const cards = await screen.findAllByTestId('chat-turn')
    const a = within(cards[0])
    expect(a.getByText('게스트')).toBeTruthy()
    expect(a.getByText('#c8000000')).toBeTruthy()
    expect(a.getByText('맞는 곳 없음')).toBeTruthy()
    expect(a.getByText('AI 문장 실패 · 앱이 답함')).toBeTruthy()
    expect(a.getByText(/AI가 바빠 앱이 직접 답함 \/ 맞는 곳 없음 · 예산을 올려 보자고 제안/)).toBeTruthy()
    expect(a.getByText('특별한 조건 없이 물어봤어요.')).toBeTruthy()
    const b = within(cards[1])
    expect(b.getByText('오류')).toBeTruthy()
    expect(b.getByText('AI 응답 없음 · 앱이 답함')).toBeTruthy()
    expect(b.getByText('English')).toBeTruthy()
    expect(b.getByText(/오류 종류: 요청이 너무 많다고 안내/)).toBeTruthy()
  })

  it('asks the database for the newest 50 of the last 7 days, and sends search, result, language and signed-in filters', async () => {
    const user = userEvent.setup()
    open()
    await screen.findByTestId('chat-turn')
    expect(turnCalls()[0]).toEqual({ p_limit: 50, p_before: null, p_days: 7, p_search: null, p_outcome: null, p_language: null, p_only_users: false })

    await user.type(screen.getByLabelText('질문 검색'), '  국밥 ')
    await user.click(screen.getByRole('button', { name: '검색' }))
    await waitFor(() => expect(turnCalls().at(-1)?.p_search).toBe('국밥'))

    await user.selectOptions(screen.getByLabelText('결과'), 'no_result')
    await waitFor(() => expect(turnCalls().at(-1)?.p_outcome).toBe('no_result'))
    await user.selectOptions(screen.getByLabelText('언어'), 'zh-Hans')
    await waitFor(() => expect(turnCalls().at(-1)?.p_language).toBe('zh-Hans'))
    await user.click(screen.getByLabelText('로그인 사용자만'))
    await waitFor(() => expect(turnCalls().at(-1)?.p_only_users).toBe(true))
    await user.selectOptions(screen.getByLabelText('기간'), '90')
    await waitFor(() => expect(turnCalls().at(-1)?.p_days).toBe(90))
    expect(fake.rpcs.filter((r) => r.name === 'admin_chat_stats').at(-1)?.args).toEqual({ p_days: 90 })

    await user.click(screen.getByRole('button', { name: '조건 지우기' }))
    await waitFor(() => expect(turnCalls().at(-1)).toMatchObject({ p_search: null, p_outcome: null, p_language: null, p_only_users: false }))
  })

  it('"더 보기" continues after the last row instead of reloading the first page', async () => {
    const user = userEvent.setup()
    const page1 = Array.from({ length: 50 }, (_, i) => turn({ id: 200 - i, question: `질문 ${200 - i}` }))
    open((a) => (a.p_before == null ? page1 : [turn({ id: 5, question: '마지막 질문' })]))
    expect((await screen.findAllByTestId('chat-turn')).length).toBe(50)
    await user.click(screen.getByRole('button', { name: '더 보기' }))
    expect(await screen.findByText('마지막 질문')).toBeTruthy()
    expect(turnCalls().at(-1)?.p_before).toBe(151)
    expect(screen.getAllByTestId('chat-turn').length).toBe(51)
    expect(screen.queryByRole('button', { name: '더 보기' })).toBeNull()
  })

  it('no questions yet: says so plainly; with filters it says nothing matched', async () => {
    const user = userEvent.setup()
    open([])
    expect(await screen.findByText(/이 기간에 기록된 질문이 없어요/)).toBeTruthy()
    await user.selectOptions(screen.getByLabelText('결과'), 'error')
    expect(await screen.findByText('조건에 맞는 질문이 없어요.')).toBeTruthy()
  })

  it('a moderator has no menu entry and cannot open the page (the database refuses as well)', async () => {
    open([turn()], 'moderator')
    await screen.findByRole('link', { name: '개요' })
    expect(screen.queryByRole('link', { name: '챗봇 기록' })).toBeNull()
    expect(screen.queryByTestId('chat-turn')).toBeNull()
    expect(turnCalls()).toEqual([])
  })

  it('a database error is shown with a retry, not an empty list', async () => {
    fake.signInAs('admin')
    fake.respond('rpc:admin_chat_stats', { data: [STATS] })
    fake.respond('rpc:admin_chat_turns', { error: { message: 'permission denied', code: '42501' } })
    fake.respond('rpc:cms_overview', { data: [] })
    render(<MemoryRouter initialEntries={['/chat-history']}><App client={makeQueryClient()} /></MemoryRouter>)
    expect(await screen.findByRole('button', { name: /다시/ }, { timeout: 4000 })).toBeTruthy()
    expect(screen.queryByText(/이 기간에 기록된 질문이 없어요/)).toBeNull()
  })
})

describe('conditionChips', () => {
  it('turns the stored conditions into words and is empty when nothing was asked', () => {
    expect(conditionChips(null)).toEqual([])
    expect(conditionChips({ hard: {}, soft: {} })).toEqual([])
    expect(conditionChips({ hard: { min_price_krw: 5000, avoid_spicy: true }, soft: { dish_keywords: ['탕'], closer: true, filling: true, group_size: 4 } }))
      .toEqual(['5,000원 이상', '맵지 않게', '어울리는 메뉴: 탕', '가깝게', '든든하게', '4명'])
    expect(conditionChips({ hard: { cuisines: ['unknown-kind'] } })).toEqual(['unknown-kind'])
  })
})
