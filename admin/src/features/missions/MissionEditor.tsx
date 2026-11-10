import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import PublishingToolbar from '@/components/PublishingToolbar'
import { Badge, Button, Card, ErrorState, Modal, Skeleton } from '@/components/ui'
import { cmsSaveDraft, cmsState, diffSnapshots, isConflict, showValue } from '@/lib/cms'
import { errorMessage } from '@/lib/utils'
import MissionFields from './MissionFields'
import type { Campaign, Mission, University } from './model'
import { MissionPreview } from './previews'
import { missionFromSnapshot, missionSnapshot, missionToForm, validateMission, type MissionForm as Form } from './schema'

const TYPE = 'mission' as const
type Msg = { tone: 'ok' | 'bad'; text: string }

/** Edits ONE mission (its whole lineage) as a draft. Saving never changes what students see or
 *  what they earn: reward, goal and rule stay as published until the toolbar publishes or
 *  schedules the draft. A published change to a mission that already has progress becomes a new
 *  version in the database, so earned rewards are never rewritten or paid twice. */
export default function MissionEditor({ mission, campaigns, universities, onClose, onChanged }: {
  mission: Mission; campaigns: Campaign[]; universities: University[]; onClose: () => void; onChanged: () => void
}) {
  const qc = useQueryClient()
  const lineage = mission.lineage_id
  const [edited, setEdited] = useState<Form | null>(null)
  const [editBase, setEditBase] = useState<number | null>(null)
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [message, setMessage] = useState<Msg | null>(null)
  const [previewing, setPreviewing] = useState(false)

  const cms = useQuery({ queryKey: ['cms', TYPE, lineage], queryFn: () => cmsState(TYPE, lineage) })
  const state = cms.data
  const base = state ? (state.draft?.data ?? state.live) : null
  const serverRev = state?.draft?.revision ?? 0
  const identity = { id: mission.id, lineage_id: lineage, version: mission.version, slug: mission.slug, kind: mission.kind }
  const form = edited ?? (base ? missionToForm(missionFromSnapshot(base, identity)) : null)
  const dirty = edited !== null
  const conflict = editBase !== null && editBase !== serverRev

  const refresh = async () => {
    await qc.invalidateQueries({ queryKey: ['cms', TYPE, lineage] }); await qc.invalidateQueries({ queryKey: ['cms-overview', TYPE] }); await qc.invalidateQueries({ queryKey: ['missions-admin'] }); onChanged()
  }
  const set = (patch: Partial<Form>) => { if (!form) return; setEdited({ ...form, ...patch }); setEditBase((b) => b ?? serverRev) }

  const save = useMutation({
    mutationFn: async () => {
      if (!form || !base) throw new Error('불러오는 중이에요')
      const e = validateMission(form, false); setErrors(e)
      if (Object.keys(e).length) throw new Error('입력값을 확인해 주세요')
      return cmsSaveDraft(TYPE, lineage, missionSnapshot(form, base), editBase ?? serverRev)
    },
    onSuccess: async () => { setMessage({ tone: 'ok', text: '초안을 저장했어요. 앱의 미션·보상·진행에는 아직 영향이 없어요. 게시하면 반영돼요.' }); setEdited(null); setEditBase(null); await refresh() },
    onError: async (e) => { setMessage({ tone: 'bad', text: errorMessage(e) }); if (isConflict(e)) await refresh() },
  })

  if (cms.isLoading) return <Skeleton className="h-64 w-full" />
  if (cms.error) return <ErrorState error={cms.error} onRetry={() => void cms.refetch()} />
  if (!state || !form || !base) return null
  const changes = diffSnapshots(state.live, state.draft?.data ?? state.live)

  return (
    <div className="space-y-3" aria-label="미션 편집">
      <div className="flex items-center justify-between"><h2 className="text-lg font-bold">미션 편집 · {mission.title} <span className="text-sm font-normal text-muted">v{mission.version}</span></h2><Button variant="outline" onClick={onClose}>닫기</Button></div>
      <PublishingToolbar type={TYPE} id={lineage} state={state} loading={false} error={null} dirty={dirty} saving={save.isPending} message={message}
        onSaveDraft={() => save.mutate()} onPreview={() => setPreviewing(true)} onChanged={async () => { await refresh(); setMessage(null) }} onConflict={() => void refresh()} />
      {conflict && (
        <div role="alert" className="space-y-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">
          <p><b>다른 관리자가 이 미션의 초안을 먼저 저장했어요.</b></p>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" onClick={() => { setEdited(null); setEditBase(null) }}>최신 초안 불러오기 (내 수정 버리기)</Button>
            <Button size="sm" onClick={() => setEditBase(serverRev)}>내 수정으로 덮어쓰기</Button>
          </div>
        </div>)}
      <div className="grid gap-4 xl:grid-cols-[1fr_20rem]">
        <Card className="space-y-4">
          <MissionFields f={form} set={set} errors={errors} isNew={false} campaigns={campaigns} universities={universities} statusLabel="게시할 때의 상태" />
        </Card>
        <div className="space-y-3 self-start">
          <p className="text-sm font-semibold">앱 미리보기 (초안 기준)</p>
          <MissionPreview title={form.title} description={form.description} points={Number(form.reward_points) || 0} target={Number(form.target_count) || 1} badge={form.rule_type === 'missions_completed'} badgeMascot={form.badge_mascot} />
          {changes.length > 0 && <Badge tone="brand">게시되지 않은 변경 {changes.length}건</Badge>}
        </div>
      </div>
      <Modal open={previewing} title="미리보기" onClose={() => setPreviewing(false)}>
        <div className="space-y-4">
          <MissionPreview title={String(base.title ?? '')} description={String(base.description ?? '')} points={Number(base.reward_points) || 0} target={Number(base.target_count) || 1} badge={base.rule_type === 'missions_completed'} badgeMascot={String(base.reward_badge_mascot ?? '')} />
          <div>
            <h3 className="mb-1 text-sm font-bold">지금 게시된 내용과 달라지는 항목 ({changes.length})</h3>
            {changes.length === 0 ? <p className="rounded-xl bg-page p-3 text-sm text-muted">게시된 내용과 같아요.</p> : (
              <ul aria-label="달라지는 항목" className="space-y-1.5 rounded-xl bg-page p-3 text-sm">
                {changes.map((c) => <li key={c.key}><b>{c.label}</b>: <span className="text-muted line-through">{showValue(c.from)}</span> → {showValue(c.to)}</li>)}
              </ul>)}
            <p className="mt-2 text-xs text-muted">목표·보상·완료 규칙·대상·기간이 바뀌고 이미 진행한 학생이 있으면, 게시할 때 새 버전으로 저장돼요. 완료 기록과 이미 받은 포인트는 그대로예요.</p>
          </div>
        </div>
      </Modal>
    </div>
  )
}
