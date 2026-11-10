import { DIETARY_LABELS, guessKind } from './week'

/** Browser-side CSV handling for the cafeteria import: parse (UTF-8 with or without BOM, quoted fields, CRLF),
 *  map headers (English or Korean), normalise every row and report row-level problems. The server validates AGAIN
 *  and resolves universities / cafeterias; nothing here writes anything. */

export const REQUIRED = ['university', 'cafeteria_name', 'date', 'meal_type', 'menu_name', 'price', 'serving_time'] as const
export const OPTIONAL = [
  'meal_option', 'program', 'description', 'notes', 'menu_items', 'side_dishes', 'soup', 'rice', 'kimchi', 'salad', 'dessert', 'shared', 'origin', 'labels', 'labels_verified', 'sold_out',
  'location', 'source_url', 'university_id', 'cafeteria_id', 'cafeteria_type',
] as const
export type Column = (typeof REQUIRED)[number] | (typeof OPTIONAL)[number]

const ALIASES: Record<string, Column> = {
  대학교: 'university', 대학: 'university', 식당: 'cafeteria_name', 식당명: 'cafeteria_name', 식당이름: 'cafeteria_name', 날짜: 'date', 식사: 'meal_type', 구분: 'meal_type',
  메뉴: 'menu_name', 메뉴명: 'menu_name', 가격: 'price', 이용시간: 'serving_time', 운영시간: 'serving_time', 옵션: 'meal_option', 코너: 'meal_option', 프로그램: 'program',
  설명: 'description', 비고: 'notes', 공지: 'notes', 메뉴목록: 'menu_items', 반찬: 'side_dishes', 반찬목록: 'side_dishes', 국: 'soup', 국탕: 'soup', 밥: 'rice', 김치: 'kimchi', 샐러드: 'salad',
  후식: 'dessert', 공통: 'shared', 공통메뉴: 'shared', 원산지: 'origin', 원산지표시사항: 'origin', 표시: 'labels', 라벨: 'labels', 식이표시: 'labels', 표시확인: 'labels_verified', 품절: 'sold_out', 위치: 'location', 출처: 'source_url', 대학교id: 'university_id', 식당id: 'cafeteria_id', 종류: 'cafeteria_type',
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

/** Several dishes in one cell: separated by "|", "/", ";" or a line break ("도시락김/미소장국"). "·", "*" and "," stay part of a name. */
export const splitCell = (v: string) => v.split(/[|/;\n]/).map((x) => x.trim()).filter(Boolean)
const YES = new Set(['y', 'yes', 'true', '1', '예', '네', '확인', '확인함', 'o'])
const DISH_COLUMNS = [['side_dishes', 'side'], ['menu_items', 'side'], ['soup', 'soup'], ['rice', 'rice'], ['kimchi', 'kimchi'], ['salad', 'salad'], ['dessert', 'dessert']] as const
export type ImportDish = { name_ko: string; kind: string; shared?: boolean }

export type ImportRow = {
  line: number; university: string; university_id: string; cafeteria_name: string; cafeteria_id: string; cafeteria_type: string; location: string
  date: string; meal_type: string; menu_name: string; price: string; start_time: string; end_time: string
  meal_option: string; program: string; description: string; notes: string; menu_items: string[]; source_url: string
  dishes: ImportDish[]; origin: string; labels: string[]; labels_verified: boolean; sold_out: boolean
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
  // dishes, in the order of a menu table: main, sides, soup, rice, kimchi, salad, dessert, then the shared ones
  const dishes: ImportDish[] = []
  const taken = new Set<string>([c('menu_name')])
  const push = (name_ko: string, kind: string, shared?: boolean) => { if (taken.has(name_ko)) return; taken.add(name_ko); dishes.push(shared ? { name_ko, kind, shared: true } : { name_ko, kind }) }
  for (const [col, kind] of DISH_COLUMNS) for (const n of splitCell(c(col))) push(n, kind)
  for (const n of splitCell(c('shared'))) push(n, guessKind(n), true)
  if (dishes.some((d) => d.name_ko.length > 60) || c('menu_name').length > 60) errors.push('메뉴 이름은 60자 이하여야 해요')
  if (dishes.length > 39) errors.push('한 식사에는 메뉴를 40개까지 둘 수 있어요')
  const labels = splitCell(c('labels')).map((l) => l.toUpperCase())
  const badLabel = labels.find((l) => !(DIETARY_LABELS as readonly string[]).includes(l))
  if (badLabel) errors.push(`알 수 없는 표시예요 (HALAL·VEGETARIAN·VEGAN): ${badLabel}`)
  const verified = YES.has(c('labels_verified').toLowerCase())
  if (labels.length > 0 && !badLabel && !verified) errors.push('식이 표시(HALAL 등)는 공식 자료로 확인했을 때만 쓸 수 있어요 (labels_verified 열에 "예")')
  if (c('origin').length > 1200) errors.push('원산지 표시는 1200자 이하로 적어 주세요')
  return {
    line: r.line, university: c('university'), university_id: c('university_id'), cafeteria_name: c('cafeteria_name'), cafeteria_id: c('cafeteria_id'),
    cafeteria_type: c('cafeteria_type'), location: c('location'), date: date ?? c('date'), meal_type: meal ?? c('meal_type'), menu_name: c('menu_name'),
    price: price === undefined ? c('price') : price === null ? '' : String(price), start_time: time?.start ?? '', end_time: time?.end ?? '',
    meal_option: c('meal_option'), program, description: c('description'), notes: c('notes'),
    menu_items: splitCell(c('menu_items')), source_url: c('source_url'),
    dishes, origin: c('origin'), labels, labels_verified: verified, sold_out: YES.has(c('sold_out').toLowerCase()), errors,
  }
}

/** What the server receives for a row (empty strings become absent, so the server's defaults and checks apply). */
export const toRpcRow = (r: ImportRow) => ({
  line: r.line, university: r.university, university_id: r.university_id || null, cafeteria_name: r.cafeteria_name, cafeteria_id: r.cafeteria_id || null,
  cafeteria_type: r.cafeteria_type || null, location: r.location || null, date: r.date, meal_type: r.meal_type, menu_name: r.menu_name, price: r.price,
  start_time: r.start_time || null, end_time: r.end_time || null, meal_option: r.meal_option, program: r.program || null, description: r.description || null,
  notes: r.notes || null, menu_items: r.menu_items, source_url: r.source_url || null,
  dishes: r.dishes, origin: r.origin || null, labels: r.labels, labels_verified: r.labels.length > 0 ? r.labels_verified : null, sold_out: r.sold_out || null,
})

export function decodeProblem(text: string): string | null {
  return text.includes('�') ? '글자가 깨져 보여요. 엑셀에서 "CSV UTF-8" 형식으로 저장해 다시 올려 주세요.' : null
}

/** The downloadable example (UTF-8 with BOM so Excel shows Korean correctly). One row per kind of entry. */
export const TEMPLATE_HEADER = 'university,cafeteria_name,date,meal_type,menu_name,side_dishes,soup,rice,kimchi,salad,dessert,shared,price,serving_time,meal_option,program,description,notes,origin,labels,labels_verified,location,source_url'
export const TEMPLATE_CSV = [
  TEMPLATE_HEADER,
  // one row per meal; several dishes in one cell are separated by / (or | or ;); "shared" dishes appear on every row that lists them
  '순천향대학교,학생식당,2026-11-23,breakfast,계란토스트,우유/과일,,,,,,,1000,08:00-09:30,,천원의 아침밥,간단한 아침 식사,,,,,학생회관 1층,https://example.org/official-menu',
  '순천향대학교,학생식당,2026-11-23,lunch,치즈닭갈비볶음밥,새우튀김*타르타르/참나물무침/햄감자채볶음/파래무침,계란국,,,,,김치/샐러드/후식차,5500,11:30-13:30,A코너,,,상기 메뉴는 재료수급상황에 따라 변경될 수 있습니다,쌀:국내산 / 배추김치:중국산 / 돈육:국내산,,,학생회관 1층,',
  '순천향대학교,학생식당,2026-11-23,lunch,돈까스,샐러드,,,,,,,6500,11:30-13:30,B코너,,,한정 판매,,,,학생회관 1층,',
  '순천향대학교,학생식당,2026-11-23,dinner,고추장불고기,양배추쌈*쌈장/명엽채볶음/참나물무침/파래무침,우동국,,,,,김치/샐러드,6000,17:00-19:00,,,,,,HALAL,예,학생회관 1층,',
  '호서대학교,기숙사식당,2026-11-24,lunch,"비빔밥, 국 세트",,국,,김치,,,,5000,11:30-13:30,,,,"고추장, 참기름 별도",,,,생활관 1층,',
].join('\r\n') + '\r\n'
export const templateBlob = () => new Blob(['\uFEFF', TEMPLATE_CSV], { type: 'text/csv;charset=utf-8' })
