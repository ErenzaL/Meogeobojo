import type { Visibility } from './schema'

/**
 * Deleting restaurants from the Admin. It is a plain DELETE of the `restaurant_overrides` row by a SUPER ADMIN (the existing
 * row-level policy; the database removes the restaurant's campus links, menus and photo rows with it, audits it with who did
 * it and the whole deleted row, and keeps the publishing history). Nothing here bypasses that: this module only decides WHICH
 * restaurants may be deleted right now and does it in small, checked steps.
 *
 *  - A PUBLISHED restaurant is never deleted: hide it first. (Deleting a published place would drop it from the app mid-use.)
 *  - A restaurant with a SCHEDULED publish is never deleted: cancel the schedule first (the job would only fail later).
 *  - The status of every restaurant is re-read from the database before each batch, so a restaurant that was published or
 *    scheduled by someone else in the meantime is skipped instead of deleted.
 *  - Row-level security does not raise an error for a caller who may not delete: it silently deletes NOTHING. So the number of
 *    rows a delete removed is checked: zero while the restaurant is still there means "not allowed" and stops the run; it is
 *    never reported as a success.
 *  - A call that failed without a database error code (a dropped connection) may or may not have been applied: the restaurant is
 *    looked up again before a retry, and if it is gone it counts as deleted.
 */
export type RestaurantRow = { id: string; name_ko: string; visibility: Visibility }
export type DeleteSkipReason = 'published' | 'scheduled' | 'gone'
export type DeleteSkip = { id: string; name: string; reason: DeleteSkipReason }
export type DeleteFailure = { id: string; name: string; message: string; code?: string }

export type DeleteDeps = {
  /** Current rows (id, name, visibility) of these ids. An id that is not returned does not exist (any more). */
  readRows: (ids: string[]) => Promise<RestaurantRow[]>
  /** Ids that have a scheduled publish right now. */
  scheduledIds: () => Promise<Set<string>>
  /** Deletes the row and returns how many rows were actually removed. */
  deleteOne: (id: string) => Promise<number>
  sleep?: (ms: number) => Promise<void>
}
export type DeleteOptions = { batchSize?: number; concurrency?: number; retries?: number; signal?: AbortSignal; onProgress?: (p: DeleteProgress) => void }
export type DeleteProgress = { phase: 'checking' | 'running' | 'done'; total: number; processed: number; deleted: number; skipped: number; failed: number; batch: number; batches: number }
export type DeleteResult = {
  total: number
  deleted: string[]
  skipped: DeleteSkip[]
  failed: DeleteFailure[]
  notRun: string[]
  stoppedBy: 'cancelled' | 'forbidden' | null
}

const errCode = (e: unknown) => (typeof e === 'object' && e && 'code' in e ? String((e as { code: unknown }).code) : undefined)
const errMsg = (e: unknown) => (e instanceof Error ? e.message : typeof e === 'object' && e && 'message' in e ? String((e as { message: unknown }).message) : '알 수 없는 오류')
const chunked = <T,>(items: T[], n: number) => Array.from({ length: Math.ceil(items.length / n) }, (_, i) => items.slice(i * n, i * n + n))

/** What may be done with a restaurant in this state. */
export const deleteVerdict = (r: RestaurantRow, scheduled: Set<string>): 'delete' | 'published' | 'scheduled' =>
  r.visibility === 'published' ? 'published' : scheduled.has(r.id) ? 'scheduled' : 'delete'

async function readAll(ids: string[], deps: DeleteDeps): Promise<Map<string, RestaurantRow>> {
  const out = new Map<string, RestaurantRow>()
  for (const part of chunked(ids, 200)) for (const r of await deps.readRows(part)) out.set(r.id, r)
  return out
}

export async function runDelete(ids: string[], deps: DeleteDeps, opts: DeleteOptions = {}): Promise<DeleteResult> {
  const batchSize = Math.max(1, opts.batchSize ?? 10)
  const concurrency = Math.max(1, opts.concurrency ?? 3)
  const retries = opts.retries ?? 2
  const sleep = deps.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)))
  const unique = [...new Set(ids)]
  const res: DeleteResult = { total: unique.length, deleted: [], skipped: [], failed: [], notRun: [], stoppedBy: null }
  const progress = (phase: DeleteProgress['phase'], batch: number, batches: number) => opts.onProgress?.({
    phase, total: res.total, processed: res.deleted.length + res.skipped.length + res.failed.length, deleted: res.deleted.length, skipped: res.skipped.length, failed: res.failed.length, batch, batches,
  })

  progress('checking', 0, 0)
  const first = await readAll(unique, deps)
  const scheduled0 = await deps.scheduledIds()
  const work: string[] = []
  for (const id of unique) {
    const row = first.get(id)
    if (!row) { res.skipped.push({ id, name: '', reason: 'gone' }); continue }
    const v = deleteVerdict(row, scheduled0)
    if (v === 'delete') work.push(id); else res.skipped.push({ id, name: row.name_ko, reason: v })
  }

  const batches = chunked(work, batchSize)
  let n = 0
  for (const batchIds of batches) {
    n++
    if (opts.signal?.aborted) { res.stoppedBy = 'cancelled'; break }
    progress('running', n, batches.length)
    // look again, right before acting: published / scheduled by someone else meanwhile, or already deleted
    const now = await readAll(batchIds, deps)
    const scheduled = await deps.scheduledIds()
    const todo: string[] = []
    for (const id of batchIds) {
      const row = now.get(id)
      if (!row) { res.skipped.push({ id, name: first.get(id)?.name_ko ?? '', reason: 'gone' }); continue }
      const v = deleteVerdict(row, scheduled)
      if (v === 'delete') todo.push(id); else res.skipped.push({ id, name: row.name_ko, reason: v })
    }

    let next = 0
    let fatal = false
    const one = async (id: string) => {
      const name = first.get(id)?.name_ko ?? ''
      for (let attempt = 0; ; attempt++) {
        try {
          const removed = await deps.deleteOne(id)
          if (removed > 0) { res.deleted.push(id); return }
          // Zero rows removed, no error: either it is gone already, or row-level security refused (not a super admin).
          const [still] = await deps.readRows([id])
          if (!still) { res.skipped.push({ id, name, reason: 'gone' }); return }
          fatal = true
          res.failed.push({ id, name, message: '삭제 권한이 없어요 (최고 관리자만 삭제할 수 있어요)', code: '42501' })
          return
        } catch (e) {
          if (errCode(e) === '42501') { fatal = true; res.failed.push({ id, name, message: errMsg(e), code: '42501' }); return }
          const code = errCode(e)
          if (code !== undefined || attempt >= retries) { res.failed.push({ id, name, message: errMsg(e), code }); return }
          await sleep(300 * 3 ** attempt)
          const [again] = await deps.readRows([id]).catch(() => [undefined] as (RestaurantRow | undefined)[])
          if (!again) { res.deleted.push(id); return } // the dropped call had in fact been applied
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
    const done = new Set([...res.deleted, ...res.failed.map((f) => f.id), ...res.skipped.map((s) => s.id)])
    res.notRun = work.filter((id) => !done.has(id))
  }
  progress('done', n, batches.length)
  return res
}
