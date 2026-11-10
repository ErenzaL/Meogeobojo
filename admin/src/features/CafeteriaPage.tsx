import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ChevronLeft, ChevronRight, Copy, ImageOff, Pencil, Trash2 } from 'lucide-react'
import { useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Field, Input, PageHeader, Select, Skeleton, Textarea } from '@/components/ui'
import { ALLOWED_IMAGE_TYPES, BUCKET, imagePath, prepareImage, storagePathFromUrl } from '@/lib/images'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'

export const MEAL_TYPES = ['breakfast', 'lunch', 'dinner'] as const
export const MEAL_LABEL: Record<(typeof MEAL_TYPES)[number], string> = { breakfast: '조식', lunch: '중식', dinner: '석식' }
export const THOUSAND_WON_BADGE = '천원의 아침밥'

export type MealForm = { date: string; type: (typeof MEAL_TYPES)[number]; option: string; items: string; price: string; start: string; end: string; badge: string; status: 'draft' | 'published' | 'closed' | 'no_menu'; source: string; notice: string }

/** One menu item per line; the first line is the main dish. Returns the jsonb stored in menu_items. */
export const parseItems = (text: string) =>
  text.split('\n').map((l) => l.trim()).filter(Boolean).map((name, i) => ({ name_ko: name, kind: i === 0 ? 'main' : 'side' }))

export function validateMeal(f: MealForm): Record<string, string> {
  const e: Record<string, string> = {}
  if (!/^\d{4}-\d{2}-\d{2}$/.test(f.date)) e.date = '날짜를 선택해 주세요'
  if (f.status === 'published' && parseItems(f.items).length === 0) e.items = '공개하려면 메뉴를 한 줄 이상 입력해 주세요'
  if (f.price !== '' && !/^\d+$/.test(f.price)) e.price = '가격은 0 이상의 정수여야 해요'
  const t = /^([01]\d|2[0-3]):[0-5]\d$/
  if (f.start && !t.test(f.start)) e.start = 'HH:MM'
  if (f.end && !t.test(f.end)) e.end = 'HH:MM'
  if (f.start && f.end && t.test(f.start) && t.test(f.end) && f.start >= f.end) e.end = '종료는 시작보다 늦어야 해요'
  if (f.source && !/^https:\/\//.test(f.source)) e.source = 'https:// 로 시작해야 해요'
  return e
}

type Extra = { photo_url?: string; photo_path?: string; notice?: string; [k: string]: unknown }
type Meal = { id: string; meal_date: string; meal_type: (typeof MEAL_TYPES)[number]; option_name: string; menu_items: { name_ko: string; kind?: string }[]; price_krw: number | null; start_time: string | null; end_time: string | null; badge: string | null; status: string; source_url: string | null; extra: Extra | null }

/** Seoul calendar date (YYYY-MM-DD): the app and the cafeteria menus use Korean dates. */
const seoulToday = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date())
export const addDays = (iso: string, n: number) => { const d = new Date(`${iso}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10) }
/** Monday of the week containing [iso]. */
export const weekStart = (iso: string) => { const dow = new Date(`${iso}T00:00:00Z`).getUTCDay(); return addDays(iso, -((dow + 6) % 7)) }
const DAY = ['월', '화', '수', '목', '금', '토', '일']
export const STATUS_LABEL: Record<string, string> = { draft: '초안 (앱에 안 보임)', published: '메뉴 공개', closed: '운영 안 함 (출처 확인)', no_menu: '메뉴 비공개 (출처 확인)' }
const emptyForm = (date = seoulToday()): MealForm => ({ date, type: 'lunch', option: '', items: '', price: '', start: '', end: '', badge: '', status: 'published', source: '', notice: '' })

export default function CafeteriaPage() {
  const qc = useQueryClient()
  const [cafeteriaId, setCafeteriaId] = useState('')
  const [week, setWeek] = useState(() => weekStart(seoulToday()))
  const [form, setForm] = useState<MealForm>(emptyForm())
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [notice, setNotice] = useState<string | null>(null)
  const [del, setDel] = useState<Meal | null>(null)
  const [editing, setEditing] = useState<Meal | null>(null)
  const weekEnd = addDays(week, 6)

  const cafs = useQuery({
    queryKey: ['cafeterias'],
    queryFn: async () => {
      const { data, error } = await supabase.from('campus_cafeterias').select('id,name_ko,kind,universities(name_ko)').order('sort_order')
      if (error) throw error
      return data as unknown as { id: string; name_ko: string | null; kind: string; universities: { name_ko: string } | null }[]
    },
  })
  const meals = useQuery({
    queryKey: ['meals', cafeteriaId, week], enabled: !!cafeteriaId,
    queryFn: async () => {
      const { data, error } = await supabase.from('cafeteria_meals').select('*').eq('cafeteria_id', cafeteriaId).gte('meal_date', week).lte('meal_date', weekEnd).order('meal_date').order('meal_type').order('option_order')
      if (error) throw error
      return data as Meal[]
    },
  })
  const refresh = () => qc.invalidateQueries({ queryKey: ['meals'] })

  const sameKey = (m: Meal) => m.meal_date === form.date && m.meal_type === form.type && m.option_name === form.option.trim()
  const save = useMutation({
    mutationFn: async () => {
      const e = validateMeal(form); setErrors(e)
      if (Object.keys(e).length) throw new Error('입력값을 확인해 주세요')
      // Keep the photo (and anything else in `extra`) of the row being overwritten.
      const before = editing ?? meals.data?.find(sameKey) ?? null
      const extra: Extra = { ...(before?.extra ?? {}) }
      if (form.notice.trim()) extra.notice = form.notice.trim(); else delete extra.notice
      const row = {
        cafeteria_id: cafeteriaId, meal_date: form.date, meal_type: form.type, option_name: form.option.trim(),
        menu_items: parseItems(form.items), price_krw: form.price === '' ? null : Number(form.price),
        start_time: form.start || null, end_time: form.end || null, badge: form.badge.trim() || null,
        status: form.status, source_url: form.source.trim() || null, verified_at: new Date().toISOString(), extra,
      }
      const { error } = await supabase.from('cafeteria_meals').upsert(row, { onConflict: 'cafeteria_id,meal_date,meal_type,option_name' })
      if (error) throw error
    },
    onSuccess: async () => {
      setNotice(form.status === 'draft' ? '초안으로 저장했어요. 공개하기 전에는 앱에 보이지 않아요.' : '저장했어요. 앱에 바로 반영돼요.')
      setEditing(null); setForm(emptyForm(form.date)); await refresh()
    },
    onError: (e) => setNotice(errorMessage(e)),
  })
  const remove = useMutation({
    mutationFn: async (m: Meal) => {
      const { error } = await supabase.from('cafeteria_meals').delete().eq('id', m.id)
      if (error) throw error
      const path = m.extra?.photo_path ?? storagePathFromUrl(m.extra?.photo_url)
      if (path) await supabase.storage.from(BUCKET).remove([path]) // no orphaned photo
    },
    onSuccess: async () => { setDel(null); await refresh() },
    onError: (e) => { setDel(null); setNotice(errorMessage(e)) },
  })
  const patch = useMutation({
    mutationFn: async ({ m, values }: { m: Meal; values: Record<string, unknown> }) => {
      const { error } = await supabase.from('cafeteria_meals').update(values).eq('id', m.id)
      if (error) throw error
    },
    onSuccess: async () => { setNotice('저장했어요.'); await refresh() },
    onError: (e) => setNotice(errorMessage(e)),
  })

  const uploadPhoto = async (m: Meal, file: File) => {
    try {
      setNotice(null)
      const img = await prepareImage(file)
      const path = imagePath(`cafeteria/${cafeteriaId}`, img.type)
      const up = await supabase.storage.from(BUCKET).upload(path, img.blob, { contentType: img.type })
      if (up.error) throw up.error
      const url = supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl
      const oldPath = m.extra?.photo_path ?? storagePathFromUrl(m.extra?.photo_url)
      const r = await supabase.from('cafeteria_meals').update({ extra: { ...(m.extra ?? {}), photo_url: url, photo_path: path } }).eq('id', m.id)
      if (r.error) { await supabase.storage.from(BUCKET).remove([path]); throw r.error }
      if (oldPath) await supabase.storage.from(BUCKET).remove([oldPath])
      setNotice('사진을 올렸어요.'); await refresh()
    } catch (e) { setNotice(errorMessage(e)) }
  }
  const clearPhoto = async (m: Meal) => {
    const { photo_url: _u, photo_path: _p, ...rest } = m.extra ?? {}
    void _u; void _p
    const oldPath = m.extra?.photo_path ?? storagePathFromUrl(m.extra?.photo_url)
    const r = await supabase.from('cafeteria_meals').update({ extra: rest }).eq('id', m.id)
    if (r.error) return setNotice(errorMessage(r.error))
    if (oldPath) await supabase.storage.from(BUCKET).remove([oldPath])
    setNotice('사진을 삭제했어요.'); await refresh()
  }

  const startEdit = (m: Meal) => {
    setEditing(m); setErrors({})
    setForm({ date: m.meal_date, type: m.meal_type, option: m.option_name, items: m.menu_items.map((i) => i.name_ko).join('\n'), price: m.price_krw == null ? '' : String(m.price_krw), start: m.start_time?.slice(0, 5) ?? '', end: m.end_time?.slice(0, 5) ?? '', badge: m.badge ?? '', status: m.status as MealForm['status'], source: m.source_url ?? '', notice: m.extra?.notice ?? '' })
  }
  /** Copies a meal into the form for the same weekday NEXT week (the usual weekly routine); nothing is saved until 저장. */
  const duplicate = (m: Meal) => {
    setEditing(null); setErrors({})
    setForm({ date: addDays(m.meal_date, 7), type: m.meal_type, option: m.option_name, items: m.menu_items.map((i) => i.name_ko).join('\n'), price: m.price_krw == null ? '' : String(m.price_krw), start: m.start_time?.slice(0, 5) ?? '', end: m.end_time?.slice(0, 5) ?? '', badge: m.badge ?? '', status: 'draft', source: m.source_url ?? '', notice: m.extra?.notice ?? '' })
    setNotice(`${addDays(m.meal_date, 7)}로 복제했어요. 내용을 확인하고 저장하세요. 초안으로 시작해요.`)
  }

  const set = <K extends keyof MealForm>(k: K, v: MealForm[K]) => setForm((f) => ({ ...f, [k]: v }))
  const days = Array.from({ length: 7 }, (_, i) => addDays(week, i))
  const byDay = (d: string) => (meals.data ?? []).filter((m) => m.meal_date === d)

  return (
    <>
      <PageHeader title="학식" description="식당별 조식(천원의 아침밥 포함) · 중식 · 석식 메뉴를 주 단위로 관리해요. 출처가 확인된 정보만 입력해 주세요. 모든 식당이 세 끼를 다 하지는 않아요." />
      {notice && <p role="status" className="mb-4 rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
      {cafs.isLoading && <Skeleton className="h-20 w-full" />}
      {cafs.error && <ErrorState error={cafs.error} onRetry={() => void cafs.refetch()} />}
      <Card className="mb-5 grid gap-3 sm:grid-cols-2">
        <Field label="학식 식당" htmlFor="caf">
          <Select id="caf" value={cafeteriaId} onChange={(e) => setCafeteriaId(e.target.value)}>
            <option value="">선택하세요</option>
            {cafs.data?.map((c) => <option key={c.id} value={c.id}>{c.universities?.name_ko ?? ''} · {c.name_ko ?? c.kind}</option>)}
          </Select>
        </Field>
        <div className="flex items-end gap-2">
          <Button variant="outline" size="icon" aria-label="이전 주" onClick={() => setWeek(addDays(week, -7))}><ChevronLeft className="size-4" /></Button>
          <div className="grow text-center text-sm font-semibold" aria-live="polite" aria-label="표시 중인 주">{week} ~ {weekEnd}</div>
          <Button variant="outline" size="icon" aria-label="다음 주" onClick={() => setWeek(addDays(week, 7))}><ChevronRight className="size-4" /></Button>
          <Button variant="outline" size="sm" onClick={() => setWeek(weekStart(seoulToday()))}>이번 주</Button>
        </div>
      </Card>
      {!cafeteriaId && <EmptyState>학식 식당을 선택하면 메뉴가 보여요.</EmptyState>}
      {cafeteriaId && (
        <div className="grid gap-5 lg:grid-cols-[1fr_24rem]">
          <div className="space-y-4">
            {meals.isLoading && <Skeleton className="h-32 w-full" />}
            {meals.error && <ErrorState error={meals.error} onRetry={() => void meals.refetch()} />}
            {meals.data && days.map((d, i) => (
              <section key={d} aria-label={`${d} ${DAY[i]}요일`}>
                <h2 className="mb-1.5 flex items-center gap-2 text-sm font-bold">{d} ({DAY[i]})
                  <Button size="sm" variant="ghost" onClick={() => { setEditing(null); setForm(emptyForm(d)) }}>+ 이 날 추가</Button></h2>
                {byDay(d).length === 0 && <div className="rounded-xl border border-dashed border-line p-3 text-xs text-muted">등록된 식단 없음 (앱에는 &lsquo;아직 정보 없음&rsquo;으로 보여요)</div>}
                <div className="space-y-2">{byDay(d).map((m) => (
                  <Card key={m.id} className="flex items-start gap-3">
                    {m.extra?.photo_url
                      ? <img src={m.extra.photo_url} alt={`${MEAL_LABEL[m.meal_type]} 사진`} className="size-16 rounded-lg object-cover" />
                      : <span className="grid size-16 shrink-0 place-items-center rounded-lg bg-page text-muted" title="사진 없음"><ImageOff className="size-5" /></span>}
                    <div className="min-w-0 flex-1">
                      <div className="font-semibold">{MEAL_LABEL[m.meal_type]} {m.option_name && `(${m.option_name})`} {m.badge && <Badge tone="brand">{m.badge}</Badge>} {m.status === 'draft' && <Badge tone="neutral">초안</Badge>} {m.status === 'closed' && <Badge tone="amber">운영 안 함</Badge>} {m.status === 'no_menu' && <Badge tone="amber">메뉴 없음</Badge>}</div>
                      <div className="text-sm text-muted">{m.menu_items.map((x) => x.name_ko).join(' · ') || '—'}</div>
                      <div className="text-xs text-muted">{m.price_krw != null ? `${m.price_krw.toLocaleString('ko-KR')}원` : '가격 미정'}{m.start_time && m.end_time ? ` · ${m.start_time.slice(0, 5)}–${m.end_time.slice(0, 5)}` : ''}{m.extra?.notice ? ` · ${m.extra.notice}` : ''}</div>
                      <div className="mt-1 flex flex-wrap items-center gap-2">
                        <label className="cursor-pointer text-xs font-semibold text-brand-strong">{m.extra?.photo_url ? '사진 교체' : '사진 추가'}
                          <input type="file" accept={ALLOWED_IMAGE_TYPES.join(',')} hidden aria-label={`${m.meal_date} ${MEAL_LABEL[m.meal_type]} 사진 올리기`} onChange={(e) => { const f = e.target.files?.[0]; if (f) void uploadPhoto(m, f); e.target.value = '' }} /></label>
                        {m.extra?.photo_url && <button type="button" className="text-xs font-semibold text-red-600" onClick={() => void clearPhoto(m)}>사진 삭제</button>}
                        {m.status === 'draft' && <Button size="sm" variant="soft" disabled={patch.isPending || m.menu_items.length === 0} onClick={() => patch.mutate({ m, values: { status: 'published', verified_at: new Date().toISOString() } })}>공개</Button>}
                        {m.status === 'published' && <Button size="sm" variant="outline" disabled={patch.isPending} onClick={() => patch.mutate({ m, values: { status: 'draft' } })}>비공개로</Button>}
                      </div>
                    </div>
                    <Button size="icon" variant="ghost" aria-label="수정" onClick={() => startEdit(m)}><Pencil className="size-4" /></Button>
                    <Button size="icon" variant="ghost" aria-label="다음 주로 복제" onClick={() => duplicate(m)}><Copy className="size-4" /></Button>
                    <Button size="icon" variant="ghost" aria-label="삭제" onClick={() => setDel(m)}><Trash2 className="size-4 text-red-600" /></Button>
                  </Card>))}</div>
              </section>))}
          </div>
          <Card className="space-y-3 self-start">
            <h2 className="font-bold">{editing ? '식단 수정' : '식단 추가 / 덮어쓰기'}</h2>
            <p className="text-xs text-muted">같은 날짜·식사·코너가 있으면 그 행을 수정해요. 사진은 저장한 뒤 카드에서 올려요.</p>
            <Field label="날짜" htmlFor="md" error={errors.date}><Input id="md" type="date" value={form.date} onChange={(e) => set('date', e.target.value)} /></Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="식사" htmlFor="mt"><Select id="mt" value={form.type} onChange={(e) => set('type', e.target.value as MealForm['type'])}>{MEAL_TYPES.map((t) => <option key={t} value={t}>{MEAL_LABEL[t]}</option>)}</Select></Field>
              <Field label="코너 (선택)" htmlFor="mo"><Input id="mo" value={form.option} onChange={(e) => set('option', e.target.value)} placeholder="B코너" /></Field>
            </div>
            <Field label="메뉴 (한 줄에 하나, 첫 줄이 메인)" htmlFor="mi" error={errors.items}><Textarea id="mi" value={form.items} onChange={(e) => set('items', e.target.value)} /></Field>
            <div className="grid grid-cols-3 gap-3">
              <Field label="가격(원)" htmlFor="mpz" error={errors.price}><Input id="mpz" inputMode="numeric" value={form.price} onChange={(e) => set('price', e.target.value)} /></Field>
              <Field label="시작" htmlFor="ms" error={errors.start}><Input id="ms" placeholder="08:00" value={form.start} onChange={(e) => set('start', e.target.value)} /></Field>
              <Field label="종료" htmlFor="me" error={errors.end}><Input id="me" placeholder="09:30" value={form.end} onChange={(e) => set('end', e.target.value)} /></Field>
            </div>
            <Field label="배지" htmlFor="mb" hint="공식 출처가 있을 때만 사용해요."><div className="flex gap-2"><Input id="mb" value={form.badge} onChange={(e) => set('badge', e.target.value)} /><Button variant="soft" size="sm" onClick={() => setForm((f) => ({ ...f, type: 'breakfast', badge: THOUSAND_WON_BADGE, price: f.price || '1000' }))}>천원의 아침밥</Button></div></Field>
            <Field label="공지 (선택)" htmlFor="mnote" hint="식단 카드 아래에 보여요. 예: 방학 중 운영시간 변경"><Input id="mnote" maxLength={120} value={form.notice} onChange={(e) => set('notice', e.target.value)} /></Field>
            <Field label="상태" htmlFor="mst"><Select id="mst" value={form.status} onChange={(e) => set('status', e.target.value as MealForm['status'])}>{Object.entries(STATUS_LABEL).map(([v, l]) => <option key={v} value={v}>{l}</option>)}</Select></Field>
            <Field label="출처 주소" htmlFor="msrc" error={errors.source}><Input id="msrc" placeholder="https://" value={form.source} onChange={(e) => set('source', e.target.value)} /></Field>
            <div className="flex gap-2"><Button disabled={save.isPending} onClick={() => save.mutate()}>저장</Button>{editing && <Button variant="outline" onClick={() => { setEditing(null); setForm(emptyForm(form.date)) }}>취소</Button>}</div>
          </Card>
        </div>)}
      <ConfirmDialog open={!!del} danger title="이 식단을 삭제할까요?" description={del ? `${del.meal_date} ${MEAL_LABEL[del.meal_type]} — 삭제 대신 '비공개로' 바꾸면 나중에 다시 공개할 수 있어요.` : undefined} confirmLabel="삭제" busy={remove.isPending}
        onCancel={() => setDel(null)} onConfirm={() => del && remove.mutate(del)} />
    </>
  )
}
