/** Client side of controlled publishing (draft -> preview -> publish / schedule).
 *  The database owns every rule: these are thin wrappers plus Seoul-time and diff helpers. */
import { supabase } from '@/lib/supabase'

export type EntityType = 'restaurant' | 'cafeteria_meal'
export type Snapshot = Record<string, unknown>

export type Job = {
  id: number; entity_type: EntityType; entity_id: string; action: 'publish' | 'unpublish'; base_version: number
  run_at: string; unpublish_at: string | null; status: 'scheduled' | 'running' | 'published' | 'failed' | 'cancelled'
  reason: string | null; created_by: string | null; created_at: string; attempts: number; last_error: string | null
  executed_at: string | null; published_version: number | null; parent_job_id: number | null
}
export type Draft = {
  data: Snapshot; revision: number; base_version: number; created_by: string | null; updated_by: string | null
  created_at: string; updated_at: string; stale: boolean; has_changes: boolean
}
export type CmsState = {
  live: Snapshot; live_version: number
  last_published: { version: number; kind: string; at: string; by: string | null; reason: string | null } | null
  draft: Draft | null; jobs: Job[]
}
export type Version = { id: number; version: number; kind: 'publish' | 'unpublish' | 'rollback' | 'visibility'; data: Snapshot; reason: string | null; rolled_back_from: number | null; published_by: string | null; published_at: string; job_id: number | null }

export const KIND_LABEL: Record<Version['kind'], string> = { publish: '게시', unpublish: '게시 중단', rollback: '복원', visibility: '공개 상태 변경' }
export const JOB_LABEL: Record<Job['status'], string> = { scheduled: '예약됨', running: '실행 중', published: '게시됨', failed: '실패', cancelled: '취소됨' }

// ---- Asia/Seoul <-> UTC -------------------------------------------------------
// Korea has no daylight saving time: Seoul is always UTC+9.
const KST_MS = 9 * 3600_000

/** "2026-11-20" + "07:00" typed in Seoul time -> the UTC ISO string stored in the database. */
export function kstToIso(date: string, time: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date); const t = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(time)
  if (!m || !t) throw new Error('날짜와 시간 형식이 올바르지 않아요')
  return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +t[1], +t[2]) - KST_MS).toISOString()
}
/** A UTC instant -> Seoul date and time parts for inputs. */
export function isoToKst(iso: string): { date: string; time: string } {
  const d = new Date(new Date(iso).getTime() + KST_MS)
  const p = (n: number) => String(n).padStart(2, '0')
  return { date: `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())}`, time: `${p(d.getUTCHours())}:${p(d.getUTCMinutes())}` }
}
/** "2026.11.20 07:00 (KST)" */
export function formatKst(iso: string | null | undefined): string {
  if (!iso) return '—'
  const { date, time } = isoToKst(iso)
  return `${date.replaceAll('-', '.')} ${time} (KST)`
}

// ---- Diff ---------------------------------------------------------------------
export const FIELD_LABEL: Record<string, string> = {
  name_ko: '이름', name_en: '영어 이름', category: '카테고리', address: '주소', latitude: '위도', longitude: '경도', phone: '전화번호',
  description: '설명', opening_hours: '영업시간', break_time: '브레이크타임', last_order_time: '주문 마감', business_status: '영업 상태',
  price_min_krw: '최저 가격', price_max_krw: '최고 가격', avg_cost_krw: '1인 평균', dining_purposes: '식사 목적', visibility: '공개 상태',
  featured: '추천 식당', display_order: '추천 순서', university_ids: '연결된 대학교',
  menu_items: '메뉴', price_krw: '가격', start_time: '시작 시간', end_time: '종료 시간', status: '상태', badge: '배지',
  source_url: '출처 주소', verified_at: '확인한 날짜', extra: '사진·공지',
}
export type Change = { key: string; label: string; from: unknown; to: unknown }
const same = (a: unknown, b: unknown) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null)
/** Fields whose value differs between the live content and the pending draft. */
export function diffSnapshots(live: Snapshot, draft: Snapshot): Change[] {
  const out: Change[] = []
  for (const key of Object.keys(FIELD_LABEL)) {
    if (!(key in draft) && !(key in live)) continue
    // an empty string and a missing value are the same thing in these forms
    const a = live[key] === '' ? null : live[key]; const b = draft[key] === '' ? null : draft[key]
    if (!same(a, b)) out.push({ key, label: FIELD_LABEL[key], from: live[key] ?? null, to: draft[key] ?? null })
  }
  return out
}
export const showValue = (v: unknown): string => {
  if (v == null || v === '') return '(비어 있음)'
  if (Array.isArray(v)) {
    if (v.length === 0) return '(없음)'
    // menu items are objects: show their names
    return v.map((x) => (typeof x === 'object' && x !== null && 'name_ko' in x ? String((x as { name_ko: unknown }).name_ko) : String(x))).join(', ')
  }
  if (typeof v === 'object') {
    const o = v as { photo_url?: string; notice?: string }
    return [o.photo_url ? '사진 있음' : null, o.notice ? `공지: ${o.notice}` : null].filter(Boolean).join(' · ') || '(비어 있음)'
  }
  return typeof v === 'boolean' ? (v ? '예' : '아니요') : String(v)
}

/** Does the live content show to students? (restaurants: visibility; meals: status) */
export const isLiveVisible = (type: EntityType, live: Snapshot): boolean =>
  type === 'restaurant' ? live.visibility === 'published' : ['published', 'closed', 'no_menu'].includes(String(live.status))

// ---- Errors -------------------------------------------------------------------
/** The database signals "someone else changed this" with SQLSTATE 40001. */
export const isConflict = (e: unknown) => typeof e === 'object' && e !== null && 'code' in e && (e as { code: string }).code === '40001'

// ---- RPC wrappers --------------------------------------------------------------
async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw error
  return data as T
}
export const cmsState = (type: EntityType, id: string) => rpc<CmsState>('cms_state', { p_type: type, p_id: id })
export const cmsSaveDraft = (type: EntityType, id: string, data: Snapshot, expectedRevision: number) =>
  rpc<{ revision: number; base_version: number; updated_at: string }>('cms_save_draft', { p_type: type, p_id: id, p_data: data, p_expected_revision: expectedRevision })
export const cmsDiscardDraft = (type: EntityType, id: string, rev: number) => rpc<void>('cms_discard_draft', { p_type: type, p_id: id, p_expected_revision: rev })
export const cmsRebaseDraft = (type: EntityType, id: string, rev: number) => rpc<unknown>('cms_rebase_draft', { p_type: type, p_id: id, p_expected_revision: rev })
export const cmsPublish = (type: EntityType, id: string, rev: number, reason: string) => rpc<number>('cms_publish', { p_type: type, p_id: id, p_expected_revision: rev, p_reason: reason || null })
export const cmsSchedule = (type: EntityType, id: string, rev: number, runAt: string, unpublishAt: string | null, reason: string) =>
  rpc<number>('cms_schedule', { p_type: type, p_id: id, p_expected_revision: rev, p_run_at: runAt, p_unpublish_at: unpublishAt, p_reason: reason || null })
export const cmsReschedule = (job: number, runAt: string, unpublishAt: string | null) => rpc<void>('cms_reschedule', { p_job: job, p_run_at: runAt, p_unpublish_at: unpublishAt })
export const cmsCancelJob = (job: number, reason: string) => rpc<void>('cms_cancel_job', { p_job: job, p_reason: reason || null })
export const cmsRetryJob = (job: number) => rpc<void>('cms_retry_job', { p_job: job })
export const cmsUnpublish = (type: EntityType, id: string, reason: string) => rpc<number>('cms_unpublish', { p_type: type, p_id: id, p_reason: reason })
export const cmsRollback = (type: EntityType, id: string, version: number, reason: string) => rpc<number>('cms_rollback', { p_type: type, p_id: id, p_version: version, p_reason: reason })
export const cmsSetVisibility = (type: EntityType, id: string, visibility: string, reason: string) => rpc<number>('cms_set_visibility', { p_type: type, p_id: id, p_visibility: visibility, p_reason: reason })
export type OverviewRow = { entity_id: string; has_draft: boolean; draft_updated_at: string | null; scheduled_at: string | null; failed_jobs: number; live_version: number; last_published_at: string | null }
export const cmsOverview = (type: EntityType, parent: string | null = null) => rpc<OverviewRow[]>('cms_overview', { p_type: type, p_parent: parent })
export async function cmsVersions(type: EntityType, id: string): Promise<Version[]> {
  const { data, error } = await supabase.from('content_versions').select('*').eq('entity_type', type).eq('entity_id', id).order('version', { ascending: false }).limit(50)
  if (error) throw error
  return data as Version[]
}
