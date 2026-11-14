import { useQuery } from '@tanstack/react-query'
import { AlertTriangle, CheckCircle2, HelpCircle, RefreshCw } from 'lucide-react'
import type { ReactNode } from 'react'
import { Badge, Button, Card, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import type { KakaoLive } from './kakaoLookup'
import { campusesOf, useKakaoRestaurantDetails, type KakaoLocation, type KakaoRestaurantDetails, type KakaoSubject, type UniRow } from './useKakaoRestaurantDetails'

/**
 * Everything here is DISPLAY ONLY. Live Kakao values are shown next to the managed fields and are never written
 * into the form, a draft, a publish payload, a CSV or Supabase (Kakao allows results in real time, not as a permanent
 * copy). The managed value, when there is one, always wins.
 */

const time = (ms: number) => new Date(ms).toLocaleTimeString('ko-KR', { timeZone: 'Asia/Seoul', hour: '2-digit', minute: '2-digit', second: '2-digit' })
const same = (managed: string, live: string) => {
  const a = managed.trim(); const b = live.trim()
  if (a === b) return true
  const na = Number(a); const nb = Number(b)
  return a !== '' && Number.isFinite(na) && Number.isFinite(nb) && Math.abs(na - nb) < 1e-6
}

/** The line under a managed field: whose value this is. [managed] is what is in the form right now. */
export function sourceNote(managed: string, live: string | null | undefined, opts: { identifier?: boolean } = {}): ReactNode {
  const hasManaged = managed.trim() !== ''
  if (hasManaged) {
    return (
      <span className="inline-flex flex-wrap items-center gap-1.5">
        <Badge tone="neutral">Meogeobojo 관리</Badge>
        {live && !opts.identifier && !same(managed, live) && <span data-testid="kakao-differs">카카오 실시간 값은 <b>{live}</b> 예요 (이 값이 우선해요)</span>}
      </span>)
  }
  if (live) {
    return (
      <span className="inline-flex flex-wrap items-center gap-1.5" data-testid="kakao-live-note">
        <Badge tone="amber">Kakao Live</Badge><b>{live}</b><span>· 저장되지 않아요. 입력하면 이 값 대신 쓰여요</span>
      </span>)
  }
  return undefined
}

export const liveText = (n: number | null | undefined) => (n == null ? null : String(n))

const FAIL_TEXT: Record<string, string> = {
  rate_limited: '카카오 요청 한도에 걸렸어요. 잠시 뒤 새로고침해 주세요.',
  timeout: '카카오 응답이 늦어져서 중단했어요. 새로고침해 주세요.',
  unavailable: '카카오(또는 검색 함수)가 지금 응답하지 않아요.',
  network: '네트워크에 연결할 수 없어요.',
  forbidden: '이 계정은 카카오 검색을 쓸 권한이 없어요.',
}

/** What to say for a lookup that has no verified place. Null while loading or when there is nothing to say. */
export function unavailableMessage(d: KakaoRestaurantDetails): string | null {
  if (d.status === 'no_context') return '연결된 대학교(또는 식당 좌표)가 없어 카카오에서 찾을 수 없어요. 대학교를 연결하면 이 정보를 불러와요.'
  if (d.status === 'not_found') return `카카오에서 이 장소 ID로 등록된 곳을 확인하지 못했어요. 이름이 같은 다른 곳은 보여 주지 않아요. 폐업했거나 캠퍼스에서 멀 수 있어요.${d.adminSearchUnavailable ? ' (관리자 검색 함수가 배포되지 않아 기본 검색만 했어요.)' : ''}`
  if (d.status === 'error') return FAIL_TEXT[d.errorKind ?? 'unavailable'] ?? FAIL_TEXT.unavailable
  return null
}

const ROWS: [string, (p: KakaoLive) => string | null][] = [
  ['이름', (p) => p.name], ['카테고리', (p) => p.category], ['주소', (p) => p.address], ['전화', (p) => p.phone],
  ['위도 / 경도', (p) => (p.latitude != null && p.longitude != null ? `${p.latitude} / ${p.longitude}` : null)],
]

/** The restaurant edit page's live Kakao panel: verification, values, refresh and why it may be empty. */
export function KakaoLiveCard({ subject, details }: { subject: KakaoSubject | undefined; details: KakaoRestaurantDetails }) {
  if (!subject?.placeId) return null
  const p = details.place
  const why = unavailableMessage(details)
  return (
    <Card aria-label="카카오 실시간 정보" className="space-y-2">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="flex flex-wrap items-center gap-2 font-bold">카카오 실시간 정보
          {details.status === 'verified' && <Badge tone="green">장소 ID로 확인됨</Badge>}
          {(details.status === 'not_found' || details.status === 'error' || details.status === 'no_context') && <Badge tone="amber">확인 못 함</Badge>}
          <span className="text-sm font-normal text-muted">읽기 전용 · 저장하지 않아요</span></h2>
        <Button type="button" size="sm" variant="outline" disabled={details.isFetching || details.status === 'no_context'} onClick={() => void details.refresh()}>
          <RefreshCw className={`size-3.5 ${details.isFetching ? 'animate-spin' : ''}`} />카카오 정보 새로고침</Button>
      </div>
      {details.isLoading && <div aria-label="카카오 정보를 불러오는 중" className="space-y-2"><Skeleton className="h-4 w-2/3" /><Skeleton className="h-4 w-1/2" /><Skeleton className="h-4 w-3/5" /></div>}
      {!details.isLoading && why && !p && <p role="status" className="flex items-start gap-2 text-sm text-muted"><AlertTriangle className="mt-0.5 size-4 shrink-0 text-amber-600" />{why}</p>}
      {p && (
        <dl className="grid gap-x-4 gap-y-1 text-sm sm:grid-cols-[8rem_1fr]">
          {ROWS.map(([k, f]) => { const v = f(p); return v ? <div key={k} className="contents"><dt className="text-muted">{k}</dt><dd>{v}</dd></div> : null })}
          {p.mapUrl && <div className="contents"><dt className="text-muted">카카오맵</dt><dd><a className="text-brand-strong underline" href={p.mapUrl} target="_blank" rel="noreferrer">장소 페이지</a></dd></div>}
        </dl>)}
      {p && why === null && details.lastSuccessAt && <p className="text-xs text-muted">마지막으로 확인한 시각 {time(details.lastSuccessAt)} (이 화면에서만 기억해요)</p>}
      <p className="text-xs text-muted">입력칸 아래에 <b>Kakao Live</b>로 표시된 값은 비어 있는 칸에 대한 참고용이에요. 입력하거나 저장하기 전에는 앱·초안·CSV에 들어가지 않고, 직접 입력한 값(<b>Meogeobojo 관리</b>)이 언제나 우선해요.</p>
    </Card>
  )
}

/** One restaurant row of the list: the live category and address, fetched lazily and cached. */
export function KakaoLiveCell({ placeId, name, location, enabled }: { placeId: string | null; name: string; location: KakaoLocation | null; enabled: boolean }) {
  const d = useKakaoRestaurantDetails(placeId, name, location, { enabled })
  if (!placeId) return <span className="text-xs text-muted">Kakao ID 없음</span>
  if (!enabled) return <span className="text-xs text-muted">—</span>
  if (d.isLoading) return <Skeleton className="h-8 w-40" />
  return (
    <div className="flex items-start gap-2 text-xs">
      {d.status === 'verified' ? <CheckCircle2 className="mt-0.5 size-3.5 shrink-0 text-green-700" aria-label="카카오에서 확인됨" /> : <HelpCircle className="mt-0.5 size-3.5 shrink-0 text-amber-600" aria-label="카카오 정보를 확인하지 못함" />}
      <div className="min-w-0">
        {d.place ? <><div className="truncate">{d.place.category ?? '카테고리 없음'}</div><div className="truncate text-muted">{d.place.address ?? '주소 없음'}</div></>
          : <span className="text-muted">{d.status === 'not_found' ? '카카오에서 확인 못 함' : d.status === 'no_context' ? '대학교 연결 없음' : '지금 불러올 수 없어요'}</span>}
      </div>
      <button type="button" className="ml-auto shrink-0 rounded p-1 text-muted hover:bg-page" aria-label={`${name} 카카오 정보 새로고침`} disabled={d.isFetching} onClick={() => void d.refresh()}>
        <RefreshCw className={`size-3 ${d.isFetching ? 'animate-spin' : ''}`} /></button>
    </div>)
}

type Uni = UniRow
/** New-restaurant check: does Kakao have a place with exactly this id? Shown BEFORE the restaurant is saved; never fills the form. */
export function KakaoIdCheck({ placeId, name, universityIds, universities, near, checkedId, onCheck }: {
  placeId: string; name: string; universityIds: string[]; universities: Uni[]; near: { latitude: number; longitude: number } | null
  checkedId: string | null; onCheck: (id: string) => void
}) {
  const id = placeId.trim()
  const campuses = campusesOf(universities.filter((u) => universityIds.includes(u.id)))
  const location = { campuses, near }
  const active = checkedId !== null && checkedId === id
  const d = useKakaoRestaurantDetails(id || null, name, location, { enabled: active })
  const existing = useQuery({
    queryKey: ['kakao-existing', id], enabled: active, staleTime: 30_000,
    queryFn: async () => {
      const { data } = await supabase.from('restaurant_overrides').select('id,name_ko').eq('kakao_place_id', id).limit(1)
      return ((data ?? []) as { id: string; name_ko: string }[])[0] ?? null
    },
  })
  if (!id) return null
  return (
    <Card aria-label="카카오 장소 확인" className="space-y-2">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="font-bold">카카오 장소 확인 <span className="text-sm font-normal text-muted">저장 전에 이 ID가 어떤 곳인지 확인해요</span></h2>
        <Button type="button" size="sm" variant="outline" disabled={d.isFetching} onClick={() => (active ? void d.refresh() : onCheck(id))}><RefreshCw className={`size-3.5 ${d.isFetching ? 'animate-spin' : ''}`} />카카오에서 확인하기</Button>
      </div>
      {!active && <p className="text-sm text-muted">대학교를 고른 뒤 '카카오에서 확인하기'를 누르면, 이 ID의 장소를 찾아서 보여 줘요. 양식에 자동으로 채우지는 않아요.</p>}
      {active && existing.data && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">이미 등록된 카카오 장소 ID예요 (<b>{existing.data.name_ko}</b>). 새로 만들지 말고 기존 식당을 편집해 주세요.</p>}
      {active && d.isLoading && <Skeleton className="h-16 w-full" />}
      {active && d.place && (
        <div className="space-y-1 text-sm">
          <p><Badge tone="green">장소 ID로 확인됨</Badge> <b>{d.place.name}</b></p>
          <p className="text-muted">{[d.place.category, d.place.address, d.place.phone].filter(Boolean).join(' · ') || '자세한 정보가 없어요'}</p>
          <p className="text-xs text-muted">맞는 곳인지 확인하세요. 이 값은 양식에 자동으로 들어가지 않아요. 아래 칸에 직접 입력한 값만 저장돼요.</p>
        </div>)}
      {active && !d.isLoading && !d.place && (
        <p role="alert" className="flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900"><AlertTriangle className="mt-0.5 size-4 shrink-0" />
          {unavailableMessage(d) ?? '확인하지 못했어요.'} 확인되지 않은 ID로도 만들 수 있지만, 다른 식당이 연결되지 않았는지 다시 확인해 주세요.</p>)}
    </Card>)
}
