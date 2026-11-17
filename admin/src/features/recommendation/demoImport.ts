import Papa from 'papaparse'

/**
 * Import of recommendation hours and amenities into `recommendation_demo_features`: REAL rows (demo_data FALSE, read by
 * every build) and SIMULATED ones (demo_data TRUE, read only in demo mode).
 *
 * It reads nothing but the columns below and writes to that one table only: restaurant records, menus, photos,
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
  takeout: boolean | null; open_late: boolean | null; demo_data: boolean; source: string
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

/** What the rows of a file are: 'file' = what each row's demo_data cell says, 'real' / 'demo' = all rows, whatever the column says. */
export type ImportKind = 'file' | 'real' | 'demo'
/** The same columns without the "_demo" ending are read too (a real file reads naturally with them). */
const ALIAS: Record<string, string> = {
  restaurant_category: 'restaurant_category_demo', open_time: 'open_time_demo', last_order_time: 'last_order_time_demo', break_time: 'break_time_demo',
  no_break_time: 'no_break_time_demo', parking: 'parking_demo', local_currency: 'local_currency_demo', fast_turnover: 'fast_turnover_demo',
  takeout: 'takeout_demo', open_late: 'open_late_demo',
}
export const REAL_SOURCE = '관리자 입력 (실제 데이터)'

export function parseDemoCsv(text: string, kind: ImportKind = 'file'): DemoParse {
  const src = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text
  if (src.trim() === '') return { fatal: '빈 파일이에요.', rows: [], ignored: [], unknown: [] }
  const res = Papa.parse<Record<string, string>>(src, { header: true, skipEmptyLines: true, transformHeader: (h) => h.trim() })
  const header = res.meta.fields ?? []
  if (!header.includes('kakao_place_id')) return { fatal: '머리글(첫 줄)에 kakao_place_id 열이 있어야 해요.', rows: [], ignored: [], unknown: [] }
  if (kind === 'file' && !header.includes('demo_data')) return { fatal: '머리글에 demo_data 열이 없어요. 열을 추가해(TRUE = 가상 데이터, FALSE = 실제 데이터) 주거나, 위에서 “모두 실제 데이터” 또는 “모두 데모 데이터”를 골라 주세요.', rows: [], ignored: [], unknown: [] }
  const known = new Set<string>([...DEMO_COLUMNS, ...Object.keys(ALIAS)])
  const ignored = header.filter((h) => h in NOT_IMPORTED).map((column) => ({ column, reason: NOT_IMPORTED[column] }))
  const unknown = header.filter((h) => !known.has(h) && !(h in NOT_IMPORTED))
  const seen = new Set<string>()
  const rows = res.data.map((raw, i): ParsedDemoRow => {
    const errors: string[] = []
    const id = (raw.kakao_place_id ?? '').trim()
    if (!KAKAO_ID.test(id)) errors.push(id === '' ? 'kakao_place_id가 비어 있어요' : `kakao_place_id 형식이 올바르지 않아요 (“${id}”)`)
    // a column named without "_demo" counts as the same column
    for (const [alias, name] of Object.entries(ALIAS)) if (raw[name] === undefined && raw[alias] !== undefined) raw[name] = raw[alias]
    let demo = true
    if (kind === 'real') demo = false
    else if (kind === 'file') {
      const flag = (raw.demo_data ?? '').trim().toLowerCase()
      if (['true', '1', 'yes', 'y'].includes(flag)) demo = true
      else if (['false', '0', 'no', 'n'].includes(flag)) demo = false
      else errors.push(`demo_data 값을 알 수 없어요 (“${raw.demo_data ?? ''}”): TRUE(가상) / FALSE(실제) 중 하나여야 해요`)
    }
    const duplicate = id !== '' && seen.has(id)
    if (id) seen.add(id)
    const row: DemoRow = {
      kakao_place_id: id, name_ko: (raw.name_ko ?? '').trim() || null, category_demo: (raw.restaurant_category_demo ?? '').trim() || null,
      open_time: normalizeTime(raw.open_time_demo ?? '', 'open_time_demo', errors), last_order_time: normalizeTime(raw.last_order_time_demo ?? '', 'last_order_time_demo', errors),
      break_time: (raw.break_time_demo ?? '').trim() || null,
      no_break_time: bool(raw.no_break_time_demo ?? '', 'no_break_time_demo', errors), parking: bool(raw.parking_demo ?? '', 'parking_demo', errors),
      local_currency: bool(raw.local_currency_demo ?? '', 'local_currency_demo', errors), fast_turnover: bool(raw.fast_turnover_demo ?? '', 'fast_turnover_demo', errors),
      takeout: bool(raw.takeout_demo ?? '', 'takeout_demo', errors), open_late: bool(raw.open_late_demo ?? '', 'open_late_demo', errors),
      demo_data: demo, source: (raw.source ?? '').trim() || (demo ? 'synthetic demo dataset' : REAL_SOURCE),
    }
    if (row.break_time && !/^\d{1,2}:\d{2}\s*[-~–]\s*\d{1,2}:\d{2}$/.test(row.break_time)) errors.push(`break_time_demo 형식이 올바르지 않아요 (“${row.break_time}”): HH:MM-HH:MM`)
    return { line: i + 2, row: errors.length === 0 ? row : null, errors, duplicate }
  })
  return { fatal: null, rows, ignored, unknown }
}

const BOM = '\uFEFF'
const cell = (v: string | number | boolean | null | undefined) => (v == null ? '' : String(v))
const hhmmss = (t: string | null) => (t ? t.slice(0, 5) : '')
const flag = (b: boolean | null) => (b == null ? '' : b ? 'TRUE' : 'FALSE')

/** The header line of the import file, with nothing in it (the columns, in the order the import reads them). */
export const demoTemplateCsv = () => BOM + DEMO_COLUMNS.join(',') + '\r\n'

export type StoredDemoRow = {
  kakao_place_id: string; name_ko: string | null; category_demo: string | null; open_time: string | null; last_order_time: string | null
  break_time: string | null; no_break_time: boolean | null; parking: boolean | null; local_currency: boolean | null; fast_turnover: boolean | null
  takeout: boolean | null; open_late: boolean | null; source: string | null; demo_data: boolean | null
}
/** The stored rows as a file this import can read again (edit it, import it back). */
export function demoExportCsv(rows: StoredDemoRow[]): string {
  const line = (r: StoredDemoRow) => [
    r.kakao_place_id, r.name_ko, r.category_demo, hhmmss(r.open_time), hhmmss(r.last_order_time), r.break_time, flag(r.no_break_time), flag(r.parking),
    flag(r.local_currency), flag(r.fast_turnover), flag(r.takeout), flag(r.open_late), r.demo_data === false ? 'FALSE' : 'TRUE', r.source ?? (r.demo_data === false ? REAL_SOURCE : 'synthetic demo dataset'),
  ]
  return BOM + Papa.unparse({ fields: [...DEMO_COLUMNS], data: rows.map((r) => line(r).map(cell)) }, { newline: '\r\n' })
}
