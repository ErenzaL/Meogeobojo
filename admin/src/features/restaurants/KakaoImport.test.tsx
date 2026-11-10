import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import { KAKAO_QUERIES } from './kakao'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const doc = (id: string, name: string, distance = '100') => ({ id, place_name: name, category_group_code: 'FD6', category_name: '음식점 > 한식', road_address_name: `도로 ${id}`, distance, x: '126.93', y: '36.77' })
const UNI = { id: 'u1', name_ko: '순천향대학교', is_active: true, latitude: 36.76999, longitude: 126.9315 }
const row = (over: Record<string, unknown> = {}) => ({ id: 'r1', kakao_place_id: '1776574318', name_ko: '어굿플레이스', category: '한식', address: '관리자가 입력한 주소', visibility: 'draft', updated_at: '2026-11-10T00:00:00Z', description: null, restaurant_university_links: [{ universities: { name_ko: '순천향대학교' } }], ...over })

function open() {
  fake.respond('universities:select', { data: [UNI] })
  return render(<MemoryRouter initialEntries={['/restaurants']}><App client={makeQueryClient()} /></MemoryRouter>)
}
async function pickUniversity() {
  const select = await screen.findByLabelText('카카오 식당 불러오기 · 대학교')
  await waitFor(() => expect(within(select).getByRole('option', { name: '순천향대학교' })).toBeTruthy())
  await userEvent.selectOptions(select, 'u1')
}

beforeEach(() => {
  fake.reset(); fake.signInAs('admin')
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
})

describe('식당 목록', () => {
  it('shows name, category, university, address, Kakao ID and publication status', async () => {
    fake.respond('restaurant_overrides:select', { data: [row()], count: 1 })
    open()
    expect(await screen.findByText('어굿플레이스')).toBeTruthy()
    expect(screen.getByText('Kakao ID 1776574318')).toBeTruthy()
    expect(screen.getByText('한식')).toBeTruthy()
    expect(screen.getByText('관리자가 입력한 주소')).toBeTruthy()
    expect(screen.getAllByText('초안').length).toBeGreaterThan(1) // the status badge (and the filter option)
    expect(screen.getAllByText('순천향대학교').length).toBeGreaterThan(0)
  })

  it('an empty catalog points at the Kakao import instead of a dead end', async () => {
    fake.respond('restaurant_overrides:select', { data: [], count: 0 })
    open()
    expect(await screen.findByText(/카카오 식당 불러오기/)).toBeTruthy()
  })
})

describe('카카오 식당 불러오기', () => {
  it('lists live results with which are already managed, registers only the ticked ones', async () => {
    fake.respond('restaurant_overrides:select', { data: [{ kakao_place_id: '1', visibility: 'published' }], count: 0 })
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: [doc('1', '가'), doc('2', '나', '50'), doc('3', '다', '70')] } })
    fake.respond('rpc:admin_register_kakao_places', { data: { added: 1, already_managed: 0, skipped: 0 } })
    open(); await pickUniversity()
    await userEvent.click(screen.getByRole('button', { name: /카카오에서 찾기/ }))
    const list = await screen.findByRole('group', { name: '찾은 식당' })
    expect(within(list).getByText(/3곳/)).toBeTruthy()
    expect(within(list).getByText(/이미 관리 중 1곳, 새 식당 2곳/)).toBeTruthy()
    expect(within(list).getByText('관리 중 · 공개')).toBeTruthy()
    expect((within(list).getByLabelText('가 선택') as HTMLInputElement).disabled).toBe(true) // already managed: cannot be picked again
    expect(fake.invokes).toHaveLength(KAKAO_QUERIES.length)
    expect(fake.invokes[0]).toMatchObject({ name: 'search_restaurants', body: { latitude: 36.76999, longitude: 126.9315 } })
    expect(fake.rpcs.filter((r) => r.name !== 'cms_overview')).toHaveLength(0) // nothing is stored before the admin chooses

    expect((within(list).getByRole('button', { name: '0곳 등록하기' }) as HTMLButtonElement).disabled).toBe(true)
    await userEvent.click(within(list).getByLabelText('나 선택'))
    await userEvent.click(within(list).getByRole('button', { name: '1곳 등록하기' }))
    expect(await screen.findByText(/1곳을 초안으로 등록했어요/)).toBeTruthy()
    const args = fake.rpcs.find((r) => r.name === 'admin_register_kakao_places')!.args as { p_university: string; p_places: Record<string, unknown>[] }
    expect(args.p_university).toBe('u1')
    expect(args.p_places.map((p) => p.id)).toEqual(['2'])
    // only what the server needs to validate and label: no address, phone or category path is sent for storage
    expect(Object.keys(args.p_places[0]).sort()).toEqual(['category_group_code', 'id', 'place_name', 'x', 'y'])
  })

  it('"새 식당 모두 선택" ticks every unmanaged place', async () => {
    fake.respond('restaurant_overrides:select', { data: [{ kakao_place_id: '1', visibility: 'draft' }], count: 0 })
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: [doc('1', '가'), doc('2', '나'), doc('3', '다')] } })
    open(); await pickUniversity()
    await userEvent.click(screen.getByRole('button', { name: /카카오에서 찾기/ }))
    await userEvent.click(await screen.findByRole('button', { name: '새 식당 모두 선택' }))
    expect(screen.getByRole('button', { name: '2곳 등록하기' })).toBeTruthy()
  })

  it('explains clearly when the migration has not been applied', async () => {
    fake.respond('restaurant_overrides:select', { data: [], count: 0 })
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: [doc('1', '가')] } })
    fake.respond('rpc:admin_register_kakao_places', { error: { message: 'Could not find the function public.admin_register_kakao_places(p_places, p_university) in the schema cache' } })
    open(); await pickUniversity()
    await userEvent.click(screen.getByRole('button', { name: /카카오에서 찾기/ }))
    await userEvent.click(await screen.findByLabelText('가 선택'))
    await userEvent.click(screen.getByRole('button', { name: '1곳 등록하기' }))
    expect(await screen.findByText(/마이그레이션 20261111000100을 먼저 적용/)).toBeTruthy()
  })

  it('says so when Kakao search fails entirely', async () => {
    fake.respond('restaurant_overrides:select', { data: [], count: 0 })
    fake.respond('fn:search_restaurants', { error: { message: 'down' } })
    open(); await pickUniversity()
    await userEvent.click(screen.getByRole('button', { name: /카카오에서 찾기/ }))
    expect(await screen.findByText(/카카오 검색에 실패했어요/)).toBeTruthy()
    expect(fake.rpcs.filter((r) => r.name !== 'cms_overview')).toHaveLength(0)
  })

  it('moderators cannot reach the restaurants page', async () => {
    fake.signInAs('moderator')
    open()
    expect(await screen.findByText('이 페이지를 볼 권한이 없어요.')).toBeTruthy()
  })
})

describe('카카오 실시간 정보', () => {
  const editPage = () => {
    fake.respond('restaurant_overrides:select', { data: [{ id: 'r1', kakao_place_id: '1', name_ko: '수정된 이름', visibility: 'draft', image_url: null }] })
    fake.respond('restaurant_university_links:select', { data: [{ university_id: 'u1', universities: { latitude: 36.77, longitude: 126.93 } }] })
    fake.respond('rpc:cms_state', { data: { live: { name_ko: '수정된 이름', visibility: 'draft', featured: false, university_ids: [], dining_purposes: [], opening_hours: {} }, live_version: 0, last_published: null, draft: null, jobs: [] } })
    render(<MemoryRouter initialEntries={['/restaurants/r1']}><App client={makeQueryClient()} /></MemoryRouter>)
  }
  it('fetches the Kakao original LIVE around the linked campus and shows it read-only, separate from the editable values', async () => {
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: [{ ...doc('1', '카카오 원래 이름'), place_url: 'http://place.map.kakao.com/1' }, doc('2', '다른 곳')] } })
    editPage()
    const card = await screen.findByLabelText('카카오 실시간 정보')
    expect(await within(card).findByText('카카오 원래 이름')).toBeTruthy()
    expect(within(card).getByText('36.77 / 126.93')).toBeTruthy()
    expect(within(card).getByRole('link', { name: '장소 페이지' }).getAttribute('href')).toBe('https://place.map.kakao.com/1')
    expect(fake.invokes[0]).toMatchObject({ name: 'search_restaurants', body: { query: '수정된 이름', latitude: 36.77, longitude: 126.93 } })
    expect(await screen.findByDisplayValue('수정된 이름')).toBeTruthy()
    // nothing from Kakao was written anywhere
    expect(fake.calls.filter((c) => c.op !== 'select')).toHaveLength(0)
    expect(fake.rpcs.filter((r) => r.name !== 'cms_state')).toHaveLength(0)
  })
  it('says so when Kakao no longer returns the place', async () => {
    fake.respond('fn:search_restaurants', { data: { success: true, restaurants: [doc('9', '없는 곳')] } })
    editPage()
    expect(await screen.findByText(/카카오에서 이 장소를 지금 찾지 못했어요/)).toBeTruthy()
  })
})
