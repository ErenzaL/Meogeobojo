import type { Visibility } from './schema'

/**
 * Bulk publish / hide for restaurants. It never changes a restaurant itself: every restaurant goes through the SAME
 * database function the single 공개 / 숨기기 buttons use (`cms_set_visibility`), one call each, so the admin-role check,
 * the publication validation, the per-restaurant lock, the versioning and the audit entry all still happen, per
 * restaurant, in the database. This module only decides WHICH restaurants to call it for, and in what bounded steps.
 *
 *  - The current status of every restaurant is re-read from the database right before it is acted on (once up front,
 *    and again for each batch), because `cms_set_visibility` would happily write a second version for a restaurant that
 *    is already in the target state. Those are skipped, so repeating a request is safe.
 *  - Bulk publish touches `draft` and `hidden` restaurants only; `archived` ones were put away on purpose and are
 *    skipped. Bulk hide touches `published` ones only.
 *  - Batches of [batchSize] with at most [concurrency] calls in flight; a failure marks just that restaurant; a
 *    permission error stops the run (nothing else would succeed either).
 *  - A call that failed without a database error code (a dropped connection) may or may not have been applied, so the
 *    restaurant is re-read before it is tried again: if it is already in the target state it counts as done.
 */
export type BulkTarget = 'published' | 'hidden'
export type RowInfo = { id: string; name_ko: string; visibility: Visibility }
export type SkipReason = 'already' | 'archived'
export type BulkFailure = { id: string; name: string; message: string; code?: string }
export type BulkSkip = { id: string; name: string; reason: SkipReason }

export type BulkDeps = {
  /** Current rows (id, name, visibility) from the database for these ids. Ids it does not return no longer exist / are not visible. */
  readStatus: (ids: string[]) => Promise<RowInfo[]>
  /** `cms_set_visibility('restaurant', id, to, reason)`. */
  setVisibility: (id: string, to: BulkTarget, reason: string) => Promise<unknown>
  sleep?: (ms: number) => Promise<void>
}

export type BulkOptions = {
  batchSize?: number
  concurrency?: number
  /** Retries for a call that failed without a database error code. */
  retries?: number
  /** Short id that ties together the audit entries of one bulk action. */
  tag?: string
  signal?: AbortSignal
  onProgress?: (p: BulkProgress) => void
}

export type BulkProgress = {
  phase: 'checking' | 'running' | 'done'
  total: number
  /** Restaurants finished (done, skipped, failed). */
  processed: number
  ok: number
  skipped: number
  failed: number
  batch: number
  batches: number
}

export type BulkResult = {
  to: BulkTarget
  tag: string
  total: number
  ok: string[]
  skipped: BulkSkip[]
  failed: BulkFailure[]
  /** Never attempted because the run stopped first. */
  notRun: string[]
  stoppedBy: 'cancelled' | 'forbidden' | null
}

export const newTag = () => Math.random().toString(16).slice(2, 10).padEnd(8, '0')
export const reasonWithTag = (tag: string, to: BulkTarget, reason: string) => `일괄 ${to === 'published' ? '공개' : '숨김'} [${tag}]: ${reason}`

const errCode = (e: unknown) => (typeof e === 'object' && e && 'code' in e ? String((e as { code: unknown }).code) : undefined)
const errMsg = (e: unknown) => (e instanceof Error ? e.message : typeof e === 'object' && e && 'message' in e ? String((e as { message: unknown }).message) : '알 수 없는 오류')
/** SQLSTATE 42501: the database says this caller may not do it. */
const isForbidden = (e: unknown) => errCode(e) === '42501'

/** What would happen to a restaurant in [visibility] for [to]: process it or skip it (and why). */
export const classify = (visibility: Visibility, to: BulkTarget): 'process' | SkipReason =>
  to === 'published' ? (visibility === 'published' ? 'already' : visibility === 'archived' ? 'archived' : 'process') : visibility === 'published' ? 'process' : 'already'

const chunked = <T,>(items: T[], n: number) => Array.from({ length: Math.ceil(items.length / n) }, (_, i) => items.slice(i * n, i * n + n))

async function readAll(ids: string[], deps: BulkDeps): Promise<Map<string, RowInfo>> {
  const out = new Map<string, RowInfo>()
  for (const part of chunked(ids, 200)) for (const r of await deps.readStatus(part)) out.set(r.id, r)
  return out
}

export async function runBulkVisibility(ids: string[], to: BulkTarget, reason: string, deps: BulkDeps, opts: BulkOptions = {}): Promise<BulkResult> {
  const batchSize = Math.max(1, opts.batchSize ?? 10)
  const concurrency = Math.max(1, opts.concurrency ?? 3)
  const retries = opts.retries ?? 2
  const tag = opts.tag ?? newTag()
  const sleep = deps.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)))
  const unique = [...new Set(ids)]

  const res: BulkResult = { to, tag, total: unique.length, ok: [], skipped: [], failed: [], notRun: [], stoppedBy: null }
  const progress = (phase: BulkProgress['phase'], batch: number, batches: number) => opts.onProgress?.({
    phase, total: res.total, processed: res.ok.length + res.skipped.length + res.failed.length, ok: res.ok.length, skipped: res.skipped.length, failed: res.failed.length, batch, batches,
  })

  progress('checking', 0, 0)
  // 1. What is the database's view of these restaurants right now?
  const first = await readAll(unique, deps)
  const work: string[] = []
  for (const id of unique) {
    const row = first.get(id)
    if (!row) { res.failed.push({ id, name: '', message: '이미 삭제됐거나 볼 수 없는 식당이에요', code: 'not_found' }); continue }
    const c = classify(row.visibility, to)
    if (c === 'process') work.push(id); else res.skipped.push({ id, name: row.name_ko, reason: c })
  }

  // 2. Bounded batches, each re-checked just before it runs.
  const batches = chunked(work, batchSize)
  let n = 0
  for (const batchIds of batches) {
    n++
    if (opts.signal?.aborted) { res.stoppedBy = 'cancelled'; break }
    progress('running', n, batches.length)
    const now = await readAll(batchIds, deps)
    const todo: string[] = []
    for (const id of batchIds) {
      const row = now.get(id)
      if (!row) { res.failed.push({ id, name: first.get(id)?.name_ko ?? '', message: '이미 삭제됐거나 볼 수 없는 식당이에요', code: 'not_found' }); continue }
      const c = classify(row.visibility, to)
      if (c === 'process') todo.push(id); else res.skipped.push({ id, name: row.name_ko, reason: c }) // someone else got there first
    }

    let next = 0
    let fatal = false
    const one = async (id: string) => {
      const name = first.get(id)?.name_ko ?? ''
      for (let attempt = 0; ; attempt++) {
        try {
          await deps.setVisibility(id, to, reasonWithTag(tag, to, reason))
          res.ok.push(id)
          return
        } catch (e) {
          if (isForbidden(e)) { fatal = true; res.failed.push({ id, name, message: errMsg(e), code: '42501' }); return }
          const code = errCode(e)
          if (code !== undefined || attempt >= retries) { res.failed.push({ id, name, message: errMsg(e), code }); return }
          // No database code: the connection may have dropped AFTER the change was made. Look before trying again.
          await sleep(300 * 3 ** attempt)
          const [again] = await deps.readStatus([id]).catch(() => [] as RowInfo[])
          if (again && classify(again.visibility, to) !== 'process') { res.ok.push(id); return }
        }
      }
    }
    const worker = async () => {
      while (!fatal && !opts.signal?.aborted) {
        const id = todo[next++]
        if (id === undefined) return
        await one(id)
        progress('running', n, batches.length)
      }
    }
    await Promise.all(Array.from({ length: Math.min(concurrency, todo.length) }, worker))
    if (fatal) { res.stoppedBy = 'forbidden'; break }
    if (opts.signal?.aborted) { res.stoppedBy = 'cancelled'; break }
  }
  if (res.stoppedBy) {
    const done = new Set([...res.ok, ...res.failed.map((f) => f.id), ...res.skipped.map((s) => s.id)])
    res.notRun = work.filter((id) => !done.has(id))
  }
  progress('done', n, batches.length)
  return res
}
