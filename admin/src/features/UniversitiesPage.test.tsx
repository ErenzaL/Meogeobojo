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

const uni = (over: Record<string, unknown> = {}) => ({ id: 'u1', name_ko: '순천향대학교', name_en: null, city: '아산', address: '충남 아산', latitude: 36.77, longitude: 126.93, search_radius_m: 1500, is_active: true, ...over })
const snap = (over: Record<string, unknown> = {}) => { const { id: _i, ...s } = uni(over); void _i; return s }
const STATE = (over: Record<string, unknown> = {}) => ({ live: snap(), live_version: 1, last_published: null, draft: null, jobs: [], ...over })
async function openPage(rows: unknown[], state: unknown = STATE()) {
  fake.signInAs('admin')
  fake.respond('universities:select', { data: rows })
  fake.respond('rpc:cms_state', { data: state })
  fake.respond('rpc:cms_save_draft', { data: { revision: 1, base_version: 1, updated_at: '2026-11-10T00:00:00Z' } })
  fake.respond('rpc:cms_overview', { data: [] })
  render(<MemoryRouter initialEntries={['/universities']}><App client={makeQueryClient()} /></MemoryRouter>)
  await screen.findByText('순천향대학교')
}
const noLiveWrites = () => { for (const op of ['insert', 'update', 'upsert', 'delete']) expect(fake.last('universities', op)).toBeUndefined() }

beforeEach(() => {
  fake.reset()
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('대학교 (초안 → 게시)', () => {
  it('saves a campus edit as a DRAFT and never writes the live row', async () => {
    await openPage([uni()])
    await userEvent.click(await screen.findByRole('button', { name: '편집' }))
    const r = await screen.findByLabelText('검색 반경 (m)')
    await userEvent.clear(r); await userEvent.type(r, '2000')
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/앱에는 아직 반영되지 않았어요/)
    const call = fake.rpcs.find((x) => x.name === 'cms_save_draft')!.args as { p_type: string; p_id: string; p_data: Record<string, unknown> }
    expect(call).toMatchObject({ p_type: 'university', p_id: 'u1' })
    expect(call.p_data).toMatchObject({ search_radius_m: 2000, latitude: 36.77, is_active: true })
    noLiveWrites()
  })

  it('refuses an out-of-range coordinate or radius before asking the server', async () => {
    await openPage([uni()])
    await userEvent.click(await screen.findByRole('button', { name: '편집' }))
    const lat = await screen.findByLabelText('위도')
    await userEvent.clear(lat); await userEvent.type(lat, '123')
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    expect(await screen.findByText('위도는 -90 ~ 90 사이여야 해요')).toBeTruthy()
    expect(fake.rpcs.some((x) => x.name === 'cms_save_draft')).toBe(false)
  })

  it('publishes the saved draft through the server', async () => {
    fake.respond('rpc:cms_publish', { data: 2 })
    const draft = { data: snap({ search_radius_m: 2000 }), revision: 1, base_version: 1, created_by: 'u-1', updated_by: 'u-1', created_at: '2026-11-09T00:00:00Z', updated_at: '2026-11-10T01:00:00Z', stale: false, has_changes: true }
    await openPage([uni()], STATE({ draft }))
    await userEvent.click(await screen.findByRole('button', { name: '편집' }))
    await userEvent.click(await screen.findByRole('button', { name: '지금 게시' }))
    const dlg = await screen.findByRole('dialog')
    await userEvent.click(within(dlg).getByRole('button', { name: '지금 게시' }))
    await waitFor(() => expect(fake.rpcs.some((x) => x.name === 'cms_publish')).toBe(true))
    expect(fake.rpcs.find((x) => x.name === 'cms_publish')!.args).toMatchObject({ p_type: 'university', p_id: 'u1', p_expected_revision: 1 })
    noLiveWrites()
  })

  it('showing / hiding a campus in the app is a versioned publication with a reason', async () => {
    fake.respond('rpc:cms_set_visibility', { data: 3 })
    await openPage([uni()])
    await userEvent.click(await screen.findByRole('button', { name: '앱에서 숨기기' }))
    const dlg = await screen.findByRole('dialog')
    await userEvent.type(within(dlg).getByLabelText(/사유/), '방학 중 점검')
    await userEvent.click(within(dlg).getByRole('button', { name: '숨기기' }))
    await waitFor(() => expect(fake.rpcs.some((x) => x.name === 'cms_set_visibility')).toBe(true))
    expect(fake.rpcs.find((x) => x.name === 'cms_set_visibility')!.args).toMatchObject({ p_type: 'university', p_id: 'u1', p_visibility: 'hidden', p_reason: '방학 중 점검' })
    noLiveWrites()
  })

  it('shows draft / scheduled / failed badges per campus', async () => {
    fake.signInAs('admin')
    fake.respond('universities:select', { data: [uni()] })
    fake.respond('rpc:cms_overview', { data: [{ entity_id: 'u1', has_draft: true, draft_updated_at: null, scheduled_at: '2098-12-31T22:00:00Z', failed_jobs: 1, live_version: 1, last_published_at: null }] })
    render(<MemoryRouter initialEntries={['/universities']}><App client={makeQueryClient()} /></MemoryRouter>)
    expect(await screen.findByText('게시되지 않은 수정 있음')).toBeTruthy()
    expect(screen.getByText('예약 2099.01.01 07:00 (KST)')).toBeTruthy()
    expect(screen.getByText('실패 1')).toBeTruthy()
  })
})
