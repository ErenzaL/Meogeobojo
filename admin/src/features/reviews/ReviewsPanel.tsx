import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Input, Select, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage, formatDateTime } from '@/lib/utils'
import ReviewCsvTools, { SOURCE_LABEL, sourceLabel } from './ReviewCsvTools'

type Review = {
  id: string; kakao_place_id: string; rating: number | null; source: string; platform: string | null; source_rating: number | null
  body: string | null; moderation_status: 'visible' | 'hidden' | 'removed'; moderation_reason: string | null; created_at: string
}
type Place = { id: string; kakao_place_id: string; name_ko: string }
const PAGE = 50
const clean = (s: string) => s.replace(/[%,()*\\]/g, ' ').trim()

export type ReviewSort = 'new' | 'old' | 'high' | 'low'
export const SORT_LABEL: Record<ReviewSort, string> = { new: '최신순', old: '오래된순', high: '별점 높은순', low: '별점 낮은순' }
export type ReviewFilters = { sort: ReviewSort; source: string; rating: string; status: string; from: string; to: string; text: string }
export const NO_FILTERS: ReviewFilters = { sort: 'new', source: '', rating: '', status: '', from: '', to: '', text: '' }

/** Where a restaurant's own review page is. */
export const restaurantReviewsPath = (placeId: string) => `/moderation/reviews/${encodeURIComponent(placeId)}`

/** The CSV tools and the review list of ONE restaurant (its review page, and the review section of its edit page). */
export default function ReviewsPanel({ placeId, canImport }: { placeId: string; canImport: boolean }) {
  return (
    <>
      <ReviewCsvTools canImport={canImport} placeId={placeId} />
      <ReviewList placeId={placeId} />
    </>
  )
}

/** A day typed in a date box is a Korean day: from its first to its last moment. */
const dayStart = (d: string) => `${d}T00:00:00+09:00`
const dayEnd = (d: string) => `${d}T23:59:59.999+09:00`

/**
 * Reviews (students' and imported ones, one table) with sorting, filters and moderation.
 * Without [placeId]: every restaurant (each review names its restaurant and links to that restaurant's page). With it: one.
 */
export function ReviewList({ placeId }: { placeId?: string }) {
  const qc = useQueryClient()
  const [f, setF] = useState<ReviewFilters>(NO_FILTERS)
  const [shown, setShown] = useState(PAGE)
  const [notice, setNotice] = useState<string | null>(null)
  const [act, setAct] = useState<{ r: Review; to: Review['moderation_status'] } | null>(null)
  const set = (patch: Partial<ReviewFilters>) => { setF((x) => ({ ...x, ...patch })); setShown(PAGE) }
  const term = clean(f.text)
  const filtered = JSON.stringify(f) !== JSON.stringify(NO_FILTERS)

  const reviews = useQuery({
    queryKey: ['reviews-list', placeId ?? 'all', f.sort, f.source, f.rating, f.status, f.from, f.to, term, shown], placeholderData: keepPreviousData,
    queryFn: async () => {
      let q = supabase.from('student_reviews').select('id,kakao_place_id,rating,source,platform,source_rating,body,moderation_status,moderation_reason,created_at', { count: 'exact' })
      if (placeId) q = q.eq('kakao_place_id', placeId)
      if (f.source) q = q.eq('source', f.source)
      if (f.rating === 'none') q = q.is('rating', null)
      else if (f.rating) q = q.eq('rating', Number(f.rating))
      if (f.status) q = q.eq('moderation_status', f.status)
      if (f.from) q = q.gte('created_at', dayStart(f.from))
      if (f.to) q = q.lte('created_at', dayEnd(f.to))
      if (term) q = q.ilike('body', `%${term}%`)
      // by stars: reviews without stars come last whichever way it goes
      if (f.sort === 'high' || f.sort === 'low') q = q.order('rating', { ascending: f.sort === 'low', nullsFirst: false })
      const { data, error, count } = await q.order('created_at', { ascending: f.sort === 'old' }).order('id').range(0, shown - 1)
      if (error) throw error
      return { rows: data as Review[], total: count ?? (data?.length ?? 0) }
    },
  })

  // names of the restaurants on the page (an imported review only carries the Kakao place id)
  const ids = [...new Set((reviews.data?.rows ?? []).map((r) => r.kakao_place_id))].sort()
  const names = useQuery({
    queryKey: ['review-places', ids.join(',')], enabled: !placeId && ids.length > 0,
    queryFn: async () => {
      const { data, error } = await supabase.from('restaurant_overrides').select('id,kakao_place_id,name_ko').in('kakao_place_id', ids)
      if (error) throw error
      return new Map((data as Place[]).map((p) => [p.kakao_place_id, p]))
    },
  })

  const run = useMutation({
    mutationFn: async ({ a, reason }: { a: NonNullable<typeof act>; reason: string }) => {
      const { error } = await supabase.rpc('admin_moderate_review', { p_review: a.r.id, p_status: a.to, p_reason: reason })
      if (error) throw error
    },
    onSuccess: async () => {
      setAct(null); setNotice('처리했어요. 활동 기록에 사유가 남았어요.')
      for (const k of ['reviews-list', 'review-stats']) await qc.invalidateQueries({ queryKey: [k] })
    },
    onError: (e) => { setAct(null); setNotice(errorMessage(e)) },
  })

  return (
    <>
      {notice && <p role="status" className="mb-4 rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
      <Card aria-label="리뷰 정렬·필터" className="mb-4 space-y-3 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <Select aria-label="정렬" className="w-40" value={f.sort} onChange={(e) => set({ sort: e.target.value as ReviewSort })}>
            {(Object.keys(SORT_LABEL) as ReviewSort[]).map((k) => <option key={k} value={k}>{SORT_LABEL[k]}</option>)}
          </Select>
          <Select aria-label="리뷰 출처" className="w-36" value={f.source} onChange={(e) => set({ source: e.target.value })}>
            <option value="">모든 출처</option>
            {Object.entries(SOURCE_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </Select>
          <Select aria-label="별점" className="w-32" value={f.rating} onChange={(e) => set({ rating: e.target.value })}>
            <option value="">모든 별점</option>
            {[5, 4, 3, 2, 1].map((n) => <option key={n} value={String(n)}>★ {n}</option>)}
            <option value="none">별점 없음</option>
          </Select>
          <Select aria-label="공개 상태" className="w-32" value={f.status} onChange={(e) => set({ status: e.target.value })}>
            <option value="">모든 상태</option><option value="visible">공개</option><option value="hidden">숨김</option><option value="removed">삭제됨</option>
          </Select>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <label className="flex items-center gap-1.5 text-sm text-muted">작성일
            <Input aria-label="작성일 시작" type="date" className="w-40" value={f.from} max={f.to || undefined} onChange={(e) => set({ from: e.target.value })} />
            ~
            <Input aria-label="작성일 끝" type="date" className="w-40" value={f.to} min={f.from || undefined} onChange={(e) => set({ to: e.target.value })} />
          </label>
          <Input aria-label="리뷰 검색" className="w-56" placeholder="리뷰 내용" value={f.text} onChange={(e) => set({ text: e.target.value })} />
          {filtered && <Button variant="outline" size="sm" onClick={() => { setF(NO_FILTERS); setShown(PAGE) }}>초기화</Button>}
          {reviews.data && <span className="text-sm text-muted">{reviews.data.total.toLocaleString()}개 중 {reviews.data.rows.length.toLocaleString()}개 표시</span>}
        </div>
      </Card>
      {reviews.isLoading && <Skeleton className="h-32 w-full" />}
      {reviews.error && <ErrorState error={reviews.error} onRetry={() => void reviews.refetch()} />}
      {reviews.data?.rows.length === 0 && <EmptyState>{filtered ? '조건에 맞는 리뷰가 없어요.' : placeId ? '이 식당의 리뷰가 아직 없어요.' : '리뷰가 없어요.'}</EmptyState>}
      <div className="space-y-3">
        {reviews.data?.rows.map((r) => {
          const p = names.data?.get(r.kakao_place_id)
          return (
            <Card key={r.id} className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <div className="font-semibold">{r.rating == null ? '별점 없음' : `★ ${r.source_rating ?? r.rating}`} {r.source !== 'app' && <Badge tone="brand">{sourceLabel(r.source)}{r.platform ? ` · ${r.platform}` : ''}</Badge>} <Badge tone={r.moderation_status === 'visible' ? 'green' : 'red'}>{({ visible: '공개', hidden: '숨김', removed: '삭제됨' })[r.moderation_status]}</Badge></div>
                <p className="text-sm">{r.body ?? '(내용 없음)'}</p>
                <div className="text-xs text-muted">
                  {!placeId && <><Link to={restaurantReviewsPath(r.kakao_place_id)} className="font-medium text-ink underline-offset-2 hover:underline">{p?.name_ko ?? r.kakao_place_id}</Link> · </>}
                  {formatDateTime(r.created_at)}{r.moderation_reason ? ` · 사유: ${r.moderation_reason}` : ''}
                </div>
              </div>
              <div className="flex gap-2">
                {r.moderation_status === 'visible'
                  ? <><Button size="sm" variant="outline" onClick={() => setAct({ r, to: 'hidden' })}>숨기기</Button><Button size="sm" variant="danger" onClick={() => setAct({ r, to: 'removed' })}>삭제</Button></>
                  : <Button size="sm" variant="soft" onClick={() => setAct({ r, to: 'visible' })}>다시 공개</Button>}
              </div>
            </Card>)
        })}
      </div>
      {reviews.data && reviews.data.rows.length < reviews.data.total && (
        <div className="mt-4"><Button variant="outline" disabled={reviews.isFetching} onClick={() => setShown((n) => n + PAGE)}>더 보기</Button></div>)}
      <ConfirmDialog open={!!act} askReason busy={run.isPending} title="사유를 입력해 주세요" description="입력한 사유는 활동 기록에 저장돼요." confirmLabel="처리"
        danger={act?.to === 'removed'} onCancel={() => setAct(null)} onConfirm={(reason) => act && run.mutate({ a: act, reason })} />
    </>
  )
}
