import Papa from 'papaparse'

/**
 * CSV for 메뉴·가격. Parsing and formatting only: nothing here talks to the database.
 *
 * The TEMPLATE has exactly these columns. An export adds `menu_id` (the stable id of the menu line, so a re-import
 * updates the same line) and `menu_status`. Both are optional on import.
 */
export const TEMPLATE_COLUMNS = ['kakao_place_id', 'restaurant_name', 'menu_name', 'price_krw', 'menu_category', 'description', 'is_available'] as const
export const EXPORT_COLUMNS = [...TEMPLATE_COLUMNS, 'menu_id', 'menu_status'] as const
const OPTIONAL_COLUMNS = ['menu_id', 'menu_status'] as const

export const MAX_FILE_BYTES = 5 * 1024 * 1024
export const MAX_ROWS = 5000
export const MAX_NAME = 120
export const MAX_DESCRIPTION = 500
export const MAX_CATEGORY = 30
const MAX_PRICE = 2_147_483_647 // the database column is a 32-bit integer

const BOM = '\uFEFF'
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
/** What a long number looks like after a spreadsheet "helpfully" turned it into scientific notation. */
const SCIENTIFIC = /^[+-]?\d+(\.\d+)?e[+-]?\d+$/i

/** The template: the header line only. No example menus or prices are invented. */
export const templateCsv = () => BOM + TEMPLATE_COLUMNS.join(',') + '\r\n'

/** Same text, comparable: NFC, trimmed, inner whitespace collapsed, case-insensitive. */
export const normalizeText = (s: string) => s.normalize('NFC').replace(/\s+/g, ' ').trim().toLowerCase()

/** Spreadsheets run text that starts with = + - @ as a formula. Exports prefix such text with ' and imports remove it again. */
const FORMULA_START = /^[=+\-@\t\r]/
export const guardCell = (s: string) => (FORMULA_START.test(s) ? `'${s}` : s)
export const unguardCell = (s: string) => (/^'[=+\-@\t\r]/.test(s) ? s.slice(1) : s)

export type CsvRow = {
  /** Line number in the file (the header is line 1). */
  line: number
  kakaoPlaceId: string
  restaurantName: string
  menuName: string
  /** null = the cell was blank (unknown price: stays NULL, never 0). */
  price: number | null
  category: string
  description: string
  /** null = blank (optional). */
  available: boolean | null
  /** The cells as typed, kept so a corrected copy of a bad row can be offered for download. */
  priceRaw: string
  availableRaw: string
  /** Optional stable id of an existing menu line. */
  menuId: string
  /** Problems with the row itself (format, length, missing name ...). */
  errors: string[]
}

export type ParsedMenuCsv = {
  /** Set when the file cannot be used at all (no header, missing columns, too large). */
  fatal: string | null
  /** Columns that are not part of the template: ignored. */
  ignoredColumns: string[]
  rows: CsvRow[]
}

const TRUE = new Set(['true', '1', 'yes', 'y', 't', 'o', '예', '네', '판매', '판매중', '판매 중', '있음'])
const FALSE = new Set(['false', '0', 'no', 'n', 'f', 'x', '아니오', '아니요', '품절', '판매안함', '판매 중지'])

export function parseBool(raw: string): { value: boolean | null; error?: string } {
  const v = raw.trim().toLowerCase()
  if (v === '') return { value: null }
  if (TRUE.has(v)) return { value: true }
  if (FALSE.has(v)) return { value: false }
  return { value: null, error: `is_available 값을 알 수 없어요 (“${raw}”): true/false, 1/0, 예/아니오 중 하나로 적어 주세요` }
}

/** Blank -> null. 7000 and 7,000 and "7,000원" are fine; decimals, negatives and text are not. */
export function parsePrice(raw: string): { value: number | null; error?: string } {
  const v = raw.trim()
  if (v === '') return { value: null }
  const digits = v.replace(/[,\s]/g, '').replace(/원$/, '')
  if (!/^\d+$/.test(digits)) return { value: null, error: `가격은 0 이상의 정수여야 해요 (“${raw}”)` }
  const n = Number(digits)
  if (!Number.isSafeInteger(n) || n > MAX_PRICE) return { value: null, error: `가격이 너무 커요 (“${raw}”)` }
  return { value: n }
}

/** Parses CSV text (UTF-8, with or without a BOM). Quoted commas, quotes and line breaks inside cells are handled; Korean text is kept as is. */
export function parseMenuCsv(text: string): ParsedMenuCsv {
  const src = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text
  if (src.trim() === '') return { fatal: '빈 파일이에요. 양식을 내려받아 작성해 주세요.', ignoredColumns: [], rows: [] }
  // U+FFFD is what a decoder writes for bytes it cannot read: the file was not saved as UTF-8 (Excel's plain "CSV" is CP949 in Korean Windows)
  if (src.includes('\uFFFD')) return { fatal: '글자가 깨져 읽혔어요. 파일이 UTF-8이 아닌 것 같아요. 엑셀에서 “CSV UTF-8(쉼표로 분리)”로 다시 저장해 주세요.', ignoredColumns: [], rows: [] }
  const res = Papa.parse<string[]>(src, { delimiter: ',', skipEmptyLines: false })
  // blank lines are dropped AFTER numbering, so a row keeps the line number the person sees in the file
  const firstIdx = res.data.findIndex((r) => r.some((c) => c.trim() !== ''))
  const headerRow = firstIdx < 0 ? [] : res.data[firstIdx]
  const body = firstIdx < 0 ? [] : res.data.slice(firstIdx + 1).map((cells, k) => ({ cells, idx: firstIdx + 1 + k })).filter((r) => r.cells.some((c) => c.trim() !== ''))
  const header = (headerRow ?? []).map((h) => h.replace(/^\uFEFF/, '').trim().toLowerCase())
  const missing = TEMPLATE_COLUMNS.filter((c) => !header.includes(c))
  if (missing.length > 0) {
    return { fatal: `머리글(첫 줄)에 다음 열이 없어요: ${missing.join(', ')}. 양식의 열 이름을 그대로 써 주세요. (쉼표(,)로 구분된 UTF-8 CSV여야 해요)`, ignoredColumns: [], rows: [] }
  }
  const dup = header.filter((h, i) => h !== '' && header.indexOf(h) !== i)
  if (dup.length > 0) return { fatal: `같은 열 이름이 여러 번 나와요: ${[...new Set(dup)].join(', ')}`, ignoredColumns: [], rows: [] }
  if (body.length > MAX_ROWS) return { fatal: `한 번에 ${MAX_ROWS.toLocaleString('ko-KR')}행까지 가져올 수 있어요 (지금 ${body.length.toLocaleString('ko-KR')}행). 파일을 나눠 주세요.`, ignoredColumns: [], rows: [] }
  const known = new Set<string>([...TEMPLATE_COLUMNS, ...OPTIONAL_COLUMNS])
  const ignoredColumns = header.filter((h) => h !== '' && !known.has(h))
  const col = (name: string) => header.indexOf(name)

  // Papa reports structural problems (an unclosed quote, a row with too many / too few cells) by row index.
  const parseErrors = new Map<number, string[]>()
  for (const e of res.errors) {
    if (e.row == null || e.row <= firstIdx) continue
    const msg = e.code === 'TooFewFields' ? '열이 모자라요' : e.code === 'TooManyFields' ? '열이 너무 많아요 (쉼표가 들어간 칸은 큰따옴표(")로 감싸 주세요)' : e.code === 'MissingQuotes' ? '큰따옴표(")가 닫히지 않았어요' : e.message
    parseErrors.set(e.row, [...(parseErrors.get(e.row) ?? []), msg])
  }

  const rows: CsvRow[] = body.map(({ cells, idx }) => {
    const get = (name: string) => {
      const idx = col(name)
      return idx < 0 ? '' : unguardCell((cells[idx] ?? '').normalize('NFC').trim())
    }
    const errors: string[] = [...(parseErrors.get(idx) ?? [])]
    // More cells than columns means an unquoted comma pushed the later cells one column over: that would import values
    // into the wrong columns, so it is refused here (trailing empty cells are harmless, and fewer cells are just blank).
    let used = cells.length
    while (used > header.length && (cells[used - 1] ?? '').trim() === '') used--
    if (used > header.length) errors.push(`열이 ${used}개인데 머리글은 ${header.length}개예요. 쉼표(,)가 들어간 칸은 큰따옴표(")로 감싸 주세요`)
    const kakaoPlaceId = get('kakao_place_id')
    const menuName = get('menu_name')
    const description = get('description')
    const category = get('menu_category')
    const menuId = get('menu_id')
    if (SCIENTIFIC.test(kakaoPlaceId)) errors.push(`kakao_place_id가 지수 형식으로 바뀌었어요 (“${kakaoPlaceId}”). 엑셀에서 이 열을 '텍스트'로 지정하고 다시 입력해 주세요`)
    if (menuName === '') errors.push('menu_name(메뉴 이름)이 비어 있어요')
    else if (menuName.length > MAX_NAME) errors.push(`메뉴 이름은 ${MAX_NAME}자 이하여야 해요`)
    if (description.length > MAX_DESCRIPTION) errors.push(`설명은 ${MAX_DESCRIPTION}자 이하여야 해요`)
    if (category.length > MAX_CATEGORY) errors.push(`분류는 ${MAX_CATEGORY}자 이하여야 해요`)
    if (menuId !== '' && !UUID.test(menuId)) errors.push(`menu_id 형식이 올바르지 않아요 (“${menuId}”)`)
    const price = parsePrice(get('price_krw'))
    if (price.error) errors.push(price.error)
    const avail = parseBool(get('is_available'))
    if (avail.error) errors.push(avail.error)
    return {
      line: idx + 1, kakaoPlaceId, restaurantName: get('restaurant_name'), menuName, price: price.value, category, description,
      available: avail.value, priceRaw: get('price_krw'), availableRaw: get('is_available'), menuId: menuId.toLowerCase(), errors,
    }
  })
  return { fatal: null, ignoredColumns, rows }
}

/** CSV text for download: the columns in order, text guarded against spreadsheet formulas, prices as plain integers, blank price = empty cell. */
export function buildMenuCsv(rows: Record<string, string | number | boolean | null | undefined>[], columns: readonly string[] = EXPORT_COLUMNS): string {
  const text = new Set(['restaurant_name', 'menu_name', 'menu_category', 'description', 'error'])
  return BOM + Papa.unparse({
    fields: [...columns],
    data: rows.map((r) => columns.map((c) => {
      const v = r[c]
      if (v == null) return ''
      const s = String(v)
      return text.has(c) ? guardCell(s) : s
    })),
  }, { newline: '\r\n' })
}
