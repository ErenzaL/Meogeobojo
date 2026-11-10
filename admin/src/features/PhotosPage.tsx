import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Archive, ArrowDown, ArrowUp, ImagePlus, ImageOff, RotateCcw, Star, Trash2 } from 'lucide-react'
import { useMemo, useState } from 'react'
import PublishingToolbar from '@/components/PublishingToolbar'
import { Badge, Button, Card, EmptyState, ErrorState, Field, Input, PageHeader, Select, Skeleton } from '@/components/ui'
import { cmsOverview, cmsSaveDraft, cmsState, diffSnapshots, isConflict, type OverviewRow, type PhotoItem } from '@/lib/cms'
import { ALLOWED_IMAGE_TYPES, BUCKET, imagePath, prepareImage } from '@/lib/images'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import PhotoPreview from './photos/PhotoPreview'
import { shownInApp, sortPhotos } from './photos/photo'

export type Photo = PhotoItem
export { shownInApp }

const TYPE = 'restaurant_photos' as const
type Msg = { tone: 'ok' | 'bad'; text: string }

/** A restaurant's cover + gallery are edited as ONE draft and published together. Uploading a
 *  file never shows it to students: the file is only part of the draft until it is published. */
export default function PhotosPage() {
  const qc = useQueryClient()
  const [restaurantId, setRestaurantId] = useState('')
  const [q, setQ] = useState('')
  const [message, setMessage] = useState<Msg | null>(null)
  const [busy, setBusy] = useState(false)
  const [credit, setCredit] = useState('')
  const [edited, setEdited] = useState<PhotoItem[] | null>(null) // null: nothing changed yet (the page shows the server draft / live)
  const [editBase, setEditBase] = useState<number | null>(null)
  const [unsaved, setUnsaved] = useState<Record<string, string>>({}) // photo id -> storage path of an upload no draft references yet
  const [previewing, setPreviewing] = useState(false)

  const restaurants = useQuery({
    queryKey: ['restaurant-picker', q, 'vis'],
    queryFn: async () => {
      let query = supabase.from('restaurant_overrides').select('id,name_ko,visibility').order('name_ko').limit(50)
      if (q.trim()) query = query.ilike('name_ko', `%${q.trim().replace(/[%,()*\\]/g, ' ')}%`)
      const { data, error } = await query
      if (error) throw error
      return data as { id: string; name_ko: string; visibility: string }[]
    },
  })
  const overview = useQuery({ queryKey: ['cms-overview', TYPE], queryFn: () => cmsOverview(TYPE) })
  const ov = useMemo(() => new Map<string, OverviewRow>((overview.data ?? []).map((r) => [r.entity_id, r])), [overview.data])
  const cms = useQuery({ queryKey: ['cms', TYPE, restaurantId], enabled: !!restaurantId, queryFn: () => cmsState(TYPE, restaurantId) })
  const state = cms.data
  const base = state ? (state.draft?.data ?? state.live) : null
  const serverRev = state?.draft?.revision ?? 0
  const serverPhotos = useMemo(() => sortPhotos((base?.photos as PhotoItem[] | undefined) ?? []), [base])
  const photos = edited ?? serverPhotos
  const dirty = edited !== null
  const conflict = editBase !== null && editBase !== serverRev
  const liveById = useMemo(() => new Map(((state?.live.photos as PhotoItem[] | undefined) ?? []).map((p) => [p.id, p])), [state])
  const shown = shownInApp(photos)
  const archived = photos.filter((p) => p.status === 'archived')
  const selected = restaurants.data?.find((r) => r.id === restaurantId)

  const refresh = async () => {
    await qc.invalidateQueries({ queryKey: ['cms', TYPE, restaurantId] }); await qc.invalidateQueries({ queryKey: ['cms-overview', TYPE] }); await qc.invalidateQueries({ queryKey: ['photos'] })
  }
  const change = (next: PhotoItem[]) => { setEdited(sortPhotos(next)); setEditBase((b) => b ?? serverRev) }
  const resetLocal = () => { setEdited(null); setEditBase(null); setUnsaved({}) }

  const save = useMutation({
    mutationFn: () => cmsSaveDraft(TYPE, restaurantId, { photos: sortPhotos(photos) }, editBase ?? serverRev),
    onSuccess: async () => { setMessage({ tone: 'ok', text: '초안을 저장했어요. 앱에는 아직 보이지 않아요. 게시하면 반영돼요.' }); resetLocal(); await refresh() },
    onError: async (e) => { setMessage({ tone: 'bad', text: errorMessage(e) }); if (isConflict(e)) await refresh() },
  })

  const dropUnsaved = (id: string) => {
    const path = unsaved[id]
    if (!path) return
    void supabase.storage.from(BUCKET).remove([path]) // only a file no draft or live row references yet
    setUnsaved(({ [id]: _gone, ...rest }) => { void _gone; return rest })
  }
  /** Upload one file (the draft references it; students cannot see it until it is published). */
  const store = async (file: File) => {
    const img = await prepareImage(file)
    const path = imagePath(`restaurants/${restaurantId}`, img.type)
    const up = await supabase.storage.from(BUCKET).upload(path, img.blob, { contentType: img.type })
    if (up.error) throw up.error
    return { path, img, url: supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl }
  }
  const newItem = (kind: PhotoItem['kind'], s: Awaited<ReturnType<typeof store>>, order: number): PhotoItem => ({
    id: crypto.randomUUID(), kind, storage_path: s.path, url: s.url, caption: null, sort_order: order, status: 'published',
    source: credit.trim() ? 'student' : 'admin', credit: credit.trim() || null, width: s.img.width, height: s.img.height, bytes: s.img.bytes,
  })

  const addGallery = async (files: FileList) => {
    setBusy(true); setMessage(null)
    let list = photos; let order = list.filter((p) => p.kind === 'gallery').reduce((m, p) => Math.max(m, p.sort_order), 0)
    let ok = 0; const failed: string[] = []; const paths: Record<string, string> = {}
    for (const f of Array.from(files)) {
      try { const s = await store(f); const it = newItem('gallery', s, ++order); list = [...list, it]; paths[it.id] = s.path; ok++ }
      catch (e) { failed.push(`${f.name}: ${errorMessage(e)}`) }
    }
    if (ok) { change(list); setUnsaved((u) => ({ ...u, ...paths })) }
    setMessage(failed.length ? { tone: 'bad', text: `${ok}장을 담았고 ${failed.length}장은 실패했어요. ${failed.join(' / ')}` } : { tone: 'ok', text: `${ok}장을 초안에 담았어요. '초안 저장' 후 게시하면 앱에 보여요.` })
    setBusy(false)
  }
  const replaceCover = async (file: File) => {
    setBusy(true); setMessage(null)
    try {
      const s = await store(file)
      const it = newItem('cover', s, 0)
      const old = shown.cover
      if (old) dropUnsaved(old.id)
      change([...photos.map((p) => (old && p.id === old.id ? { ...p, status: 'archived' as const } : p)), it])
      setUnsaved((u) => ({ ...u, [it.id]: s.path }))
      setMessage({ tone: 'ok', text: '새 대표 사진을 초안에 담았어요. 이전 대표 사진은 게시하면 보관돼요.' })
    } catch (e) { setMessage({ tone: 'bad', text: errorMessage(e) }) } finally { setBusy(false) }
  }
  const makeCover = (p: PhotoItem) => {
    const old = shown.cover
    change(photos.map((x) => (x.id === p.id ? { ...x, kind: 'cover' as const, status: 'published' as const, sort_order: 0 } : old && x.id === old.id ? { ...x, status: 'archived' as const } : x)))
    setMessage({ tone: 'ok', text: '대표 사진으로 담았어요. 이전 대표 사진은 게시하면 보관돼요.' })
  }
  const patch = (p: PhotoItem, values: Partial<PhotoItem>) => change(photos.map((x) => (x.id === p.id ? { ...x, ...values } : x)))
  const move = (p: PhotoItem, dir: -1 | 1) => {
    const i = shown.gallery.findIndex((x) => x.id === p.id); const o = shown.gallery[i + dir]
    if (!o) return
    change(photos.map((x) => (x.id === p.id ? { ...x, sort_order: o.sort_order } : x.id === o.id ? { ...x, sort_order: p.sort_order } : x)))
  }
  /** Removes a photo from the draft. A published one is archived on publish: its file and row are kept. */
  const remove = (p: PhotoItem) => { dropUnsaved(p.id); change(photos.filter((x) => x.id !== p.id)) }

  const badge = (p: PhotoItem) => {
    const o = liveById.get(p.id)
    return !o ? 'new' : diffSnapshots({ photos: [o] }, { photos: [p] }).some((c) => c.key.startsWith('chg:')) ? 'edited' : null
  }
  const Tile = ({ p, i }: { p: PhotoItem; i: number }) => (
    <Card className="space-y-2 p-3">
      <img src={p.url} alt={p.caption || '식당 사진'} className="aspect-[4/3] w-full rounded-lg object-cover" loading="lazy" />
      <Input aria-label="사진 설명" defaultValue={p.caption ?? ''} placeholder="사진 설명 (선택)" maxLength={200}
        onBlur={(e) => { const v = e.target.value.trim(); if (v !== (p.caption ?? '')) patch(p, { caption: v || null }) }} />
      {p.credit && <div className="text-xs text-muted">출처: {p.credit}</div>}
      <div className="flex flex-wrap items-center gap-1">
        {badge(p) === 'new' && <Badge tone="neutral">게시 전</Badge>}{badge(p) === 'edited' && <Badge tone="brand">수정됨</Badge>}
        {p.status === 'published' && p.kind === 'gallery' && <>
          <Button size="icon" variant="ghost" aria-label="앞으로" disabled={busy || i === 0} onClick={() => move(p, -1)}><ArrowUp className="size-4" /></Button>
          <Button size="icon" variant="ghost" aria-label="뒤로" disabled={busy || i === shown.gallery.length - 1} onClick={() => move(p, 1)}><ArrowDown className="size-4" /></Button>
          <Button size="sm" variant="outline" disabled={busy} onClick={() => makeCover(p)}><Star className="size-4" />대표로</Button>
        </>}
        {p.status === 'published'
          ? <Button size="icon" variant="ghost" aria-label="보관" disabled={busy} onClick={() => patch(p, { status: 'archived' })}><Archive className="size-4" /></Button>
          : <Button size="icon" variant="ghost" aria-label="복원" disabled={busy || p.kind === 'cover'} onClick={() => patch(p, { status: 'published' })}><RotateCcw className="size-4" /></Button>}
        <Button size="icon" variant="ghost" aria-label="목록에서 제거" title={liveById.has(p.id) ? '게시하면 보관 처리돼요 (파일은 지워지지 않아요)' : '아직 게시되지 않은 사진이에요'} disabled={busy} onClick={() => remove(p)}><Trash2 className="size-4 text-red-600" /></Button>
      </div>
    </Card>)

  return (
    <>
      <PageHeader title="사진 관리" description="식당 대표 사진과 갤러리를 올려요. 큰 사진은 올리기 전에 자동으로 줄여요. 올리거나 고친 내용은 초안으로 저장되고, 게시해야 앱 식당 상세에 보여요." />
      {message && !restaurantId && <p role="alert" className="mb-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{message.text}</p>}
      <Card className="mb-5 grid gap-3 sm:grid-cols-2">
        <Field label="식당 검색" htmlFor="pq"><Input id="pq" value={q} onChange={(e) => setQ(e.target.value)} placeholder="이름으로 검색" /></Field>
        <Field label="식당 선택" htmlFor="ps">
          <Select id="ps" value={restaurantId} onChange={(e) => { setRestaurantId(e.target.value); resetLocal(); setMessage(null) }}>
            <option value="">선택하세요</option>{restaurants.data?.map((r) => { const o = ov.get(r.id); return <option key={r.id} value={r.id}>{r.name_ko}{o?.scheduled_at ? ' · 예약됨' : o?.has_draft ? ' · 초안 있음' : ''}</option> })}
          </Select>
        </Field>
      </Card>
      {!restaurantId && <EmptyState>식당을 선택하면 사진이 보여요.</EmptyState>}
      {restaurantId && cms.isLoading && <Skeleton className="h-48 w-full" />}
      {restaurantId && cms.error && <ErrorState error={cms.error} onRetry={() => void cms.refetch()} />}
      {restaurantId && state && (
        <div className="space-y-6">
          <PublishingToolbar type={TYPE} id={restaurantId} state={state} loading={false} error={null} dirty={dirty} saving={save.isPending} message={message}
            onSaveDraft={() => save.mutate()} onPreview={() => setPreviewing(true)} onChanged={async () => { await refresh(); setMessage(null) }} onConflict={() => void refresh()} />
          {conflict && (
            <div role="alert" className="space-y-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">
              <p><b>다른 관리자가 이 식당의 사진 초안을 먼저 저장했어요.</b></p>
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="outline" onClick={resetLocal}>최신 초안 불러오기 (내 수정 버리기)</Button>
                <Button size="sm" onClick={() => setEditBase(serverRev)}>내 수정으로 덮어쓰기</Button>
              </div>
            </div>)}
          {selected && selected.visibility !== 'published' && (
            <p className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">이 식당은 아직 &lsquo;{selected.visibility}&rsquo; 상태라 앱에 사진이 보이지 않아요. 식당을 공개하면 함께 보여요.</p>
          )}
          <section aria-labelledby="cover-h">
            <h2 id="cover-h" className="mb-2 font-bold">대표 사진 <span className="text-sm font-normal text-muted">앱 카드와 상세 맨 위에 보여요</span></h2>
            <Card className="flex flex-wrap items-center gap-4">
              {shown.cover
                ? <img src={shown.cover.url} alt="현재 대표 사진" className="aspect-[4/3] w-60 rounded-xl object-cover" />
                : <div className="grid aspect-[4/3] w-60 place-items-center rounded-xl bg-page text-muted"><div className="text-center text-sm"><ImageOff className="mx-auto mb-1 size-6" />대표 사진 없음<br />앱에는 기본 이미지가 보여요</div></div>}
              <div className="space-y-2">
                {shown.cover && (liveById.get(shown.cover.id)?.status === 'published' && liveById.get(shown.cover.id)?.kind === 'cover' ? <Badge tone="brand">앱에 표시 중</Badge> : <Badge tone="neutral">게시 전</Badge>)}
                <label className={`inline-flex h-10 cursor-pointer items-center gap-2 rounded-xl bg-brand px-4 text-sm font-semibold text-brand-ink ${busy ? 'pointer-events-none opacity-50' : ''}`}>
                  <ImagePlus className="size-4" />{shown.cover ? '대표 사진 교체' : '대표 사진 올리기'}
                  <input type="file" accept={ALLOWED_IMAGE_TYPES.join(',')} hidden aria-label="대표 사진 올리기" onChange={(e) => { const f = e.target.files?.[0]; if (f) void replaceCover(f); e.target.value = '' }} />
                </label>
                <p className="text-xs text-muted">JPG · PNG · WEBP. 긴 변 1600px 이하로 줄여 올려요.</p>
              </div>
            </Card>
          </section>
          <section aria-labelledby="gal-h">
            <div className="mb-2 flex flex-wrap items-end justify-between gap-3">
              <h2 id="gal-h" className="font-bold">갤러리 <span className="text-sm font-normal text-muted">{shown.gallery.length}장</span></h2>
              <div className="flex flex-wrap items-end gap-3">
                <Field label="사진 제공자 (학생 사진일 때만)" htmlFor="pc"><Input id="pc" value={credit} onChange={(e) => setCredit(e.target.value)} placeholder="예: 닉네임 (동의받은 경우)" maxLength={100} /></Field>
                <label className={`inline-flex h-10 cursor-pointer items-center gap-2 rounded-xl bg-brand px-4 text-sm font-semibold text-brand-ink ${busy ? 'pointer-events-none opacity-50' : ''}`}>
                  <ImagePlus className="size-4" />사진 올리기
                  <input type="file" multiple accept={ALLOWED_IMAGE_TYPES.join(',')} hidden aria-label="갤러리 사진 올리기" onChange={(e) => { if (e.target.files?.length) void addGallery(e.target.files); e.target.value = '' }} />
                </label>
              </div>
            </div>
            {shown.gallery.length === 0 && <EmptyState>갤러리 사진이 없어요.</EmptyState>}
            <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{shown.gallery.map((p, i) => <Tile key={p.id} p={p} i={i} />)}</div>
          </section>
          {archived.length > 0 && (
            <section aria-labelledby="arc-h">
              <h2 id="arc-h" className="mb-2 font-bold">보관된 사진 <span className="text-sm font-normal text-muted">앱에는 보이지 않아요</span></h2>
              <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">{archived.map((p, i) => <Tile key={p.id} p={p} i={i} />)}</div>
            </section>)}
          <PhotoPreview open={previewing} live={state.live} draft={state.draft?.data ?? state.live} onClose={() => setPreviewing(false)} />
        </div>)}
    </>
  )
}
