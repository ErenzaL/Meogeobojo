/** Client side of the publishing overview (cms_health). Read-only. */
import type { EntityType } from '@/lib/cms'
import { supabase } from '@/lib/supabase'

export type HealthDraft = { entity_type: EntityType; entity_id: string; label: string; updated_at: string; updated_by: string | null; stale: boolean; has_changes: boolean }
export type HealthJob = { id: number; entity_type: EntityType; entity_id: string; label: string; action: 'publish' | 'unpublish'; status: string; run_at: string; unpublish_at: string | null; created_by: string | null; reason: string | null; overdue: boolean }
export type HealthFailed = { id: number; entity_type: EntityType; entity_id: string; label: string; action: string; run_at: string; executed_at: string | null; attempts: number; last_error: string | null; created_by: string | null }
export type HealthRecent = { entity_type: EntityType; entity_id: string; label: string; version: number; kind: string; reason: string | null; published_at: string; published_by: string | null; job_id: number | null }
export type CmsHealth = {
  generated_at: string
  cron: { available: boolean; job_found: boolean; schedule?: string; active?: boolean; last_success_at?: string | null; recent_runs?: { status: string; start_time: string; end_time: string | null; message: string | null }[]; error?: string }
  jobs: { scheduled: number; overdue: number; running: number; stuck: number; failed: number; next_run_at: string | null; last_executed_at: string | null }
  realtime: { publication: boolean; tables: string[]; missing: string[] }
  guards: { present: string[]; missing: string[] }
  schema: { cafeteria_status: boolean; contributions: boolean }
  drafts: HealthDraft[]; scheduled: HealthJob[]; failed: HealthFailed[]; recent: HealthRecent[]
}

export async function cmsHealth(): Promise<CmsHealth> {
  const { data, error } = await supabase.rpc('cms_health')
  if (error) throw error
  return data as CmsHealth
}
/** The function is not in the database yet (migration 20261116000100 not applied). */
export const isMissingFunction = (e: unknown) => typeof e === 'object' && e !== null && 'code' in e && ['PGRST202', '42883'].includes((e as { code: string }).code)

export const TYPE_LABEL: Record<EntityType, string> = {
  restaurant: '식당', cafeteria_week: '학식 주간 식단', restaurant_menus: '메뉴·가격', restaurant_photos: '사진', cafeteria_meal: '학식 식단', mission: '미션', campaign: '캠페인', app_content: '앱 콘텐츠', university: '대학교',
}
/** Where an entity is edited (and its publishing toolbar lives). */
export const TYPE_ROUTE = (type: EntityType, id: string): string => ({
  restaurant: `/restaurants/${id}`, cafeteria_week: '/cafeteria', restaurant_menus: '/menus', restaurant_photos: '/photos', cafeteria_meal: '/cafeteria', mission: '/missions', campaign: '/missions', app_content: '/content', university: '/universities',
}[type])

/** Counts only, for a database that does not have cms_health yet (the tables are admin-readable). */
export async function basicCounts() {
  const count = async (table: string, status?: string) => {
    let q = supabase.from(table).select('*', { count: 'exact', head: true })
    if (status) q = q.eq('status', status)
    const { count: n, error } = await q
    if (error) throw error
    return n ?? 0
  }
  return { drafts: await count('content_drafts'), scheduled: await count('publication_jobs', 'scheduled'), failed: await count('publication_jobs', 'failed'), versions: await count('content_versions') }
}

export const BUILD: { commit: string; builtAt: string } = typeof __BUILD_INFO__ === 'undefined' ? { commit: 'unknown', builtAt: '' } : __BUILD_INFO__
