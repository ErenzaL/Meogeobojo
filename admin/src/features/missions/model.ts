/** Shared definitions for the mission admin screens. The database is the source
 *  of truth (CHECK constraints + SECURITY DEFINER functions); these lists only
 *  drive the form controls and previews. */

export const MASCOTS = ['standing', 'wink', 'cheer', 'sparkle', 'burger', 'boba', 'searching', 'sleeping', 'confused', 'running'] as const
export type MascotKey = (typeof MASCOTS)[number]
export const MASCOT_LABEL: Record<MascotKey, string> = {
  standing: '기본', wink: '윙크 점프', cheer: '응원', sparkle: '반짝', burger: '버거', boba: '버블티', searching: '탐색', sleeping: '휴식', confused: '갸웃', running: '달리기',
}
/** The mascot artwork already used by the Flutter app (copied unchanged). */
export const mascotSrc = (key: string) => `${import.meta.env.BASE_URL}mascot/${key}.png`

export const KINDS = [
  { value: 'monthly', label: '월간' },
  { value: 'daily', label: '데일리' },
  { value: 'weekly', label: '주간' },
  { value: 'achievement', label: '도전과제' },
] as const
export type Kind = (typeof KINDS)[number]['value']

export const RULES = [
  { value: 'favorite_distinct', label: '서로 다른 맛집 저장' },
  { value: 'favorite_cheap', label: '확인된 가격 이하 맛집 저장' },
  { value: 'activity_days', label: '서로 다른 날 활동' },
  { value: 'activity_refs', label: '서로 다른 항목 탐색' },
  { value: 'review_valid', label: '유효한 리뷰 작성' },
  { value: 'contribution_approved', label: '승인된 기여' },
  { value: 'missions_completed', label: '캠페인 미션 N개 완료 (마스터)' },
] as const
export type RuleType = (typeof RULES)[number]['value']

export const EVENTS = [
  { value: 'recommendation_view', label: '오늘의 추천 확인' },
  { value: 'category_explore', label: '카테고리 탐색' },
] as const

export const CONTRIBUTION_KINDS = [
  { value: 'menu_photo', label: '메뉴 사진' },
  { value: 'info_correction', label: '메뉴·가격 정보 수정' },
] as const

export const ICONS = ['sparkle', 'favorite', 'review', 'photo', 'category', 'value', 'fix', 'trophy', 'star'] as const
export const ICON_LABEL: Record<(typeof ICONS)[number], string> = {
  sparkle: '반짝', favorite: '찜', review: '리뷰', photo: '사진', category: '탐색', value: '가성비', fix: '정보 수정', trophy: '트로피', star: '별',
}

export const ACTIONS = [
  { value: 'none', label: '없음' },
  { value: 'recommend', label: '추천 받기 (홈)' },
  { value: 'map', label: '맛집 찾으러 가기 (지도)' },
  { value: 'favorites', label: '저렴한 맛집 찾기 (홈)' },
  { value: 'categories', label: '카테고리 둘러보기' },
  { value: 'review', label: '리뷰 작성하기' },
  { value: 'photo', label: '메뉴 사진 올리기' },
  { value: 'correct', label: '정보 수정 제안하기' },
] as const

export type PublishState = 'draft' | 'published'
export type Campaign = {
  id: string; slug: string; title: string; subtitle: string | null; description: string | null
  theme_color: string; banner_mascot: string; starts_at: string; ends_at: string; publish_state: PublishState
}
export type MissionStatus = 'draft' | 'active' | 'paused' | 'archived'
export type Mission = {
  id: string; lineage_id: string; version: number; campaign_id: string | null; slug: string; kind: Kind
  title: string; description: string | null; category: string | null; icon: string; reward_points: number
  rule_type: RuleType; rule_params: Record<string, unknown>; target_count: number; recurrence: 'none' | 'daily' | 'weekly'
  university_id: string | null; starts_at: string | null; ends_at: string | null; action_key: string; sort_order: number
  reward_badge_key: string | null; reward_badge_name: string | null; reward_badge_mascot: string | null; status: MissionStatus
}
export type University = { id: string; name_ko: string }

export const STATUS_LABEL: Record<MissionStatus, string> = { draft: '초안', active: '운영 중', paused: '일시중지', archived: '보관' }
export const STATE_LABEL = { draft: '초안', scheduled: '예약됨', active: '진행 중', ended: '종료' } as const
