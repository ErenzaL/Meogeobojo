import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Archive, ArrowDown, ArrowUp, ImageOff, Pencil, RotateCcw, Star, ThumbsUp, Trash2 } from 'lucide-react'
import { useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Field, Input, PageHeader, Select, Skeleton, Textarea } from '@/components/ui'
import { ALLOWED_IMAGE_TYPES, BUCKET, imagePath, prepareImage, storagePathFromUrl } from '@/lib/images'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'

export { ALLOWED_IMAGE_TYPES, MAX_IMAGE_BYTES, validateImageFile } from '@/lib/images'

export const MENU_CATEGORIES = ['식사', '면류', '분식', '안주', '사이드', '음료', '디저트', '기타']

type Menu = {
  id: string; name_ko: string; description_ko: string | null; price_krw: number | null; available: boolean; representative: boolean
  recommended: boolean; category: string | null; price_verified_on: string | null; status: 'active' | 'archived'; sort_order: number; image_url: string | null
}
type Draft = { name: string; price: string; description: string; category: string; verified: string }
const emptyDraft: Draft = { name: '', price: '', description: '', category: '', verified: '' }

/** Pure form check: unknown prices stay unknown (empty = null), never 0. */
export function validateMenu(d: Draft): { error: string | null; price: number | null } {
  if (!d.name.trim()) return { error: '메뉴 이름을 입력해 주세요', price: null }
  const price = d.price.trim() === '' ? null : Number(d.price.replace(/[,\s]/g, ''))
  if (price != null && (!Number.isInteger(price) || price < 0)) return { error: '가격은 0 이상의 정수여야 해요', price: null }
  if (d.verified && !/^\d{4}-\d{2}-\d{2}$/.test(d.verified)) return { error: '가격 확인일 형식이 올바르지 않아요', price: null }
  if (d.verified && price == null) return { error: '가격이 없으면 확인일을 적을 수 없어요', price: null }
  return { error: null, price }
}

export default function MenusPage() {
  const qc = useQueryClient()
  const [restaurantId, setRestaurantId] = useState('')
  const [q, setQ] = useState('')
  const [notice, setNotice] = useState<string | null>(null)
  const [del, setDel] = useState<Menu | null>(null)
  const [editing, setEditing] = useState<Menu | null>(null)
  const [showArchived, setShowArchived] = useState(false)
  const [draft, setDraft] = useState<Draft>(emptyDraft)

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

  const all = menus.data ?? []
  const visible = all.filter((m) => showArchived || m.status === 'active')
  const archivedCount = all.filter((m) => m.status === 'archived').length

  const submit = () => {
    const { error, price } = validateMenu(draft)
    if (error) return setNotice(error)
    const row = {
      name_ko: draft.name.trim(), description_ko: draft.description.trim() || null, price_krw: price,
      category: draft.category || null, price_verified_on: price == null ? null : draft.verified || null,
    }
    run.mutate(async () => {
      if (editing) {
        const r = await supabase.from('restaurant_menus').update(row).eq('id', editing.id)
        if (!r.error) { setEditing(null); setDraft(emptyDraft) }
        return r
      }
      const next = (all.at(-1)?.sort_order ?? 0) + 1
      const r = await supabase.from('restaurant_menus').insert({ ...row, restaurant_id: restaurantId, source: 'admin', sort_order: next })
      if (!r.error) setDraft(emptyDraft)
      return r
    })
  }
  const startEdit = (m: Menu) => {
    setEditing(m)
    setDraft({ name: m.name_ko, price: m.price_krw == null ? '' : String(m.price_krw), description: m.description_ko ?? '', category: m.category ?? '', verified: m.price_verified_on ?? '' })
  }
  const move = (m: Menu, dir: -1 | 1) => {
    const list = visible; const i = list.findIndex((x) => x.id === m.id); const o = list[i + dir]
    if (!o) return
    run.mutate(async () => {
      const a = await supabase.from('restaurant_menus').update({ sort_order: o.sort_order }).eq('id', m.id)
      if (a.error) return a
      return supabase.from('restaurant_menus').update({ sort_order: m.sort_order }).eq('id', o.id)
    })
  }
  const removeFile = async (url: string | null) => {
    const path = storagePathFromUrl(url)
    if (path) await supabase.storage.from(BUCKET).remove([path])
  }
  const upload = async (m: Menu, file: File) => {
    try {
      setNotice(null)
      const img = await prepareImage(file)
      const path = imagePath(`menus/${restaurantId}`, img.type)
      const up = await supabase.storage.from(BUCKET).upload(path, img.blob, { contentType: img.type })
      if (up.error) return setNotice(errorMessage(up.error))
      const url = supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl
      const old = m.image_url
      const r = await supabase.from('restaurant_menus').update({ image_url: url }).eq('id', m.id)
      if (r.error) { await supabase.storage.from(BUCKET).remove([path]); return setNotice(errorMessage(r.error)) }
      await removeFile(old) // the replaced file would be an orphan
      await refresh()
    } catch (e) { setNotice(errorMessage(e)) }
  }
  const clearPhoto = (m: Menu) => run.mutate(async () => {
    const r = await supabase.from('restaurant_menus').update({ image_url: null }).eq('id', m.id)
    if (!r.error) await removeFile(m.image_url)
    return r
  })
  const set = <K extends keyof Draft>(k: K, v: Draft[K]) => setDraft((d) => ({ ...d, [k]: v }))
  const patch = (m: Menu, values: Partial<Menu>) => run.mutate(() => supabase.from('restaurant_menus').update(values).eq('id', m.id))

  return (
    <>
      <PageHeader title="메뉴·가격" description="식당별 메뉴와 가격(원)을 관리해요. 가격을 모르면 비워 두세요. 변경 내용은 앱 식당 상세에 바로 반영돼요." />
      {notice && <p role="alert" className="mb-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{notice}</p>}
      <Card className="mb-5 grid gap-3 sm:grid-cols-2">
        <Field label="식당 검색" htmlFor="rq"><Input id="rq" value={q} onChange={(e) => setQ(e.target.value)} placeholder="이름으로 검색" /></Field>
        <Field label="식당 선택" htmlFor="rs">
          <Select id="rs" value={restaurantId} onChange={(e) => { setRestaurantId(e.target.value); setEditing(null); setDraft(emptyDraft) }}>
            <option value="">선택하세요</option>{restaurants.data?.map((r) => <option key={r.id} value={r.id}>{r.name_ko}</option>)}
          </Select>
        </Field>
      </Card>
      {!restaurantId && <EmptyState>식당을 선택하면 메뉴가 보여요.</EmptyState>}
      {restaurantId && menus.isLoading && <Skeleton className="h-40 w-full" />}
      {restaurantId && menus.error && <ErrorState error={menus.error} onRetry={() => void menus.refetch()} />}
      {restaurantId && menus.data && (
        <div className="grid gap-5 lg:grid-cols-[1fr_22rem]">
          <div className="space-y-3">
            {archivedCount > 0 && (
              <label className="flex items-center gap-2 text-sm text-muted"><input type="checkbox" checked={showArchived} onChange={(e) => setShowArchived(e.target.checked)} />보관된 메뉴 {archivedCount}개 보기</label>
            )}
            {visible.length === 0 && <EmptyState>등록된 메뉴가 없어요.</EmptyState>}
            {visible.map((m, i) => (
              <Card key={m.id} className={`flex flex-wrap items-center gap-3 ${m.status === 'archived' ? 'opacity-60' : ''}`}>
                {m.image_url
                  ? <img src={m.image_url} alt={`${m.name_ko} 사진`} className="size-16 rounded-lg object-cover" />
                  : <span className="grid size-16 place-items-center rounded-lg bg-page text-muted" title="사진 없음"><ImageOff className="size-5" /></span>}
                <div className="min-w-0 flex-1">
                  <div className="font-semibold">{m.name_ko} {m.representative && <Badge tone="brand">대표</Badge>} {m.recommended && <Badge tone="brand">추천</Badge>} {!m.available && <Badge tone="amber">품절</Badge>} {m.status === 'archived' && <Badge tone="amber">보관됨</Badge>}</div>
                  <div className="text-sm text-muted">
                    {m.price_krw != null ? `${m.price_krw.toLocaleString('ko-KR')}원` : '가격 미정'}
                    {m.category ? ` · ${m.category}` : ''}{m.description_ko ? ` · ${m.description_ko}` : ''}
                  </div>
                  <div className="text-xs text-muted">{m.price_krw != null ? (m.price_verified_on ? `가격 확인 ${m.price_verified_on}` : '가격 확인일 없음') : ''}</div>
                </div>
                <label className="cursor-pointer text-xs font-semibold text-brand-strong">{m.image_url ? '사진 교체' : '사진 추가'}
                  <input type="file" accept={ALLOWED_IMAGE_TYPES.join(',')} hidden aria-label={`${m.name_ko} 사진 올리기`} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(m, f); e.target.value = '' }} /></label>
                {m.image_url && <Button size="sm" variant="ghost" onClick={() => clearPhoto(m)}>사진 삭제</Button>}
                <Button size="icon" variant="ghost" aria-label="수정" onClick={() => startEdit(m)}><Pencil className="size-4" /></Button>
                <Button size="icon" variant="ghost" aria-label="대표 메뉴 전환" onClick={() => patch(m, { representative: !m.representative })}><Star className={`size-4 ${m.representative ? 'fill-brand text-brand-strong' : ''}`} /></Button>
                <Button size="icon" variant="ghost" aria-label="추천 메뉴 전환" onClick={() => patch(m, { recommended: !m.recommended })}><ThumbsUp className={`size-4 ${m.recommended ? 'fill-brand text-brand-strong' : ''}`} /></Button>
                <Button size="sm" variant="outline" onClick={() => patch(m, { available: !m.available })}>{m.available ? '품절 처리' : '판매 재개'}</Button>
                <Button size="icon" variant="ghost" aria-label="위로" disabled={i === 0} onClick={() => move(m, -1)}><ArrowUp className="size-4" /></Button>
                <Button size="icon" variant="ghost" aria-label="아래로" disabled={i === visible.length - 1} onClick={() => move(m, 1)}><ArrowDown className="size-4" /></Button>
                {m.status === 'active'
                  ? <Button size="icon" variant="ghost" aria-label="보관" onClick={() => patch(m, { status: 'archived' })}><Archive className="size-4" /></Button>
                  : <Button size="icon" variant="ghost" aria-label="복원" onClick={() => patch(m, { status: 'active' })}><RotateCcw className="size-4" /></Button>}
                <Button size="icon" variant="ghost" aria-label="삭제" onClick={() => setDel(m)}><Trash2 className="size-4 text-red-600" /></Button>
              </Card>))}
          </div>
          <Card className="space-y-3 self-start">
            <h2 className="font-bold">{editing ? `메뉴 수정 · ${editing.name_ko}` : '새 메뉴'}</h2>
            <Field label="메뉴 이름" htmlFor="mn"><Input id="mn" value={draft.name} onChange={(e) => set('name', e.target.value)} placeholder="제육 정식" /></Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="가격 (원)" htmlFor="mp" hint="모르면 비워 두세요"><Input id="mp" inputMode="numeric" value={draft.price} onChange={(e) => set('price', e.target.value)} /></Field>
              <Field label="분류" htmlFor="mc"><Select id="mc" value={draft.category} onChange={(e) => set('category', e.target.value)}><option value="">선택 안 함</option>{MENU_CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}</Select></Field>
            </div>
            <Field label="가격 확인일" htmlFor="mv" hint="가격을 직접 확인한 날"><Input id="mv" type="date" value={draft.verified} onChange={(e) => set('verified', e.target.value)} /></Field>
            <Field label="설명" htmlFor="md"><Textarea id="md" className="min-h-16" value={draft.description} onChange={(e) => set('description', e.target.value)} /></Field>
            <div className="flex gap-2">
              <Button onClick={submit} disabled={run.isPending}>{editing ? '저장' : '메뉴 추가'}</Button>
              {editing && <Button variant="outline" onClick={() => { setEditing(null); setDraft(emptyDraft) }}>취소</Button>}
            </div>
            {!editing && <p className="text-xs text-muted">메뉴를 추가한 뒤 카드의 &lsquo;사진 추가&rsquo;로 사진을 올려요.</p>}
          </Card>
        </div>)}
      <ConfirmDialog open={!!del} danger title="메뉴를 삭제할까요?" description={del ? `${del.name_ko} — 삭제 대신 '보관'하면 나중에 복원할 수 있어요.` : undefined} confirmLabel="삭제"
        onCancel={() => setDel(null)} onConfirm={() => { const m = del!; setDel(null); run.mutate(async () => { const r = await supabase.from('restaurant_menus').delete().eq('id', m.id); if (!r.error) await removeFile(m.image_url); return r }) }} />
    </>
  )
}
