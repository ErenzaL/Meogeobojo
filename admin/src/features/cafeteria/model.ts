/** Shared definitions for the 학식 admin screens. The database is the source of
 *  truth (CHECK constraints, RLS); these lists only drive the controls. */

export const KINDS = [
  { value: 'student', label: '학생식당' },
  { value: 'dormitory', label: '기숙사식당' },
  { value: 'staff', label: '교직원식당' },
  { value: 'other', label: '기타' },
] as const
export type Kind = (typeof KINDS)[number]['value']
export const kindLabel = (k: string) => KINDS.find((x) => x.value === k)?.label ?? k

export const STATUSES = ['active', 'inactive', 'archived'] as const
export type CafeteriaStatus = (typeof STATUSES)[number]
export const STATUS_LABEL: Record<CafeteriaStatus, string> = { active: '운영 중 (앱에 보임)', inactive: '비활성 (앱에서 숨김)', archived: '보관됨 (앱에서 숨김)' }

export type Cafeteria = {
  id: string; university_id: string; kind: Kind; name_ko: string | null; name_en: string | null; name_zh: string | null
  location_description: string | null; sort_order: number; status: CafeteriaStatus; operating_note: string | null
  universities: { name_ko: string } | null
}

export type CafeteriaForm = {
  university_id: string; kind: Kind; name_ko: string; name_en: string; name_zh: string
  location: string; sort_order: string; status: CafeteriaStatus; operating_note: string
}
export const emptyCafeteriaForm = (university_id = ''): CafeteriaForm => ({
  university_id, kind: 'student', name_ko: '', name_en: '', name_zh: '', location: '', sort_order: '0', status: 'active', operating_note: '',
})
export const cafeteriaToForm = (c: Cafeteria): CafeteriaForm => ({
  university_id: c.university_id, kind: c.kind, name_ko: c.name_ko ?? '', name_en: c.name_en ?? '', name_zh: c.name_zh ?? '',
  location: c.location_description ?? '', sort_order: String(c.sort_order ?? 0), status: c.status, operating_note: c.operating_note ?? '',
})

export function validateCafeteria(f: CafeteriaForm): Record<string, string> {
  const e: Record<string, string> = {}
  if (!f.university_id) e.university_id = '대학교를 선택해 주세요'
  if (f.name_ko.length > 60) e.name_ko = '60자 이하로 입력해 주세요'
  if (f.name_en.length > 60) e.name_en = '60자 이하로 입력해 주세요'
  if (f.name_zh.length > 60) e.name_zh = '60자 이하로 입력해 주세요'
  if (f.operating_note.length > 300) e.operating_note = '300자 이하로 입력해 주세요'
  if (!/^-?\d{1,4}$/.test(f.sort_order.trim())) e.sort_order = '숫자로 입력해 주세요'
  return e
}

/** Form → row. Empty strings become NULL: a name nobody confirmed is never invented. */
export function cafeteriaRow(f: CafeteriaForm) {
  const nul = (s: string) => (s.trim() === '' ? null : s.trim())
  return {
    university_id: f.university_id, kind: f.kind, name_ko: nul(f.name_ko), name_en: nul(f.name_en), name_zh: nul(f.name_zh),
    location_description: nul(f.location), sort_order: Number(f.sort_order.trim()), status: f.status, operating_note: nul(f.operating_note),
  }
}

export const cafeteriaTitle = (c: Pick<Cafeteria, 'name_ko' | 'kind'>) => c.name_ko ?? `${kindLabel(c.kind)} (이름 미확인)`
