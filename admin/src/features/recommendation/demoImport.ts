import Papa from 'papaparse'

/**
 * Import of the SYNTHETIC recommendation demo file into `recommendation_demo_features` (development only).
 *
 * It reads nothing but the demo columns below and writes to that one table only: restaurant records, menus, photos,
 * publication states and administrator-entered values are never touched. Latitude / longitude / distance columns are
 * ignored on purpose (distances use Kakao's live coordinates; none are invented), and so are the menu statistics (the
 * budget is judged on the published menus).
 */
export const DEMO_COLUMNS = [
  'kakao_place_id', 'name_ko', 'restaurant_category_demo', 'open_time_demo', 'last_order_time_demo', 'break_time_demo',
  'no_break_time_demo', 'parking_demo', 'local_currency_demo', 'fast_turnover_demo', 'takeout_demo', 'open_late_demo', 'demo_data', 'source',
] as const

/** Columns of the file that are deliberately NOT imported, with the reason shown in the preview. */
export const NOT_IMPORTED: Record<string, string> = {
  latitude: '좌표는 저장하지 않아요. 거리는 카카오 실시간 좌표로 계산해요',
  longitude: '좌표는 저장하지 않아요. 거리는 카카오 실시간 좌표로 계산해요',
  distance_note: '안내 문구예요',
  visibility: '식당의 공개 상태는 바꾸지 않아요',
  menu_count_original: '예산은 게시된 메뉴로만 판단해서 읽지 않아요',
  classified_meal_count: '예산은 게시된 메뉴로만 판단해서 읽지 않아요',
  lowest_classified_meal_price_krw: '예산은 게시된 메뉴로만 판단해서 읽지 않아요',
  meal_under_8000_demo: '예산은 게시된 메뉴로만 판단해서 읽지 않아요',
  meal_under_10000_demo: '예산은 게시된 메뉴로만 판단해서 읽지 않아요',
  meal_under_12000_demo: '예산은 게시된 메뉴로만 판단해서 읽지 않아요',
}

export type DemoRow = {
  kakao_place_id: string; name_ko: string | null; category_demo: string | null
  open_time: string | null; last_order_time: string | null; break_time: string | null
  no_break_time: boolean | null; parking: boolean | null; local_currency: boolean | null; fast_turnover: boolean | null
  takeout: boolean | null; open_late: boolean | null; demo_data: true; source: string
}
export type ParsedDemoRow = { line: number; row: DemoRow | null; errors: string[]; duplicate: boolean }
export type DemoParse = { fatal: string | null; rows: ParsedDemoRow[]; ignored: { column: string; reason: string }[]; unknown: string[] }

const KAKAO_ID = /^\d{1,20}$/
const bool = (raw: string, name: string, errors: string[]): boolean | null => {
  const v = raw.trim().toLowerCase()
  if (v === '') return null
  if (['true', '1', 'yes', 'y'].includes(v)) return true
  if (['false', '0', 'no', 'n'].includes(v)) return false
  errors.push(`${name} 값을 알 수 없어요 (“${raw}”): TRUE / FALSE 중 하나여야 해요`)
  return null
}
/** "9:00" / "09:00" / "09:00:00" -> "09:00". */
export function normalizeTime(raw: string, name: string, errors: string[]): string | null {
  const v = raw.trim()
  if (v === '') return null
  const m = /^(\d{1,2}):(\d{2})(?::\d{2})?$/.exec(v)
  if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) { errors.push(`${name} 시간 형식이 올바르지 않아요 (“${raw}”): HH:MM`); return null }
  return `${m[1].padStart(2, '0')}:${m[2]}`
}

export function parseDemoCsv(text: string): DemoParse {
  const src = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text
  if (src.trim() === '') return { fatal: '빈 파일이에요.', rows: [], ignored: [], unknown: [] }
  const res = Papa.parse<Record<string, string>>(src, { header: true, skipEmptyLines: true, transformHeader: (h) => h.trim() })
  const header = res.meta.fields ?? []
  if (!header.includes('kakao_place_id')) return { fatal: '머리글(첫 줄)에 kakao_place_id 열이 있어야 해요.', rows: [], ignored: [], unknown: [] }
  if (!header.includes('demo_data')) return { fatal: '머리글에 demo_data 열이 없어요. 이 가져오기는 가상(데모) 데이터 전용이에요. 실제 식당 정보는 식당 페이지의 CSV 가져오기를 쓰세요.', rows: [], ignored: [], unknown: [] }
  const known = new Set<string>(DEMO_COLUMNS)
  const ignored = header.filter((h) => h in NOT_IMPORTED).map((column) => ({ column, reason: NOT_IMPORTED[column] }))
  const unknown = header.filter((h) => !known.has(h) && !(h in NOT_IMPORTED))
  const seen = new Set<string>()
  const rows = res.data.map((raw, i): ParsedDemoRow => {
    const errors: string[] = []
    const id = (raw.kakao_place_id ?? '').trim()
    if (!KAKAO_ID.test(id)) errors.push(id === '' ? 'kakao_place_id가 비어 있어요' : `kakao_place_id 형식이 올바르지 않아요 (“${id}”)`)
    const flag = (raw.demo_data ?? '').trim().toLowerCase()
    if (flag !== 'true') errors.push('demo_data가 TRUE가 아니에요. 가상 데이터로 표시되지 않은 줄은 가져오지 않아요')
    const duplicate = id !== '' && seen.has(id)
    if (id) seen.add(id)
    const row: DemoRow = {
      kakao_place_id: id, name_ko: (raw.name_ko ?? '').trim() || null, category_demo: (raw.restaurant_category_demo ?? '').trim() || null,
      open_time: normalizeTime(raw.open_time_demo ?? '', 'open_time_demo', errors), last_order_time: normalizeTime(raw.last_order_time_demo ?? '', 'last_order_time_demo', errors),
      break_time: (raw.break_time_demo ?? '').trim() || null,
      no_break_time: bool(raw.no_break_time_demo ?? '', 'no_break_time_demo', errors), parking: bool(raw.parking_demo ?? '', 'parking_demo', errors),
      local_currency: bool(raw.local_currency_demo ?? '', 'local_currency_demo', errors), fast_turnover: bool(raw.fast_turnover_demo ?? '', 'fast_turnover_demo', errors),
      takeout: bool(raw.takeout_demo ?? '', 'takeout_demo', errors), open_late: bool(raw.open_late_demo ?? '', 'open_late_demo', errors),
      demo_data: true, source: (raw.source ?? '').trim() || 'synthetic demo dataset',
    }
    if (row.break_time && !/^\d{1,2}:\d{2}\s*[-~–]\s*\d{1,2}:\d{2}$/.test(row.break_time)) errors.push(`break_time_demo 형식이 올바르지 않아요 (“${row.break_time}”): HH:MM-HH:MM`)
    return { line: i + 2, row: errors.length === 0 ? row : null, errors, duplicate }
  })
  return { fatal: null, rows, ignored, unknown }
}
