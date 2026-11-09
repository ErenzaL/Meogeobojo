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

describe('restaurant editing', () => {
  const row = { id: 'r1', name_ko: '국수집', kakao_place_id: 'k1', description: '옛 설명', visibility: 'published', price_min_krw: 8000, dining_purposes: [] }

  it('validates, asks for confirmation, then writes the change to the database', async () => {
    fake.signInAs('admin')
    fake.respond('restaurant_overrides:select', { data: [row] })
    fake.respond('restaurant_overrides:update', { data: null })
    fake.respond('universities:select', { data: [] })
    open('/restaurants/r1')
    const desc = await screen.findByLabelText('설명')
    await waitFor(() => expect(desc).toHaveValue('옛 설명'))

    const user = userEvent.setup()
    await user.clear(desc)
    await user.type(desc, '새 설명입니다')
    await user.click(screen.getByRole('button', { name: '저장' }))
    // important change: confirmation first, nothing written yet
    expect(await screen.findByText('변경 사항을 저장할까요?')).toBeInTheDocument()
    expect(fake.last('restaurant_overrides', 'update')).toBeUndefined()

    await user.click(within(screen.getByRole('dialog', { hidden: true })).getByRole('button', { name: '저장' }))
    await waitFor(() => expect(fake.last('restaurant_overrides', 'update')).toBeDefined())
    const upd = fake.last('restaurant_overrides', 'update')!
    expect(upd.payload).toMatchObject({ description: '새 설명입니다', name_ko: '국수집', kakao_place_id: 'k1' })
    expect(upd.filters).toContainEqual(['eq', 'id', 'r1'])
    expect(await screen.findByText('저장했어요.')).toBeInTheDocument()
  })

  it('shows field errors and does not open the confirmation for invalid input', async () => {
    fake.signInAs('admin')
    fake.respond('restaurant_overrides:select', { data: [row] })
    open('/restaurants/new')
    const user = userEvent.setup()
    await user.click(await screen.findByRole('button', { name: '저장' }))
    expect(await screen.findByText('이름을 입력해 주세요')).toBeInTheDocument()
    expect(screen.queryByText('식당을 추가할까요?')).not.toBeInTheDocument()
  })

  it('explains a duplicate Kakao place id', async () => {
    fake.signInAs('admin')
    fake.respond('restaurant_overrides:select', { data: [row] })
    fake.respond('restaurant_overrides:insert', { data: null, error: { code: '23505', message: 'duplicate key' } })
    open('/restaurants/new')
    const user = userEvent.setup()
    await user.type(await screen.findByLabelText('이름 (한국어)'), '중복식당')
    await user.type(screen.getByLabelText('카카오 장소 ID'), 'k1')
    await user.click(screen.getByRole('button', { name: '저장' }))
    await user.click(within(await screen.findByRole('dialog', { hidden: true })).getByRole('button', { name: '저장' }))
    expect(await screen.findByText('이미 등록된 카카오 장소 ID예요. 기존 식당을 편집해 주세요.')).toBeInTheDocument()
  })
})
