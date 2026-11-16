import { useQuery } from '@tanstack/react-query'
import { useMemo, useState } from 'react'
import { Badge, Button, Card, ErrorState, Input, Select, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { buildInputRows, hhmm, summarize, yesNo, type FeatureRow, type InputRow, type MenuLite, type RestaurantLite } from './inputs'

const PAGE = 1000
async function fetchAll<T>(table: string, columns: string, order: string): Promise<T[]> {
  const out: T[] = []
  for (let from = 0; from < 20000; from += PAGE) {
    const { data, error } = await supabase.from(table).select(columns).order(order).range(from, from + PAGE - 1)
    if (error) throw error
    const rows = (data ?? []) as T[]
    out.push(...rows)
    if (rows.length < PAGE) break
  }
  return out
}

const SHOWN = 100
const visLabel: Record<string, string> = { published: '공개', draft: '초안', hidden: '숨김', archived: '보관' }

/** 추천 page: the data the recommendation runs on, per restaurant (stored hours/amenities + published menus). Read-only. */
export default function RecommendationInputs() {
  const q = useQuery({
    queryKey: ['recommendation-inputs'],
    queryFn: async () => {
      const [features, restaurants, menus] = await Promise.all([
        fetchAll<FeatureRow>('recommendation_demo_features', 'kakao_place_id,name_ko,open_time,last_order_time,break_time,no_break_time,parking,local_currency,fast_turnover,takeout,open_late,source', 'kakao_place_id').catch(() => [] as FeatureRow[]),
        fetchAll<RestaurantLite>('restaurant_overrides', 'id,kakao_place_id,name_ko,visibility', 'name_ko'),
        fetchAll<MenuLite>('restaurant_menus', 'restaurant_id,category,price_krw,status,available', 'id'),
      ])
      return buildInputRows(features, restaurants, menus)
    },
  })
  const [search, setSearch] = useState('')
  const [vis, setVis] = useState('published')
  const [budget, setBudget] = useState('')
  const [limit, setLimit] = useState(SHOWN)
  const rows = q.data
  const sum = useMemo(() => (rows ? summarize(rows) : null), [rows])
  const shown = useMemo(() => {
    const term = search.trim().toLowerCase()
    return (rows ?? []).filter((r) => (vis === '' || r.visibility === vis)
      && (budget === '' || (budget === 'ready' ? r.menus.meals > 0 : r.menus.meals === 0))
      && (term === '' || r.name.toLowerCase().includes(term) || r.kakaoPlaceId.includes(term)))
  }, [rows, search, vis, budget])

  return (
    <section aria-label="추천에 쓰이는 식당 정보" className="mb-6 space-y-3">
      <h2 className="text-lg font-bold">추천에 쓰이는 식당 정보</h2>
      <p className="max-w-3xl text-sm text-muted">식당마다 앱의 추천이 지금 쓰는 영업시간·편의 정보와, 예산을 판정하는 게시된 메뉴를 보여줘요. 읽기 전용이에요. 위치와 거리는 저장하지 않고 카카오의 실시간 좌표로 계산해요.</p>
      {q.isLoading && <Skeleton className="h-40 w-full" />}
      {q.error && <ErrorState error={q.error} onRetry={() => void q.refetch()} />}
      {sum && (
        <>
          <div role="status" aria-label="추천 정보 요약" className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
            <Card><div className="text-xs text-muted">공개 식당</div><div className="text-xl font-bold">{sum.published}곳</div></Card>
            <Card><div className="text-xs text-muted">영업시간·편의 정보가 있는 곳</div><div className="text-xl font-bold">{sum.withFeatures}곳</div></Card>
            <Card><div className="text-xs text-muted">영업시간(시작·마지막 주문)이 있는 곳</div><div className="text-xl font-bold">{sum.withHours}곳</div></Card>
            <Card><div className="text-xs text-muted">게시된 메뉴가 있는 곳</div><div className="text-xl font-bold">{sum.withMenus}곳</div></Card>
            <Card><div className="text-xs text-muted">예산을 판정할 수 있는 곳</div><div className="text-xl font-bold">{sum.budgetReady}곳</div><div className="text-[11px] text-muted">식사·면류·분식 메뉴와 가격이 있어요</div></Card>
          </div>
          <div className="grid gap-3 sm:grid-cols-3">
            <Input aria-label="추천 정보 검색" placeholder="식당 이름 또는 장소 ID" value={search} onChange={(e) => { setSearch(e.target.value); setLimit(SHOWN) }} />
            <Select aria-label="공개 상태 보기" value={vis} onChange={(e) => { setVis(e.target.value); setLimit(SHOWN) }}>
              <option value="">모든 상태</option><option value="published">공개</option><option value="draft">초안</option><option value="hidden">숨김</option><option value="archived">보관</option>
            </Select>
            <Select aria-label="예산 판정 보기" value={budget} onChange={(e) => { setBudget(e.target.value); setLimit(SHOWN) }}>
              <option value="">예산 판정: 전체</option><option value="ready">예산 판정 가능</option><option value="no">예산 판정 불가 (식사 메뉴·가격 없음)</option>
            </Select>
          </div>
          <div className="overflow-auto rounded-2xl border border-line bg-white">
            <table aria-label="추천 입력 정보" className="w-full text-xs">
              <thead className="sticky top-0 border-b border-line bg-page text-left text-muted">
                <tr>{['식당', '공개', '영업', '브레이크', '주차', '포장', '지역화폐', '빠른 회전', '늦게까지', '메뉴', '식사 메뉴', '최저 식사 가격', '출처'].map((h) => <th key={h} className="whitespace-nowrap px-3 py-2 font-medium">{h}</th>)}</tr>
              </thead>
              <tbody>
                {shown.slice(0, limit).map((r) => <Row key={r.kakaoPlaceId || r.name} r={r} />)}
                {shown.length === 0 && <tr><td colSpan={13} className="px-3 py-6 text-center text-muted">조건에 맞는 식당이 없어요.</td></tr>}
              </tbody>
            </table>
          </div>
          <div className="flex items-center gap-3 text-xs text-muted">
            <span>{shown.length}곳 중 {Math.min(limit, shown.length)}곳 표시</span>
            {shown.length > limit && <Button size="sm" variant="outline" onClick={() => setLimit((n) => n + SHOWN)}>더 보기</Button>}
          </div>
        </>)}
    </section>
  )
}

function Row({ r }: { r: InputRow }) {
  const f = r.features
  const hours = f?.open_time && f.last_order_time ? `${hhmm(f.open_time)} ~ ${hhmm(f.last_order_time)}` : '미확인'
  return (
    <tr className="border-b border-line align-top last:border-0">
      <td className="px-3 py-2"><div className="font-medium">{r.name}</div><div className="text-muted">{r.kakaoPlaceId ? `ID ${r.kakaoPlaceId}` : '장소 ID 없음'}</div></td>
      <td className="px-3 py-2">{r.visibility ? <Badge tone={r.visibility === 'published' ? 'green' : 'neutral'}>{visLabel[r.visibility] ?? r.visibility}</Badge> : '—'}</td>
      <td className="whitespace-nowrap px-3 py-2">{hours}</td>
      <td className="whitespace-nowrap px-3 py-2">{!f ? '미확인' : f.break_time ?? (f.no_break_time === true ? '없음' : '미확인')}</td>
      <td className="px-3 py-2">{yesNo(f?.parking)}</td>
      <td className="px-3 py-2">{yesNo(f?.takeout)}</td>
      <td className="px-3 py-2">{yesNo(f?.local_currency)}</td>
      <td className="px-3 py-2">{yesNo(f?.fast_turnover)}</td>
      <td className="px-3 py-2">{yesNo(f?.open_late)}</td>
      <td className="px-3 py-2 tabular-nums">{r.menus.active}개{r.menus.active > r.menus.categorized ? <span className="text-muted"> (분류 {r.menus.categorized})</span> : null}</td>
      <td className="px-3 py-2 tabular-nums">{r.menus.meals > 0 ? `${r.menus.meals}개` : <span className="text-amber-900">없음</span>}</td>
      <td className="px-3 py-2 tabular-nums">{r.menus.cheapestMeal != null ? `${r.menus.cheapestMeal.toLocaleString('ko-KR')}원` : '—'}</td>
      <td className="px-3 py-2 text-muted">{f?.source ?? '—'}</td>
    </tr>
  )
}
