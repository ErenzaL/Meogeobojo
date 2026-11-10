import { useQuery } from '@tanstack/react-query'
import { useState } from 'react'
import { Card, EmptyState, ErrorState, Select, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'

type Stats = {
  participants: number; completers: number; completions: number; points_awarded: number; points_revoked: number
  missions: { id: string; title: string; kind: string; status: string; version: number; participants: number; completions: number; points: number }[]
  daily: { day: string; participants: number; completions: number }[]
  weekly: { week: string; participants: number; completions: number }[]
  by_university: { university: string; participants: number; completions: number }[]
  engagement: { mission_users: number; app_active_users: number }
  pending_contributions: number
}

const pct = (n: number, d: number) => (d > 0 ? `${Math.round((n / d) * 100)}%` : '—')

function Bars({ rows, label }: { rows: { key: string; a: number; b: number }[]; label: string }) {
  const max = Math.max(1, ...rows.map((r) => r.a))
  if (rows.length === 0) return <p className="text-sm text-muted">이 기간에 기록이 없어요.</p>
  return (
    <ul aria-label={label} className="space-y-1.5">
      {rows.map((r) => (
        <li key={r.key} className="grid grid-cols-[5.5rem_1fr_6rem] items-center gap-2 text-xs">
          <span className="text-muted">{r.key}</span>
          <div className="h-2 rounded-full bg-page"><div className="h-full rounded-full bg-brand-strong" style={{ width: `${(r.a / max) * 100}%` }} /></div>
          <span>참여 {r.a} · 완료 {r.b}</span>
        </li>))}
    </ul>
  )
}

/** Real numbers only: every figure comes from admin_mission_stats() over the
 *  progress, points and activity tables. With no activity it says so. */
export default function MissionAnalytics() {
  const [days, setDays] = useState(30)
  const q = useQuery({
    queryKey: ['mission-stats', days],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('admin_mission_stats', { p_days: days })
      if (error) throw error
      return data as Stats
    },
  })
  if (q.isLoading) return <Skeleton className="h-64 w-full" />
  if (q.error) return <ErrorState error={q.error} onRetry={() => void q.refetch()} />
  const s = q.data
  if (!s) return <EmptyState>데이터를 불러오지 못했어요.</EmptyState>
  const empty = s.participants === 0 && s.completions === 0
  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Select aria-label="기간" className="w-40" value={days} onChange={(e) => setDays(Number(e.target.value))}>
          {[7, 30, 90].map((d) => <option key={d} value={d}>최근 {d}일</option>)}
        </Select>
        {s.pending_contributions > 0 && <span className="text-sm text-muted">검토 대기 기여 {s.pending_contributions}건</span>}
      </div>
      {empty && <EmptyState>이 기간에 미션 참여 기록이 아직 없어요. 가짜 지표는 보여주지 않아요.</EmptyState>}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {[
          ['참여 사용자', String(s.participants)],
          ['미션 완료 수', String(s.completions)],
          ['지급 포인트', `${s.points_awarded}P`],
          ['회수 포인트', `${s.points_revoked}P`],
        ].map(([k, v]) => <Card key={k}><div className="text-sm text-muted">{k}</div><div className="mt-1 text-2xl font-bold">{v}</div></Card>)}
      </div>
      <Card className="space-y-2">
        <h3 className="font-bold">앱 활동 대비 미션 참여</h3>
        <p className="text-sm text-muted">앱에서 활동한 사용자(찜·탐색·리뷰) {s.engagement.app_active_users}명 중 미션에 참여한 사용자 {s.engagement.mission_users}명 ({pct(s.engagement.mission_users, s.engagement.app_active_users)})</p>
      </Card>
      <Card className="space-y-3 overflow-x-auto">
        <h3 className="font-bold">미션별 참여·완료율</h3>
        <table className="w-full min-w-[34rem] text-left text-sm">
          <thead className="text-xs text-muted"><tr><th className="py-1">미션</th><th>유형</th><th>참여</th><th>완료</th><th>완료율</th><th>지급 포인트</th></tr></thead>
          <tbody>
            {s.missions.map((m) => (
              <tr key={m.id} className="border-t border-line"><td className="py-1.5 font-medium">{m.title}{m.version > 1 ? ` (v${m.version})` : ''}</td><td>{m.kind}</td><td>{m.participants}</td><td>{m.completions}</td><td>{pct(m.completions, m.participants)}</td><td>{m.points}P</td></tr>))}
          </tbody>
        </table>
        {s.missions.length === 0 && <p className="text-sm text-muted">운영 중인 미션이 없어요.</p>}
      </Card>
      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="space-y-3"><h3 className="font-bold">일별 추이</h3><Bars label="일별 참여" rows={s.daily.map((d) => ({ key: d.day.slice(5), a: d.participants, b: d.completions }))} /></Card>
        <Card className="space-y-3"><h3 className="font-bold">주별 추이</h3><Bars label="주별 참여" rows={s.weekly.map((w) => ({ key: w.week, a: w.participants, b: w.completions }))} /></Card>
      </div>
      <Card className="space-y-3">
        <h3 className="font-bold">대학교별 완료율</h3>
        <Bars label="대학교별" rows={s.by_university.map((u) => ({ key: u.university, a: u.participants, b: u.completions }))} />
      </Card>
    </div>
  )
}
