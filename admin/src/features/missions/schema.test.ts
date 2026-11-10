import { describe, expect, it } from 'vitest'
import {
  campaignPayload, campaignState, emptyCampaignForm, emptyMissionForm, isoToSeoulDate, isoToSeoulLastDay, missionPayload, missionPhase,
  recurrenceFor, seoulNextDayIso, seoulStartIso, validateCampaign, validateMission, ruleParams,
} from './schema'

describe('Asia/Seoul periods', () => {
  it('a campaign for 2026-11-01 .. 2026-11-30 is stored as UTC with an exclusive end', () => {
    expect(seoulStartIso('2026-11-01')).toBe('2026-10-31T15:00:00.000Z')
    expect(seoulNextDayIso('2026-11-30')).toBe('2026-11-30T15:00:00.000Z')
  })
  it('round-trips to the dates the admin typed', () => {
    expect(isoToSeoulDate('2026-10-31T15:00:00.000Z')).toBe('2026-11-01')
    expect(isoToSeoulLastDay('2026-11-30T15:00:00.000Z')).toBe('2026-11-30')
  })
})

describe('campaign state (draft / scheduled / active / ended)', () => {
  const c = { publish_state: 'published' as const, starts_at: '2026-10-31T15:00:00Z', ends_at: '2026-11-30T15:00:00Z' }
  it('derives each state from publish state and dates', () => {
    expect(campaignState({ ...c, publish_state: 'draft' }, new Date('2026-11-10T00:00:00Z'))).toBe('draft')
    expect(campaignState(c, new Date('2026-10-01T00:00:00Z'))).toBe('scheduled')
    expect(campaignState(c, new Date('2026-11-10T00:00:00Z'))).toBe('active')
    expect(campaignState(c, new Date('2026-11-30T15:00:00Z'))).toBe('ended')
  })
  it('a scheduled active mission shows as scheduled, then ended', () => {
    const m = { status: 'active' as const, starts_at: null, ends_at: null }
    expect(missionPhase(m, c, new Date('2026-10-01T00:00:00Z'))).toBe('scheduled')
    expect(missionPhase(m, c, new Date('2026-12-02T00:00:00Z'))).toBe('ended')
    expect(missionPhase({ ...m, status: 'paused' }, c)).toBe('paused')
  })
})

describe('campaign validation', () => {
  const ok = { ...emptyCampaignForm(), slug: '2026-12', title: '12월 미션', start_date: '2026-12-01', end_date: '2026-12-31' }
  it('accepts a complete campaign', () => expect(validateCampaign(ok, true)).toEqual({}))
  it('rejects bad input with a message per field', () => {
    const e = validateCampaign({ ...ok, slug: 'A B', title: ' ', theme_color: 'orange', end_date: '2026-11-30' }, true)
    expect(Object.keys(e).sort()).toEqual(['end_date', 'slug', 'theme_color', 'title'])
  })
  it('builds the RPC payload in UTC', () => {
    expect(campaignPayload(ok)).toMatchObject({ slug: '2026-12', starts_at: '2026-11-30T15:00:00.000Z', ends_at: '2026-12-31T15:00:00.000Z' })
    expect(campaignPayload(ok, 'id-1')).not.toHaveProperty('slug')
  })
})

describe('mission validation and payload', () => {
  const ok = { ...emptyMissionForm(), slug: 'nov-test', title: '테스트', campaign_id: 'camp-1' }
  it('accepts a monthly mission with a campaign', () => expect(validateMission(ok, true)).toEqual({}))
  it('requires a campaign for monthly missions', () => expect(validateMission({ ...ok, campaign_id: '' }, true).campaign_id).toBeTruthy())
  it('bounds points and target', () => {
    const e = validateMission({ ...ok, reward_points: '-1', target_count: '0' }, true)
    expect(e.reward_points).toBeTruthy(); expect(e.target_count).toBeTruthy()
    expect(validateMission({ ...ok, reward_points: '10001' }, true).reward_points).toBeTruthy()
    expect(validateMission({ ...ok, target_count: '1.5' }, true).target_count).toBeTruthy()
  })
  it('a master mission must be monthly', () => {
    expect(validateMission({ ...ok, kind: 'daily', rule_type: 'missions_completed' }, true).rule_type).toBeTruthy()
  })
  it('checks the end date against the start date', () => {
    expect(validateMission({ ...ok, start_date: '2026-11-10', end_date: '2026-11-01' }, true).end_date).toBeTruthy()
  })
  it('slug is only validated when creating (it cannot be edited later)', () => {
    expect(validateMission({ ...ok, slug: 'NOT OK' }, true).slug).toBeTruthy()
    expect(validateMission({ ...ok, slug: 'NOT OK' }, false).slug).toBeUndefined()
  })
  it('recurrence follows the kind, so a daily mission cannot be set to never reset', () => {
    expect(recurrenceFor('daily')).toBe('daily'); expect(recurrenceFor('weekly')).toBe('weekly')
    expect(recurrenceFor('monthly')).toBe('none'); expect(recurrenceFor('achievement')).toBe('none')
    expect(missionPayload({ ...ok, kind: 'daily', campaign_id: '' }).recurrence).toBe('daily')
  })
  it('builds rule parameters for each rule type', () => {
    expect(ruleParams({ ...ok, rule_type: 'favorite_cheap', max_price_krw: '10000' })).toEqual({ max_price_krw: 10000 })
    expect(ruleParams({ ...ok, rule_type: 'activity_refs', event: 'category_explore', exclude: 'all, , x' })).toEqual({ event: 'category_explore', exclude: ['all', 'x'] })
    expect(ruleParams({ ...ok, rule_type: 'contribution_approved', contribution_kind: 'menu_photo' })).toEqual({ kind: 'menu_photo' })
    expect(ruleParams({ ...ok, rule_type: 'missions_completed' })).toEqual({})
  })
  it('sends null (not empty strings) for cleared optional fields', () => {
    const p = missionPayload({ ...ok, description: '', university_id: '', start_date: '', end_date: '', badge_key: '' })
    expect(p).toMatchObject({ description: null, university_id: null, starts_at: null, ends_at: null, reward_badge_key: null })
  })
})
