import type { Campaign, Kind, Mission, RuleType } from './model'

const DAY = 24 * 3600 * 1000
const KST = 9 * 3600 * 1000

/** Mission periods are Asia/Seoul calendar days; the database stores UTC. */
export const seoulStartIso = (date: string) => new Date(`${date}T00:00:00+09:00`).toISOString()
/** An inclusive last day in the form becomes an EXCLUSIVE end (the next midnight, Seoul). */
export const seoulNextDayIso = (date: string) => new Date(new Date(`${date}T00:00:00+09:00`).getTime() + DAY).toISOString()
export const isoToSeoulDate = (iso: string) => new Date(new Date(iso).getTime() + KST).toISOString().slice(0, 10)
export const isoToSeoulLastDay = (iso: string) => isoToSeoulDate(new Date(new Date(iso).getTime() - 1000).toISOString())

const isDate = (s: string) => /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(new Date(`${s}T00:00:00+09:00`).getTime())

/** draft | scheduled | active | ended, as the database derives it. */
export function campaignState(c: Pick<Campaign, 'publish_state' | 'starts_at' | 'ends_at'>, now = new Date()) {
  if (c.publish_state !== 'published') return 'draft' as const
  if (now < new Date(c.starts_at)) return 'scheduled' as const
  if (now < new Date(c.ends_at)) return 'active' as const
  return 'ended' as const
}

/** What an admin sees for a mission: its own status plus its schedule. */
export function missionPhase(m: Pick<Mission, 'status' | 'starts_at' | 'ends_at'>, campaign: Pick<Campaign, 'starts_at' | 'ends_at'> | undefined, now = new Date()) {
  if (m.status !== 'active') return m.status
  const start = m.starts_at ?? campaign?.starts_at
  const end = m.ends_at ?? campaign?.ends_at
  if (start && now < new Date(start)) return 'scheduled' as const
  if (end && now >= new Date(end)) return 'ended' as const
  return 'active' as const
}

export type CampaignForm = { slug: string; title: string; subtitle: string; description: string; theme_color: string; banner_mascot: string; start_date: string; end_date: string }

export function validateCampaign(f: CampaignForm, isNew: boolean): Record<string, string> {
  const e: Record<string, string> = {}
  if (isNew && !/^[a-z0-9][a-z0-9_-]{1,40}$/.test(f.slug)) e.slug = '영문 소문자·숫자·-·_ 2~41자 (예: 2026-12)'
  if (!f.title.trim()) e.title = '캠페인 이름을 입력해 주세요'
  else if (f.title.trim().length > 60) e.title = '60자 이하여야 해요'
  if (f.subtitle.length > 120) e.subtitle = '120자 이하여야 해요'
  if (f.description.length > 1000) e.description = '1000자 이하여야 해요'
  if (!/^#[0-9A-Fa-f]{6}$/.test(f.theme_color)) e.theme_color = '#RRGGBB 형식이어야 해요'
  if (!isDate(f.start_date)) e.start_date = '시작일을 선택해 주세요'
  if (!isDate(f.end_date)) e.end_date = '종료일을 선택해 주세요'
  else if (isDate(f.start_date) && f.end_date < f.start_date) e.end_date = '종료일은 시작일 이후여야 해요'
  return e
}

export const campaignPayload = (f: CampaignForm, id?: string) => ({
  ...(id ? { id } : { slug: f.slug }),
  title: f.title.trim(), subtitle: f.subtitle.trim() || null, description: f.description.trim() || null,
  theme_color: f.theme_color, banner_mascot: f.banner_mascot,
  starts_at: seoulStartIso(f.start_date), ends_at: seoulNextDayIso(f.end_date),
})

export type MissionForm = {
  slug: string; kind: Kind; campaign_id: string; title: string; description: string; category: string; icon: string
  reward_points: string; rule_type: RuleType; target_count: string; university_id: string
  start_date: string; end_date: string; action_key: string; sort_order: string
  event: string; exclude: string; max_price_krw: string; min_chars: string; contribution_kind: string
  badge_key: string; badge_name: string; badge_mascot: string; status: string
}

export const recurrenceFor = (k: Kind) => (k === 'daily' ? 'daily' : k === 'weekly' ? 'weekly' : 'none') as 'daily' | 'weekly' | 'none'

export function ruleParams(f: MissionForm): Record<string, unknown> {
  switch (f.rule_type) {
    case 'favorite_cheap': return { max_price_krw: Number(f.max_price_krw) }
    case 'activity_days': return { event: f.event }
    case 'activity_refs': return { event: f.event, exclude: f.exclude.split(',').map((s) => s.trim()).filter(Boolean) }
    case 'review_valid': return { min_chars: Number(f.min_chars) }
    case 'contribution_approved': return { kind: f.contribution_kind }
    default: return {}
  }
}

export function validateMission(f: MissionForm, isNew: boolean): Record<string, string> {
  const e: Record<string, string> = {}
  if (isNew && !/^[a-z0-9][a-z0-9_-]{1,60}$/.test(f.slug)) e.slug = '영문 소문자·숫자·-·_ 2~61자'
  if (!f.title.trim()) e.title = '제목을 입력해 주세요'
  else if (f.title.trim().length > 60) e.title = '60자 이하여야 해요'
  if (f.description.length > 300) e.description = '300자 이하여야 해요'
  const pts = Number(f.reward_points), target = Number(f.target_count)
  if (!Number.isInteger(pts) || pts < 0 || pts > 10000) e.reward_points = '0 ~ 10000 사이 정수'
  if (!Number.isInteger(target) || target < 1 || target > 1000) e.target_count = '1 ~ 1000 사이 정수'
  if (f.kind === 'monthly' && !f.campaign_id) e.campaign_id = '월간 미션은 캠페인을 선택해야 해요'
  if (f.rule_type === 'missions_completed' && f.kind !== 'monthly') e.rule_type = '마스터 미션은 월간 미션이어야 해요'
  if (f.rule_type === 'favorite_cheap' && !(Number(f.max_price_krw) > 0)) e.max_price_krw = '0보다 큰 금액(원)'
  if (f.rule_type === 'review_valid' && !(Number(f.min_chars) >= 1)) e.min_chars = '1 이상의 글자 수'
  if ((f.rule_type === 'activity_days' || f.rule_type === 'activity_refs') && !f.event) e.event = '활동 종류를 선택해 주세요'
  if (f.rule_type === 'contribution_approved' && !f.contribution_kind) e.contribution_kind = '기여 종류를 선택해 주세요'
  if (f.start_date && !isDate(f.start_date)) e.start_date = '날짜 형식이 올바르지 않아요'
  if (f.end_date && !isDate(f.end_date)) e.end_date = '날짜 형식이 올바르지 않아요'
  if (f.start_date && f.end_date && f.end_date < f.start_date) e.end_date = '종료일은 시작일 이후여야 해요'
  if (f.badge_key && !/^[a-z0-9][a-z0-9_]{1,60}$/.test(f.badge_key)) e.badge_key = '영문 소문자·숫자·_ 2~61자'
  return e
}

export function missionPayload(f: MissionForm, id?: string) {
  return {
    ...(id ? { id } : { slug: f.slug }),
    kind: f.kind, campaign_id: f.campaign_id || null,
    title: f.title.trim(), description: f.description.trim() || null, category: f.category.trim() || null, icon: f.icon,
    reward_points: Number(f.reward_points), rule_type: f.rule_type, rule_params: ruleParams(f), target_count: Number(f.target_count),
    recurrence: recurrenceFor(f.kind), university_id: f.university_id || null,
    starts_at: f.start_date ? seoulStartIso(f.start_date) : null,
    ends_at: f.end_date ? seoulNextDayIso(f.end_date) : null,
    action_key: f.action_key, sort_order: Number(f.sort_order) || 0,
    reward_badge_key: f.badge_key.trim() || null, reward_badge_name: f.badge_name.trim() || null, reward_badge_mascot: f.badge_mascot || null,
    status: f.status,
  }
}

export const emptyMissionForm = (): MissionForm => ({
  slug: '', kind: 'monthly', campaign_id: '', title: '', description: '', category: '', icon: 'star', reward_points: '10',
  rule_type: 'favorite_distinct', target_count: '3', university_id: '', start_date: '', end_date: '', action_key: 'none', sort_order: '0',
  event: 'recommendation_view', exclude: '', max_price_krw: '10000', min_chars: '10', contribution_kind: 'menu_photo',
  badge_key: '', badge_name: '', badge_mascot: '', status: 'draft',
})

export function missionToForm(m: Mission): MissionForm {
  const p = m.rule_params as Record<string, unknown>
  return {
    slug: m.slug, kind: m.kind, campaign_id: m.campaign_id ?? '', title: m.title, description: m.description ?? '', category: m.category ?? '',
    icon: m.icon, reward_points: String(m.reward_points), rule_type: m.rule_type, target_count: String(m.target_count),
    university_id: m.university_id ?? '', start_date: m.starts_at ? isoToSeoulDate(m.starts_at) : '', end_date: m.ends_at ? isoToSeoulLastDay(m.ends_at) : '',
    action_key: m.action_key, sort_order: String(m.sort_order),
    event: typeof p.event === 'string' ? p.event : 'recommendation_view',
    exclude: Array.isArray(p.exclude) ? (p.exclude as string[]).join(', ') : '',
    max_price_krw: String(p.max_price_krw ?? 10000), min_chars: String(p.min_chars ?? 10),
    contribution_kind: typeof p.kind === 'string' ? p.kind : 'menu_photo',
    badge_key: m.reward_badge_key ?? '', badge_name: m.reward_badge_name ?? '', badge_mascot: m.reward_badge_mascot ?? '', status: m.status,
  }
}

export function campaignToForm(c: Campaign): CampaignForm {
  return {
    slug: c.slug, title: c.title, subtitle: c.subtitle ?? '', description: c.description ?? '', theme_color: c.theme_color,
    banner_mascot: c.banner_mascot, start_date: isoToSeoulDate(c.starts_at), end_date: isoToSeoulLastDay(c.ends_at),
  }
}

export const emptyCampaignForm = (): CampaignForm => ({
  slug: '', title: '', subtitle: '', description: '', theme_color: '#E85D04', banner_mascot: 'cheer', start_date: '', end_date: '',
})
