/** Browser-side CSV handling for the cafeteria import: parse (UTF-8 with or without BOM, quoted fields, CRLF),
 *  map headers (English or Korean), normalise every row and report row-level problems. The server validates AGAIN
 *  and resolves universities / cafeterias; nothing here writes anything. */

export const REQUIRED = ['university', 'cafeteria_name', 'date', 'meal_type', 'menu_name', 'price', 'serving_time'] as const
export const OPTIONAL = ['meal_option', 'program', 'description', 'notes', 'menu_items', 'location', 'source_url', 'university_id', 'cafeteria_id', 'cafeteria_type'] as const
export type Column = (typeof REQUIRED)[number] | (typeof OPTIONAL)[number]

const ALIASES: Record<string, Column> = {
  대학교: 'university', 대학: 'university', 식당: 'cafeteria_name', 식당명: 'cafeteria_name', 식당이름: 'cafeteria_name', 날짜: 'date', 식사: 'meal_type', 구분: 'meal_type',
  메뉴: 'menu_name', 메뉴명: 'menu_name', 가격: 'price', 이용시간: 'serving_time', 운영시간: 'serving_time', 옵션: 'meal_option', 코너: 'meal_option', 프로그램: 'program',
  설명: 'description', 비고: 'notes', 공지: 'notes', 메뉴목록: 'menu_items', 위치: 'location', 출처: 'source_url', 대학교id: 'university_id', 식당id: 'cafeteria_id', 종류: 'cafeteria_type',
}

/** RFC 4180 style: quotes, doubled quotes, commas and line breaks inside quotes, CRLF / LF / CR, a leading BOM. Blank lines are skipped. */
export function parseCsv(input: string): string[][] {
  const text = input.charCodeAt(0) === 0xfeff ? input.slice(1) : input
  const delimiter = !text.split(/\r?\n/, 1)[0].includes(',') && text.split(/\r?\n/, 1)[0].includes('\t') ? '\t' : ','
  const rows: string[][] = []
  let row: string[] = []; let field = ''; let quoted = false; let seen = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (quoted) {
      if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++ } else quoted = false } else field += c
    } else if (c === '"' && field === '') { quoted = true; seen = true }
    else if (c === delimiter) { row.push(field); field = ''; seen = true }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++
      if (seen || field !== '' || row.length > 0) { row.push(field); rows.push(row) }
      row = []; field = ''; seen = false
    } else { field += c; seen = true }
  }
  if (seen || field !== '' || row.length > 0) { row.push(field); rows.push(row) }
  return rows.filter((r) => r.some((x) => x.trim() !== ''))
}

const key = (h: string): Column | null => {
  const k = h.replace(/^\uFEFF/, '').trim().toLowerCase().replace(/[\s-]+/g, '_')
  if ((REQUIRED as readonly string[]).includes(k) || (OPTIONAL as readonly string[]).includes(k)) return k as Column
  return ALIASES[k.replace(/_/g, '')] ?? null
}

export type Table = { columns: (Column | null)[]; missing: string[]; unknown: string[]; rows: { line: number; cells: Partial<Record<Column, string>> }[] }
export function toTable(grid: string[][]): Table {
  if (grid.length === 0) return { columns: [], missing: [...REQUIRED], unknown: [], rows: [] }
  const columns = grid[0].map(key)
  const present = new Set(columns.filter(Boolean))
  return {
    columns, missing: REQUIRED.filter((c) => !present.has(c)), unknown: grid[0].filter((_, i) => !columns[i]).map((h) => h.trim()).filter(Boolean),
    rows: grid.slice(1).map((r, i) => ({ line: i + 2, cells: Object.fromEntries(columns.map((c, j) => [c, (r[j] ?? '').trim()]).filter(([c]) => c)) as Partial<Record<Column, string>> })),
  }
}

const MEALS: Record<string, 'breakfast' | 'lunch' | 'dinner'> = { breakfast: 'breakfast', 조식: 'breakfast', 아침: 'breakfast', lunch: 'lunch', 중식: 'lunch', 점심: 'lunch', dinner: 'dinner', 석식: 'dinner', 저녁: 'dinner' }
export const normalizeMeal = (v: string) => MEALS[v.trim().toLowerCase()] ?? null

/** YYYY-MM-DD, YYYY.MM.DD, YYYY/MM/DD (leading zeros optional); null unless it is a real calendar date. */
export function normalizeDate(v: string): string | null {
  const m = /^(\d{4})[-./](\d{1,2})[-./](\d{1,2})$/.exec(v.trim())
  if (!m) return null
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])]
  const dt = new Date(Date.UTC(y, mo - 1, d))
  if (dt.getUTCFullYear() !== y || dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d) return null
  return `${m[1]}-${String(mo).padStart(2, '0')}-${String(d).padStart(2, '0')}`
}
/** "8000", "8,000", "8,000원", "" (unknown) -> number | null; undefined when invalid. */
export function normalizePrice(v: string): number | null | undefined {
  const t = v.trim().replace(/[,\s]/g, '').replace(/원$/, '')
  if (t === '') return null
  return /^\d+$/.test(t) ? Number(t) : undefined
}
/** "11:30-13:30", "11:30~13:30", "11:30 – 13:30", "" -> {start, end}; undefined when invalid. */
export function normalizeTime(v: string): { start: string | null; end: string | null } | undefined {
  const t = v.trim()
  if (t === '') return { start: null, end: null }
  const m = /^(\d{1,2}):(\d{2})\s*[-~–—]\s*(\d{1,2}):(\d{2})$/.exec(t)
  if (!m) return undefined
  const f = (h: string, mi: string) => `${h.padStart(2, '0')}:${mi}`
  const start = f(m[1], m[2]); const end = f(m[3], m[4])
  const ok = /^([01]\d|2[0-3]):[0-5]\d$/
  return ok.test(start) && ok.test(end) && start < end ? { start, end } : undefined
}
const PROGRAMS: Record<string, string> = { '천원의아침밥': '천원의 아침밥', '1000won': '천원의 아침밥', '1000원의아침밥': '천원의 아침밥' }
export const normalizeProgram = (v: string) => { const t = v.trim(); return t === '' ? '' : PROGRAMS[t.replace(/\s+/g, '').toLowerCase()] ?? t }

export type ImportRow = {
  line: number; university: string; university_id: string; cafeteria_name: string; cafeteria_id: string; cafeteria_type: string; location: string
  date: string; meal_type: string; menu_name: string; price: string; start_time: string; end_time: string
  meal_option: string; program: string; description: string; notes: string; menu_items: string[]; source_url: string
  errors: string[]
}
/** One normalised row; [errors] are the problems the browser can already see (the server checks the rest). */
export function normalizeRow(r: { line: number; cells: Partial<Record<Column, string>> }): ImportRow {
  const c = (k: Column) => (r.cells[k] ?? '').trim()
  const errors: string[] = []
  for (const k of ['university', 'cafeteria_name', 'menu_name', 'date', 'meal_type'] as const) {
    if (c(k) === '' && !(k === 'university' && c('university_id')) && !(k === 'cafeteria_name' && c('cafeteria_id'))) errors.push(`${k} 값이 비어 있어요`)
  }
  const date = c('date') === '' ? '' : normalizeDate(c('date'))
  if (date === null) errors.push(`날짜가 올바르지 않아요 (YYYY-MM-DD): ${c('date')}`)
  const meal = c('meal_type') === '' ? '' : normalizeMeal(c('meal_type'))
  if (meal === null) errors.push(`식사 종류가 올바르지 않아요 (조식·중식·석식): ${c('meal_type')}`)
  const price = normalizePrice(c('price'))
  if (price === undefined) errors.push(`가격이 올바르지 않아요 (0 이상의 정수): ${c('price')}`)
  const time = normalizeTime(c('serving_time'))
  if (time === undefined) errors.push(`이용 시간이 올바르지 않아요 (HH:MM-HH:MM): ${c('serving_time')}`)
  const program = normalizeProgram(c('program'))
  return {
    line: r.line, university: c('university'), university_id: c('university_id'), cafeteria_name: c('cafeteria_name'), cafeteria_id: c('cafeteria_id'),
    cafeteria_type: c('cafeteria_type'), location: c('location'), date: date ?? c('date'), meal_type: meal ?? c('meal_type'), menu_name: c('menu_name'),
    price: price === undefined ? c('price') : price === null ? '' : String(price), start_time: time?.start ?? '', end_time: time?.end ?? '',
    meal_option: c('meal_option'), program, description: c('description'), notes: c('notes'),
    menu_items: c('menu_items').split('|').map((x) => x.trim()).filter(Boolean), source_url: c('source_url'), errors,
  }
}

/** What the server receives for a row (empty strings become absent, so the server's defaults and checks apply). */
export const toRpcRow = (r: ImportRow) => ({
  line: r.line, university: r.university, university_id: r.university_id || null, cafeteria_name: r.cafeteria_name, cafeteria_id: r.cafeteria_id || null,
  cafeteria_type: r.cafeteria_type || null, location: r.location || null, date: r.date, meal_type: r.meal_type, menu_name: r.menu_name, price: r.price,
  start_time: r.start_time || null, end_time: r.end_time || null, meal_option: r.meal_option, program: r.program || null, description: r.description || null,
  notes: r.notes || null, menu_items: r.menu_items, source_url: r.source_url || null,
})

export function decodeProblem(text: string): string | null {
  return text.includes('�') ? '글자가 깨져 보여요. 엑셀에서 "CSV UTF-8" 형식으로 저장해 다시 올려 주세요.' : null
}

/** The downloadable example (UTF-8 with BOM so Excel shows Korean correctly). One row per kind of entry. */
export const TEMPLATE_HEADER = 'university,cafeteria_name,date,meal_type,menu_name,price,serving_time,meal_option,program,description,notes,menu_items,location,source_url'
export const TEMPLATE_CSV = [
  TEMPLATE_HEADER,
  '순천향대학교,학생식당,2026-11-23,breakfast,계란토스트,1000,08:00-09:30,,천원의 아침밥,간단한 아침 식사,,우유|과일,학생회관 1층,https://example.org/official-menu',
  '순천향대학교,학생식당,2026-11-23,lunch,제육볶음,5500,11:30-13:30,A코너,,,,밥|된장국|김치,학생회관 1층,',
  '순천향대학교,학생식당,2026-11-23,lunch,돈까스,6500,11:30-13:30,B코너,,,한정 판매,밥|샐러드,학생회관 1층,',
  '순천향대학교,학생식당,2026-11-23,dinner,김치찌개,5500,17:00-19:00,,,,,밥|계란말이,학생회관 1층,',
  '호서대학교,기숙사식당,2026-11-24,lunch,"비빔밥, 국 세트",5000,11:30-13:30,,,"고추장, 참기름 별도",,국|김치,생활관 1층,',
].join('\r\n') + '\r\n'
export const templateBlob = () => new Blob(['\uFEFF', TEMPLATE_CSV], { type: 'text/csv;charset=utf-8' })
