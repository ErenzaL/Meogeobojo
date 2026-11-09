import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowDown, ArrowUp, Star, Trash2 } from 'lucide-react'
import { useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Field, Input, PageHeader, Select, Skeleton, Textarea } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'

type Menu = { id: string; name_ko: string; description_ko: string | null; price_krw: number | null; available: boolean; representative: boolean; sort_order: number; image_url: string | null }

export const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp']
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024
/** Client-side pre-check; the storage bucket enforces the same limits. */
/** Unique storage path for a menu photo (kept outside the component: it reads the clock). */
export const menuImagePath = (menuId: string, mime: string) => `menus/${menuId}-${Date.now()}.${mime.split('/')[1]}`

export const validateImageFile = (f: { type: string; size: number }): string | null =>
  !ALLOWED_IMAGE_TYPES.includes(f.type) ? 'JPG, PNG, WEBP 이미지만 올릴 수 있어요' : f.size > MAX_IMAGE_BYTES ? '이미지는 5MB 이하여야 해요' : null

export default function MenusPage() {
  const qc = useQueryClient()
  const [restaurantId, setRestaurantId] = useState('')
  const [q, setQ] = useState('')
  const [notice, setNotice] = useState<string | null>(null)
  const [del, setDel] = useState<Menu | null>(null)
  const [draft, setDraft] = useState({ name: '', price: '', description: '' })

  const restaurants = useQuery({
    queryKey: ['restaurant-picker', q],
    queryFn: async () => {
      let query = supabase.from('restaurant_overrides').select('id,name_ko').order('name_ko').limit(50)
      if (q.trim()) query = query.ilike('name_ko', `%${q.trim().replace(/[%,()*\\]/g, ' ')}%`)
      const { data, error } = await query
      if (error) throw error
      return data as { id: string; name_ko: string }[]
    },
  })
  const menus = useQuery({
    queryKey: ['menus', restaurantId], enabled: !!restaurantId,
    queryFn: async () => {
      const { data, error } = await supabase.from('restaurant_menus').select('*').eq('restaurant_id', restaurantId).order('sort_order').order('created_at')
      if (error) throw error
      return data as Menu[]
    },
  })
  const refresh = () => qc.invalidateQueries({ queryKey: ['menus', restaurantId] })
  const run = useMutation({
    mutationFn: async (fn: () => PromiseLike<{ error: unknown }>) => { const { error } = await fn(); if (error) throw error },
    onSuccess: async () => { setNotice(null); await refresh() },
    onError: (e) => setNotice(errorMessage(e)),
  })

  const add = () => {
    const price = draft.price.trim() === '' ? null : Number(draft.price)
    if (!draft.name.trim()) return setNotice('메뉴 이름을 입력해 주세요')
    if (price != null && (!Number.isInteger(price) || price < 0)) return setNotice('가격은 0 이상의 정수여야 해요')
    run.mutate(async () => {
      const next = (menus.data?.at(-1)?.sort_order ?? 0) + 1
      const r = await supabase.from('restaurant_menus').insert({ restaurant_id: restaurantId, name_ko: draft.name.trim(), description_ko: draft.description.trim() || null, price_krw: price, source: 'admin', sort_order: next })
      if (!r.error) setDraft({ name: '', price: '', description: '' })
      return r
    })
  }
  const move = (m: Menu, dir: -1 | 1) => {
    const list = menus.data ?? []; const i = list.findIndex((x) => x.id === m.id); const o = list[i + dir]
    if (!o) return
    run.mutate(async () => {
      const a = await supabase.from('restaurant_menus').update({ sort_order: o.sort_order }).eq('id', m.id)
      if (a.error) return a
      return supabase.from('restaurant_menus').update({ sort_order: m.sort_order }).eq('id', o.id)
    })
  }
  const upload = async (m: Menu, file: File) => {
    const bad = validateImageFile(file); if (bad) return setNotice(bad)
    const path = menuImagePath(m.id, file.type)
    const up = await supabase.storage.from('restaurant-images').upload(path, file, { contentType: file.type })
    if (up.error) return setNotice(errorMessage(up.error))
    const url = supabase.storage.from('restaurant-images').getPublicUrl(path).data.publicUrl
    run.mutate(() => supabase.from('restaurant_menus').update({ image_url: url }).eq('id', m.id))
  }

  return (
    <>
      <PageHeader title="메뉴·가격" description="식당별 메뉴와 가격(원)을 관리해요. 변경 내용은 앱 식당 상세에 반영돼요." />
      {notice && <p role="alert" className="mb-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{notice}</p>}
      <Card className="mb-5 grid gap-3 sm:grid-cols-2">
        <Field label="식당 검색" htmlFor="rq"><Input id="rq" value={q} onChange={(e) => setQ(e.target.value)} placeholder="이름으로 검색" /></Field>
        <Field label="식당 선택" htmlFor="rs">
          <Select id="rs" value={restaurantId} onChange={(e) => setRestaurantId(e.target.value)}>
            <option value="">선택하세요</option>{restaurants.data?.map((r) => <option key={r.id} value={r.id}>{r.name_ko}</option>)}
          </Select>
        </Field>
      </Card>
      {!restaurantId && <EmptyState>식당을 선택하면 메뉴가 보여요.</EmptyState>}
      {restaurantId && menus.isLoading && <Skeleton className="h-40 w-full" />}
      {restaurantId && menus.error && <ErrorState error={menus.error} onRetry={() => void menus.refetch()} />}
      {restaurantId && menus.data && (
        <div className="space-y-3">
          {menus.data.length === 0 && <EmptyState>등록된 메뉴가 없어요.</EmptyState>}
          {menus.data.map((m, i) => (
            <Card key={m.id} className="flex flex-wrap items-center gap-3">
              {m.image_url && <img src={m.image_url} alt="" className="size-14 rounded-lg object-cover" />}
              <div className="min-w-0 flex-1">
                <div className="font-semibold">{m.name_ko} {m.representative && <Badge tone="brand">대표</Badge>} {!m.available && <Badge tone="amber">품절</Badge>}</div>
                <div className="text-sm text-muted">{m.price_krw != null ? `${m.price_krw.toLocaleString('ko-KR')}원` : '가격 미정'}{m.description_ko ? ` · ${m.description_ko}` : ''}</div>
              </div>
              <label className="cursor-pointer text-xs font-semibold text-brand-strong">사진
                <input type="file" accept={ALLOWED_IMAGE_TYPES.join(',')} hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(m, f); e.target.value = '' }} /></label>
              <Button size="icon" variant="ghost" aria-label="대표 메뉴 전환" onClick={() => run.mutate(() => supabase.from('restaurant_menus').update({ representative: !m.representative }).eq('id', m.id))}><Star className={`size-4 ${m.representative ? 'fill-brand text-brand-strong' : ''}`} /></Button>
              <Button size="sm" variant="outline" onClick={() => run.mutate(() => supabase.from('restaurant_menus').update({ available: !m.available }).eq('id', m.id))}>{m.available ? '품절 처리' : '판매 재개'}</Button>
              <Button size="icon" variant="ghost" aria-label="위로" disabled={i === 0} onClick={() => move(m, -1)}><ArrowUp className="size-4" /></Button>
              <Button size="icon" variant="ghost" aria-label="아래로" disabled={i === menus.data.length - 1} onClick={() => move(m, 1)}><ArrowDown className="size-4" /></Button>
              <Button size="icon" variant="ghost" aria-label="삭제" onClick={() => setDel(m)}><Trash2 className="size-4 text-red-600" /></Button>
            </Card>))}
          <Card className="grid gap-3 sm:grid-cols-[1fr_9rem]">
            <Field label="새 메뉴 이름" htmlFor="mn"><Input id="mn" value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} /></Field>
            <Field label="가격 (원)" htmlFor="mp"><Input id="mp" inputMode="numeric" value={draft.price} onChange={(e) => setDraft({ ...draft, price: e.target.value })} /></Field>
            <div className="sm:col-span-2"><Field label="설명" htmlFor="md"><Textarea id="md" className="min-h-16" value={draft.description} onChange={(e) => setDraft({ ...draft, description: e.target.value })} /></Field></div>
            <div><Button onClick={add} disabled={run.isPending}>메뉴 추가</Button></div>
          </Card>
        </div>)}
      <ConfirmDialog open={!!del} danger title="메뉴를 삭제할까요?" description={del?.name_ko} confirmLabel="삭제"
        onCancel={() => setDel(null)} onConfirm={() => { const m = del!; setDel(null); run.mutate(() => supabase.from('restaurant_menus').delete().eq('id', m.id)) }} />
    </>
  )
}
