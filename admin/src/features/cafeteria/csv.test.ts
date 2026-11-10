import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { decodeProblem, normalizeDate, normalizeMeal, normalizePrice, normalizeProgram, normalizeRow, normalizeTime, parseCsv, REQUIRED, TEMPLATE_CSV, TEMPLATE_HEADER, toRpcRow, toTable } from './csv'

describe('parseCsv', () => {
  it('reads Korean text, with and without a UTF-8 BOM', () => {
    expect(parseCsv('대학교,식당\n순천향대학교,학생식당\n')).toEqual([['대학교', '식당'], ['순천향대학교', '학생식당']])
    expect(parseCsv('\uFEFF대학교,식당\n순천향대학교,학생식당')[0][0]).toBe('대학교')
  })
  it('handles quotes, commas and line breaks inside quotes, doubled quotes, CRLF and CR', () => {
    expect(parseCsv('a,b\r\n"비빔밥, 국","그는 ""좋다""고 말했다"\r\n"두 줄\n메뉴",x\r')).toEqual([['a', 'b'], ['비빔밥, 국', '그는 "좋다"고 말했다'], ['두 줄\n메뉴', 'x']])
  })
  it('skips blank lines, keeps empty cells, and reads a file without a final newline', () => {
    expect(parseCsv('a,b,c\n\n1,,3\n,,\n4,5,6')).toEqual([['a', 'b', 'c'], ['1', '', '3'], ['4', '5', '6']])
  })
  it('accepts tab-separated text (copied from a spreadsheet)', () => {
    expect(parseCsv('a\tb\n1\t2')).toEqual([['a', 'b'], ['1', '2']])
  })
  it('warns about text that was not UTF-8', () => expect(decodeProblem('�����')).toMatch(/UTF-8/))
})

describe('headers', () => {
  it('maps English and Korean headers and lists what is missing or unknown', () => {
    const t = toTable(parseCsv('대학교,식당,날짜,식사,메뉴,가격,이용시간,기타\nA,B,2026-11-09,조식,x,1,08:00-09:00,?'))
    expect(t.missing).toEqual([])
    expect(t.unknown).toEqual(['기타'])
    expect(t.rows[0].cells).toMatchObject({ university: 'A', cafeteria_name: 'B', date: '2026-11-09', meal_type: '조식', menu_name: 'x', price: '1', serving_time: '08:00-09:00' })
    expect(toTable(parseCsv('university,date\nA,B')).missing).toEqual(['cafeteria_name', 'meal_type', 'menu_name', 'price', 'serving_time'])
  })
  it('numbers rows the way a spreadsheet does (the header is line 1)', () => {
    const t = toTable(parseCsv(`${TEMPLATE_HEADER}\nA,B,2026-11-09,lunch,x,1,\n\nA,B,2026-11-10,lunch,y,1,\n`))
    expect(t.rows.map((r) => r.line)).toEqual([2, 3])
  })
})

describe('normalising values', () => {
  it('dates: several separators, real calendar dates only', () => {
    expect(normalizeDate('2026-11-09')).toBe('2026-11-09')
    expect(normalizeDate('2026.11.9')).toBe('2026-11-09')
    expect(normalizeDate('2026/1/5')).toBe('2026-01-05')
    expect(normalizeDate('2026-02-30')).toBeNull()
    expect(normalizeDate('2026-13-01')).toBeNull()
    expect(normalizeDate('11/09/2026')).toBeNull()
    expect(normalizeDate('')).toBeNull()
  })
  it('meal types: English and Korean, nothing else', () => {
    expect(['조식', '아침', 'Breakfast', '중식', '점심', 'LUNCH', '석식', '저녁', 'dinner'].map(normalizeMeal)).toEqual(['breakfast', 'breakfast', 'breakfast', 'lunch', 'lunch', 'lunch', 'dinner', 'dinner', 'dinner'])
    expect(normalizeMeal('브런치')).toBeNull()
  })
  it('prices: thousands separators and 원 are fine, unknown stays unknown, junk is refused', () => {
    expect([normalizePrice('5500'), normalizePrice('5,500'), normalizePrice('5,500원'), normalizePrice('')]).toEqual([5500, 5500, 5500, null])
    expect([normalizePrice('-5'), normalizePrice('abc'), normalizePrice('5.5')]).toEqual([undefined, undefined, undefined])
  })
  it('serving time: several dashes, one-digit hours; the end must follow the start', () => {
    expect(normalizeTime('11:30-13:30')).toEqual({ start: '11:30', end: '13:30' })
    expect(normalizeTime('8:00 ~ 9:30')).toEqual({ start: '08:00', end: '09:30' })
    expect(normalizeTime('')).toEqual({ start: null, end: null })
    expect([normalizeTime('14:00-13:00'), normalizeTime('11:30'), normalizeTime('25:00-26:00')]).toEqual([undefined, undefined, undefined])
  })
  it('the programme name 천원의 아침밥 is recognised in its common spellings', () => {
    expect(['천원의 아침밥', '천원의아침밥', '1000won'].map(normalizeProgram)).toEqual(['천원의 아침밥', '천원의 아침밥', '천원의 아침밥'])
    expect(normalizeProgram('')).toBe('')
  })
})

describe('rows', () => {
  const row = (cells: Record<string, string>) => normalizeRow({ line: 2, cells: { university: 'U', cafeteria_name: 'C', date: '2026-11-09', meal_type: '점심', menu_name: '제육', price: '5,500', serving_time: '11:30-13:30', ...cells } })
  it('a good row is normalised', () => {
    const r = row({ meal_option: 'A코너', menu_items: '밥| 국 |김치', program: '' })
    expect(r.errors).toEqual([])
    expect(r).toMatchObject({ meal_type: 'lunch', price: '5500', start_time: '11:30', end_time: '13:30', meal_option: 'A코너', menu_items: ['밥', '국', '김치'] })
  })
  it('reports every problem the browser can see', () => {
    const r = row({ date: '2026-02-30', meal_type: '브런치', price: '-1', serving_time: '14:00-13:00', menu_name: '', university: '' })
    expect(r.errors.join('|')).toMatch(/university/)
    expect(r.errors.join('|')).toMatch(/menu_name/)
    expect(r.errors.join('|')).toMatch(/날짜/)
    expect(r.errors.join('|')).toMatch(/식사 종류/)
    expect(r.errors.join('|')).toMatch(/가격/)
    expect(r.errors.join('|')).toMatch(/이용 시간/)
  })
  it('stable ids replace the names', () => {
    expect(row({ university: '', university_id: 'u-1', cafeteria_name: '', cafeteria_id: 'c-1' }).errors).toEqual([])
  })
  it('an empty price or time is allowed here (the server reports it as a warning)', () => {
    expect(row({ price: '', serving_time: '' }).errors).toEqual([])
  })
  it('what is sent to the server: empty optional values are absent', () => {
    const sent = toRpcRow(row({}))
    expect(sent).toMatchObject({ university: 'U', cafeteria_id: null, program: null, description: null, source_url: null, menu_items: [], meal_option: '' })
  })
})

describe('the example template', () => {
  const t = toTable(parseCsv(TEMPLATE_CSV))
  it('has every required column and parses without errors', () => {
    expect(REQUIRED.every((c) => TEMPLATE_HEADER.split(',').includes(c))).toBe(true)
    expect(t.missing).toEqual([]); expect(t.unknown).toEqual([])
    expect(t.rows.map((r) => normalizeRow(r).errors)).toEqual([[], [], [], [], []])
  })
  it('shows a breakfast programme, two options at lunch, a quoted cell with a comma, and two universities', () => {
    const rows = t.rows.map(normalizeRow)
    expect(rows[0]).toMatchObject({ meal_type: 'breakfast', program: '천원의 아침밥', price: '1000' })
    expect(rows.filter((r) => r.meal_type === 'lunch' && r.university === '순천향대학교').map((r) => r.meal_option)).toEqual(['A코너', 'B코너'])
    expect(rows[4].menu_name).toBe('비빔밥, 국 세트')
    expect(new Set(rows.map((r) => r.university)).size).toBe(2)
  })
  it('is the same file that ships in the repository for download', () => {
    expect(readFileSync(join(process.cwd(), '..', 'supabase', 'cafeteria', 'weekly_import_template.csv'), 'utf8').replace(/^\uFEFF/, '')).toBe(TEMPLATE_CSV)
  })
})
