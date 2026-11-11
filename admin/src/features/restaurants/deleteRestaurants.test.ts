import { describe, expect, it } from 'vitest'
import { deleteVerdict, type DeleteDeps, type DeleteProgress, type RestaurantRow, runDelete } from './deleteRestaurants'
import type { Visibility } from './schema'

/** A tiny in-memory database behind the three functions the engine uses. */
function db(initial: Record<string, Visibility>, hooks: { scheduled?: string[]; superAdmin?: boolean; fail?: (id: string, n: number) => unknown; onDelete?: (id: string) => void } = {}) {
  const rows = new Map(Object.entries(initial))
  const deletes: string[] = []
  const reads: string[][] = []
  const attempts = new Map<string, number>()
  let inflight = 0
  let maxInflight = 0
  const scheduled = new Set(hooks.scheduled ?? [])
  const deps: DeleteDeps = {
    sleep: async () => undefined,
    readRows: async (ids) => { reads.push(ids); return ids.filter((id) => rows.has(id)).map((id): RestaurantRow => ({ id, name_ko: `식당 ${id}`, visibility: rows.get(id)! })) },
    scheduledIds: async () => new Set(scheduled),
    deleteOne: async (id) => {
      inflight++; maxInflight = Math.max(maxInflight, inflight)
      await Promise.resolve()
      inflight--
      const n = (attempts.get(id) ?? 0) + 1
      attempts.set(id, n)
      deletes.push(id)
      const f = hooks.fail?.(id, n)
      if (f === 'applied-but-lost') { rows.delete(id); throw new TypeError('Failed to fetch') }
      if (f) throw f
      if (hooks.superAdmin === false) return 0 // row-level security: no error, nothing deleted
      const had = rows.delete(id)
      if (had) hooks.onDelete?.(id)
      return had ? 1 : 0
    },
  }
  return { deps, rows, deletes, reads, scheduled, stats: () => ({ maxInflight }) }
}
const ids = (n: number) => Array.from({ length: n }, (_, i) => `r${i}`)
const drafts = (list: string[]): Record<string, Visibility> => Object.fromEntries(list.map((i) => [i, 'draft' as Visibility]))

describe('what may be deleted', () => {
  const row = (v: Visibility): RestaurantRow => ({ id: 'a', name_ko: 'a', visibility: v })
  it('drafts, hidden and archived restaurants can; a published one never', () => {
    for (const v of ['draft', 'hidden', 'archived'] as const) expect(deleteVerdict(row(v), new Set())).toBe('delete')
    expect(deleteVerdict(row('published'), new Set())).toBe('published')
  })
  it('a restaurant with a scheduled publish cannot', () => {
    expect(deleteVerdict(row('draft'), new Set(['a']))).toBe('scheduled')
  })
  it('published wins over scheduled (the first thing to do is hide it)', () => {
    expect(deleteVerdict(row('published'), new Set(['a']))).toBe('published')
  })
})

describe('deleting', () => {
  it('deletes the selected restaurants, each exactly once, and nothing else', async () => {
    const all = ids(30)
    const d = db(drafts(all))
    const res = await runDelete(all.slice(0, 12), d.deps)
    expect(res.deleted.sort()).toEqual(all.slice(0, 12).sort())
    expect(d.deletes).toHaveLength(12)
    expect(new Set(d.deletes).size).toBe(12)
    expect(all.slice(12).every((i) => d.rows.has(i))).toBe(true)
    expect(d.reads.flat().every((i) => all.slice(0, 12).includes(i))).toBe(true) // it never even looked at the others
    expect(res.stoppedBy).toBeNull()
    expect(res.failed).toEqual([])
  })

  it('published restaurants are NOT deleted: skipped with the reason', async () => {
    const d = db({ a: 'published', b: 'draft', c: 'hidden', d: 'archived' })
    const res = await runDelete(['a', 'b', 'c', 'd'], d.deps)
    expect(res.skipped).toEqual([{ id: 'a', name: '식당 a', reason: 'published' }])
    expect(res.deleted.sort()).toEqual(['b', 'c', 'd'])
    expect(d.rows.get('a')).toBe('published')
  })

  it('restaurants with a scheduled publish are NOT deleted', async () => {
    const d = db(drafts(['a', 'b']), { scheduled: ['b'] })
    const res = await runDelete(['a', 'b'], d.deps)
    expect(res.deleted).toEqual(['a'])
    expect(res.skipped).toEqual([{ id: 'b', name: '식당 b', reason: 'scheduled' }])
    expect(d.rows.has('b')).toBe(true)
  })

  it('a restaurant that is already gone is reported as such, not as a failure', async () => {
    const d = db(drafts(['a']))
    const res = await runDelete(['a', 'ghost'], d.deps)
    expect(res.deleted).toEqual(['a'])
    expect(res.skipped).toEqual([{ id: 'ghost', name: '', reason: 'gone' }])
    expect(res.failed).toEqual([])
  })

  it('repeating the same request deletes nothing more', async () => {
    const d = db(drafts(ids(8)))
    await runDelete(ids(8), d.deps)
    const before = d.deletes.length
    const again = await runDelete(ids(8), d.deps)
    expect(d.deletes.length).toBe(before)
    expect(again.deleted).toEqual([])
    expect(again.skipped.every((s) => s.reason === 'gone')).toBe(true)
  })

  it('duplicate ids are one restaurant', async () => {
    const d = db(drafts(['a']))
    const res = await runDelete(['a', 'a', 'a'], d.deps)
    expect(res.total).toBe(1)
    expect(d.deletes).toHaveLength(1)
  })
})

describe('the checks right before acting', () => {
  it('a restaurant published by someone else after the preview is skipped, never deleted', async () => {
    const all = ids(25)
    const d: ReturnType<typeof db> = db(drafts(all), { onDelete: (id) => { if (id === 'r0') d.rows.set('r15', 'published') } })
    const res = await runDelete(all, d.deps, { concurrency: 1 })
    expect(d.deletes).not.toContain('r15')
    expect(res.skipped).toEqual([{ id: 'r15', name: '식당 r15', reason: 'published' }])
    expect(d.rows.get('r15')).toBe('published')
    expect(res.deleted).toHaveLength(24)
  })

  it('one that got a scheduled publish meanwhile is skipped', async () => {
    const all = ids(25)
    const d: ReturnType<typeof db> = db(drafts(all), { onDelete: (id) => { if (id === 'r0') d.scheduled.add('r20') } })
    const res = await runDelete(all, d.deps, { concurrency: 1 })
    expect(d.deletes).not.toContain('r20')
    expect(res.skipped.map((s) => [s.id, s.reason])).toEqual([['r20', 'scheduled']])
  })

  it('one deleted by someone else meanwhile counts as already gone', async () => {
    const all = ids(25)
    const d: ReturnType<typeof db> = db(drafts(all), { onDelete: (id) => { if (id === 'r0') d.rows.delete('r18') } })
    const res = await runDelete(all, d.deps, { concurrency: 1 })
    expect(res.skipped.map((s) => [s.id, s.reason])).toEqual([['r18', 'gone']])
    expect(res.failed).toEqual([])
  })
})

describe('permission: row-level security deletes nothing and says nothing', () => {
  it('zero rows removed while the restaurant is still there is "not allowed": the run stops, nothing is called a success', async () => {
    const d = db(drafts(ids(40)), { superAdmin: false })
    const res = await runDelete(ids(40), d.deps)
    expect(res.deleted).toEqual([])
    expect(res.stoppedBy).toBe('forbidden')
    expect(res.failed[0]).toMatchObject({ code: '42501' })
    expect(res.failed[0].message).toContain('최고 관리자')
    expect(d.deletes.length).toBeLessThanOrEqual(3) // not 40
    expect(res.failed.length + res.notRun.length).toBe(40 - res.skipped.length)
    expect(ids(40).every((i) => d.rows.has(i))).toBe(true)
  })

  it('an explicit permission error (SQLSTATE 42501) stops the run too', async () => {
    const denied = Object.assign(new Error('permission denied'), { code: '42501' })
    const d = db(drafts(ids(30)), { fail: () => denied })
    const res = await runDelete(ids(30), d.deps)
    expect(res.stoppedBy).toBe('forbidden')
    expect(res.deleted).toEqual([])
    expect(d.deletes.length).toBeLessThanOrEqual(3)
  })
})

describe('partial failure, retries, connection drops', () => {
  it('one failing restaurant fails alone, named, with the reason; the rest are deleted', async () => {
    const bad = Object.assign(new Error('update or delete violates foreign key constraint'), { code: '23503' })
    const d = db(drafts(ids(20)), { fail: (id) => (id === 'r3' ? bad : null) })
    const res = await runDelete(ids(20), d.deps)
    expect(res.deleted).toHaveLength(19)
    expect(res.failed).toEqual([{ id: 'r3', name: '식당 r3', message: 'update or delete violates foreign key constraint', code: '23503' }])
    expect(d.rows.has('r3')).toBe(true)
    expect(d.deletes.filter((i) => i === 'r3')).toHaveLength(1) // a database refusal is not retried blindly
  })

  it('retrying only the failed ones finishes the job', async () => {
    let broken = true
    const bad = Object.assign(new Error('conflict'), { code: '40001' })
    const d = db(drafts(ids(12)), { fail: (id) => (broken && id === 'r5' ? bad : null) })
    const first = await runDelete(ids(12), d.deps)
    broken = false
    const before = d.deletes.length
    const second = await runDelete(first.failed.map((f) => f.id), d.deps)
    expect(second.deleted).toEqual(['r5'])
    expect(d.deletes.length - before).toBe(1)
    expect(d.rows.size).toBe(0)
  })

  it('a dropped connection after the delete had been applied counts as deleted, once', async () => {
    const d = db(drafts(['a']), { fail: (_id, n) => (n === 1 ? 'applied-but-lost' : null) })
    const res = await runDelete(['a'], d.deps)
    expect(res.deleted).toEqual(['a'])
    expect(d.deletes).toHaveLength(1)
  })

  it('a dropped connection where nothing was applied is retried, then succeeds', async () => {
    let n = 0
    const d = db(drafts(['a']), { fail: () => (n++ < 1 ? new TypeError('Failed to fetch') : null) })
    const res = await runDelete(['a'], d.deps)
    expect(res.deleted).toEqual(['a'])
    expect(d.deletes).toHaveLength(2)
  })

  it('a connection that keeps failing gives up after the retries and is reported', async () => {
    const d = db(drafts(['a', 'b']), { fail: (id) => (id === 'a' ? new TypeError('Failed to fetch') : null) })
    const res = await runDelete(['a', 'b'], d.deps, { retries: 2 })
    expect(res.failed.map((f) => f.id)).toEqual(['a'])
    expect(res.deleted).toEqual(['b'])
    expect(d.deletes.filter((i) => i === 'a')).toHaveLength(3)
  })
})

describe('bounded work and cancelling', () => {
  it('batches of 10, at most 3 deletes in flight, the status re-read before every batch', async () => {
    const all = ids(124)
    const d = db(drafts(all))
    const seen: DeleteProgress[] = []
    await runDelete(all, d.deps, { onProgress: (p) => seen.push(p) })
    expect(d.stats().maxInflight).toBeLessThanOrEqual(3)
    expect(d.stats().maxInflight).toBeGreaterThan(1)
    expect(d.reads.filter((r) => r.length <= 10)).toHaveLength(13)
    expect(seen[0].phase).toBe('checking')
    expect(seen[seen.length - 1]).toMatchObject({ phase: 'done', total: 124, processed: 124, deleted: 124, failed: 0, batches: 13 })
  })

  it('cancelling stops between batches, keeps what was deleted, and lists what was not run', async () => {
    const ctl = new AbortController()
    const d = db(drafts(ids(40)), { onDelete: (id) => { if (id === 'r12') ctl.abort() } })
    const res = await runDelete(ids(40), d.deps, { signal: ctl.signal, concurrency: 1 })
    expect(res.stoppedBy).toBe('cancelled')
    expect(res.deleted.length).toBeGreaterThanOrEqual(10)
    expect(res.deleted.length).toBeLessThan(40)
    expect(res.deleted.length + res.notRun.length).toBe(40)
    expect(res.notRun.every((i) => d.rows.has(i))).toBe(true)
  })

  it('an already-cancelled run deletes nothing', async () => {
    const ctl = new AbortController(); ctl.abort()
    const d = db(drafts(ids(5)))
    const res = await runDelete(ids(5), d.deps, { signal: ctl.signal })
    expect(d.deletes).toHaveLength(0)
    expect(res.notRun).toHaveLength(5)
  })
})
