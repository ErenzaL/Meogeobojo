import { describe, expect, it } from 'vitest'
import { type BulkDeps, type BulkProgress, classify, reasonWithTag, type RowInfo, runBulkVisibility } from './bulkVisibility'
import type { Visibility } from './schema'

/** A tiny in-memory database behind the two functions the engine uses. */
function db(initial: Record<string, Visibility>, hooks: { fail?: (id: string, n: number) => unknown; onSet?: (id: string) => void; names?: Record<string, string> } = {}) {
  const state = new Map(Object.entries(initial))
  const calls: { id: string; to: string; reason: string }[] = []
  const reads: string[][] = []
  const attempts = new Map<string, number>()
  let inflight = 0
  let maxInflight = 0
  const deps: BulkDeps & { sleep: (ms: number) => Promise<void> } = {
    sleep: async () => undefined,
    readStatus: async (ids) => {
      reads.push(ids)
      return ids.filter((id) => state.has(id)).map((id): RowInfo => ({ id, name_ko: hooks.names?.[id] ?? `식당 ${id}`, visibility: state.get(id)! }))
    },
    setVisibility: async (id, to, reason) => {
      inflight++; maxInflight = Math.max(maxInflight, inflight)
      await Promise.resolve()
      inflight--
      const n = (attempts.get(id) ?? 0) + 1
      attempts.set(id, n)
      calls.push({ id, to, reason })
      const f = hooks.fail?.(id, n)
      if (f !== undefined && f !== null) { if (f === 'applied-but-lost') { state.set(id, to); throw new TypeError('Failed to fetch') } throw f }
      state.set(id, to)
      hooks.onSet?.(id)
      return 1
    },
  }
  return { deps, state, calls, reads, stats: () => ({ maxInflight }), get: (id: string) => state.get(id) }
}
const ids = (n: number, prefix = 'r') => Array.from({ length: n }, (_, i) => `${prefix}${i}`)
const allDraft = (list: string[]): Record<string, Visibility> => Object.fromEntries(list.map((i) => [i, 'draft' as Visibility]))

describe('what a bulk action does to each status', () => {
  it('publish: draft and hidden are published; published is already done; archived is left alone', () => {
    expect(classify('draft', 'published')).toBe('process')
    expect(classify('hidden', 'published')).toBe('process')
    expect(classify('published', 'published')).toBe('already')
    expect(classify('archived', 'published')).toBe('archived')
  })
  it('hide: only published ones change; everything else is already not public', () => {
    expect(classify('published', 'hidden')).toBe('process')
    for (const v of ['draft', 'hidden', 'archived'] as const) expect(classify(v, 'hidden')).toBe('already')
  })
})

describe('bulk publish', () => {
  it('goes through cms_set_visibility once per restaurant, with a tagged reason, and changes nothing else', async () => {
    const d = db(allDraft(ids(25)))
    const res = await runBulkVisibility(ids(25), 'published', '개강 시즌', d.deps, { tag: 'ab12cd34' })
    expect(res.ok).toHaveLength(25)
    expect(res.failed).toEqual([])
    expect(d.calls).toHaveLength(25)
    expect(new Set(d.calls.map((c) => c.id)).size).toBe(25) // each exactly once
    expect(d.calls.every((c) => c.to === 'published' && c.reason === '일괄 공개 [ab12cd34]: 개강 시즌')).toBe(true)
    expect(ids(25).every((i) => d.get(i) === 'published')).toBe(true)
    expect(res.stoppedBy).toBeNull()
  })

  it('only the selected restaurants are touched', async () => {
    const all = ids(30)
    const d = db(allDraft(all))
    await runBulkVisibility(all.slice(0, 7), 'published', 'x', d.deps)
    expect(all.filter((i) => d.get(i) === 'published')).toEqual(all.slice(0, 7))
    expect(all.slice(7).every((i) => d.get(i) === 'draft')).toBe(true)
    expect(d.reads.flat().every((i) => all.slice(0, 7).includes(i))).toBe(true) // it did not even look at the others
  })

  it('already-published restaurants are skipped: no RPC, no second version, no second audit entry', async () => {
    const d = db({ a: 'published', b: 'draft', c: 'published', d: 'hidden' })
    const res = await runBulkVisibility(['a', 'b', 'c', 'd'], 'published', 'x', d.deps)
    expect(res.skipped.map((s) => [s.id, s.reason])).toEqual([['a', 'already'], ['c', 'already']])
    expect(d.calls.map((c) => c.id).sort()).toEqual(['b', 'd'])
    expect(res.ok.sort()).toEqual(['b', 'd'])
  })

  it('archived restaurants are not published by a bulk action', async () => {
    const d = db({ a: 'archived', b: 'draft' })
    const res = await runBulkVisibility(['a', 'b'], 'published', 'x', d.deps)
    expect(res.skipped).toEqual([{ id: 'a', name: '식당 a', reason: 'archived' }])
    expect(d.get('a')).toBe('archived')
    expect(d.get('b')).toBe('published')
  })

  it('repeating the same request is safe: the second run calls nothing', async () => {
    const d = db(allDraft(ids(12)))
    await runBulkVisibility(ids(12), 'published', 'x', d.deps)
    const before = d.calls.length
    const again = await runBulkVisibility(ids(12), 'published', 'x', d.deps)
    expect(d.calls.length).toBe(before)
    expect(again.ok).toEqual([])
    expect(again.skipped).toHaveLength(12)
  })

  it('duplicate ids in the request are one restaurant', async () => {
    const d = db({ a: 'draft' })
    const res = await runBulkVisibility(['a', 'a', 'a'], 'published', 'x', d.deps)
    expect(res.total).toBe(1)
    expect(d.calls).toHaveLength(1)
  })

  it('a restaurant that no longer exists is reported, not silently dropped', async () => {
    const d = db({ a: 'draft' })
    const res = await runBulkVisibility(['a', 'ghost'], 'published', 'x', d.deps)
    expect(res.failed).toEqual([{ id: 'ghost', name: '', message: expect.stringContaining('삭제'), code: 'not_found' }])
    expect(res.ok).toEqual(['a'])
  })
})

describe('bulk hide', () => {
  it('hides only published restaurants, with the same RPC', async () => {
    const d = db({ a: 'published', b: 'published', c: 'draft', d: 'archived', e: 'hidden' })
    const res = await runBulkVisibility(['a', 'b', 'c', 'd', 'e'], 'hidden', '점검', d.deps, { tag: '00000001' })
    expect(res.ok.sort()).toEqual(['a', 'b'])
    expect(res.skipped.map((s) => s.id).sort()).toEqual(['c', 'd', 'e'])
    expect(d.calls.every((c) => c.to === 'hidden' && c.reason === '일괄 숨김 [00000001]: 점검')).toBe(true)
    expect(['c', 'd', 'e'].map((i) => d.get(i))).toEqual(['draft', 'archived', 'hidden'])
  })
})

describe('bounded work', () => {
  it('works in batches of 10 with at most 3 calls in flight, re-reading the status before every batch', async () => {
    const list = ids(124)
    const d = db(allDraft(list))
    const seen: BulkProgress[] = []
    await runBulkVisibility(list, 'published', 'x', d.deps, { onProgress: (p) => seen.push(p) })
    expect(d.stats().maxInflight).toBeLessThanOrEqual(3)
    expect(d.stats().maxInflight).toBeGreaterThan(1)
    const batchReads = d.reads.filter((r) => r.length <= 10)
    expect(batchReads).toHaveLength(13) // 124 restaurants -> 13 batches, each re-checked
    expect(seen[0].phase).toBe('checking')
    expect(seen[seen.length - 1]).toMatchObject({ phase: 'done', total: 124, processed: 124, ok: 124, failed: 0, batches: 13 })
    expect(Math.max(...seen.map((p) => p.processed))).toBe(124)
  })

  it('looks the status up in chunks of at most 200', async () => {
    const list = ids(450)
    const d = db(allDraft(list))
    await runBulkVisibility(list, 'published', 'x', d.deps, { batchSize: 50 })
    expect(Math.max(...d.reads.map((r) => r.length))).toBeLessThanOrEqual(200)
  })

  it('a restaurant changed by someone else while the run was going is skipped, not published twice', async () => {
    const list = ids(25)
    const d: ReturnType<typeof db> = db(allDraft(list), { onSet: (id) => { if (id === 'r0') d.state.set('r15', 'published') } }) // another admin publishes r15 meanwhile
    const res = await runBulkVisibility(list, 'published', 'x', d.deps, { concurrency: 1 })
    expect(d.calls.map((c) => c.id)).not.toContain('r15')
    expect(res.skipped.map((s) => s.id)).toEqual(['r15'])
    expect(res.ok).toHaveLength(24)
  })
})

describe('partial failure and retry', () => {
  it('one failing restaurant fails alone: the others are done, and the failure names the id and the reason', async () => {
    const bad = Object.assign(new Error('가격이 올바르지 않아요 (최저 ≤ 최고, 0 이상)'), { code: '22023' })
    const d = db(allDraft(ids(30)), { fail: (id) => (id === 'r3' || id === 'r22' ? bad : null), names: { r3: '국수집', r22: '라멘' } })
    const res = await runBulkVisibility(ids(30), 'published', 'x', d.deps)
    expect(res.ok).toHaveLength(28)
    expect(res.failed.map((f) => [f.id, f.name, f.code])).toEqual([['r3', '국수집', '22023'], ['r22', '라멘', '22023']])
    expect(res.failed[0].message).toContain('가격이 올바르지 않아요')
    expect(d.get('r3')).toBe('draft')
    expect(res.stoppedBy).toBeNull()
    expect(d.calls.filter((c) => c.id === 'r3')).toHaveLength(1) // a database refusal is not retried blindly
  })

  it('retrying only the failed ones fixes them and touches nothing else', async () => {
    let broken = true
    const bad = Object.assign(new Error('conflict'), { code: '40001' })
    const d = db(allDraft(ids(30)), { fail: (id) => (broken && (id === 'r3' || id === 'r22') ? bad : null) })
    const first = await runBulkVisibility(ids(30), 'published', 'x', d.deps)
    const before = d.calls.length
    broken = false
    const retry = await runBulkVisibility(first.failed.map((f) => f.id), 'published', 'x', d.deps)
    expect(retry.ok.sort()).toEqual(['r22', 'r3'])
    expect(d.calls.length - before).toBe(2)
    expect(ids(30).every((i) => d.get(i) === 'published')).toBe(true)
  })

  it('a permission error (SQLSTATE 42501) stops the run at once; the rest is reported as not run', async () => {
    const denied = Object.assign(new Error('permission denied: admin role required'), { code: '42501' })
    const d = db(allDraft(ids(124)), { fail: () => denied })
    const res = await runBulkVisibility(ids(124), 'published', 'x', d.deps)
    expect(res.stoppedBy).toBe('forbidden')
    expect(d.calls.length).toBeLessThanOrEqual(3) // only the first calls in flight, not 124
    expect(res.ok).toEqual([])
    expect(res.failed.length + res.notRun.length).toBe(124)
    expect(res.notRun.length).toBeGreaterThan(100)
    expect(ids(124).every((i) => d.get(i) === 'draft')).toBe(true)
  })

  it('a dropped connection: if the change had in fact been applied it counts once and is not repeated', async () => {
    const d = db({ a: 'draft' }, { fail: (_id, n) => (n === 1 ? 'applied-but-lost' : null) })
    const res = await runBulkVisibility(['a'], 'published', 'x', d.deps)
    expect(res.ok).toEqual(['a'])
    expect(d.calls).toHaveLength(1) // not written a second time
  })

  it('a dropped connection where nothing was applied is retried, then succeeds', async () => {
    let n = 0
    const d = db({ a: 'draft' }, { fail: () => (n++ < 1 ? new TypeError('Failed to fetch') : null) })
    const res = await runBulkVisibility(['a'], 'published', 'x', d.deps)
    expect(res.ok).toEqual(['a'])
    expect(d.calls).toHaveLength(2)
  })

  it('a connection that keeps failing gives up after the retries and is reported', async () => {
    const d = db({ a: 'draft', b: 'draft' }, { fail: (id) => (id === 'a' ? new TypeError('Failed to fetch') : null) })
    const res = await runBulkVisibility(['a', 'b'], 'published', 'x', d.deps, { retries: 2 })
    expect(res.failed.map((f) => f.id)).toEqual(['a'])
    expect(res.ok).toEqual(['b'])
    expect(d.calls.filter((c) => c.id === 'a')).toHaveLength(3)
  })
})

describe('cancellation', () => {
  it('stops between batches, keeps what was done, and says what was not run', async () => {
    const ctl = new AbortController()
    const d = db(allDraft(ids(40)), { onSet: (id) => { if (id === 'r12') ctl.abort() } })
    const res = await runBulkVisibility(ids(40), 'published', 'x', d.deps, { signal: ctl.signal, concurrency: 1 })
    expect(res.stoppedBy).toBe('cancelled')
    expect(res.ok.length).toBeGreaterThanOrEqual(10)
    expect(res.ok.length).toBeLessThan(40)
    expect(res.ok.length + res.notRun.length).toBe(40)
    expect(res.notRun.every((i) => d.get(i) === 'draft')).toBe(true)
  })
  it('an already-cancelled run changes nothing', async () => {
    const ctl = new AbortController(); ctl.abort()
    const d = db(allDraft(ids(5)))
    const res = await runBulkVisibility(ids(5), 'published', 'x', d.deps, { signal: ctl.signal })
    expect(d.calls).toHaveLength(0)
    expect(res.notRun).toHaveLength(5)
  })
})

describe('audit reason', () => {
  it('names the action and a batch tag so one bulk run can be found again in the history', () => {
    expect(reasonWithTag('ab12cd34', 'published', '개강')).toBe('일괄 공개 [ab12cd34]: 개강')
    expect(reasonWithTag('ab12cd34', 'hidden', '점검')).toBe('일괄 숨김 [ab12cd34]: 점검')
  })
})
