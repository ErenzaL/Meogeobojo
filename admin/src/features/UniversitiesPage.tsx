import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useMemo, useState } from 'react'
import PublishingToolbar from '@/components/PublishingToolbar'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Field, Input, Modal, PageHeader, Skeleton } from '@/components/ui'
import { cmsOverview, cmsSaveDraft, cmsSetVisibility, cmsState, diffSnapshots, formatKst, isConflict, showValue, type OverviewRow } from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'

const TYPE = 'university' as const
type Uni = { id: string; name_ko: string; name_en: string | null; city: string | null; address: string | null; latitude: number | null; longitude: number | null; is_active: boolean; search_radius_m: number }
type Form = { name_ko: string; name_en: string; address: string; latitude: string; longitude: string; radius: string }

/** Validates campus coordinates and radius (also enforced by CHECK constraints and the publish step). */
export function validateUniversity(v: { name_ko: string; latitude: string; longitude: string; radius: string }): Record<string, string> {
  const e: Record<string, string> = {}
  if (!v.name_ko.trim()) e.name_ko = '이름을 입력해 주세요'
  const lat = Number(v.latitude), lng = Number(v.longitude), r = Number(v.radius)
  if (v.latitude === '' || Number.isNaN(lat) || lat < -90 || lat > 90) e.latitude = '위도는 -90 ~ 90 사이여야 해요'
  if (v.longitude === '' || Number.isNaN(lng) || lng < -180 || lng > 180) e.longitude = '경도는 -180 ~ 180 사이여야 해요'
  if (!Number.isInteger(r) || r < 100 || r > 5000) e.radius = '검색 반경은 100 ~ 5000 m 사이여야 해요'
  return e
}
const formFrom = (s: Record<string, unknown>): Form => ({
  name_ko: String(s.name_ko ?? ''), name_en: String(s.name_en ?? ''), address: String(s.address ?? ''),
  latitude: s.latitude == null ? '' : String(s.latitude), longitude: s.longitude == null ? '' : String(s.longitude), radius: String(s.search_radius_m ?? 1500),
})

function Editor({ uni, onClose, onChanged }: { uni: Uni; onClose: () => void; onChanged: () => void }) {
  const qc = useQueryClient()
  const [edited, setEdited] = useState<Form | null>(null)
  const [editBase, setEditBase] = useState<number | null>(null)
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [message, setMessage] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null)
  const [previewing, setPreviewing] = useState(false)
  const cms = useQuery({ queryKey: ['cms', TYPE, uni.id], queryFn: () => cmsState(TYPE, uni.id) })
  const state = cms.data
  const base = state ? (state.draft?.data ?? state.live) : null
  const serverRev = state?.draft?.revision ?? 0
  const form = edited ?? (base ? formFrom(base) : null)
  const conflict = editBase !== null && editBase !== serverRev
  const refresh = async () => {
    await qc.invalidateQueries({ queryKey: ['cms', TYPE, uni.id] }); await qc.invalidateQueries({ queryKey: ['cms-overview', TYPE] }); await qc.invalidateQueries({ queryKey: ['universities-admin'] }); await qc.invalidateQueries({ queryKey: ['universities'] }); onChanged()
  }
  const set = (patch: Partial<Form>) => { if (!form) return; setEdited({ ...form, ...patch }); setEditBase((b) => b ?? serverRev) }
  const save = useMutation({
    mutationFn: async () => {
      if (!form || !base) throw new Error('불러오는 중이에요')
      const e = validateUniversity(form); setErrors(e)
      if (Object.keys(e).length) throw new Error('입력값을 확인해 주세요')
      return cmsSaveDraft(TYPE, uni.id, {
        ...base, name_ko: form.name_ko.trim(), name_en: form.name_en.trim() || null, address: form.address.trim() || null,
        latitude: Number(form.latitude), longitude: Number(form.longitude), search_radius_m: Number(form.radius), is_active: true,
      }, editBase ?? serverRev)
    },
    onSuccess: async () => { setMessage({ tone: 'ok', text: '초안을 저장했어요. 앱에는 아직 반영되지 않았어요. 게시하면 바뀌어요.' }); setEdited(null); setEditBase(null); await refresh() },
    onError: async (e) => { setMessage({ tone: 'bad', text: errorMessage(e) }); if (isConflict(e)) await refresh() },
  })
  if (cms.isLoading) return <Skeleton className="h-48 w-full" />
  if (cms.error) return <ErrorState error={cms.error} onRetry={() => void cms.refetch()} />
  if (!state || !form || !base) return null
  const changes = diffSnapshots(state.live, state.draft?.data ?? state.live)
  return (
    <div className="space-y-3 self-start" aria-label="대학교 편집">
      <div className="flex items-center justify-between"><h2 className="font-bold">{uni.name_ko} 편집</h2><Button size="sm" variant="outline" onClick={onClose}>닫기</Button></div>
      <PublishingToolbar type={TYPE} id={uni.id} state={state} loading={false} error={null} dirty={edited !== null} saving={save.isPending} message={message}
        onSaveDraft={() => save.mutate()} onPreview={() => setPreviewing(true)} onChanged={async () => { await refresh(); setMessage(null) }} onConflict={() => void refresh()} />
      {conflict && (
        <div role="alert" className="space-y-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">
          <p><b>다른 관리자가 이 대학교의 초안을 먼저 저장했어요.</b></p>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" onClick={() => { setEdited(null); setEditBase(null) }}>최신 초안 불러오기 (내 수정 버리기)</Button>
            <Button size="sm" onClick={() => setEditBase(serverRev)}>내 수정으로 덮어쓰기</Button>
          </div>
        </div>)}
      <Card className="space-y-3">
        <Field label="이름" htmlFor="u_name" error={errors.name_ko}><Input id="u_name" value={form.name_ko} onChange={(e) => set({ name_ko: e.target.value })} /></Field>
        <Field label="영문 이름" htmlFor="u_en"><Input id="u_en" value={form.name_en} onChange={(e) => set({ name_en: e.target.value })} /></Field>
        <Field label="주소" htmlFor="u_addr"><Input id="u_addr" value={form.address} onChange={(e) => set({ address: e.target.value })} /></Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="위도" htmlFor="u_lat" error={errors.latitude}><Input id="u_lat" value={form.latitude} onChange={(e) => set({ latitude: e.target.value })} /></Field>
          <Field label="경도" htmlFor="u_lng" error={errors.longitude}><Input id="u_lng" value={form.longitude} onChange={(e) => set({ longitude: e.target.value })} /></Field>
        </div>
        <Field label="검색 반경 (m)" htmlFor="u_r" error={errors.radius}><Input id="u_r" value={form.radius} onChange={(e) => set({ radius: e.target.value })} /></Field>
        <p className="text-xs text-muted">저장은 초안이에요. 게시하면 앱의 대학교 목록과 식당 검색 범위에 반영돼요.</p>
      </Card>
      <Modal open={previewing} title="미리보기" onClose={() => setPreviewing(false)}>
        <div className="space-y-4">
          <div aria-label="앱 대학교 미리보기" className="rounded-2xl border border-line bg-white p-4 shadow-sm">
            <div className="font-bold">{String(base.name_ko ?? '')}</div>
            <div className="text-xs text-muted">{String(base.address ?? '주소 없음')} · 반경 {String(base.search_radius_m)}m</div>
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

export default function UniversitiesPage() {
  const qc = useQueryClient()
  const list = useQuery({
    queryKey: ['universities-admin'],
    queryFn: async () => {
      const { data, error } = await supabase.from('universities').select('*').order('name_ko')
      if (error) throw error
      return data as Uni[]
    },
  })
  const overview = useQuery({ queryKey: ['cms-overview', TYPE], queryFn: () => cmsOverview(TYPE) })
  const ov = useMemo(() => new Map<string, OverviewRow>((overview.data ?? []).map((r) => [r.entity_id, r])), [overview.data])
  const [editingId, setEditingId] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [vis, setVis] = useState<{ u: Uni; to: 'published' | 'hidden' } | null>(null)
  const setVisibility = useMutation({
    mutationFn: async ({ u, to, reason }: { u: Uni; to: 'published' | 'hidden'; reason: string }) => { await cmsSetVisibility(TYPE, u.id, to, reason) },
    onSuccess: async (_d, { to }) => {
      setVis(null); setNotice(to === 'published' ? '앱에 표시하도록 게시했어요. 게시 이력에 남았어요.' : '앱에서 숨겼어요. 데이터는 지워지지 않아요. 게시 이력에 남았어요.')
      await qc.invalidateQueries({ queryKey: ['universities-admin'] }); await qc.invalidateQueries({ queryKey: ['universities'] }); await qc.invalidateQueries({ queryKey: ['cms'] }); await qc.invalidateQueries({ queryKey: ['cms-overview', TYPE] })
    },
    onError: (e) => { setVis(null); setNotice(errorMessage(e)) },
  })
  if (list.isLoading) return <Skeleton className="h-64 w-full" />
  if (list.error) return <ErrorState error={list.error} onRetry={() => void list.refetch()} />
  const editing = list.data?.find((u) => u.id === editingId) ?? null
  return (
    <>
      <PageHeader title="대학교" description="캠퍼스 좌표, 식당 검색 반경, 앱 표시 여부를 관리해요. 수정은 초안으로 저장되고, 게시하거나 예약해야 앱에 반영돼요. 식당 연결은 식당 편집 화면에서 해요." />
      {notice && <p role="status" className="mb-4 rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
      {list.data?.length === 0 && <EmptyState>등록된 대학교가 없어요.</EmptyState>}
      <div className="grid gap-4 lg:grid-cols-[1fr_26rem]">
        <div className="space-y-3">
          {list.data?.map((u) => {
            const o = ov.get(u.id)
            return (
              <Card key={u.id} className={`flex items-center justify-between gap-3 ${editingId === u.id ? 'ring-2 ring-brand-strong' : ''}`}>
                <div>
                  <div className="font-semibold">{u.name_ko} {!u.is_active && <Badge tone="amber">비활성</Badge>}</div>
                  <div className="text-xs text-muted">{u.city ?? '—'} · {u.latitude?.toFixed(5)}, {u.longitude?.toFixed(5)} · 반경 {u.search_radius_m}m</div>
                  {o && (o.has_draft || o.scheduled_at || o.failed_jobs > 0) && (
                    <div className="mt-1 flex flex-wrap gap-1">
                      {o.has_draft && <Badge tone="brand">게시되지 않은 수정 있음</Badge>}
                      {o.scheduled_at && <Badge tone="amber">예약 {formatKst(o.scheduled_at)}</Badge>}
                      {o.failed_jobs > 0 && <Badge tone="red">실패 {o.failed_jobs}</Badge>}
                    </div>)}
                </div>
                <div className="flex shrink-0 gap-2">
                  {u.is_active ? <Button size="sm" variant="outline" onClick={() => setVis({ u, to: 'hidden' })}>앱에서 숨기기</Button> : <Button size="sm" variant="soft" onClick={() => setVis({ u, to: 'published' })}>앱에 표시</Button>}
                  <Button size="sm" variant="outline" onClick={() => setEditingId(u.id)}>편집</Button>
                </div>
              </Card>)
          })}
        </div>
        {editing && <Editor key={editing.id} uni={editing} onClose={() => setEditingId(null)} onChanged={() => void qc.invalidateQueries({ queryKey: ['universities-admin'] })} />}
      </div>
      <ConfirmDialog open={!!vis} askReason busy={setVisibility.isPending} danger={vis?.to === 'hidden'}
        title={vis ? (vis.to === 'published' ? '앱에 표시할까요?' : '앱에서 숨길까요?') : ''}
        description={vis ? `${vis.u.name_ko} — ${vis.to === 'published' ? '학생이 이 대학교를 고를 수 있게 돼요.' : '새로 고르는 학생에게 보이지 않아요. 식당·메뉴 데이터는 지워지지 않아요.'}` : undefined}
        confirmLabel={vis?.to === 'published' ? '표시' : '숨기기'} onCancel={() => setVis(null)} onConfirm={(reason) => vis && setVisibility.mutate({ u: vis.u, to: vis.to, reason })} />
    </>
  )
}
