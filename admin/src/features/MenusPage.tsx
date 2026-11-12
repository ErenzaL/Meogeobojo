import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowDown, ArrowUp, ImageOff, Pencil, RotateCcw, Star, ThumbsUp, Trash2, Archive } from 'lucide-react'
import { useMemo, useState } from 'react'
import PublishingToolbar from '@/components/PublishingToolbar'
import { Badge, Button, Card, EmptyState, ErrorState, Field, Input, PageHeader, Select, Skeleton, Textarea } from '@/components/ui'
import { cmsOverview, cmsSaveDraft, cmsState, diffSnapshots, isConflict, type MenuItem, type OverviewRow } from '@/lib/cms'
import { ALLOWED_IMAGE_TYPES, BUCKET, imagePath, prepareImage } from '@/lib/images'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import { useUniversities } from './restaurants/RestaurantsPage'
import { fetchMenuCounts, fetchPickerRestaurants } from './restaurants/picker/pickerData'
import RestaurantPicker, { MENU_ITEM } from './restaurants/picker/RestaurantPicker'
import type { PickerFilters } from './restaurants/picker/pickerLogic'
import MenuCsvTools from './menus/MenuCsvTools'
import MenuPreview from './menus/MenuPreview'
import { draftFromItem, emptyMenuDraft, itemFromDraft, MENU_CATEGORIES, sortItems, validateMenu, type MenuDraft } from './menus/menu'

export { ALLOWED_IMAGE_TYPES, MAX_IMAGE_BYTES, validateImageFile } from '@/lib/images'
export { MENU_CATEGORIES, validateMenu }

const TYPE = 'restaurant_menus' as const
type Msg = { tone: 'ok' | 'bad'; text: string }

/** A restaurant's menu list is edited as ONE draft and published together. Nothing here
 *  writes the live menus: 초안 저장 stores the draft, the toolbar publishes / schedules it. */
export default function MenusPage() {
  const qc = useQueryClient()
  const [restaurantId, setRestaurantId] = useState('')
  const [filters, setFilters] = useState<PickerFilters>({ search: '', university: '', has: '' })
  const q = filters.search
  const [message, setMessage] = useState<Msg | null>(null)
  const [editing, setEditing] = useState<MenuItem | null>(null)
  const [showArchived, setShowArchived] = useState(false)
  const [form, setForm] = useState<MenuDraft>(emptyMenuDraft)
  const [edited, setEdited] = useState<MenuItem[] | null>(null) // null: nothing changed yet (the list shows the server draft / live)
  const [editBase, setEditBase] = useState<number | null>(null)
  const [unsaved, setUnsaved] = useState<Record<string, string>>({}) // item id -> storage path of an upload no draft references yet
  const [previewing, setPreviewing] = useState(false)

  // Every managed restaurant (the same rows as the 식당 page), grouped by school; not a capped search result.
  const restaurants = useQuery({ queryKey: ['menu-picker', 'restaurants'], queryFn: fetchPickerRestaurants, refetchOnMount: 'always' })
  const menuCounts = useQuery({ queryKey: ['menu-picker', 'counts'], queryFn: fetchMenuCounts, refetchOnMount: 'always' })
  const universities = useUniversities()
  const schools = useMemo(() => (universities.data ?? []).map((u) => ({ id: u.id, name_ko: u.name_ko })), [universities.data])
  const counts = useMemo(() => menuCounts.data ?? new Map<string, number>(), [menuCounts.data])
  const school = schools.find((u) => u.id === filters.university)
  const overview = useQuery({ queryKey: ['cms-overview', TYPE], queryFn: () => cmsOverview(TYPE) })
  const ov = useMemo(() => new Map<string, OverviewRow>((overview.data ?? []).map((r) => [r.entity_id, r])), [overview.data])

  const cms = useQuery({ queryKey: ['cms', TYPE, restaurantId], enabled: !!restaurantId, queryFn: () => cmsState(TYPE, restaurantId) })
  const state = cms.data
  const base = state ? (state.draft?.data ?? state.live) : null
  const serverRev = state?.draft?.revision ?? 0
  const serverItems = useMemo(() => sortItems((base?.items as MenuItem[] | undefined) ?? []), [base])
  const items = edited ?? serverItems
  const dirty = edited !== null
  const conflict = editBase !== null && editBase !== serverRev
  const liveIds = useMemo(() => new Set(((state?.live.items as MenuItem[] | undefined) ?? []).map((i) => i.id)), [state])
  const liveById = useMemo(() => new Map(((state?.live.items as MenuItem[] | undefined) ?? []).map((i) => [i.id, i])), [state])

  const refresh = async () => {
    await qc.invalidateQueries({ queryKey: ['cms', TYPE, restaurantId] }); await qc.invalidateQueries({ queryKey: ['cms-overview', TYPE] }); await qc.invalidateQueries({ queryKey: ['menus'] }); await qc.invalidateQueries({ queryKey: ['menu-picker'] })
  }
  const change = (next: MenuItem[]) => { setEdited(sortItems(next)); setEditBase((b) => b ?? serverRev) }
  const resetLocal = () => { setEdited(null); setEditBase(null); setEditing(null); setForm(emptyMenuDraft); setUnsaved({}) }

  const save = useMutation({
    mutationFn: () => cmsSaveDraft(TYPE, restaurantId, { items: sortItems(items) }, editBase ?? serverRev),
    onSuccess: async () => {
      setMessage({ tone: 'ok', text: '초안을 저장했어요. 앱에는 아직 보이지 않아요. 게시하면 반영돼요.' })
      resetLocal(); await refresh()
    },
    onError: async (e) => { setMessage({ tone: 'bad', text: errorMessage(e) }); if (isConflict(e)) await refresh() },
  })

  const submit = () => {
    const { error, price } = validateMenu(form)
    if (error) return setMessage({ tone: 'bad', text: error })
    if (editing) {
      change(items.map((m) => (m.id === editing.id ? itemFromDraft(form, price, m) : m)))
      setMessage({ tone: 'ok', text: `${form.name.trim()} 수정을 초안에 담았어요. '초안 저장'을 눌러 저장해 주세요.` })
      setEditing(null)
    } else {
      const next = (items.at(-1)?.sort_order ?? 0) + 1
      change([...items, itemFromDraft(form, price, { id: crypto.randomUUID(), sort_order: next })])
      setMessage({ tone: 'ok', text: `${form.name.trim()}을(를) 초안에 담았어요. '초안 저장'을 눌러 저장해 주세요.` })
    }
    setForm(emptyMenuDraft)
  }
  const patch = (m: MenuItem, values: Partial<MenuItem>) => change(items.map((x) => (x.id === m.id ? { ...x, ...values } : x)))
  const move = (m: MenuItem, dir: -1 | 1) => {
    const list = items.filter((x) => showArchived || x.status === 'active'); const i = list.findIndex((x) => x.id === m.id); const o = list[i + dir]
    if (!o) return
    change(items.map((x) => (x.id === m.id ? { ...x, sort_order: o.sort_order } : x.id === o.id ? { ...x, sort_order: m.sort_order } : x)))
  }
  /** Removes a line from the draft. If it was published it becomes ARCHIVED when published (never deleted). */
  const remove = (m: MenuItem) => {
    change(items.filter((x) => x.id !== m.id))
    const path = unsaved[m.id]
    if (path) { void supabase.storage.from(BUCKET).remove([path]); setUnsaved(({ [m.id]: _gone, ...rest }) => { void _gone; return rest }) }
    if (editing?.id === m.id) { setEditing(null); setForm(emptyMenuDraft) }
  }
  /** The photo is staged in the draft; a published photo file is never deleted (a rollback needs it). */
  const upload = async (m: MenuItem, file: File) => {
    try {
      setMessage(null)
      const img = await prepareImage(file)
      const path = imagePath(`menus/${restaurantId}`, img.type)
      const up = await supabase.storage.from(BUCKET).upload(path, img.blob, { contentType: img.type })
      if (up.error) return setMessage({ tone: 'bad', text: errorMessage(up.error) })
      if (unsaved[m.id]) await supabase.storage.from(BUCKET).remove([unsaved[m.id]]) // an earlier unsaved pick would be an orphan
      patch(m, { image_url: supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl })
      setUnsaved((u) => ({ ...u, [m.id]: path }))
      setMessage({ tone: 'ok', text: '사진을 골랐어요. 초안을 저장하면 반영돼요. (게시 전에는 앱에 보이지 않아요)' })
    } catch (e) { setMessage({ tone: 'bad', text: errorMessage(e) }) }
  }
  const clearPhoto = (m: MenuItem) => {
    // only an upload no draft references yet is removed; a saved or published file stays (rollback needs it)
    if (unsaved[m.id]) { void supabase.storage.from(BUCKET).remove([unsaved[m.id]]); setUnsaved(({ [m.id]: _gone, ...rest }) => { void _gone; return rest }) }
    patch(m, { image_url: null })
  }
  const set = <K extends keyof MenuDraft>(k: K, v: MenuDraft[K]) => setForm((d) => ({ ...d, [k]: v }))

  const visible = items.filter((m) => showArchived || m.status === 'active')
  const archivedCount = items.filter((m) => m.status === 'archived').length
  const changed = (m: MenuItem) => {
    const o = liveById.get(m.id)
    return !o ? 'new' : diffSnapshots({ items: [o] }, { items: [m] }).some((c) => c.key.startsWith('chg:')) ? 'edited' : null
  }
  return (
    <>
      <PageHeader title="메뉴·가격" description="식당별 메뉴와 가격(원)을 관리해요. 대학교별로 묶인 목록에서 식당을 고르세요. 가격을 모르면 비워 두세요. 수정은 초안으로 저장되고, 게시해야 앱 식당 상세에 반영돼요."
        actions={<MenuCsvTools selected={restaurantId ? { id: restaurantId, name_ko: restaurants.data?.find((r) => r.id === restaurantId)?.name_ko ?? '' } : null} search={q} university={school ? { id: school.id, name: school.name_ko } : null} />} />
      {message && !restaurantId && <p role="alert" className="mb-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{message.text}</p>}
      <RestaurantPicker item={MENU_ITEM} restaurants={restaurants.data} universities={schools} counts={counts} overview={ov}
        loading={restaurants.isLoading} error={restaurants.error} onRetry={() => void restaurants.refetch()}
        filters={filters} onFilters={setFilters} selectedId={restaurantId} onSelect={(id) => { setRestaurantId(id); resetLocal(); setMessage(null) }} />
      {!restaurantId && <EmptyState>위 목록에서 식당을 선택하면 메뉴가 보여요.</EmptyState>}
      {restaurantId && cms.isLoading && <Skeleton className="h-40 w-full" />}
      {restaurantId && cms.error && <ErrorState error={cms.error} onRetry={() => void cms.refetch()} />}
      {restaurantId && state && (
        <>
          <PublishingToolbar type={TYPE} id={restaurantId} state={state} loading={false} error={null} dirty={dirty} saving={save.isPending} message={message}
            onSaveDraft={() => save.mutate()} onPreview={() => setPreviewing(true)} onChanged={async () => { await refresh(); setMessage(null) }} onConflict={() => void refresh()} />
          {conflict && (
            <div role="alert" className="mb-4 space-y-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">
              <p><b>다른 관리자가 이 식당의 메뉴 초안을 먼저 저장했어요.</b></p>
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="outline" onClick={resetLocal}>최신 초안 불러오기 (내 수정 버리기)</Button>
                <Button size="sm" onClick={() => setEditBase(serverRev)}>내 수정으로 덮어쓰기</Button>
              </div>
            </div>)}
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
                    <div className="font-semibold">{m.name_ko} {m.representative && <Badge tone="brand">대표</Badge>} {m.recommended && <Badge tone="brand">추천</Badge>} {!m.available && <Badge tone="amber">품절</Badge>} {m.status === 'archived' && <Badge tone="amber">보관됨</Badge>} {changed(m) === 'new' && <Badge tone="neutral">새 메뉴 (게시 전)</Badge>} {changed(m) === 'edited' && <Badge tone="brand">수정됨 (게시 전)</Badge>}</div>
                    <div className="text-sm text-muted">
                      {m.price_krw != null ? `${m.price_krw.toLocaleString('ko-KR')}원` : '가격 미정'}
                      {m.category ? ` · ${m.category}` : ''}{m.description_ko ? ` · ${m.description_ko}` : ''}
                    </div>
                    <div className="text-xs text-muted">{m.price_krw != null ? (m.price_verified_on ? `가격 확인 ${m.price_verified_on}` : '가격 확인일 없음') : ''}</div>
                  </div>
                  <label className="cursor-pointer text-xs font-semibold text-brand-strong">{m.image_url ? '사진 교체' : '사진 추가'}
                    <input type="file" accept={ALLOWED_IMAGE_TYPES.join(',')} hidden aria-label={`${m.name_ko} 사진 올리기`} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(m, f); e.target.value = '' }} /></label>
                  {m.image_url && <Button size="sm" variant="ghost" onClick={() => clearPhoto(m)}>사진 삭제</Button>}
                  <Button size="icon" variant="ghost" aria-label="수정" onClick={() => { setEditing(m); setForm(draftFromItem(m)) }}><Pencil className="size-4" /></Button>
                  <Button size="icon" variant="ghost" aria-label="대표 메뉴 전환" onClick={() => patch(m, { representative: !m.representative })}><Star className={`size-4 ${m.representative ? 'fill-brand text-brand-strong' : ''}`} /></Button>
                  <Button size="icon" variant="ghost" aria-label="추천 메뉴 전환" onClick={() => patch(m, { recommended: !m.recommended })}><ThumbsUp className={`size-4 ${m.recommended ? 'fill-brand text-brand-strong' : ''}`} /></Button>
                  <Button size="sm" variant="outline" onClick={() => patch(m, { available: !m.available })}>{m.available ? '품절 처리' : '판매 재개'}</Button>
                  <Button size="icon" variant="ghost" aria-label="위로" disabled={i === 0} onClick={() => move(m, -1)}><ArrowUp className="size-4" /></Button>
                  <Button size="icon" variant="ghost" aria-label="아래로" disabled={i === visible.length - 1} onClick={() => move(m, 1)}><ArrowDown className="size-4" /></Button>
                  {m.status === 'active'
                    ? <Button size="icon" variant="ghost" aria-label="보관" onClick={() => patch(m, { status: 'archived' })}><Archive className="size-4" /></Button>
                    : <Button size="icon" variant="ghost" aria-label="복원" onClick={() => patch(m, { status: 'active' })}><RotateCcw className="size-4" /></Button>}
                  <Button size="icon" variant="ghost" aria-label="목록에서 제거" title={liveIds.has(m.id) ? '게시하면 보관 처리돼요 (삭제되지 않아요)' : '아직 게시되지 않은 메뉴예요'} onClick={() => remove(m)}><Trash2 className="size-4 text-red-600" /></Button>
                </Card>))}
            </div>
            <Card className="space-y-3 self-start">
              <h2 className="font-bold">{editing ? `메뉴 수정 · ${editing.name_ko}` : '새 메뉴'}</h2>
              <Field label="메뉴 이름" htmlFor="mn"><Input id="mn" value={form.name} onChange={(e) => set('name', e.target.value)} placeholder="제육 정식" /></Field>
              <div className="grid grid-cols-2 gap-3">
                <Field label="가격 (원)" htmlFor="mp" hint="모르면 비워 두세요"><Input id="mp" inputMode="numeric" value={form.price} onChange={(e) => set('price', e.target.value)} /></Field>
                <Field label="분류" htmlFor="mc"><Select id="mc" value={form.category} onChange={(e) => set('category', e.target.value)}><option value="">선택 안 함</option>{MENU_CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}</Select></Field>
              </div>
              <Field label="가격 확인일" htmlFor="mv" hint="가격을 직접 확인한 날"><Input id="mv" type="date" value={form.verified} onChange={(e) => set('verified', e.target.value)} /></Field>
              <Field label="설명" htmlFor="md"><Textarea id="md" className="min-h-16" value={form.description} onChange={(e) => set('description', e.target.value)} /></Field>
              <div className="flex gap-2">
                <Button onClick={submit}>{editing ? '수정 담기' : '메뉴 추가'}</Button>
                {editing && <Button variant="outline" onClick={() => { setEditing(null); setForm(emptyMenuDraft) }}>취소</Button>}
              </div>
              <p className="text-xs text-muted">추가·수정은 먼저 초안에 담겨요. 위의 &lsquo;초안 저장&rsquo; 후 &lsquo;지금 게시&rsquo; 또는 &lsquo;예약 게시&rsquo;로 앱에 반영해요. 메뉴를 추가한 뒤 카드의 &lsquo;사진 추가&rsquo;로 사진을 올려요.</p>
            </Card>
          </div>
          <MenuPreview open={previewing} live={state.live} draft={state.draft?.data ?? state.live} onClose={() => setPreviewing(false)} />
        </>)}
    </>
  )
}
