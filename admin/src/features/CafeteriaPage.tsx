import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, Archive, ChevronLeft, ChevronRight, Copy, ImageOff, Pencil, Plus, Power, Trash2 } from 'lucide-react'
import { useMemo, useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Field, Input, PageHeader, Select, Skeleton } from '@/components/ui'
import { cmsOverview, cmsSetVisibility, formatKst, isLiveVisible, type OverviewRow } from '@/lib/cms'
import { BUCKET, storagePathFromUrl } from '@/lib/images'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import CafeteriaFormModal from './cafeteria/CafeteriaFormModal'
import MealEditor from './cafeteria/MealEditor'
import MealFields from './cafeteria/MealFields'
import { cafeteriaTitle, kindLabel, STATUS_LABEL as CAF_STATUS, type Cafeteria } from './cafeteria/model'

export * from './cafeteria/meal'
import { DAY, MEAL_LABEL, MEAL_TYPES, addDays, emptyForm, parseItems, seoulDateOf, seoulToday, validateMeal, weekStart, type Extra, type Meal, type MealForm } from './cafeteria/meal'

/** The cafeteria list. A database that has not had the cafeteria-management migration
 *  (20261113000100) has no `status` / `operating_note` columns: the page then still
 *  works with every cafeteria treated as active, and says what is missing. */
function useCafeterias() {
  return useQuery({
    queryKey: ['cafeterias'],
    queryFn: async (): Promise<{ rows: Cafeteria[]; legacy: boolean }> => {
      const cols = 'id,university_id,kind,name_ko,name_en,name_zh,location_description,sort_order'
      const full = await supabase.from('campus_cafeterias').select(`${cols},status,operating_note,universities(name_ko)`).order('sort_order').order('created_at')
      if (!full.error) return { rows: full.data as unknown as Cafeteria[], legacy: false }
      const missing = (full.error as { code?: string; message?: string }).code === '42703' || /does not exist|schema cache/i.test((full.error as { message?: string }).message ?? '')
      if (!missing) throw full.error
      const old = await supabase.from('campus_cafeterias').select(`${cols},universities(name_ko)`).order('sort_order').order('created_at')
      if (old.error) throw old.error
      return { rows: (old.data as unknown as Cafeteria[]).map((c) => ({ ...c, status: 'active', operating_note: null })), legacy: true }
    },
  })
}

export default function CafeteriaPage() {
  const qc = useQueryClient()
  const [pickedUniversity, setPickedUniversity] = useState('')
  const [pickedCafeteria, setPickedCafeteria] = useState('')
  const [search, setSearch] = useState('')
  const [showInactive, setShowInactive] = useState(false)
  const [week, setWeek] = useState(() => weekStart(seoulToday()))
  const [newForm, setNewForm] = useState<MealForm>(emptyForm())
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [notice, setNotice] = useState<string | null>(null)
  const [del, setDel] = useState<Meal | null>(null)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [vis, setVis] = useState<{ m: Meal; to: 'published' | 'hidden' } | null>(null)
  const [cafModal, setCafModal] = useState<'new' | 'edit' | null>(null)
  const [cafAct, setCafAct] = useState<{ c: Cafeteria; to: 'active' | 'inactive' | 'archived' } | null>(null)
  const weekEnd = addDays(week, 6)

  const unis = useQuery({
    queryKey: ['universities'],
    queryFn: async () => {
      const { data, error } = await supabase.from('universities').select('id,name_ko,is_active').order('name_ko')
      if (error) throw error
      return data as { id: string; name_ko: string; is_active: boolean }[]
    },
  })
  const cafs = useCafeterias()
  const all = cafs.data?.rows ?? []
  const legacy = cafs.data?.legacy ?? false
  // Menus are managed ONE UNIVERSITY AT A TIME: a university is always chosen
  // (the first by default) and everything below belongs to it.
  const universityId = pickedUniversity || unis.data?.[0]?.id || ''
  const university = unis.data?.find((u) => u.id === universityId) ?? null
  const ofUniversity = all.filter((c) => c.university_id === universityId)
  const counts = (uid: string) => all.filter((c) => c.university_id === uid && c.status !== 'archived').length
  // The cafeteria being managed: the picked one if it belongs to this university
  // (a just-created one is picked as soon as it has loaded), else its first live one.
  const cafeteriaId = ofUniversity.some((c) => c.id === pickedCafeteria) ? pickedCafeteria : ofUniversity.find((c) => c.status === 'active')?.id ?? ''
  const q = search.trim().toLowerCase()
  const visibleCafs = ofUniversity.filter((c) => (showInactive || c.status === 'active' || c.id === cafeteriaId)
    && (!q || (c.name_ko ?? '').toLowerCase().includes(q) || (c.name_en ?? '').toLowerCase().includes(q) || (c.location_description ?? '').toLowerCase().includes(q)))
  const caf = ofUniversity.find((c) => c.id === cafeteriaId) ?? null

  const meals = useQuery({
    queryKey: ['meals', cafeteriaId, week], enabled: !!cafeteriaId,
    queryFn: async () => {
      const { data, error } = await supabase.from('cafeteria_meals').select('*').eq('cafeteria_id', cafeteriaId).gte('meal_date', week).lte('meal_date', weekEnd).order('meal_date').order('meal_type').order('option_order')
      if (error) throw error
      return data as Meal[]
    },
  })
  // draft / scheduled / failed per meal of this cafeteria (publishing overview)
  const overview = useQuery({ queryKey: ['cms-overview', 'cafeteria_meal', cafeteriaId], enabled: !!cafeteriaId, queryFn: () => cmsOverview('cafeteria_meal', cafeteriaId) })
  const ov = useMemo(() => new Map<string, OverviewRow>((overview.data ?? []).map((r) => [r.entity_id, r])), [overview.data])
  const refresh = async () => { await qc.invalidateQueries({ queryKey: ['meals'] }); await qc.invalidateQueries({ queryKey: ['cms-overview', 'cafeteria_meal', cafeteriaId] }) }

  const setCafStatus = useMutation({
    mutationFn: async ({ c, to }: { c: Cafeteria; to: 'active' | 'inactive' | 'archived' }) => {
      const { error } = await supabase.from('campus_cafeterias').update({ status: to }).eq('id', c.id)
      if (error) throw error
    },
    onSuccess: async (_d, { to }) => {
      setCafAct(null); setNotice(to === 'active' ? '다시 운영 중으로 바꿨어요. 앱에 보여요.' : to === 'inactive' ? '비활성으로 바꿨어요. 앱에서 숨겨져요. 메뉴 기록은 그대로예요.' : '보관했어요. 앱에서 숨겨져요. 언제든 복원할 수 있어요.')
      await qc.invalidateQueries({ queryKey: ['cafeterias'] })
    },
    onError: (e) => { setCafAct(null); setNotice(errorMessage(e)) },
  })

  /** A new meal is created as a hidden DRAFT row (never visible to students). It is
   *  then edited, previewed and published from the toolbar. Nothing is overwritten:
   *  the same date / meal / corner is refused. */
  const create = useMutation({
    mutationFn: async () => {
      const e = validateMeal(newForm); setErrors(e)
      if (Object.keys(e).length) throw new Error('입력값을 확인해 주세요')
      const extra: Extra = {}
      if (newForm.notice.trim()) extra.notice = newForm.notice.trim()
      const { data, error } = await supabase.from('cafeteria_meals').insert({
        cafeteria_id: cafeteriaId, meal_date: newForm.date, meal_type: newForm.type, option_name: newForm.option.trim(),
        menu_items: parseItems(newForm.items), price_krw: newForm.price === '' ? null : Number(newForm.price),
        start_time: newForm.start || null, end_time: newForm.end || null, badge: newForm.badge.trim() || null,
        status: 'draft', source_url: newForm.source.trim() || null, verified_at: `${newForm.verified}T00:00:00+09:00`, extra,
      }).select('id').single()
      if (error) throw error
      return (data as { id: string }).id
    },
    onSuccess: async (id) => {
      setNotice('초안으로 만들었어요. 앱에는 아직 보이지 않아요. 아래에서 다듬고 게시해 주세요.')
      setNewForm(emptyForm(newForm.date)); setEditingId(id); await refresh()
    },
    onError: (e) => setNotice((e as { code?: string })?.code === '23505' ? '같은 날짜·식사·코너의 식단이 이미 있어요. 그 식단을 수정해 주세요.' : errorMessage(e)),
  })
  /** Only a DRAFT meal can be deleted (and its own photo file with it). A published
   *  meal must be unpublished first; published history is never destroyed. */
  const remove = useMutation({
    mutationFn: async (m: Meal) => {
      const { error } = await supabase.from('cafeteria_meals').delete().eq('id', m.id)
      if (error) throw error
      const path = m.extra?.photo_path ?? storagePathFromUrl(m.extra?.photo_url)
      if (path) await supabase.storage.from(BUCKET).remove([path])
    },
    onSuccess: async () => { setDel(null); await refresh() },
    onError: (e) => { setDel(null); setNotice(errorMessage(e)) },
  })
  /** Publish / hide a meal right away: an immediate, versioned change with a reason. */
  const setVisibility = useMutation({
    mutationFn: async ({ m, to, reason }: { m: Meal; to: 'published' | 'hidden'; reason: string }) => { await cmsSetVisibility('cafeteria_meal', m.id, to, reason) },
    onSuccess: async (_d, { to }) => { setVis(null); setNotice(to === 'published' ? '공개했어요. 앱에서 새로고침하면 보여요. 게시 이력에 남았어요.' : '비공개로 바꿨어요 (초안 상태). 게시 이력에 남았어요.'); await refresh(); await qc.invalidateQueries({ queryKey: ['cms'] }) },
    onError: (e) => { setVis(null); setNotice(errorMessage(e)) },
  })

  /** Copies a meal into the NEW-meal form for the same weekday next week; nothing is saved until 초안으로 추가. */
  const duplicate = (m: Meal) => {
    setEditingId(null); setErrors({})
    setNewForm({ date: addDays(m.meal_date, 7), type: m.meal_type, option: m.option_name, items: m.menu_items.map((i) => i.name_ko).join('\n'), price: m.price_krw == null ? '' : String(m.price_krw), start: m.start_time?.slice(0, 5) ?? '', end: m.end_time?.slice(0, 5) ?? '', badge: m.badge ?? '', status: 'draft', source: m.source_url ?? '', notice: m.extra?.notice ?? '', verified: seoulToday() })
    setNotice(`${addDays(m.meal_date, 7)}로 복제했어요. 내용을 확인하고 초안으로 추가하세요.`)
  }
  /** A fresh form for a meal slot that has nothing yet (nothing is created until 초안으로 추가). */
  const addFor = (date: string, type: MealForm['type']) => { setEditingId(null); setErrors({}); setNewForm({ ...emptyForm(date), type }) }

  const setN = <K extends keyof MealForm>(k: K, v: MealForm[K]) => setNewForm((f) => ({ ...f, [k]: v }))
  const days = Array.from({ length: 7 }, (_, i) => addDays(week, i))
  const byDay = (d: string) => (meals.data ?? []).filter((m) => m.meal_date === d)
  const universitiesForForm = (unis.data ?? []).map((u) => ({ id: u.id, name_ko: u.name_ko }))
  const editing = (meals.data ?? []).find((m) => m.id === editingId) ?? null

  return (
    <>
      <PageHeader title="학식" description="학식 식당을 등록하고, 식당별 조식(천원의 아침밥 포함) · 중식 · 석식 메뉴를 주 단위로 관리해요. 수정은 초안으로 저장되고, 게시해야 앱에 보여요. 모든 식당이 세 끼를 다 하지는 않아요."
        actions={<Button onClick={() => setCafModal('new')}><Plus className="size-4" />학식 식당 추가</Button>} />
      {notice && <p role="status" className="mb-4 rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
      {legacy && (
        <p role="alert" className="mb-4 flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900"><AlertTriangle className="mt-0.5 size-4 shrink-0" />
          <span>데이터베이스에 학식 식당 관리 기능(마이그레이션 <b>20261113000100</b>)이 아직 적용되지 않았어요. 식당 목록과 메뉴는 그대로 볼 수 있고 모두 &lsquo;운영 중&rsquo;으로 취급해요. 적용하면 활성·비활성·보관과 운영 안내를 쓸 수 있어요.</span></p>)}
      {(cafs.isLoading || unis.isLoading) && <Skeleton className="h-20 w-full" />}
      {cafs.error && <ErrorState error={cafs.error} onRetry={() => void cafs.refetch()} />}
      <Card className="mb-5 space-y-3">
        <div className="grid gap-3 sm:grid-cols-3">
          <Field label="대학교" htmlFor="cuni" hint="학식은 대학교별로 관리해요">
            <Select id="cuni" value={universityId} onChange={(e) => { setPickedUniversity(e.target.value); setPickedCafeteria(''); setEditingId(null); setNewForm(emptyForm()) }}>
              {unis.data?.map((u) => <option key={u.id} value={u.id}>{u.name_ko} (학식 {counts(u.id)}곳)</option>)}
            </Select>
          </Field>
          <Field label="식당 검색" htmlFor="csearch"><Input id="csearch" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="이름 · 위치" /></Field>
          <Field label="학식 식당" htmlFor="caf">
            <Select id="caf" value={cafeteriaId} onChange={(e) => { setPickedCafeteria(e.target.value); setEditingId(null) }}>
              <option value="">{visibleCafs.length ? '선택하세요' : '식당 없음'}</option>
              {visibleCafs.map((c) => <option key={c.id} value={c.id}>{cafeteriaTitle(c)}{c.status !== 'active' ? ` (${c.status === 'inactive' ? '비활성' : '보관'})` : ''}</option>)}
            </Select>
          </Field>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {!legacy && <label className="flex items-center gap-2 text-sm text-muted"><input type="checkbox" checked={showInactive} onChange={(e) => setShowInactive(e.target.checked)} />비활성·보관된 식당도 보기</label>}
          {caf && (
            <div className="ml-auto flex flex-wrap items-center gap-2">
              {!legacy && <Badge tone={caf.status === 'active' ? 'green' : 'amber'}>{CAF_STATUS[caf.status]}</Badge>}
              <Button size="sm" variant="outline" onClick={() => setCafModal('edit')}><Pencil className="size-3.5" />식당 정보 수정</Button>
              {!legacy && caf.status !== 'active' && <Button size="sm" variant="soft" onClick={() => setCafAct({ c: caf, to: 'active' })}><Power className="size-3.5" />운영 중으로</Button>}
              {!legacy && caf.status === 'active' && <Button size="sm" variant="outline" onClick={() => setCafAct({ c: caf, to: 'inactive' })}><Power className="size-3.5" />비활성화</Button>}
              {!legacy && caf.status !== 'archived' && <Button size="sm" variant="outline" onClick={() => setCafAct({ c: caf, to: 'archived' })}><Archive className="size-3.5" />보관</Button>}
            </div>)}
        </div>
        {university && (
          <p className="text-xs text-muted" aria-label="대학교 현황">
            {university.name_ko}: 학식 식당 {ofUniversity.filter((c) => c.status === 'active').length}곳 운영 중
            {ofUniversity.some((c) => c.status === 'inactive') ? ` · 비활성 ${ofUniversity.filter((c) => c.status === 'inactive').length}곳` : ''}
            {ofUniversity.some((c) => c.status === 'archived') ? ` · 보관 ${ofUniversity.filter((c) => c.status === 'archived').length}곳` : ''}
          </p>)}
        {caf && <p className="text-xs text-muted">{kindLabel(caf.kind)}{caf.location_description ? ` · ${caf.location_description}` : ''}{caf.operating_note ? ` · ${caf.operating_note}` : ''}</p>}
      </Card>
      {cafs.data && university && ofUniversity.length === 0 && <EmptyState>{university.name_ko}에 등록된 학식 식당이 없어요. 위의 &lsquo;학식 식당 추가&rsquo;로 만들어 주세요.</EmptyState>}
      {cafs.data && ofUniversity.length > 0 && visibleCafs.length === 0 && <EmptyState>조건에 맞는 학식 식당이 없어요.</EmptyState>}
      {!cafeteriaId && visibleCafs.length > 0 && <EmptyState>학식 식당을 선택하면 메뉴가 보여요.</EmptyState>}
      {cafeteriaId && (
        <div className="mb-3 flex items-center gap-2">
          <Button variant="outline" size="icon" aria-label="이전 주" onClick={() => setWeek(addDays(week, -7))}><ChevronLeft className="size-4" /></Button>
          <div className="grow text-center text-sm font-semibold" aria-live="polite" aria-label="표시 중인 주">{week} ~ {weekEnd}</div>
          <Button variant="outline" size="icon" aria-label="다음 주" onClick={() => setWeek(addDays(week, 7))}><ChevronRight className="size-4" /></Button>
          <Button variant="outline" size="sm" onClick={() => setWeek(weekStart(seoulToday()))}>이번 주</Button>
        </div>)}
      {cafeteriaId && (
        <div className="grid gap-5 lg:grid-cols-[1fr_26rem]">
          <div className="space-y-4">
            {meals.isLoading && <Skeleton className="h-32 w-full" />}
            {meals.error && <ErrorState error={meals.error} onRetry={() => void meals.refetch()} />}
            {meals.data && days.map((d, i) => (
              <section key={d} aria-label={`${d} ${DAY[i]}요일`} className="space-y-1.5">
                <h2 className="text-sm font-bold">{d} ({DAY[i]})</h2>
                {byDay(d).length === 0 && <div className="rounded-xl border border-dashed border-line p-3 text-xs text-muted">등록된 식단 없음 (앱에는 &lsquo;아직 정보 없음&rsquo;으로 보여요)</div>}
                {MEAL_TYPES.map((type) => {
                  const ms = byDay(d).filter((m) => m.meal_type === type)
                  if (byDay(d).length === 0) return null
                  return (
                    <div key={type} role="group" aria-label={`${d} ${MEAL_LABEL[type]}`} className="space-y-2">
                      {ms.length === 0 && (
                        <div className="flex items-center justify-between rounded-xl border border-dashed border-line px-3 py-2 text-xs text-muted">
                          <span>{MEAL_LABEL[type]} · 등록 안 함</span>
                          <Button size="sm" variant="ghost" onClick={() => addFor(d, type)}>+ {MEAL_LABEL[type]} 추가</Button>
                        </div>)}
                      {ms.map((m) => {
                        const o = ov.get(m.id)
                        const visible = isLiveVisible('cafeteria_meal', { status: m.status })
                        return (
                          <Card key={m.id} className={`flex items-start gap-3 ${editingId === m.id ? 'ring-2 ring-brand-strong' : ''}`}>
                            {m.extra?.photo_url
                              ? <img src={m.extra.photo_url} alt={`${MEAL_LABEL[m.meal_type]} 사진`} className="size-16 rounded-lg object-cover" />
                              : <span className="grid size-16 shrink-0 place-items-center rounded-lg bg-page text-muted" title="사진 없음"><ImageOff className="size-5" /></span>}
                            <div className="min-w-0 flex-1">
                              <div className="font-semibold">{MEAL_LABEL[m.meal_type]} {m.option_name && `(${m.option_name})`} {m.badge && <Badge tone="brand">{m.badge}</Badge>} {m.status === 'draft' && <Badge tone="neutral">초안</Badge>} {m.status === 'published' && <Badge tone="green">공개</Badge>} {m.status === 'closed' && <Badge tone="amber">운영 안 함</Badge>} {m.status === 'no_menu' && <Badge tone="amber">메뉴 없음</Badge>}</div>
                              <div className="text-sm text-muted">{m.menu_items.map((x) => x.name_ko).join(' · ') || '—'}</div>
                              <div className="text-xs text-muted">{m.price_krw != null ? `${m.price_krw.toLocaleString('ko-KR')}원` : '가격 미정'}{m.start_time && m.end_time ? ` · ${m.start_time.slice(0, 5)}–${m.end_time.slice(0, 5)}` : ''}{m.extra?.notice ? ` · ${m.extra.notice}` : ''}</div>
                              <div className="text-xs text-muted">확인 {seoulDateOf(m.verified_at)}{m.source_url ? <> · <a className="text-brand-strong underline" href={m.source_url} target="_blank" rel="noreferrer">출처</a></> : ' · 출처 없음'}</div>
                              {o && (o.has_draft || o.scheduled_at || o.failed_jobs > 0) && (
                                <div className="mt-1 flex flex-wrap gap-1">
                                  {o.has_draft && <Badge tone="brand">게시되지 않은 수정 있음</Badge>}
                                  {o.scheduled_at && <Badge tone="amber">예약 {formatKst(o.scheduled_at)}</Badge>}
                                  {o.failed_jobs > 0 && <Badge tone="red">실패 {o.failed_jobs}</Badge>}
                                </div>)}
                              <div className="mt-1 flex flex-wrap items-center gap-2">
                                {m.status === 'draft' && <Button size="sm" variant="soft" disabled={m.menu_items.length === 0} onClick={() => setVis({ m, to: 'published' })}>바로 공개</Button>}
                                {visible && <Button size="sm" variant="outline" onClick={() => setVis({ m, to: 'hidden' })}>비공개로</Button>}
                              </div>
                            </div>
                            <Button size="icon" variant="ghost" aria-label="수정" onClick={() => setEditingId(m.id)}><Pencil className="size-4" /></Button>
                            <Button size="icon" variant="ghost" aria-label="다음 주로 복제" onClick={() => duplicate(m)}><Copy className="size-4" /></Button>
                            <Button size="icon" variant="ghost" aria-label="삭제" disabled={m.status !== 'draft'} title={m.status !== 'draft' ? '게시된 식단은 먼저 비공개로 바꿔야 삭제할 수 있어요' : undefined} onClick={() => setDel(m)}><Trash2 className="size-4 text-red-600" /></Button>
                          </Card>)
                      })}
                    </div>)
                })}
                <Button size="sm" variant="ghost" onClick={() => addFor(d, 'lunch')}>+ 이 날 식단 추가</Button>
              </section>))}
          </div>
          {editing ? (
            <div className="self-start"><MealEditor key={editing.id} meal={editing} cafeteriaId={cafeteriaId} onClose={() => setEditingId(null)} onChanged={() => void refresh()} /></div>
          ) : (
            <Card className="space-y-3 self-start">
              <h2 className="font-bold">식단 추가 (초안)</h2>
              <p className="text-xs text-muted">같은 날짜·식사·코너는 하나만 만들 수 있어요. 같은 식사에 코너를 여러 개 둘 수 있어요. 만들면 초안이라 앱에 보이지 않고, 게시하면 보여요.</p>
              <MealFields form={newForm} errors={errors} set={setN} identity />
              <Button disabled={create.isPending} onClick={() => create.mutate()}>초안으로 추가</Button>
            </Card>)}
        </div>)}
      {cafModal && (
        <CafeteriaFormModal cafeteria={cafModal === 'edit' ? caf : null} universities={universitiesForForm} defaultUniversity={universityId} legacy={legacy}
          onClose={() => setCafModal(null)}
          onSaved={(id, msg, uni) => { setCafModal(null); setNotice(msg); setPickedUniversity(uni); setPickedCafeteria(id); if (cafModal === 'new') setShowInactive(true) }} />)}
      <ConfirmDialog open={!!cafAct} busy={setCafStatus.isPending} danger={cafAct?.to === 'archived'}
        title={cafAct ? `"${cafeteriaTitle(cafAct.c)}" ${cafAct.to === 'active' ? '다시 운영 중으로?' : cafAct.to === 'inactive' ? '비활성화할까요?' : '보관할까요?'}` : ''}
        description={cafAct?.to === 'active' ? '앱의 학식 화면에 이 식당과 공개된 메뉴가 다시 보여요.' : '앱의 학식 화면에서 이 식당과 메뉴가 숨겨져요. 메뉴 기록은 지워지지 않아요.'}
        confirmLabel={cafAct?.to === 'active' ? '운영 중으로' : cafAct?.to === 'inactive' ? '비활성화' : '보관'}
        onCancel={() => setCafAct(null)} onConfirm={() => cafAct && setCafStatus.mutate({ c: cafAct.c, to: cafAct.to })} />
      <ConfirmDialog open={!!vis} askReason busy={setVisibility.isPending} danger={vis?.to === 'hidden'}
        title={vis ? (vis.to === 'published' ? '지금 공개할까요?' : '비공개로 바꿀까요?') : ''}
        description={vis ? `${vis.m.meal_date} ${MEAL_LABEL[vis.m.meal_type]} — ${vis.to === 'published' ? '저장된 내용 그대로 앱에 보여요. 게시 이력에 남아요.' : '앱에서 숨겨져요 (초안 상태). 내용은 지워지지 않아요.'}` : undefined}
        confirmLabel={vis?.to === 'published' ? '공개' : '비공개로'} onCancel={() => setVis(null)} onConfirm={(reason) => vis && setVisibility.mutate({ m: vis.m, to: vis.to, reason })} />
      <ConfirmDialog open={!!del} danger title="이 초안 식단을 삭제할까요?" description={del ? `${del.meal_date} ${MEAL_LABEL[del.meal_type]} — 아직 게시되지 않은 초안만 삭제할 수 있어요.` : undefined} confirmLabel="삭제" busy={remove.isPending}
        onCancel={() => setDel(null)} onConfirm={() => del && remove.mutate(del)} />
    </>
  )
}
