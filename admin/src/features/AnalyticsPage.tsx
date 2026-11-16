import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Card, ErrorState, PageHeader, Select, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'

type Stats = { visitors: number; returning_visitors: number; app_opens: number; restaurant_views: number; directions_clicks: number; searches: number }
type Day = { day: string; visitors: number; restaurant_views: number; directions_clicks: number; searches: number }
type Term = { term: string; searches: number }

const n = (v: number) => Number(v).toLocaleString('ko-KR')

async function rpc<T>(name: string, args: Record<string, number>): Promise<T[]> {
  const { data, error } = await supabase.rpc(name, args)
  if (error) throw error
  return (Array.isArray(data) ? data : data ? [data] : []) as T[]
}

/** Real usage only: anonymous app events (public.app_events, migration 20261122000100), aggregated by the database. */
export default function AnalyticsPage() {
  const [days, setDays] = useState(7)
  const q = useQuery({
    queryKey: ['app-event-stats', days],
    queryFn: async () => {
      const [stats, daily, terms] = await Promise.all([
        rpc<Stats>('admin_event_stats', { p_days: days }),
        rpc<Day>('admin_event_daily', { p_days: days }),
        rpc<Term>('admin_top_search_queries', { p_days: days, p_limit: 20 }),
      ])
      return { stats: stats[0] ?? null, daily, terms }
    },
  })
  const data = q.data
  const s = data?.stats
  const none = !q.isLoading && !q.error && (!s || s.app_opens + s.restaurant_views + s.directions_clicks + s.searches === 0)
  return (
    <>
      <PageHeader
        title="분석"
        description="앱이 익명으로 기록한 사용 이벤트만 보여줘요. 계정 정보는 저장하지 않아요."
        actions={
          <Select aria-label="기간" value={days} onChange={(e) => setDays(Number(e.target.value))}>
            <option value={7}>최근 7일</option>
            <option value={30}>최근 30일</option>
          </Select>
        }
      />
      {q.isLoading && <Skeleton className="h-40 w-full" />}
      {q.error && <ErrorState error={q.error} onRetry={() => void q.refetch()} />}
      {none && (
        <Card className="max-w-2xl space-y-2 text-sm">
          <p className="font-semibold">이 기간에 기록된 사용 이벤트가 없어요.</p>
          <p className="text-muted">앱을 열거나 식당을 보고, 길찾기나 검색을 하면 여기에 쌓여요. 가짜 수치는 만들지 않아요.</p>
        </Card>
      )}
      {data && s && !none && (
        <div className="space-y-6">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Stat label="방문자" value={n(s.visitors)} hint="이 기간에 앱을 쓴 기기 수" />
            <Stat
              label="재방문자"
              value={n(s.returning_visitors)}
              hint={s.visitors > 0 ? `방문자의 ${((s.returning_visitors / s.visitors) * 100).toFixed(0)}% · 서로 다른 2일 이상 사용` : '서로 다른 2일 이상 사용'}
            />
            <Stat label="앱 실행" value={n(s.app_opens)} />
            <Stat label="식당 상세 조회" value={n(s.restaurant_views)} />
            <Stat label="길찾기" value={n(s.directions_clicks)} hint={s.restaurant_views > 0 ? `상세 조회의 ${((s.directions_clicks / s.restaurant_views) * 100).toFixed(0)}%` : undefined} />
            <Stat label="검색" value={n(s.searches)} />
          </div>
          <div className="grid gap-4 lg:grid-cols-2">
            <Card>
              <h2 className="mb-3 font-semibold">날짜별</h2>
              <table className="w-full text-sm tabular-nums">
                <thead className="text-left text-xs text-muted"><tr><th className="py-1">날짜</th><th>방문자</th><th>상세 조회</th><th>길찾기</th><th>검색</th></tr></thead>
                <tbody>
                  {data.daily.map((d) => (
                    <tr key={d.day} className="border-t border-line"><td className="py-1.5">{d.day}</td><td>{n(d.visitors)}</td><td>{n(d.restaurant_views)}</td><td>{n(d.directions_clicks)}</td><td>{n(d.searches)}</td></tr>
                  ))}
                </tbody>
              </table>
            </Card>
            <Card>
              <h2 className="mb-3 font-semibold">많이 찾은 검색어</h2>
              {data.terms.length === 0 ? (
                <p className="text-sm text-muted">이 기간에 검색이 없어요.</p>
              ) : (
                <ol className="space-y-1 text-sm">
                  {data.terms.map((t, i) => (
                    <li key={t.term} className="flex justify-between border-t border-line py-1.5 first:border-t-0"><span>{i + 1}. {t.term}</span><span className="tabular-nums text-muted">{n(t.searches)}회</span></li>
                  ))}
                </ol>
              )}
            </Card>
          </div>
        </div>
      )}
    </>
  )
}

function Stat({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <Card>
      <div className="text-sm text-muted">{label}</div>
      <div className="mt-1 text-3xl font-bold tabular-nums">{value}</div>
      {hint && <div className="mt-1 text-xs text-muted">{hint}</div>}
    </Card>
  )
}
