import { useQuery } from '@tanstack/react-query'
import { useMemo, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { Button, Card } from '@/components/ui'
import type { OverviewRow } from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import RestaurantPicker, { type PickerItem } from '../restaurants/picker/RestaurantPicker'
import type { PickerFilters } from '../restaurants/picker/pickerLogic'
import { useUniversities } from '../restaurants/RestaurantsPage'
import ReviewCsvTools from './ReviewCsvTools'
import { ReviewList, restaurantReviewsPath } from './ReviewsPanel'
import { fetchReviewCounts, fetchReviewRestaurants } from './reviewPickerData'

const REVIEW_ITEM: PickerItem = { label: '리뷰', unit: '개', subject: '리뷰가' }
const NO_OVERVIEW = new Map<string, OverviewRow>()

/** How many reviews there are in every state (unfiltered): the overall picture above the list. */
function ReviewStats() {
  const stats = useQuery({
    queryKey: ['review-stats'],
    queryFn: async () => {
      const count = async (narrow: (q: ReturnType<typeof base>) => unknown) => {
        const { count: n, error } = await (narrow(base()) as PromiseLike<{ count: number | null; error: unknown }>)
        if (error) throw error
        return n ?? 0
      }
      const base = () => supabase.from('student_reviews').select('id', { count: 'exact', head: true })
      const [all, visible, hidden, removed, noStars] = await Promise.all([
        count((q) => q), count((q) => q.eq('moderation_status', 'visible')), count((q) => q.eq('moderation_status', 'hidden')),
        count((q) => q.eq('moderation_status', 'removed')), count((q) => q.is('rating', null)),
      ])
      return { all, visible, hidden, removed, noStars }
    },
    retry: false,
  })
  if (!stats.data) return null
  const s = stats.data
  return (
    <Card aria-label="리뷰 현황" className="mb-4 flex flex-wrap items-baseline gap-x-6 gap-y-1 p-4 text-sm">
      <span>전체 리뷰 <b className="text-lg">{s.all.toLocaleString()}</b></span>
      <span className="text-muted">공개 {s.visible.toLocaleString()}</span>
      <span className="text-muted">숨김 {s.hidden.toLocaleString()}</span>
      <span className="text-muted">삭제됨 {s.removed.toLocaleString()}</span>
      <span className="text-muted">별점 없음 {s.noStars.toLocaleString()}</span>
    </Card>
  )
}

/**
 * 리뷰 tab, the overall page. CSV 가져오기 / 내보내기 for every restaurant, the overall picture, and the reviews of ALL
 * restaurants (sort and filter as you like). Picking a restaurant (a name in the list, or 식당별 보기) opens that
 * restaurant's own page.
 */
export default function ReviewsTab({ canImport }: { canImport: boolean }) {
  const [params, setParams] = useSearchParams()
  const nav = useNavigate()
  const byRestaurant = params.get('view') === 'restaurants'
  const setView = (restaurants: boolean) => setParams((p) => { const n = new URLSearchParams(p); if (restaurants) n.set('view', 'restaurants'); else n.delete('view'); return n }, { replace: true })

  return (
    <>
      <ReviewCsvTools canImport={canImport} />
      <div role="group" aria-label="보기" className="mb-4 flex gap-2">
        <Button variant={byRestaurant ? 'outline' : 'soft'} aria-pressed={!byRestaurant} onClick={() => setView(false)}>전체 리뷰</Button>
        <Button variant={byRestaurant ? 'soft' : 'outline'} aria-pressed={byRestaurant} onClick={() => setView(true)}>식당별 보기</Button>
      </div>
      {byRestaurant
        ? <ByRestaurant onOpen={(placeId) => nav(restaurantReviewsPath(placeId))} />
        : <section aria-label="전체 리뷰"><ReviewStats /><ReviewList /></section>}
    </>
  )
}

/** Every managed restaurant with its review count; picking one opens its page. */
function ByRestaurant({ onOpen }: { onOpen: (placeId: string) => void }) {
  const [filters, setFilters] = useState<PickerFilters>({ search: '', university: '', has: '' })
  const [noPlace, setNoPlace] = useState('')
  const restaurants = useQuery({ queryKey: ['review-picker', 'restaurants'], queryFn: fetchReviewRestaurants, refetchOnMount: 'always' })
  const reviewCounts = useQuery({ queryKey: ['review-picker', 'counts'], queryFn: fetchReviewCounts, refetchOnMount: 'always' })
  const universities = useUniversities()
  const schools = useMemo(() => (universities.data ?? []).map((u) => ({ id: u.id, name_ko: u.name_ko })), [universities.data])
  // the picker counts per restaurant (its id); the reviews are counted per Kakao place id
  const counts = useMemo(() => new Map((restaurants.data ?? []).map((r) => [r.id, r.kakaoPlaceId ? (reviewCounts.data?.get(r.kakaoPlaceId) ?? 0) : 0])), [restaurants.data, reviewCounts.data])
  const pick = (id: string) => {
    const r = restaurants.data?.find((x) => x.id === id)
    if (r?.kakaoPlaceId) onOpen(r.kakaoPlaceId)
    else setNoPlace(id)
  }
  return (
    <section aria-label="식당별 리뷰">
      <RestaurantPicker item={REVIEW_ITEM} restaurants={restaurants.data} universities={schools} counts={counts} overview={NO_OVERVIEW}
        loading={restaurants.isLoading} error={restaurants.error} onRetry={() => void restaurants.refetch()}
        filters={filters} onFilters={setFilters} selectedId={noPlace} onSelect={pick} />
      {noPlace && <Card className="text-sm text-muted">카카오 장소 ID가 없는 식당은 리뷰를 불러올 수 없어요.</Card>}
    </section>
  )
}
