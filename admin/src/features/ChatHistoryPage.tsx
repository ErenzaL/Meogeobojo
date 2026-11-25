import { useState, type FormEvent } from 'react'
import { useInfiniteQuery, useQuery } from '@tanstack/react-query'
import { Badge, Button, Card, EmptyState, ErrorState, Input, PageHeader, Select, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { formatDateTime } from '@/lib/utils'

type Shown = { id: string; name?: string; reason?: string }
type Prefs = {
  hard?: { max_price_krw?: number | null; min_price_krw?: number | null; max_walk_minutes?: number | null; cuisines?: string[]; dish_keywords?: string[]; avoid_spicy?: boolean; open_now?: boolean }
  soft?: { dish_keywords?: string[]; cheap?: boolean; filling?: boolean; closer?: boolean; group_size?: number | null }
}
export type ChatTurn = {
  id: number; created_at: string; user_id: string | null; nickname: string | null; client_id: string; language: string
  question: string; intent: string | null; prefs: Prefs | null; outcome: string; ai_status: string; reply: string | null
  restaurants: Shown[] | null; failure: string | null; notes: string[] | null
}
type Stats = { turns: number; askers: number; signed_in_turns: number; answered: number; no_result: number; chitchat: number; errors: number; ai_issues: number }

const PAGE = 50
const n = (v: number | null | undefined) => Number(v ?? 0).toLocaleString('ko-KR')
const won = (v: number) => `${Number(v).toLocaleString('ko-KR')}원`

const OUTCOME: Record<string, { label: string; tone: 'green' | 'amber' | 'red' | 'neutral' }> = {
  answered: { label: '추천함', tone: 'green' },
  no_result: { label: '맞는 곳 없음', tone: 'amber' },
  chitchat: { label: '일상 대화', tone: 'neutral' },
  clarify: { label: '되물음', tone: 'neutral' },
  error: { label: '오류', tone: 'red' },
}
const AI: Record<string, { label: string; tone: 'green' | 'amber' | 'red' }> = {
  ok: { label: 'AI 정상', tone: 'green' },
  busy: { label: 'AI 문장 실패 · 앱이 답함', tone: 'amber' },
  down: { label: 'AI 응답 없음 · 앱이 답함', tone: 'red' },
}
const LANGUAGE: Record<string, string> = { ko: '한국어', en: 'English', 'zh-Hans': '中文' }
const INTENT: Record<string, string> = { search: '새 추천 요청', more: '더 보여 달라', different: '다른 곳을 원함', menu: '메뉴 보기', compare: '비교', chitchat: '일상 대화', clarify: '되물음' }
const CUISINE: Record<string, string> = { korean: '한식', japanese: '일식', chinese: '중식', snack: '분식', western: '양식', salad: '샐러드', cafe: '카페' }
/** The lines the app wrote itself (the chat stores their kind, the words live in the app's translations). */
const NOTE: Record<string, string> = {
  foundCount: '조건에 맞는 곳을 찾았다고 안내', aiBusy: 'AI가 바빠 앱이 직접 답함', networkError: '네트워크 오류 안내', rateLimited: '요청이 너무 많다고 안내',
  genericError: '오류 안내', noMore: '더 보여 줄 곳이 없다고 안내', hoursUnknown: '영업시간 정보가 없다고 안내', menuOpened: '메뉴를 펼쳐 보여 줌', menuNone: '등록된 메뉴가 없다고 안내',
  cheapest: '가장 저렴한 곳을 안내', closest: '가장 가까운 곳을 안내', noPriceData: '가격 정보가 없다고 안내', noneGeneric: '맞는 곳이 없다고 안내',
  noneRaiseBudget: '맞는 곳 없음 · 예산을 올려 보자고 제안', noneWiderDistance: '맞는 곳 없음 · 거리를 넓혀 보자고 제안', noneAnyCuisine: '맞는 곳 없음 · 다른 음식 종류를 제안', noneDropDish: '맞는 곳 없음 · 다른 메뉴를 제안',
}

/** What the assistant understood, as short Korean chips. Empty when nothing specific was asked. */
export function conditionChips(p: Prefs | null): string[] {
  if (!p) return []
  const h = p.hard ?? {}; const s = p.soft ?? {}
  const out: string[] = []
  for (const d of h.dish_keywords ?? []) out.push(`메뉴: ${d}`)
  for (const c of h.cuisines ?? []) out.push(CUISINE[c] ?? c)
  if (h.max_price_krw != null) out.push(`${won(h.max_price_krw)} 이하`)
  if (h.min_price_krw != null) out.push(`${won(h.min_price_krw)} 이상`)
  if (h.max_walk_minutes != null) out.push(`도보 ${h.max_walk_minutes}분 이내`)
  if (h.open_now) out.push('지금 영업 중')
  if (h.avoid_spicy) out.push('맵지 않게')
  for (const d of s.dish_keywords ?? []) out.push(`어울리는 메뉴: ${d}`)
  if (s.cheap) out.push('저렴하게')
  if (s.closer) out.push('가깝게')
  if (s.filling) out.push('든든하게')
  if (s.group_size != null) out.push(`${s.group_size}명`)
  return out
}

async function rpc<T>(name: string, args: Record<string, unknown>): Promise<T[]> {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw error
  return (Array.isArray(data) ? data : data ? [data] : []) as T[]
}

function Stat({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <Card className="space-y-1">
      <p className="text-xs text-muted">{label}</p>
      <p className="text-2xl font-semibold tabular-nums">{value}</p>
      {hint && <p className="text-xs text-muted">{hint}</p>}
    </Card>
  )
}

function Turn({ t }: { t: ChatTurn }) {
  const outcome = OUTCOME[t.outcome] ?? { label: t.outcome, tone: 'neutral' as const }
  const ai = AI[t.ai_status] ?? { label: t.ai_status, tone: 'amber' as const }
  const chips = conditionChips(t.prefs)
  const shown = t.restaurants ?? []
  const notes = (t.notes ?? []).map((k) => NOTE[k] ?? k)
  return (
    <Card className="space-y-3" data-testid="chat-turn">
      <div className="flex flex-wrap items-center gap-2 text-xs text-muted">
        <span>{formatDateTime(t.created_at)}</span>
        <span aria-hidden>·</span>
        <span className="font-medium text-ink">{t.user_id ? (t.nickname ?? '닉네임 없음') : '게스트'}</span>
        <span title="기기마다 무작위로 만든 번호예요. 같은 번호면 같은 기기예요.">#{t.client_id.slice(0, 8)}</span>
        <Badge>{LANGUAGE[t.language] ?? t.language}</Badge>
        <Badge tone={outcome.tone}>{outcome.label}</Badge>
        <Badge tone={ai.tone}>{ai.label}</Badge>
      </div>

      <div>
        <p className="text-xs font-medium text-muted">질문</p>
        <p className="whitespace-pre-wrap break-words text-base font-semibold">{t.question}</p>
      </div>

      {(t.intent || chips.length > 0) && (
        <div className="space-y-1">
          <p className="text-xs font-medium text-muted">이렇게 이해했어요{t.intent ? ` · ${INTENT[t.intent] ?? t.intent}` : ''}</p>
          {chips.length > 0
            ? <div className="flex flex-wrap gap-1.5">{chips.map((c) => <Badge key={c} tone="brand">{c}</Badge>)}</div>
            : <p className="text-sm text-muted">특별한 조건 없이 물어봤어요.</p>}
        </div>
      )}

      <div className="space-y-1">
        <p className="text-xs font-medium text-muted">챗봇의 답</p>
        {t.reply && <p className="whitespace-pre-wrap break-words text-sm">{t.reply}</p>}
        {notes.length > 0 && <p className="text-sm text-muted">앱이 직접 쓴 안내: {notes.join(' / ')}</p>}
        {!t.reply && notes.length === 0 && shown.length === 0 && <p className="text-sm text-muted">기록된 답이 없어요.</p>}
        {t.failure && <p className="text-sm text-red-700">오류 종류: {NOTE[t.failure] ?? t.failure}</p>}
      </div>

      {shown.length > 0 && (
        <div className="space-y-1">
          <p className="text-xs font-medium text-muted">추천한 식당 {shown.length}곳</p>
          <ol className="space-y-1 text-sm">
            {shown.map((r, i) => (
              <li key={`${r.id}-${i}`} className="flex gap-2">
                <span className="w-5 shrink-0 tabular-nums text-muted">{i + 1}.</span>
                <span><span className="font-medium">{r.name ?? r.id}</span>{r.reason ? <span className="text-muted"> — {r.reason}</span> : null}</span>
              </li>
            ))}
          </ol>
        </div>
      )}
    </Card>
  )
}

/**
 * 챗봇 기록: what people asked the AI chat and what it answered (public.chat_turns, migration 20261129000100).
 * Admins only; the database keeps 90 days and writes every opening of this page to the activity log.
 */
export default function ChatHistoryPage() {
  const [days, setDays] = useState(7)
  const [draft, setDraft] = useState('')
  const [search, setSearch] = useState('')
  const [outcome, setOutcome] = useState('')
  const [language, setLanguage] = useState('')
  const [onlyUsers, setOnlyUsers] = useState(false)

  const stats = useQuery({
    queryKey: ['chat-history-stats', days],
    queryFn: async () => (await rpc<Stats>('admin_chat_stats', { p_days: days }))[0] ?? null,
  })
  const list = useInfiniteQuery({
    queryKey: ['chat-history', days, search, outcome, language, onlyUsers],
    initialPageParam: null as number | null,
    queryFn: ({ pageParam }) => rpc<ChatTurn>('admin_chat_turns', {
      p_limit: PAGE, p_before: pageParam, p_days: days, p_search: search || null, p_outcome: outcome || null, p_language: language || null, p_only_users: onlyUsers,
    }),
    getNextPageParam: (last) => (last.length === PAGE ? Number(last[last.length - 1].id) : undefined),
  })
  const rows = list.data?.pages.flat() ?? []
  const s = stats.data
  const submit = (e: FormEvent) => { e.preventDefault(); setSearch(draft.trim()) }
  const filtered = Boolean(search || outcome || language || onlyUsers)

  return (
    <>
      <PageHeader
        title="챗봇 기록"
        description="사용자가 AI 챗봇에 물어본 질문과 챗봇의 답이에요. 최근 90일까지만 보관하고, 이 화면을 연 사실은 활동 기록에 남아요."
        actions={
          <Select aria-label="기간" value={days} onChange={(e) => setDays(Number(e.target.value))}>
            <option value={1}>오늘 하루</option>
            <option value={7}>최근 7일</option>
            <option value={30}>최근 30일</option>
            <option value={90}>최근 90일</option>
          </Select>
        }
      />

      <Card className="mb-4 max-w-3xl space-y-1 text-sm">
        <p className="font-semibold">사용자가 직접 입력한 글이에요. 조심해서 다뤄 주세요.</p>
        <p className="text-muted">이메일과 IP 주소는 저장하지 않아요. 로그인한 사용자는 닉네임이, 게스트는 기기마다 무작위로 만든 번호만 보여요. 질문 내용을 서비스 개선 외의 목적으로 쓰거나 밖으로 옮기지 말아 주세요.</p>
      </Card>

      {stats.error ? <ErrorState error={stats.error} onRetry={() => void stats.refetch()} /> : (
        <div className="mb-5 grid grid-cols-2 gap-3 md:grid-cols-4">
          {stats.isLoading || !s
            ? Array.from({ length: 4 }, (_, i) => <Skeleton key={i} className="h-24 w-full" />)
            : <>
                <Stat label="질문 수" value={n(s.turns)} hint={`로그인 사용자 ${n(s.signed_in_turns)}건`} />
                <Stat label="질문한 사람" value={n(s.askers)} hint="계정 또는 기기 기준" />
                <Stat label="맞는 곳을 못 찾음" value={n(s.no_result)} hint={`추천함 ${n(s.answered)}건`} />
                <Stat label="AI가 답하지 못함" value={n(s.ai_issues)} hint={`오류 ${n(s.errors)}건`} />
              </>}
        </div>
      )}

      <form onSubmit={submit} className="mb-4 flex flex-wrap items-end gap-2">
        <Input aria-label="질문 검색" placeholder="질문에서 찾기 (예: 국밥)" value={draft} onChange={(e) => setDraft(e.target.value)} className="w-64" maxLength={100} />
        <Button type="submit">검색</Button>
        <Select aria-label="결과" value={outcome} onChange={(e) => setOutcome(e.target.value)}>
          <option value="">모든 결과</option>
          {Object.entries(OUTCOME).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
        </Select>
        <Select aria-label="언어" value={language} onChange={(e) => setLanguage(e.target.value)}>
          <option value="">모든 언어</option>
          {Object.entries(LANGUAGE).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </Select>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={onlyUsers} onChange={(e) => setOnlyUsers(e.target.checked)} />
          로그인 사용자만
        </label>
        {filtered && <Button variant="ghost" onClick={() => { setDraft(''); setSearch(''); setOutcome(''); setLanguage(''); setOnlyUsers(false) }}>조건 지우기</Button>}
      </form>

      {list.error ? <ErrorState error={list.error} onRetry={() => void list.refetch()} /> : list.isLoading ? (
        <div className="space-y-3">{Array.from({ length: 3 }, (_, i) => <Skeleton key={i} className="h-40 w-full" />)}</div>
      ) : rows.length === 0 ? (
        <EmptyState>{filtered ? '조건에 맞는 질문이 없어요.' : '이 기간에 기록된 질문이 없어요. 사용자가 챗봇에 질문하면 여기에 쌓여요.'}</EmptyState>
      ) : (
        <div className="space-y-3">
          {rows.map((t) => <Turn key={t.id} t={t} />)}
          {list.hasNextPage
            ? <Button variant="outline" disabled={list.isFetchingNextPage} onClick={() => void list.fetchNextPage()}>{list.isFetchingNextPage ? '불러오는 중…' : '더 보기'}</Button>
            : <p className="text-center text-xs text-muted">여기까지예요 · {n(rows.length)}건</p>}
        </div>
      )}
    </>
  )
}
