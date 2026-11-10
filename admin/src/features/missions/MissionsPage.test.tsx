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

const open = (path = '/missions') => render(<MemoryRouter initialEntries={[path]}><App client={makeQueryClient()} /></MemoryRouter>)

const campaign = { id: 'camp-1', slug: '2026-11', title: '11월 미션', subtitle: '가을엔, 맛집 탐험하기 🍁', description: null, theme_color: '#E85D04', banner_mascot: 'cheer', starts_at: '2026-10-31T15:00:00Z', ends_at: '2026-11-30T15:00:00Z', publish_state: 'published' }
const mission = (over: Record<string, unknown> = {}) => ({
  id: 'm1', lineage_id: 'm1', version: 1, campaign_id: 'camp-1', slug: 'nov-save', kind: 'monthly', title: '맛집 찜하기', description: '맛집 5곳 저장', category: null, icon: 'favorite',
  reward_points: 20, rule_type: 'favorite_distinct', rule_params: {}, target_count: 5, recurrence: 'none', university_id: null, starts_at: null, ends_at: null,
  action_key: 'map', sort_order: 1, reward_badge_key: null, reward_badge_name: null, reward_badge_mascot: null, status: 'active', ...over,
})

beforeEach(() => {
  fake.reset()
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('access', () => {
  it('has a 미션 관리 entry in the sidebar', async () => {
    fake.signInAs('admin')
    fake.respond('missions:select', { data: [] }); fake.respond('monthly_campaigns:select', { data: [] })
    open()
    const nav = await screen.findByRole('navigation')
    expect(within(nav).getByText('미션 관리')).toBeInTheDocument()
  })

  it('a user with no admin role gets no mission UI', async () => {
    fake.signInAs(null)
    open()
    expect(await screen.findByText('접근 권한이 없어요')).toBeInTheDocument()
    expect(screen.queryByText('미션 추가')).not.toBeInTheDocument()
  })

  it('a moderator only gets the contribution review tab', async () => {
    fake.signInAs('moderator')
    fake.respond('user_contributions:select', { data: [] })
    open()
    expect(await screen.findByText('검토할 기여가 없어요.')).toBeInTheDocument()
    expect(screen.queryByRole('tab', { name: '캠페인' })).not.toBeInTheDocument()
    expect(screen.queryByRole('tab', { name: '분석' })).not.toBeInTheDocument()
    expect(screen.queryByRole('tab', { name: '사용자 진행' })).not.toBeInTheDocument()
    expect(fake.rpcs.find((r) => r.name === 'admin_mission_stats')).toBeUndefined()
  })
})

describe('missions', () => {
  it('lists missions with their state and reward', async () => {
    fake.signInAs('admin')
    fake.respond('monthly_campaigns:select', { data: [campaign] })
    fake.respond('missions:select', { data: [mission(), mission({ id: 'm2', slug: 'nov-draft', title: '초안 미션', status: 'draft' }), mission({ id: 'm3', slug: 'm', title: '마스터', rule_type: 'missions_completed', reward_points: 0, reward_badge_key: 'nov_master' })] })
    open()
    expect(await screen.findByText('맛집 찜하기')).toBeInTheDocument()
    expect(screen.getByText('초안 미션')).toBeInTheDocument()
    expect(screen.getByText(/뱃지 nov_master/)).toBeInTheDocument()
    expect(screen.getAllByText('초안').length).toBeGreaterThan(0)
  })

  it('pausing needs a reason, then calls the database function', async () => {
    fake.signInAs('admin')
    fake.respond('monthly_campaigns:select', { data: [campaign] })
    fake.respond('missions:select', { data: [mission()] })
    fake.respond('rpc:admin_set_mission_status', { data: null })
    open()
    const user = userEvent.setup()
    await user.click(await screen.findByRole('button', { name: '일시중지' }))
    const dialog = await screen.findByRole('dialog', { hidden: true })
    await user.click(within(dialog).getByRole('button', { name: '확인' }))
    expect(fake.rpcs.find((r) => r.name === 'admin_set_mission_status')).toBeUndefined() // reason is required
    await user.type(within(dialog).getByLabelText('사유 (필수)'), '점검')
    await user.click(within(dialog).getByRole('button', { name: '확인' }))
    await waitFor(() => expect(fake.rpcs.find((r) => r.name === 'admin_set_mission_status')).toBeDefined())
    expect(fake.rpcs.find((r) => r.name === 'admin_set_mission_status')!.args).toEqual({ p_id: 'm1', p_status: 'paused', p_reason: '점검' })
  })

  it('creates a mission through admin_save_mission with a normalized payload and a live preview', async () => {
    fake.signInAs('admin')
    fake.respond('monthly_campaigns:select', { data: [campaign] })
    fake.respond('missions:select', { data: [] })
    fake.respond('universities:select', { data: [{ id: 'u1', name_ko: '순천향대학교' }] })
    fake.respond('rpc:admin_save_mission', { data: 'new-id' })
    open()
    const user = userEvent.setup()
    await user.click(await screen.findByRole('button', { name: '미션 추가' }))
    await user.type(screen.getByLabelText(/식별자/), 'nov-lunch')
    await user.type(screen.getByLabelText('제목'), '점심 탐험')
    await user.selectOptions(screen.getByLabelText('캠페인'), 'camp-1')
    expect(within(screen.getByTestId('mission-preview')).getByText('점심 탐험')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: '만들기' }))
    await waitFor(() => expect(fake.rpcs.find((r) => r.name === 'admin_save_mission')).toBeDefined())
    expect((fake.rpcs.find((r) => r.name === 'admin_save_mission')!.args as { p: Record<string, unknown> }).p).toMatchObject({
      slug: 'nov-lunch', kind: 'monthly', campaign_id: 'camp-1', title: '점심 탐험', reward_points: 10, target_count: 3,
      rule_type: 'favorite_distinct', recurrence: 'none', university_id: null, status: 'draft',
    })
  })

  it('shows field errors and sends nothing for invalid input', async () => {
    fake.signInAs('admin')
    fake.respond('monthly_campaigns:select', { data: [campaign] }); fake.respond('missions:select', { data: [] }); fake.respond('universities:select', { data: [] })
    open()
    const user = userEvent.setup()
    await user.click(await screen.findByRole('button', { name: '미션 추가' }))
    await user.click(screen.getByRole('button', { name: '만들기' }))
    expect(await screen.findByText('제목을 입력해 주세요')).toBeInTheDocument()
    expect(fake.rpcs.find((r) => r.name === 'admin_save_mission')).toBeUndefined()
  })

  it('tells the admin when an edit became a new version', async () => {
    fake.signInAs('admin')
    fake.respond('monthly_campaigns:select', { data: [campaign] }); fake.respond('missions:select', { data: [mission()] }); fake.respond('universities:select', { data: [] })
    fake.respond('rpc:admin_save_mission', { data: 'm1-v2' })
    open()
    const user = userEvent.setup()
    await user.click(await screen.findByRole('button', { name: '편집' }))
    expect(screen.getByText(/새 버전이 만들어져요/)).toBeInTheDocument()
    const target = screen.getByLabelText('목표 횟수')
    await user.clear(target); await user.type(target, '7')
    await user.click(screen.getByRole('button', { name: '저장' }))
    expect(await screen.findByText(/새 버전\(v2\)으로 저장했어요/)).toBeInTheDocument()
    expect((fake.rpcs.find((r) => r.name === 'admin_save_mission')!.args as { p: { id: string; target_count: number } }).p).toMatchObject({ id: 'm1', target_count: 7 })
  })
})

describe('campaigns', () => {
  it('shows campaign state and previews the banner before publishing', async () => {
    fake.signInAs('admin')
    fake.respond('monthly_campaigns:select', { data: [{ ...campaign, publish_state: 'draft' }] })
    fake.respond('missions:select', { data: [mission()] })
    fake.respond('rpc:admin_save_campaign', { data: 'c2' })
    open()
    const user = userEvent.setup()
    await user.click(await screen.findByRole('tab', { name: '캠페인' }))
    expect(await screen.findByText('초안')).toBeInTheDocument()
    expect(screen.getByText(/미션 1개/)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: '캠페인 추가' }))
    await user.type(screen.getByLabelText(/식별자/), '2026-12')
    await user.type(screen.getByLabelText('이름'), '12월 미션')
    await user.type(screen.getByLabelText('부제목'), '겨울엔 따뜻한 한 끼')
    await user.type(screen.getByLabelText('시작일 (한국 시간)'), '2026-12-01')
    await user.type(screen.getByLabelText('종료일 (포함)'), '2026-12-31')
    const preview = screen.getByTestId('banner-preview')
    expect(within(preview).getByText('12월 미션')).toBeInTheDocument()
    expect(within(preview).getByText('2026.12.01 – 2026.12.31')).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: '저장' }))
    await waitFor(() => expect(fake.rpcs.find((r) => r.name === 'admin_save_campaign')).toBeDefined())
    expect((fake.rpcs.find((r) => r.name === 'admin_save_campaign')!.args as { p: Record<string, unknown> }).p).toMatchObject({
      slug: '2026-12', title: '12월 미션', starts_at: '2026-11-30T15:00:00.000Z', ends_at: '2026-12-31T15:00:00.000Z',
    })
  })

  it('publishing asks for a reason and calls admin_set_campaign_publish', async () => {
    fake.signInAs('admin')
    fake.respond('monthly_campaigns:select', { data: [{ ...campaign, publish_state: 'draft' }] }); fake.respond('missions:select', { data: [] })
    fake.respond('rpc:admin_set_campaign_publish', { data: null })
    open()
    const user = userEvent.setup()
    await user.click(await screen.findByRole('tab', { name: '캠페인' }))
    await user.click(await screen.findByRole('button', { name: '게시' }))
    const dialog = await screen.findByRole('dialog', { hidden: true })
    await user.type(within(dialog).getByLabelText('사유 (필수)'), '11월 오픈')
    await user.click(within(dialog).getByRole('button', { name: '확인' }))
    await waitFor(() => expect(fake.rpcs.find((r) => r.name === 'admin_set_campaign_publish')).toBeDefined())
    expect(fake.rpcs.find((r) => r.name === 'admin_set_campaign_publish')!.args).toEqual({ p_id: 'camp-1', p_state: 'published', p_reason: '11월 오픈' })
  })
})

describe('analytics', () => {
  const stats = {
    participants: 12, completers: 8, completions: 20, points_awarded: 340, points_revoked: 20,
    missions: [{ id: 'm1', title: '맛집 찜하기', kind: 'monthly', status: 'active', version: 1, participants: 10, completions: 5, points: 100 }],
    daily: [{ day: '2026-11-09', participants: 4, completions: 2 }], weekly: [{ week: '2026-W46', participants: 9, completions: 6 }],
    by_university: [{ university: '순천향대학교', participants: 9, completions: 6 }],
    engagement: { mission_users: 12, app_active_users: 40 }, pending_contributions: 3,
  }
  it('renders real figures from admin_mission_stats', async () => {
    fake.signInAs('admin')
    fake.respond('rpc:admin_mission_stats', { data: stats })
    open()
    await userEvent.setup().click(await screen.findByRole('tab', { name: '분석' }))
    expect(await screen.findByText('340P')).toBeInTheDocument()
    expect(screen.getByText('50%')).toBeInTheDocument() // 5 of 10 completed
    expect(screen.getByText(/12명 \(30%\)/)).toBeInTheDocument()
    expect(screen.getByText('순천향대학교')).toBeInTheDocument()
    expect(fake.rpcs.find((r) => r.name === 'admin_mission_stats')!.args).toEqual({ p_days: 30 })
  })
  it('says so when there is no activity instead of inventing numbers', async () => {
    fake.signInAs('admin')
    fake.respond('rpc:admin_mission_stats', { data: { ...stats, participants: 0, completions: 0, points_awarded: 0, points_revoked: 0, missions: [], daily: [], weekly: [], by_university: [], engagement: { mission_users: 0, app_active_users: 0 }, pending_contributions: 0 } })
    open()
    await userEvent.setup().click(await screen.findByRole('tab', { name: '분석' }))
    expect(await screen.findByText(/가짜 지표는 보여주지 않아요/)).toBeInTheDocument()
  })
})

describe('user progress and contributions', () => {
  const history = {
    balance: 20,
    progress: [{ mission_id: 'm1', title: '맛집 찜하기', kind: 'monthly', period_key: 'once', progress: 5, target: 5, completed_at: '2026-11-09T01:00:00Z', revoked_at: null, version: 1 }],
    transactions: [{ id: 7, points: 20, kind: 'mission_reward', reason: '맛집 찜하기', period_key: 'once', ref_id: null, created_at: '2026-11-09T01:00:00Z' }],
    badges: [], contributions: [],
  }
  it('finds a user, shows history, and revokes a reward with a reason (no way to edit a balance)', async () => {
    fake.signInAs('admin')
    fake.respond('profiles:select', { data: [{ id: '11111111-1111-4111-8111-111111111111', nickname: '민수' }] })
    fake.respond('rpc:admin_suspicious_mission_activity', { data: [] })
    fake.respond('rpc:admin_user_missions', { data: history })
    fake.respond('rpc:admin_revoke_reward', { data: null })
    open()
    const user = userEvent.setup()
    await user.click(await screen.findByRole('tab', { name: '사용자 진행' }))
    await user.type(screen.getByLabelText('닉네임 또는 사용자 ID'), '민수')
    await user.click(await screen.findByRole('button', { name: '민수' }))
    expect(await screen.findByText('20P', { selector: 'b' })).toBeInTheDocument()
    expect(screen.queryByRole('textbox', { name: /잔액|포인트/ })).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: '회수' }))
    const dialog = await screen.findByRole('dialog', { hidden: true })
    await user.type(within(dialog).getByLabelText('사유 (필수)'), '자동화 의심')
    await user.click(within(dialog).getByRole('button', { name: '회수' }))
    await waitFor(() => expect(fake.rpcs.find((r) => r.name === 'admin_revoke_reward')).toBeDefined())
    expect(fake.rpcs.find((r) => r.name === 'admin_revoke_reward')!.args).toEqual({ p_tx: 7, p_reason: '자동화 의심' })
  })

  it('lists suspicious activity as a lead, not a verdict', async () => {
    fake.signInAs('admin')
    fake.respond('rpc:admin_suspicious_mission_activity', { data: [{ user_id: 'u1', reason: 'many_events', detail: '41 activity events in one hour', last_seen: '2026-11-09T01:00:00Z' }] })
    open()
    await userEvent.setup().click(await screen.findByRole('tab', { name: '사용자 진행' }))
    expect(await screen.findByText('짧은 시간에 활동이 너무 많아요')).toBeInTheDocument()
    expect(screen.getByText(/자동 판정이 아니에요/)).toBeInTheDocument()
  })

  it('approves a contribution, and rejecting needs a note', async () => {
    fake.signInAs('moderator')
    fake.respond('user_contributions:select', { data: [{ id: 'c1', user_id: 'u1', kind: 'menu_photo', kakao_place_id: 'k1', payload: { path: 'a.jpg' }, status: 'pending', created_at: '2026-11-09T01:00:00Z' }] })
    fake.respond('rpc:admin_review_contribution', { data: null })
    open()
    const user = userEvent.setup()
    await user.click(await screen.findByRole('button', { name: '승인' }))
    await waitFor(() => expect(fake.rpcs.some((r) => r.name === 'admin_review_contribution')).toBe(true))
    expect(fake.rpcs[0].args).toEqual({ p_id: 'c1', p_status: 'approved', p_note: null })
    await user.click(await screen.findByRole('button', { name: '반려' }))
    const dialog = await screen.findByRole('dialog', { hidden: true })
    await user.click(within(dialog).getByRole('button', { name: '반려' }))
    expect(fake.rpcs.filter((r) => r.name === 'admin_review_contribution')).toHaveLength(1) // no note, no call
    await user.type(within(dialog).getByLabelText('사유 (필수)'), '흐릿해요')
    await user.click(within(dialog).getByRole('button', { name: '반려' }))
    await waitFor(() => expect(fake.rpcs.filter((r) => r.name === 'admin_review_contribution')).toHaveLength(2))
    expect(fake.rpcs[1].args).toEqual({ p_id: 'c1', p_status: 'rejected', p_note: '흐릿해요' })
  })
})
