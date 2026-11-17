import { beforeEach, describe, expect, it, vi } from 'vitest'
import { fake } from '@/test/fakeSupabase'
import { fetchExportItems } from './menuData'

vi.mock('@/lib/supabase', async () => {
  const m = await import('@/test/fakeSupabase')
  return { supabase: m.fake.client, supabaseConfigured: true }
})

type Call = { filters: [string, ...unknown[]][] }

describe('export reads every menu line, not only the first 1000', () => {
  beforeEach(() => { fake.reset(); fake.signInAs('admin') })

  it('pages through the lines of a chunk of restaurants (the database answers at most 1000 rows at a time)', async () => {
    // 3 restaurants, 2,450 lines in all: one request is not enough
    const all = Array.from({ length: 2450 }, (_, i) => ({ id: `m${String(i).padStart(5, '0')}`, restaurant_id: `r${i % 3}`, name_ko: `메뉴${i}`, description_ko: null, price_krw: 5000, category: '식사', price_verified_on: null, available: true, representative: false, recommended: false, status: 'active', sort_order: i, image_url: null }))
    fake.respond('restaurant_menus:select', (c: Call) => {
      const r = c.filters.find((f) => f[0] === 'range')
      const [from, to] = r ? [r[1] as number, r[2] as number] : [0, 999]
      return { data: all.slice(from, Math.min(to, from + 999) + 1) }
    })
    fake.respond('content_drafts:select', { data: [] })
    const out = await fetchExportItems(['r0', 'r1', 'r2'], 'published')
    expect([...out.values()].reduce((n, v) => n + v.length, 0)).toBe(2450)
    expect(fake.calls.filter((c) => c.table === 'restaurant_menus').length).toBe(3)
  })
})
