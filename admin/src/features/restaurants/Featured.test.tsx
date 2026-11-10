import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'
import { emptyRestaurantForm, fromRow, toRow } from './schema'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

describe('featured placement in the form values', () => {
  it('round-trips featured and the display order', () => {
    const f = fromRow({ name_ko: '식당', visibility: 'published', featured: true, display_order: 3 }, [])
    expect(f.featured).toBe(true); expect(f.display_order).toBe('3')
    expect(toRow({ ...f, display_order: '3' })).toMatchObject({ featured: true, display_order: 3 })
  })
  it('an empty order is NULL, never 0, and not featured by default', () => {
    expect(toRow({ ...emptyRestaurantForm, name_ko: 'x' })).toMatchObject({ featured: false, display_order: null })
  })
})

describe('식당 편집', () => {
  beforeEach(() => {
    fake.reset(); fake.signInAs('admin')
    HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
    HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
  })
  it('saves featured + display order to restaurant_overrides', async () => {
    fake.respond('restaurant_overrides:select', { data: [{ id: 'r1', kakao_place_id: '1', name_ko: '온기식당', visibility: 'published', featured: false, display_order: null }] })
    fake.respond('restaurant_university_links:select', { data: [] })
    render(<MemoryRouter initialEntries={['/restaurants/r1']}><App client={makeQueryClient()} /></MemoryRouter>)
    await userEvent.click(await screen.findByLabelText('추천 식당'))
    await userEvent.type(screen.getByLabelText('추천 표시 순서'), '2')
    await userEvent.click(screen.getByRole('button', { name: '저장' }))
    const dialogSave = await screen.findAllByRole('button', { name: /저장|확인/, hidden: true })
    await userEvent.click(dialogSave.at(-1)!)
    await waitFor(() => expect(fake.last('restaurant_overrides', 'update')).toBeTruthy())
    expect(fake.last('restaurant_overrides', 'update')!.payload).toMatchObject({ featured: true, display_order: 2, name_ko: '온기식당' })
  })
})
