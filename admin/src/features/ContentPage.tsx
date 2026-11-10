import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Pencil, Trash2 } from 'lucide-react'
import { useMemo, useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Field, Input, PageHeader, Select, Skeleton, Textarea } from '@/components/ui'
import { cmsOverview, cmsSetVisibility, formatKst, type OverviewRow } from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import ContentEditor from './content/ContentEditor'
import { KIND, type Item, type Kind } from './content/content'

const TYPE = 'app_content' as const

/** Announcements, banners and featured restaurants. A new item is created switched OFF; editing
 *  saves a draft; the publishing toolbar makes it live now or at a scheduled Seoul time. */
export default function ContentPage() {
  const qc = useQueryClient()
  const [draft, setDraft] = useState({ kind: 'announcement' as Kind, title: '', body: '', link_url: '', kakao_place_id: '' })
  const [notice, setNotice] = useState<string | null>(null)
  const [del, setDel] = useState<Item | null>(null)
  const [vis, setVis] = useState<{ c: Item; to: 'published' | 'hidden' } | null>(null)
  const [editingId, setEditingId] = useState<string | null>(null)
  const list = useQuery({ queryKey: ['content'], queryFn: async () => {
    const { data, error } = await supabase.from('app_content').select('*').order('kind').order('sort_order')
    if (error) throw error
    return data as Item[]
  } })
  const overview = useQuery({ queryKey: ['cms-overview', TYPE], queryFn: () => cmsOverview(TYPE) })
  const ov = useMemo(() => new Map<string, OverviewRow>((overview.data ?? []).map((r) => [r.entity_id, r])), [overview.data])
  const refresh = async () => { await qc.invalidateQueries({ queryKey: ['content'] }); await qc.invalidateQueries({ queryKey: ['cms-overview', TYPE] }) }

  const create = useMutation({
    mutationFn: async () => {
      if (!draft.title.trim()) throw new Error('제목을 입력해 주세요')
      if (draft.link_url && !/^https:\/\//.test(draft.link_url)) throw new Error('링크는 https:// 로 시작해야 해요')
      if (draft.kind === 'featured' && !draft.kakao_place_id.trim()) throw new Error('추천 식당은 카카오 장소 ID가 필요해요')
      const { data, error } = await supabase.from('app_content').insert({ kind: draft.kind, title: draft.title.trim(), body: draft.body.trim() || null, link_url: draft.link_url.trim() || null, kakao_place_id: draft.kakao_place_id.trim() || null, active: false }).select('id').single()
      if (error) throw error
      return (data as { id: string }).id
    },
    onSuccess: async (id) => { setNotice('꺼진 상태로 만들었어요. 앱에는 보이지 않아요. 편집해서 게시해 주세요.'); setDraft({ ...draft, title: '', body: '', link_url: '', kakao_place_id: '' }); setEditingId(id); await refresh() },
    onError: (e) => setNotice(errorMessage(e)),
  })
  const setVisibility = useMutation({
    mutationFn: async ({ c, to, reason }: { c: Item; to: 'published' | 'hidden'; reason: string }) => { await cmsSetVisibility(TYPE, c.id, to, reason) },
    onSuccess: async (_d, { to }) => { setVis(null); setNotice(to === 'published' ? '게시했어요. 앱에서 새로고침하면 보여요. 게시 이력에 남았어요.' : '내렸어요. 내용은 지워지지 않았어요. 게시 이력에 남았어요.'); await refresh(); await qc.invalidateQueries({ queryKey: ['cms'] }) },
    onError: (e) => { setVis(null); setNotice(errorMessage(e)) },
  })
  const remove = useMutation({
    mutationFn: async (c: Item) => { const { error } = await supabase.from('app_content').delete().eq('id', c.id); if (error) throw error },
    onSuccess: async () => { setDel(null); await refresh() },
    onError: (e) => { setDel(null); setNotice(errorMessage(e)) },
  })
  const editing = list.data?.find((c) => c.id === editingId) ?? null

  return (
    <>
      <PageHeader title="앱 콘텐츠" description="공지, 배너, 추천 식당을 관리해요. 새 항목은 꺼진 상태로 만들어지고, 수정은 초안으로 저장돼요. 게시하거나 예약해야 앱에 보여요." />
      {notice && <p role="alert" className="mb-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{notice}</p>}
      <div className="grid gap-5 lg:grid-cols-[1fr_26rem]">
        <div className="space-y-3">
          {list.isLoading && <Skeleton className="h-24 w-full" />}
          {list.error && <ErrorState error={list.error} onRetry={() => void list.refetch()} />}
          {list.data?.length === 0 && <EmptyState>등록된 콘텐츠가 없어요.</EmptyState>}
          {list.data?.map((c) => {
            const o = ov.get(c.id)
            return (
              <Card key={c.id} className={`flex items-start justify-between gap-3 ${editingId === c.id ? 'ring-2 ring-brand-strong' : ''}`}>
                <div>
                  <div className="font-semibold">{c.title} <Badge tone="brand">{KIND[c.kind]}</Badge> <Badge tone={c.active ? 'green' : 'neutral'}>{c.active ? '노출 중' : '꺼짐'}</Badge></div>
                  {c.body && <p className="text-sm text-muted">{c.body}</p>}
                  {c.kakao_place_id && <p className="text-xs text-muted">Kakao {c.kakao_place_id}</p>}
                  {o && (o.has_draft || o.scheduled_at || o.failed_jobs > 0) && (
                    <div className="mt-1 flex flex-wrap gap-1">
                      {o.has_draft && <Badge tone="brand">게시되지 않은 수정 있음</Badge>}
                      {o.scheduled_at && <Badge tone="amber">예약 {formatKst(o.scheduled_at)}</Badge>}
                      {o.failed_jobs > 0 && <Badge tone="red">실패 {o.failed_jobs}</Badge>}
                    </div>)}
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  {!c.active && <Button size="sm" variant="soft" onClick={() => setVis({ c, to: 'published' })}>바로 게시</Button>}
                  {c.active && <Button size="sm" variant="outline" onClick={() => setVis({ c, to: 'hidden' })}>내리기</Button>}
                  <Button size="icon" variant="ghost" aria-label="수정" onClick={() => setEditingId(c.id)}><Pencil className="size-4" /></Button>
                  <Button size="icon" variant="ghost" aria-label="삭제" disabled={c.active} title={c.active ? '노출 중인 항목은 먼저 내려야 삭제할 수 있어요' : undefined} onClick={() => setDel(c)}><Trash2 className="size-4 text-red-600" /></Button>
                </div>
              </Card>)
          })}
        </div>
        {editing ? (
          <div className="self-start"><ContentEditor key={editing.id} item={editing} onClose={() => setEditingId(null)} onChanged={() => void refresh()} /></div>
        ) : (
          <Card className="space-y-3 self-start">
            <h2 className="font-bold">새 항목 (꺼진 상태로 추가)</h2>
            <Field label="종류" htmlFor="ck"><Select id="ck" value={draft.kind} onChange={(e) => setDraft({ ...draft, kind: e.target.value as Kind })}>{Object.entries(KIND).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</Select></Field>
            <Field label="제목" htmlFor="ct"><Input id="ct" value={draft.title} onChange={(e) => setDraft({ ...draft, title: e.target.value })} /></Field>
            <Field label="내용" htmlFor="cb"><Textarea id="cb" value={draft.body} onChange={(e) => setDraft({ ...draft, body: e.target.value })} /></Field>
            <Field label="링크 (https)" htmlFor="cl"><Input id="cl" value={draft.link_url} onChange={(e) => setDraft({ ...draft, link_url: e.target.value })} /></Field>
            {draft.kind === 'featured' && <Field label="카카오 장소 ID" htmlFor="cp"><Input id="cp" value={draft.kakao_place_id} onChange={(e) => setDraft({ ...draft, kakao_place_id: e.target.value })} /></Field>}
            <Button disabled={create.isPending} onClick={() => create.mutate()}>추가</Button>
          </Card>)}
      </div>
      <ConfirmDialog open={!!vis} askReason busy={setVisibility.isPending} danger={vis?.to === 'hidden'}
        title={vis ? (vis.to === 'published' ? '지금 게시할까요?' : '앱에서 내릴까요?') : ''}
        description={vis ? `${vis.c.title} — ${vis.to === 'published' ? '저장된 내용 그대로 앱에 보여요 (노출 기간이 있으면 그 안에서만). 게시 이력에 남아요.' : '앱에서 숨겨져요. 내용은 지워지지 않아요.'}` : undefined}
        confirmLabel={vis?.to === 'published' ? '게시' : '내리기'} onCancel={() => setVis(null)} onConfirm={(reason) => vis && setVisibility.mutate({ c: vis.c, to: vis.to, reason })} />
      <ConfirmDialog open={!!del} danger title="삭제할까요?" description={del ? `${del.title} — 노출 중이 아닌 항목만 삭제할 수 있어요.` : undefined} confirmLabel="삭제" busy={remove.isPending}
        onCancel={() => setDel(null)} onConfirm={() => del && remove.mutate(del)} />
    </>
  )
}
