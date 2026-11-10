import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from './App'
import { fake } from './test/fakeSupabase'

vi.mock('@/lib/supabase', async () => {
  const m = await import('./test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const open = (path: string) =>
  render(<MemoryRouter initialEntries={[path]}><App client={makeQueryClient()} /></MemoryRouter>)

beforeEach(() => {
  fake.reset()
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('route protection', () => {
  it('sends a signed-out visitor to the login page', async () => {
    open('/restaurants')
    expect(await screen.findByText('관리자 계정으로 로그인해 주세요.')).toBeInTheDocument()
  })

  it('signed in WITHOUT a role in the database is denied (no admin UI)', async () => {
    fake.signInAs(null)
    open('/restaurants')
    expect(await screen.findByText('접근 권한이 없어요')).toBeInTheDocument()
    expect(screen.queryByText('식당 추가')).not.toBeInTheDocument()
  })

  it('a moderator sees moderation but is blocked from restaurant management', async () => {
    fake.signInAs('moderator')
    open('/restaurants')
    expect(await screen.findByText('이 페이지를 볼 권한이 없어요.')).toBeInTheDocument()
    const nav = screen.getByRole('navigation')
    expect(within(nav).getByText('리뷰·신고')).toBeInTheDocument()
    expect(within(nav).queryByText('식당')).not.toBeInTheDocument()
  })

  it('an admin reaches restaurant management, but not role management', async () => {
    fake.signInAs('admin')
    fake.respond('restaurant_overrides:select', { data: [{ id: 'r1', name_ko: '국수집', kakao_place_id: 'k1', category: '한식', visibility: 'published', updated_at: '2026-11-09T00:00:00Z', description: null }], count: 1 })
    open('/restaurants')
    expect(await screen.findByText('국수집')).toBeInTheDocument()
    expect(screen.getByText('식당 추가')).toBeInTheDocument()
    expect(fake.calls.some((c) => c.table === 'admin_roles' && c.op === 'select')).toBe(true)
  })

  it('only a super admin sees the role manager', async () => {
    fake.signInAs('admin')
    open('/settings')
    await screen.findByText('내 역할:')
    expect(screen.queryByText('관리자 역할 (최고 관리자 전용)')).not.toBeInTheDocument()
  })
})

const LIVE = { name_ko: '국수집', name_en: null, category: null, address: null, latitude: null, longitude: null, phone: null, description: '옛 설명', opening_hours: {}, break_time: null, last_order_time: null, business_status: null, price_min_krw: 8000, price_max_krw: null, avg_cost_krw: null, dining_purposes: [], visibility: 'published', featured: false, display_order: null, university_ids: [] }
const STATE = { live: LIVE, live_version: 2, last_published: null, draft: null, jobs: [] }

describe('restaurant editing (draft, not live)', () => {
  const row = { id: 'r1', name_ko: '국수집', kakao_place_id: 'k1', image_url: null }

  it('saves edits as a DRAFT: the live restaurant row is never written', async () => {
    fake.signInAs('admin')
    fake.respond('restaurant_overrides:select', { data: [row] })
    fake.respond('rpc:cms_state', { data: STATE })
    fake.respond('rpc:cms_save_draft', { data: { revision: 1, base_version: 2, updated_at: '2026-11-10T01:00:00Z' } })
    fake.respond('universities:select', { data: [] })
    open('/restaurants/r1')
    const desc = await screen.findByLabelText('설명')
    await waitFor(() => expect(desc).toHaveValue('옛 설명'))

    const user = userEvent.setup()
    await user.clear(desc)
    await user.type(desc, '새 설명입니다')
    await user.click(screen.getByRole('button', { name: '초안 저장' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_save_draft')).toBe(true))
    const call = fake.rpcs.find((r) => r.name === 'cms_save_draft')!.args as { p_type: string; p_id: string; p_data: Record<string, unknown>; p_expected_revision: number }
    expect(call).toMatchObject({ p_type: 'restaurant', p_id: 'r1', p_expected_revision: 0 })
    expect(call.p_data).toMatchObject({ description: '새 설명입니다', name_ko: '국수집', visibility: 'published' })
    expect(call.p_data).not.toHaveProperty('kakao_place_id') // identity is never part of a draft
    expect(call.p_data).not.toHaveProperty('image_url') // the cover is published from 사진 관리
    expect(fake.last('restaurant_overrides', 'update')).toBeUndefined() // the LIVE row is untouched
    expect(await screen.findByText(/초안을 저장했어요. 앱에는 아직 보이지 않아요/)).toBeInTheDocument()
  })

  it('a new restaurant is created as a draft row and then opened for editing', async () => {
    fake.signInAs('admin')
    fake.respond('restaurant_overrides:insert', { data: [{ id: 'new1' }] })
    fake.respond('universities:select', { data: [] })
    open('/restaurants/new')
    const user = userEvent.setup()
    expect(await screen.findByLabelText('공개 상태')).toBeDisabled() // new ones always start as drafts
    await user.type(screen.getByLabelText('이름 (한국어)'), '새 식당')
    await user.click(screen.getByRole('button', { name: '초안으로 만들기' }))
    await waitFor(() => expect(fake.last('restaurant_overrides', 'insert')).toBeDefined())
    expect(fake.last('restaurant_overrides', 'insert')!.payload).toMatchObject({ name_ko: '새 식당', visibility: 'draft', featured: false })
  })

  it('shows field errors and creates nothing for invalid input', async () => {
    fake.signInAs('admin')
    fake.respond('universities:select', { data: [] })
    open('/restaurants/new')
    const user = userEvent.setup()
    await user.click(await screen.findByRole('button', { name: '초안으로 만들기' }))
    expect(await screen.findByText('이름을 입력해 주세요')).toBeInTheDocument()
    expect(fake.last('restaurant_overrides', 'insert')).toBeUndefined()
  })

  it('explains a duplicate Kakao place id', async () => {
    fake.signInAs('admin')
    fake.respond('restaurant_overrides:insert', { data: null, error: { code: '23505', message: 'duplicate key' } })
    fake.respond('universities:select', { data: [] })
    open('/restaurants/new')
    const user = userEvent.setup()
    await user.type(await screen.findByLabelText('이름 (한국어)'), '중복식당')
    await user.type(screen.getByLabelText('카카오 장소 ID'), 'k1')
    await user.click(screen.getByRole('button', { name: '초안으로 만들기' }))
    expect(await screen.findByText('이미 등록된 카카오 장소 ID예요. 기존 식당을 편집해 주세요.')).toBeInTheDocument()
  })
})

describe('recommendation monitoring', () => {
  it('says plainly when no telemetry exists (no invented numbers)', async () => {
    fake.signInAs('admin')
    fake.respond('rpc:admin_recommendation_stats', { data: [] })
    open('/recommendations')
    expect(await screen.findByText('아직 기록된 추천 요청이 없어요.')).toBeInTheDocument()
  })
})
