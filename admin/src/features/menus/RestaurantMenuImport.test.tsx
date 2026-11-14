import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import type { MenuItem } from '@/lib/cms'
import { fake } from '@/test/fakeSupabase'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const A = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const B = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const item = (id: string, name: string, over: Partial<MenuItem> = {}): MenuItem => ({
  id, name_ko: name, description_ko: null, price_krw: null, category: null, price_verified_on: null, available: true, representative: false, recommended: false,
  status: 'active', sort_order: 1, image_url: null, ...over,
})

type Rest = { id: string; name_ko: string; kakao_place_id: string | null }
const RESTAURANTS: Rest[] = [
  { id: 'r1', name_ko: '어굿플레이스', kakao_place_id: '1001' },
  { id: 'r2', name_ko: '라멘집', kakao_place_id: '1002' },
  { id: 'r3', name_ko: '메뉴없는집', kakao_place_id: '1003' },
  { id: 'r4', name_ko: '직접등록집', kakao_place_id: null },
]
let live: Record<string, MenuItem[]> = {}
let drafts: Record<string, { items: MenuItem[]; revision: number }> = {}
let saveFail: Record<string, { code?: string; message: string }> = {}
let publishFail: Record<string, { code?: string; message: string }> = {}
let denied = false
let saved: { id: string; items: MenuItem[]; expected: number }[] = []
let published: { id: string; rev: number; reason: string }[] = []

function seed() {
  live = { r1: [item(A, '제육 정식', { price_krw: 8000, price_verified_on: '2026-10-01', sort_order: 1, representative: true, image_url: 'https://x/a.png' })], r2: [], r3: [], r4: [item(B, '직접 메뉴', { price_krw: 5000 })] }
  drafts = {}; saveFail = {}; publishFail = {}; denied = false; saved = []; published = []
}
const stateOf = (id: string) => ({
  live: { items: live[id] ?? [] }, live_version: 1, last_published: null, jobs: [],
  draft: drafts[id] ? { data: { items: drafts[id].items }, revision: drafts[id].revision, base_version: 1, created_by: 'u', updated_by: 'u', created_at: '', updated_at: '', stale: false, has_changes: true } : null,
})

type Call = { filters: [string, ...unknown[]][] }
function wire() {
  fake.respond('restaurant_overrides:select', (c: Call) => {
    const get = (n: string) => c.filters.filter((x) => x[0] === n)
    let rows = [...RESTAURANTS]
    for (const e of get('eq')) if (e[1] === 'id') rows = rows.filter((r) => r.id === e[2])
    for (const e of get('in')) if (e[1] === 'kakao_place_id') rows = rows.filter((r) => r.kakao_place_id && (e[2] as string[]).includes(r.kakao_place_id))
    for (const e of get('ilike')) if (e[1] === 'name_ko') rows = rows.filter((r) => r.name_ko.includes(String(e[2]).replace(/%/g, '')))
    return { data: rows }
  })
  fake.respond('restaurant_menus:select', (c: Call) => {
    const get = (n: string) => c.filters.filter((x) => x[0] === n)
    const all = Object.entries(live).flatMap(([rid, items]) => items.map((i) => ({ ...i, restaurant_id: rid })))
    const byRest = get('in').find((e) => e[1] === 'restaurant_id')
    const byId = get('in').find((e) => e[1] === 'id')
    return { data: byRest ? all.filter((m) => (byRest[2] as string[]).includes(m.restaurant_id)) : byId ? all.filter((m) => (byId[2] as string[]).includes(m.id)) : all }
  })
  fake.respond('content_drafts:select', (c: Call) => {
    const inn = c.filters.find((e) => e[0] === 'in' && e[1] === 'entity_id')
    return { data: Object.entries(drafts).filter(([id]) => !inn || (inn[2] as string[]).includes(id)).map(([id, d]) => ({ entity_id: id, data: { items: d.items } })) }
  })
  fake.respond('rpc:cms_overview', { data: [] })
  fake.respond('rpc:cms_state', (a: unknown) => ({ data: stateOf((a as { p_id: string }).p_id) }))
  fake.respond('rpc:cms_save_draft', (a: unknown) => {
    const x = a as { p_id: string; p_data: { items: MenuItem[] }; p_expected_revision: number }
    if (denied) return { error: { code: '42501', message: 'permission denied: admin role required' } }
    if (saveFail[x.p_id]) return { error: saveFail[x.p_id] }
    const cur = drafts[x.p_id]?.revision ?? 0
    if (x.p_expected_revision !== cur) return { error: { code: '40001', message: '다른 관리자가 먼저 저장했어요' } }
    drafts[x.p_id] = { items: x.p_data.items, revision: cur + 1 }
    saved.push({ id: x.p_id, items: x.p_data.items, expected: x.p_expected_revision })
    return { data: { revision: cur + 1, base_version: 1, updated_at: 'now' } }
  })
  fake.respond('rpc:cms_publish', (a: unknown) => {
    const x = a as { p_id: string; p_expected_revision: number; p_reason: string }
    if (publishFail[x.p_id]) return { error: publishFail[x.p_id] }
    published.push({ id: x.p_id, rev: x.p_expected_revision, reason: x.p_reason })
    return { data: 2 }
  })
}

let blobs: { name: string; blob: Blob }[] = []
const file = (text: string, name = 'menus.csv') => new File([text], name, { type: 'text/csv' })
const HEAD7 = 'kakao_place_id,restaurant_name,menu_name,price_krw,menu_category,description,is_available'
const csv = (...lines: string[]) => '\uFEFF' + [HEAD7, ...lines].join('\r\n')
const saves = () => fake.rpcs.filter((r) => r.name === 'cms_save_draft').map((r) => r.args as { p_id: string; p_data: { items: MenuItem[] }; p_expected_revision: number })

async function pick(name: string) {
  render(<MemoryRouter initialEntries={['/menus']}><App client={makeQueryClient()} /></MemoryRouter>)
  await userEvent.click(await screen.findByRole('button', { name: new RegExp(name) }))
  await screen.findByRole('heading', { name: '새 메뉴' })
}
async function openImport(text: string, name = 'menus.csv') {
  await userEvent.click(screen.getByRole('button', { name: 'CSV 가져오기' }))
  const d = await screen.findByRole('dialog', { hidden: true })
  await userEvent.upload(within(d).getByLabelText('CSV 파일 선택'), file(text, name))
  return d
}
const summary = (d: HTMLElement) => within(d).findByLabelText('가져오기 미리보기 요약')
const result = (d: HTMLElement) => within(d).findByLabelText('가져오기 결과')
const ten = (prefix = '메뉴') => Array.from({ length: 10 }, (_, i) => `,,${prefix}${i + 1},${(i + 1) * 1000},식사,설명 ${i + 1},true`)

beforeEach(() => {
  fake.reset(); fake.signInAs('admin'); seed(); wire()
  fake.respond('universities:select', { data: [] })
  blobs = []
  URL.createObjectURL = vi.fn((b: Blob) => { blobs.push({ name: '', blob: b }); return 'blob:x' })
  URL.revokeObjectURL = vi.fn()
  HTMLAnchorElement.prototype.click = vi.fn(function (this: HTMLAnchorElement) { blobs[blobs.length - 1].name = this.download })
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('the button', () => {
  it('is disabled until a restaurant is selected, then enabled; the dialog names the selected restaurant', async () => {
    render(<MemoryRouter initialEntries={['/menus']}><App client={makeQueryClient()} /></MemoryRouter>)
    expect((await screen.findByRole('button', { name: 'CSV 가져오기' }) as HTMLButtonElement).disabled).toBe(true)
    await userEvent.click(await screen.findByRole('button', { name: /어굿플레이스/ }))
    await screen.findByRole('heading', { name: '새 메뉴' })
    const b = screen.getByRole('button', { name: 'CSV 가져오기' }) as HTMLButtonElement
    expect(b.disabled).toBe(false)
    await userEvent.click(b)
    expect((await screen.findByTestId('import-target')).textContent).toBe('어굿플레이스')
  })

  it('is blocked while there are unsaved edits in the menu editor (an import must not race them)', async () => {
    await pick('어굿플레이스')
    await userEvent.type(screen.getByLabelText('메뉴 이름'), '직접 추가')
    await userEvent.click(screen.getByRole('button', { name: '메뉴 추가' }))
    expect((screen.getByRole('button', { name: 'CSV 가져오기' }) as HTMLButtonElement).disabled).toBe(true)
  })

  it('the template download is available in the dialog', async () => {
    await pick('어굿플레이스')
    await userEvent.click(screen.getByRole('button', { name: 'CSV 가져오기' }))
    const d = await screen.findByRole('dialog', { hidden: true })
    await userEvent.click(within(d).getByRole('button', { name: 'CSV 양식 다운로드' }))
    expect(blobs[0].name).toBe('meogeobojo_menu_import_template.csv')
    expect((await blobs[0].blob.text()).replace('\uFEFF', '')).toBe(HEAD7 + '\r\n')
  })
})

describe('restaurant-specific import', () => {
  it('10 valid Korean menus (UTF-8 with BOM, "8,500원") go into the selected restaurant only, as a draft', async () => {
    await pick('라멘집')
    const lines = [...ten('라멘'), '1002,라멘집,"돈코츠, 곱빼기","8,500원",면류,"국물이 진한\n라멘",예']
    const d = await openImport(csv(...lines))
    const s = await summary(d)
    expect(s.textContent).toMatch(/전체 11줄/)
    expect(s.textContent).toMatch(/오류 0/)
    expect(within(d).getByRole('table', { name: '미리보기' }).textContent).toMatch(/돈코츠, 곱빼기/)
    await userEvent.click(within(d).getByRole('button', { name: /초안으로 가져오기/ }))
    const r = await result(d)
    expect(r.textContent).toMatch(/라멘집/)
    expect(r.textContent).toMatch(/추가 11개/)
    expect(saves()).toHaveLength(1)
    expect(saves()[0].p_id).toBe('r2')
    const names = saves()[0].p_data.items.map((i) => i.name_ko)
    expect(names).toContain('돈코츠, 곱빼기')
    expect(saves()[0].p_data.items.find((i) => i.name_ko === '돈코츠, 곱빼기')).toMatchObject({ price_krw: 8500, category: '면류', available: true })
    expect(drafts.r1).toBeUndefined() // the other restaurants are untouched
    expect(drafts.r4).toBeUndefined()
    expect(published).toEqual([]) // nothing is published by an import
    expect(live.r2).toEqual([]) // and nothing live changed: it is a draft only
  })

  it('the imported menus show in the list right away, without a reload', async () => {
    await pick('라멘집')
    const d = await openImport(csv(',,돈코츠 라멘,9000,면류,,'))
    await summary(d)
    await userEvent.click(within(d).getByRole('button', { name: /초안으로 가져오기/ }))
    await result(d)
    await userEvent.click(within(d).getAllByRole('button', { name: '닫기' }).at(-1)!)
    expect(await screen.findByText('돈코츠 라멘')).toBeTruthy()
    expect(screen.getByText(/가져온 메뉴를 초안으로 저장했어요/)).toBeTruthy()
  })

  it('restaurant A\'s menus stay as they were when a different CSV goes into restaurant B', async () => {
    await pick('어굿플레이스')
    let d = await openImport(csv(',,A 새 메뉴,7000,,,'))
    await summary(d)
    await userEvent.click(within(d).getByRole('button', { name: /초안으로 가져오기/ }))
    await result(d)
    const aDraft = JSON.stringify(drafts.r1.items)
    await userEvent.click(within(d).getAllByRole('button', { name: '닫기' }).at(-1)!)
    await userEvent.click(await screen.findByRole('button', { name: /라멘집/ }))
    await screen.findByRole('heading', { name: '새 메뉴' })
    d = await openImport(csv(',,B 새 메뉴,6000,,,'))
    await summary(d)
    await userEvent.click(within(d).getByRole('button', { name: /초안으로 가져오기/ }))
    await result(d)
    expect(saves().map((s) => s.p_id)).toEqual(['r1', 'r2'])
    expect(JSON.stringify(drafts.r1.items)).toBe(aDraft)
    expect(drafts.r2.items.map((i) => i.name_ko)).toEqual(['B 새 메뉴'])
  })

  it('the same menu name in two restaurants is not a duplicate', async () => {
    await pick('라멘집')
    const d = await openImport(csv(',,제육 정식,8000,,,')) // r1 has 제육 정식; r2 does not
    const s = await summary(d)
    expect(s.textContent).toMatch(/추가 1/)
    expect(s.textContent).toMatch(/중복 가능성 0/)
  })

  it('importing the same file twice with "새 메뉴만 추가" adds nothing the second time (and saves nothing)', async () => {
    await pick('라멘집')
    const text = csv(',,돈코츠,9000,,,', ',,미소,8000,,,')
    const d = await openImport(text)
    await summary(d)
    await userEvent.click(within(d).getByRole('button', { name: /초안으로 가져오기/ }))
    await result(d)
    await userEvent.click(within(d).getByRole('button', { name: '다른 파일 가져오기' }))
    await userEvent.upload(within(d).getByLabelText('CSV 파일 선택'), file(text))
    const s = await summary(d)
    expect(s.textContent).toMatch(/추가 0 · 갱신 0 · 건너뜀 2/)
    expect(s.textContent).toMatch(/이 식당에 이미 있음 2/)
    expect((within(d).getByRole('button', { name: '가져올 내용이 없어요' }) as HTMLButtonElement).disabled).toBe(true)
    expect(saves()).toHaveLength(1)
  })

  it('"새 메뉴만 추가" is the default; "기존 메뉴 업데이트" changes prices and keeps the photo', async () => {
    await pick('어굿플레이스')
    const d = await openImport(csv(',,제육 정식,9500,,,', ',,새 메뉴,5000,,,'))
    await summary(d)
    expect((within(d).getByRole('radio', { name: /새 메뉴만 추가/ }) as HTMLInputElement).checked).toBe(true)
    await userEvent.click(within(d).getByRole('radio', { name: /기존 메뉴 업데이트/ }))
    expect((await summary(d)).textContent).toMatch(/추가 1 · 갱신 1/)
    await userEvent.click(within(d).getByRole('button', { name: /초안으로 가져오기/ }))
    const r = await result(d)
    expect(r.textContent).toMatch(/추가 1개 · 갱신 1개/)
    const items = saves()[0].p_data.items
    expect(items.find((i) => i.id === A)).toMatchObject({ price_krw: 9500, image_url: 'https://x/a.png', representative: true, price_verified_on: null })
    expect(items.map((i) => i.name_ko)).toContain('새 메뉴')
  })
})

describe('files that do not belong to the selected restaurant', () => {
  it('another restaurant\'s Kakao Place ID stops the import before anything is planned or saved', async () => {
    await pick('어굿플레이스')
    const d = await openImport(csv('1001,,국수,5000,,,', '1002,라멘집,우동,6000,,,'))
    const alert = await within(d).findByLabelText('다른 식당 파일')
    expect(alert.textContent).toMatch(/가져오기를 멈췄어요/)
    expect(alert.textContent).toMatch(/3줄/)
    expect(within(d).queryByRole('button', { name: /초안으로 가져오기/ })).toBeNull()
    expect(saves()).toHaveLength(0)
  })

  it('another restaurant\'s name with no place id also stops it', async () => {
    await pick('어굿플레이스')
    const d = await openImport(csv(',라멘집,우동,6000,,,'))
    expect((await within(d).findByLabelText('다른 식당 파일')).textContent).toMatch(/라멘집/)
    expect(saves()).toHaveLength(0)
  })

  it('blank ids are allowed, and a matching id with a different name is just noted', async () => {
    await pick('어굿플레이스')
    const d = await openImport(csv('1001,옛 이름,국수,5000,,,', ',,우동,6000,,,'))
    const s = await summary(d)
    expect(s.textContent).toMatch(/추가 2/)
    expect(s.textContent).toMatch(/장소 ID가 같아서/)
  })

  it('a hand-made restaurant (no place id) accepts a file with blank ids', async () => {
    await pick('직접등록집')
    const d = await openImport(csv(',,새 메뉴,3000,,,'))
    expect((await summary(d)).textContent).toMatch(/추가 1/)
  })
})

describe('invalid rows', () => {
  it('bad prices and missing names are listed with their row numbers, and the import cannot be confirmed', async () => {
    await pick('라멘집')
    const d = await openImport(csv(',,좋은 메뉴,5000,,,', ',,,4000,,,', ',,나쁜 가격,abc,,,', ',,음수,-5,,,', ',,소수,10.5,,,'))
    const s = await summary(d)
    expect(s.textContent).toMatch(/전체 5줄/)
    expect(s.textContent).toMatch(/올바른 줄 1/)
    expect(s.textContent).toMatch(/오류 4/)
    const table = within(d).getByRole('table', { name: '미리보기' })
    expect(table.textContent).toMatch(/메뉴 이름.*비어 있어요/)
    for (const line of ['3', '4', '5', '6']) expect(within(table).getAllByText(line).length).toBeGreaterThan(0)
    expect((within(d).getByRole('button', { name: '오류를 고쳐야 가져올 수 있어요' }) as HTMLButtonElement).disabled).toBe(true)
    expect(within(d).getByRole('alert').textContent).toMatch(/일부만 가져오지 않아요/)
    expect(saves()).toHaveLength(0)
  })

  it('a file with the wrong header, or empty, is explained and nothing is read', async () => {
    await pick('라멘집')
    await userEvent.click(screen.getByRole('button', { name: 'CSV 가져오기' }))
    const d = await screen.findByRole('dialog', { hidden: true })
    await userEvent.upload(within(d).getByLabelText('CSV 파일 선택'), file('a,b\n1,2'))
    expect((await within(d).findByRole('alert')).textContent).toMatch(/다음 열이 없어요/)
  })
})

describe('전체 교체 (replace the whole list)', () => {
  it('asks for a second confirmation naming the restaurant and the existing items affected, then replaces only that restaurant\'s draft', async () => {
    await pick('어굿플레이스')
    const d = await openImport(csv(',,새 메뉴,6000,,,'))
    await summary(d)
    await userEvent.click(within(d).getByRole('radio', { name: /전체 교체/ }))
    expect((await summary(d)).textContent).toMatch(/추가 1 · 갱신 0 · 건너뜀 0 · 초안에서 빠짐 1/)
    expect(within(d).getAllByText('빠짐').length).toBeGreaterThan(0)
    await userEvent.click(within(d).getByRole('button', { name: '전체 교체 확인…' }))
    const c = await within(d).findByRole('alertdialog')
    expect(c.textContent).toMatch(/어굿플레이스/)
    expect(c.textContent).toMatch(/영향받는 기존 메뉴는 모두 1개/)
    expect(saves()).toHaveLength(0) // not yet
    await userEvent.click(within(c).getByRole('button', { name: '돌아가기' }))
    await userEvent.click(within(d).getByRole('button', { name: '전체 교체 확인…' }))
    await userEvent.click(within(await within(d).findByRole('alertdialog')).getByRole('button', { name: '어굿플레이스 메뉴 전체 교체' }))
    const r = await result(d)
    expect(r.textContent).toMatch(/초안에서 뺀 메뉴 1개/)
    expect(saves()).toHaveLength(1)
    expect(saves()[0].p_id).toBe('r1')
    expect(saves()[0].p_data.items.map((i) => i.name_ko)).toEqual(['새 메뉴']) // the old line left the DRAFT; the published one is archived only when this is published
    expect(live.r1.map((i) => i.id)).toEqual([A]) // nothing live was deleted or changed
    expect(drafts.r4).toBeUndefined(); expect(drafts.r2).toBeUndefined()
  })

  it('is refused, with nothing saved, when the file has an error (a skipped line would otherwise delete a menu)', async () => {
    await pick('어굿플레이스')
    const d = await openImport(csv(',,제육 정식,8000,,,', ',,고장난 줄,abc,,,'))
    await summary(d)
    await userEvent.click(within(d).getByRole('radio', { name: /전체 교체/ }))
    expect((within(d).getByRole('button', { name: '오류를 고쳐야 가져올 수 있어요' }) as HTMLButtonElement).disabled).toBe(true)
    expect(saves()).toHaveLength(0)
  })
})

describe('permissions and failures', () => {
  it('a user who is not allowed to save gets an error and nothing is saved', async () => {
    denied = true
    await pick('라멘집')
    const d = await openImport(csv(',,돈코츠,9000,,,'))
    await summary(d)
    await userEvent.click(within(d).getByRole('button', { name: /초안으로 가져오기/ }))
    expect((await within(d).findByRole('alert')).textContent).toMatch(/permission denied|관리자 권한/)
    expect(drafts.r2).toBeUndefined()
    expect(published).toEqual([])
  })

  it('a double click on the confirm button saves once', async () => {
    await pick('라멘집')
    const d = await openImport(csv(',,돈코츠,9000,,,'))
    await summary(d)
    const b = within(d).getByRole('button', { name: /초안으로 가져오기/ })
    await userEvent.dblClick(b)
    await result(d)
    expect(saves()).toHaveLength(1)
  })

  it('another admin saving first (stale revision) is retried against the newest draft and nothing is lost', async () => {
    await pick('라멘집')
    const d = await openImport(csv(',,돈코츠,9000,,,'))
    await summary(d)
    drafts.r2 = { items: [item('ffffffff-ffff-4fff-8fff-ffffffffffff', '다른 관리자 메뉴', { sort_order: 1 })], revision: 1 } // saved after the preview
    await userEvent.click(within(d).getByRole('button', { name: /초안으로 가져오기/ }))
    await result(d)
    expect(drafts.r2.items.map((i) => i.name_ko).sort()).toEqual(['다른 관리자 메뉴', '돈코츠'])
  })
})
