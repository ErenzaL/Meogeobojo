import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Trash2 } from 'lucide-react'
import { useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Field, Input, PageHeader, Select, Skeleton, Textarea } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'

type Item = { id: string; kind: 'announcement' | 'banner' | 'featured'; title: string; body: string | null; link_url: string | null; kakao_place_id: string | null; active: boolean; sort_order: number }
const KIND = { announcement: '공지', banner: '배너', featured: '추천 식당' } as const

export default function ContentPage() {
  const qc = useQueryClient()
  const [draft, setDraft] = useState({ kind: 'announcement' as Item['kind'], title: '', body: '', link_url: '', kakao_place_id: '' })
  const [notice, setNotice] = useState<string | null>(null)
  const [del, setDel] = useState<Item | null>(null)
  const list = useQuery({ queryKey: ['content'], queryFn: async () => {
    const { data, error } = await supabase.from('app_content').select('*').order('kind').order('sort_order')
    if (error) throw error
    return data as Item[]
  } })
  const run = useMutation({
    mutationFn: async (fn: () => PromiseLike<{ error: unknown }>) => { const { error } = await fn(); if (error) throw error },
    onSuccess: async () => { setNotice(null); await qc.invalidateQueries({ queryKey: ['content'] }) },
    onError: (e) => setNotice(errorMessage(e)),
  })
  const add = () => {
    if (!draft.title.trim()) return setNotice('제목을 입력해 주세요')
    if (draft.link_url && !/^https:\/\//.test(draft.link_url)) return setNotice('링크는 https:// 로 시작해야 해요')
    if (draft.kind === 'featured' && !draft.kakao_place_id.trim()) return setNotice('추천 식당은 카카오 장소 ID가 필요해요')
    run.mutate(async () => {
      const r = await supabase.from('app_content').insert({ kind: draft.kind, title: draft.title.trim(), body: draft.body.trim() || null, link_url: draft.link_url.trim() || null, kakao_place_id: draft.kakao_place_id.trim() || null, active: false })
      if (!r.error) setDraft({ ...draft, title: '', body: '', link_url: '', kakao_place_id: '' })
      return r
    })
  }
  return (
    <>
      <PageHeader title="앱 콘텐츠" description="공지, 배너, 추천 식당을 관리해요. 새 항목은 비활성으로 만들어지고, 켜면 앱에 보여요." />
      {notice && <p role="alert" className="mb-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{notice}</p>}
      <div className="grid gap-5 lg:grid-cols-[1fr_22rem]">
        <div className="space-y-3">
          {list.isLoading && <Skeleton className="h-24 w-full" />}
          {list.error && <ErrorState error={list.error} onRetry={() => void list.refetch()} />}
          {list.data?.length === 0 && <EmptyState>등록된 콘텐츠가 없어요.</EmptyState>}
          {list.data?.map((c) => (
            <Card key={c.id} className="flex items-start justify-between gap-3">
              <div>
                <div className="font-semibold">{c.title} <Badge tone="brand">{KIND[c.kind]}</Badge> <Badge tone={c.active ? 'green' : 'neutral'}>{c.active ? '노출 중' : '꺼짐'}</Badge></div>
                {c.body && <p className="text-sm text-muted">{c.body}</p>}
                {c.kakao_place_id && <p className="text-xs text-muted">Kakao {c.kakao_place_id}</p>}
              </div>
              <div className="flex gap-2">
                <Button size="sm" variant="outline" onClick={() => run.mutate(() => supabase.from('app_content').update({ active: !c.active }).eq('id', c.id))}>{c.active ? '끄기' : '켜기'}</Button>
                <Button size="icon" variant="ghost" aria-label="삭제" onClick={() => setDel(c)}><Trash2 className="size-4 text-red-600" /></Button>
              </div>
            </Card>))}
        </div>
        <Card className="space-y-3 self-start">
          <h2 className="font-bold">새 항목</h2>
          <Field label="종류" htmlFor="ck"><Select id="ck" value={draft.kind} onChange={(e) => setDraft({ ...draft, kind: e.target.value as Item['kind'] })}>{Object.entries(KIND).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</Select></Field>
          <Field label="제목" htmlFor="ct"><Input id="ct" value={draft.title} onChange={(e) => setDraft({ ...draft, title: e.target.value })} /></Field>
          <Field label="내용" htmlFor="cb"><Textarea id="cb" value={draft.body} onChange={(e) => setDraft({ ...draft, body: e.target.value })} /></Field>
          <Field label="링크 (https)" htmlFor="cl"><Input id="cl" value={draft.link_url} onChange={(e) => setDraft({ ...draft, link_url: e.target.value })} /></Field>
          {draft.kind === 'featured' && <Field label="카카오 장소 ID" htmlFor="cp"><Input id="cp" value={draft.kakao_place_id} onChange={(e) => setDraft({ ...draft, kakao_place_id: e.target.value })} /></Field>}
          <Button disabled={run.isPending} onClick={add}>추가</Button>
        </Card>
      </div>
      <ConfirmDialog open={!!del} danger title="삭제할까요?" description={del?.title} confirmLabel="삭제" onCancel={() => setDel(null)}
        onConfirm={() => { const c = del!; setDel(null); run.mutate(() => supabase.from('app_content').delete().eq('id', c.id)) }} />
    </>
  )
}
