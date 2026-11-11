/**
 * Diagnosis helpers for the Kakao import: which stage failed, with what HTTP status, and a probe that tells
 * "the function is not deployed" apart from "the network is down". Nothing here ever returns a secret: every text
 * that reaches the screen goes through [redact].
 */

export type ImportStage = 'university' | 'function_check' | 'grid_search' | 'keyword_search' | 'legacy_search' | 'managed_lookup' | 'register'

export const STAGE_LABEL: Record<ImportStage, string> = {
  university: '대학교 설정 읽기',
  function_check: '검색 함수 확인',
  grid_search: '구역 검색',
  keyword_search: '키워드 검색',
  legacy_search: '기존 방식 검색',
  managed_lookup: '관리 중인 식당 확인',
  register: '등록',
}

export type DiagError = { stage: ImportStage; status?: number; code?: string; message: string; jobId?: string }

/** Strips anything that looks like a credential from [text]: Kakao keys, bearer tokens, JWTs, apikey params, long opaque tokens. */
export function redact(text: string): string {
  return String(text)
    .replace(/KakaoAK\s+\S+/gi, 'KakaoAK ***')
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]+/gi, 'Bearer ***')
    .replace(/([?&](?:apikey|api_key|key|token|access_token)=)[^&\s"']+/gi, '$1***')
    .replace(/\b(sb_(?:publishable|secret)_[A-Za-z0-9_-]+)/g, '***')
    .replace(/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}/g, '***')
    .replace(/\b[A-Fa-f0-9]{32,}\b/g, '***')
    .replace(/\b[A-Za-z0-9_-]{40,}\b/g, '***')
}

/** A server-supplied error code is shown and stored too, so it is cleaned and bounded like any other text. */
export const safeCode = (code: string): string => redact(code).slice(0, 80)

/** One line for the Admin: stage, HTTP status, code and the job id (so a report can be matched to a job). */
export function describeError(e: DiagError): string {
  const parts = [`단계: ${STAGE_LABEL[e.stage]}`, e.status ? `HTTP ${e.status}` : 'HTTP 상태 없음', e.code ? safeCode(e.code) : undefined].filter(Boolean)
  return `${parts.join(' · ')} — ${redact(e.message)}${e.jobId ? ` (작업 ID ${e.jobId.slice(0, 8)})` : ''}`
}

/** The HTTP status carried by a supabase-js function error (`context` is the Response), if any. */
export function statusOf(error: unknown): number | undefined {
  const s = (error as { context?: { status?: unknown } } | null)?.context?.status
  return typeof s === 'number' ? s : undefined
}

export type FnProbe = { state: 'deployed' | 'not_deployed' | 'unreachable'; status?: number }

/**
 * Is `functions/v1/<name>` there? A plain GET with the key in the query string is a "simple" cross-origin request: no
 * custom headers, so no CORS preflight. That matters: for a function that does not exist the platform answers the
 * preflight with 404, a browser then refuses the real call and supabase-js reports a bare "network error" with no
 * status at all. A simple GET lets the browser hand us the actual status.
 *   404 -> not deployed. Any other status (405 from the function itself, 401 from the gateway ...) -> it exists.
 *   No answer at all -> unreachable (offline, blocked, or a CORS-less error).
 */
export async function probeFunction(baseUrl: string, name: string, key: string, doFetch: typeof fetch = fetch, timeoutMs = 8000): Promise<FnProbe> {
  const ctl = new AbortController()
  const timer = setTimeout(() => ctl.abort(), timeoutMs)
  try {
    const res = await doFetch(`${baseUrl.replace(/\/+$/, '')}/functions/v1/${name}?apikey=${encodeURIComponent(key)}`, { method: 'GET', signal: ctl.signal })
    return res.status === 404 ? { state: 'not_deployed', status: 404 } : { state: 'deployed', status: res.status }
  } catch {
    return { state: 'unreachable' }
  } finally {
    clearTimeout(timer)
  }
}
