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

const item = (over: Record<string, unknown> = {}) => ({
  id: 'n1', kind: 'notification', title: '개강 안내', body: '학식 운영 시간이 바뀌어요', image_url: null, link_url: null, kakao_place_id: null, university_id: null, active: true, sort_order: 0, starts_at: null, ends_at: null, updated_at: '2026-11-10T00:00:00Z', ...over,
})
const snap = (over: Record<string, unknown> = {}) => { const { id: _i, kind: _k, updated_at: _u, ...s } = item(over); void _i; void _k; void _u; return s }
const STATE = (over: Record<string, unknown> = {}) => ({ live: snap(), live_version: 1, last_published: null, draft: null, jobs: [], ...over })

type Call = { filters: [string, ...unknown[]][] }
async function open(rows: unknown[] = [item()], path = '/notifications') {
  fake.signInAs('admin')
  fake.respond('app_content:select', { data: rows })
  fake.respond('rpc:cms_state', { data: STATE() })
  fake.respond('rpc:cms_save_draft', { data: { revision: 1, base_version: 1, updated_at: '2026-11-10T00:00:00Z' } })
  fake.respond('rpc:cms_overview', { data: [] })
  render(<MemoryRouter initialEntries={[path]}><App client={makeQueryClient()} /></MemoryRouter>)
}

beforeEach(() => {
  fake.reset()
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('알림 관리', () => {
  it('has its own entry in the sidebar and its own page', async () => {
    await open([])
    const nav = await screen.findByRole('link', { name: '알림' })
    expect(nav.getAttribute('href')).toBe('/notifications')
    expect(await screen.findByRole('heading', { name: '알림' })).toBeTruthy()
    expect(screen.getAllByText(/종 아이콘/).length).toBeGreaterThan(0)
  })

  it('lists only notifications and announcements (the kinds the bell shows), newest change first', async () => {
    await open([item(), item({ id: 'n2', kind: 'announcement', title: '공지 하나' })])
    expect(await screen.findByText('개강 안내')).toBeTruthy()
    expect(screen.getByText('공지 하나')).toBeTruthy()
    const q = [...fake.calls].reverse().find((c) => c.table === 'app_content' && c.op === 'select') as unknown as Call
    expect(q.filters.find((f) => f[0] === 'in')).toEqual(['in', 'kind', ['notification', 'announcement']])
    expect(q.filters.find((f) => f[0] === 'order')).toEqual(['order', 'updated_at', { ascending: false }])
  })

  it('creates a notification of the bell-only kind, switched OFF, and says where it will show', async () => {
    fake.respond('app_content:insert', { data: { id: 'new1' } })
    await open([])
    await screen.findByText(/등록된 알림이 없어요/)
    expect((screen.getByLabelText('종류') as HTMLSelectElement).value).toBe('notification') // the default of this page
    expect(screen.getByText(/종 아이콘\(🔔\) 목록에만 보여요/)).toBeTruthy()
    expect([...(screen.getByLabelText('종류') as HTMLSelectElement).options].map((o) => o.value)).toEqual(['notification', 'announcement'])
    await userEvent.type(screen.getByLabelText('제목'), '새 학기 안내')
    await userEvent.type(screen.getByLabelText('내용'), '개강 첫 주 학식은 운영해요')
    await userEvent.type(screen.getByLabelText('링크 (https)'), 'https://example.org/news')
    await userEvent.click(screen.getByRole('button', { name: '추가' }))
    await screen.findByText(/꺼진 상태로 만들었어요/)
    expect(fake.last('app_content', 'insert')!.payload).toMatchObject({ kind: 'notification', title: '새 학기 안내', body: '개강 첫 주 학식은 운영해요', link_url: 'https://example.org/news', active: false })
  })

  it('a 공지 made here shows in the bell AND on Home (the hint says so)', async () => {
    await open([])
    await screen.findByText(/등록된 알림이 없어요/)
    await userEvent.selectOptions(screen.getByLabelText('종류'), 'announcement')
    expect(screen.getByText(/홈 화면 카드와 종 아이콘/)).toBeTruthy()
  })

  it('validates before creating (title, https link) like the 앱 콘텐츠 page', async () => {
    await open([])
    await screen.findByText(/등록된 알림이 없어요/)
    await userEvent.click(screen.getByRole('button', { name: '추가' }))
    expect(await screen.findByText('제목을 입력해 주세요')).toBeTruthy()
    await userEvent.type(screen.getByLabelText('제목'), 'x')
    await userEvent.type(screen.getByLabelText('링크 (https)'), 'http://nope')
    await userEvent.click(screen.getByRole('button', { name: '추가' }))
    expect(await screen.findByText(/https:\/\/ 로 시작/)).toBeTruthy()
    expect(fake.last('app_content', 'insert')).toBeUndefined()
  })

  it('before the database migration the bell-only kind is refused: the admin is told exactly what to apply and what works meanwhile', async () => {
    fake.respond('app_content:insert', { error: { code: '23514', message: 'new row for relation "app_content" violates check constraint "app_content_kind_check"' } })
    await open([])
    await screen.findByText(/등록된 알림이 없어요/)
    await userEvent.type(screen.getByLabelText('제목'), '새 알림')
    await userEvent.click(screen.getByRole('button', { name: '추가' }))
    const alert = await screen.findByRole('alert')
    expect(alert.textContent).toContain('20261120000100_notification_kind.sql')
    expect(alert.textContent).toContain("'공지'로 만들면")
  })

  it('a refusal for another reason is shown as it is (the migration hint is only for the kind constraint)', async () => {
    fake.respond('app_content:insert', { error: { message: 'permission denied for table app_content' } })
    await open([])
    await screen.findByText(/등록된 알림이 없어요/)
    await userEvent.type(screen.getByLabelText('제목'), '새 알림')
    await userEvent.click(screen.getByRole('button', { name: '추가' }))
    expect((await screen.findByRole('alert')).textContent).toBe('permission denied for table app_content')
  })

  it('publishing and unpublishing go through the existing publishing function, with a reason, and never edit the live row', async () => {
    fake.respond('rpc:cms_set_visibility', { data: 2 })
    await open([item({ active: false })])
    await userEvent.click(await screen.findByRole('button', { name: '바로 게시' }))
    const dlg = await screen.findByRole('dialog', { hidden: true })
    await userEvent.click(within(dlg).getByRole('button', { name: '게시' }))
    expect(fake.rpcs.filter((r) => r.name === 'cms_set_visibility')).toHaveLength(0) // a reason is required
    await userEvent.type(within(dlg).getByLabelText('사유 (필수)'), '개강 안내')
    await userEvent.click(within(dlg).getByRole('button', { name: '게시' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_set_visibility')).toBe(true))
    expect(fake.rpcs.find((r) => r.name === 'cms_set_visibility')!.args).toEqual({ p_type: 'app_content', p_id: 'n1', p_visibility: 'published', p_reason: '개강 안내' })
    for (const op of ['update', 'upsert', 'delete']) expect(fake.last('app_content', op)).toBeUndefined()
  })

  it('editing opens the existing editor (draft, schedule, history) for a notification', async () => {
    await open()
    await userEvent.click(await screen.findByRole('button', { name: '수정' }))
    expect(await screen.findByLabelText('콘텐츠 편집')).toBeTruthy()
    expect(screen.getByRole('heading', { name: '알림 편집' })).toBeTruthy()
  })

  it('moderators cannot reach it (admin only, like 앱 콘텐츠)', async () => {
    fake.signInAs('moderator')
    fake.respond('app_content:select', { data: [] })
    render(<MemoryRouter initialEntries={['/notifications']}><App client={makeQueryClient()} /></MemoryRouter>)
    expect(await screen.findByText(/권한이 없어요/)).toBeTruthy()
    expect(screen.queryByRole('link', { name: '알림' })).toBeNull()
  })
})

describe('앱 콘텐츠 still shows everything', () => {
  it('lists all kinds (no kind filter), offers 알림 as a kind, and keeps its own title', async () => {
    await open([item({ kind: 'banner', id: 'b1', title: '배너 하나' })], '/content')
    expect(await screen.findByText('배너 하나')).toBeTruthy()
    expect(screen.getByRole('heading', { name: '앱 콘텐츠' })).toBeTruthy()
    const q = [...fake.calls].reverse().find((c) => c.table === 'app_content' && c.op === 'select') as unknown as Call
    expect(q.filters.some((f) => f[0] === 'in')).toBe(false)
    expect([...(screen.getByLabelText('종류') as HTMLSelectElement).options].map((o) => o.value)).toEqual(['announcement', 'banner', 'featured', 'notification'])
  })
})
