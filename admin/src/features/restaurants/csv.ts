import Papa from 'papaparse'
import { restaurantSchema, emptyRestaurantForm, toRow, type RestaurantForm } from './schema'

/**
 * The ONE column list of the restaurant CSV: the export, the template and the import all use it, so a file exported from
 * here imports again. It follows the current 식당 정보 fields. Older columns (break_time, last_order_time, business_status,
 * price_min_krw, price_max_krw, avg_cost_krw, dining_purposes) are not exported; a file that still has them imports fine
 * (they are ignored), and nothing in the database is removed.
 */
export const CSV_COLUMNS = [
  'kakao_place_id', 'name_ko', 'name_en', 'category', 'address', 'phone', 'latitude', 'longitude', 'description',
  'image_url', 'visibility',
] as const

const stripBom = (t: string) => (t.charCodeAt(0) === 0xfeff ? t.slice(1) : t)

export type ParsedRow = { line: number; values: RestaurantForm | null; errors: string[]; duplicateInFile: boolean }

/** Parses and validates CSV text. Never writes anything. */
export function parseRestaurantCsv(text: string): ParsedRow[] {
  const res = Papa.parse<Record<string, string>>(stripBom(text), { header: true, skipEmptyLines: true })
  const seen = new Set<string>()
  return res.data.map((raw, i) => {
    const candidate = { ...emptyRestaurantForm }
    for (const c of CSV_COLUMNS) {
      const v = (raw[c] ?? '').trim()
      if (c in candidate) (candidate as Record<string, unknown>)[c] = v
    }
    // Imports always arrive as drafts unless the file says otherwise.
    if (!candidate.visibility) candidate.visibility = 'draft'
    const parsed = restaurantSchema.safeParse(candidate)
    const id = candidate.kakao_place_id
    const duplicateInFile = id !== '' && seen.has(id)
    if (id) seen.add(id)
    return {
      line: i + 2, // header is line 1
      values: parsed.success ? parsed.data : null,
      errors: parsed.success ? [] : parsed.error.issues.map((e) => `${e.path.join('.')}: ${e.message}`),
      duplicateInFile,
    }
  })
}

export function buildCsv(rows: Record<string, unknown>[]): string {
  return Papa.unparse({
    fields: [...CSV_COLUMNS],
    data: rows.map((r) =>
      CSV_COLUMNS.map((c) => {
        const v = r[c]
        return Array.isArray(v) ? v.join(', ') : v == null ? '' : String(v)
      }),
    ),
  })
}

export { toRow }

/** The header line only (UTF-8 BOM so Excel shows Korean correctly). Same columns as the export and the import. */
export const restaurantTemplateCsv = () => '\uFEFF' + Papa.unparse({ fields: [...CSV_COLUMNS], data: [] }) + '\r\n'

/** Columns of an uploaded file that this import does not read (for example an older export). */
export function ignoredCsvColumns(text: string): string[] {
  const head = Papa.parse<string[]>(stripBom(text), { preview: 1 }).data[0] ?? []
  const known = new Set<string>(CSV_COLUMNS)
  return head.map((h) => h.trim()).filter((h) => h !== '' && !known.has(h))
}
