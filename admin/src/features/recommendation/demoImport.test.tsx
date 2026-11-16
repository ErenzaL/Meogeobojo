import { QueryClientProvider } from '@tanstack/react-query'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import DemoFeaturesImport from './DemoFeaturesImport'
import FIXTURE from './__fixtures__/demo_features.csv?raw'
import { normalizeTime, parseDemoCsv } from './demoImport'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const HEAD = 'kakao_place_id,name_ko,restaurant_category_demo,open_time_demo,last_order_time_demo,break_time_demo,no_break_time_demo,parking_demo,local_currency_demo,fast_turnover_demo,takeout_demo,open_late_demo,demo_data,source'
const csv = (...lines: string[]) => [HEAD, ...lines].join('\n')

describe('parsing the synthetic demo file', () => {
  const p = parseDemoCsv(FIXTURE)
  it('reads all 168 rows; every row is valid and marked demo data', () => {
    expect(p.fatal).toBeNull()
    expect(p.rows).toHaveLength(168)
    expect(p.rows.every((r) => r.row !== null)).toBe(true)
    expect(p.rows.every((r) => r.row!.demo_data === true)).toBe(true)
    expect(new Set(p.rows.map((r) => r.row!.kakao_place_id)).size).toBe(168)
  })
  it('normalises times ("9:00" -> "09:00") and keeps the flags as booleans', () => {
    const first = p.rows[0].row!
    expect(first).toMatchObject({ kakao_place_id: '1046337753', open_time: '09:00', last_order_time: '21:30', no_break_time: true, parking: false, takeout: true })
    expect(p.rows.filter((r) => r.row!.parking === true)).toHaveLength(52)
    expect(p.rows.filter((r) => r.row!.break_time === '15:00-17:00')).toHaveLength(33)
  })
  it('never imports coordinates, visibility or the menu statistics, and says why', () => {
    const cols = p.ignored.map((x) => x.column)
    for (const c of ['latitude', 'longitude', 'visibility', 'meal_under_8000_demo', 'meal_under_10000_demo', 'lowest_classified_meal_price_krw']) expect(cols).toContain(c)
    expect(p.ignored.find((x) => x.column === 'latitude')!.reason).toMatch(/카카오 실시간 좌표/)
    for (const r of p.rows) expect(Object.keys(r.row!)).not.toEqual(expect.arrayContaining(['latitude']))
  })
})

describe('validation', () => {
  it('a file without a demo_data column is refused (it is not a demo file)', () => {
    expect(parseDemoCsv('kakao_place_id,name_ko\n1,A\n').fatal).toMatch(/demo_data/)
    expect(parseDemoCsv('name_ko\nA\n').fatal).toMatch(/kakao_place_id/)
  })
  it('a row that is not marked TRUE as demo data, a bad id, time or flag are errors with the reason', () => {
    const p = parseDemoCsv(csv('1,A,,09:00,21:00,,TRUE,TRUE,FALSE,FALSE,TRUE,FALSE,FALSE,', 'abc,B,,09:00,21:00,,TRUE,,,,,,TRUE,', '3,C,,25:00,21:00,,TRUE,,,,,,TRUE,', '4,D,,09:00,21:00,,maybe,,,,,,TRUE,', '5,E,,09:00,21:00,lunch,TRUE,,,,,,TRUE,'))
    expect(p.rows.map((r) => r.row === null)).toEqual([true, true, true, true, true])
    expect(p.rows[0].errors.join()).toMatch(/demo_data가 TRUE가 아니에요/)
    expect(p.rows[1].errors.join()).toMatch(/kakao_place_id 형식/)
    expect(p.rows[2].errors.join()).toMatch(/open_time_demo/)
    expect(p.rows[3].errors.join()).toMatch(/no_break_time_demo/)
    expect(p.rows[4].errors.join()).toMatch(/break_time_demo/)
  })
  it('a repeated id is flagged, blank flags stay unknown (null), never false', () => {
    const p = parseDemoCsv(csv('7,A,,,,,,,,,,,TRUE,', '7,B,,,,,,,,,,,TRUE,'))
    expect(p.rows[0].row).toMatchObject({ parking: null, takeout: null, open_time: null })
    expect(p.rows[1].duplicate).toBe(true)
  })
  it('normalizeTime', () => {
    const e: string[] = []
    expect([normalizeTime('9:00', 't', e), normalizeTime('09:05:00', 't', e), normalizeTime('', 't', e)]).toEqual(['09:00', '09:05', null])
    expect(e).toEqual([])
  })
})

const file = (text: string) => new File([text], 'demo.csv', { type: 'text/csv' })
beforeEach(() => {
  fake.reset(); fake.signInAs('admin')
  fake.respond('recommendation_demo_features:select', { data: null, count: 3 })
  fake.respond('restaurant_overrides:select', { data: [{ kakao_place_id: '1046337753' }, { kakao_place_id: '382170960' }] })
})

describe('the admin import', () => {
  const renderIt = () => render(<QueryClientProvider client={makeQueryClient()}><DemoFeaturesImport /></QueryClientProvider>)

  it('says the data is simulated, previews the counts and the ignored columns, and writes nothing until confirmed', async () => {
    renderIt()
    const card = screen.getByLabelText('추천 데모 데이터')
    expect(card.textContent).toMatch(/가상/)
    await userEvent.upload(screen.getByTestId('demo-csv-input'), file(FIXTURE))
    const s = await screen.findByLabelText('데모 가져오기 미리보기')
    expect(s.textContent).toMatch(/전체 168줄/)
    expect(s.textContent).toMatch(/저장할 수 있는 줄 168/)
    expect(s.textContent).toMatch(/오류 0/)
    expect(s.textContent).toMatch(/식당 목록에 없는 장소 ID 166곳/)
    expect(s.textContent).toMatch(/latitude.*좌표는 저장하지 않아요/)
    expect(fake.calls.filter((c) => c.op !== 'select')).toHaveLength(0)
  })

  it('saves ONLY into the demo table (upsert on the Kakao id) and never touches restaurants, menus, photos or visibility', async () => {
    renderIt()
    await userEvent.upload(screen.getByTestId('demo-csv-input'), file(FIXTURE))
    await userEvent.click(await screen.findByRole('button', { name: /데모 데이터 168곳 저장/ }))
    await waitFor(() => expect(screen.getByText(/데모 데이터 168곳을 저장했어요/)).toBeTruthy())
    const writes = fake.calls.filter((c) => c.op !== 'select')
    expect(writes.map((c) => c.table)).toEqual(['recommendation_demo_features'])
    expect(writes[0].op).toBe('upsert')
    expect((writes[0].payload as unknown[]).length).toBe(168)
    expect(writes[0].filters.some((f) => f[0] === 'upsert')).toBe(false)
    expect(fake.rpcs.filter((r) => /cms_/.test(r.name))).toHaveLength(0)
  })

  it('the clear button deletes from the demo table only, after a confirmation', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true)
    renderIt()
    await screen.findByText(/현재 저장된 데모 데이터: 3곳/)
    await userEvent.click(screen.getByRole('button', { name: '데모 데이터 모두 지우기' }))
    await waitFor(() => expect(fake.calls.some((c) => c.op === 'delete')).toBe(true))
    expect(fake.calls.filter((c) => c.op !== 'select').map((c) => c.table)).toEqual(['recommendation_demo_features'])
    await within(document.body).findByText('데모 데이터를 모두 지웠어요.')
  })

  it('a file that is not demo data is refused with an explanation', async () => {
    renderIt()
    await userEvent.upload(screen.getByTestId('demo-csv-input'), file('kakao_place_id,name_ko\n1,A\n'))
    expect((await screen.findByRole('alert')).textContent).toMatch(/데모\) 데이터 전용/)
  })
})
