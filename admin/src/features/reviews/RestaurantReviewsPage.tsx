import { useQuery } from '@tanstack/react-query'
import { ArrowLeft } from 'lucide-react'
import { Link, useParams } from 'react-router-dom'
import { PageHeader } from '@/components/ui'
import { useAuth } from '@/lib/auth'
import { supabase } from '@/lib/supabase'
import ReviewsPanel from './ReviewsPanel'

/** One restaurant's reviews, with its own CSV 가져오기 / 내보내기 (opened from the overall 리뷰 page). */
export default function RestaurantReviewsPage() {
  const { placeId = '' } = useParams()
  const { can } = useAuth()
  const place = useQuery({
    queryKey: ['review-place', placeId],
    queryFn: async () => {
      const { data, error } = await supabase.from('restaurant_overrides').select('id,name_ko').eq('kakao_place_id', placeId).limit(1)
      if (error) throw error
      return ((data ?? []) as { id: string; name_ko: string }[])[0] ?? null
    },
  })
  return (
    <div className="max-w-4xl">
      <Link to="/moderation?tab=reviews" className="mb-3 inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><ArrowLeft className="size-4" />전체 리뷰</Link>
      <PageHeader title={place.data?.name_ko ?? '식당 리뷰'} description={`이 식당의 리뷰만 모아 보여요 · 카카오 장소 ID ${placeId}`}
        actions={place.data && can('admin') ? <Link to={`/restaurants/${place.data.id}`} className="text-sm font-medium underline-offset-2 hover:underline">식당 정보 열기</Link> : undefined} />
      {place.data === null && <p className="mb-4 rounded-xl bg-page p-3 text-sm text-muted">이 장소는 아직 식당 정보에 없어요. 리뷰는 그대로 저장돼 있어요.</p>}
      <ReviewsPanel placeId={placeId} canImport={can('admin')} />
    </div>
  )
}
