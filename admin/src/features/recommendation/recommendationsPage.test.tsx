import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const open = () => render(<MemoryRouter initialEntries={['/recommendations']}><App client={makeQueryClient()} /></MemoryRouter>)

describe('추천 page: the CSV import is at the top', () => {
  beforeEach(() => {
    fake.reset()
    fake.respond('recommendation_demo_features:select', { data: [], count: 0 })
    fake.respond('restaurant_overrides:select', { data: [] })
    fake.respond('restaurant_menus:select', { data: [] })
    fake.respond('rpc:admin_recommendation_stats', { data: null })
  })

  it('an admin sees a "CSV 가져오기" button in the header, and the import card above the restaurant table', async () => {
    fake.signInAs('admin')
    open()
    expect(await screen.findByRole('button', { name: 'CSV 가져오기' })).toBeTruthy()
    const card = screen.getByLabelText('추천 데모 데이터')
    const inputs = await screen.findByLabelText('추천에 쓰이는 식당 정보')
    expect(card.compareDocumentPosition(inputs) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy() // the card comes first
    expect(screen.getByRole('button', { name: 'CSV 양식 내려받기' })).toBeTruthy()
    expect(screen.getByRole('button', { name: '저장된 데이터 내려받기' })).toBeTruthy()
  })
})
