import { describe, expect, it } from 'vitest'
import { buildCsv, parseRestaurantCsv } from './csv'
import { emptyRestaurantForm, fromRow, restaurantSchema, toRow } from './schema'

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
})

describe('CSV', () => {
  const csv = 'kakao_place_id,name_ko,price_min_krw,visibility\nk1,국수집,8000,\nk2,,100,\nk1,중복집,5000,\nk3,숫자오류,abc,published\n'
  it('validates every row and flags duplicates inside the file', () => {
    const rows = parseRestaurantCsv(csv)
    expect(rows).toHaveLength(4)
    expect(rows[0].values?.visibility).toBe('draft') // imports default to draft
    expect(rows[1].values).toBeNull()                // name missing
    expect(rows[2].duplicateInFile).toBe(true)
    expect(rows[3].errors.join()).toContain('price_min_krw')
    expect(rows[0].line).toBe(2)
  })
  it('ignores a UTF-8 BOM', () => expect(parseRestaurantCsv('﻿name_ko\n국수집\n')[0].values?.name_ko).toBe('국수집'))
  it('exports a header plus one line per row', () => {
    const out = buildCsv([{ kakao_place_id: 'k1', name_ko: '국수집', dining_purposes: ['혼밥', '회식'] }])
    expect(out.split(/\r?\n/)).toHaveLength(2)
    expect(out).toContain('"혼밥, 회식"')
  })
})
