import { render, screen, waitFor, within } from '@testing-library/react'
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
const HEAD = 'kakao_place_id,restaurant_name,menu_name,price_krw,menu_category,description,is_available,menu_id'
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
async function lastCsv(): Promise<string> { return (await blobs[blobs.length - 1].blob.text()).replace('﻿', '') }

const file = (text: string, name = 'menus.csv') => new File([text], name, { type: 'text/csv' })
const csv = (...lines: string[]) => [HEAD, ...lines].join('\n')
const saves = () => fake.rpcs.filter((r) => r.name === 'cms_save_draft').map((r) => r.args as { p_type: string; p_id: string; p_data: { items: MenuItem[] }; p_expected_revision: number })

function open() { return render(<MemoryRouter initialEntries={['/menus']}><App client={makeQueryClient()} /></MemoryRouter>) }
async function ready() { open(); await screen.findByRole('button', { name: /CSV 가져오기/ }) }
async function pickRestaurant(name: string) {
  await userEvent.click(await screen.findByRole('button', { name: new RegExp(name) }))
  await screen.findByRole('heading', { name: '새 메뉴' }) // the menu editor of that restaurant has loaded
}
async function openImport(text: string) {
  await userEvent.click(screen.getByRole('button', { name: /CSV 가져오기/ }))
  const d = await screen.findByRole('dialog', { hidden: true })
  await userEvent.upload(within(d).getByLabelText('CSV 파일 선택'), file(text))
  return d
}
const summary = (d: HTMLElement) => within(d).findByLabelText('가져오기 미리보기 요약')

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

describe('buttons and template', () => {
  it('the three buttons are at the top of 메뉴·가격', async () => {
    await ready()
    for (const n of ['CSV 양식 다운로드', 'CSV 가져오기', 'CSV 내보내기']) expect(screen.getByRole('button', { name: new RegExp(n) })).toBeTruthy()
  })
  it('the template download is the seven columns and nothing else (no invented menus or prices)', async () => {
    await ready()
    await userEvent.click(screen.getByRole('button', { name: /CSV 양식 다운로드/ }))
    expect(blobs[0].name).toBe('meogeobojo_menu_import_template.csv')
    expect(await lastCsv()).toBe('kakao_place_id,restaurant_name,menu_name,price_krw,menu_category,description,is_available\r\n')
  })
})

describe('importing', () => {
  it('previews several restaurants with counts for valid, invalid, duplicate, matched and unmatched; saves nothing until confirmed', async () => {
    await ready()
    const d = await openImport(csv(
      '1001,어굿플레이스,우동,6000,면류,따뜻한 국물,true,',
      '1001,어굿플레이스,김치찌개,,식사,,,', // no price: unknown
      '1002,라멘집,돈코츠,9000,면류,"진한 국물, 차슈",,',
      '9999,유령식당,국수,5000,,,,', // not a managed restaurant
      '1001,어굿플레이스,튀김,abc,,,,', // invalid price
      '1002,라멘집,돈코츠,9500,,,,', // duplicate of an earlier row
    ))
    const s = await summary(d)
    expect(s.textContent).toContain('전체 6줄')
    expect(s.textContent).toContain('가져올 수 있는 줄 3 (추가 3 · 갱신 0)')
    expect(s.textContent).toContain('오류 2') // bad price + unknown restaurant
    expect(s.textContent).toContain('중복 1')
    expect(s.textContent).toContain('찾은 식당 2곳')
    expect(s.textContent).toContain('찾지 못한 식당 1곳')
    expect(s.textContent).toContain('9999')
    const table = within(d).getByLabelText('미리보기')
    expect(within(table).getByText('식당 없음')).toBeTruthy()
    expect(within(table).getAllByText('추가')).toHaveLength(3)
    expect(within(table).getByText('중복')).toBeTruthy()
    expect(within(table).getByText(/가격은 0 이상의 정수/)).toBeTruthy()
    expect(within(table).getByText('진한 국물, 차슈')).toBeTruthy() // the quoted comma stayed in one cell
    expect(saves()).toHaveLength(0) // nothing is written by a preview
  })

  it('saves ONE DRAFT per restaurant: existing menus kept, a blank price stays null, nothing published, no restaurant touched', async () => {
    await ready()
    const d = await openImport(csv('1001,어굿플레이스,우동,6000,면류,,,', '1001,어굿플레이스,김치찌개,,식사,,,', '1002,라멘집,돈코츠,9000,,,,'))
    await userEvent.click(await within(d).findByRole('button', { name: /초안으로 저장 \(메뉴 3개, 식당 2곳\)/ }))
    const result = await within(d).findByLabelText('가져오기 결과')
    expect(result.textContent).toContain('초안으로 저장한 식당 2곳')
    expect(result.textContent).toContain('메뉴 추가 3개')
    expect(result.textContent).toContain('아직 게시하지 않았어요')
    const calls = saves()
    expect(calls.map((c) => [c.p_type, c.p_id, c.p_expected_revision])).toEqual([['restaurant_menus', 'r1', 0], ['restaurant_menus', 'r2', 0]])
    const r1 = calls[0].p_data.items
    expect(r1.map((i) => i.name_ko)).toEqual(['제육 정식', '우동', '김치찌개']) // the existing menu is still there
    expect(r1[0]).toEqual(live.r1[0]) // untouched: price, verified date, flag, photo
    expect(r1[2]).toMatchObject({ name_ko: '김치찌개', price_krw: null, status: 'active', price_verified_on: null }) // unknown price is null, not 0
    expect(fake.rpcs.filter((r) => r.name === 'cms_publish')).toHaveLength(0) // never published automatically
    expect(fake.calls.filter((c) => c.table === 'restaurant_overrides' && c.op !== 'select')).toHaveLength(0) // restaurant records untouched
    expect(live.r1).toHaveLength(1) // the published list is unchanged until published
  })

  it('append mode skips menus that already exist; update mode shows the conflict (old -> new) and changes only what the file says', async () => {
    await ready()
    const d = await openImport(csv(`1001,어굿플레이스,제육 정식,9000,,,,`, '1001,어굿플레이스,우동,6000,,,,'))
    let s = await summary(d)
    expect(s.textContent).toContain('추가 1 · 갱신 0')
    expect(s.textContent).toContain('중복 1') // append (the default): the existing menu is not touched
    await userEvent.click(within(d).getByRole('radio', { name: /갱신/ }))
    s = await summary(d)
    expect(s.textContent).toContain('추가 1 · 갱신 1')
    const table = within(d).getByLabelText('미리보기')
    expect(within(table).getByText('갱신')).toBeTruthy()
    expect(table.textContent).toContain('8,000원 → 9,000원') // the conflict, visible before anything is saved
    expect(table.textContent).toContain('가격 확인일') // the verification date of the OLD price is cleared
    await userEvent.click(within(d).getByRole('button', { name: /초안으로 저장/ }))
    await within(d).findByLabelText('가져오기 결과')
    const item1 = saves()[0].p_data.items.find((i) => i.id === A)!
    expect(item1).toMatchObject({ price_krw: 9000, price_verified_on: null, representative: true, image_url: 'https://x/a.png', name_ko: '제육 정식' })
  })

  it('a restaurant name that does not match its Kakao place id is held back until the admin allows it', async () => {
    await ready()
    const d = await openImport(csv('1001,라멘집,우동,6000,,,,'))
    const s = await summary(d)
    expect(s.textContent).toContain('이름 불일치(제외) 1')
    expect(within(d).getByRole('button', { name: '가져올 메뉴가 없어요' })).toBeTruthy()
    await userEvent.click(within(d).getByRole('checkbox', { name: /식당 이름이 달라도/ }))
    expect(await within(d).findByRole('button', { name: /초안으로 저장 \(메뉴 1개/ })).toBeTruthy()
  })

  it('"선택한 식당만": rows without a place id go to the selected restaurant; a row for another restaurant is refused', async () => {
    await ready()
    await pickRestaurant('라멘집')
    const d = await openImport(csv(',,돈코츠,9000,,,,', '1001,,우동,6000,,,,'))
    const s = await summary(d)
    await userEvent.click(within(d).getByRole('radio', { name: /선택한 식당만/ }))
    expect((await summary(d)).textContent).toContain('추가 1')
    expect(s).toBeTruthy()
    expect(within(d).getByLabelText('미리보기').textContent).toContain('장소 ID와 달라서')
    await userEvent.click(within(d).getByRole('button', { name: /초안으로 저장/ }))
    await within(d).findByLabelText('가져오기 결과')
    expect(saves().map((c) => c.p_id)).toEqual(['r2']) // never r1
  })

  it('an id that belongs to another restaurant is refused (a menu can not be moved by import)', async () => {
    await ready()
    const d = await openImport(csv(`1002,라멘집,제육 정식,1,,,,${A}`)) // A is a menu of r1
    await summary(d)
    expect(within(d).getByLabelText('미리보기').textContent).toContain('다른 식당의 메뉴')
    expect(within(d).getByRole('button', { name: '가져올 메뉴가 없어요' })).toBeTruthy()
  })

  const refuse = async (f: File, expected: string) => {
    await ready()
    await userEvent.click(screen.getByRole('button', { name: /CSV 가져오기/ }))
    const d = await screen.findByRole('dialog', { hidden: true })
    await userEvent.upload(within(d).getByLabelText('CSV 파일 선택'), f)
    expect((await within(d).findByRole('alert')).textContent).toContain(expected)
    expect(within(d).queryByLabelText('가져오기 미리보기 요약')).toBeNull()
    expect(saves()).toHaveLength(0)
  }
  it('refuses a file with the wrong headers, saying which columns are missing', () => refuse(file('이름,가격\n국수,5000'), '머리글(첫 줄)에 다음 열이 없어요'))
  it('refuses an empty file', () => refuse(file('x'.repeat(0) + '\n  \n'), '빈 파일'))
  it('refuses a file that is not UTF-8 instead of importing garbage', () => refuse(file(csv('1001,,\uFFFD\uFFFD,1,,,,')), 'UTF-8'))
  it('refuses a file over the size limit', async () => {
    await ready()
    await userEvent.click(screen.getByRole('button', { name: /CSV 가져오기/ }))
    const d = await screen.findByRole('dialog', { hidden: true })
    const big = new File(['x'], 'big.csv', { type: 'text/csv' })
    Object.defineProperty(big, 'size', { value: 6 * 1024 * 1024 })
    await userEvent.upload(within(d).getByLabelText('CSV 파일 선택'), big)
    expect((await within(d).findByRole('alert')).textContent).toContain('파일이 너무 커요')
  })

  it('"문제 있는 줄 CSV 내려받기" gives the bad rows back as typed, with the reason, so they can be fixed and uploaded again', async () => {
    await ready()
    const d = await openImport(csv('1001,어굿플레이스,튀김,abc,,,,', '9999,유령,국수,5000,,,,', '1001,어굿플레이스,우동,6000,,,,'))
    await summary(d)
    await userEvent.click(within(d).getByRole('button', { name: /문제 있는 줄 CSV 내려받기/ }))
    const out = await lastCsv()
    expect(out.split('\r\n')[0]).toBe('kakao_place_id,restaurant_name,menu_name,price_krw,menu_category,description,is_available,menu_id,error')
    expect(out).toContain('튀김,abc') // the price as typed
    expect(out).toContain('식당이 관리 목록에 없어요')
    expect(out).not.toContain('우동') // the good row is not in the error file
  })

  it('a partial failure keeps the saved restaurants, names the failed one, and retrying saves only that one', async () => {
    saveFail = { r2: { code: '22023', message: '메뉴 이름이 너무 길어요' } }
    await ready()
    const d = await openImport(csv('1001,어굿플레이스,우동,6000,,,,', '1002,라멘집,돈코츠,9000,,,,'))
    await userEvent.click(await within(d).findByRole('button', { name: /초안으로 저장/ }))
    const result = await within(d).findByLabelText('가져오기 결과')
    expect(result.textContent).toContain('초안으로 저장한 식당 1곳')
    expect(result.textContent).toContain('저장 못 한 식당 1곳')
    const failedList = within(d).getByLabelText('저장하지 못한 식당')
    expect(failedList.textContent).toContain('라멘집')
    expect(failedList.textContent).toContain('메뉴 이름이 너무 길어요')
    expect(drafts.r1).toBeDefined()
    saveFail = {}
    const before = saved.length
    await userEvent.click(within(d).getByRole('button', { name: /저장 못 한 식당 다시 시도 \(1\)/ }))
    await waitFor(() => expect(within(d).getByLabelText('가져오기 결과').textContent).toContain('초안으로 저장한 식당 2곳'))
    expect(saved.slice(before).map((s) => s.id)).toEqual(['r2']) // only the failed one was saved again
  })

  it('a permission error stops the import and says so', async () => {
    denied = true
    await ready()
    const d = await openImport(csv('1001,어굿플레이스,우동,6000,,,,'))
    await userEvent.click(await within(d).findByRole('button', { name: /초안으로 저장/ }))
    expect((await within(d).findByRole('alert')).textContent).toContain('관리자 권한이 확인되지 않아')
    expect(Object.keys(drafts)).toHaveLength(0)
  })

  it('importing the same file twice does not duplicate anything', async () => {
    await ready()
    const text = csv('1001,어굿플레이스,우동,6000,,,,')
    let d = await openImport(text)
    await userEvent.click(await within(d).findByRole('button', { name: /초안으로 저장/ }))
    await within(d).findByLabelText('가져오기 결과')
    await userEvent.click(within(d).getByRole('button', { name: '다른 파일 가져오기' }))
    await userEvent.upload(within(d).getByLabelText('CSV 파일 선택'), file(text))
    d = await screen.findByRole('dialog', { hidden: true })
    const s = await summary(d)
    expect(s.textContent).toContain('추가 0')
    expect(s.textContent).toContain('중복 1') // now it already exists (in the draft)
    expect(drafts.r1.items.filter((i) => i.name_ko === '우동')).toHaveLength(1)
  })
})

describe('optional publishing of the imported menus (existing publish function only)', () => {
  it('publishes each saved draft at the saved revision, with a required reason; restaurant status is untouched', async () => {
    await ready()
    const d = await openImport(csv('1001,어굿플레이스,우동,6000,,,,', '1002,라멘집,돈코츠,9000,,,,'))
    await userEvent.click(await within(d).findByRole('button', { name: /초안으로 저장/ }))
    await within(d).findByLabelText('가져오기 결과')
    expect(published).toHaveLength(0) // saving did not publish
    await userEvent.click(within(d).getByRole('button', { name: /가져온 2곳 메뉴 게시/ }))
    const box = within(d).getByLabelText('가져온 메뉴 게시')
    await userEvent.clear(within(box).getByLabelText(/사유/))
    expect((within(box).getByRole('button', { name: '2곳 게시' }) as HTMLButtonElement).disabled).toBe(true) // reason required
    await userEvent.type(within(box).getByLabelText(/사유/), '개강 메뉴')
    await userEvent.click(within(box).getByRole('button', { name: '2곳 게시' }))
    const res = await within(d).findByLabelText('게시 결과')
    expect(res.textContent).toContain('게시한 식당 2곳')
    expect(published.map((p) => [p.id, p.rev, p.reason]).sort()).toEqual([['r1', 1, '개강 메뉴'], ['r2', 1, '개강 메뉴']])
    expect(fake.calls.filter((c) => c.table === 'restaurant_overrides' && c.op !== 'select')).toHaveLength(0)
  })

  it('warns that an earlier draft of the same restaurant is published together with the import, and a conflict fails only that restaurant', async () => {
    drafts.r1 = { items: [item(A, '제육 정식', { price_krw: 8000 }), item('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '동료의 초안 메뉴', { sort_order: 2 })], revision: 3 }
    publishFail = { r2: { code: '40001', message: '초안이 바뀌었어요' } }
    await ready()
    const d = await openImport(csv('1001,어굿플레이스,우동,6000,,,,', '1002,라멘집,돈코츠,9000,,,,'))
    await userEvent.click(await within(d).findByRole('button', { name: /초안으로 저장/ }))
    await within(d).findByLabelText('가져오기 결과')
    expect(saves()[0].p_data.items.map((i) => i.name_ko)).toContain('동료의 초안 메뉴') // merged onto the existing draft, not over it
    expect(saves()[0].p_expected_revision).toBe(3)
    await userEvent.click(within(d).getByRole('button', { name: /가져온 2곳 메뉴 게시/ }))
    expect(within(d).getByLabelText('가져온 메뉴 게시').textContent).toContain('1곳은 가져오기 전에 이미 초안이 있었어요')
    await userEvent.click(within(d).getByRole('button', { name: '2곳 게시' }))
    const res = await within(d).findByLabelText('게시 결과')
    expect(res.textContent).toContain('게시한 식당 1곳')
    expect(res.textContent).toContain('게시 못 한 식당 1곳')
    expect(res.textContent).toContain('초안이 바뀌었어요')
  })
})

describe('exporting', () => {
  async function exportWith(scope: RegExp | null, opts: { published?: boolean; archived?: boolean } = {}) {
    await userEvent.click(screen.getByRole('button', { name: /CSV 내보내기/ }))
    const d = await screen.findByRole('dialog', { hidden: true })
    if (scope) await userEvent.click(within(d).getByRole('radio', { name: scope }))
    if (opts.published) await userEvent.click(within(d).getByRole('radio', { name: /게시된 메뉴만/ }))
    if (opts.archived) await userEvent.click(within(d).getByRole('checkbox', { name: /보관된 메뉴도 포함/ }))
    await userEvent.click(within(d).getByRole('button', { name: '내보내기' }))
    await waitFor(() => expect(blobs.length).toBeGreaterThan(0))
    return d
  }
  const lines = async () => (await lastCsv()).split('\r\n').filter(Boolean)

  it('the selected restaurant: the template columns plus menu_id and menu_status, exact prices, Korean text, blank price empty', async () => {
    live.r1 = [item(A, '제육 정식', { price_krw: 8000, category: '식사', description_ko: '밥, 국, 반찬', sort_order: 1 }), item(B, '김치찌개', { price_krw: null, available: false, sort_order: 2 })]
    await ready()
    await pickRestaurant('어굿플레이스')
    const d = await exportWith(/선택한 식당/)
    const out = await lines()
    expect(out[0]).toBe('kakao_place_id,restaurant_name,menu_name,price_krw,menu_category,description,is_available,menu_id,menu_status')
    expect(out[1]).toBe(`1001,어굿플레이스,제육 정식,8000,식사,"밥, 국, 반찬",true,${A},active`)
    expect(out[2]).toBe(`1001,어굿플레이스,김치찌개,,,,false,${B},active`) // unknown price: empty, not 0
    expect(out).toHaveLength(3)
    expect(blobs[0].name).toMatch(/^menus-selected-\d{8}\.csv$/)
    expect((await within(d).findByRole('status')).textContent).toContain('식당 1곳, 메뉴 2개')
  })

  it('exports what the editor shows: the draft if there is one, the published list otherwise; "게시된 메뉴만" ignores drafts', async () => {
    drafts.r1 = { items: [item(A, '제육 정식', { price_krw: 9999 })], revision: 1 }
    await ready()
    await pickRestaurant('어굿플레이스')
    await exportWith(/선택한 식당/)
    expect((await lines())[1]).toContain(',9999,') // the draft's price
  })

  it('"게시된 메뉴만" uses the published rows', async () => {
    drafts.r1 = { items: [item(A, '제육 정식', { price_krw: 9999 })], revision: 1 }
    await ready()
    await pickRestaurant('어굿플레이스')
    await exportWith(/선택한 식당/, { published: true })
    expect((await lines())[1]).toContain(',8000,')
  })

  it('archived menus are left out unless asked for, and keep their status when included', async () => {
    live.r1 = [item(A, '제육 정식', { price_krw: 8000 }), item(B, '단종 메뉴', { status: 'archived', sort_order: 2 })]
    await ready()
    await pickRestaurant('어굿플레이스')
    await exportWith(/선택한 식당/)
    expect(await lines()).toHaveLength(2)
    blobs = []
    await userEvent.click(screen.getByRole('button', { name: '닫기' }))
    await exportWith(/선택한 식당/, { archived: true })
    const out = await lines()
    expect(out).toHaveLength(3)
    expect(out[2]).toContain(',archived')
  })

  it('all restaurants, and the searched ones only', async () => {
    live.r2 = [item('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '돈코츠', { price_krw: 9000 })]
    await ready()
    await exportWith(/모든 식당/)
    const all = await lines()
    expect(all.slice(1).map((l) => l.split(',')[1]).sort()).toEqual(['라멘집', '어굿플레이스', '직접등록집'].sort())
    blobs = []
    await userEvent.click(screen.getByRole('button', { name: '닫기' }))
    await userEvent.type(screen.getByLabelText('식당 검색'), '라멘')
    await exportWith(/검색한 식당/)
    expect((await lines()).slice(1).map((l) => l.split(',')[1])).toEqual(['라멘집'])
  })

  it('an exported file imports again as "갱신" without any change (round trip by menu id)', async () => {
    live.r1 = [item(A, '제육 정식', { price_krw: 8000, category: '식사', description_ko: '밥, 국', sort_order: 1 }), item(B, '김치찌개', { price_krw: null, available: false, sort_order: 2 })]
    await ready()
    await pickRestaurant('어굿플레이스')
    await exportWith(/선택한 식당/)
    const exported = await lastCsv()
    await userEvent.click(screen.getByRole('button', { name: '닫기' }))
    await userEvent.click(screen.getByRole('button', { name: /CSV 가져오기/ }))
    const d = await screen.findByRole('dialog', { hidden: true })
    await userEvent.upload(within(d).getByLabelText('CSV 파일 선택'), file(exported))
    await userEvent.click(await within(d).findByRole('radio', { name: /갱신/ }))
    const s = await summary(d)
    expect(s.textContent).toContain('변경 없음 2')
    expect(s.textContent).toContain('추가 0 · 갱신 0')
    expect(within(d).getByRole('button', { name: '가져올 메뉴가 없어요' })).toBeTruthy()
  })
})
