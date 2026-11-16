import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fake } from '@/test/fakeSupabase'
import FIXTURE from './__fixtures__/restaurants_168.csv?raw'
import RestaurantCsvImport from './RestaurantCsvImport'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const HOST = 'x.supabase.co'
const HEAD = 'kakao_place_id,name_ko,name_en,category,address,phone,latitude,longitude,description,break_time,price_min_krw,price_max_krw,image_url,visibility'
const csv = (...lines: string[]) => [HEAD, ...lines].join('\n')
const file = (text: string) => new File([text], 'restaurants.csv', { type: 'text/csv' })

type Row = { id: string; kakao_place_id: string; name_ko: string; visibility: string; category: string | null; address: string | null; description: string | null; image_url: string | null }
let db: Row[] = []
let revision: Record<string, number> = {}
type Call = { filters: [string, ...unknown[]][] }
const saves = () => fake.rpcs.filter((r) => r.name === 'cms_save_draft').map((r) => r.args as { p_type: string; p_id: string; p_data: Record<string, unknown>; p_expected_revision: number })
const writes = () => [...saves(), ...fake.calls.filter((c) => c.op !== 'select')]

beforeEach(() => {
  vi.stubEnv('VITE_SUPABASE_URL', `https://${HOST}`)
  fake.reset(); fake.signInAs('admin')
  db = [
    { id: 'id-1', kakao_place_id: '1001', name_ko: '있는 식당', visibility: 'published', category: null, address: null, description: '내 설명', image_url: null },
    { id: 'id-2', kakao_place_id: '1002', name_ko: '그대로 식당', visibility: 'published', category: '음식점 > 한식', address: '주소', description: null, image_url: null },
  ]
  revision = {}
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
  fake.respond('restaurant_overrides:select', (c: Call) => {
    const inn = c.filters.find((f) => f[0] === 'in' && f[1] === 'kakao_place_id')
    const eq = c.filters.find((f) => f[0] === 'eq' && f[1] === 'kakao_place_id')
    const rows = db.filter((r) => (inn ? (inn[2] as string[]).includes(r.kakao_place_id) : eq ? r.kakao_place_id === eq[2] : true))
    return { data: rows.map((r) => ({ ...r, name_en: null, phone: null, latitude: null, longitude: null })) }
  })
  fake.respond('content_drafts:select', { data: [] })
  fake.respond('restaurant_photos:select', { data: [] })
  fake.respond('rpc:cms_state', (a: unknown) => {
    const x = a as { p_type: string; p_id: string }
    const r = db.find((d) => d.id === x.p_id)!
    const live = x.p_type === 'restaurant'
      ? { name_ko: r.name_ko, name_en: null, category: r.category, address: r.address, phone: null, latitude: null, longitude: null, description: r.description, visibility: r.visibility, featured: true, display_order: 2, university_ids: ['u1'] }
      : { photos: [] }
    return { data: { live, live_version: 1, last_published: null, draft: revision[`${x.p_type}:${x.p_id}`] ? { data: live, revision: revision[`${x.p_type}:${x.p_id}`] } : null, jobs: [] } }
  })
  fake.respond('rpc:cms_save_draft', (a: unknown) => {
    const x = a as { p_type: string; p_id: string }
    const k = `${x.p_type}:${x.p_id}`; revision[k] = (revision[k] ?? 0) + 1
    return { data: { revision: revision[k], base_version: 1, updated_at: 'now' } }
  })
  fake.respond('restaurant_overrides:upsert', (c: { payload?: unknown }) => {
    const rows = c.payload as { kakao_place_id: string; name_ko: string; visibility: string }[]
    const fresh = rows.filter((r) => !db.some((d) => d.kakao_place_id === r.kakao_place_id))
    const made = fresh.map((r, i) => ({ id: `new-${i}`, kakao_place_id: r.kakao_place_id }))
    return { data: made }
  })
})

async function open(text: string) {
  const onClose = vi.fn()
  render(<RestaurantCsvImport onClose={onClose} />)
  const d = await screen.findByRole('dialog', { hidden: true })
  await userEvent.upload(within(d).getByLabelText('CSV 파일 선택'), file(text))
  return { d, onClose }
}
const summary = (d: HTMLElement) => within(d).findByLabelText('가져오기 미리보기 요약')

describe('식당 CSV 가져오기', () => {
  it('an existing restaurant is an update target, not a duplicate error; the default mode is 빈 정보만 채우기; the preview writes nothing', async () => {
    const { d } = await open(csv(
      '1001,있는 식당,,음식점 > 한식,충남 아산시,,,,CSV 설명,15:00-17:00,5000,9000,,draft', // exists: category + address missing; description present; legacy columns filled
      '1002,그대로 식당,,,,,,,,,,,,published', // exists: nothing to add
      '1003,새 식당,,음식점 > 중식,,,,,,,,,,published',
    ))
    const s = await summary(d)
    expect((within(d).getByRole('radio', { name: /빈 정보만 채우기/ }) as HTMLInputElement).checked).toBe(true)
    expect(s.textContent).toMatch(/전체 3줄/)
    expect(s.textContent).toMatch(/이미 있는 식당 2곳/)
    expect(s.textContent).toMatch(/신규 식당 1곳/)
    expect(s.textContent).toMatch(/정보를 채우거나 바꿀 식당 1곳/)
    expect(s.textContent).toMatch(/변경 없음 1곳/)
    expect(s.textContent).toMatch(/오류 0줄/)
    const table = within(d).getByRole('table', { name: '미리보기' })
    expect(table.textContent).toMatch(/카테고리: 비어 있음 → 음식점 > 한식/)
    expect(table.textContent).toMatch(/주소: 비어 있음 → 충남 아산시/)
    expect(table.textContent).not.toMatch(/설명:/) // the stored description is kept
    expect(writes()).toHaveLength(0) // nothing is written by the preview
  })

  it('lists the columns it does not read, with the reason (prices are restaurant-level, not menu prices)', async () => {
    const { d } = await open(csv('1001,있는 식당,,,,,,,,15:00-17:00,5000,9000,,draft'))
    const cols = await within(d).findByLabelText('열 확인')
    expect(cols.textContent).toMatch(/break_time/)
    expect(cols.textContent).toMatch(/price_min_krw.*메뉴별 가격이 아니라/)
    expect(cols.textContent).toMatch(/visibility.*적용하지 않아요/)
  })

  it('변경사항 적용하기 saves DRAFTS for the existing restaurant (id, visibility and the rest of the record kept) and adds the new one as a draft', async () => {
    const { d } = await open(csv('1001,있는 식당,,음식점 > 한식,충남 아산시,,,,CSV 설명,,,,,draft', '1003,새 식당,,음식점 > 중식,,,,,,,,,,published'))
    await summary(d)
    await userEvent.click(within(d).getByRole('button', { name: '변경사항 적용하기' }))
    const r = await within(d).findByLabelText('가져오기 결과')
    expect(r.textContent).toMatch(/신규 1 · 업데이트 1 · 변경 없음 0 · 건너뜀 0 · 실패 0/)
    expect(saves()).toHaveLength(1)
    const s = saves()[0]
    expect([s.p_type, s.p_id, s.p_expected_revision]).toEqual(['restaurant', 'id-1', 0])
    expect(s.p_data).toMatchObject({ category: '음식점 > 한식', address: '충남 아산시', description: '내 설명', visibility: 'published', featured: true, display_order: 2, university_ids: ['u1'] })
    const up = fake.last('restaurant_overrides', 'upsert')!
    const rows = up.payload as { kakao_place_id: string; visibility: string; featured: boolean }[]
    expect(rows).toHaveLength(1)
    expect(rows[0]).toMatchObject({ kakao_place_id: '1003', visibility: 'draft', featured: false })
    expect(fake.rpcs.some((x) => x.name === 'cms_publish')).toBe(false)
    expect(r.textContent).toMatch(/아직 게시하지 않았어요/)
  })

  it('CSV 값으로 업데이트 shows the changes and needs an explicit confirmation before it can be applied', async () => {
    const { d } = await open(csv('1002,그대로 식당,,음식점 > 중식,새 주소,,,,,,,,,'))
    await summary(d)
    await userEvent.click(within(d).getByRole('radio', { name: /CSV 값으로 업데이트/ }))
    const table = within(d).getByRole('table', { name: '미리보기' })
    expect(table.textContent).toMatch(/카테고리: 음식점 > 한식 → 음식점 > 중식/)
    const apply = within(d).getByRole('button', { name: '변경사항 적용하기' }) as HTMLButtonElement
    expect(apply.disabled).toBe(true)
    await userEvent.click(within(d).getByRole('checkbox', { name: /확인했어요/ }))
    expect(apply.disabled).toBe(false)
    await userEvent.click(apply)
    await within(d).findByLabelText('가져오기 결과')
    expect(saves()[0].p_data).toMatchObject({ category: '음식점 > 중식', address: '새 주소', visibility: 'published' })
  })

  it('신규 식당만 추가 skips existing restaurants without calling them errors', async () => {
    const { d } = await open(csv('1001,있는 식당,,음식점 > 한식,,,,,,,,,,', '1004,새 식당,,,,,,,,,,,,'))
    await summary(d)
    await userEvent.click(within(d).getByRole('radio', { name: /신규 식당만 추가/ }))
    const s = await summary(d)
    expect(s.textContent).toMatch(/건너뜀\(이미 있음\) 1곳/)
    expect(s.textContent).toMatch(/오류 0줄/)
    await userEvent.click(within(d).getByRole('button', { name: '변경사항 적용하기' }))
    const r = await within(d).findByLabelText('가져오기 결과')
    expect(r.textContent).toMatch(/신규 1 · 업데이트 0 · 변경 없음 0 · 건너뜀 1 · 실패 0/)
    expect(saves()).toHaveLength(0)
  })

  it('a row without a Kakao id is set aside for review, never guessed', async () => {
    const { d } = await open(csv(',이름만 있는 식당,,,,,,,,,,,,', '1003,새 식당,,,,,,,,,,,,'))
    const s = await summary(d)
    expect(s.textContent).toMatch(/검토 필요\(장소 ID 없음·형식 오류\) 1줄/)
    expect(within(d).getByRole('table', { name: '미리보기' }).textContent).toMatch(/이름만으로는 같은 식당인지 알 수 없어서/)
  })

  it('the uploaded 168-row file: all 168 rows are read, the 7 old columns are listed, nothing is written in the preview', async () => {
    db = []
    const { d } = await open(FIXTURE)
    const s = await summary(d)
    expect(s.textContent).toMatch(/전체 168줄/)
    expect(s.textContent).toMatch(/신규 식당 168곳/)
    expect(s.textContent).toMatch(/오류 0줄/)
    const cols = within(d).getByLabelText('열 확인')
    for (const c of ['break_time', 'last_order_time', 'business_status', 'price_min_krw', 'price_max_krw', 'avg_cost_krw', 'dining_purposes']) expect(cols.textContent).toContain(c)
    await waitFor(() => expect(writes()).toHaveLength(0))
  })

  it('a double click applies once', async () => {
    const { d } = await open(csv('1001,있는 식당,,음식점 > 한식,,,,,,,,,,'))
    await summary(d)
    await userEvent.dblClick(within(d).getByRole('button', { name: '변경사항 적용하기' }))
    await within(d).findByLabelText('가져오기 결과')
    expect(saves()).toHaveLength(1)
  })

  it('a file without the key columns is explained and nothing is read', async () => {
    const onClose = vi.fn()
    render(<RestaurantCsvImport onClose={onClose} />)
    const d = await screen.findByRole('dialog', { hidden: true })
    await userEvent.upload(within(d).getByLabelText('CSV 파일 선택'), file('a,b\n1,2'))
    expect((await within(d).findByRole('alert')).textContent).toMatch(/kakao_place_id와 name_ko/)
  })
})
