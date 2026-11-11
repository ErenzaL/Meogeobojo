import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

type Vis = 'draft' | 'published' | 'hidden' | 'archived'
type R = { id: string; kakao_place_id: string; name_ko: string; category: string; address: string; visibility: Vis; updated_at: string; description: string | null; image_url: string | null; restaurant_university_links: unknown[] }
const pad = (n: number) => String(n).padStart(2, '0')
/** 45 restaurants: 식당01..식당30 are 한식, 식당31..식당45 양식. 03 and 04 are published, 05 archived, 06 hidden. */
let db: R[] = []
let menus: { restaurant_id: string }[] = []
let broken: Record<string, { code?: string; message: string }> = {}
let denied = false

function seed() {
  db = Array.from({ length: 45 }, (_, i) => {
    const n = i + 1
    return {
      id: `id-${pad(n)}`, kakao_place_id: `kp${pad(n)}`, name_ko: `식당${pad(n)}`, category: n <= 30 ? '한식' : '양식', address: `주소 ${n}`,
      visibility: (n === 3 || n === 4 ? 'published' : n === 5 ? 'archived' : n === 6 ? 'hidden' : 'draft') as Vis,
      updated_at: new Date(2026, 10, 10, 12, 0, 45 - n).toISOString(), // 01 is the newest
      description: n === 11 ? '설명이 있는 식당' : null, image_url: n === 10 ? 'https://x/img.png' : null, restaurant_university_links: [],
    }
  })
  menus = [{ restaurant_id: 'id-12' }]
  broken = {}
  denied = false
}

type Call = { filters: [string, ...unknown[]][] }
function wire() {
  fake.respond('restaurant_overrides:select', (c: Call) => {
    const f = c.filters
    const get = (n: string) => f.filter((x) => x[0] === n)
    const cols = String(get('select')[0]?.[1] ?? '')
    let rows = [...db]
    const or = get('or')[0]
    if (or) { const term = /ilike\.%(.*?)%/.exec(String(or[1]))?.[1] ?? ''; rows = rows.filter((r) => r.name_ko.includes(term) || r.kakao_place_id.includes(term)) }
    for (const e of get('eq')) if (e[1] === 'visibility') rows = rows.filter((r) => r.visibility === e[2])
    for (const e of get('ilike')) if (e[1] === 'category') rows = rows.filter((r) => r.category.includes(String(e[2]).replace(/%/g, '')))
    for (const e of get('in')) if (e[1] === 'id') rows = rows.filter((r) => (e[2] as string[]).includes(r.id))
    const total = rows.length
    const range = get('range')[0]
    if (range) rows = rows.slice(Number(range[1]), Number(range[2]) + 1)
    if (cols.startsWith('id,image_url,visibility')) return { data: rows.map((r) => ({ id: r.id, image_url: r.image_url, visibility: r.visibility })), count: total }
    if (cols.startsWith('id,name_ko,visibility')) return { data: rows.map((r) => ({ id: r.id, name_ko: r.name_ko, visibility: r.visibility, image_url: r.image_url, description: r.description })), count: total }
    if (cols.startsWith('id')) return { data: rows.map((r) => ({ id: r.id })), count: total }
    return { data: rows, count: total }
  })
  fake.respond('restaurant_menus:select', (c: Call) => {
    const inn = c.filters.find((x) => x[0] === 'in' && x[1] === 'restaurant_id')
    return { data: inn ? menus.filter((m) => (inn[2] as string[]).includes(m.restaurant_id)) : menus }
  })
  fake.respond('rpc:cms_overview', { data: [] })
  fake.respond('rpc:cms_set_visibility', (a: unknown) => {
    const args = a as { p_id: string; p_visibility: Vis }
    if (denied) return { error: { code: '42501', message: 'permission denied: admin role required' } }
    if (broken[args.p_id]) return { error: broken[args.p_id] }
    const r = db.find((x) => x.id === args.p_id)
    if (r) r.visibility = args.p_visibility
    return { data: 1 }
  })
}

const setCalls = () => fake.rpcs.filter((r) => r.name === 'cms_set_visibility').map((r) => r.args as { p_type: string; p_id: string; p_visibility: string; p_reason: string })
const status = () => screen.getByLabelText('선택 현황').textContent ?? ''
function open() {
  return render(<MemoryRouter initialEntries={['/restaurants']}><App client={makeQueryClient()} /></MemoryRouter>)
}
async function ready() { open(); await screen.findByText('식당01') }
const click = (el: HTMLElement) => userEvent.click(el)
const dlg = async () => await screen.findByRole('dialog', { hidden: true })

beforeEach(() => {
  fake.reset(); fake.signInAs('admin'); seed(); wire()
  fake.respond('universities:select', { data: [] })
  localStorage.clear()
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('selecting', () => {
  it('individual restaurants: a checkbox per row, an exact count', async () => {
    await ready()
    expect(status()).toContain('선택한 식당 0곳')
    await click(screen.getByLabelText('식당01 선택'))
    await click(screen.getByLabelText('식당02 선택'))
    expect(status()).toContain('선택한 식당 2곳')
    expect(status()).toContain('직접 선택')
    await click(screen.getByLabelText('식당01 선택'))
    expect(status()).toContain('선택한 식당 1곳')
  })

  it('the header checkbox selects (and clears) the current page and says it is the page', async () => {
    await ready()
    const head = () => screen.getByLabelText('이 페이지 모두 선택/해제 (표 머리글)') as HTMLInputElement // re-rendered with the selection: look it up each time
    await click(head())
    expect(status()).toContain('선택한 식당 20곳')
    expect(status()).toContain('선택 방식: 현재 페이지 20곳')
    expect(head().checked).toBe(true)
    await click(head())
    expect(status()).toContain('선택한 식당 0곳')
    expect(head().checked).toBe(false)
  })

  it('the header checkbox is indeterminate when only some of the page is selected', async () => {
    await ready()
    await click(screen.getByLabelText('식당01 선택'))
    expect((screen.getByLabelText('이 페이지 모두 선택/해제 (표 머리글)') as HTMLInputElement).indeterminate).toBe(true)
  })

  it('"현재 페이지 전체 선택" is the page only (20 of 45), and the buttons show the exact numbers', async () => {
    await ready()
    expect(screen.getByRole('button', { name: '현재 페이지 전체 선택 (20곳)' })).toBeTruthy()
    expect(screen.getByRole('button', { name: '검색/필터 결과 전체 선택 (45곳)' })).toBeTruthy()
    expect(screen.getByRole('button', { name: /^전체 선택 \(45곳\)/ })).toBeTruthy()
    await click(screen.getByRole('button', { name: '현재 페이지 전체 선택 (20곳)' }))
    expect(status()).toContain('선택한 식당 20곳')
    expect(status()).toContain('선택 방식: 현재 페이지 20곳')
  })

  it('the selection survives paging; after paging it is described as hand-picked, and the new page can be added', async () => {
    await ready()
    await click(screen.getByRole('button', { name: '현재 페이지 전체 선택 (20곳)' }))
    await click(screen.getByRole('button', { name: '다음 페이지' }))
    await screen.findByText('식당21')
    expect(status()).toContain('선택한 식당 20곳')
    expect(status()).toContain('직접 선택 (이 페이지 0곳 포함')
    await click(screen.getByLabelText('식당21 선택'))
    expect(status()).toContain('선택한 식당 21곳')
    await click(screen.getByRole('button', { name: '이전 페이지' }))
    await screen.findByText('식당01')
    expect(status()).toContain('이 페이지 20곳 포함')
  })

  it('"검색/필터 결과 전체 선택" selects EVERY matching result, not just this page, using the page\'s filters', async () => {
    await ready()
    await userEvent.type(screen.getByLabelText('카테고리'), '한식')
    await waitFor(() => expect(screen.getByRole('button', { name: '검색/필터 결과 전체 선택 (30곳)' })).toBeTruthy())
    await click(screen.getByRole('button', { name: '검색/필터 결과 전체 선택 (30곳)' }))
    await waitFor(() => expect(status()).toContain('선택한 식당 30곳'))
    expect(status()).toContain('선택 방식: 검색/필터 결과 전체 30곳') // 30, not the 20 of the page
    const q = [...fake.calls].reverse().find((c) => c.table === 'restaurant_overrides' && c.filters.some((f) => f[0] === 'select' && f[1] === 'id'))!
    expect(q.filters.find((f) => f[0] === 'ilike')).toEqual(['ilike', 'category', '%한식%']) // the same filter as the list
    expect(q.filters.some((f) => f[0] === 'range' && f[1] === 0 && f[2] === 999)).toBe(true) // fetched 1000 at a time
  })

  it('a search narrows "all matching" to the search results', async () => {
    await ready()
    await userEvent.type(screen.getByLabelText('식당 검색'), '식당1')
    await waitFor(() => expect(screen.getByRole('button', { name: '검색/필터 결과 전체 선택 (10곳)' })).toBeTruthy()) // 식당10 .. 식당19
    await click(screen.getByRole('button', { name: '검색/필터 결과 전체 선택 (10곳)' }))
    await waitFor(() => expect(status()).toContain('선택한 식당 10곳'))
    expect(status()).toContain('검색/필터 결과 전체 10곳')
  })

  it('after the filters change, the selection stays but is no longer called "filter results"', async () => {
    await ready()
    await userEvent.type(screen.getByLabelText('카테고리'), '한식')
    await waitFor(() => screen.getByRole('button', { name: '검색/필터 결과 전체 선택 (30곳)' }))
    await click(screen.getByRole('button', { name: '검색/필터 결과 전체 선택 (30곳)' }))
    await waitFor(() => expect(status()).toContain('검색/필터 결과 전체 30곳'))
    await userEvent.clear(screen.getByLabelText('카테고리'))
    await userEvent.type(screen.getByLabelText('카테고리'), '양식')
    await waitFor(() => expect(screen.getByRole('button', { name: '검색/필터 결과 전체 선택 (15곳)' })).toBeTruthy())
    expect(status()).toContain('선택한 식당 30곳') // nothing lost
    expect(status()).toContain('직접 선택') // but it no longer describes the 양식 results
  })

  it('sorting does not lose the selection', async () => {
    await ready()
    await click(screen.getByRole('button', { name: '현재 페이지 전체 선택 (20곳)' }))
    await click(screen.getByRole('button', { name: /수정일/ }))
    await waitFor(() => expect(status()).toContain('선택한 식당 20곳'))
  })

  it('"전체 선택" selects every managed restaurant regardless of filters, "선택 해제" clears', async () => {
    await ready()
    await userEvent.type(screen.getByLabelText('카테고리'), '양식')
    await waitFor(() => screen.getByRole('button', { name: '검색/필터 결과 전체 선택 (15곳)' }))
    await click(screen.getByRole('button', { name: /^전체 선택 \(/ }))
    await waitFor(() => expect(status()).toContain('선택한 식당 45곳'))
    expect(status()).toContain('선택 방식: 전체 45곳')
    await click(screen.getByRole('button', { name: '선택 해제' }))
    expect(status()).toContain('선택한 식당 0곳')
    expect((screen.getByRole('button', { name: '선택한 식당 공개' }) as HTMLButtonElement).disabled).toBe(true)
  })
})

describe('bulk publish', () => {
  async function pickPageAndOpen(to: '공개' | '비공개') {
    await ready()
    await click(screen.getByRole('button', { name: '현재 페이지 전체 선택 (20곳)' }))
    await click(screen.getByRole('button', { name: `선택한 식당 ${to}` }))
    return await dlg()
  }

  it('asks first: exact counts, already-published, archived, and a warning about incomplete data', async () => {
    const d = await pickPageAndOpen('공개')
    const list = await within(d).findByLabelText('선택 내용')
    expect(list.textContent).toContain('선택한 식당 20곳')
    expect(list.textContent).toContain('이미 공개 중 2곳') // 식당03, 식당04
    expect(list.textContent).toContain('보관됨 1곳') // 식당05 is archived: left alone
    expect(list.textContent).toContain('이번에 공개 식당 17곳')
    const warn = within(d).getByLabelText('정보가 덜 채워진 식당')
    expect(warn.textContent).toContain('공개할 17곳 중')
    expect(warn.textContent).toContain('대표 사진 없음 16곳') // 식당10 has a photo
    expect(warn.textContent).toContain('메뉴 없음 16곳') // 식당12 has a menu
    expect(warn.textContent).toContain('설명 없음 16곳') // 식당11 has a description
    expect(warn.textContent).toContain('필수 조건이 아니라서 이대로 공개돼요') // not made mandatory
    expect(warn.textContent).toContain("'확인됨'으로 표시되지는 않아요") // not marked verified
    expect(setCalls()).toHaveLength(0) // nothing happens before the admin confirms
  })

  it('publishes the 17 that need it through cms_set_visibility, with progress and a result, then refreshes the table and the count', async () => {
    const d = await pickPageAndOpen('공개')
    expect(await screen.findByText(/공개 2\)/)).toBeTruthy() // before: 2 published
    await userEvent.clear(within(d).getByLabelText(/사유/))
    await userEvent.type(within(d).getByLabelText(/사유/), '개강 시즌')
    await click(within(d).getByRole('button', { name: '17곳 공개' }))
    const result = await within(d).findByLabelText('결과')
    expect(result.textContent).toContain('공개 성공 17곳')
    expect(result.textContent).toContain('건너뜀 3곳') // 03 and 04 (already published), 05 (archived)
    expect(result.textContent).toContain('실패 0곳')
    const calls = setCalls()
    expect(calls).toHaveLength(17)
    expect(new Set(calls.map((c) => c.p_id)).size).toBe(17)
    expect(calls.every((c) => c.p_type === 'restaurant' && c.p_visibility === 'published' && /^일괄 공개 \[[0-9a-f]{8}\]: 개강 시즌$/.test(c.p_reason))).toBe(true)
    expect(calls.map((c) => c.p_id)).not.toContain('id-03') // already published
    expect(calls.map((c) => c.p_id)).not.toContain('id-05') // archived
    expect(calls.map((c) => c.p_id)).not.toContain('id-21') // outside the selection
    // the other fields of a restaurant are never written by this page
    expect(fake.calls.filter((c) => c.table === 'restaurant_overrides' && c.op !== 'select')).toHaveLength(0)
    await click(within(d).getByRole('button', { name: '닫기' }))
    expect(await screen.findByText(/일괄 처리가 끝났어요/)).toBeTruthy()
    await waitFor(() => expect(screen.getByLabelText('사진·메뉴 현황').textContent).toContain('공개 19)')) // 2 + 17
    expect(status()).toContain('선택한 식당 0곳')
  })

  it('shows the failures with their ids, keeps the successes, and retries only the failed ones', async () => {
    broken = { 'id-07': { code: '22023', message: '가격이 올바르지 않아요 (최저 ≤ 최고, 0 이상)' }, 'id-08': { code: '40001', message: '다른 관리자가 먼저 바꿨어요' } }
    const d = await pickPageAndOpen('공개')
    await click(await within(d).findByRole('button', { name: '17곳 공개' }))
    const result = await within(d).findByLabelText('결과')
    expect(result.textContent).toContain('공개 성공 15곳')
    expect(result.textContent).toContain('실패 2곳')
    const failed = within(d).getByLabelText('실패한 식당')
    expect(failed.textContent).toContain('식당07')
    expect(failed.textContent).toContain('ID id-07')
    expect(failed.textContent).toContain('가격이 올바르지 않아요')
    expect(failed.textContent).toContain('ID id-08')
    expect(db.find((r) => r.id === 'id-07')!.visibility).toBe('draft')
    expect(db.find((r) => r.id === 'id-09')!.visibility).toBe('published')
    const before = setCalls().length
    broken = {}
    await click(within(d).getByRole('button', { name: '실패·남은 식당 다시 시도 (2)' }))
    await waitFor(() => expect(within(d).getByLabelText('결과').textContent).toContain('공개 성공 2곳'))
    expect(setCalls().slice(before).map((c) => c.p_id).sort()).toEqual(['id-07', 'id-08']) // only those two
    expect(db.filter((r) => ['id-07', 'id-08'].includes(r.id)).every((r) => r.visibility === 'published')).toBe(true)
  })

  it('a database refusal for lack of permission stops the run: nothing else is attempted and nothing changes', async () => {
    denied = true
    const d = await pickPageAndOpen('공개')
    await click(await within(d).findByRole('button', { name: '17곳 공개' }))
    expect(await within(d).findByText('중간에 멈췄어요')).toBeTruthy()
    expect(within(d).getByRole('alert').textContent).toContain('관리자 권한이 확인되지 않아')
    expect(setCalls().length).toBeLessThanOrEqual(3) // not 17
    expect(db.filter((r) => r.visibility === 'published').map((r) => r.id).sort()).toEqual(['id-03', 'id-04'])
    expect(within(d).getByLabelText('결과').textContent).toContain('성공 0곳')
  })

  it('only already-published restaurants selected: nothing to do, no calls, no second version', async () => {
    await ready()
    await click(screen.getByLabelText('식당03 선택'))
    await click(screen.getByLabelText('식당04 선택'))
    await click(screen.getByRole('button', { name: '선택한 식당 공개' }))
    const d = await dlg()
    expect((await within(d).findByLabelText('선택 내용')).textContent).toContain('이미 공개 중 2곳')
    const go = within(d).getByRole('button', { name: '공개할 식당이 없어요' }) as HTMLButtonElement
    expect(go.disabled).toBe(true)
    expect(setCalls()).toHaveLength(0)
  })

  it('a restaurant published by someone else after the dialog opened is skipped, not published twice', async () => {
    const d = await pickPageAndOpen('공개')
    await within(d).findByLabelText('선택 내용')
    db.find((r) => r.id === 'id-15')!.visibility = 'published' // another admin, meanwhile
    await click(within(d).getByRole('button', { name: '17곳 공개' }))
    const result = await within(d).findByLabelText('결과')
    expect(setCalls().map((c) => c.p_id)).not.toContain('id-15')
    expect(result.textContent).toContain('공개 성공 16곳')
    expect(result.textContent).toContain('건너뜀 4곳') // + the one someone else published
  })

  it('a reason is required', async () => {
    const d = await pickPageAndOpen('공개')
    await userEvent.clear(await within(d).findByLabelText(/사유/))
    await click(within(d).getByRole('button', { name: '17곳 공개' }))
    expect(within(d).getByText('사유를 입력해 주세요')).toBeTruthy()
    expect(setCalls()).toHaveLength(0)
  })

  it('cancel closes the dialog without doing anything', async () => {
    const d = await pickPageAndOpen('공개')
    await click(await within(d).findByRole('button', { name: '취소' }))
    expect(setCalls()).toHaveLength(0)
    expect(screen.queryByLabelText('선택 내용')).toBeNull()
    expect(status()).toContain('선택한 식당 20곳') // the selection is kept
  })
})

describe('bulk unpublish', () => {
  it('hides only the published ones among the selection, with the same function and a tagged reason', async () => {
    await ready()
    await click(screen.getByRole('button', { name: '현재 페이지 전체 선택 (20곳)' }))
    await click(screen.getByRole('button', { name: '선택한 식당 비공개' }))
    const d = await dlg()
    const list = await within(d).findByLabelText('선택 내용')
    expect(list.textContent).toContain('이미 비공개 18곳')
    expect(list.textContent).toContain('이번에 숨길 식당 2곳')
    expect(within(d).queryByLabelText('정보가 덜 채워진 식당')).toBeNull() // that warning is for publishing
    await click(within(d).getByRole('button', { name: '2곳 숨기기' }))
    expect((await within(d).findByLabelText('결과')).textContent).toContain('숨김 성공 2곳')
    expect(setCalls().map((c) => [c.p_id, c.p_visibility]).sort()).toEqual([['id-03', 'hidden'], ['id-04', 'hidden']])
    expect(setCalls()[0].p_reason).toMatch(/^일괄 숨김 \[[0-9a-f]{8}\]: /)
  })
})

describe('the single-restaurant buttons still work as before', () => {
  it('공개 on one row: one reason-checked cms_set_visibility call, no bulk dialog', async () => {
    await ready()
    const row = screen.getByText('식당01').closest('tr')!
    await click(within(row).getByRole('button', { name: '공개' }))
    const d = await dlg()
    expect(within(d).getByText(/이 식당을 공개할까요/)).toBeTruthy()
    await click(within(d).getByRole('button', { name: '공개' }))
    expect(setCalls()).toHaveLength(0) // a reason is required here too
    await userEvent.type(within(d).getByLabelText('사유 (필수)'), '개별 공개')
    await click(within(d).getByRole('button', { name: '공개' }))
    await waitFor(() => expect(setCalls()).toHaveLength(1))
    expect(setCalls()[0]).toEqual({ p_type: 'restaurant', p_id: 'id-01', p_visibility: 'published', p_reason: '개별 공개' })
    expect(screen.queryByLabelText('선택 내용')).toBeNull()
  })
})
