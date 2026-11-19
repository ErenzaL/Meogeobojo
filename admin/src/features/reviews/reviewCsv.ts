import Papa from 'papaparse'

/**
 * Review CSV: parsing a collected file (kakao / naver / delivery-app reviews), and the export.
 *
 * Imported reviews go into the SAME table as the reviews students write in the app (`student_reviews`), so the app, the
 * website and this page always show the same rows. The browser parses and previews; `admin_import_reviews` validates and
 * writes. Nothing here talks to the database.
 */

/** What an export contains (and what a template starts with). A file exported here imports again. */
export const REVIEW_EXPORT_COLUMNS = [
  'kakao_place_id', 'source', 'platform', 'record_type', 'rating', 'review_text', 'review_date', 'source_review_id', 'moderation_status',
] as const

/** The columns the import reads. Every other column of a file (restaurant names, naver_* match data, ...) is ignored. */
const READ = new Set(['kakao_place_id', 'source', 'platform', 'record_type', 'rating', 'review_text', 'review_date', 'source_review_id'])
/** Columns that are expected in a file but deliberately not read, so they are not reported as "unknown". */
const KNOWN_UNREAD = new Set(['moderation_status', 'name_ko', 'restaurant_address', 'naver_rating', 'kakao_rating', 'rating_status', 'source_place_id', 'source_url', 'review_count', 'source_file'])

/** One row as `admin_import_reviews` takes it. */
export type ImportRow = {
  line: number; kakao_place_id: string; source: string; platform: string; source_review_id: string
  rating: string; body: string; reviewed_at: string
}

export type SkipReason = 'restaurant_only' | 'app' | 'empty' | 'other_place'
export type ParsedReviewRow = {
  line: number
  row: ImportRow | null
  errors: string[]
  skip: SkipReason | null
  /** the same review appears earlier in the file */
  duplicate: boolean
  /** the year was worked out from the weekday (Naver writes "10.29.목") */
  inferredYear: boolean
  /** no usable date: the import time is used */
  undated: boolean
}
export type ReviewParse = { fatal: string | null; rows: ParsedReviewRow[]; ignored: string[]; unknown: string[] }

const stripBom = (t: string) => (t.charCodeAt(0) === 0xfeff ? t.slice(1) : t)
const WEEKDAYS = '일월화수목금토' // index = JS getUTCDay()
const pad = (n: number, w = 2) => String(n).padStart(w, '0')

/** The calendar date of "today" in Korea. */
function seoulToday(now: Date) {
  const k = new Date(now.getTime() + 9 * 3600_000)
  return Date.UTC(k.getUTCFullYear(), k.getUTCMonth(), k.getUTCDate())
}
const validDate = (y: number, m: number, d: number) => {
  const t = new Date(Date.UTC(y, m - 1, d))
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d
}
const validTime = (h: number, mi: number, s: number) => h >= 0 && h <= 23 && mi >= 0 && mi <= 59 && s >= 0 && s <= 59
const iso = (y: number, m: number, d: number, h = 0, mi = 0, s = 0) => `${pad(y, 4)}-${pad(m)}-${pad(d)}T${pad(h)}:${pad(mi)}:${pad(s)}+09:00`

export type ParsedDate = { iso: string | null; inferred: boolean; error?: string }

/**
 * A review date from any of the shapes the collected files use. A time without an offset is Korean time (+09:00).
 *   2026-06-13T14:15:00+09:00 / 2026-06-13 14:15 / 2026-06-13      (the export, ISO)
 *   6/13/26 14:15 / 6/13/2026 14:15:00                              (Excel, month first)
 *   25.12.8.월 / 2025.12.8.                                          (Naver)
 *   10.29.목                                                         (Naver, this year: the year is the latest one whose
 *                                                                    calendar puts that day on that weekday)
 * An empty cell is "no date" (the import time is used), not an error.
 */
export function parseReviewDate(raw: string, now: Date = new Date()): ParsedDate {
  const v = raw.trim()
  if (v === '') return { iso: null, inferred: false }
  const bad = (): ParsedDate => ({ iso: null, inferred: false, error: `날짜를 읽을 수 없어요: ${v}` })

  let m = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?)?\s*(Z|[+-]\d{2}:?\d{2})?$/.exec(v)
  if (m) {
    const [y, mo, d, h, mi, s] = [+m[1], +m[2], +m[3], +(m[4] ?? 0), +(m[5] ?? 0), +(m[6] ?? 0)]
    if (!validDate(y, mo, d) || !validTime(h, mi, s)) return bad()
    if (m[7] === undefined) return { iso: iso(y, mo, d, h, mi, s), inferred: false }
    const off = m[7] === 'Z' ? 'Z' : m[7].length === 5 ? `${m[7].slice(0, 3)}:${m[7].slice(3)}` : m[7]
    return { iso: `${pad(y, 4)}-${pad(mo)}-${pad(d)}T${pad(h)}:${pad(mi)}:${pad(s)}${off}`, inferred: false }
  }

  m = /^(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$/.exec(v)
  if (m) {
    const y = m[3].length === 2 ? 2000 + +m[3] : +m[3]
    const [mo, d, h, mi, s] = [+m[1], +m[2], +(m[4] ?? 0), +(m[5] ?? 0), +(m[6] ?? 0)]
    return validDate(y, mo, d) && validTime(h, mi, s) ? { iso: iso(y, mo, d, h, mi, s), inferred: false } : bad()
  }

  m = /^(\d{2}|\d{4})\.\s?(\d{1,2})\.\s?(\d{1,2})\.?(?:\s*([일월화수목금토])(?:요일)?)?$/.exec(v)
  if (m) {
    const y = m[1].length === 2 ? 2000 + +m[1] : +m[1]
    const [mo, d] = [+m[2], +m[3]]
    if (!validDate(y, mo, d)) return bad()
    if (m[4] && WEEKDAYS[new Date(Date.UTC(y, mo - 1, d)).getUTCDay()] !== m[4]) return { iso: null, inferred: false, error: `요일이 맞지 않아요: ${v}` }
    return { iso: iso(y, mo, d), inferred: false }
  }

  m = /^(\d{1,2})\.\s?(\d{1,2})\.\s?([일월화수목금토])(?:요일)?$/.exec(v)
  if (m) {
    const [mo, d] = [+m[1], +m[2]]
    const today = seoulToday(now)
    const thisYear = new Date(today).getUTCFullYear()
    for (let y = thisYear; y > thisYear - 12; y--) {
      if (!validDate(y, mo, d)) continue
      const t = Date.UTC(y, mo - 1, d)
      if (t <= today && WEEKDAYS[new Date(t).getUTCDay()] === m[3]) return { iso: iso(y, mo, d), inferred: true }
    }
    return { iso: null, inferred: false, error: `연도를 알 수 없어요: ${v}` }
  }
  return bad()
}

/** A rating cell: empty, "-" or a number 1..5 in half steps (0.5 is accepted: it is a real Naver value). */
function parseRating(raw: string): { value: string; error?: string } {
  const v = raw.trim()
  if (v === '' || v === '-' || v === '–') return { value: '' }
  const n = Number(v)
  if (!Number.isFinite(n) || n < 0.5 || n > 5 || n * 2 !== Math.trunc(n * 2)) return { value: '', error: `별점이 올바르지 않아요 (0.5~5): ${v}` }
  return { value: String(n) }
}

/**
 * Parses and validates CSV text. Never writes anything.
 * [placeId]: the file is for ONE restaurant. Its kakao_place_id column is then optional (an empty cell means that
 * restaurant), and a line of any other restaurant is skipped, never imported.
 */
export function parseReviewCsv(text: string, now: Date = new Date(), placeId?: string): ReviewParse {
  const res = Papa.parse<Record<string, string>>(stripBom(text), { header: true, skipEmptyLines: 'greedy', transformHeader: (h) => h.trim() })
  const head = res.meta.fields ?? []
  const fatal = !placeId && !head.includes('kakao_place_id') ? '첫 줄에 kakao_place_id 열이 없어요. 리뷰 CSV가 맞는지 확인해 주세요.'
    : !head.includes('source') ? '첫 줄에 source 열이 없어요 (kakao · naver · lemong 처럼 리뷰를 가져온 곳).'
    : !head.includes('review_text') && !head.includes('rating') ? 'review_text 또는 rating 열이 필요해요.'
    : null
  const ignored = head.filter((h) => h !== '' && !READ.has(h))
  const unknown = ignored.filter((h) => !KNOWN_UNREAD.has(h) && !h.startsWith('naver_'))
  if (fatal) return { fatal, rows: [], ignored, unknown }

  const seen = new Set<string>()
  const rows = res.data.map((raw, i): ParsedReviewRow => {
    const line = i + 2 // the header is line 1
    const get = (c: string) => (raw[c] ?? '').trim()
    const base = { line, row: null, errors: [] as string[], skip: null as SkipReason | null, duplicate: false, inferredYear: false, undated: false }
    const type = get('record_type')
    if (type !== '' && type !== 'review') return { ...base, skip: 'restaurant_only' }
    const source = get('source').toLowerCase()
    if (source === 'app') return { ...base, skip: 'app' }

    const errors: string[] = []
    const place = get('kakao_place_id') || placeId || ''
    if (placeId && place !== placeId && !/e\+/i.test(place)) return { ...base, skip: 'other_place' }
    if (/e\+/i.test(place)) errors.push(`장소 ID가 엑셀에서 줄어들었어요 (${place}). 열을 "텍스트"로 두고 다시 저장해 주세요.`)
    else if (!/^[A-Za-z0-9_-]{1,40}$/.test(place)) errors.push(`장소 ID가 올바르지 않아요: ${place || '(비어 있음)'}`)
    if (!/^[a-z0-9_]{2,20}$/.test(source)) errors.push(`출처(source)가 올바르지 않아요: ${source || '(비어 있음)'}`)
    const rating = parseRating(get('rating'))
    if (rating.error) errors.push(rating.error)
    const body = get('review_text')
    if (body.length > 2000) errors.push(`리뷰 내용이 2000자를 넘어요 (${body.length}자)`)
    const date = parseReviewDate(get('review_date'), now)
    if (date.error) errors.push(date.error)

    if (errors.length === 0 && rating.value === '' && body === '') return { ...base, skip: 'empty' }
    if (errors.length > 0) return { ...base, errors }

    const row: ImportRow = {
      line, kakao_place_id: place, source, platform: get('platform'), source_review_id: get('source_review_id'),
      rating: rating.value, body, reviewed_at: date.iso ?? '',
    }
    // the same review twice in one file: keep the first (the server judges the same way)
    const key = row.source_review_id !== '' ? `${source}|${place}|${row.source_review_id}`
      : `${source}|${row.platform}|${place}|${row.reviewed_at}|${row.rating}|${row.body}`
    const duplicate = seen.has(key)
    seen.add(key)
    return { ...base, row, duplicate, inferredYear: date.inferred, undated: date.iso === null }
  })
  return { fatal: null, rows, ignored, unknown }
}

export type ReviewTotals = {
  lines: number; importable: number; duplicate: number; invalid: number
  restaurantOnly: number; app: number; empty: number; otherPlace: number; inferredYear: number; undated: number; places: number
}
export function reviewTotals(p: ReviewParse): ReviewTotals {
  const ok = p.rows.filter((r) => r.row && !r.duplicate)
  return {
    lines: p.rows.length, importable: ok.length,
    duplicate: p.rows.filter((r) => r.row && r.duplicate).length,
    invalid: p.rows.filter((r) => r.errors.length > 0).length,
    restaurantOnly: p.rows.filter((r) => r.skip === 'restaurant_only').length,
    app: p.rows.filter((r) => r.skip === 'app').length,
    empty: p.rows.filter((r) => r.skip === 'empty').length,
    otherPlace: p.rows.filter((r) => r.skip === 'other_place').length,
    inferredYear: ok.filter((r) => r.inferredYear).length,
    undated: ok.filter((r) => r.undated).length,
    places: new Set(ok.map((r) => r.row!.kakao_place_id)).size,
  }
}

/** A stored review as the export reads it. */
export type StoredReview = {
  kakao_place_id: string; source: string; platform: string | null; rating: number | null; source_rating: number | null
  body: string | null; created_at: string; source_review_id: string | null; moderation_status: string
}

/** "2026-06-13T14:15:00+09:00": Korean time, so the file reads the same as the collected ones. */
export function kstIso(isoUtc: string): string {
  const t = new Date(isoUtc)
  if (Number.isNaN(t.getTime())) return ''
  const k = new Date(t.getTime() + 9 * 3600_000)
  return `${pad(k.getUTCFullYear(), 4)}-${pad(k.getUTCMonth() + 1)}-${pad(k.getUTCDate())}T${pad(k.getUTCHours())}:${pad(k.getUTCMinutes())}:${pad(k.getUTCSeconds())}+09:00`
}

/** The export: one line per stored review (the author of a student review is never written). UTF-8 BOM so Excel shows Korean. */
export function reviewExportCsv(rows: StoredReview[]): string {
  const data = rows.map((r) => [
    r.kakao_place_id, r.source, r.platform ?? '', 'review',
    // the original rating when there is one (a half star stays 4.5), else the app's whole-star rating
    r.source_rating ?? r.rating ?? '', r.body ?? '', kstIso(r.created_at), r.source_review_id ?? '', r.moderation_status,
  ].map((v) => (v == null ? '' : String(v))))
  return '﻿' + Papa.unparse({ fields: [...REVIEW_EXPORT_COLUMNS], data }) + '\r\n'
}

/** The header line only. */
export const reviewTemplateCsv = () => '﻿' + Papa.unparse({ fields: [...REVIEW_EXPORT_COLUMNS], data: [] }) + '\r\n'
