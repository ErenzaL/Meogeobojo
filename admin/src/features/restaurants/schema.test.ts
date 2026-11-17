import { describe, expect, it } from 'vitest'
import { buildCsv, CSV_COLUMNS, ignoredCsvColumns, parseRestaurantCsv, restaurantTemplateCsv } from './csv'
import { emptyRestaurantForm, fromRow, restaurantSchema, snapshotFromForm, toRow } from './schema'

const valid = { ...emptyRestaurantForm, name_ko: '국수집' }

describe('restaurantSchema', () => {
  it('accepts a minimal restaurant', () => expect(restaurantSchema.safeParse(valid).success).toBe(true))
  it('requires a name', () => {
    const r = restaurantSchema.safeParse({ ...valid, name_ko: '  ' })
    expect(r.success).toBe(false)
  })
  it.each([
    [{ price_min_krw: '12a' }, 'price_min_krw'],
    [{ latitude: '95' }, 'latitude'],
    [{ longitude: 'abc' }, 'longitude'],
    [{ last_order_time: '25:99' }, 'last_order_time'],
    [{ image_url: 'http://insecure.example/x.png' }, 'image_url'],
    [{ price_min_krw: '9000', price_max_krw: '5000' }, 'price_max_krw'],
    [{ description: 'x'.repeat(2001) }, 'description'],
  ])('rejects %j', (patch, field) => {
    const r = restaurantSchema.safeParse({ ...valid, ...patch })
    expect(r.success).toBe(false)
    if (!r.success) expect(r.error.issues.some((i) => i.path[0] === field)).toBe(true)
  })
})

describe('toRow / fromRow', () => {
  it('turns blanks into NULL and parses numbers and lists', () => {
    const row = toRow({ ...valid, price_min_krw: '8000', price_max_krw: '12000', dining_purposes: '혼밥, 회식 ,', business_status: '', visibility: 'published' })
    expect(row).toMatchObject({ name_ko: '국수집', kakao_place_id: null, description: null, price_min_krw: 8000, price_max_krw: 12000, dining_purposes: ['혼밥', '회식'], business_status: null, visibility: 'published' })
  })
  it('round-trips a database row', () => {
    const f = fromRow({ name_ko: 'A', kakao_place_id: 'k1', price_min_krw: 9000, last_order_time: '21:30:00', dining_purposes: ['혼밥'], visibility: 'hidden', business_status: 'open' }, ['u1'])
    expect(f).toMatchObject({ name_ko: 'A', kakao_place_id: 'k1', price_min_krw: '9000', last_order_time: '21:30', dining_purposes: '혼밥', visibility: 'hidden', business_status: 'open', university_ids: ['u1'] })
  })
  it('falls back to draft for unknown visibility', () => expect(fromRow({ name_ko: 'A', visibility: 'weird' }, []).visibility).toBe('draft'))
  it('keeps the opening time in opening_hours.open, without wiping other keys', () => {
    expect(restaurantSchema.safeParse({ ...valid, open_time: '24:00' }).success).toBe(false)
    expect(toRow({ ...valid, open_time: '11:00' }).opening_hours).toEqual({ open: '11:00' })
    expect(fromRow({ name_ko: 'A', opening_hours: { open: '11:00:00' } }, []).open_time).toBe('11:00')
    const base = { opening_hours: { note: '일요일 휴무', open: '10:00' } }
    expect(snapshotFromForm({ ...valid, open_time: '11:30' }, base).opening_hours).toEqual({ note: '일요일 휴무', open: '11:30' })
    expect(snapshotFromForm({ ...valid, open_time: '' }, base).opening_hours).toEqual({ note: '일요일 휴무' })
  })
})

describe('CSV', () => {
  const csv = 'kakao_place_id,name_ko,latitude,visibility\nk1,국수집,36.7,\nk2,,36.8,\nk1,중복집,36.9,\nk3,숫자오류,abc,published\n'
  it('validates every row and flags duplicates inside the file', () => {
    const rows = parseRestaurantCsv(csv)
    expect(rows).toHaveLength(4)
    expect(rows[0].values?.visibility).toBe('draft') // imports default to draft
    expect(rows[1].values).toBeNull()                // name missing
    expect(rows[2].duplicateInFile).toBe(true)
    expect(rows[3].errors.join()).toContain('latitude')
    expect(rows[0].line).toBe(2)
  })
  it('ignores a UTF-8 BOM', () => expect(parseRestaurantCsv('﻿name_ko\n국수집\n')[0].values?.name_ko).toBe('국수집'))
  it('exports a header plus one line per row', () => {
    const out = buildCsv([{ kakao_place_id: 'k1', name_ko: '국수집', description: ['혼밥', '회식'] }])
    expect(out.split(/\r?\n/)).toHaveLength(2)
    expect(out).toContain('"혼밥, 회식"')
  })

  const CURRENT = ['kakao_place_id', 'name_ko', 'name_en', 'category', 'address', 'phone', 'latitude', 'longitude', 'description', 'open_time', 'last_order_time', 'break_time', 'image_url', 'visibility']
  const OLD = ['business_status', 'price_min_krw', 'price_max_krw', 'avg_cost_krw', 'dining_purposes']
  const dbRow = { id: 'x', kakao_place_id: 'k1', name_ko: '국수집', name_en: 'Noodle', category: '음식점 > 한식', address: '충남 아산시 1', phone: '041-111-2222', latitude: 36.77, longitude: 126.93, description: '설명, 쉼표 포함', image_url: 'https://x/a.png', visibility: 'published', featured: true, display_order: 3,
    break_time: '15:00-17:00', last_order_time: '21:30:00', business_status: 'open', price_min_krw: 5000, price_max_krw: 9000, avg_cost_krw: 7000, dining_purposes: ['혼밥'], opening_hours: { open: '11:00' } }
  it('the export, the template and the import share one column list: exactly the current fields', () => {
    expect([...CSV_COLUMNS]).toEqual(CURRENT)
    const header = (t: string) => t.replace('\uFEFF', '').split(/\r?\n/)[0].split(',')
    expect(header(buildCsv([dbRow]))).toEqual(CURRENT)
    expect(header(restaurantTemplateCsv())).toEqual(CURRENT)
    expect(restaurantTemplateCsv().startsWith('\uFEFF')).toBe(true)
  })
  it('the old columns never appear in a download, even though the database rows still carry them', () => {
    const out = buildCsv([dbRow])
    for (const c of OLD) expect(out).not.toContain(c)
    expect(out).not.toContain('혼밥')
  })
  it('the hours are exported as the form shows them: opening_hours.open and the last order as HH:MM', () => {
    const line = buildCsv([dbRow]).split(/\r?\n/)[1]
    expect(line).toContain(',11:00,21:30,15:00-17:00,')
  })
  it('an exported file imports again: every row valid, same values, drafts unless the file says otherwise', () => {
    const rows = parseRestaurantCsv('\uFEFF' + buildCsv([dbRow, { ...dbRow, kakao_place_id: 'k2', name_ko: '직접 등록', category: null, phone: null, latitude: null, longitude: null, visibility: 'draft' }]))
    expect(rows.map((r) => r.errors)).toEqual([[], []])
    expect(rows[0].values).toMatchObject({ kakao_place_id: 'k1', name_ko: '국수집', name_en: 'Noodle', category: '음식점 > 한식', address: '충남 아산시 1', phone: '041-111-2222', latitude: '36.77', longitude: '126.93', description: '설명, 쉼표 포함', image_url: 'https://x/a.png', visibility: 'published' })
    expect(rows[1].values).toMatchObject({ name_ko: '직접 등록', latitude: '', visibility: 'draft' })
    expect(rows.every((r) => !r.duplicateInFile)).toBe(true)
  })
  it('the template is a valid empty import', () => { expect(parseRestaurantCsv(restaurantTemplateCsv())).toEqual([]) })
  it('an older export (with the removed columns) still imports; those columns are ignored and reported', () => {
    const head = [...CURRENT.slice(0, 9), ...OLD, ...CURRENT.slice(9)]
    const old = head.join(',') + '\n' + head.map((h) => ({ kakao_place_id: 'k9', name_ko: '옛 파일 식당', business_status: 'open', price_min_krw: '5000', image_url: 'https://x/b.png', visibility: 'draft' } as Record<string, string>)[h] ?? '').join(',') + '\n'
    const rows = parseRestaurantCsv(old)
    expect(rows[0].errors).toEqual([])
    expect(rows[0].values).toMatchObject({ kakao_place_id: 'k9', name_ko: '옛 파일 식당', image_url: 'https://x/b.png' })
    expect(rows[0].values?.business_status).toBe('')
    expect(rows[0].values?.price_min_krw).toBe('')
    expect(ignoredCsvColumns(old)).toEqual(OLD)
    expect(ignoredCsvColumns(restaurantTemplateCsv())).toEqual([])
  })
})
