import { describe, expect, it } from 'vitest'
import { buildMenuCsv, EXPORT_COLUMNS, guardCell, MAX_ROWS, normalizeText, parseBool, parseMenuCsv, parsePrice, TEMPLATE_COLUMNS, templateCsv, unguardCell } from './menuCsv'

const HEAD = 'kakao_place_id,restaurant_name,menu_name,price_krw,menu_category,description,is_available'
const csv = (...lines: string[]) => [HEAD, ...lines].join('\n')

describe('template', () => {
  it('has exactly the seven columns, in order, and no invented menus or prices', () => {
    expect([...TEMPLATE_COLUMNS]).toEqual(['kakao_place_id', 'restaurant_name', 'menu_name', 'price_krw', 'menu_category', 'description', 'is_available'])
    expect(templateCsv().replace('﻿', '')).toBe(`${HEAD}\r\n`)
    expect(templateCsv().split(/\r?\n/).filter(Boolean)).toHaveLength(1) // the header only
  })
  it('starts with a BOM so Excel opens it as UTF-8, and parses back as an empty, valid file', () => {
    expect(templateCsv().charCodeAt(0)).toBe(0xfeff)
    const p = parseMenuCsv(templateCsv())
    expect(p.fatal).toBeNull()
    expect(p.rows).toEqual([])
  })
})

describe('parsing: encoding and quoting', () => {
  it('reads UTF-8 with and without a BOM identically', () => {
    const body = csv('1001,어굿플레이스,제육 정식,9000,식사,,true')
    const a = parseMenuCsv(body)
    const b = parseMenuCsv('﻿' + body)
    expect(b.rows).toEqual(a.rows)
    expect(a.rows[0]).toMatchObject({ kakaoPlaceId: '1001', restaurantName: '어굿플레이스', menuName: '제육 정식', price: 9000, category: '식사', available: true })
    expect(a.rows[0].errors).toEqual([])
  })

  it('keeps commas, quotes and line breaks inside quoted cells, and Korean text, intact', () => {
    const p = parseMenuCsv(csv('1001,"카페, 어굿","김치찌개, 된장찌개 세트",12000,식사,"국물이 ""진한"" 맛\n두 줄 설명",true'))
    expect(p.rows).toHaveLength(1)
    expect(p.rows[0].restaurantName).toBe('카페, 어굿')
    expect(p.rows[0].menuName).toBe('김치찌개, 된장찌개 세트')
    expect(p.rows[0].description).toBe('국물이 "진한" 맛\n두 줄 설명')
    expect(p.rows[0].errors).toEqual([])
  })

  it('normalises decomposed Korean (what macOS produces) to the same text as typed Korean', () => {
    const nfd = '제육 정식'.normalize('NFD')
    expect(nfd).not.toBe('제육 정식')
    expect(parseMenuCsv(csv(`1001,,${nfd},,,,`)).rows[0].menuName).toBe('제육 정식')
  })

  it('accepts CRLF line endings and ignores blank lines but keeps the file\'s own line numbers', () => {
    const p = parseMenuCsv(`${HEAD}\r\n1001,,국수,5000,,,\r\n\r\n1001,,우동,6000,,,\r\n`)
    expect(p.rows.map((r) => [r.line, r.menuName])).toEqual([[2, '국수'], [4, '우동']])
  })

  it('a row with too many cells (an unquoted comma) or an unclosed quote is flagged on that row', () => {
    const p = parseMenuCsv(csv('1001,,국수,5000,,,true', '1001,,김치,찌개,5000,,,true,extra,extra', '1001,,"안 닫힌 따옴표,5000,,,true'))
    expect(p.rows[0].errors).toEqual([])
    expect(p.rows[1].errors.join(' ')).toMatch(/열이 \d+개인데 머리글은 7개/)
  })

  it('an unquoted comma can never shift a value into the wrong column unnoticed', () => {
    // "김치,찌개" -> 8 cells: the price would have been read from the wrong cell
    const p = parseMenuCsv(csv('1001,어굿,김치,찌개,5000,식사,설명,true'))
    expect(p.rows[0].errors.join(' ')).toMatch(/큰따옴표/)
    // a harmless trailing comma is fine
    expect(parseMenuCsv(csv('1001,어굿,국수,5000,식사,설명,true,')).rows[0].errors).toEqual([])
  })

  it('an unclosed quote is reported', () => {
    const p = parseMenuCsv(csv('1001,,"안 닫힌 따옴표,5000,,,true'))
    expect(p.rows.length === 0 || p.rows[0].errors.length > 0).toBe(true)
    expect(p.rows.flatMap((r) => r.errors).join(' ')).toMatch(/큰따옴표/)
  })
})

describe('parsing: headers', () => {
  it('reports every missing column and refuses the file', () => {
    const p = parseMenuCsv('kakao_place_id,menu_name\n1,국수')
    expect(p.fatal).toContain('restaurant_name')
    expect(p.fatal).toContain('price_krw')
    expect(p.rows).toEqual([])
  })
  it('column order, case and surrounding spaces do not matter', () => {
    const p = parseMenuCsv(' MENU_NAME , Kakao_Place_ID ,price_krw,restaurant_name,menu_category,description,is_available\n국수,1001,5000,,,,')
    expect(p.fatal).toBeNull()
    expect(p.rows[0]).toMatchObject({ kakaoPlaceId: '1001', menuName: '국수', price: 5000 })
  })
  it('extra columns are ignored (and listed); menu_id and menu_status are known optional columns', () => {
    const p = parseMenuCsv(`${HEAD},menu_id,menu_status,memo,error\n1001,,국수,5000,,,,aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa,active,내 메모,x`)
    expect(p.ignoredColumns).toEqual(['memo', 'error'])
    expect(p.rows[0].menuId).toBe('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
  })
  it('a repeated column name is refused', () => {
    expect(parseMenuCsv(`${HEAD},menu_name\n1001,,국수,5000,,,,x`).fatal).toMatch(/같은 열 이름/)
  })
  it('an empty file or a semicolon-separated one is refused with a useful message', () => {
    expect(parseMenuCsv('').fatal).toMatch(/빈 파일/)
    expect(parseMenuCsv('   \n  ').fatal).toMatch(/빈 파일/)
    expect(parseMenuCsv(HEAD.replace(/,/g, ';') + '\n1;;국수;5000;;;').fatal).toMatch(/쉼표/)
  })
  it('a file that was not saved as UTF-8 (broken characters) is refused instead of importing garbage', () => {
    expect(parseMenuCsv(csv('1001,,\uFFFD\uFFFD 정식,5000,,,')).fatal).toMatch(/UTF-8/)
  })
  it('a file with too many rows is refused', () => {
    const rows = Array.from({ length: MAX_ROWS + 1 }, (_, i) => `1001,,메뉴${i},,,,`)
    expect(parseMenuCsv(csv(...rows)).fatal).toMatch(/나눠/)
  })
})

describe('prices', () => {
  it('blank stays unknown (null), never 0; an explicit 0 is 0', () => {
    expect(parsePrice('')).toEqual({ value: null })
    expect(parsePrice('   ')).toEqual({ value: null })
    expect(parsePrice('0')).toEqual({ value: 0 })
  })
  it('plain integers, thousands separators and a trailing 원 are accepted', () => {
    expect(parsePrice('7000').value).toBe(7000)
    expect(parsePrice('7,000').value).toBe(7000)
    expect(parsePrice(' 7,000원 ').value).toBe(7000)
    expect(parsePrice('2147483647').value).toBe(2147483647)
  })
  it('negative, decimal, scientific, text and out-of-range prices are errors (nothing is guessed)', () => {
    for (const bad of ['-1', '7.5', '7000.0', '1e3', '약 7000', '무료', '2147483648', '99999999999999999999']) expect(parsePrice(bad).error, bad).toBeTruthy()
  })
  it('a blank price cell becomes null on the row; a bad one is a row error', () => {
    const p = parseMenuCsv(csv('1001,,국수,,,,', '1001,,우동,abc,,,'))
    expect(p.rows[0].price).toBeNull()
    expect(p.rows[0].errors).toEqual([])
    expect(p.rows[1].errors.join(' ')).toMatch(/가격은 0 이상의 정수/)
  })
})

describe('is_available', () => {
  it('true/false in the usual spellings, blank = not stated', () => {
    for (const t of ['true', 'TRUE', '1', 'yes', 'Y', '예', '판매']) expect(parseBool(t).value, t).toBe(true)
    for (const f of ['false', 'FALSE', '0', 'no', 'N', '아니오', '품절']) expect(parseBool(f).value, f).toBe(false)
    expect(parseBool('')).toEqual({ value: null })
  })
  it('anything else is an error, not silently true', () => {
    expect(parseBool('maybe').error).toBeTruthy()
    expect(parseBool('2').error).toBeTruthy()
  })
})

describe('row validation', () => {
  it('menu_name is required; lengths are limited', () => {
    const long = 'ㄱ'.repeat(121)
    const p = parseMenuCsv(csv('1001,,,5000,,,', `1001,,${long},,,,`, `1001,,국수,,${'ㅂ'.repeat(31)},,`, `1001,,국수2,,,${'ㅅ'.repeat(501)},`))
    expect(p.rows[0].errors.join(' ')).toMatch(/menu_name/)
    expect(p.rows[1].errors.join(' ')).toMatch(/120자/)
    expect(p.rows[2].errors.join(' ')).toMatch(/30자/)
    expect(p.rows[3].errors.join(' ')).toMatch(/500자/)
  })
  it('menu_id must be a uuid (stored lower-case)', () => {
    const p = parseMenuCsv(`${HEAD},menu_id\n1001,,국수,,,,,not-a-uuid\n1001,,우동,,,,,AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA`)
    expect(p.rows[0].errors.join(' ')).toMatch(/menu_id 형식/)
    expect(p.rows[1].errors).toEqual([])
    expect(p.rows[1].menuId).toBe('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
  })
  it('a Kakao id a spreadsheet turned into scientific notation is caught, not imported as a wrong id', () => {
    const p = parseMenuCsv(csv('1.77657E+09,,국수,,,,'))
    expect(p.rows[0].errors.join(' ')).toMatch(/지수 형식/)
  })
})

describe('export formatting and round trip', () => {
  it('export columns = the template plus menu_id and menu_status', () => {
    expect([...EXPORT_COLUMNS]).toEqual([...TEMPLATE_COLUMNS, 'menu_id', 'menu_status'])
  })
  it('writes prices as plain integers, a blank price as an empty cell (not 0), booleans as true/false', () => {
    const out = buildMenuCsv([
      { kakao_place_id: '1001', restaurant_name: '어굿', menu_name: '국수', price_krw: 7000, menu_category: '면류', description: '', is_available: true, menu_id: 'id1', menu_status: 'active' },
      { kakao_place_id: '1001', restaurant_name: '어굿', menu_name: '우동', price_krw: null, menu_category: '', description: '', is_available: false, menu_id: 'id2', menu_status: 'active' },
    ]).replace('﻿', '').split('\r\n')
    expect(out[0]).toBe(`${HEAD},menu_id,menu_status`)
    expect(out[1]).toBe('1001,어굿,국수,7000,면류,,true,id1,active')
    expect(out[2]).toBe('1001,어굿,우동,,,,false,id2,active') // no 0
  })
  it('quotes commas, quotes and line breaks, and keeps Korean text', () => {
    const out = buildMenuCsv([{ kakao_place_id: '1', restaurant_name: '카페, 어굿', menu_name: '"특" 제육', price_krw: 1, menu_category: '', description: '두\n줄', is_available: true, menu_id: 'x', menu_status: 'active' }])
    const back = parseMenuCsv(out)
    expect(back.rows[0]).toMatchObject({ restaurantName: '카페, 어굿', menuName: '"특" 제육', description: '두\n줄' })
  })
  it('text that starts like a spreadsheet formula is guarded on export and restored on import', () => {
    expect(guardCell('=SUM(A1)')).toBe("'=SUM(A1)")
    expect(guardCell('-매운맛')).toBe("'-매운맛")
    expect(guardCell('국수')).toBe('국수')
    expect(unguardCell("'=SUM(A1)")).toBe('=SUM(A1)')
    expect(unguardCell("'국수")).toBe("'국수") // an ordinary apostrophe is left alone
    const out = buildMenuCsv([{ kakao_place_id: '1', restaurant_name: 'r', menu_name: '=1+1', price_krw: 5, menu_category: '', description: '@멘션', is_available: true, menu_id: 'x', menu_status: 'active' }])
    expect(out).toContain("'=1+1")
    const back = parseMenuCsv(out).rows[0]
    expect([back.menuName, back.description]).toEqual(['=1+1', '@멘션'])
  })
  it('an exported file imports again to the same rows (prices, Korean text, ids)', () => {
    const rows = [
      { kakao_place_id: '1001', restaurant_name: '어굿플레이스', menu_name: '제육 정식', price_krw: 9000, menu_category: '식사', description: '밥, 국, 반찬', is_available: true, menu_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', menu_status: 'active' },
      { kakao_place_id: '1002', restaurant_name: '라멘집', menu_name: '돈코츠', price_krw: null, menu_category: '면류', description: '', is_available: false, menu_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', menu_status: 'active' },
    ]
    const back = parseMenuCsv(buildMenuCsv(rows))
    expect(back.fatal).toBeNull()
    expect(back.rows.map((r) => [r.kakaoPlaceId, r.menuName, r.price, r.category, r.description, r.available, r.menuId, r.errors.length])).toEqual([
      ['1001', '제육 정식', 9000, '식사', '밥, 국, 반찬', true, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 0],
      ['1002', '돈코츠', null, '면류', '', false, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 0],
    ])
  })
})

describe('normalizeText', () => {
  it('compares names ignoring case, spacing and Unicode form', () => {
    expect(normalizeText('  제육   정식 ')).toBe(normalizeText('제육 정식'))
    expect(normalizeText('Pasta')).toBe(normalizeText('pasta'))
    expect(normalizeText('제육'.normalize('NFD'))).toBe(normalizeText('제육'))
    expect(normalizeText('제육 정식')).not.toBe(normalizeText('제육정식'))
  })
})
