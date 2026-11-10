import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import { TEMPLATE_CSV } from './csv'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const HEAD = 'university,cafeteria_name,date,meal_type,menu_name,price,serving_time,meal_option,program,source_url\n'
const csvFile = (text: string, bom = false) => new File([(bom ? '﻿' : '') + text], 'menus.csv', { type: 'text/csv' })
type Sent = { p_rows: { line: number; date: string; meal_type: string; university: string; menu_name: string; price: string; start_time: string | null; meal_option: string; program: string | null }[]; p_mode: string; p_dry_run: boolean; p_create_missing: boolean; p_allow_multi_university: boolean }
const calls = () => fake.rpcs.filter((r) => r.name === 'cafeteria_import').map((r) => r.args as Sent)

const entry = (line: number, status: string, over: Record<string, unknown> = {}) => ({ line, status, message: null, university: '순천향대학교', cafeteria: '학생식당', ...over })
const result = (rows: unknown[], over: Record<string, unknown> = {}) => ({ dry_run: true, mode: 'create_only', multi_university: false, universities: ['순천향대학교'], new_cafeterias: [],
  summary: { created: 0, updated: 0, unchanged: 0, skipped: 0, failed: 0, cafeterias_created: 0, weeks_changed: 0 }, rows, ...over })

async function openImport() {
  fake.signInAs('admin')
  fake.respond('universities:select', { data: [{ id: 'u1', name_ko: '순천향대학교', is_active: true }] })
  fake.respond('campus_cafeterias:select', { data: [] })
  fake.respond('cafeteria_weeks:select', { data: [] })
  fake.respond('rpc:cms_overview', { data: [] })
  render(<MemoryRouter initialEntries={['/cafeteria']}><App client={makeQueryClient()} /></MemoryRouter>)
  await userEvent.click(await screen.findByRole('button', { name: /CSV 일괄 등록/ }))
  return screen.findByRole('dialog', { name: 'CSV 일괄 등록' })
}
const upload = async (dlg: HTMLElement, file: File) => userEvent.upload(within(dlg).getByLabelText('CSV 파일 선택'), file)

beforeEach(() => {
  fake.reset()
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('CSV 일괄 등록', () => {
  it('offers the example template and explains the format', async () => {
    const dlg = await openImport()
    expect(within(dlg).getByRole('button', { name: /예시 파일 내려받기/ })).toBeTruthy()
    expect(dlg.textContent).toMatch(/university, cafeteria_name, date, meal_type, menu_name, price, serving_time/)
    expect(dlg.textContent).toMatch(/초안으로만 저장/)
    URL.createObjectURL = vi.fn(() => 'blob:x'); URL.revokeObjectURL = vi.fn()
    await userEvent.click(within(dlg).getByRole('button', { name: /예시 파일 내려받기/ }))
    const blob = (URL.createObjectURL as unknown as { mock: { calls: [Blob][] } }).mock.calls[0][0]
    expect(blob.type).toMatch(/text\/csv/)
  })

  it('reads a Korean UTF-8 file with a BOM, previews it through the server (a dry run) and writes nothing', async () => {
    fake.respond('rpc:cafeteria_import', { data: result([entry(2, 'create'), entry(3, 'create')], { summary: { created: 2, updated: 0, unchanged: 0, skipped: 0, failed: 0, cafeterias_created: 0, weeks_changed: 1 } }) })
    const dlg = await openImport()
    await upload(dlg, csvFile(HEAD + '순천향대학교,학생식당,2026-11-23,점심,제육볶음,"5,500",11:30-13:30,A코너,,\n순천향대학교,학생식당,2026-11-23,조식,계란토스트,1000,08:00-09:30,,천원의 아침밥,https://example.org/m\n', true))
    const preview = await within(dlg).findByLabelText('가져오기 미리보기')
    expect(within(preview).getByText('제육볶음')).toBeTruthy()
    expect(within(preview).getByText(/5,500원/)).toBeTruthy()
    expect(within(preview).getByText(/조식 · 천원의 아침밥/)).toBeTruthy()
    await waitFor(() => expect(calls()).toHaveLength(1))
    const sent = calls()[0]
    expect(sent.p_dry_run).toBe(true)
    expect(sent.p_rows[0]).toMatchObject({ line: 2, date: '2026-11-23', meal_type: 'lunch', university: '순천향대학교', price: '5500', start_time: '11:30', meal_option: 'A코너' })
    expect(sent.p_rows[1]).toMatchObject({ meal_type: 'breakfast', program: '천원의 아침밥' })
    expect(calls().some((c) => !c.p_dry_run)).toBe(false)
    expect(await within(dlg).findByLabelText('미리보기 요약')).toBeTruthy()
  })

  it('shows row-level errors and warnings; bad rows are never sent to the server; good rows still import', async () => {
    fake.respond('rpc:cafeteria_import', { data: result([entry(2, 'create'), entry(6, 'error', { message: '등록되지 않은 식당이에요: 없는식당' })], { summary: { created: 1, updated: 0, unchanged: 0, skipped: 0, failed: 1, cafeterias_created: 0, weeks_changed: 1 } }) })
    const dlg = await openImport()
    await upload(dlg, csvFile(HEAD + [
      '순천향대학교,학생식당,2026-11-23,lunch,정상,5500,11:30-13:30,,,',
      '순천향대학교,학생식당,2026-02-30,lunch,날짜오류,5500,11:30-13:30,,,',
      '순천향대학교,학생식당,2026-11-24,brunch,식사오류,5500,11:30-13:30,,,',
      '순천향대학교,학생식당,2026-11-24,lunch,가격오류,-5,11:30-13:30,,,',
      '순천향대학교,없는식당,2026-11-25,lunch,식당오류,5500,11:30-13:30,,,',
    ].join('\n')))
    const preview = await within(dlg).findByLabelText('가져오기 미리보기')
    await waitFor(() => expect(calls()).toHaveLength(1))
    expect(calls()[0].p_rows.map((r) => r.line)).toEqual([2, 6]) // only the rows the browser accepted
    expect(within(preview).getByText(/날짜가 올바르지 않아요/)).toBeTruthy()
    expect(within(preview).getByText(/식사 종류가 올바르지 않아요/)).toBeTruthy()
    expect(within(preview).getByText(/가격이 올바르지 않아요/)).toBeTruthy()
    expect(within(preview).getByText(/등록되지 않은 식당이에요/)).toBeTruthy() // the server's reason
    expect(within(dlg).getByText(/오류가 있는 4행은 가져오지 않아요/)).toBeTruthy()
    expect(within(dlg).getByRole('button', { name: '오류 없는 1행만 초안으로 가져오기' })).toBeTruthy()
    await userEvent.click(within(dlg).getByLabelText('오류가 있는 행만 보기'))
    expect(within(preview).queryByText('정상')).toBeNull()
  })

  it('refuses a file that is missing required columns, is empty, or was saved in the wrong encoding', async () => {
    const dlg = await openImport()
    await upload(dlg, csvFile('university,date\nA,2026-11-23\n'))
    expect(await within(dlg).findByText(/필수 열이 없어요: cafeteria_name, meal_type, menu_name, price, serving_time/)).toBeTruthy()
    await upload(dlg, csvFile(HEAD))
    expect(await within(dlg).findByText('데이터 행이 없어요.')).toBeTruthy()
    await upload(dlg, csvFile(HEAD + '�����,�����,2026-11-23,lunch,x,1,\n'))
    expect(await within(dlg).findByText(/UTF-8/)).toBeTruthy()
    expect(calls()).toHaveLength(0)
  })

  it('applies the import as DRAFTS and reports created / updated / unchanged / skipped / failed', async () => {
    const plan = result([entry(2, 'create'), entry(3, 'update'), entry(4, 'unchanged')], { summary: { created: 1, updated: 1, unchanged: 1, skipped: 0, failed: 0, cafeterias_created: 0, weeks_changed: 1 } })
    fake.respond('rpc:cafeteria_import', (a: unknown) => ({ data: (a as Sent).p_dry_run ? plan : { ...plan, dry_run: false } }))
    const dlg = await openImport()
    await upload(dlg, csvFile(HEAD + [2, 3, 4].map((n) => `순천향대학교,학생식당,2026-11-2${n},lunch,메뉴${n},5500,11:30-13:30,,,`).join('\n')))
    const go = await within(dlg).findByRole('button', { name: '2행을 초안으로 가져오기' })
    await userEvent.click(go)
    const summary = await within(dlg).findByLabelText('가져오기 결과')
    expect(summary.textContent).toMatch(/새로 만듦 1/); expect(summary.textContent).toMatch(/수정 1/); expect(summary.textContent).toMatch(/변경 없음 1/)
    expect(dlg.textContent).toMatch(/앱에는 아직 보이지 않아요/)
    const applied = calls().filter((c) => !c.p_dry_run)
    expect(applied).toHaveLength(1)
    expect(applied[0]).toMatchObject({ p_mode: 'create_only', p_create_missing: false, p_allow_multi_university: false })
    for (const op of ['insert', 'update', 'upsert']) expect(fake.last('cafeteria_meals', op)).toBeUndefined() // the browser never writes menus itself
  })

  it('the import mode is chosen explicitly and re-previewed (create-only is the safe default)', async () => {
    fake.respond('rpc:cafeteria_import', { data: result([entry(2, 'create')], { summary: { created: 1, updated: 0, unchanged: 0, skipped: 0, failed: 0, cafeterias_created: 0, weeks_changed: 1 } }) })
    const dlg = await openImport()
    await upload(dlg, csvFile(HEAD + '순천향대학교,학생식당,2026-11-23,lunch,제육,5500,11:30-13:30,,,\n'))
    await within(dlg).findByLabelText('가져오기 방식')
    expect((within(dlg).getByLabelText('가져오기 방식') as HTMLSelectElement).value).toBe('create_only')
    await userEvent.selectOptions(within(dlg).getByLabelText('가져오기 방식'), 'upsert')
    await waitFor(() => expect(calls().at(-1)!.p_mode).toBe('upsert'))
    await userEvent.selectOptions(within(dlg).getByLabelText('가져오기 방식'), 'update_only')
    await waitFor(() => expect(calls().at(-1)!.p_mode).toBe('update_only'))
  })

  it('missing cafeterias are created only when the admin asks, and the preview names them', async () => {
    const withNew = result([entry(2, 'create', { new_cafeteria: true, cafeteria: '새 식당' })], { new_cafeterias: [{ university: '순천향대학교', name: '새 식당' }], summary: { created: 1, updated: 0, unchanged: 0, skipped: 0, failed: 0, cafeterias_created: 1, weeks_changed: 1 } })
    fake.respond('rpc:cafeteria_import', { data: withNew })
    const dlg = await openImport()
    await upload(dlg, csvFile(HEAD + '순천향대학교,새 식당,2026-11-23,lunch,제육,5500,11:30-13:30,,,\n'))
    expect(await within(dlg).findByText(/새로 만들 식당: 순천향대학교 · 새 식당/)).toBeTruthy()
    expect((within(dlg).getByRole('button', { name: /초안으로 가져오기/ }) as HTMLButtonElement).disabled).toBe(true) // not allowed yet
    await userEvent.click(within(dlg).getByLabelText(/없는 식당은 새로 만들기/))
    await waitFor(() => expect(calls().at(-1)!.p_create_missing).toBe(true))
    await waitFor(() => expect((within(dlg).getByRole('button', { name: /초안으로 가져오기/ }) as HTMLButtonElement).disabled).toBe(false))
  })

  it('an import that spans several universities needs an explicit confirmation before it can be applied', async () => {
    const multi = result([entry(2, 'create'), entry(3, 'create', { university: '호서대학교' })], { multi_university: true, universities: ['순천향대학교', '호서대학교'], summary: { created: 2, updated: 0, unchanged: 0, skipped: 0, failed: 0, cafeterias_created: 0, weeks_changed: 2 } })
    fake.respond('rpc:cafeteria_import', { data: multi })
    const dlg = await openImport()
    await upload(dlg, csvFile(HEAD + '순천향대학교,학생식당,2026-11-23,lunch,a,1,\n호서대학교,학생식당,2026-11-23,lunch,b,1,\n'))
    const apply = async () => within(dlg).getByRole('button', { name: /초안으로 가져오기/ }) as HTMLButtonElement
    expect(await within(dlg).findByText(/여러 대학교의 식단을 한 번에 바꿔요/)).toBeTruthy()
    expect((await apply()).disabled).toBe(true)
    await userEvent.click(within(dlg).getByLabelText('여러 대학교 변경 확인'))
    expect((await apply()).disabled).toBe(false)
    await userEvent.click(await apply())
    await waitFor(() => expect(calls().some((c) => !c.p_dry_run)).toBe(true))
    expect(calls().find((c) => !c.p_dry_run)!.p_allow_multi_university).toBe(true)
  })

  it('a server refusal is shown, and a database without the import function says which migration to apply', async () => {
    fake.respond('rpc:cafeteria_import', { error: { code: 'PGRST202', message: 'Could not find the function public.cafeteria_import' } })
    const dlg = await openImport()
    await upload(dlg, csvFile(HEAD + '순천향대학교,학생식당,2026-11-23,lunch,제육,5500,11:30-13:30,,,\n'))
    expect(await within(dlg).findByText(/20261118000100/)).toBeTruthy()
  })

  it('the shipped example imports cleanly: 5 rows, two universities, a 천원의 아침밥 breakfast and two lunch options', async () => {
    fake.respond('rpc:cafeteria_import', { data: result([2, 3, 4, 5, 6].map((n) => entry(n, 'create')), { multi_university: true, universities: ['순천향대학교', '호서대학교'] }) })
    const dlg = await openImport()
    await upload(dlg, csvFile(TEMPLATE_CSV, true))
    await within(dlg).findByLabelText('가져오기 미리보기')
    await waitFor(() => expect(calls()).toHaveLength(1))
    expect(calls()[0].p_rows).toHaveLength(5)
    expect(calls()[0].p_rows.some((r) => r.program === '천원의 아침밥')).toBe(true)
    expect(calls()[0].p_rows.filter((r) => r.meal_type === 'lunch').map((r) => r.meal_option)).toEqual(['A코너', 'B코너', ''])
  })
})
