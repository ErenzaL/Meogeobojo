import type { JobState } from './kakaoScan'
import { redact, safeCode } from './kakaoDiag'

/**
 * Remembers the PROGRESS of a scan (job id, which grid squares are done, failed or pending, the page cursor of each,
 * counters) in this browser so an interrupted scan can be continued instead of restarted.
 *
 * It deliberately stores NO place data: no names, addresses, coordinates or ids of places. Kakao's terms allow
 * Local API results in real time only, so the found places live in the page's memory (and become permanent only
 * when an admin registers them, which stores the place id and a name label as before). A resumed scan therefore
 * continues the unfinished squares; places found before the interruption are not restored.
 */
const KEY = (campusId: string) => `kakao-import-job:${campusId}`

type Store = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>
const defaultStore = (): Store | null => { try { return globalThis.localStorage ?? null } catch { return null } }

export function saveJob(job: JobState, store: Store | null = defaultStore()): void {
  if (!store) return
  try {
    const safe: JobState = { ...job, updatedAt: new Date().toISOString(), tasks: job.tasks.map((t) => (t.error ? { ...t, error: { ...t.error, message: redact(t.error.message), code: t.error.code ? safeCode(t.error.code) : undefined } } : t)) }
    store.setItem(KEY(job.campus.id), JSON.stringify(safe))
  } catch { /* storage full or blocked: the scan still works, it just cannot be resumed */ }
}

export function clearJob(campusId: string, store: Store | null = defaultStore()): void {
  try { store?.removeItem(KEY(campusId)) } catch { /* ignore */ }
}

const isTask = (t: unknown): boolean => {
  const o = t as Record<string, unknown> | null
  return !!o && typeof o.key === 'string' && (o.group === 'FD6' || o.group === 'CE7') && ['pending', 'done', 'failed'].includes(o.status as string)
    && [o.depth, o.dx, o.dy, o.half, o.page].every((n) => typeof n === 'number' && Number.isFinite(n))
}

/** The stored job of this university, or null if there is none or it is not a valid job of this version. */
export function loadJob(campusId: string, store: Store | null = defaultStore()): JobState | null {
  try {
    const raw = store?.getItem(KEY(campusId))
    if (!raw) return null
    const j = JSON.parse(raw) as JobState
    if (j?.v !== 1 || typeof j.id !== 'string' || j.campus?.id !== campusId || !Array.isArray(j.tasks) || !j.tasks.every(isTask)) return null
    return j
  } catch { return null }
}

/** The grid of a stored job is only valid for the same centre and radius. */
export const jobMatchesCampus = (job: JobState, c: { latitude: number; longitude: number; radiusM: number }) =>
  job.campus.latitude === c.latitude && job.campus.longitude === c.longitude && job.campus.radiusM === c.radiusM

export const hasUnfinishedWork = (job: JobState) => job.tasks.some((t) => t.status !== 'done')

export function jobSummary(job: JobState) {
  const count = (s: string) => job.tasks.filter((t) => t.status === s).length
  return { jobId: job.id, total: job.tasks.length, done: count('done'), failed: count('failed'), pending: count('pending'), radiusM: job.campus.radiusM, updatedAt: job.updatedAt }
}
