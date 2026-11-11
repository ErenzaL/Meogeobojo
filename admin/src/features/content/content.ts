import { isoToKst, kstToIso } from '@/lib/cms'

export const KIND = { announcement: '공지', banner: '배너', featured: '추천 식당', notification: '알림' } as const
/** Where each kind shows up in the app and on the website. */
export const KIND_HINT: Record<keyof typeof KIND, string> = {
  notification: '알림은 앱·웹의 종 아이콘(🔔) 목록에만 보여요.',
  announcement: '공지는 홈 화면 카드와 종 아이콘(🔔) 목록에 함께 보여요.',
  banner: '배너는 홈 화면 카드로만 보여요.',
  featured: '추천 식당은 홈의 추천 목록에 보여요.',
}
/** The database rejects a kind it does not know with this constraint (migration 20261120000100 adds 'notification'). */
export const KIND_CONSTRAINT = /app_content_kind_check|violates check constraint/i
export type Kind = keyof typeof KIND
export type Item = {
  id: string; kind: Kind; title: string; body: string | null; image_url: string | null; link_url: string | null; kakao_place_id: string | null
  university_id: string | null; active: boolean; sort_order: number; starts_at: string | null; ends_at: string | null
}
export type ContentForm = { title: string; body: string; image: string; link: string; place: string; sort: string; sDate: string; sTime: string; eDate: string; eTime: string }

export function formFromSnapshot(snap: Record<string, unknown>): ContentForm {
  const s = snap.starts_at ? isoToKst(snap.starts_at as string) : null; const e = snap.ends_at ? isoToKst(snap.ends_at as string) : null
  return {
    title: String(snap.title ?? ''), body: String(snap.body ?? ''), image: String(snap.image_url ?? ''), link: String(snap.link_url ?? ''), place: String(snap.kakao_place_id ?? ''),
    sort: String(snap.sort_order ?? 0), sDate: s?.date ?? '', sTime: s?.time ?? '00:00', eDate: e?.date ?? '', eTime: e?.time ?? '23:59',
  }
}
export function validateContent(f: ContentForm, kind: Kind): Record<string, string> {
  const e: Record<string, string> = {}
  if (!f.title.trim()) e.title = '제목을 입력해 주세요'
  else if (f.title.trim().length > 120) e.title = '120자 이하여야 해요'
  if (f.body.length > 2000) e.body = '2000자 이하여야 해요'
  if (f.link && !/^https:\/\//.test(f.link)) e.link = '링크는 https:// 로 시작해야 해요'
  if (f.image && !/^https:\/\//.test(f.image)) e.image = '이미지 주소는 https:// 로 시작해야 해요'
  if (kind === 'featured' && !f.place.trim()) e.place = '추천 식당은 카카오 장소 ID가 필요해요'
  if (!/^-?\d+$/.test(f.sort.trim())) e.sort = '정수를 입력해 주세요'
  if (f.eDate && !f.sDate) { /* an end without a start is fine: shown until then */ }
  if (f.sDate && f.eDate && `${f.sDate}T${f.sTime}` >= `${f.eDate}T${f.eTime}`) e.eDate = '노출 종료는 시작보다 늦어야 해요'
  return e
}
/** Snapshot from the form. Publishing makes the item live, so `active` is true. A window
 *  edge that did not change keeps its stored text (no phantom "changes"). */
export function snapshotFromForm(f: ContentForm, base: Record<string, unknown>): Record<string, unknown> {
  const keep = (iso: string | null, old: unknown) => (iso && typeof old === 'string' && new Date(old).getTime() === new Date(iso).getTime() ? old : iso)
  return {
    title: f.title.trim(), body: f.body.trim() || null, image_url: f.image.trim() || null, link_url: f.link.trim() || null, kakao_place_id: f.place.trim() || null,
    university_id: (base.university_id as string | null) ?? null, active: true, sort_order: Number(f.sort.trim()),
    starts_at: keep(f.sDate ? kstToIso(f.sDate, f.sTime || '00:00') : null, base.starts_at), ends_at: keep(f.eDate ? kstToIso(f.eDate, f.eTime || '23:59') : null, base.ends_at),
  }
}
