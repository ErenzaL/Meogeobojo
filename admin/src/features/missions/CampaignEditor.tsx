import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import PublishingToolbar from '@/components/PublishingToolbar'
import { Button, Card, ErrorState, Field, Input, Modal, Select, Skeleton, Textarea } from '@/components/ui'
import { cmsSaveDraft, cmsState, diffSnapshots, isConflict, showValue } from '@/lib/cms'
import { errorMessage } from '@/lib/utils'
import { MASCOTS, MASCOT_LABEL, type Campaign } from './model'
import { BannerPreview } from './previews'
import { campaignPayload, campaignToForm, seoulNextDayIso, seoulStartIso, validateCampaign, type CampaignForm } from './schema'

const TYPE = 'campaign' as const

/** Edits ONE campaign as a draft. Saving changes nothing in the app; the toolbar publishes or
 *  schedules it (server side), unpublishes it, and restores earlier versions. */
export default function CampaignEditor({ campaign, onClose, onChanged }: { campaign: Campaign; onClose: () => void; onChanged: () => void }) {
  const qc = useQueryClient()
  const [edited, setEdited] = useState<CampaignForm | null>(null)
  const [editBase, setEditBase] = useState<number | null>(null)
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [message, setMessage] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null)
  const [previewing, setPreviewing] = useState(false)
  const cms = useQuery({ queryKey: ['cms', TYPE, campaign.id], queryFn: () => cmsState(TYPE, campaign.id) })
  const state = cms.data
  const base = state ? (state.draft?.data ?? state.live) : null
  const serverRev = state?.draft?.revision ?? 0
  const form = edited ?? (base ? campaignToForm({ ...campaign, ...(base as object) } as Campaign) : null)
  const conflict = editBase !== null && editBase !== serverRev
  const refresh = async () => {
    await qc.invalidateQueries({ queryKey: ['cms', TYPE, campaign.id] }); await qc.invalidateQueries({ queryKey: ['cms-overview', TYPE] }); await qc.invalidateQueries({ queryKey: ['campaigns-admin'] }); onChanged()
  }
  const set = (patch: Partial<CampaignForm>) => { if (!form) return; setEdited({ ...form, ...patch }); setEditBase((b) => b ?? serverRev) }
  const save = useMutation({
    mutationFn: async () => {
      if (!form || !base) throw new Error('불러오는 중이에요')
      const e = validateCampaign(form, false); setErrors(e)
      if (Object.keys(e).length) throw new Error('입력값을 확인해 주세요')
      const { id: _id, slug: _s, ...p } = campaignPayload(form, campaign.id) as Record<string, unknown>; void _id; void _s
      const snap: Record<string, unknown> = { ...p, publish_state: 'published' }
      for (const k of ['starts_at', 'ends_at'] as const) { const old = base[k] as string | undefined; if (old && new Date(old).getTime() === new Date(snap[k] as string).getTime()) snap[k] = old }
      return cmsSaveDraft(TYPE, campaign.id, snap, editBase ?? serverRev)
    },
    onSuccess: async () => { setMessage({ tone: 'ok', text: '초안을 저장했어요. 앱에는 아직 반영되지 않았어요. 게시하면 보여요.' }); setEdited(null); setEditBase(null); await refresh() },
    onError: async (e) => { setMessage({ tone: 'bad', text: errorMessage(e) }); if (isConflict(e)) await refresh() },
  })
  if (cms.isLoading) return <Skeleton className="h-48 w-full" />
  if (cms.error) return <ErrorState error={cms.error} onRetry={() => void cms.refetch()} />
  if (!state || !form || !base) return null
  const changes = diffSnapshots(state.live, state.draft?.data ?? state.live)
  const color = /^#[0-9A-Fa-f]{6}$/.test(form.theme_color) ? form.theme_color : '#E85D04'
  return (
    <div className="space-y-3" aria-label="캠페인 편집">
      <div className="flex items-center justify-between"><h2 className="text-lg font-bold">{campaign.title} 편집</h2><Button variant="outline" onClick={onClose}>닫기</Button></div>
      <PublishingToolbar type={TYPE} id={campaign.id} state={state} loading={false} error={null} dirty={edited !== null} saving={save.isPending} message={message}
        onSaveDraft={() => save.mutate()} onPreview={() => setPreviewing(true)} onChanged={async () => { await refresh(); setMessage(null) }} onConflict={() => void refresh()} />
      {conflict && (
        <div role="alert" className="space-y-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">
          <p><b>다른 관리자가 이 캠페인의 초안을 먼저 저장했어요.</b></p>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" onClick={() => { setEdited(null); setEditBase(null) }}>최신 초안 불러오기 (내 수정 버리기)</Button>
            <Button size="sm" onClick={() => setEditBase(serverRev)}>내 수정으로 덮어쓰기</Button>
          </div>
        </div>)}
      <div className="grid gap-4 xl:grid-cols-[1fr_24rem]">
        <Card className="space-y-4">
          <Field label="이름" htmlFor="c_title" error={errors.title}><Input id="c_title" value={form.title} onChange={(e) => set({ title: e.target.value })} /></Field>
          <Field label="부제목" htmlFor="c_sub" error={errors.subtitle}><Input id="c_sub" value={form.subtitle} onChange={(e) => set({ subtitle: e.target.value })} /></Field>
          <Field label="설명" htmlFor="c_desc" error={errors.description}><Textarea id="c_desc" value={form.description} onChange={(e) => set({ description: e.target.value })} /></Field>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="시작일 (한국 시간)" htmlFor="c_start" error={errors.start_date}><Input id="c_start" type="date" value={form.start_date} onChange={(e) => set({ start_date: e.target.value })} /></Field>
            <Field label="종료일 (포함)" htmlFor="c_end" error={errors.end_date}><Input id="c_end" type="date" value={form.end_date} onChange={(e) => set({ end_date: e.target.value })} /></Field>
            <Field label="테마 색상" htmlFor="c_color" error={errors.theme_color}><Input id="c_color" value={form.theme_color} onChange={(e) => set({ theme_color: e.target.value })} /></Field>
            <Field label="배너 마스코트" htmlFor="c_mascot"><Select id="c_mascot" value={form.banner_mascot} onChange={(e) => set({ banner_mascot: e.target.value })}>{MASCOTS.map((m) => <option key={m} value={m}>{MASCOT_LABEL[m]}</option>)}</Select></Field>
          </div>
        </Card>
        <div className="space-y-2 self-start">
          <p className="text-sm font-semibold">앱 배너 미리보기 (초안 기준)</p>
          <BannerPreview title={form.title} subtitle={form.subtitle} color={color} mascot={form.banner_mascot}
            startIso={form.start_date ? seoulStartIso(form.start_date) : undefined} endIso={form.end_date ? seoulNextDayIso(form.end_date) : undefined} />
        </div>
      </div>
      <Modal open={previewing} title="미리보기" onClose={() => setPreviewing(false)}>
        <div className="space-y-4">
          <BannerPreview title={String(base.title ?? '')} subtitle={String(base.subtitle ?? '')} color={String(base.theme_color ?? '#E85D04')} mascot={String(base.banner_mascot ?? 'cheer')} startIso={String(base.starts_at ?? '')} endIso={String(base.ends_at ?? '')} />
          <div>
            <h3 className="mb-1 text-sm font-bold">지금 게시된 내용과 달라지는 항목 ({changes.length})</h3>
            {changes.length === 0 ? <p className="rounded-xl bg-page p-3 text-sm text-muted">게시된 내용과 같아요.</p> : (
              <ul aria-label="달라지는 항목" className="space-y-1.5 rounded-xl bg-page p-3 text-sm">
                {changes.map((c) => <li key={c.key}><b>{c.label}</b>: <span className="text-muted line-through">{showValue(c.from)}</span> → {showValue(c.to)}</li>)}
              </ul>)}
          </div>
        </div>
      </Modal>
    </div>
  )
}
