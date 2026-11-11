import { isFoodPlace, KAKAO_QUERIES, type KakaoDoc } from './kakao'
import { cellCentre, cellRadiusM, cellTouchesCampus, childCells, type Campus, type Cell, placeDistanceM, rootCell } from './kakaoGeo'

/** What one cell search asks of the server: one circle, one food group, optionally one keyword. */
export type CellQuery = { campusId: string; lat: number; lng: number; radiusM: number; group: Group; query?: string }
export type Group = 'FD6' | 'CE7'
export type FailKind = 'rate_limited' | 'unavailable' | 'rejected' | 'network' | 'not_deployed' | 'forbidden' | 'aborted'
export type CellOutcome =
  | { ok: true; docs: KakaoDoc[]; truncated: boolean; kakaoCalls: number; total: number; universityRadiusM?: number }
  | { ok: false; kind: FailKind; status?: number; message: string }
export type SearchCell = (q: CellQuery, signal: AbortSignal) => Promise<CellOutcome>

export type ScanOptions = {
  /** How many times a square may be split into quarters (3000 m radius: 6 levels = squares of ~94 m). */
  maxDepth?: number
  /** Hard ceilings so a scan can never run away (every attempt, including retries, counts). */
  maxInvocations?: number
  maxKakaoCalls?: number
  concurrency?: number
  /** Retries per cell for rate limits / outages / network (not for refusals). */
  retries?: number
  baseDelayMs?: number
  /** Stop after this many cells in a row ran out of retries on a rate limit. */
  rateLimitStop?: number
  keywords?: readonly string[]
  groups?: readonly Group[]
  sleep?: (ms: number, signal: AbortSignal) => Promise<void>
  random?: () => number
  onProgress?: (p: Progress) => void
  signal?: AbortSignal
}

export type Progress = {
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
}

export type FailedCell = { group: Group; query?: string; depth: number; lat: number; lng: number; radiusM: number; kind: FailKind; message: string }
export type Place = KakaoDoc & { distanceM: number }
export type StopReason = 'cancelled' | 'budget' | 'rate_limited' | 'not_deployed' | 'forbidden' | 'rejected'

export type ScanResult = {
  places: Place[]
  progress: Progress
  failedCells: FailedCell[]
  /** Squares that were still over Kakao's cap at the finest level: places there may be missing. */
  saturatedCells: { group: Group; lat: number; lng: number; radiusM: number; stillTruncatedAfterKeywords: boolean }[]
  /** Cells that were never searched because the scan stopped first. */
  unsearchedCells: number
  stoppedBy: StopReason | null
  /** True only if every needed cell was searched without failure or cap. Even then it is "what Kakao exposes", not a census. */
  complete: boolean
  warnings: string[]
}

type Task = { cell: Cell; group: Group; query?: string }

const defaultSleep = (ms: number, signal: AbortSignal) =>
  new Promise<void>((resolve) => {
    if (signal.aborted) return resolve()
    const t = setTimeout(done, ms)
    function done() { signal.removeEventListener('abort', done); clearTimeout(t); resolve() }
    signal.addEventListener('abort', done, { once: true })
  })

const RETRYABLE: ReadonlySet<FailKind> = new Set(['rate_limited', 'unavailable', 'network'])

/**
 * Covers the university's whole configured circle (centre and radius come from the `universities` row, passed in by
 * the caller) with an adaptive grid:
 *  1. The bounding square of the circle is searched for each food group (FD6 restaurants, CE7 cafes) as one circle.
 *     Kakao hands out at most 45 places per search; when a search reports it was TRUNCATED the square is split into
 *     quarters and each quarter is searched, down to `maxDepth`. Squares that cannot touch the circle are skipped.
 *  2. Squares still truncated at the finest level are searched again once per existing keyword (the app's category
 *     keywords), because different keywords surface different places of a crowded block.
 * Every place gets its true distance from the campus centre; those beyond the radius are dropped. Places are
 * deduplicated by Kakao place id. Failures are retried with exponential backoff; what still fails is reported.
 * Nothing is cached or stored: the result lives in memory for the preview.
 */
export async function scanCampus(campus: Campus, search: SearchCell, opts: ScanOptions = {}): Promise<ScanResult> {
  const maxDepth = opts.maxDepth ?? 6
  const maxInvocations = opts.maxInvocations ?? 1500
  const maxKakaoCalls = opts.maxKakaoCalls ?? 3000
  const concurrency = Math.max(1, opts.concurrency ?? 4)
  const retries = opts.retries ?? 3
  const baseDelay = opts.baseDelayMs ?? 500
  const rateLimitStop = opts.rateLimitStop ?? 5
  const groups = opts.groups ?? (['FD6', 'CE7'] as const)
  const keywords = opts.keywords ?? KAKAO_QUERIES
  const sleep = opts.sleep ?? defaultSleep
  const random = opts.random ?? Math.random

  const ctl = new AbortController()
  const outer = opts.signal
  if (outer) { if (outer.aborted) ctl.abort(); else outer.addEventListener('abort', () => ctl.abort(), { once: true }) }
  const signal = ctl.signal

  const found = new Map<string, Place>()
  const outsideIds = new Set<string>()
  const failedCells: FailedCell[] = []
  const saturated: { group: Group; cell: Cell }[] = []
  const stillTruncated = new Set<string>()
  const warnings: string[] = []
  const state: { stoppedBy: StopReason | null } = { stoppedBy: null }
  let consecutiveRateLimited = 0
  let invocations = 0
  let kakaoCalls = 0
  let retried = 0
  let cellsDone = 0
  let phase: Progress['phase'] = 'grid'

  const queue: Task[] = []
  let inflight = 0
  let wake: (() => void) | null = null
  const notify = () => { const w = wake; wake = null; w?.() }
  const stop = (why: StopReason) => { if (!state.stoppedBy) state.stoppedBy = why; ctl.abort() }

  const snapshot = (): Progress => ({
    phase, radiusM: campus.radiusM, cellsDone, cellsQueued: queue.length + inflight, cellsSaturated: saturated.length,
    invocations, kakaoCalls, retries: retried, unique: found.size, outside: outsideIds.size, failed: failedCells.length,
  })
  const report = () => opts.onProgress?.(snapshot())

  const absorb = (docs: KakaoDoc[]) => {
    for (const d of docs) {
      if (!d || d.id == null || !isFoodPlace(d)) continue
      const id = String(d.id)
      if (found.has(id) || outsideIds.has(id)) continue
      const dist = placeDistanceM(d, campus)
      if (dist == null) continue // no usable coordinates: cannot be placed, never guessed
      if (dist > campus.radiusM) { outsideIds.add(id); continue }
      found.set(id, { ...d, id, distance: String(Math.round(dist)), distanceM: dist })
    }
  }

  const queryFor = (t: Task): CellQuery => {
    const { lat, lng } = cellCentre(t.cell, campus)
    return { campusId: campus.id, lat, lng, radiusM: cellRadiusM(t.cell), group: t.group, ...(t.query ? { query: t.query } : {}) }
  }

  /** One cell, with backoff. Returns the outcome of the last attempt. */
  const run = async (t: Task): Promise<CellOutcome> => {
    const q = queryFor(t)
    let attempt = 0
    for (;;) {
      if (signal.aborted) return { ok: false, kind: 'aborted', message: 'cancelled' }
      if (invocations >= maxInvocations || kakaoCalls >= maxKakaoCalls) { stop('budget'); return { ok: false, kind: 'aborted', message: 'budget' } }
      invocations++
      let out: CellOutcome
      try { out = await search(q, signal) } catch (e) { out = { ok: false, kind: 'network', message: e instanceof Error ? e.message : String(e) } }
      if (out.ok) kakaoCalls += out.kakaoCalls
      else if (signal.aborted) return { ok: false, kind: 'aborted', message: 'cancelled' }
      report()
      if (out.ok || !RETRYABLE.has(out.kind) || attempt >= retries) return out
      attempt++
      retried++
      const delay = baseDelay * 2 ** (attempt - 1) * (0.75 + random() * 0.5)
      await sleep(delay, signal)
    }
  }

  const worker = async () => {
    for (;;) {
      if (signal.aborted) return
      const t = queue.shift()
      if (!t) {
        if (inflight === 0) return
        await new Promise<void>((r) => { const prev = wake; wake = () => { prev?.(); r() } })
        continue
      }
      inflight++
      try {
        const out = await run(t)
        if (out.ok) {
          consecutiveRateLimited = 0
          cellsDone++
          absorb(out.docs)
          if (out.truncated) {
            if (!t.query && t.cell.depth < maxDepth) {
              for (const c of childCells(t.cell)) if (cellTouchesCampus(c, campus)) queue.push({ cell: c, group: t.group })
            } else if (!t.query) saturated.push({ group: t.group, cell: t.cell })
            else stillTruncated.add(`${t.group}|${t.cell.dx}|${t.cell.dy}|${t.cell.half}`)
          }
        } else if (out.kind === 'aborted') {
          // not a failure of the cell: the scan was stopped
        } else {
          cellsDone++
          const { lat, lng, radiusM } = queryFor(t)
          failedCells.push({ group: t.group, query: t.query, depth: t.cell.depth, lat, lng, radiusM, kind: out.kind, message: out.message })
          if (out.kind === 'not_deployed' || out.kind === 'forbidden' || out.kind === 'rejected') stop(out.kind)
          if (out.kind === 'rate_limited' && ++consecutiveRateLimited >= rateLimitStop) stop('rate_limited')
          if (out.kind !== 'rate_limited') consecutiveRateLimited = 0
        }
      } finally {
        inflight--
        report()
        notify()
      }
    }
  }

  const drain = async () => {
    await Promise.all(Array.from({ length: concurrency }, worker))
  }

  // ---- phase 1: the grid, per food group
  const root = rootCell(campus)
  for (const g of groups) if (cellTouchesCampus(root, campus)) queue.push({ cell: root, group: g })
  report()
  await drain()

  // ---- phase 2: keywords inside the squares the grid could not resolve
  if (!state.stoppedBy && saturated.length > 0 && keywords.length > 0) {
    phase = 'keywords'
    for (const s of saturated) for (const kw of keywords) queue.push({ cell: s.cell, group: s.group, query: kw })
    report()
    await drain()
  }

  const unsearched = queue.length
  queue.length = 0
  phase = 'done'
  const progress = snapshot()
  progress.cellsQueued = 0
  opts.onProgress?.(progress)

  const satOut = saturated.map((s) => {
    const { lat, lng } = cellCentre(s.cell, campus)
    return { group: s.group, lat, lng, radiusM: cellRadiusM(s.cell), stillTruncatedAfterKeywords: stillTruncated.has(`${s.group}|${s.cell.dx}|${s.cell.dy}|${s.cell.half}`) }
  })

  if (state.stoppedBy === 'cancelled' || (outer?.aborted && !state.stoppedBy)) state.stoppedBy = 'cancelled'
  const stoppedBy = state.stoppedBy
  if (stoppedBy === 'budget') warnings.push(`요청 한도(${maxInvocations}회 / 카카오 ${maxKakaoCalls}회)에 도달해 중단했어요. 반경을 줄이거나 다시 실행해 주세요.`)
  if (stoppedBy === 'rate_limited') warnings.push('카카오가 요청 제한(429)을 계속 돌려줘 중단했어요. 잠시 뒤 다시 시도해 주세요.')
  if (stoppedBy === 'cancelled') warnings.push('중단했어요. 지금까지 찾은 결과만 보여요.')
  if (failedCells.length > 0) warnings.push(`${failedCells.length}개 구역/키워드 검색이 실패했어요(재시도 후에도). 그 주변 식당이 빠졌을 수 있어요.`)
  if (satOut.length > 0) warnings.push(`${satOut.length}개 구역은 가장 잘게 나눠도 카카오 노출 한도(검색당 45곳)를 넘었어요. 그 구역의 식당 일부는 카카오가 알려주지 않아 빠졌을 수 있어요.`)

  const places = [...found.values()].sort((a, b) => a.distanceM - b.distanceM)
  const complete = stoppedBy === null && failedCells.length === 0 && satOut.length === 0 && unsearched === 0
  return { places, progress, failedCells, saturatedCells: satOut, unsearchedCells: unsearched, stoppedBy, complete, warnings }
}

/** Wraps `supabase.functions.invoke('admin_kakao_search')` as a [SearchCell]. */
export type InvokeFn = (name: string, opts: { body: Record<string, unknown>; signal?: AbortSignal }) => PromiseLike<{ data: unknown; error: unknown }>

export function makeSupabaseSearch(invoke: InvokeFn): SearchCell {
  return async (q, signal) => {
    let res: { data: unknown; error: unknown }
    try {
      res = await invoke('admin_kakao_search', {
        body: { university_id: q.campusId, category_group_code: q.group, ...(q.query ? { query: q.query } : {}), cell: { lat: q.lat, lng: q.lng, radius_m: q.radiusM } },
        signal,
      })
    } catch (e) {
      return { ok: false, kind: signal.aborted ? 'aborted' : 'network', message: e instanceof Error ? e.message : String(e) }
    }
    if (res.error) return await classifyInvokeError(res.error)
    const b = res.data as { success?: boolean; documents?: unknown; meta?: { truncated?: boolean; kakao_calls?: number; total_count?: number }; university?: { search_radius_m?: number } } | null
    // No answer at all: the function does not exist on this project.
    if (b == null) return { ok: false, kind: 'not_deployed', message: 'no response from admin_kakao_search' }
    if (b.success !== true || !Array.isArray(b.documents) || !b.meta) return { ok: false, kind: 'unavailable', message: 'unexpected response' }
    return {
      ok: true, docs: b.documents as KakaoDoc[], truncated: b.meta.truncated === true,
      kakaoCalls: Number(b.meta.kakao_calls ?? 1), total: Number(b.meta.total_count ?? 0), universityRadiusM: b.university?.search_radius_m,
    }
  }
}

async function classifyInvokeError(error: unknown): Promise<CellOutcome> {
  const e = error as { name?: string; message?: string; context?: { status?: number; json?: () => Promise<unknown> } }
  const status = e.context?.status
  const message = e.message ?? 'error'
  if (e.name === 'FunctionsFetchError' || status === undefined) return { ok: false, kind: 'network', message }
  let body = null as { error?: string; code?: string } | null
  try { body = (await e.context!.json!()) as { error?: string; code?: string } } catch { /* not json */ }
  // The platform's own 404 (no such function) is not ours: our 404 carries { success:false, error }.
  if (status === 404 && (e.name === 'FunctionsRelayError' || !body?.error)) return { ok: false, kind: 'not_deployed', status, message: 'admin_kakao_search is not deployed' }
  if (status === 401 || status === 403) return { ok: false, kind: 'forbidden', status, message: body?.error ?? 'forbidden' }
  if (status === 429) return { ok: false, kind: 'rate_limited', status, message: body?.error ?? 'rate limited' }
  if (status >= 500 || status === 408) return { ok: false, kind: 'unavailable', status, message: body?.error ?? message }
  return { ok: false, kind: 'rejected', status, message: body?.error ?? message }
}
