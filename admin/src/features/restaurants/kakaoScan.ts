import { isFoodPlace, KAKAO_QUERIES, type KakaoDoc } from './kakao'
import { redact, safeCode } from './kakaoDiag'
import { cellCentre, cellRadiusM, cellTouchesCampus, childCells, type Campus, type Cell, placeDistanceM, rootCell } from './kakaoGeo'

/** What one request asks of the server: ONE PAGE of one circle for one food group, optionally one keyword. */
export type CellQuery = { campusId: string; lat: number; lng: number; radiusM: number; group: Group; query?: string; page: number }
export type Group = 'FD6' | 'CE7'
export type FailKind = 'rate_limited' | 'unavailable' | 'network' | 'timeout' | 'rejected' | 'not_deployed' | 'forbidden' | 'aborted'
export type CellOutcome =
  | { ok: true; docs: KakaoDoc[]; truncated: boolean; kakaoCalls: number; total: number; /** the cursor: the next page of this cell, or null/absent when it was the last */ nextPage?: number | null; universityRadiusM?: number }
  | { ok: false; kind: FailKind; status?: number; code?: string; message: string }
export type SearchCell = (q: CellQuery, signal: AbortSignal) => Promise<CellOutcome>

// ---------------------------------------------------------------------------------------------------------------
// the job: everything needed to continue a scan, and nothing from Kakao (no place data)
// ---------------------------------------------------------------------------------------------------------------
export type TaskError = { kind: FailKind; status?: number; code?: string; message: string }
export type JobTask = {
  /** Stable id of this square + group + keyword. */
  key: string
  group: Group
  query?: string
  depth: number
  dx: number
  dy: number
  half: number
  /** done: fully read. failed: gave up after retries (the cursor below says where to continue). pending: not finished. */
  status: 'pending' | 'done' | 'failed'
  /** The CURSOR: the next page to request for this square (1..3). */
  page: number
  /** Pages already read. */
  pages: number
  truncated?: boolean
  /** Still over Kakao's cap at the finest level (group searches only). */
  saturated?: boolean
  error?: TaskError
}
export type StopReason = 'cancelled' | 'budget' | 'rate_limited' | 'not_deployed' | 'forbidden' | 'rejected'
export type JobStatus = 'running' | 'complete' | 'partial' | 'stopped' | 'cancelled'
export type JobState = {
  v: 1
  id: string
  campus: Campus
  createdAt: string
  updatedAt: string
  limits: { maxDepth: number; groups: Group[]; keywords: string[] }
  phase: 'grid' | 'keywords' | 'done'
  tasks: JobTask[]
  counters: { invocations: number; kakaoCalls: number; retries: number }
  status: JobStatus
  stoppedBy: StopReason | null
}

/** The places found in this page session. Memory only: never persisted (Kakao's terms). */
export type ScanMemory = { found: Map<string, Place>; outside: Set<string> }
export const newMemory = (): ScanMemory => ({ found: new Map(), outside: new Set() })

export type ScanOptions = {
  /** How many times a square may be split into quarters (3000 m radius: 6 levels = squares of ~94 m). */
  maxDepth?: number
  /** Ceilings PER RUN, so a scan can never run away (every attempt, including retries, counts). A resumed run gets a fresh allowance. */
  maxInvocations?: number
  maxKakaoCalls?: number
  /** Searches in flight at once. Starts conservative and drops by one for every rate-limit answer (never below 1). */
  concurrency?: number
  /** Retries per request for rate limits / outages / timeouts / network (never for refusals). */
  retries?: number
  baseDelayMs?: number
  /** A request that has not answered in this long is cancelled and retried. */
  timeoutMs?: number
  /** Stop after this many squares in a row ran out of retries on a rate limit. */
  rateLimitStop?: number
  /** Stop after this many squares in a row were refused (HTTP 4xx): something is wrong with the request itself. */
  rejectedStop?: number
  /** Call [onCheckpoint] after this many squares finished (and at the end), so the caller can save the job. */
  batchSize?: number
  keywords?: readonly string[]
  groups?: readonly Group[]
  sleep?: (ms: number, signal: AbortSignal) => Promise<void>
  random?: () => number
  onProgress?: (p: Progress) => void
  onCheckpoint?: (job: JobState) => void
  signal?: AbortSignal
  /** Reuse the places of an earlier run of the same job (same page session) so partial results are kept. */
  memory?: ScanMemory
  /** Re-try squares that failed in an earlier run (default true). */
  retryFailed?: boolean
}

export type Progress = {
  jobId: string
  phase: 'grid' | 'keywords' | 'done'
  radiusM: number
  cellsDone: number
  cellsQueued: number
  cellsSaturated: number
  invocations: number
  kakaoCalls: number
  retries: number
  /** Distinct places inside the radius so far. */
  unique: number
  /** Distinct places Kakao returned that lie outside the radius (the circles overshoot the square) and are dropped. */
  outside: number
  failed: number
  /** Searches allowed in flight right now (lowered by rate limits). */
  concurrency: number
}

export type FailedCell = { group: Group; query?: string; depth: number; lat: number; lng: number; radiusM: number; page: number; kind: FailKind; status?: number; code?: string; message: string }
export type ErrorSummary = { kind: FailKind; status?: number; code?: string; message: string; count: number; stage: 'grid_search' | 'keyword_search' }
export type Place = KakaoDoc & { distanceM: number }

export type ScanResult = {
  places: Place[]
  progress: Progress
  job: JobState
  failedCells: FailedCell[]
  /** Distinct failures with their HTTP status / code, for the Admin to show (no secrets: messages are redacted). */
  errors: ErrorSummary[]
  /** Squares that were still over Kakao's cap at the finest level: places there may be missing. */
  saturatedCells: { group: Group; lat: number; lng: number; radiusM: number; stillTruncatedAfterKeywords: boolean }[]
  /** Squares not finished because the run stopped first (they keep their page cursor and can be resumed). */
  unsearchedCells: number
  stoppedBy: StopReason | null
  /** True only if every needed square was read without failure or cap. Even then it is "what Kakao exposes", not a census. */
  complete: boolean
  warnings: string[]
}

const defaultSleep = (ms: number, signal: AbortSignal) =>
  new Promise<void>((resolve) => {
    if (signal.aborted) return resolve()
    const t = setTimeout(done, ms)
    function done() { signal.removeEventListener('abort', done); clearTimeout(t); resolve() }
    signal.addEventListener('abort', done, { once: true })
  })

const RETRYABLE: ReadonlySet<FailKind> = new Set(['rate_limited', 'unavailable', 'network', 'timeout'])
const errText = (e: unknown) => redact(e instanceof Error ? e.message : String(e))

function makeId(): string {
  try { if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID() } catch { /* fall through */ }
  return `job-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
}

const taskKey = (group: Group, query: string | undefined, c: Cell) => `${group}|${query ?? ''}|${c.depth}|${Math.round(c.dx)}|${Math.round(c.dy)}`
const cellOf = (t: JobTask): Cell => ({ dx: t.dx, dy: t.dy, half: t.half, depth: t.depth })

/** A fresh job: the root square of the university's circle, once per food group. */
export function newJob(campus: Campus, o: Pick<ScanOptions, 'maxDepth' | 'groups' | 'keywords'> = {}): JobState {
  const now = new Date().toISOString()
  const groups = [...(o.groups ?? (['FD6', 'CE7'] as const))]
  const job: JobState = {
    v: 1, id: makeId(), campus: { ...campus }, createdAt: now, updatedAt: now,
    limits: { maxDepth: o.maxDepth ?? 6, groups, keywords: [...(o.keywords ?? KAKAO_QUERIES)] },
    phase: 'grid', tasks: [], counters: { invocations: 0, kakaoCalls: 0, retries: 0 }, status: 'running', stoppedBy: null,
  }
  const root = rootCell(campus)
  if (cellTouchesCampus(root, campus)) for (const g of groups) job.tasks.push({ key: taskKey(g, undefined, root), group: g, depth: 0, dx: 0, dy: 0, half: root.half, status: 'pending', page: 1, pages: 0 })
  return job
}

/** Convenience: a new job, run to the end of this run's allowance. */
export const scanCampus = (campus: Campus, search: SearchCell, opts: ScanOptions = {}) => runJob(newJob(campus, opts), search, opts)

/**
 * Covers the university's whole configured circle (centre and radius are in `job.campus`, read from the `universities`
 * row by the caller) with an adaptive grid, in small bounded steps:
 *  1. The bounding square of the circle is searched for each food group (FD6 restaurants, CE7 cafes) as one circle,
 *     ONE PAGE PER REQUEST. Kakao hands out at most 45 places per search; when a search reports it was TRUNCATED the
 *     square is split into quarters, down to `maxDepth`. Squares that cannot touch the circle are skipped.
 *  2. Squares still truncated at the finest level are searched again once per existing keyword (the app's category
 *     keywords), because different keywords surface different places of a crowded block.
 * Every place gets its true distance from the campus centre; those beyond the radius are dropped. Places are
 * deduplicated by Kakao place id. Each request has a timeout and is retried with exponential backoff; what still
 * fails marks only THAT square as failed (its page cursor is kept) while everything else carries on. The job is
 * checkpointed every few squares and can be handed back to [runJob] to continue: finished squares are not searched
 * again, failed ones are retried from their cursor. Nothing from Kakao is cached or stored: the result lives in memory.
 */
export async function runJob(job: JobState, search: SearchCell, opts: ScanOptions = {}): Promise<ScanResult> {
  const campus = job.campus
  const maxInvocations = opts.maxInvocations ?? 1500
  const maxKakaoCalls = opts.maxKakaoCalls ?? 3000
  const startConcurrency = Math.max(1, opts.concurrency ?? 3)
  const retries = opts.retries ?? 3
  const baseDelay = opts.baseDelayMs ?? 500
  const timeoutMs = opts.timeoutMs ?? 20000
  const rateLimitStop = opts.rateLimitStop ?? 5
  const rejectedStop = opts.rejectedStop ?? 3
  const batchSize = Math.max(1, opts.batchSize ?? 8)
  const maxDepth = job.limits.maxDepth
  const sleep = opts.sleep ?? defaultSleep
  const random = opts.random ?? Math.random
  const memory = opts.memory ?? newMemory()

  const ctl = new AbortController()
  const outer = opts.signal
  if (outer) { if (outer.aborted) ctl.abort(); else outer.addEventListener('abort', () => ctl.abort(), { once: true }) }
  const signal = ctl.signal

  const state: { stoppedBy: StopReason | null; limit: number; degraded: boolean } = { stoppedBy: null, limit: startConcurrency, degraded: false }
  let consecutiveRateLimited = 0
  let consecutiveRejected = 0
  let runInvocations = 0
  let runKakaoCalls = 0
  let cellsDone = job.tasks.filter((t) => t.status === 'done').length
  let sinceCheckpoint = 0

  // Squares that failed in an earlier run are tried again from their cursor.
  if (opts.retryFailed ?? true) for (const t of job.tasks) if (t.status === 'failed') { t.status = 'pending'; t.error = undefined }
  job.status = 'running'
  job.stoppedBy = null

  const byKey = new Map(job.tasks.map((t) => [t.key, t]))
  const queue: JobTask[] = job.tasks.filter((t) => t.status === 'pending')
  let inflight = 0
  let waiters: (() => void)[] = []
  const notify = () => { const w = waiters; waiters = []; for (const r of w) r() }
  const park = () => new Promise<void>((r) => waiters.push(r))
  const stop = (why: StopReason) => { if (!state.stoppedBy) state.stoppedBy = why; ctl.abort() }

  const addTask = (group: Group, query: string | undefined, c: Cell) => {
    const key = taskKey(group, query, c)
    if (byKey.has(key)) return
    const t: JobTask = { key, group, query, depth: c.depth, dx: c.dx, dy: c.dy, half: c.half, status: 'pending', page: 1, pages: 0 }
    byKey.set(key, t); job.tasks.push(t); queue.push(t)
  }

  const snapshot = (): Progress => ({
    jobId: job.id, phase: job.phase, radiusM: campus.radiusM, cellsDone,
    cellsQueued: queue.length + inflight, cellsSaturated: job.tasks.filter((t) => t.saturated).length,
    invocations: job.counters.invocations, kakaoCalls: job.counters.kakaoCalls, retries: job.counters.retries,
    unique: memory.found.size, outside: memory.outside.size, failed: job.tasks.filter((t) => t.status === 'failed').length, concurrency: state.limit,
  })
  const report = () => opts.onProgress?.(snapshot())
  const checkpoint = () => { job.updatedAt = new Date().toISOString(); try { opts.onCheckpoint?.(job) } catch { /* saving is best effort */ } }

  const absorb = (docs: KakaoDoc[]) => {
    for (const d of docs) {
      if (!d || d.id == null || !isFoodPlace(d)) continue
      const id = String(d.id)
      if (memory.found.has(id) || memory.outside.has(id)) continue
      const dist = placeDistanceM(d, campus)
      if (dist == null) continue // no usable coordinates: cannot be placed, never guessed
      if (dist > campus.radiusM) { memory.outside.add(id); continue }
      memory.found.set(id, { ...d, id, distance: String(Math.round(dist)), distanceM: dist })
    }
  }

  const queryFor = (t: JobTask): CellQuery => {
    const { lat, lng } = cellCentre(cellOf(t), campus)
    return { campusId: campus.id, lat, lng, radiusM: cellRadiusM(cellOf(t)), group: t.group, page: t.page, ...(t.query ? { query: t.query } : {}) }
  }

  /** One attempt, bounded by a timeout and by cancellation even if the search function ignores its signal. */
  const attempt = async (q: CellQuery): Promise<CellOutcome> => {
    const c = new AbortController()
    const onAbort = () => c.abort()
    signal.addEventListener('abort', onAbort, { once: true })
    let timer: ReturnType<typeof setTimeout> | undefined
    const timedOut = new Promise<CellOutcome>((res) => { timer = setTimeout(() => { c.abort(); res({ ok: false, kind: 'timeout', message: `${Math.round(timeoutMs / 1000)}초 안에 응답이 없었어요` }) }, timeoutMs) })
    const cancelled = new Promise<CellOutcome>((res) => { if (signal.aborted) res({ ok: false, kind: 'aborted', message: 'cancelled' }); else signal.addEventListener('abort', () => res({ ok: false, kind: 'aborted', message: 'cancelled' }), { once: true }) })
    const call = search(q, c.signal).catch((e): CellOutcome => ({ ok: false, kind: signal.aborted ? 'aborted' : 'network', message: errText(e) }))
    try { return await Promise.race([call, timedOut, cancelled]) }
    finally { clearTimeout(timer); signal.removeEventListener('abort', onAbort) }
  }

  /** One page of one square, with retries and backoff. */
  const requestPage = async (t: JobTask): Promise<CellOutcome> => {
    let tries = 0
    for (;;) {
      if (signal.aborted) return { ok: false, kind: 'aborted', message: 'cancelled' }
      if (runInvocations >= maxInvocations || runKakaoCalls >= maxKakaoCalls) { stop('budget'); return { ok: false, kind: 'aborted', message: 'budget' } }
      runInvocations++
      job.counters.invocations++
      const out = await attempt(queryFor(t))
      if (out.ok) { runKakaoCalls += out.kakaoCalls; job.counters.kakaoCalls += out.kakaoCalls }
      else if (out.kind === 'rate_limited' && state.limit > 1) { state.limit--; state.degraded = true }
      report()
      if (out.ok || out.kind === 'aborted' || !RETRYABLE.has(out.kind) || tries >= retries) return out
      tries++
      job.counters.retries++
      await sleep(baseDelay * 2 ** (tries - 1) * (0.75 + random() * 0.5) * (out.kind === 'rate_limited' ? 2 : 1), signal)
    }
  }

  /** All pages of a square, starting at its cursor. */
  const runTask = async (t: JobTask): Promise<CellOutcome> => {
    for (;;) {
      const out = await requestPage(t)
      if (!out.ok) return out
      absorb(out.docs)
      t.pages++
      t.truncated = out.truncated
      if (out.nextPage != null && out.nextPage > t.page) { t.page = out.nextPage; continue } // advance the cursor
      return out
    }
  }

  const finish = (t: JobTask, out: CellOutcome) => {
    if (out.ok) {
      t.status = 'done'; t.error = undefined
      consecutiveRateLimited = 0; consecutiveRejected = 0
      cellsDone++
      if (t.truncated) {
        if (!t.query && t.depth < maxDepth) for (const c of childCells(cellOf(t))) { if (cellTouchesCampus(c, campus)) addTask(t.group, undefined, c) }
        else if (!t.query) t.saturated = true
      }
      return
    }
    if (out.kind === 'aborted') return // stopped: the square stays pending, cursor intact
    t.status = 'failed'
    t.error = { kind: out.kind, status: out.status, code: out.code ? safeCode(out.code) : undefined, message: redact(out.message) }
    cellsDone++
    if (out.kind === 'not_deployed' || out.kind === 'forbidden') stop(out.kind)
    consecutiveRejected = out.kind === 'rejected' ? consecutiveRejected + 1 : 0
    if (out.kind === 'rejected' && consecutiveRejected >= rejectedStop) stop('rejected')
    consecutiveRateLimited = out.kind === 'rate_limited' ? consecutiveRateLimited + 1 : 0
    if (out.kind === 'rate_limited' && consecutiveRateLimited >= rateLimitStop) stop('rate_limited')
  }

  const worker = async () => {
    for (;;) {
      if (signal.aborted) return
      if (inflight >= state.limit) { await park(); continue }
      const t = queue.shift()
      if (!t) { if (inflight === 0) return; await park(); continue }
      inflight++
      try {
        finish(t, await runTask(t))
        if (++sinceCheckpoint >= batchSize) { sinceCheckpoint = 0; checkpoint() }
      } finally {
        inflight--
        report()
        notify()
      }
    }
  }
  const drain = async () => { await Promise.all(Array.from({ length: startConcurrency }, worker)) }

  report()
  await drain()

  // ---- keywords inside the squares the grid could not resolve
  if (!state.stoppedBy && job.limits.keywords.length > 0 && job.tasks.some((t) => !t.query && t.saturated)) {
    job.phase = 'keywords'
    for (const s of job.tasks.filter((t) => !t.query && t.saturated)) for (const kw of job.limits.keywords) addTask(s.group, kw, cellOf(s))
    report()
    await drain()
  }

  const unsearched = job.tasks.filter((t) => t.status === 'pending').length
  queue.length = 0
  if (unsearched === 0) job.phase = 'done'
  if (state.stoppedBy === 'cancelled' || (outer?.aborted && !state.stoppedBy)) state.stoppedBy = 'cancelled'
  const stoppedBy = state.stoppedBy
  job.stoppedBy = stoppedBy

  const failed = job.tasks.filter((t) => t.status === 'failed')
  const kwStill = new Set(job.tasks.filter((t) => t.query && t.truncated).map((t) => `${t.group}|${Math.round(t.dx)}|${Math.round(t.dy)}|${t.depth}`))
  const saturated = job.tasks.filter((t) => !t.query && t.saturated)
  const satOut = saturated.map((t) => {
    const { lat, lng } = cellCentre(cellOf(t), campus)
    return { group: t.group, lat, lng, radiusM: cellRadiusM(cellOf(t)), stillTruncatedAfterKeywords: kwStill.has(`${t.group}|${Math.round(t.dx)}|${Math.round(t.dy)}|${t.depth}`) }
  })
  job.status = stoppedBy === 'cancelled' ? 'cancelled' : stoppedBy ? 'stopped' : failed.length > 0 || satOut.length > 0 || unsearched > 0 ? 'partial' : 'complete'
  const complete = job.status === 'complete'

  const errors: ErrorSummary[] = []
  for (const t of failed) {
    const e = t.error!
    const stage = t.query ? 'keyword_search' : 'grid_search'
    const hit = errors.find((x) => x.kind === e.kind && x.status === e.status && x.code === e.code && x.stage === stage)
    if (hit) hit.count++
    else errors.push({ kind: e.kind, status: e.status, code: e.code, message: e.message, count: 1, stage })
  }

  const warnings: string[] = []
  if (stoppedBy === 'budget') warnings.push(`이번 실행의 요청 한도(${maxInvocations}회 / 카카오 ${maxKakaoCalls}회)에 도달해 멈췄어요. "이어서 하기"로 남은 구역만 계속할 수 있어요.`)
  if (stoppedBy === 'rate_limited') warnings.push('카카오가 요청 제한(429)을 계속 돌려줘 멈췄어요. 잠시 뒤 "이어서 하기"로 남은 구역만 계속할 수 있어요.')
  if (stoppedBy === 'cancelled') warnings.push('중단했어요. 지금까지 찾은 결과만 보여요. "이어서 하기"로 남은 구역만 계속할 수 있어요.')
  if (stoppedBy === 'not_deployed') warnings.push('검색 함수(admin_kakao_search)가 이 프로젝트에 배포되어 있지 않아요.')
  if (stoppedBy === 'forbidden') warnings.push('관리자 권한이 확인되지 않아 카카오 검색을 멈췄어요. 다시 로그인한 뒤 시도해 주세요.')
  if (stoppedBy === 'rejected') warnings.push('서버가 검색 요청을 계속 거절해 멈췄어요(HTTP 4xx). 아래 오류 내용을 확인해 주세요.')
  if (state.degraded) warnings.push(`카카오 요청 제한(429)이 있어 동시 요청을 ${state.limit}개로 줄여서 진행했어요.`)
  if (failed.length > 0) warnings.push(`${failed.length}개 구역/키워드 검색이 실패했어요(재시도 후에도). 성공한 구역의 결과는 그대로 두었고, "실패한 구역 다시 시도"로 그 구역만 다시 찾을 수 있어요.`)
  if (satOut.length > 0) warnings.push(`${satOut.length}개 구역은 가장 잘게 나눠도 카카오 노출 한도(검색당 45곳)를 넘었어요. 그 구역의 식당 일부는 카카오가 알려주지 않아 빠졌을 수 있어요.`)

  checkpoint()
  const progress = snapshot()
  progress.cellsQueued = 0
  opts.onProgress?.(progress)

  const places = [...memory.found.values()].sort((a, b) => a.distanceM - b.distanceM)
  return {
    places, progress, job, errors, stoppedBy, complete, warnings, unsearchedCells: unsearched, saturatedCells: satOut,
    failedCells: failed.map((t) => {
      const { lat, lng } = cellCentre(cellOf(t), campus)
      return { group: t.group, query: t.query, depth: t.depth, lat, lng, radiusM: cellRadiusM(cellOf(t)), page: t.page, kind: t.error!.kind, status: t.error!.status, code: t.error!.code, message: t.error!.message }
    }),
  }
}

/** Wraps `supabase.functions.invoke('admin_kakao_search')` as a [SearchCell]. */
export type InvokeFn = (name: string, opts: { body: Record<string, unknown>; signal?: AbortSignal }) => PromiseLike<{ data: unknown; error: unknown }>
/** Answers "is the function there?" when a call fails without any HTTP status (see `probeFunction`). Called at most once per search function. */
export type ProbeFn = () => Promise<{ state: 'deployed' | 'not_deployed' | 'unreachable'; status?: number }>

export function makeSupabaseSearch(invoke: InvokeFn, probe?: ProbeFn): SearchCell {
  let probed: ReturnType<ProbeFn> | null = null
  const probeOnce = () => (probed ??= probe!())
  return async (q, signal) => {
    let res: { data: unknown; error: unknown }
    try {
      res = await invoke('admin_kakao_search', {
        body: { university_id: q.campusId, category_group_code: q.group, page: q.page, ...(q.query ? { query: q.query } : {}), cell: { lat: q.lat, lng: q.lng, radius_m: q.radiusM } },
        signal,
      })
    } catch (e) {
      return signal.aborted ? { ok: false, kind: 'aborted', message: 'cancelled' } : await classifyInvokeError(e, probe ? probeOnce : undefined)
    }
    if (res.error) return await classifyInvokeError(res.error, probe ? probeOnce : undefined)
    const b = res.data as { success?: boolean; documents?: unknown; meta?: { truncated?: boolean; kakao_calls?: number; total_count?: number; next_page?: number | null }; university?: { search_radius_m?: number } } | null
    // No answer at all: the function does not exist on this project.
    if (b == null) return { ok: false, kind: 'not_deployed', message: 'no response from admin_kakao_search' }
    if (b.success !== true || !Array.isArray(b.documents) || !b.meta) return { ok: false, kind: 'unavailable', message: 'unexpected response' }
    return {
      ok: true, docs: b.documents as KakaoDoc[], truncated: b.meta.truncated === true, nextPage: b.meta.next_page ?? null,
      kakaoCalls: Number(b.meta.kakao_calls ?? 1), total: Number(b.meta.total_count ?? 0), universityRadiusM: b.university?.search_radius_m,
    }
  }
}

async function classifyInvokeError(error: unknown, probe?: () => ReturnType<ProbeFn>): Promise<CellOutcome> {
  const e = error as { name?: string; message?: string; context?: { status?: number; json?: () => Promise<unknown> } }
  const status = e?.context?.status
  const message = redact(e?.message ?? 'error')
  if (e?.name === 'FunctionsFetchError' || status === undefined) {
    // No HTTP status. For a function that does not exist the browser sees a failed CORS preflight (404) and reports
    // exactly this, so ask the platform directly before calling it a network problem.
    const p = probe ? await probe() : null
    if (p?.state === 'not_deployed') return { ok: false, kind: 'not_deployed', status: p.status ?? 404, code: 'NOT_FOUND', message: 'admin_kakao_search 함수가 이 프로젝트에 배포되어 있지 않아요' }
    return { ok: false, kind: 'network', message: p?.state === 'unreachable' ? `네트워크 또는 CORS 오류 (HTTP 상태 없음): ${message}` : message }
  }
  let body = null as { error?: string; code?: string } | null
  try { body = (await e.context!.json!()) as { error?: string; code?: string } } catch { /* not json */ }
  const code = typeof body?.error === 'string' ? safeCode(body.error) : typeof body?.code === 'string' ? safeCode(body.code) : undefined
  // The platform's own 404 (no such function) is not ours: our 404 carries { success:false, error }.
  if (status === 404 && (e.name === 'FunctionsRelayError' || !body?.error)) return { ok: false, kind: 'not_deployed', status, code: code ?? 'NOT_FOUND', message: 'admin_kakao_search 함수가 이 프로젝트에 배포되어 있지 않아요' }
  if (status === 401 || status === 403) return { ok: false, kind: 'forbidden', status, code, message: code ?? 'forbidden' }
  if (status === 429) return { ok: false, kind: 'rate_limited', status, code, message: code ?? 'rate limited' }
  if (status === 408 || status === 504) return { ok: false, kind: 'timeout', status, code, message: code ?? message }
  if (status >= 500) return { ok: false, kind: 'unavailable', status, code, message: code ?? message }
  return { ok: false, kind: 'rejected', status, code, message: code ?? message }
}
