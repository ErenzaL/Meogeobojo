import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useMemo, useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Field, Input, Select, Skeleton, Textarea } from '@/components/ui'
import { cmsOverview, cmsSetVisibility, formatKst, type OverviewRow } from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import CampaignEditor from './CampaignEditor'
import { useCampaigns } from './MissionList'
import { MASCOTS, MASCOT_LABEL, STATE_LABEL, type Campaign, type Mission } from './model'
import { BannerPreview } from './previews'
import { campaignPayload, campaignState, campaignToForm, emptyCampaignForm, seoulNextDayIso, seoulStartIso, validateCampaign, type CampaignForm } from './schema'

const TONE = { draft: 'neutral', scheduled: 'amber', active: 'green', ended: 'red' } as const

export default function CampaignList() {
  const qc = useQueryClient()
  const campaigns = useCampaigns()
  const missions = useQuery({ queryKey: ['missions-admin'], queryFn: async () => {
    const { data, error } = await supabase.from('missions').select('id,campaign_id,status')
    if (error) throw error
    return data as Pick<Mission, 'id' | 'campaign_id' | 'status'>[]
  } })
  const [editing, setEditing] = useState<Campaign | 'new' | null>(null)
  const [f, setF] = useState<CampaignForm>(emptyCampaignForm())
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [notice, setNotice] = useState<string | null>(null)
  const [act, setAct] = useState<{ c: Campaign; to: 'draft' | 'published' } | null>(null)

  const open = (c: Campaign | 'new') => { setEditing(c); setErrors({}); setF(c === 'new' ? emptyCampaignForm() : campaignToForm(c)) }
  const set = (patch: Partial<CampaignForm>) => setF((p) => ({ ...p, ...patch }))
  const save = useMutation({
    mutationFn: async () => {
      const e = validateCampaign(f, editing === 'new'); setErrors(e)
      if (Object.keys(e).length) throw new Error('입력값을 확인해 주세요')
      const { error } = await supabase.rpc('admin_save_campaign', { p: campaignPayload(f) })
      if (error) throw error
    },
    onSuccess: async () => { setEditing(null); setNotice('초안으로 만들었어요. 앱에는 아직 보이지 않아요. 편집해서 게시하거나 예약해 주세요.'); await qc.invalidateQueries({ queryKey: ['campaigns-admin'] }) },
    onError: (e) => setNotice(errorMessage(e)),
  })
  const overview = useQuery({ queryKey: ['cms-overview', 'campaign'], queryFn: () => cmsOverview('campaign') })
  const ov = useMemo(() => new Map<string, OverviewRow>((overview.data ?? []).map((r) => [r.entity_id, r])), [overview.data])
  const publish = useMutation({
    // publishing / taking back is a versioned, audited publication (history + rollback)
    mutationFn: async ({ c, to, reason }: { c: Campaign; to: 'draft' | 'published'; reason: string }) => { await cmsSetVisibility('campaign', c.id, to === 'published' ? 'published' : 'hidden', reason) },
    onSuccess: async () => { setAct(null); setNotice('처리했어요. 게시 이력에 사유가 남았어요.'); await qc.invalidateQueries({ queryKey: ['campaigns-admin'] }); await qc.invalidateQueries({ queryKey: ['cms'] }); await qc.invalidateQueries({ queryKey: ['cms-overview', 'campaign'] }) },
    onError: (e) => { setAct(null); setNotice(errorMessage(e)) },
  })

  if (campaigns.isLoading) return <Skeleton className="h-48 w-full" />
  if (campaigns.error) return <ErrorState error={campaigns.error} onRetry={() => void campaigns.refetch()} />

  if (editing && editing !== 'new') return <CampaignEditor campaign={editing} onClose={() => setEditing(null)} onChanged={() => void qc.invalidateQueries({ queryKey: ['campaigns-admin'] })} />
  if (editing) {
    const isNew = true
    return (
      <div className="grid gap-4 xl:grid-cols-[1fr_24rem]">
        <Card className="space-y-4">
          <h2 className="text-lg font-bold">캠페인 만들기</h2>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="식별자 (slug)" htmlFor="c_slug" error={errors.slug} hint="예: 2026-12. 만든 뒤에는 바꿀 수 없어요"><Input id="c_slug" value={f.slug} disabled={!isNew} onChange={(e) => set({ slug: e.target.value })} /></Field>
            <Field label="이름" htmlFor="c_title" error={errors.title}><Input id="c_title" value={f.title} onChange={(e) => set({ title: e.target.value })} /></Field>
          </div>
          <Field label="부제목" htmlFor="c_sub" error={errors.subtitle}><Input id="c_sub" value={f.subtitle} onChange={(e) => set({ subtitle: e.target.value })} /></Field>
          <Field label="설명" htmlFor="c_desc" error={errors.description}><Textarea id="c_desc" value={f.description} onChange={(e) => set({ description: e.target.value })} /></Field>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="시작일 (한국 시간)" htmlFor="c_start" error={errors.start_date}><Input id="c_start" type="date" value={f.start_date} onChange={(e) => set({ start_date: e.target.value })} /></Field>
            <Field label="종료일 (포함)" htmlFor="c_end" error={errors.end_date}><Input id="c_end" type="date" value={f.end_date} onChange={(e) => set({ end_date: e.target.value })} /></Field>
            <Field label="테마 색상" htmlFor="c_color" error={errors.theme_color}><Input id="c_color" value={f.theme_color} onChange={(e) => set({ theme_color: e.target.value })} /></Field>
            <Field label="배너 마스코트" htmlFor="c_mascot"><Select id="c_mascot" value={f.banner_mascot} onChange={(e) => set({ banner_mascot: e.target.value })}>{MASCOTS.map((m) => <option key={m} value={m}>{MASCOT_LABEL[m]}</option>)}</Select></Field>
          </div>
          <p className="text-xs text-muted">마스코트는 앱에 이미 있는 이미지 중에서만 고를 수 있어요. 새 캐릭터는 만들지 않아요.</p>
          <div className="flex gap-2"><Button disabled={save.isPending} onClick={() => save.mutate()}>초안으로 만들기</Button><Button variant="outline" onClick={() => setEditing(null)}>취소</Button></div>
        </Card>
        <div className="space-y-2 self-start">
          <p className="text-sm font-semibold">앱 배너 미리보기</p>
          <BannerPreview title={f.title} subtitle={f.subtitle} color={/^#[0-9A-Fa-f]{6}$/.test(f.theme_color) ? f.theme_color : '#E85D04'} mascot={f.banner_mascot}
            startIso={f.start_date ? seoulStartIso(f.start_date) : undefined} endIso={f.end_date ? seoulNextDayIso(f.end_date) : undefined} />
        </div>
      </div>)
  }

  return (
    <>
      {notice && <p role="status" className="mb-4 rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
      <div className="mb-4 flex justify-end"><Button onClick={() => open('new')}>캠페인 추가</Button></div>
      {campaigns.data?.length === 0 && <EmptyState>캠페인이 없어요.</EmptyState>}
      <div className="space-y-3">
        {campaigns.data?.map((c) => {
          const st = campaignState(c)
          const n = missions.data?.filter((m) => m.campaign_id === c.id && m.status !== 'archived').length ?? 0
          return (
            <Card key={c.id} className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <div className="flex items-center gap-2 font-semibold">{c.title}<Badge tone={TONE[st]}>{STATE_LABEL[st]}</Badge></div>
                {ov.get(c.id) && (ov.get(c.id)!.has_draft || ov.get(c.id)!.scheduled_at || ov.get(c.id)!.failed_jobs > 0) && (
                  <div className="my-1 flex flex-wrap gap-1">
                    {ov.get(c.id)!.has_draft && <Badge tone="brand">게시되지 않은 수정 있음</Badge>}
                    {ov.get(c.id)!.scheduled_at && <Badge tone="amber">예약 {formatKst(ov.get(c.id)!.scheduled_at)}</Badge>}
                    {ov.get(c.id)!.failed_jobs > 0 && <Badge tone="red">실패 {ov.get(c.id)!.failed_jobs}</Badge>}
                  </div>)}
                <div className="text-xs text-muted">{c.slug} · 미션 {n}개 · {c.starts_at.slice(0, 10)} ~ {c.ends_at.slice(0, 10)} (UTC)</div>
              </div>
              <div className="flex gap-2">
                <Button size="sm" variant="outline" onClick={() => open(c)}>편집</Button>
                {c.publish_state === 'draft'
                  ? <Button size="sm" variant="soft" onClick={() => setAct({ c, to: 'published' })}>게시</Button>
                  : <Button size="sm" variant="outline" onClick={() => setAct({ c, to: 'draft' })}>게시 취소</Button>}
              </div>
            </Card>)
        })}
      </div>
      <ConfirmDialog open={!!act} askReason busy={publish.isPending} title={act ? `"${act.c.title}" ${act.to === 'published' ? '게시' : '게시 취소'}` : ''}
        description={act?.to === 'published' ? '게시하면 시작일부터 앱에 나타나요 (시작 전에는 "예약됨").' : '게시를 취소하면 앱에서 사라져요. 사용자의 진행과 포인트는 지워지지 않아요.'}
        onCancel={() => setAct(null)} onConfirm={(reason) => act && publish.mutate({ c: act.c, to: act.to, reason })} />
    </>
  )
}
