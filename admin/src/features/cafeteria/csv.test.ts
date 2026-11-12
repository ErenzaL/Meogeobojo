import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { decodeProblem, isBlankScopedRow, normalizeScopedRow, SCOPED_COLUMNS, SCOPED_REQUIRED, scopedTemplateCsv, normalizeDate, normalizeMeal, normalizePrice, normalizeProgram, normalizeRow, normalizeTime, parseCsv, REQUIRED, TEMPLATE_CSV, TEMPLATE_HEADER, toRpcRow, toTable } from './csv'

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

describe('several dishes per meal', () => {
  const HEAD = 'university,cafeteria_name,date,meal_type,menu_name,side_dishes,soup,rice,kimchi,salad,dessert,shared,origin,labels,labels_verified'
  const row = (csv: string) => normalizeRow(toTable(parseCsv(`${HEAD}\n${csv}`)).rows[0])

  it('reads the Monday lunch of a real menu table as structured dishes in table order', () => {
    const r = row('순천향대학교,향설1관,2026-11-09,중식,치즈닭갈비볶음밥,새우튀김*타르타르/참나물무침/햄감자채볶음/파래무침,계란국,,,,,김치/샐러드/후식차,쌀:국내산 / 배추김치:중국산,,')
    expect(r.errors).toEqual([])
    expect(r.dishes).toEqual([
      { name_ko: '새우튀김*타르타르', kind: 'side' }, { name_ko: '참나물무침', kind: 'side' }, { name_ko: '햄감자채볶음', kind: 'side' }, { name_ko: '파래무침', kind: 'side' },
      { name_ko: '계란국', kind: 'soup' }, { name_ko: '김치', kind: 'kimchi', shared: true }, { name_ko: '샐러드', kind: 'salad', shared: true }, { name_ko: '후식차', kind: 'dessert', shared: true },
    ])
    expect(r.origin).toBe('쌀:국내산 / 배추김치:중국산')
    expect(toRpcRow(r)).toMatchObject({ menu_name: '치즈닭갈비볶음밥', dishes: r.dishes, origin: '쌀:국내산 / 배추김치:중국산', labels: [], labels_verified: null })
  })

  it('accepts | ; and line breaks as separators, uses category columns, and drops a dish repeated in the same row', () => {
    const r = row('A,B,2026-11-09,lunch,밥버거,"우동국\n파래무침|파래무침",,쌀밥,배추김치,,,,,,')
    expect(r.dishes.map((d) => [d.name_ko, d.kind])).toEqual([['우동국', 'side'], ['파래무침', 'side'], ['쌀밥', 'rice'], ['배추김치', 'kimchi']])
  })

  it('a dietary label needs the confirmation column; unknown labels are errors; a confirmed one is sent with its confirmation', () => {
    expect(row('A,B,2026-11-13,lunch,x,,,,,,,,,HALAL,').errors.join()).toContain('labels_verified')
    expect(row('A,B,2026-11-13,lunch,x,,,,,,,,,KOSHER,예').errors.join()).toContain('KOSHER')
    const ok = row('A,B,2026-11-13,lunch,x,,,,,,,,,halal,예')
    expect(ok.errors).toEqual([])
    expect(toRpcRow(ok)).toMatchObject({ labels: ['HALAL'], labels_verified: true })
  })

  it('the older menu_items column still works as a list of side dishes', () => {
    const t = toTable(parseCsv('university,cafeteria_name,date,meal_type,menu_name,price,serving_time,menu_items\nA,B,2026-11-09,lunch,x,1,,우유|과일'))
    expect(normalizeRow(t.rows[0]).dishes).toEqual([{ name_ko: '우유', kind: 'side' }, { name_ko: '과일', kind: 'side' }])
  })
})

describe('the 향설1관 weekly menu table (supabase/cafeteria/examples)', () => {
  const file = readFileSync(join(process.cwd(), '..', 'supabase', 'cafeteria', 'examples', 'hyangseol1_2026-11-09.csv'), 'utf8')
  const rows = toTable(parseCsv(file)).rows.map(normalizeRow)

  it('has 5 days x breakfast / lunch / dinner, all valid, in one cafeteria and one week', () => {
    expect(rows).toHaveLength(15)
    expect(rows.flatMap((r) => r.errors)).toEqual([])
    expect(new Set(rows.map((r) => r.date))).toEqual(new Set(['2026-11-09', '2026-11-10', '2026-11-11', '2026-11-12', '2026-11-13']))
    expect(new Set(rows.map((r) => `${r.date}|${r.meal_type}|${r.meal_option}`)).size).toBe(15)
    expect(new Set(rows.map((r) => r.cafeteria_name))).toEqual(new Set(['향설1관']))
  })

  it("Monday lunch is exactly the menu table's: the main dish, four dishes, the soup, and the shared kimchi / salad / dessert", () => {
    const r = rows.find((x) => x.date === '2026-11-09' && x.meal_type === 'lunch')!
    expect(r.menu_name).toBe('치즈닭갈비볶음밥')
    expect(r.dishes).toEqual([
      { name_ko: '새우튀김*타르타르', kind: 'side' }, { name_ko: '참나물무침', kind: 'side' }, { name_ko: '햄감자채볶음', kind: 'side' }, { name_ko: '파래무침', kind: 'side' },
      { name_ko: '계란국', kind: 'soup' }, { name_ko: '김치', kind: 'kimchi', shared: true }, { name_ko: '샐러드', kind: 'salad', shared: true }, { name_ko: '후식차', kind: 'dessert', shared: true },
    ])
    expect(r.origin).toContain('쌀:국내산')
    expect(r.notes).toBe('상기 메뉴는 재료수급상황에 따라 변경될 수 있습니다')
  })

  it('a table cell holding two dishes ("도시락김/미소장국") becomes two dishes; the shared row differs per meal; no label is claimed', () => {
    const wedBreakfast = rows.find((x) => x.date === '2026-11-11' && x.meal_type === 'breakfast')!
    expect(wedBreakfast.dishes.map((d) => d.name_ko)).toEqual(expect.arrayContaining(['도시락김', '미소장국']))
    expect(rows.find((x) => x.meal_type === 'breakfast')!.dishes.filter((d) => d.shared).map((d) => d.name_ko)).toEqual(['아산쌀밥', '김치', '샐러드'])
    expect(rows.find((x) => x.meal_type === 'dinner')!.dishes.filter((d) => d.shared).map((d) => d.name_ko)).toEqual(['김치', '샐러드'])
    expect(rows.every((r) => r.labels.length === 0)).toBe(true)
  })
})

describe('one cafeteria, one week', () => {
  const scope = { universityId: 'u1', universityName: '순천향대학교', cafeteriaId: 'c1', cafeteriaName: '교직원식당', cafeteriaNames: ['교직원식당', 'Staff Hall'], weekStart: '2026-11-09', periods: ['lunch', 'dinner'] as ('lunch' | 'dinner')[], weekend: false }
  const row = (cells: Record<string, string>, line = 2) => ({ line, cells: cells as never })

  it('needs only the date, the meal and the menu name: no university or cafeteria columns', () => {
    expect([...SCOPED_REQUIRED]).toEqual(['date', 'meal_type', 'menu_name'])
    const t = toTable(parseCsv('date,meal_type,menu_name\n2026-11-09,중식,제육'), SCOPED_REQUIRED)
    expect(t.missing).toEqual([])
    expect(toTable(parseCsv('date,menu_name\n2026-11-09,제육'), SCOPED_REQUIRED).missing).toEqual(['meal_type'])
    // the full importer still wants every column
    expect(toTable(parseCsv('date,meal_type,menu_name\n2026-11-09,중식,제육')).missing).toContain('university')
  })

  it('a row belongs to the cafeteria being edited, whatever the file says or leaves out', () => {
    const r = normalizeScopedRow(row({ date: '2026-11-10', meal_type: '중식', menu_name: '제육볶음', price: '5,500' }), scope)
    expect(r.errors).toEqual([])
    expect(toRpcRow(r)).toMatchObject({ university_id: 'u1', cafeteria_id: 'c1', date: '2026-11-10', meal_type: 'lunch', menu_name: '제육볶음', price: '5500' })
  })

  it('only dates inside the week count (Monday to Sunday)', () => {
    const at = (date: string) => normalizeScopedRow(row({ date, meal_type: '중식', menu_name: 'x' }), scope).errors
    expect(at('2026-11-09')).toEqual([])
    expect(at('2026-11-15')).toEqual([])
    expect(at('2026-11-08')[0]).toMatch(/이 주\(2026-11-09 ~ 2026-11-15\)의 날짜가 아니에요/)
    expect(at('2026-11-16')[0]).toMatch(/날짜가 아니에요/)
    expect(at('2026.11.12')).toEqual([]) // other date spellings are read first, then checked
  })

  it('a row of another cafeteria or university is refused, a matching name (any language) is fine', () => {
    const err = (extra: Record<string, string>) => normalizeScopedRow(row({ date: '2026-11-10', meal_type: '중식', menu_name: 'x', ...extra }), scope).errors
    expect(err({ cafeteria_name: '교직원식당' })).toEqual([])
    expect(err({ cafeteria_name: 'staff hall' })).toEqual([])
    expect(err({ cafeteria_name: '학생식당' })[0]).toMatch(/다른 식당\(학생식당\)의 행이에요/)
    expect(err({ university: '호서대학교' })[0]).toMatch(/다른 대학교\(호서대학교\)의 행이에요/)
    expect(err({ university: '순천향대학교', cafeteria_name: '교직원식당' })).toEqual([])
  })

  it('a cafeteria without a known name does not reject a name column it cannot compare', () => {
    const noName = { ...scope, cafeteriaNames: [] as string[] }
    expect(normalizeScopedRow(row({ date: '2026-11-10', meal_type: '중식', menu_name: 'x', cafeteria_name: '아무거나' }), noName).errors).toEqual([])
  })

  it('the usual row problems are still reported', () => {
    const e = normalizeScopedRow(row({ date: '2026-11-10', meal_type: '간식', menu_name: 'x', price: 'abc' }), scope).errors
    expect(e.some((m) => /식사 종류/.test(m))).toBe(true)
    expect(e.some((m) => /가격/.test(m))).toBe(true)
  })

  it('an unfilled template row is blank (skipped), a half-filled one is not', () => {
    expect(isBlankScopedRow(row({ date: '2026-11-10', meal_type: '석식', menu_name: '', price: '', serving_time: '' }))).toBe(true)
    expect(isBlankScopedRow(row({ date: '2026-11-10', meal_type: '석식', menu_name: '', price: '6000' }))).toBe(false)
    expect(isBlankScopedRow(row({ date: '2026-11-10', meal_type: '석식', menu_name: '비빔밥' }))).toBe(false)
  })

  it('the template has a row per day and served meal for THIS week, nothing else filled in', () => {
    const lines = scopedTemplateCsv(scope).trim().split('\r\n')
    expect(lines[0]).toBe(SCOPED_COLUMNS.join(','))
    expect(lines).toHaveLength(1 + 5 * 2) // Mon-Fri x lunch + dinner
    expect(lines[1].split(',')[0]).toBe('2026-11-09')
    expect(lines[1].split(',')[1]).toBe('중식')
    expect(lines[2].split(',')[1]).toBe('석식')
    expect(lines.at(-1)!.split(',')[0]).toBe('2026-11-13')
    for (const l of lines.slice(1)) { const c = l.split(','); expect(c).toHaveLength(SCOPED_COLUMNS.length); expect(c.slice(2).every((x) => x === '')).toBe(true) }
    expect(scopedTemplateCsv({ ...scope, weekend: true }).trim().split('\r\n')).toHaveLength(1 + 7 * 2)
    expect(scopedTemplateCsv({ ...scope, periods: ['breakfast', 'lunch', 'dinner'] }).trim().split('\r\n')).toHaveLength(1 + 5 * 3)
  })

  it('an unfilled template read back by the browser is entirely blank, so it can never import anything by accident', () => {
    const t = toTable(parseCsv(scopedTemplateCsv(scope)), SCOPED_REQUIRED)
    expect(t.missing).toEqual([])
    expect(t.rows.every(isBlankScopedRow)).toBe(true)
  })
})
