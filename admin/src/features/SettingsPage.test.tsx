import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import App, { makeQueryClient } from '@/App'
import { fake } from '@/test/fakeSupabase'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

const A = '01aca408-d171-4ef0-bf7e-929cdd5c1bbb', B = '8425f58c-f113-4394-80a7-265379b5996c', C = 'e99dd87d-4398-415d-896f-8e2180c3e6c1'
const open = () => render(<MemoryRouter initialEntries={['/settings']}><App client={makeQueryClient()} /></MemoryRouter>)

beforeEach(() => {
  fake.reset(); fake.signInAs('super_admin')
  HTMLDialogElement.prototype.showModal = function (this: HTMLDialogElement) { this.setAttribute('open', '') }
  HTMLDialogElement.prototype.close = function (this: HTMLDialogElement) { this.removeAttribute('open') }
  fake.respond('admin_roles:select', { data: [{ user_id: A, role: 'super_admin', created_at: '2026-11-01T00:00:00Z' }, { user_id: B, role: 'admin', created_at: '2026-11-02T00:00:00Z' }, { user_id: C, role: 'admin', created_at: '2026-11-03T00:00:00Z' }] })
})

describe('관리자 역할: who is who', () => {
  it('shows each role holder by nickname, with the id beside it; one without a nickname says so', async () => {
    fake.respond('profiles:select', { data: [{ id: A, nickname: '에렌' }, { id: B, nickname: '  소미  ' }] })
    open()
    const card = within(await screen.findByText('관리자 역할 (최고 관리자 전용)').then((h) => h.closest('div')!))
    expect(await card.findByText('에렌')).toBeInTheDocument()
    expect(card.getByText('소미')).toBeInTheDocument()
    expect(card.getByText('(닉네임 없음)')).toBeInTheDocument()
    for (const id of [A, B, C]) expect(card.getByText(id)).toBeInTheDocument()
    // the names are asked for exactly the role holders
    const q = fake.last('profiles', 'select')!
    expect(q.filters.find((f) => f[0] === 'in')).toEqual(['in', 'id', [A, B, C]])
  })

  it('a failed name lookup still lists the roles (by id)', async () => {
    fake.respond('profiles:select', { data: null, error: { message: 'denied' } })
    open()
    expect(await screen.findByText(B)).toBeInTheDocument()
    expect(screen.getAllByText('(닉네임 없음)')).toHaveLength(3)
  })

  it('the revoke confirmation names who is being revoked', async () => {
    fake.respond('profiles:select', { data: [{ id: B, nickname: '소미' }] })
    open()
    await screen.findByText('소미')
    await userEvent.click(screen.getAllByRole('button', { name: '해제' })[1])
    expect(await screen.findByText(`소미 · ${B}`)).toBeInTheDocument()
    expect(fake.rpcs.some((r) => r.name === 'admin_revoke_role')).toBe(false) // nothing is revoked before confirming
  })
})
