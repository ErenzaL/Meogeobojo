import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Trash2 } from 'lucide-react'
import { useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Field, Input, PageHeader, Select, Skeleton, Textarea } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'

export const MEAL_TYPES = ['breakfast', 'lunch', 'dinner'] as const
export const MEAL_LABEL: Record<(typeof MEAL_TYPES)[number], string> = { breakfast: '조식', lunch: '중식', dinner: '석식' }
export const THOUSAND_WON_BADGE = '천원의 아침밥'

export type MealForm = { date: string; type: (typeof MEAL_TYPES)[number]; option: string; items: string; price: string; start: string; end: string; badge: string; status: 'published' | 'closed' | 'no_menu'; source: string }

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

type Meal = { id: string; meal_date: string; meal_type: (typeof MEAL_TYPES)[number]; option_name: string; menu_items: { name_ko: string }[]; price_krw: number | null; start_time: string | null; end_time: string | null; badge: string | null; status: string }
const today = () => new Date().toISOString().slice(0, 10)
const emptyForm = (): MealForm => ({ date: today(), type: 'lunch', option: '', items: '', price: '', start: '', end: '', badge: '', status: 'published', source: '' })

export default function CafeteriaPage() {
  const qc = useQueryClient()
  const [cafeteriaId, setCafeteriaId] = useState('')
  const [from, setFrom] = useState(today())
  const [form, setForm] = useState<MealForm>(emptyForm())
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [notice, setNotice] = useState<string | null>(null)
  const [del, setDel] = useState<Meal | null>(null)

  const cafs = useQuery({
    queryKey: ['cafeterias'],
    queryFn: async () => {
      const { data, error } = await supabase.from('campus_cafeterias').select('id,name_ko,kind,universities(name_ko)').order('sort_order')
      if (error) throw error
      return data as unknown as { id: string; name_ko: string | null; kind: string; universities: { name_ko: string } | null }[]
    },
  })
  const meals = useQuery({
    queryKey: ['meals', cafeteriaId, from], enabled: !!cafeteriaId,
    queryFn: async () => {
      const { data, error } = await supabase.from('cafeteria_meals').select('*').eq('cafeteria_id', cafeteriaId).gte('meal_date', from).order('meal_date').order('meal_type').limit(100)
      if (error) throw error
      return data as Meal[]
    },
  })

  const save = useMutation({
    mutationFn: async () => {
      const e = validateMeal(form); setErrors(e)
      if (Object.keys(e).length) throw new Error('입력값을 확인해 주세요')
      const row = {
        cafeteria_id: cafeteriaId, meal_date: form.date, meal_type: form.type, option_name: form.option.trim(),
        menu_items: parseItems(form.items), price_krw: form.price === '' ? null : Number(form.price),
        start_time: form.start || null, end_time: form.end || null, badge: form.badge.trim() || null,
        status: form.status, source_url: form.source.trim() || null, verified_at: new Date().toISOString(),
      }
      const { error } = await supabase.from('cafeteria_meals').upsert(row, { onConflict: 'cafeteria_id,meal_date,meal_type,option_name' })
      if (error) throw error
    },
    onSuccess: async () => { setNotice('저장했어요.'); setForm(emptyForm()); await qc.invalidateQueries({ queryKey: ['meals'] }) },
    onError: (e) => setNotice(errorMessage(e)),
  })
  const remove = useMutation({
    mutationFn: async (id: string) => { const { error } = await supabase.from('cafeteria_meals').delete().eq('id', id); if (error) throw error },
    onSuccess: async () => { setDel(null); await qc.invalidateQueries({ queryKey: ['meals'] }) },
    onError: (e) => { setDel(null); setNotice(errorMessage(e)) },
  })

  const set = <K extends keyof MealForm>(k: K, v: MealForm[K]) => setForm((f) => ({ ...f, [k]: v }))
  return (
    <>
      <PageHeader title="학식" description="식당별 조식(천원의 아침밥 포함) · 중식 · 석식 메뉴를 관리해요. 출처가 확인된 정보만 입력해 주세요." />
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
        <Field label="이 날짜부터 보기" htmlFor="from"><Input id="from" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
      </Card>
      {!cafeteriaId && <EmptyState>학식 식당을 선택하면 메뉴가 보여요.</EmptyState>}
      {cafeteriaId && (
        <div className="grid gap-5 lg:grid-cols-[1fr_24rem]">
          <div className="space-y-3">
            {meals.isLoading && <Skeleton className="h-32 w-full" />}
            {meals.error && <ErrorState error={meals.error} onRetry={() => void meals.refetch()} />}
            {meals.data?.length === 0 && <EmptyState>이 날짜 이후에 등록된 메뉴가 없어요.</EmptyState>}
            {meals.data?.map((m) => (
              <Card key={m.id} className="flex items-start justify-between gap-3">
                <div>
                  <div className="font-semibold">{m.meal_date} · {MEAL_LABEL[m.meal_type]} {m.option_name && `(${m.option_name})`} {m.badge && <Badge tone="brand">{m.badge}</Badge>} {m.status !== 'published' && <Badge tone="amber">{m.status === 'closed' ? '운영 안 함' : '메뉴 없음'}</Badge>}</div>
                  <div className="text-sm text-muted">{m.menu_items.map((i) => i.name_ko).join(' · ') || '—'}</div>
                  <div className="text-xs text-muted">{m.price_krw != null ? `${m.price_krw.toLocaleString('ko-KR')}원` : '가격 미정'}{m.start_time && m.end_time ? ` · ${m.start_time.slice(0, 5)}–${m.end_time.slice(0, 5)}` : ''}</div>
                </div>
                <Button size="icon" variant="ghost" aria-label="삭제" onClick={() => setDel(m)}><Trash2 className="size-4 text-red-600" /></Button>
              </Card>))}
          </div>
          <Card className="space-y-3 self-start">
            <h2 className="font-bold">메뉴 추가 / 덮어쓰기</h2>
            <p className="text-xs text-muted">같은 날짜·식사·코너가 있으면 그 행을 수정해요.</p>
            <Field label="날짜" htmlFor="md" error={errors.date}><Input id="md" type="date" value={form.date} onChange={(e) => set('date', e.target.value)} /></Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="식사" htmlFor="mt"><Select id="mt" value={form.type} onChange={(e) => { const t = e.target.value as MealForm['type']; set('type', t) }}>{MEAL_TYPES.map((t) => <option key={t} value={t}>{MEAL_LABEL[t]}</option>)}</Select></Field>
              <Field label="코너 (선택)" htmlFor="mo"><Input id="mo" value={form.option} onChange={(e) => set('option', e.target.value)} placeholder="B코너" /></Field>
            </div>
            <Field label="메뉴 (한 줄에 하나, 첫 줄이 메인)" htmlFor="mi" error={errors.items}><Textarea id="mi" value={form.items} onChange={(e) => set('items', e.target.value)} /></Field>
            <div className="grid grid-cols-3 gap-3">
              <Field label="가격(원)" htmlFor="mpz" error={errors.price}><Input id="mpz" inputMode="numeric" value={form.price} onChange={(e) => set('price', e.target.value)} /></Field>
              <Field label="시작" htmlFor="ms" error={errors.start}><Input id="ms" placeholder="08:00" value={form.start} onChange={(e) => set('start', e.target.value)} /></Field>
              <Field label="종료" htmlFor="me" error={errors.end}><Input id="me" placeholder="09:30" value={form.end} onChange={(e) => set('end', e.target.value)} /></Field>
            </div>
            <Field label="배지" htmlFor="mb" hint="공식 출처가 있을 때만 사용해요."><div className="flex gap-2"><Input id="mb" value={form.badge} onChange={(e) => set('badge', e.target.value)} /><Button variant="soft" size="sm" onClick={() => setForm((f) => ({ ...f, type: 'breakfast', badge: THOUSAND_WON_BADGE, price: f.price || '1000' }))}>천원의 아침밥</Button></div></Field>
            <Field label="상태" htmlFor="mst"><Select id="mst" value={form.status} onChange={(e) => set('status', e.target.value as MealForm['status'])}><option value="published">메뉴 공개</option><option value="closed">운영 안 함 (출처 확인)</option><option value="no_menu">메뉴 비공개 (출처 확인)</option></Select></Field>
            <Field label="출처 주소" htmlFor="msrc" error={errors.source}><Input id="msrc" placeholder="https://" value={form.source} onChange={(e) => set('source', e.target.value)} /></Field>
            <Button disabled={save.isPending} onClick={() => save.mutate()}>저장</Button>
          </Card>
        </div>)}
      <ConfirmDialog open={!!del} danger title="이 식단을 삭제할까요?" description={del ? `${del.meal_date} ${MEAL_LABEL[del.meal_type]}` : undefined} confirmLabel="삭제" busy={remove.isPending}
        onCancel={() => setDel(null)} onConfirm={() => del && remove.mutate(del.id)} />
    </>
  )
}
