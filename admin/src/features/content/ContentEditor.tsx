import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import PublishingToolbar from '@/components/PublishingToolbar'
import { Badge, Button, Card, ErrorState, Field, Input, Modal, Skeleton, Textarea } from '@/components/ui'
import { cmsSaveDraft, cmsState, diffSnapshots, isConflict, showValue } from '@/lib/cms'
import { errorMessage } from '@/lib/utils'
import { formFromSnapshot, KIND, snapshotFromForm, validateContent, type ContentForm, type Item } from './content'

const TYPE = 'app_content' as const
type Msg = { tone: 'ok' | 'bad'; text: string }

/** Edits ONE announcement / banner / featured restaurant as a draft. Saving never changes what
 *  students see; the toolbar publishes, schedules (server side), unpublishes and restores. */
export default function ContentEditor({ item, onClose, onChanged }: { item: Item; onClose: () => void; onChanged: () => void }) {
  const qc = useQueryClient()
  const [edited, setEdited] = useState<ContentForm | null>(null)
  const [editBase, setEditBase] = useState<number | null>(null)
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [message, setMessage] = useState<Msg | null>(null)
  const [previewing, setPreviewing] = useState(false)
  const cms = useQuery({ queryKey: ['cms', TYPE, item.id], queryFn: () => cmsState(TYPE, item.id) })
  const state = cms.data
  const base = state ? (state.draft?.data ?? state.live) : null
  const serverRev = state?.draft?.revision ?? 0
  const form = edited ?? (base ? formFromSnapshot(base) : null)
  const dirty = edited !== null
  const conflict = editBase !== null && editBase !== serverRev
  const refresh = async () => {
    await qc.invalidateQueries({ queryKey: ['cms', TYPE, item.id] }); await qc.invalidateQueries({ queryKey: ['cms-overview', TYPE] }); await qc.invalidateQueries({ queryKey: ['content'] }); onChanged()
  }
  const set = (patch: Partial<ContentForm>) => { if (!form) return; setEdited({ ...form, ...patch }); setEditBase((b) => b ?? serverRev) }
  const save = useMutation({
    mutationFn: async () => {
      if (!form || !base) throw new Error('불러오는 중이에요')
      const e = validateContent(form, item.kind); setErrors(e)
      if (Object.keys(e).length) throw new Error('입력값을 확인해 주세요')
      return cmsSaveDraft(TYPE, item.id, snapshotFromForm(form, base), editBase ?? serverRev)
    },
    onSuccess: async () => { setMessage({ tone: 'ok', text: '초안을 저장했어요. 앱에는 아직 반영되지 않았어요. 게시하면 보여요.' }); setEdited(null); setEditBase(null); await refresh() },
    onError: async (e) => { setMessage({ tone: 'bad', text: errorMessage(e) }); if (isConflict(e)) await refresh() },
  })
  if (cms.isLoading) return <Skeleton className="h-48 w-full" />
  if (cms.error) return <ErrorState error={cms.error} onRetry={() => void cms.refetch()} />
  if (!state || !form || !base) return null
  const changes = diffSnapshots(state.live, state.draft?.data ?? state.live)
  const pv = formFromSnapshot(base)
  return (
    <div className="space-y-3" aria-label="콘텐츠 편집">
      <div className="flex items-center justify-between"><h2 className="font-bold">{KIND[item.kind]} 편집</h2><Button size="sm" variant="outline" onClick={onClose}>닫기</Button></div>
      <PublishingToolbar type={TYPE} id={item.id} state={state} loading={false} error={null} dirty={dirty} saving={save.isPending} message={message}
        onSaveDraft={() => save.mutate()} onPreview={() => setPreviewing(true)} onChanged={async () => { await refresh(); setMessage(null) }} onConflict={() => void refresh()} />
      {conflict && (
        <div role="alert" className="space-y-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">
          <p><b>다른 관리자가 이 항목의 초안을 먼저 저장했어요.</b></p>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" onClick={() => { setEdited(null); setEditBase(null) }}>최신 초안 불러오기 (내 수정 버리기)</Button>
            <Button size="sm" onClick={() => setEditBase(serverRev)}>내 수정으로 덮어쓰기</Button>
          </div>
        </div>)}
      <Card className="space-y-3">
        <Field label="제목" htmlFor="ce_t" error={errors.title}><Input id="ce_t" value={form.title} onChange={(e) => set({ title: e.target.value })} /></Field>
        <Field label="내용" htmlFor="ce_b" error={errors.body}><Textarea id="ce_b" value={form.body} onChange={(e) => set({ body: e.target.value })} /></Field>
        <Field label="링크 (https)" htmlFor="ce_l" error={errors.link}><Input id="ce_l" value={form.link} onChange={(e) => set({ link: e.target.value })} /></Field>
        <Field label="이미지 주소 (https)" htmlFor="ce_i" error={errors.image}><Input id="ce_i" value={form.image} onChange={(e) => set({ image: e.target.value })} /></Field>
        {item.kind === 'featured' && <Field label="카카오 장소 ID" htmlFor="ce_p" error={errors.place}><Input id="ce_p" value={form.place} onChange={(e) => set({ place: e.target.value })} /></Field>}
        <Field label="정렬 순서" htmlFor="ce_s" error={errors.sort}><Input id="ce_s" inputMode="numeric" value={form.sort} onChange={(e) => set({ sort: e.target.value })} /></Field>
        <fieldset className="space-y-2 rounded-xl border border-line p-3">
          <legend className="px-1 text-sm font-semibold">노출 기간 (한국 시간, 선택)</legend>
          <p className="text-xs text-muted">게시한 뒤 이 기간 안에서만 앱에 보여요. 예약 게시와는 별개예요.</p>
          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="노출 시작 날짜" htmlFor="ce_sd"><Input id="ce_sd" type="date" value={form.sDate} onChange={(e) => set({ sDate: e.target.value })} /></Field>
            <Field label="노출 시작 시간" htmlFor="ce_st"><Input id="ce_st" type="time" value={form.sTime} onChange={(e) => set({ sTime: e.target.value })} /></Field>
            <Field label="노출 종료 날짜" htmlFor="ce_ed" error={errors.eDate}><Input id="ce_ed" type="date" value={form.eDate} onChange={(e) => set({ eDate: e.target.value })} /></Field>
            <Field label="노출 종료 시간" htmlFor="ce_et"><Input id="ce_et" type="time" value={form.eTime} onChange={(e) => set({ eTime: e.target.value })} /></Field>
          </div>
        </fieldset>
      </Card>
      <Modal open={previewing} title="미리보기" onClose={() => setPreviewing(false)}>
        <div className="space-y-4">
          <div aria-label="앱 콘텐츠 미리보기" className="space-y-2 rounded-2xl border border-line bg-white p-4 shadow-sm">
            <Badge tone="brand">{KIND[item.kind]}</Badge>
            {base.image_url ? <img src={String(base.image_url)} alt="콘텐츠 이미지" className="aspect-[16/8] w-full rounded-xl object-cover" /> : null}
            <div className="font-bold">{String(base.title ?? '')}</div>
            {base.body ? <p className="text-sm text-muted">{String(base.body)}</p> : null}
            <p className="text-xs text-muted">노출 기간: {pv.sDate ? `${pv.sDate} ${pv.sTime}` : '제한 없음'} ~ {pv.eDate ? `${pv.eDate} ${pv.eTime}` : '제한 없음'} (KST)</p>
          </div>
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
