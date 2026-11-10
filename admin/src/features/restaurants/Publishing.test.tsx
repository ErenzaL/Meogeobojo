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

const LIVE = { name_ko: '옛 이름', name_en: null, category: null, address: null, latitude: null, longitude: null, phone: null, description: '옛 설명', opening_hours: {}, break_time: null, last_order_time: null, business_status: null, price_min_krw: 8000, price_max_krw: null, avg_cost_krw: null, dining_purposes: [], visibility: 'published', featured: false, display_order: null, university_ids: [] }
const DRAFT = (over: Record<string, unknown> = {}) => ({ data: { ...LIVE, name_ko: '새 이름', price_min_krw: 9000 }, revision: 3, base_version: 2, created_by: 'u-1', updated_by: 'u-1', created_at: '2026-11-09T00:00:00Z', updated_at: '2026-11-10T01:00:00Z', stale: false, has_changes: true, ...over })
const JOB = (over: Record<string, unknown> = {}) => ({ id: 7, entity_type: 'restaurant', entity_id: 'r1', action: 'publish', base_version: 2, run_at: '2098-12-31T22:00:00Z', unpublish_at: null, status: 'scheduled', reason: '아침 메뉴', created_by: 'u-1', created_at: '2026-11-10T00:00:00Z', attempts: 0, last_error: null, executed_at: null, published_version: null, parent_job_id: null, ...over })
const STATE = (over: Record<string, unknown> = {}) => ({ live: LIVE, live_version: 2, last_published: { version: 2, kind: 'publish', at: '2026-11-19T22:00:00Z', by: 'u-1', reason: '지난 게시' }, draft: null, jobs: [], ...over })

function open(state: unknown) {
  fake.respond('restaurant_overrides:select', { data: [{ id: 'r1', kakao_place_id: 'k1', image_url: null }] })
  fake.respond('rpc:cms_state', { data: state })
  fake.respond('profiles:select', { data: [{ id: 'u-1', nickname: '김관리' }] })
  fake.respond('universities:select', { data: [] })
  return render(<MemoryRouter initialEntries={['/restaurants/r1']}><App client={makeQueryClient()} /></MemoryRouter>)
}
const tool = async () => within(await screen.findByLabelText('게시 도구'))
const calls = (name: string) => fake.rpcs.filter((r) => r.name === name)

beforeEach(() => {
  fake.reset(); fake.signInAs('admin')
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('게시 도구: status', () => {
  it('shows live status, last published (Seoul time, by whom) and that there is no draft', async () => {
    open(STATE())
    const t = await tool()
    const status = await t.findByLabelText('게시 상태')
    expect(within(status).getByText('공개')).toBeTruthy()
    expect(within(status).getByText('v2')).toBeTruthy()
    expect(within(status).getByText('없음')).toBeTruthy()
    await waitFor(() => expect(within(status).getByText(/2026\.11\.20 07:00 \(KST\) · 김관리/)).toBeTruthy())
    expect((t.getByRole('button', { name: '지금 게시' }) as HTMLButtonElement).disabled).toBe(true) // nothing to publish
    expect((t.getByRole('button', { name: '미리보기' }) as HTMLButtonElement).disabled).toBe(true)
  })

  it('reports pending unpublished changes and when the draft was saved', async () => {
    open(STATE({ draft: DRAFT() }))
    const status = within(await screen.findByLabelText('게시 상태'))
    expect(await status.findByText('게시되지 않은 변경 2건')).toBeTruthy()
    expect(status.getByText(/2026\.11\.10 10:00 \(KST\)/)).toBeTruthy()
  })
})

describe('지금 게시', () => {
  it('summarises what will change, then publishes the saved draft at its revision', async () => {
    fake.respond('rpc:cms_publish', { data: 3 })
    open(STATE({ draft: DRAFT() }))
    const t = await tool()
    await userEvent.click(await t.findByRole('button', { name: '지금 게시' }))
    const dlg = await screen.findByRole('dialog', { name: '지금 게시할까요?' })
    const list = within(dlg).getByLabelText('바뀌는 항목')
    expect(within(list).getByText(/옛 이름/)).toBeTruthy()
    expect(within(list).getByText(/새 이름/)).toBeTruthy()
    expect(calls('cms_publish')).toHaveLength(0) // nothing before confirming
    await userEvent.type(within(dlg).getByLabelText('게시 메모 (선택)'), '메뉴판 반영')
    await userEvent.click(within(dlg).getByRole('button', { name: '지금 게시' }))
    expect(await screen.findByText(/버전 3을 게시했어요/)).toBeTruthy()
    expect(calls('cms_publish')[0].args).toEqual({ p_type: 'restaurant', p_id: 'r1', p_expected_revision: 3, p_reason: '메뉴판 반영' })
  })

  it('unsaved edits must be saved as a draft first: publish, schedule and preview are off', async () => {
    open(STATE({ draft: DRAFT() }))
    const t = await tool()
    await userEvent.type(await screen.findByLabelText('설명'), ' 추가')
    expect((t.getByRole('button', { name: '지금 게시' }) as HTMLButtonElement).disabled).toBe(true)
    expect((t.getByRole('button', { name: '예약 게시' }) as HTMLButtonElement).disabled).toBe(true)
    expect((t.getByRole('button', { name: '미리보기' }) as HTMLButtonElement).disabled).toBe(true)
    expect(t.getByText('저장하지 않은 수정')).toBeTruthy()
  })

  it('a conflict (another admin changed it) is explained and nothing is overwritten', async () => {
    fake.respond('rpc:cms_publish', { error: { code: '40001', message: '다른 관리자가 이 초안을 먼저 저장했어요. 새로고침해서 확인한 뒤 다시 게시해 주세요.' } })
    open(STATE({ draft: DRAFT() }))
    const t = await tool()
    await userEvent.click(await t.findByRole('button', { name: '지금 게시' }))
    await userEvent.click(within(await screen.findByRole('dialog', { name: '지금 게시할까요?' })).getByRole('button', { name: '지금 게시' }))
    expect(await screen.findByText(/다른 관리자가 이 초안을 먼저 저장했어요/)).toBeTruthy()
  })

  it('a stale draft (live moved on) must be rebased before it can be published', async () => {
    fake.respond('rpc:cms_rebase_draft', { data: { revision: 4, base_version: 3 } })
    open(STATE({ draft: DRAFT({ stale: true }), live_version: 3 }))
    const t = await tool()
    expect(await t.findByText(/라이브 내용이 바뀌었어요/)).toBeTruthy()
    expect((t.getByRole('button', { name: '지금 게시' }) as HTMLButtonElement).disabled).toBe(true)
    await userEvent.click(t.getByRole('button', { name: '최신 기준으로 맞추기' }))
    await waitFor(() => expect(calls('cms_rebase_draft')).toHaveLength(1))
    expect(calls('cms_rebase_draft')[0].args).toMatchObject({ p_expected_revision: 3 })
  })
})

describe('예약 게시', () => {
  it('sends the Seoul time as UTC, with an optional end, and says the server runs it', async () => {
    fake.respond('rpc:cms_schedule', { data: 9 })
    open(STATE({ draft: DRAFT() }))
    const t = await tool()
    await userEvent.click(await t.findByRole('button', { name: '예약 게시' }))
    const dlg = await screen.findByRole('dialog', { name: '예약 게시' })
    expect(within(dlg).getByText(/Asia\/Seoul/)).toBeTruthy()
    const run = within(dlg).getByRole('button', { name: '예약하기' }) as HTMLButtonElement
    expect(run.disabled).toBe(true) // no date yet
    await userEvent.type(within(dlg).getByLabelText('게시 날짜'), '2099-01-01')
    await userEvent.clear(within(dlg).getByLabelText('게시 시간')); await userEvent.type(within(dlg).getByLabelText('게시 시간'), '07:00')
    await userEvent.click(within(dlg).getByLabelText(/게시 종료 시각도 정하기/))
    await userEvent.type(within(dlg).getByLabelText('종료 날짜'), '2099-01-03')
    await userEvent.type(within(dlg).getByLabelText('메모 (선택)'), '아침 7시 메뉴')
    expect(run.disabled).toBe(false)
    await userEvent.click(run)
    expect(await screen.findByText(/서버가 그 시각에 자동으로 게시해요/)).toBeTruthy()
    expect(calls('cms_schedule')[0].args).toEqual({
      p_type: 'restaurant', p_id: 'r1', p_expected_revision: 3, p_run_at: '2098-12-31T22:00:00.000Z',
      p_unpublish_at: '2099-01-03T14:00:00.000Z', p_reason: '아침 7시 메뉴',
    })
  })

  it('refuses a time in the past or an end before the start (before asking the server)', async () => {
    open(STATE({ draft: DRAFT() }))
    const t = await tool()
    await userEvent.click(await t.findByRole('button', { name: '예약 게시' }))
    const dlg = await screen.findByRole('dialog', { name: '예약 게시' })
    await userEvent.type(within(dlg).getByLabelText('게시 날짜'), '2020-01-01')
    expect(within(dlg).getByText('예약 시각은 지금부터 1분 이후여야 해요')).toBeTruthy()
    expect((within(dlg).getByRole('button', { name: '예약하기' }) as HTMLButtonElement).disabled).toBe(true)
    await userEvent.clear(within(dlg).getByLabelText('게시 날짜')); await userEvent.type(within(dlg).getByLabelText('게시 날짜'), '2099-01-02')
    await userEvent.click(within(dlg).getByLabelText(/게시 종료 시각도 정하기/))
    await userEvent.type(within(dlg).getByLabelText('종료 날짜'), '2099-01-01')
    expect(within(dlg).getByText('게시 종료 시각은 게시 시각보다 늦어야 해요')).toBeTruthy()
    expect(calls('cms_schedule')).toHaveLength(0)
  })

  it('while scheduled: shows the time and who, blocks publish-now, and can cancel (live unchanged)', async () => {
    fake.respond('rpc:cms_cancel_job', { data: null })
    open(STATE({ draft: DRAFT(), jobs: [JOB()] }))
    const t = await tool()
    const status = within(await t.findByLabelText('게시 상태'))
    expect(await status.findByText('2099.01.01 07:00 (KST)')).toBeTruthy()
    expect((t.getByRole('button', { name: '지금 게시' }) as HTMLButtonElement).disabled).toBe(true)
    expect((t.getByRole('button', { name: '예약 게시' }) as HTMLButtonElement).disabled).toBe(true)
    await userEvent.click(t.getByRole('button', { name: '예약 취소' }))
    expect(await screen.findByText(/예약을 취소했어요. 라이브는 바뀌지 않았어요/)).toBeTruthy()
    expect(calls('cms_cancel_job')[0].args).toMatchObject({ p_job: 7 })
    expect(calls('cms_publish')).toHaveLength(0)
  })
})

describe('게시 중단 · 복원 · 이력', () => {
  it('unpublishing needs a reason and keeps the content', async () => {
    fake.respond('rpc:cms_unpublish', { data: 3 })
    open(STATE())
    const t = await tool()
    await userEvent.click(await t.findByRole('button', { name: '게시 중단' }))
    const dlg = await screen.findByRole('dialog', { hidden: true })
    await userEvent.click(within(dlg).getByRole('button', { name: '게시 중단' }))
    expect(calls('cms_unpublish')).toHaveLength(0) // no reason, no call
    await userEvent.type(within(dlg).getByLabelText('사유 (필수)'), '메뉴 점검')
    await userEvent.click(within(dlg).getByRole('button', { name: '게시 중단' }))
    expect(await screen.findByText(/내용은 지워지지 않고 이력에 남아요/)).toBeTruthy()
    expect(calls('cms_unpublish')[0].args).toEqual({ p_type: 'restaurant', p_id: 'r1', p_reason: '메뉴 점검' })
  })

  it('the history lists versions and restores an older one as a new version, with a reason', async () => {
    fake.respond('rpc:cms_rollback', { data: 3 })
    fake.respond('content_versions:select', { data: [
      { id: 2, version: 2, kind: 'publish', data: LIVE, reason: '지난 게시', rolled_back_from: null, published_by: 'u-1', published_at: '2026-11-19T22:00:00Z', job_id: null },
      { id: 1, version: 1, kind: 'publish', data: LIVE, reason: '처음', rolled_back_from: null, published_by: 'u-1', published_at: '2026-11-01T00:00:00Z', job_id: null },
    ] })
    open(STATE())
    const t = await tool()
    await userEvent.click(await t.findByRole('button', { name: '게시 이력' }))
    const hist = within(await screen.findByLabelText('게시 이력'))
    expect(await hist.findByText('현재 라이브')).toBeTruthy()
    expect(hist.getAllByRole('button', { name: /이 버전으로 복원/ })).toHaveLength(1) // not for the current one
    await userEvent.click(hist.getByRole('button', { name: /이 버전으로 복원/ }))
    const dlg = await screen.findByRole('dialog', { hidden: true })
    await userEvent.type(within(dlg).getByLabelText('사유 (필수)'), '잘못 게시함')
    await userEvent.click(within(dlg).getByRole('button', { name: '복원' }))
    expect(await screen.findByText(/새 버전 3으로 복원했어요/)).toBeTruthy()
    expect(calls('cms_rollback')[0].args).toEqual({ p_type: 'restaurant', p_id: 'r1', p_version: 1, p_reason: '잘못 게시함' })
  })

  it('a failed scheduled publish is surfaced with its reason and can be retried', async () => {
    fake.respond('rpc:cms_retry_job', { data: null })
    fake.respond('content_versions:select', { data: [] })
    open(STATE({ jobs: [JOB({ status: 'failed', last_error: '예약한 뒤 라이브 내용이 바뀌어서 게시하지 않았어요 (충돌)' })] }))
    const t = await tool()
    expect(await t.findByText(/예약 게시 1건이 실패했어요/)).toBeTruthy()
    await userEvent.click(t.getByRole('button', { name: '게시 이력' }))
    const hist = within(await screen.findByLabelText('게시 이력'))
    expect(hist.getByText(/원인: 예약한 뒤 라이브 내용이 바뀌어서/)).toBeTruthy()
    await userEvent.click(hist.getByRole('button', { name: /다시 시도/ }))
    await screen.findByText(/다시 시도하도록 예약했어요/)
    expect(calls('cms_retry_job')[0].args).toMatchObject({ p_job: 7 })
  })
})

describe('미리보기', () => {
  it('shows the app card from the saved draft and exactly what differs from live', async () => {
    open(STATE({ draft: DRAFT() }))
    const t = await tool()
    await userEvent.click(await t.findByRole('button', { name: '미리보기' }))
    const dlg = await screen.findByRole('dialog', { name: '미리보기' })
    expect(within(dlg).getByLabelText('앱 식당 카드 미리보기').textContent).toContain('새 이름')
    expect(within(dlg).getByLabelText('앱 식당 카드 미리보기').textContent).toContain('9,000원부터')
    expect(within(within(dlg).getByLabelText('달라지는 항목')).getAllByRole('listitem')).toHaveLength(2)
  })

  it('warns when the draft would not be visible in the app', async () => {
    open(STATE({ draft: DRAFT({ data: { ...LIVE, visibility: 'hidden' } }) }))
    await userEvent.click(await (await tool()).findByRole('button', { name: '미리보기' }))
    expect(await screen.findByText(/앱 목록에는 이 식당이 보이지 않아요/)).toBeTruthy()
  })
})

describe('식당 목록: 게시 상태', () => {
  const rows = [
    { id: 'a', kakao_place_id: '1', name_ko: '초안식당', category: null, address: null, visibility: 'draft', updated_at: '2026-11-10T00:00:00Z', description: null, image_url: null },
    { id: 'b', kakao_place_id: '2', name_ko: '예약식당', category: null, address: null, visibility: 'published', updated_at: '2026-11-10T00:00:00Z', description: null, image_url: null },
    { id: 'c', kakao_place_id: '3', name_ko: '실패식당', category: null, address: null, visibility: 'published', updated_at: '2026-11-10T00:00:00Z', description: null, image_url: null },
  ]
  const overview = [
    { entity_id: 'a', has_draft: true, draft_updated_at: '2026-11-10T00:00:00Z', scheduled_at: null, failed_jobs: 0, live_version: 0, last_published_at: null },
    { entity_id: 'b', has_draft: false, draft_updated_at: null, scheduled_at: '2098-12-31T22:00:00Z', failed_jobs: 0, live_version: 3, last_published_at: '2026-11-01T00:00:00Z' },
    { entity_id: 'c', has_draft: false, draft_updated_at: null, scheduled_at: null, failed_jobs: 2, live_version: 1, last_published_at: '2026-11-01T00:00:00Z' },
  ]
  const openList = () => {
    fake.respond('restaurant_overrides:select', { data: rows, count: 3 })
    fake.respond('rpc:cms_overview', { data: overview })
    fake.respond('universities:select', { data: [] })
    return render(<MemoryRouter initialEntries={['/restaurants']}><App client={makeQueryClient()} /></MemoryRouter>)
  }

  it('shows draft / scheduled / failed per restaurant', async () => {
    openList()
    expect(await screen.findByText('초안 있음')).toBeTruthy()
    expect(await screen.findByText('예약 2099.01.01 07:00 (KST)')).toBeTruthy()
    expect(screen.getByText('실패 2')).toBeTruthy()
  })

  it('filters by publishing status using the publishing overview', async () => {
    openList()
    await screen.findByText('초안식당')
    await userEvent.selectOptions(screen.getByLabelText('게시 상태 필터'), 'scheduled')
    await waitFor(() => {
      const q = [...fake.calls].reverse().find((c) => c.table === 'restaurant_overrides' && c.filters.some((f) => f[0] === 'in' && f[1] === 'id'))
      expect(q!.filters.find((f) => f[0] === 'in' && f[1] === 'id')![2]).toEqual(['b'])
    })
    await userEvent.selectOptions(screen.getByLabelText('게시 상태 필터'), 'failed')
    await waitFor(() => {
      const q = [...fake.calls].reverse().find((c) => c.table === 'restaurant_overrides' && c.filters.some((f) => f[0] === 'in' && f[1] === 'id'))
      expect(q!.filters.find((f) => f[0] === 'in' && f[1] === 'id')![2]).toEqual(['c'])
    })
    await userEvent.selectOptions(screen.getByLabelText('게시 상태 필터'), 'draft')
    await waitFor(() => {
      const q = [...fake.calls].reverse().find((c) => c.table === 'restaurant_overrides' && c.filters.some((f) => f[0] === 'or' && String(f[1]).includes('visibility.eq.draft')))
      expect(String(q!.filters.find((f) => f[0] === 'or')![1])).toContain('id.in.(a)')
    })
  })

  it('hiding a restaurant is a versioned change that asks for a reason (no silent edit of the live row)', async () => {
    fake.respond('rpc:cms_set_visibility', { data: 4 })
    openList()
    await userEvent.click((await screen.findAllByRole('button', { name: '숨기기' }))[0])
    const dlg = await screen.findByRole('dialog', { hidden: true })
    await userEvent.click(within(dlg).getByRole('button', { name: '숨기기' }))
    expect(calls('cms_set_visibility')).toHaveLength(0) // a reason is required
    await userEvent.type(within(dlg).getByLabelText('사유 (필수)'), '폐업 확인')
    await userEvent.click(within(dlg).getByRole('button', { name: '숨기기' }))
    await waitFor(() => expect(calls('cms_set_visibility')).toHaveLength(1))
    expect(calls('cms_set_visibility')[0].args).toMatchObject({ p_type: 'restaurant', p_visibility: 'hidden', p_reason: '폐업 확인' })
    expect(fake.last('restaurant_overrides', 'update')).toBeUndefined()
  })
})
