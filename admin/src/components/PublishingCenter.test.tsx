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

describe('/settings bulk publishing of drafts', () => {
  const draft = (id: string, label: string, over: Record<string, unknown> = {}) => ({ entity_type: 'restaurant_photos', entity_id: id, label, updated_at: '2026-11-10T01:00:00Z', updated_by: 'u-1', stale: false, has_changes: true, ...over })
  const withDrafts = (drafts: unknown[]) => fake.respond('rpc:cms_health', { data: HEALTH({ drafts: drafts as CmsHealth['drafts'] }) })
  const stateOf = (a: unknown) => ({ data: { live: {}, live_version: 1, last_published: null, jobs: [], draft: { revision: Number((a as { p_id: string }).p_id.replace(/\D/g, '')) + 10 } } })

  it('publishes only the ticked drafts, each with its current revision', async () => {
    withDrafts([draft('a1', '빅토리아'), draft('a2', '삼거리식당'), draft('a3', '스시산')])
    fake.respond('rpc:cms_state', stateOf); fake.respond('rpc:cms_publish', { data: 2 })
    openSettings()
    const card = await screen.findByLabelText('게시되지 않은 초안')
    await userEvent.click(within(card).getByRole('checkbox', { name: '빅토리아 선택' }))
    await userEvent.click(within(card).getByRole('checkbox', { name: '스시산 선택' }))
    await userEvent.click(within(card).getByRole('button', { name: '선택한 2건 게시' }))
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: '2건 게시' }))
    await waitFor(() => expect(fake.rpcs.filter((r) => r.name === 'cms_publish')).toHaveLength(2))
    expect(fake.rpcs.filter((r) => r.name === 'cms_publish').map((r) => r.args)).toEqual([
      { p_type: 'restaurant_photos', p_id: 'a1', p_expected_revision: 11, p_reason: '설정에서 초안 일괄 게시' },
      { p_type: 'restaurant_photos', p_id: 'a3', p_expected_revision: 13, p_reason: '설정에서 초안 일괄 게시' },
    ])
    expect(await screen.findByText(/초안 2건을 게시했어요/)).toBeTruthy()
  })

  it('does nothing until something is ticked', async () => {
    withDrafts([draft('a1', '빅토리아')])
    openSettings()
    const card = await screen.findByLabelText('게시되지 않은 초안')
    expect((within(card).getByRole('button', { name: '선택해서 게시' }) as HTMLButtonElement).disabled).toBe(true)
  })

  it('"전체 선택" and "모두 게시" skip drafts whose live content changed or that match live', async () => {
    withDrafts([draft('a1', '빅토리아'), draft('a2', '오래된 초안', { stale: true }), draft('a3', '같은 초안', { has_changes: false }), draft('a4', '스시산')])
    fake.respond('rpc:cms_state', stateOf); fake.respond('rpc:cms_publish', { data: 2 })
    openSettings()
    const card = await screen.findByLabelText('게시되지 않은 초안')
    expect((within(card).getByRole('checkbox', { name: '오래된 초안 선택' }) as HTMLInputElement).disabled).toBe(true)
    expect((within(card).getByRole('checkbox', { name: '같은 초안 선택' }) as HTMLInputElement).disabled).toBe(true)
    await userEvent.click(within(card).getByRole('checkbox', { name: '전체 선택' }))
    expect(within(card).getByRole('button', { name: '선택한 2건 게시' })).toBeTruthy()
    await userEvent.click(within(card).getByRole('checkbox', { name: '전체 선택' }))
    await userEvent.click(within(card).getByRole('button', { name: /모두 게시 \(2건\)/ }))
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: '2건 게시' }))
    await waitFor(() => expect(fake.rpcs.filter((r) => r.name === 'cms_publish').map((r) => (r.args as { p_id: string }).p_id)).toEqual(['a1', 'a4']))
  })

  it('keeps going when one draft fails and says which one and why', async () => {
    withDrafts([draft('a1', '빅토리아'), draft('a2', '삼거리식당')])
    fake.respond('rpc:cms_state', stateOf)
    fake.respond('rpc:cms_publish', (a: unknown) => ((a as { p_id: string }).p_id === 'a1' ? { error: { code: '40001', message: '다른 관리자가 이 초안을 먼저 저장했어요' } } : { data: 2 }))
    openSettings()
    const card = await screen.findByLabelText('게시되지 않은 초안')
    await userEvent.click(within(card).getByRole('button', { name: /모두 게시/ }))
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: '2건 게시' }))
    const alert = await screen.findByRole('alert')
    expect(alert.textContent).toMatch(/1건을 게시했고 1건은 게시하지 못했어요/)
    expect(alert.textContent).toMatch(/빅토리아: .*먼저 저장/)
    expect(fake.rpcs.filter((r) => r.name === 'cms_publish')).toHaveLength(2)
  })
})
