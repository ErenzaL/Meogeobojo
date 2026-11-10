import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const ROWS = [
  { id: 'r1', kakao_place_id: '1', name_ko: '사진있는집', category: '한식', address: null, visibility: 'published', updated_at: '2026-11-10T00:00:00Z', description: null, image_url: 'https://x.supabase.co/a.webp' },
  { id: 'r2', kakao_place_id: '2', name_ko: '사진없는집', category: '일식', address: null, visibility: 'draft', updated_at: '2026-11-10T00:00:00Z', description: null, image_url: null },
  { id: 'r3', kakao_place_id: '3', name_ko: '메뉴없는집', category: '중식', address: null, visibility: 'published', updated_at: '2026-11-10T00:00:00Z', description: null, image_url: null },
]

beforeEach(() => {
  fake.reset(); fake.signInAs('admin')
  fake.respond('restaurant_overrides:select', { data: ROWS, count: ROWS.length })
  fake.respond('restaurant_menus:select', { data: [{ restaurant_id: 'r1' }, { restaurant_id: 'r1' }, { restaurant_id: null }] })
  fake.respond('universities:select', { data: [] })
  render(<MemoryRouter initialEntries={['/restaurants']}><App client={makeQueryClient()} /></MemoryRouter>)
})

describe('식당 사진·메뉴 현황', () => {
  it('shows real coverage counts and thumbnails', async () => {
    const bar = await screen.findByRole('status', { name: '사진·메뉴 현황' })
    expect(bar.textContent).toContain('관리 중 3곳 (공개 2)')
    expect(bar.textContent).toContain('대표 사진 1 / 없음 2')
    expect(bar.textContent).toContain('메뉴 1 / 없음 2') // r1 only: duplicates and null owners are not counted twice
    expect(document.querySelector('img[src="https://x.supabase.co/a.webp"]')).toBeTruthy()
    expect(screen.getAllByTitle('대표 사진 없음')).toHaveLength(2)
  })

  it('filters restaurants without a photo', async () => {
    await screen.findByText('사진있는집')
    await userEvent.selectOptions(screen.getByLabelText('사진 필터'), 'none')
    await waitFor(() => {
      const q = [...fake.calls].reverse().find((c) => c.table === 'restaurant_overrides' && c.filters.some((f) => f[0] === 'is' && f[1] === 'image_url'))
      expect(q).toBeTruthy()
    })
  })

  it('filters restaurants without a menu using the real set of menu owners', async () => {
    await screen.findByText('사진있는집')
    await userEvent.selectOptions(screen.getByLabelText('메뉴 필터'), 'none')
    await waitFor(() => {
      const q = [...fake.calls].reverse().find((c) => c.table === 'restaurant_overrides' && c.filters.some((f) => f[0] === 'not' && f[1] === 'id'))
      expect(q).toBeTruthy()
      expect(q!.filters.find((f) => f[0] === 'not' && f[1] === 'id')).toEqual(['not', 'id', 'in', '(r1)'])
    })
  })
})
