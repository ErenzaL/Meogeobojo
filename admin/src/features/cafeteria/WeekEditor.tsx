import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, CalendarDays, ChevronLeft, ChevronRight, Clock, Copy, CopyPlus, FileUp, Layers, ListChecks } from 'lucide-react'
import { useMemo, useState } from 'react'
import PublishingToolbar from '@/components/PublishingToolbar'
import { Badge, Button, Card, ConfirmDialog, ErrorState, Skeleton } from '@/components/ui'
import { cafeteriaWeekEntity, cmsPublishWeekDays, cmsSaveDraft, cmsState, isConflict } from '@/lib/cms'
import { isMissingFunction } from '@/lib/cmsHealth'
import { errorMessage } from '@/lib/utils'
import CsvImport from './CsvImport'
import { addDays, MEAL_LABEL, MEAL_TYPES, seoulToday } from './meal'
import WeekGrid, { optionLabel } from './WeekGrid'
import WeekPreview from './WeekPreview'
import { BulkDialog, CopyDayDialog, CopyWeekDialog, HoursDialog, PublishDaysDialog, SharedDialog } from './WeekTools'
import {
  addOption, applyHours, applyNotes, applyShared, normalizeOrders, bulkPatch, changedDates, copyDay, copyWeek, isWeekend, mondayOf, prepareForSave, removeMeal, renameOption, slotKey, sortMeals,
  updateExtra, updateMeal, validateWeek, weekCounts, weekDates, type MealPeriod, type MealStatus, type WeekMeal,
} from './week'

const TYPE = 'cafeteria_week' as const
type Msg = { tone: 'ok' | 'bad'; text: string }
type Dialog = null | 'copyDay' | 'copyWeek' | 'hours' | 'shared' | 'bulk' | 'publishDays' | 'csv'

/** One cafeteria, one week, ONE draft: all menus (Monday-Friday, optionally the weekend) are edited in the same grid and
 *  saved together. The publishing toolbar publishes / schedules / unpublishes / restores the WHOLE week atomically;
 *  "선택한 날만 게시" publishes chosen days atomically. Saving never changes what students see. */
export default function WeekEditor({ cafeteria, week, onWeek, onChanged }: {
  cafeteria: { id: string; name: string; names?: string[]; universityId?: string; universityName?: string; mealPeriods: MealPeriod[]; operatingDays: number[] }; week: string; onWeek: (monday: string) => void; onChanged: () => void
}) {
  const qc = useQueryClient()
  const [edited, setEdited] = useState<WeekMeal[] | null>(null)
  const [editBase, setEditBase] = useState<number | null>(null)
  const [message, setMessage] = useState<Msg | null>(null)
  const [dialog, setDialog] = useState<Dialog>(null)
  const [previewing, setPreviewing] = useState(false)
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [weekendOn, setWeekendOn] = useState<boolean | null>(null)
  const [confirm, setConfirm] = useState<{ title: string; text: string; label: string; run: () => void } | null>(null)
  const [pendingWeek, setPendingWeek] = useState<string | null>(null)
  const [problems, setProblems] = useState<Map<string, string>>(new Map())
  const [copying, setCopying] = useState(false)

  const entity = useQuery({ queryKey: ['cafeteria-week', cafeteria.id, week], queryFn: () => cafeteriaWeekEntity(cafeteria.id, week), retry: false })
  const id = entity.data
  const cms = useQuery({ queryKey: ['cms', TYPE, id], enabled: !!id, queryFn: () => cmsState(TYPE, id!) })
  const state = cms.data
  const liveMeals = useMemo(() => sortMeals(((state?.live.meals as WeekMeal[] | undefined) ?? [])), [state])
  const serverMeals = useMemo(() => sortMeals((((state?.draft?.data ?? state?.live)?.meals as WeekMeal[] | undefined) ?? [])), [state])
  const serverRev = state?.draft?.revision ?? 0
  const meals = edited ?? serverMeals
  const dirty = edited !== null
  const liveKeys = useMemo(() => new Set(liveMeals.map(slotKey)), [liveMeals])
  const conflict = editBase !== null && editBase !== serverRev

  const weekend = weekendOn ?? (cafeteria.operatingDays.some((d) => d >= 6) || meals.some((m) => isWeekend(m.date)))
  const dates = weekDates(week, weekend)
  const periods = MEAL_TYPES.filter((t) => cafeteria.mealPeriods.includes(t) || meals.some((m) => m.meal_type === t))
  const counts = weekCounts(meals)

  const refresh = async () => {
    await qc.invalidateQueries({ queryKey: ['cms', TYPE, id] }); await qc.invalidateQueries({ queryKey: ['cms-overview', TYPE] }); await qc.invalidateQueries({ queryKey: ['cafeteria-weeks'] }); onChanged()
  }
  const change = (next: WeekMeal[]) => { setEdited(normalizeOrders(next)); setEditBase((b) => b ?? serverRev); setProblems(new Map()) }
  const reset = () => { setEdited(null); setEditBase(null); setSelected(new Set()); setProblems(new Map()) }
  const goWeek = (monday: string) => { if (dirty) setPendingWeek(monday); else { reset(); setMessage(null); onWeek(monday) } }

  const save = useMutation({
    mutationFn: async () => {
      const { meals: ready, errors } = prepareForSave(meals, liveKeys)
      const all = [...errors, ...validateWeek(ready)]
      if (all.length) { setProblems(new Map(all.map((e) => [e.key, e.message]))); throw new Error(all.length === 1 ? all[0].message : `${all[0].message} (외 ${all.length - 1}건)`) }
      return cmsSaveDraft(TYPE, id!, { meals: ready }, editBase ?? serverRev)
    },
    onSuccess: async () => { setMessage({ tone: 'ok', text: '한 주 전체를 초안으로 저장했어요. 앱에는 아직 보이지 않아요. 게시하면 반영돼요.' }); reset(); await refresh() },
    onError: async (e) => { setMessage({ tone: 'bad', text: errorMessage(e) }); if (isConflict(e)) await refresh() },
  })
  const publishDays = useMutation({
    mutationFn: ({ days, reason }: { days: string[]; reason: string }) => cmsPublishWeekDays(id!, state!.draft!.revision, days, reason),
    onSuccess: async (v, { days }) => { setDialog(null); setMessage({ tone: 'ok', text: `${days.length}일을 한꺼번에 게시했어요 (버전 ${v}). 나머지 날의 수정은 초안에 남아 있어요.` }); await refresh(); await qc.invalidateQueries({ queryKey: ['cms-versions', TYPE, id] }) },
    onError: async (e) => { setDialog(null); setMessage({ tone: 'bad', text: errorMessage(e) }); if (isConflict(e)) await refresh() },
  })

  const ops = {
    change: (key: string, patch: Partial<WeekMeal>) => change(updateMeal(meals, key, patch)),
    extra: (key: string, patch: Partial<WeekMeal['extra']>) => change(updateExtra(meals, key, patch)),
    rename: (key: string, name: string) => change(renameOption(meals, key, name)),
    taken: (m: WeekMeal, name: string) => name !== m.option_name && meals.some((x) => x !== m && x.date === m.date && x.meal_type === m.meal_type && x.option_name === name),
    add: (date: string, type: MealPeriod) => change(addOption(meals, date, type)),
    select: (key: string, on: boolean) => setSelected((s) => { const n = new Set(s); if (on) n.add(key); else n.delete(key); return n }),
    remove: (m: WeekMeal) => {
      const key = slotKey(m)
      if (liveKeys.has(key)) setConfirm({ title: `${optionLabel(m)} 메뉴를 삭제할까요?`, text: '게시하면 이 메뉴가 앱에서 사라져요 (내용은 지워지지 않고 게시 이력으로 복원할 수 있어요).', label: '삭제', run: () => change(removeMeal(meals, key)) })
      else change(removeMeal(meals, key))
    },
    askStatus: (m: WeekMeal, to: MealStatus) => {
      const key = slotKey(m)
      const apply = () => change(updateMeal(meals, key, { status: to }))
      if (to !== 'published' && m.status === 'published' && liveKeys.has(key)) {
        setConfirm({ title: `${optionLabel(m)}을(를) ${to === 'closed' ? '운영 안 함' : '메뉴 비공개'}으로 바꿀까요?`, text: '게시하면 앱에서 메뉴 대신 그 상태가 보여요.', label: '바꾸기', run: apply })
      } else apply()
    },
  }

  const copyFromWeek = async (source: string, overwrite: boolean) => {
    setCopying(true)
    try {
      const otherId = await cafeteriaWeekEntity(cafeteria.id, source)
      const other = await cmsState(TYPE, otherId)
      const otherMeals = (((other.draft?.data ?? other.live).meals as WeekMeal[] | undefined) ?? [])
      const run = () => { change(copyWeek(meals, otherMeals, source, week, { overwrite })); setMessage({ tone: 'ok', text: `${source} 주의 식단 ${otherMeals.length}개를 가져왔어요. 확인한 뒤 '초안 저장'을 눌러 주세요.` }) }
      setDialog(null)
      if (otherMeals.length === 0) setMessage({ tone: 'bad', text: `${source} 주에는 가져올 식단이 없어요.` })
      else if (overwrite && meals.length > 0) setConfirm({ title: '이 주의 메뉴를 모두 바꿀까요?', text: `지금 입력된 메뉴 ${meals.length}개가 ${source} 주의 식단으로 바뀌어요 (저장 전에는 되돌릴 수 있어요).`, label: '모두 바꾸기', run })
      else run()
    } catch (e) { setMessage({ tone: 'bad', text: errorMessage(e) }) } finally { setCopying(false) }
  }

  if (entity.isLoading || (id && cms.isLoading)) return <Skeleton className="h-64 w-full" />
  if (isMissingFunction(entity.error)) {
    return <Card role="alert" className="border-amber-300 bg-amber-50 text-sm text-amber-900"><b>주간 식단 기능이 아직 데이터베이스에 없어요.</b> 마이그레이션 <b>20261118000100</b>을 적용하면 한 주를 한꺼번에 편집·게시할 수 있어요. 식당 정보 관리는 지금도 그대로 쓸 수 있어요.</Card>
  }
  if (entity.error) return <ErrorState error={entity.error} onRetry={() => void entity.refetch()} />
  if (cms.error) return <ErrorState error={cms.error} onRetry={() => void cms.refetch()} />
  if (!state || !id) return null
  const draftMeals = ((state.draft?.data.meals as WeekMeal[] | undefined) ?? [])
  const changed = state.draft ? changedDates(liveMeals, draftMeals) : []
  const monday = mondayOf(seoulToday())
  const end = addDays(week, 6)

  return (
    <div className="space-y-3" aria-label="주간 식단 편집">
      <div className="flex flex-wrap items-center gap-2">
        <Button variant="outline" size="icon" aria-label="이전 주" onClick={() => goWeek(addDays(week, -7))}><ChevronLeft className="size-4" /></Button>
        <div className="grow text-center text-sm font-semibold" aria-label="표시 중인 주">{week} ~ {end}</div>
        <Button variant="outline" size="icon" aria-label="다음 주" onClick={() => goWeek(addDays(week, 7))}><ChevronRight className="size-4" /></Button>
        <Button variant="outline" size="sm" onClick={() => goWeek(monday)}>이번 주</Button>
      </div>

      <PublishingToolbar type={TYPE} id={id} state={state} loading={false} error={null} dirty={dirty} saving={save.isPending} message={message}
        onSaveDraft={() => save.mutate()} onPreview={() => setPreviewing(true)} onChanged={async () => { await refresh(); setMessage(null) }} onConflict={() => void refresh()} />

      <Card className="flex flex-wrap items-center gap-2 !p-3">
        {cafeteria.universityId && <Button size="sm" variant="soft" disabled={dirty} title={dirty ? '먼저 초안을 저장하거나 수정을 버려 주세요' : '이 식당의 이 주 메뉴를 CSV 파일로 한 번에 채워요'} onClick={() => setDialog('csv')}><FileUp className="size-3.5" />CSV로 이 주 채우기</Button>}
        <Button size="sm" variant="outline" onClick={() => setDialog('copyDay')}><Copy className="size-3.5" />요일 복사</Button>
        <Button size="sm" variant="outline" onClick={() => setDialog('copyWeek')}><CopyPlus className="size-3.5" />다른 주 복사</Button>
        <Button size="sm" variant="outline" onClick={() => setDialog('hours')}><Clock className="size-3.5" />공통 운영 시간</Button>
        <Button size="sm" variant="outline" onClick={() => setDialog('shared')}><Layers className="size-3.5" />공통 메뉴·공지</Button>
        <Button size="sm" variant="outline" disabled={selected.size === 0} onClick={() => setDialog('bulk')}><ListChecks className="size-3.5" />일괄 수정 ({selected.size})</Button>
        <Button size="sm" variant="soft" disabled={!state.draft || dirty || state.draft.stale || changed.length === 0} title={!state.draft ? '저장한 초안이 있어야 해요' : dirty ? '먼저 초안을 저장해 주세요' : undefined} onClick={() => setDialog('publishDays')}><CalendarDays className="size-3.5" />선택한 날만 게시</Button>
        <label className="ml-auto flex items-center gap-1.5 text-sm"><input type="checkbox" aria-label="주말 표시" checked={weekend} onChange={(e) => setWeekendOn(e.target.checked)} />토·일도 편집</label>
        <span className="text-xs text-muted">{counts.slots}칸 입력 · 메뉴 {counts.menus}개{counts.thousandWon ? ` · 천원의 아침밥 ${counts.thousandWon}일` : ''}</span>
      </Card>

      {conflict && (
        <div role="alert" className="space-y-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">
          <p><b>다른 관리자가 이 주의 초안을 먼저 저장했어요.</b></p>
          <div className="flex flex-wrap gap-2"><Button size="sm" variant="outline" onClick={reset}>최신 초안 불러오기 (내 수정 버리기)</Button><Button size="sm" onClick={() => setEditBase(serverRev)}>내 수정으로 덮어쓰기</Button></div>
        </div>)}
      {cafeteria.mealPeriods.length < 3 && (
        <p className="flex items-center gap-2 text-xs text-muted"><AlertTriangle className="size-3.5" />이 식당은 {cafeteria.mealPeriods.map((t) => MEAL_LABEL[t]).join('·')}만 운영하도록 설정돼 있어요. 다른 식사는 식당 정보에서 켜면 나타나요.</p>)}
      <div className="flex flex-wrap items-center gap-2 text-xs text-muted">
        <Badge tone={state.draft ? 'brand' : 'neutral'}>{state.draft ? '초안 있음' : '초안 없음'}</Badge>
        {dirty && <Badge tone="amber">저장하지 않은 수정</Badge>}
        <span>조식 · 중식 · 석식은 모두 입력하지 않아도 돼요. 입력하지 않은 식사는 앱과 웹에 나타나지 않아요. 빈 칸은 아무것도 바꾸지 않아요. 메뉴를 지우거나 &lsquo;운영 안 함&rsquo;으로 바꾸려면 직접 선택하고 확인해 주세요.</span>
      </div>

      <WeekGrid dates={dates} periods={periods} meals={meals} liveKeys={liveKeys} selected={selected} problems={problems} ops={ops} />

      <WeekPreview open={previewing} live={state.live} draft={state.draft?.data ?? state.live} dates={weekDates(week, weekend || draftMeals.some((m) => isWeekend(m.date)))} periods={periods} onClose={() => setPreviewing(false)} />
      {dialog === 'csv' && cafeteria.universityId && (
        <CsvImport onClose={() => setDialog(null)} onDone={() => { reset(); void refresh() }}
          scope={{ universityId: cafeteria.universityId, universityName: cafeteria.universityName ?? '', cafeteriaId: cafeteria.id, cafeteriaName: cafeteria.name, cafeteriaNames: cafeteria.names ?? [], weekStart: week, periods, weekend }} />)}
      {dialog === 'copyDay' && <CopyDayDialog open dates={dates} onClose={() => setDialog(null)} onApply={(from, to, overwrite) => {
        const run = () => { change(copyDay(meals, from, to, { overwrite })); setMessage({ tone: 'ok', text: `${from} 의 메뉴를 ${to.length}일에 복사했어요. 확인한 뒤 '초안 저장'을 눌러 주세요.` }) }
        if (overwrite && to.some((d) => meals.some((m) => m.date === d))) setConfirm({ title: '그 요일의 메뉴를 덮어쓸까요?', text: '선택한 요일에 이미 입력된 메뉴가 바뀌어요 (저장 전에는 되돌릴 수 있어요).', label: '덮어쓰기', run })
        else run()
      }} />}
      {dialog === 'copyWeek' && <CopyWeekDialog open thisMonday={week} previousMonday={addDays(week, -7)} nextMonday={addDays(week, 7)} busy={copying} onClose={() => setDialog(null)} onApply={(src, ow) => void copyFromWeek(src, ow)} />}
      {dialog === 'hours' && <HoursDialog open dates={dates} periods={periods} onClose={() => setDialog(null)} onApply={(ds, ps, s, e) => { change(applyHours(meals, ds, ps, s, e)); setMessage({ tone: 'ok', text: `${ds.length}일의 ${ps.map((p) => MEAL_LABEL[p]).join('·')} 이용 시간을 ${s}–${e}로 맞췄어요.` }) }} />}
      {dialog === 'shared' && <SharedDialog open dates={dates} periods={periods} onClose={() => setDialog(null)} onApply={({ dates: ds, perMeal, mode, origin, notice }) => {
        let next = meals
        if (Object.values(perMeal).some((t) => t && t.trim())) next = applyShared(next, ds, perMeal, mode).meals
        if (mode === 'add' && (origin.trim() || notice.trim())) next = applyNotes(next, ds, periods, { origin, notice }).meals
        const touched = next.filter((m, i) => m !== meals[i]).length   // distinct meals that really changed
        if (touched === 0) { setMessage({ tone: 'bad', text: '적용할 메뉴가 없었어요. 고른 요일에 공개 중인 메뉴가 있는지, 이미 같은 내용인지 확인해 주세요.' }); return }
        change(next); setMessage({ tone: 'ok', text: `${touched}개 식사에 공통 내용을 적용했어요. 확인한 뒤 '초안 저장'을 눌러 주세요.` })
      }} />}
      {dialog === 'bulk' && <BulkDialog open count={selected.size} onClose={() => setDialog(null)} onApply={(p) => {
        let next = bulkPatch(meals, [...selected], { ...(p.price !== undefined ? { price_krw: p.price } : {}), ...(p.start ? { start_time: p.start, end_time: p.end } : {}), ...(p.status ? { status: p.status } : {}) })
        if (p.soldOut !== undefined) for (const k of selected) next = updateExtra(next, k, { sold_out: p.soldOut })
        change(next); setSelected(new Set())
      }} />}
      {dialog === 'publishDays' && <PublishDaysDialog open dates={dates} changed={changed} busy={publishDays.isPending} onClose={() => setDialog(null)} onPublish={(days, reason) => publishDays.mutate({ days, reason })} />}

      <ConfirmDialog open={!!confirm} title={confirm?.title ?? ''} description={confirm?.text} confirmLabel={confirm?.label ?? '확인'} danger onCancel={() => setConfirm(null)} onConfirm={() => { confirm?.run(); setConfirm(null) }} />
      <ConfirmDialog open={!!pendingWeek} title="저장하지 않은 수정이 있어요" description="다른 주로 이동하면 이 주의 저장하지 않은 수정이 사라져요." confirmLabel="수정을 버리고 이동" danger
        onCancel={() => setPendingWeek(null)} onConfirm={() => { const w = pendingWeek!; setPendingWeek(null); reset(); setMessage(null); onWeek(w) }} />
    </div>
  )
}
