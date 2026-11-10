import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import { healthChecks } from './PublishingCenter'
import type { CmsHealth } from '@/lib/cmsHealth'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const HEALTH = (over: Partial<CmsHealth> = {}): CmsHealth => ({
  generated_at: '2026-11-10T10:00:00Z',
  cron: { available: true, job_found: true, schedule: '* * * * *', active: true, last_success_at: new Date().toISOString(), recent_runs: [{ status: 'succeeded', start_time: new Date().toISOString(), end_time: null, message: null }] },
  jobs: { scheduled: 1, overdue: 0, running: 0, stuck: 0, failed: 0, next_run_at: '2098-12-31T22:00:00Z', last_executed_at: null },
  realtime: { publication: true, tables: ['app_content'], missing: [] },
  guards: { present: ['a'], missing: [] },
  schema: { cafeteria_status: true, contributions: true },
  drafts: [{ entity_type: 'app_content', entity_id: 'c1', label: '개강 공지', updated_at: '2026-11-10T01:00:00Z', updated_by: 'u-1', stale: false, has_changes: true }],
  scheduled: [{ id: 7, entity_type: 'restaurant', entity_id: 'r1', label: '온기식당', action: 'publish', status: 'scheduled', run_at: '2098-12-31T22:00:00Z', unpublish_at: null, created_by: 'u-1', reason: '아침 메뉴', overdue: false }],
  failed: [], recent: [{ entity_type: 'university', entity_id: 'u1', label: '순천향대학교', version: 3, kind: 'publish', reason: '반경 수정', published_at: '2026-11-10T02:00:00Z', published_by: 'u-1', job_id: null }],
  ...over,
})

function openSettings(role: 'admin' | 'moderator' = 'admin') {
  fake.signInAs(role)
  return render(<MemoryRouter initialEntries={['/settings']}><App client={makeQueryClient()} /></MemoryRouter>)
}
beforeEach(() => {
  fake.reset()
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
  fake.respond('profiles:select', { data: [{ id: 'u-1', nickname: '김관리' }] })
})

describe('healthChecks', () => {
  it('is all clear for a healthy system', () => expect(healthChecks(HEALTH()).every((c) => c.level === 'ok')).toBe(true))
  it('puts the worst problem first and says what to do', () => {
    const c = healthChecks(HEALTH({ cron: { available: false, job_found: false }, jobs: { scheduled: 2, overdue: 2, running: 0, stuck: 0, failed: 1, next_run_at: null, last_executed_at: null }, guards: { present: [], missing: ['app_content_guard_live'] }, realtime: { publication: true, tables: [], missing: ['app_content'] } }))
    expect(c[0].level).toBe('bad')
    expect(c.find((x) => x.title.includes('pg_cron'))!.detail).toMatch(/Extensions/)
    expect(c.find((x) => x.title === '예약 게시 지연')!.detail).toMatch(/2건/)
    expect(c.find((x) => x.title === '라이브 내용 보호')!.detail).toMatch(/app_content_guard_live/)
    expect(c.find((x) => x.title === '앱 실시간 갱신')!.level).toBe('warn')
  })
  it('flags a missing cron job, a failing run history, and a missing status column', () => {
    expect(healthChecks(HEALTH({ cron: { available: true, job_found: false } }))[0].detail).toMatch(/cms-run-due-jobs/)
    const failing = HEALTH({ cron: { available: true, job_found: true, schedule: '* * * * *', active: true, recent_runs: [{ status: 'failed', start_time: 'x', end_time: null, message: 'boom' }] } })
    expect(healthChecks(failing).some((x) => x.level === 'warn' && x.detail.includes('boom'))).toBe(true)
    expect(healthChecks(HEALTH({ schema: { cafeteria_status: false, contributions: true } })).some((x) => x.title === '학식 식당 상태' && x.level === 'bad')).toBe(true)
  })
})

describe('/settings 게시 관리', () => {
  it('shows pending drafts, scheduled jobs, recent publications and the health summary', async () => {
    fake.respond('rpc:cms_health', { data: HEALTH() })
    openSettings()
    const drafts = await screen.findByLabelText('게시되지 않은 초안')
    expect(within(drafts).getByText('개강 공지')).toBeTruthy()
    expect(within(drafts).getByRole('link', { name: '열어서 게시하기' }).getAttribute('href')).toBe('/content')
    await waitFor(() => expect(within(drafts).getByText(/김관리/)).toBeTruthy())
    const scheduled = screen.getByLabelText('예약된 게시')
    expect(within(scheduled).getByText('온기식당')).toBeTruthy()
    expect(within(scheduled).getByText(/2099\.01\.01 07:00 \(KST\)/)).toBeTruthy()
    expect(within(scheduled).getByRole('link', { name: '열기' }).getAttribute('href')).toBe('/restaurants/r1')
    const recent = screen.getByLabelText('최근 게시')
    expect(within(recent).getByText('순천향대학교')).toBeTruthy()
    expect(within(recent).getByText(/v3 · 게시/)).toBeTruthy()
    expect(within(screen.getByLabelText('동기화 상태')).getByText('정상')).toBeTruthy()
  })

  it('explains content publication versus code deployment and shows the code version', async () => {
    fake.respond('rpc:cms_health', { data: HEALTH() })
    openSettings()
    const card = await screen.findByLabelText('콘텐츠 게시와 코드 배포')
    expect(card.textContent).toMatch(/다시 빌드하지 않아도/)
    expect(card.textContent).toMatch(/Render가 빌드/)
    expect(card.textContent).toMatch(/지금 열려 있는 관리자 코드/)
  })

  it('cancels a scheduled publication through the authorized RPC', async () => {
    fake.respond('rpc:cms_health', { data: HEALTH() }); fake.respond('rpc:cms_cancel_job', { data: null })
    openSettings()
    await userEvent.click(await screen.findByRole('button', { name: '예약 취소' }))
    const dlg = await screen.findByRole('dialog')
    await userEvent.click(within(dlg).getByRole('button', { name: '예약 취소' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_cancel_job')).toBe(true))
    expect(fake.rpcs.find((r) => r.name === 'cms_cancel_job')!.args).toEqual({ p_job: 7, p_reason: '예약 취소' })
  })

  it('shows the reason a scheduled publication failed and retries it', async () => {
    fake.respond('rpc:cms_health', { data: HEALTH({ failed: [{ id: 9, entity_type: 'mission', entity_id: 'm1', label: '찜하기', action: 'publish', run_at: '2026-11-10T00:00:00Z', executed_at: '2026-11-10T00:01:00Z', attempts: 1, last_error: '목표 횟수는 1 ~ 1000 사이 정수여야 해요', created_by: 'u-1' }], jobs: { scheduled: 0, overdue: 0, running: 0, stuck: 0, failed: 1, next_run_at: null, last_executed_at: null } }) })
    fake.respond('rpc:cms_retry_job', { data: null })
    openSettings()
    const failed = await screen.findByLabelText('실패한 예약')
    expect(within(failed).getByText(/목표 횟수는 1 ~ 1000/)).toBeTruthy()
    await userEvent.click(within(failed).getByRole('button', { name: '다시 시도' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'cms_retry_job')).toBe(true))
    expect(fake.rpcs.find((r) => r.name === 'cms_retry_job')!.args).toEqual({ p_job: 9 })
  })

  it('warns loudly when the scheduler is not running', async () => {
    fake.respond('rpc:cms_health', { data: HEALTH({ cron: { available: false, job_found: false }, jobs: { scheduled: 1, overdue: 1, running: 0, stuck: 0, failed: 0, next_run_at: null, last_executed_at: null } }) })
    openSettings()
    const sync = await screen.findByLabelText('동기화 상태')
    expect(within(sync).getByText('문제 있음')).toBeTruthy()
    expect(within(sync).getByText(/pg_cron이 꺼져 있어요/)).toBeTruthy()
  })

  it('degrades honestly when cms_health is not in the database yet (migration 20261116000100)', async () => {
    fake.respond('rpc:cms_health', { error: { code: 'PGRST202', message: 'Could not find the function public.cms_health' } })
    fake.respond('content_drafts:select', { data: [], count: 4 }); fake.respond('publication_jobs:select', { data: [], count: 2 }); fake.respond('content_versions:select', { data: [], count: 9 })
    openSettings()
    expect(await screen.findByText(/20261116000100/)).toBeTruthy()
    expect(await screen.findByText(/현재 초안 4건/)).toBeTruthy()
  })

  it('is for admins only: moderators do not see it', async () => {
    fake.respond('rpc:cms_health', { data: HEALTH() })
    openSettings('moderator')
    await screen.findByText('내 역할:')
    expect(screen.queryByLabelText('게시 관리')).toBeNull()
    expect(fake.rpcs.some((r) => r.name === 'cms_health')).toBe(false)
  })
})
