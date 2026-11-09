import Papa from 'papaparse'
import { restaurantSchema, emptyRestaurantForm, toRow, type RestaurantForm } from './schema'

export const CSV_COLUMNS = [
  'kakao_place_id', 'name_ko', 'name_en', 'category', 'address', 'phone', 'latitude', 'longitude', 'description',
  'break_time', 'last_order_time', 'business_status', 'price_min_krw', 'price_max_krw', 'avg_cost_krw',
  'dining_purposes', 'image_url', 'visibility',
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
