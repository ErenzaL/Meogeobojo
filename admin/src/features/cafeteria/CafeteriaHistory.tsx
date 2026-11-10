import { useQuery } from '@tanstack/react-query'
import { Badge, Button, EmptyState, ErrorState, Skeleton } from '@/components/ui'
import { formatKst, KIND_LABEL, type Version } from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import { addDays } from './meal'

type WeekRow = { id: string; week_start: string }

/** The publication history of one cafeteria across all its weeks (every publish, take-down and restore). Restoring is done in
 *  the week's own page (게시 이력 → 이 버전으로 복원): "이 주 열기" goes there. */
export default function CafeteriaHistory({ weeks, onOpenWeek }: { weeks: WeekRow[]; onOpenWeek: (monday: string) => void }) {
  const ids = weeks.map((w) => w.id)
  const q = useQuery({
    queryKey: ['cafeteria-history', ids.join(',')], enabled: ids.length > 0,
    queryFn: async () => {
      const { data, error } = await supabase.from('content_versions').select('id,entity_id,version,kind,reason,published_at,published_by,rolled_back_from').eq('entity_type', 'cafeteria_week').in('entity_id', ids).order('published_at', { ascending: false }).limit(60)
      if (error) throw error
      return data as (Pick<Version, 'id' | 'version' | 'kind' | 'reason' | 'published_at' | 'published_by' | 'rolled_back_from'> & { entity_id: string })[]
    },
  })
  const monday = new Map(weeks.map((w) => [w.id, w.week_start]))
  if (ids.length === 0) return <EmptyState>아직 게시한 적이 없어요.</EmptyState>
  if (q.isLoading) return <Skeleton className="h-24 w-full" />
  if (q.error) return <ErrorState error={q.error} onRetry={() => void q.refetch()} />
  if (!q.data?.length) return <EmptyState>아직 게시한 적이 없어요.</EmptyState>
  return (
    <ul aria-label="식당 게시 이력" className="divide-y divide-line rounded-2xl border border-line bg-white text-sm">
      {q.data.map((v) => {
        const m = monday.get(v.entity_id) ?? ''
        return (
          <li key={v.id} className="flex flex-wrap items-center justify-between gap-2 p-3">
            <span><Badge tone="brand">v{v.version} · {KIND_LABEL[v.kind] ?? v.kind}</Badge> <b>{m} ~ {m ? addDays(m, 6) : ''}</b>
              {v.rolled_back_from ? <span className="text-xs text-muted"> (v{v.rolled_back_from}에서 복원)</span> : null}
              <span className="ml-2 text-xs text-muted">{formatKst(v.published_at)}{v.reason ? ` · ${v.reason}` : ''}</span></span>
            <Button size="sm" variant="outline" onClick={() => onOpenWeek(m)}>이 주 열기</Button>
          </li>)
      })}
    </ul>)
}
