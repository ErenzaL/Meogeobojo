import { useQuery } from '@tanstack/react-query'
import { Badge, Card, ErrorState, PageHeader, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { formatDateTime } from '@/lib/utils'

type Stats = { total: number; errors: number; mock_requests: number; avg_latency_ms: number | null; last_success_at: string | null; latest_model_version: string | null; latest_is_mock: boolean | null }

/** Real telemetry only (public.recommendation_requests, written by the server). */
export default function RecommendationsPage() {
  const q = useQuery({
    queryKey: ['recommendation-stats'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('admin_recommendation_stats', { p_days: 7 })
      if (error) throw error
      const row = (Array.isArray(data) ? data[0] : data) as Stats | null | undefined
      return row ?? null
    },
  })
  const s = q.data
  const none = !q.isLoading && !q.error && (!s || s.total === 0)
  return (
    <>
      <PageHeader title="추천" description="최근 7일 동안 서버가 기록한 추천 API 호출만 보여줘요." />
      {q.isLoading && <Skeleton className="h-40 w-full" />}
      {q.error && <ErrorState error={q.error} onRetry={() => void q.refetch()} />}
      {none && (
        <Card className="max-w-2xl space-y-2 text-sm">
          <p className="font-semibold">아직 기록된 추천 요청이 없어요.</p>
          <p className="text-muted">추천 모델이 연결되고 서버가 요청을 기록하기 시작하면 모델 버전, 요청 수, 평균 지연 시간, 오류율이 여기에 표시돼요. 지금 보이는 값은 없고, 가짜 수치도 만들지 않아요.</p>
        </Card>
      )}
      {s && s.total > 0 && (
        <>
          {s.latest_is_mock && (
            <p role="alert" className="mb-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">
              최근 응답은 <b>테스트용 목(mock)</b>이에요. 실제 추천 모델의 예측이 아니에요.
            </p>
          )}
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Card><div className="text-sm text-muted">현재 모델 버전</div><div className="mt-1 text-xl font-bold">{s.latest_model_version ?? '—'} {s.latest_is_mock && <Badge tone="amber">mock</Badge>}</div></Card>
            <Card><div className="text-sm text-muted">요청 수</div><div className="mt-1 text-3xl font-bold tabular-nums">{s.total.toLocaleString('ko-KR')}</div></Card>
            <Card><div className="text-sm text-muted">평균 지연 (성공 요청)</div><div className="mt-1 text-3xl font-bold tabular-nums">{s.avg_latency_ms != null ? `${s.avg_latency_ms} ms` : '—'}</div></Card>
            <Card><div className="text-sm text-muted">오류율</div><div className="mt-1 text-3xl font-bold tabular-nums">{((s.errors / s.total) * 100).toFixed(1)}%</div></Card>
          </div>
          <p className="mt-4 text-sm text-muted">마지막 성공: {formatDateTime(s.last_success_at)}</p>
        </>
      )}
    </>
  )
}
