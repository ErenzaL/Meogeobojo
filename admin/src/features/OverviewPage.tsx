import { useQuery } from '@tanstack/react-query'
import { Card, ErrorState, PageHeader, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'

async function count(table: string, filter?: (q: ReturnType<typeof base>) => ReturnType<typeof base>) {
  const q = filter ? filter(base(table)) : base(table)
  const { count: n, error } = await q
  if (error) throw error
  return n ?? 0
}
const base = (table: string) => supabase.from(table).select('*', { count: 'exact', head: true })

/** Real counts only: each tile is a COUNT query; a failing tile shows its error instead of a made-up number. */
export default function OverviewPage() {
  const stats = useQuery({
    queryKey: ['overview'],
    queryFn: async () => {
      const [restaurants, published, noDescription, universities, users, reviews, openReports] = await Promise.all([
        count('restaurant_overrides'),
        count('restaurant_overrides', (q) => q.eq('visibility', 'published')),
        count('restaurant_overrides', (q) => q.is('description', null)),
        count('universities'),
        count('profiles'),
        count('student_reviews'),
        count('reports', (q) => q.eq('status', 'open')),
      ])
      const byVis = await Promise.all((['draft', 'published', 'hidden', 'archived'] as const).map(async (v) => [v, await count('restaurant_overrides', (q) => q.eq('visibility', v))] as const))
      return { restaurants, published, noDescription, universities, users, reviews, openReports, byVis }
    },
  })
  const tiles: [string, number | undefined][] = stats.data ? [
    ['관리 중인 식당', stats.data.restaurants], ['공개된 식당', stats.data.published], ['설명이 없는 식당', stats.data.noDescription],
    ['대학교', stats.data.universities], ['가입한 사용자', stats.data.users], ['리뷰', stats.data.reviews], ['처리 대기 신고', stats.data.openReports],
  ] : []
  const max = Math.max(1, ...(stats.data?.byVis.map(([, n]) => n) ?? [1]))
  return (
    <>
      <PageHeader title="개요" description="데이터베이스에서 바로 집계한 값이에요." />
      {stats.error && <ErrorState error={stats.error} onRetry={() => void stats.refetch()} />}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {stats.isLoading ? Array.from({ length: 8 }, (_, i) => <Skeleton key={i} className="h-24" />) : tiles.map(([label, n]) => (
          <Card key={label}><div className="text-sm text-muted">{label}</div><div className="mt-1 text-3xl font-bold tabular-nums">{n?.toLocaleString('ko-KR')}</div></Card>))}
      </div>
      {stats.data && (
        <Card className="mt-6 max-w-xl">
          <h2 className="mb-3 font-bold">식당 공개 상태</h2>
          <div className="space-y-2">
            {stats.data.byVis.map(([v, n]) => (
              <div key={v} className="flex items-center gap-3 text-sm">
                <span className="w-12 text-muted">{({ draft: '초안', published: '공개', hidden: '숨김', archived: '보관' } as const)[v]}</span>
                <div className="h-3 flex-1 rounded-full bg-page"><div className="h-3 rounded-full bg-brand-strong" style={{ width: `${(n / max) * 100}%` }} /></div>
                <span className="w-10 text-right tabular-nums">{n}</span>
              </div>))}
          </div>
        </Card>)}
    </>
  )
}
