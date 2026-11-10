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
  id: 'c1', kind: 'announcement', title: '개강 공지', body: '내용', image_url: null, link_url: null, kakao_place_id: null, university_id: null, active: true, sort_order: 0, starts_at: null, ends_at: null, ...over,
})
const snap = (over: Record<string, unknown> = {}) => { const { id: _i, kind: _k, ...s } = item(over); void _i; void _k; return s }
const STATE = (over: Record<string, unknown> = {}, live: Record<string, unknown> = {}) => ({ live: snap(live), live_version: 1, last_published: null, draft: null, jobs: [], ...over })

async function openPage(rows: unknown[], state: unknown = STATE()) {
  fake.signInAs('admin')
  fake.respond('app_content:select', { data: rows })
  fake.respond('rpc:cms_state', { data: state })
  fake.respond('rpc:cms_save_draft', { data: { revision: 1, base_version: 1, updated_at: '2026-11-10T00:00:00Z' } })
  fake.respond('rpc:cms_overview', { data: [] })
  render(<MemoryRouter initialEntries={['/content']}><App client={makeQueryClient()} /></MemoryRouter>)
  await screen.findByText(rows.length ? (rows[0] as { title: string }).title : '등록된 콘텐츠가 없어요.')
}
const noLiveWrites = () => { for (const op of ['update', 'upsert', 'delete']) expect(fake.last('app_content', op)).toBeUndefined() }

beforeEach(() => {
  fake.reset()
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('앱 콘텐츠 (초안 → 게시)', () => {
  it('creates a new item switched OFF', async () => {
    fake.respond('app_content:insert', { data: { id: 'new1' } })
    await openPage([])
    await userEvent.type(screen.getByLabelText('제목'), '새 공지')
    await userEvent.click(screen.getByRole('button', { name: '추가' }))
    await screen.findByText(/꺼진 상태로 만들었어요/)
    expect(fake.last('app_content', 'insert')!.payload).toMatchObject({ kind: 'announcement', title: '새 공지', active: false })
  })

  it('validates before creating: title, https link, featured place id', async () => {
    await openPage([])
    await userEvent.click(screen.getByRole('button', { name: '추가' }))
    expect(await screen.findByText('제목을 입력해 주세요')).toBeTruthy()
    await userEvent.type(screen.getByLabelText('제목'), 'x')
    await userEvent.type(screen.getByLabelText('링크 (https)'), 'http://nope')
    await userEvent.click(screen.getByRole('button', { name: '추가' }))
    expect(await screen.findByText(/https:\/\/ 로 시작/)).toBeTruthy()
    await userEvent.clear(screen.getByLabelText('링크 (https)'))
    await userEvent.selectOptions(screen.getByLabelText('종류'), 'featured')
    await userEvent.click(screen.getByRole('button', { name: '추가' }))
    expect(await screen.findByText(/카카오 장소 ID가 필요/)).toBeTruthy()
    expect(fake.last('app_content', 'insert')).toBeUndefined()
  })

  it('saving the editor stores a DRAFT; the live content is not written', async () => {
    await openPage([item()])
    await userEvent.click(await screen.findByRole('button', { name: '수정' }))
    const title = await screen.findByLabelText('제목', { selector: '#ce_t' })
    await userEvent.clear(title); await userEvent.type(title, '새 제목')
    await userEvent.click(screen.getByRole('button', { name: '초안 저장' }))
    await screen.findByText(/앱에는 아직 반영되지 않았어요/)
    const call = fake.rpcs.find((r) => r.name === 'cms_save_draft')!.args as { p_type: string; p_id: string; p_data: Record<string, unknown>; p_expected_revision: number }
    expect(call).toMatchObject({ p_type: 'app_content', p_id: 'c1', p_expected_revision: 0 })
    expect(call.p_data).toMatchObject({ title: '새 제목', body: '내용', active: true, starts_at: null, ends_at: null })
    noLiveWrites()
  })

  it('schedules a saved draft for a Seoul time with an optional end', async () => {
    fake.respond('rpc:cms_schedule', { data: 5 })
    const draft = { data: snap({ title: '예약 공지' }), revision: 1, base_version: 1, created_by: 'u-1', updated_by: 'u-1', created_at: '2026-11-09T00:00:00Z', updated_at: '2026-11-10T01:00:00Z', stale: false, has_changes: true }
    await openPage([item()], STATE({ draft }))
    await userEvent.click(await screen.findByRole('button', { name: '수정' }))
    await userEvent.click(await screen.findByRole('button', { name: '예약 게시' }))
    const dlg = await screen.findByRole('dialog', { name: '예약 게시' })
    await userEvent.type(within(dlg).getByLabelText('게시 날짜'), '2099-01-01')
    await userEvent.clear(within(dlg).getByLabelText('게시 시간')); await userEvent.type(within(dlg).getByLabelText('게시 시간'), '07:00')
    await userEvent.click(within(dlg).getByRole('button', { name: '예약하기' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_schedule')).toBe(true))
    expect(fake.rpcs.find((r) => r.name === 'cms_schedule')!.args).toMatchObject({ p_type: 'app_content', p_id: 'c1', p_run_at: '2098-12-31T22:00:00.000Z' })
  })

  it('cancels a scheduled publication and publishes a draft now', async () => {
    fake.respond('rpc:cms_cancel_job', { data: null })
    const job = { id: 7, entity_type: 'app_content', entity_id: 'c1', action: 'publish', base_version: 1, run_at: '2098-12-31T22:00:00Z', unpublish_at: null, status: 'scheduled', reason: null, created_by: 'u-1', created_at: '2026-11-10T00:00:00Z', attempts: 0, last_error: null, executed_at: null, published_version: null, parent_job_id: null }
    const draft = { data: snap({ title: '예약 공지' }), revision: 1, base_version: 1, created_by: 'u-1', updated_by: 'u-1', created_at: '2026-11-09T00:00:00Z', updated_at: '2026-11-10T01:00:00Z', stale: false, has_changes: true }
    await openPage([item()], STATE({ draft, jobs: [job] }))
    await userEvent.click(await screen.findByRole('button', { name: '수정' }))
    await userEvent.click(await screen.findByRole('button', { name: '예약 취소' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_cancel_job')).toBe(true))
    expect(fake.rpcs.find((r) => r.name === 'cms_cancel_job')!.args).toMatchObject({ p_job: 7 })
  })

  it('quick publish / take down go through the audited, versioned server call with a reason', async () => {
    fake.respond('rpc:cms_set_visibility', { data: 3 })
    await openPage([item({ id: 'off', title: '꺼진 공지', active: false }), item({ id: 'on', title: '켜진 공지' })])
    await userEvent.click(await screen.findByRole('button', { name: '바로 게시' }))
    const dlg = await screen.findByRole('dialog')
    await userEvent.type(within(dlg).getByLabelText(/사유/), '개강')
    await userEvent.click(within(dlg).getByRole('button', { name: '게시' }))
    await waitFor(() => expect(fake.rpcs.filter((r) => r.name === 'cms_set_visibility')).toHaveLength(1))
    expect(fake.rpcs.find((r) => r.name === 'cms_set_visibility')!.args).toMatchObject({ p_type: 'app_content', p_id: 'off', p_visibility: 'published', p_reason: '개강' })
    await userEvent.click(screen.getByRole('button', { name: '내리기' }))
    const dlg2 = await screen.findByRole('dialog')
    await userEvent.type(within(dlg2).getByLabelText(/사유/), '종료')
    await userEvent.click(within(dlg2).getByRole('button', { name: '내리기' }))
    await waitFor(() => expect(fake.rpcs.filter((r) => r.name === 'cms_set_visibility')).toHaveLength(2))
    expect(fake.rpcs.filter((r) => r.name === 'cms_set_visibility')[1].args).toMatchObject({ p_id: 'on', p_visibility: 'hidden' })
    noLiveWrites()
  })

  it('only an item that is switched off can be deleted', async () => {
    await openPage([item({ id: 'off', title: '꺼진 공지', active: false }), item({ id: 'on', title: '켜진 공지' })])
    const del = await screen.findAllByRole('button', { name: '삭제' })
    expect(del.map((b) => (b as HTMLButtonElement).disabled).sort()).toEqual([false, true])
    await userEvent.click(del.find((b) => !(b as HTMLButtonElement).disabled)!)
    await userEvent.click(screen.getAllByRole('button', { name: '삭제' }).at(-1)!)
    await waitFor(() => expect(fake.last('app_content', 'delete')).toBeTruthy())
  })

  it('shows unpublished changes, schedules and failures per item', async () => {
    fake.respond('rpc:cms_overview', { data: [{ entity_id: 'c1', has_draft: true, draft_updated_at: null, scheduled_at: '2098-12-31T22:00:00Z', failed_jobs: 2, live_version: 1, last_published_at: null }] })
    fake.signInAs('admin')
    fake.respond('app_content:select', { data: [item()] })
    render(<MemoryRouter initialEntries={['/content']}><App client={makeQueryClient()} /></MemoryRouter>)
    expect(await screen.findByText('게시되지 않은 수정 있음')).toBeTruthy()
    expect(screen.getByText('예약 2099.01.01 07:00 (KST)')).toBeTruthy()
    expect(screen.getByText('실패 2')).toBeTruthy()
  })
})
