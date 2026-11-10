import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Select, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import MissionForm from './MissionForm'
import { KINDS, STATUS_LABEL, type Campaign, type Mission, type MissionStatus, type University } from './model'
import { missionPhase } from './schema'

const PHASE_TONE = { draft: 'neutral', paused: 'amber', archived: 'neutral', scheduled: 'amber', active: 'green', ended: 'red' } as const
const PHASE_LABEL = { ...STATUS_LABEL, scheduled: '예약됨', active: '진행 중', ended: '종료' } as const

export const useCampaigns = () => useQuery({
  queryKey: ['campaigns-admin'],
  queryFn: async () => {
    const { data, error } = await supabase.from('monthly_campaigns').select('*').order('starts_at', { ascending: false })
    if (error) throw error
    return data as Campaign[]
  },
})

export default function MissionList() {
  const qc = useQueryClient()
  const campaigns = useCampaigns()
  const unis = useQuery({ queryKey: ['universities'], queryFn: async () => {
    const { data, error } = await supabase.from('universities').select('id,name_ko').order('name_ko')
    if (error) throw error
    return data as University[]
  } })
  const list = useQuery({ queryKey: ['missions-admin'], queryFn: async () => {
    const { data, error } = await supabase.from('missions').select('*').order('kind').order('sort_order')
    if (error) throw error
    return data as Mission[]
  } })
  const [editing, setEditing] = useState<Mission | 'new' | null>(null)
  const [filter, setFilter] = useState({ kind: '', campaign: '', status: '' })
  const [notice, setNotice] = useState<string | null>(null)
  const [act, setAct] = useState<{ m: Mission; to: MissionStatus } | null>(null)

  const setStatus = useMutation({
    mutationFn: async ({ m, to, reason }: { m: Mission; to: MissionStatus; reason: string }) => {
      const { error } = await supabase.rpc('admin_set_mission_status', { p_id: m.id, p_status: to, p_reason: reason })
      if (error) throw error
    },
    onSuccess: async () => { setAct(null); setNotice('상태를 바꿨어요. 활동 기록에 사유가 남았어요.'); await qc.invalidateQueries({ queryKey: ['missions-admin'] }) },
    onError: (e) => { setAct(null); setNotice(errorMessage(e)) },
  })
  const duplicate = useMutation({
    mutationFn: async (m: Mission) => { const { error } = await supabase.rpc('admin_duplicate_mission', { p_id: m.id, p_campaign: null }); if (error) throw error },
    onSuccess: async () => { setNotice('초안으로 복제했어요. 뱃지 키는 복사되지 않아요.'); await qc.invalidateQueries({ queryKey: ['missions-admin'] }) },
    onError: (e) => setNotice(errorMessage(e)),
  })

  if (list.isLoading || campaigns.isLoading) return <Skeleton className="h-48 w-full" />
  if (list.error) return <ErrorState error={list.error} onRetry={() => void list.refetch()} />
  const camps = campaigns.data ?? []
  if (editing) {
    return <MissionForm mission={editing === 'new' ? null : editing} campaigns={camps} universities={unis.data ?? []}
      onDone={(m) => { setEditing(null); if (m) setNotice(m) }} />
  }
  const shown = (list.data ?? []).filter((m) => (!filter.kind || m.kind === filter.kind) && (!filter.campaign || m.campaign_id === filter.campaign) && (!filter.status || m.status === filter.status))
  return (
    <>
      {notice && <p role="status" className="mb-4 rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
      <div className="mb-4 flex flex-wrap items-center gap-2">
        <Select aria-label="유형" className="w-36" value={filter.kind} onChange={(e) => setFilter({ ...filter, kind: e.target.value })}><option value="">모든 유형</option>{KINDS.map((k) => <option key={k.value} value={k.value}>{k.label}</option>)}</Select>
        <Select aria-label="캠페인" className="w-44" value={filter.campaign} onChange={(e) => setFilter({ ...filter, campaign: e.target.value })}><option value="">모든 캠페인</option>{camps.map((c) => <option key={c.id} value={c.id}>{c.title}</option>)}</Select>
        <Select aria-label="상태" className="w-36" value={filter.status} onChange={(e) => setFilter({ ...filter, status: e.target.value })}><option value="">모든 상태</option>{(Object.keys(STATUS_LABEL) as MissionStatus[]).map((s) => <option key={s} value={s}>{STATUS_LABEL[s]}</option>)}</Select>
        <Button className="ml-auto" onClick={() => setEditing('new')}>미션 추가</Button>
      </div>
      {shown.length === 0 && <EmptyState>조건에 맞는 미션이 없어요.</EmptyState>}
      <div className="space-y-3">
        {shown.map((m) => {
          const camp = camps.find((c) => c.id === m.campaign_id)
          const phase = missionPhase(m, camp)
          return (
            <Card key={m.id} className="flex flex-wrap items-center justify-between gap-3">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2 font-semibold">{m.title}<Badge tone={PHASE_TONE[phase]}>{PHASE_LABEL[phase]}</Badge>{m.version > 1 && <Badge tone="brand">v{m.version}</Badge>}</div>
                <div className="text-xs text-muted">{KINDS.find((k) => k.value === m.kind)?.label} · {camp?.title ?? '캠페인 없음'} · 목표 {m.target_count} · {m.reward_badge_key ? `뱃지 ${m.reward_badge_key}` : `${m.reward_points}P`} · {m.slug}</div>
              </div>
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="outline" disabled={m.status === 'archived'} onClick={() => setEditing(m)}>편집</Button>
                <Button size="sm" variant="outline" onClick={() => duplicate.mutate(m)}>복제</Button>
                {m.status !== 'active' && m.status !== 'archived' && <Button size="sm" variant="soft" onClick={() => setAct({ m, to: 'active' })}>활성화</Button>}
                {m.status === 'active' && <Button size="sm" variant="outline" onClick={() => setAct({ m, to: 'paused' })}>일시중지</Button>}
                {m.status !== 'archived' && <Button size="sm" variant="outline" onClick={() => setAct({ m, to: 'archived' })}>보관</Button>}
              </div>
            </Card>)
        })}
      </div>
      <ConfirmDialog open={!!act} askReason busy={setStatus.isPending} danger={act?.to === 'archived'}
        title={act ? `"${act.m.title}" → ${STATUS_LABEL[act.to]}` : ''}
        description={act?.to === 'archived' ? '보관한 미션은 앱에서 사라지고 다시 편집할 수 없어요. 완료 기록과 포인트는 남아요.' : '사유는 활동 기록에 남아요.'}
        onCancel={() => setAct(null)} onConfirm={(reason) => act && setStatus.mutate({ m: act.m, to: act.to, reason })} />
    </>
  )
}
