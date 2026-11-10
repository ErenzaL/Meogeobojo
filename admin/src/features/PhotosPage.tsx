import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Archive, ArrowDown, ArrowUp, ImagePlus, ImageOff, RotateCcw, Star, Trash2 } from 'lucide-react'
import { useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Field, Input, PageHeader, Select, Skeleton } from '@/components/ui'
import { ALLOWED_IMAGE_TYPES, BUCKET, imagePath, prepareImage } from '@/lib/images'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'

export type Photo = {
  id: string; restaurant_id: string; kind: 'cover' | 'gallery'; storage_path: string; url: string; caption: string | null
  sort_order: number; status: 'published' | 'archived'; source: 'admin' | 'student'; credit: string | null
}

/** What the student app shows for a restaurant, in order: the live cover, then live gallery photos. */
export const shownInApp = (photos: Photo[]) => ({
  cover: photos.find((p) => p.kind === 'cover' && p.status === 'published') ?? null,
  gallery: photos.filter((p) => p.kind === 'gallery' && p.status === 'published').sort((a, b) => a.sort_order - b.sort_order),
})

export default function PhotosPage() {
  const qc = useQueryClient()
  const [restaurantId, setRestaurantId] = useState('')
  const [q, setQ] = useState('')
  const [notice, setNotice] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null)
  const [del, setDel] = useState<Photo | null>(null)
  const [busy, setBusy] = useState(false)
  const [credit, setCredit] = useState('')

  const restaurants = useQuery({
    queryKey: ['restaurant-picker', q],
    queryFn: async () => {
      let query = supabase.from('restaurant_overrides').select('id,name_ko,visibility').order('name_ko').limit(50)
      if (q.trim()) query = query.ilike('name_ko', `%${q.trim().replace(/[%,()*\\]/g, ' ')}%`)
      const { data, error } = await query
      if (error) throw error
      return data as { id: string; name_ko: string; visibility: string }[]
    },
  })
  const photos = useQuery({
    queryKey: ['photos', restaurantId], enabled: !!restaurantId,
    queryFn: async () => {
      const { data, error } = await supabase.from('restaurant_photos').select('*').eq('restaurant_id', restaurantId).order('sort_order').order('created_at')
      if (error) throw error
      return data as Photo[]
    },
  })
  const refresh = () => qc.invalidateQueries({ queryKey: ['photos', restaurantId] })
  const all = photos.data ?? []
  const live = shownInApp(all)
  const archived = all.filter((p) => p.status === 'archived')
  const selected = restaurants.data?.find((r) => r.id === restaurantId)

  /** Run one step; any failure becomes a visible message instead of a half-done state. */
  const guard = async (fn: () => Promise<string | void>) => {
    setBusy(true); setNotice(null)
    try { const ok = await fn(); if (ok) setNotice({ tone: 'ok', text: ok }) }
    catch (e) { setNotice({ tone: 'bad', text: errorMessage(e) }) }
    finally { setBusy(false); await refresh() }
  }
  const must = <T extends { error: unknown }>(r: T) => { if (r.error) throw r.error; return r }
  const removeFiles = async (paths: string[]) => { if (paths.length) await supabase.storage.from(BUCKET).remove(paths) }

  /** Upload one file and return the row values (the row is inserted by the caller). */
  const store = async (file: File) => {
    const img = await prepareImage(file)
    const path = imagePath(`restaurants/${restaurantId}`, img.type)
    must(await supabase.storage.from(BUCKET).upload(path, img.blob, { contentType: img.type }))
    return { path, img, url: supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl }
  }
  const rowFor = (kind: Photo['kind'], s: Awaited<ReturnType<typeof store>>, order: number) => ({
    restaurant_id: restaurantId, kind, storage_path: s.path, url: s.url, sort_order: order,
    width: s.img.width, height: s.img.height, bytes: s.img.bytes, source: credit.trim() ? 'student' : 'admin', credit: credit.trim() || null,
  })

  const addGallery = (files: FileList) => guard(async () => {
    let order = (all.filter((p) => p.kind === 'gallery').at(-1)?.sort_order ?? 0)
    let ok = 0; const failed: string[] = []
    for (const f of Array.from(files)) {
      try {
        const s = await store(f)
        const r = await supabase.from('restaurant_photos').insert(rowFor('gallery', s, ++order))
        if (r.error) { await removeFiles([s.path]); throw r.error }
        ok++
      } catch (e) { failed.push(`${f.name}: ${errorMessage(e)}`) }
    }
    if (failed.length) throw new Error(`${ok}장 올렸고 ${failed.length}장은 실패했어요. ${failed.join(' / ')}`)
    return `${ok}장을 올렸어요.`
  })

  const replaceCover = (file: File) => guard(async () => {
    const s = await store(file)
    const old = live.cover
    try {
      if (old) must(await supabase.from('restaurant_photos').update({ status: 'archived' }).eq('id', old.id))
      must(await supabase.from('restaurant_photos').insert(rowFor('cover', s, 0)))
    } catch (e) {
      if (old) await supabase.from('restaurant_photos').update({ status: 'published' }).eq('id', old.id)
      await removeFiles([s.path])
      throw e
    }
    if (old) { must(await supabase.from('restaurant_photos').delete().eq('id', old.id)); await removeFiles([old.storage_path]) }
    return '대표 사진을 바꿨어요. 앱에 바로 반영돼요.'
  })

  const makeCover = (p: Photo) => guard(async () => {
    const old = live.cover
    if (old) must(await supabase.from('restaurant_photos').update({ status: 'archived' }).eq('id', old.id))
    const r = await supabase.from('restaurant_photos').update({ kind: 'cover', status: 'published', sort_order: 0 }).eq('id', p.id)
    if (r.error) { if (old) await supabase.from('restaurant_photos').update({ status: 'published' }).eq('id', old.id); throw r.error }
    return '대표 사진으로 지정했어요. 이전 대표 사진은 보관돼요.'
  })
  const patch = (p: Photo, values: Partial<Photo>, msg?: string) => guard(async () => { must(await supabase.from('restaurant_photos').update(values).eq('id', p.id)); return msg })
  const move = (p: Photo, dir: -1 | 1) => {
    const i = live.gallery.findIndex((x) => x.id === p.id); const o = live.gallery[i + dir]
    if (!o) return
    return guard(async () => {
      must(await supabase.from('restaurant_photos').update({ sort_order: o.sort_order }).eq('id', p.id))
      must(await supabase.from('restaurant_photos').update({ sort_order: p.sort_order }).eq('id', o.id))
    })
  }
  const remove = useMutation({
    mutationFn: async (p: Photo) => {
      must(await supabase.from('restaurant_photos').delete().eq('id', p.id))
      await removeFiles([p.storage_path]) // no orphaned file
    },
    onSuccess: async () => { setDel(null); setNotice({ tone: 'ok', text: '사진을 삭제했어요.' }); await refresh() },
    onError: (e) => { setDel(null); setNotice({ tone: 'bad', text: errorMessage(e) }) },
  })

  const Tile = ({ p, i }: { p: Photo; i: number }) => (
    <Card className="space-y-2 p-3">
      <img src={p.url} alt={p.caption || '식당 사진'} className="aspect-[4/3] w-full rounded-lg object-cover" loading="lazy" />
      <Input aria-label="사진 설명" defaultValue={p.caption ?? ''} placeholder="사진 설명 (선택)" maxLength={200}
        onBlur={(e) => { const v = e.target.value.trim(); if (v !== (p.caption ?? '')) void patch(p, { caption: v || null }, '설명을 저장했어요.') }} />
      {p.credit && <div className="text-xs text-muted">출처: {p.credit}</div>}
      <div className="flex flex-wrap items-center gap-1">
        {p.status === 'published' && p.kind === 'gallery' && <>
          <Button size="icon" variant="ghost" aria-label="앞으로" disabled={busy || i === 0} onClick={() => void move(p, -1)}><ArrowUp className="size-4" /></Button>
          <Button size="icon" variant="ghost" aria-label="뒤로" disabled={busy || i === live.gallery.length - 1} onClick={() => void move(p, 1)}><ArrowDown className="size-4" /></Button>
          <Button size="sm" variant="outline" disabled={busy} onClick={() => void makeCover(p)}><Star className="size-4" />대표로</Button>
        </>}
        {p.status === 'published'
          ? <Button size="icon" variant="ghost" aria-label="보관" disabled={busy} onClick={() => void patch(p, { status: 'archived' }, '보관했어요. 앱에서는 숨겨져요.')}><Archive className="size-4" /></Button>
          : <Button size="icon" variant="ghost" aria-label="복원" disabled={busy || p.kind === 'cover'} onClick={() => void patch(p, { status: 'published' }, '복원했어요.')}><RotateCcw className="size-4" /></Button>}
        <Button size="icon" variant="ghost" aria-label="삭제" disabled={busy} onClick={() => setDel(p)}><Trash2 className="size-4 text-red-600" /></Button>
      </div>
    </Card>)

  return (
    <>
      <PageHeader title="사진 관리" description="식당 대표 사진과 갤러리를 올려요. 큰 사진은 올리기 전에 자동으로 줄여요. 올린 사진은 앱 식당 상세에 바로 보여요." />
      {notice && <p role={notice.tone === 'bad' ? 'alert' : 'status'} className={`mb-4 rounded-xl p-3 text-sm ${notice.tone === 'bad' ? 'bg-amber-50 text-amber-900' : 'bg-brand/30'}`}>{notice.text}</p>}
      <Card className="mb-5 grid gap-3 sm:grid-cols-2">
        <Field label="식당 검색" htmlFor="pq"><Input id="pq" value={q} onChange={(e) => setQ(e.target.value)} placeholder="이름으로 검색" /></Field>
        <Field label="식당 선택" htmlFor="ps">
          <Select id="ps" value={restaurantId} onChange={(e) => { setRestaurantId(e.target.value); setNotice(null) }}>
            <option value="">선택하세요</option>{restaurants.data?.map((r) => <option key={r.id} value={r.id}>{r.name_ko}</option>)}
          </Select>
        </Field>
      </Card>
      {!restaurantId && <EmptyState>식당을 선택하면 사진이 보여요.</EmptyState>}
      {restaurantId && photos.isLoading && <Skeleton className="h-48 w-full" />}
      {restaurantId && photos.error && <ErrorState error={photos.error} onRetry={() => void photos.refetch()} />}
      {restaurantId && photos.data && (
        <div className="space-y-6">
          {selected && selected.visibility !== 'published' && (
            <p className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">이 식당은 아직 &lsquo;{selected.visibility}&rsquo; 상태라 앱에 사진이 보이지 않아요. 식당을 공개하면 함께 보여요.</p>
          )}
          <section aria-labelledby="cover-h">
            <h2 id="cover-h" className="mb-2 font-bold">대표 사진 <span className="text-sm font-normal text-muted">앱 카드와 상세 맨 위에 보여요</span></h2>
            <Card className="flex flex-wrap items-center gap-4">
              {live.cover
                ? <img src={live.cover.url} alt="현재 대표 사진" className="aspect-[4/3] w-60 rounded-xl object-cover" />
                : <div className="grid aspect-[4/3] w-60 place-items-center rounded-xl bg-page text-muted"><div className="text-center text-sm"><ImageOff className="mx-auto mb-1 size-6" />대표 사진 없음<br />앱에는 기본 이미지가 보여요</div></div>}
              <div className="space-y-2">
                {live.cover && <Badge tone="brand">앱에 표시 중</Badge>}
                <label className={`inline-flex h-10 cursor-pointer items-center gap-2 rounded-xl bg-brand px-4 text-sm font-semibold text-brand-ink ${busy ? 'pointer-events-none opacity-50' : ''}`}>
                  <ImagePlus className="size-4" />{live.cover ? '대표 사진 교체' : '대표 사진 올리기'}
                  <input type="file" accept={ALLOWED_IMAGE_TYPES.join(',')} hidden aria-label="대표 사진 올리기" onChange={(e) => { const f = e.target.files?.[0]; if (f) void replaceCover(f); e.target.value = '' }} />
                </label>
                <p className="text-xs text-muted">JPG · PNG · WEBP. 긴 변 1600px 이하로 줄여 올려요.</p>
              </div>
            </Card>
          </section>
          <section aria-labelledby="gal-h">
            <div className="mb-2 flex flex-wrap items-end justify-between gap-3">
              <h2 id="gal-h" className="font-bold">갤러리 <span className="text-sm font-normal text-muted">{live.gallery.length}장 공개 중</span></h2>
              <div className="flex flex-wrap items-end gap-3">
                <Field label="사진 제공자 (학생 사진일 때만)" htmlFor="pc"><Input id="pc" value={credit} onChange={(e) => setCredit(e.target.value)} placeholder="예: 닉네임 (동의받은 경우)" maxLength={100} /></Field>
                <label className={`inline-flex h-10 cursor-pointer items-center gap-2 rounded-xl bg-brand px-4 text-sm font-semibold text-brand-ink ${busy ? 'pointer-events-none opacity-50' : ''}`}>
                  <ImagePlus className="size-4" />사진 올리기
                  <input type="file" multiple accept={ALLOWED_IMAGE_TYPES.join(',')} hidden aria-label="갤러리 사진 올리기" onChange={(e) => { if (e.target.files?.length) void addGallery(e.target.files); e.target.value = '' }} />
                </label>
              </div>
            </div>
            {live.gallery.length === 0 && <EmptyState>갤러리 사진이 없어요.</EmptyState>}
            <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{live.gallery.map((p, i) => <Tile key={p.id} p={p} i={i} />)}</div>
          </section>
          {archived.length > 0 && (
            <section aria-labelledby="arc-h">
              <h2 id="arc-h" className="mb-2 font-bold">보관된 사진 <span className="text-sm font-normal text-muted">앱에는 보이지 않아요</span></h2>
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{archived.map((p, i) => <Tile key={p.id} p={p} i={i} />)}</div>
            </section>)}
        </div>)}
      <ConfirmDialog open={!!del} danger title="사진을 삭제할까요?" description="저장소의 파일도 함께 지워요. 삭제 대신 '보관'하면 나중에 복원할 수 있어요." confirmLabel="삭제" busy={remove.isPending}
        onCancel={() => setDel(null)} onConfirm={() => del && remove.mutate(del)} />
    </>
  )
}
