import { describe, expect, it } from 'vitest'
import FIXTURE from './__fixtures__/reviews_sample.csv?raw'
import { kstIso, parseReviewCsv, parseReviewDate, reviewExportCsv, reviewTemplateCsv, reviewTotals, type StoredReview } from './reviewCsv'

// "today" for the tests: 2026-11-19 (Thursday), Korean time
const NOW = new Date('2026-11-19T00:20:00+09:00')

describe('review dates', () => {
  it('Excel month-first dates are Korean local time', () => {
    expect(parseReviewDate('6/13/26 14:15', NOW)).toEqual({ iso: '2026-06-13T14:15:00+09:00', inferred: false })
    expect(parseReviewDate('8/10/25 0:06', NOW).iso).toBe('2025-08-10T00:06:00+09:00')
    expect(parseReviewDate('9/28/2025 18:42:30', NOW).iso).toBe('2025-09-28T18:42:30+09:00')
  })
  it('Naver dates with a year, with or without the weekday', () => {
    expect(parseReviewDate('25.12.8.월', NOW).iso).toBe('2025-12-08T00:00:00+09:00')
    expect(parseReviewDate('2025.12.8.', NOW).iso).toBe('2025-12-08T00:00:00+09:00')
    expect(parseReviewDate('25.12.9.월', NOW).error).toMatch(/요일/) // 2025-12-09 is a Tuesday
  })
  it('a Naver date without a year takes the latest year whose calendar matches the weekday', () => {
    expect(parseReviewDate('10.29.목', NOW)).toEqual({ iso: '2026-10-29T00:00:00+09:00', inferred: true })
    // 2026-12-25 is still in the future on 2026-11-19, so it is the year before: 2025-12-25 was a Thursday
    expect(parseReviewDate('12.25.목', NOW)).toEqual({ iso: '2025-12-25T00:00:00+09:00', inferred: true })
    expect(parseReviewDate('2.30.월', NOW).error).toBeTruthy()
  })
  it('ISO, with or without an offset; an empty cell is "no date", not an error', () => {
    expect(parseReviewDate('2026-06-13T14:15:00+09:00', NOW).iso).toBe('2026-06-13T14:15:00+09:00')
    expect(parseReviewDate('2026-06-13 14:15', NOW).iso).toBe('2026-06-13T14:15:00+09:00')
    expect(parseReviewDate('2026-06-13T05:15:00Z', NOW).iso).toBe('2026-06-13T05:15:00Z')
    expect(parseReviewDate('2026-06-13', NOW).iso).toBe('2026-06-13T00:00:00+09:00')
    expect(parseReviewDate('  ', NOW)).toEqual({ iso: null, inferred: false })
    expect(parseReviewDate('yesterday', NOW).error).toMatch(/읽을 수 없어요/)
    expect(parseReviewDate('13/40/26', NOW).error).toBeTruthy()
  })
})

describe('the collected file (25 columns, a quoted multi-line cell)', () => {
  const p = parseReviewCsv(FIXTURE, NOW)
  const t = reviewTotals(p)
  it('reads every line, keeps the multi-line review in one row and numbers lines like a spreadsheet', () => {
    expect(p.fatal).toBeNull()
    expect(p.rows).toHaveLength(10)
    expect(p.rows[0].line).toBe(2)
    expect(p.rows[0].row).toMatchObject({ kakao_place_id: '1046337753', source: 'kakao', rating: '1', source_review_id: '15736070', reviewed_at: '2026-06-13T14:15:00+09:00' })
    expect(p.rows[0].row!.body).toBe('불친절. 1인 2시간이라 정해주시네요..\n사람도 없는데 그런 카페는 처음입니다.')
  })
  it('counts what can be imported, and why the rest is not', () => {
    expect(t).toMatchObject({ lines: 10, importable: 7, duplicate: 1, invalid: 0, restaurantOnly: 1, empty: 1, places: 2 })
    expect(p.rows[9].skip).toBe('restaurant_only')
    expect(p.rows[8].skip).toBe('empty') // neither a rating nor text
    expect(p.rows[2].duplicate).toBe(true) // the same kakao review id twice
  })
  it('keeps half stars, text-only and star-only reviews, and "-" means no rating', () => {
    const by = (i: number) => p.rows[i].row!
    expect(by(3).rating).toBe('4.5')
    expect(by(4)).toMatchObject({ rating: '', body: '별점 없이 글만 있는 방문자 리뷰', reviewed_at: '2026-10-29T00:00:00+09:00' })
    expect(by(5)).toMatchObject({ rating: '3.5', body: '' })
    expect(by(6)).toMatchObject({ rating: '', platform: 'BAEMIN', body: '배달 빨라요' })
    expect(by(7)).toMatchObject({ rating: '5', platform: 'CPEATS', reviewed_at: '' })
  })
  it('knows which dates were inferred and which are missing', () => {
    expect(t.inferredYear).toBe(2) // 10.29.목 and 7.26.일
    expect(t.undated).toBe(1)
    expect(p.rows[5].row!.reviewed_at).toBe('2026-07-26T00:00:00+09:00')
  })
  it('lists the columns it does not read, without calling the known ones unknown', () => {
    expect(p.ignored).toEqual(expect.arrayContaining(['name_ko', 'naver_rating', 'source_url']))
    expect(p.unknown).toEqual([])
    expect(parseReviewCsv('kakao_place_id,source,review_text,mystery\n1,naver,좋아요,x\n', NOW).unknown).toEqual(['mystery'])
  })
})

describe('validation', () => {
  const head = 'kakao_place_id,source,rating,review_text,review_date\n'
  it('a file that is not a review file is refused with the reason', () => {
    expect(parseReviewCsv('name\nA\n', NOW).fatal).toMatch(/kakao_place_id/)
    expect(parseReviewCsv('kakao_place_id,review_text\n1,a\n', NOW).fatal).toMatch(/source/)
    expect(parseReviewCsv('kakao_place_id,source\n1,naver\n', NOW).fatal).toMatch(/review_text/)
  })
  it('bad cells are errors on their own line, never silently fixed', () => {
    const p = parseReviewCsv(head + '1.04634E+09,naver,5,좋아요,\nabc!,naver,5,좋아요,\n1,,5,좋아요,\n1,naver,6,좋아요,\n1,naver,4.3,좋아요,\n1,naver,5,좋아요,내일모레\n', NOW)
    expect(p.rows.map((r) => r.row === null)).toEqual([true, true, true, true, true, true])
    expect(p.rows[0].errors.join()).toMatch(/엑셀/)
    expect(p.rows[1].errors.join()).toMatch(/장소 ID/)
    expect(p.rows[2].errors.join()).toMatch(/출처/)
    expect(p.rows[3].errors.join()).toMatch(/별점/)
    expect(p.rows[4].errors.join()).toMatch(/별점/)
    expect(p.rows[5].errors.join()).toMatch(/날짜/)
  })
  it('over-long text is refused; the app\'s own reviews in an export are skipped, not imported', () => {
    expect(parseReviewCsv(head + `1,naver,5,${'가'.repeat(2001)},\n`, NOW).rows[0].errors.join()).toMatch(/2000자/)
    expect(parseReviewCsv(head + '1,app,5,학생 글,\n', NOW).rows[0].skip).toBe('app')
  })
})

describe('a file for ONE restaurant', () => {
  const head = 'kakao_place_id,source,rating,review_text\n'
  it('takes only that restaurant\'s lines; the other restaurants\' lines are skipped, not imported', () => {
    const p = parseReviewCsv(head + '111,naver,5,이 식당\n222,naver,4,다른 식당\n111,kakao,3,이 식당 두번째\n', NOW, '111')
    expect(p.rows.map((r) => r.row?.kakao_place_id ?? r.skip)).toEqual(['111', 'other_place', '111'])
    expect(reviewTotals(p)).toMatchObject({ importable: 2, otherPlace: 1, places: 1 })
  })
  it('the place column may be empty or missing: the lines belong to that restaurant', () => {
    expect(parseReviewCsv(head + ',naver,5,좋아요\n', NOW, '111').rows[0].row!.kakao_place_id).toBe('111')
    const noColumn = parseReviewCsv('source,rating,review_text\nnaver,5,좋아요\n', NOW, '111')
    expect(noColumn.fatal).toBeNull()
    expect(noColumn.rows[0].row!.kakao_place_id).toBe('111')
    // without a restaurant the column is required, as before
    expect(parseReviewCsv('source,rating,review_text\nnaver,5,좋아요\n', NOW).fatal).toMatch(/kakao_place_id/)
  })
  it('the whole collected file, read for one restaurant, yields exactly that restaurant\'s reviews', () => {
    const p = parseReviewCsv(FIXTURE, NOW, '382170960')
    expect(reviewTotals(p)).toMatchObject({ importable: 2, places: 1 })
    expect(p.rows.filter((r) => r.row).every((r) => r.row!.kakao_place_id === '382170960')).toBe(true)
  })
})

describe('export and template', () => {
  const stored: StoredReview[] = [
    { kakao_place_id: '1', source: 'naver', platform: null, rating: 5, source_rating: 4.5, body: '좋아요, "정말"\n두 줄', created_at: '2025-12-07T15:00:00Z', source_review_id: null, moderation_status: 'visible' },
    { kakao_place_id: '1', source: 'app', platform: null, rating: 3, source_rating: null, body: null, created_at: '2026-06-13T05:15:00Z', source_review_id: null, moderation_status: 'hidden' },
  ]
  it('writes Korean time and the original half star, with a BOM for Excel', () => {
    const csv = reviewExportCsv(stored)
    expect(csv.charCodeAt(0)).toBe(0xfeff)
    expect(csv).toContain('2025-12-08T00:00:00+09:00')
    expect(csv).toContain(',4.5,')
    expect(kstIso('garbage')).toBe('')
  })
  it('an exported file imports again: the naver row round-trips exactly, the app row is skipped', () => {
    const p = parseReviewCsv(reviewExportCsv(stored), NOW)
    expect(p.fatal).toBeNull()
    expect(p.rows[0].row).toMatchObject({ source: 'naver', rating: '4.5', body: '좋아요, "정말"\n두 줄', reviewed_at: '2025-12-08T00:00:00+09:00' })
    expect(p.rows[1].skip).toBe('app')
  })
  it('the template is just the header and also parses (to nothing)', () => {
    expect(reviewTemplateCsv().charCodeAt(0)).toBe(0xfeff)
    expect(reviewTemplateCsv().slice(1).split(',')[0]).toBe('kakao_place_id')
    expect(parseReviewCsv(reviewTemplateCsv(), NOW)).toMatchObject({ fatal: null, rows: [] })
  })
})
