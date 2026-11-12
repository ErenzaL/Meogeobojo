import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, Archive, FileUp, Pencil, Plus, Power } from 'lucide-react'
import { useMemo, useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Field, Input, PageHeader, Select, Skeleton } from '@/components/ui'
import { cmsOverview, formatKst, type OverviewRow } from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import CafeteriaFormModal from './cafeteria/CafeteriaFormModal'
import CafeteriaHistory from './cafeteria/CafeteriaHistory'
import CsvImport from './cafeteria/CsvImport'
import { seoulToday, weekStart } from './cafeteria/meal'
import { cafeteriaTitle, DAYS, daysOf, kindLabel, PERIOD_LABEL, periodsOf, STATUS_LABEL as CAF_STATUS, type Cafeteria } from './cafeteria/model'
import WeekEditor from './cafeteria/WeekEditor'

export * from './cafeteria/meal'

type Tab = 'week' | 'info' | 'history'
type StatusFilter = 'live' | 'active' | 'inactive' | 'archived' | 'all'
const FILTER_LABEL: Record<StatusFilter, string> = { live: '보관 제외 전체', active: '운영 중', inactive: '비활성', archived: '보관됨', all: '모두' }

/** The cafeteria list. A database without migration 20261113000100 has no `status` / `operating_note`, and one without
 *  20261118000100 has no meal periods / weekdays / photo: the page still works and says what is missing. */
function useCafeterias() {
  return useQuery({
    queryKey: ['cafeterias'],
    queryFn: async (): Promise<{ rows: Cafeteria[]; legacy: boolean; weekly: boolean }> => {
      const cols = 'id,university_id,kind,name_ko,name_en,name_zh,location_description,sort_order'
      const missing = (e: unknown) => (e as { code?: string })?.code === '42703' || /does not exist|schema cache/i.test((e as { message?: string })?.message ?? '')
      const a = await supabase.from('campus_cafeterias').select(`${cols},status,operating_note,meal_periods,operating_days,photo_url,photo_path,universities(name_ko)`).order('sort_order').order('created_at')
      if (!a.error) return { rows: a.data as unknown as Cafeteria[], legacy: false, weekly: true }
      if (!missing(a.error)) throw a.error
      const b = await supabase.from('campus_cafeterias').select(`${cols},status,operating_note,universities(name_ko)`).order('sort_order').order('created_at')
      if (!b.error) return { rows: b.data as unknown as Cafeteria[], legacy: false, weekly: false }
      if (!missing(b.error)) throw b.error
      const c = await supabase.from('campus_cafeterias').select(`${cols},universities(name_ko)`).order('sort_order').order('created_at')
      if (c.error) throw c.error
      return { rows: (c.data as unknown as Cafeteria[]).map((x) => ({ ...x, status: 'active', operating_note: null })), legacy: true, weekly: false }
    },
  })
}

export default function CafeteriaPage() {
  const qc = useQueryClient()
  const [pickedUniversity, setPickedUniversity] = useState('')
  const [pickedCafeteria, setPickedCafeteria] = useState('')
  const [search, setSearch] = useState('')
  const [filter, setFilter] = useState<StatusFilter>('live')
  const [tab, setTab] = useState<Tab>('week')
  const [week, setWeek] = useState(() => weekStart(seoulToday()))
  const [notice, setNotice] = useState<string | null>(null)
  const [cafModal, setCafModal] = useState<'new' | 'edit' | null>(null)
  const [csv, setCsv] = useState(false)
  const [cafAct, setCafAct] = useState<{ c: Cafeteria; to: 'active' | 'inactive' | 'archived' } | null>(null)

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
  const weekly = cafs.data?.weekly ?? true
  // Cafeterias are managed ONE UNIVERSITY AT A TIME: a university is always chosen (the first by default).
  const universityId = pickedUniversity || unis.data?.[0]?.id || ''
  const university = unis.data?.find((u) => u.id === universityId) ?? null
  const ofUniversity = all.filter((c) => c.university_id === universityId)
  const counts = (uid: string) => all.filter((c) => c.university_id === uid && c.status !== 'archived').length
  const q = search.trim().toLowerCase()
  const matches = (c: Cafeteria) => !q || (c.name_ko ?? '').toLowerCase().includes(q) || (c.name_en ?? '').toLowerCase().includes(q) || (c.location_description ?? '').toLowerCase().includes(q)
  const byStatus = (c: Cafeteria) => (filter === 'all' ? true : filter === 'live' ? c.status !== 'archived' : c.status === filter)
  const listed = ofUniversity.filter((c) => byStatus(c) && matches(c))
  // the selected cafeteria: the picked one if it belongs to this university (a just-created one is picked as soon as it has loaded)
  const caf = ofUniversity.find((c) => c.id === pickedCafeteria) ?? null

  // per-cafeteria publishing state (drafts / schedules / failures), from the week entities and the overview
  const weeks = useQuery({
    queryKey: ['cafeteria-weeks', universityId], enabled: weekly && ofUniversity.length > 0,
    queryFn: async () => {
      const { data, error } = await supabase.from('cafeteria_weeks').select('id,cafeteria_id,week_start').in('cafeteria_id', ofUniversity.map((c) => c.id))
      if (error) throw error
      return data as { id: string; cafeteria_id: string; week_start: string }[]
    },
    retry: false,
  })
  const overview = useQuery({ queryKey: ['cms-overview', 'cafeteria_week'], enabled: weekly && ofUniversity.length > 0, queryFn: () => cmsOverview('cafeteria_week'), retry: false })
  const ov = useMemo(() => new Map<string, OverviewRow>((overview.data ?? []).map((r) => [r.entity_id, r])), [overview.data])
  const stateOf = (cid: string) => {
    const ws = (weeks.data ?? []).filter((w) => w.cafeteria_id === cid)
    return { drafts: ws.filter((w) => ov.get(w.id)?.has_draft).length, scheduled: ws.filter((w) => ov.get(w.id)?.scheduled_at).length, failed: ws.filter((w) => (ov.get(w.id)?.failed_jobs ?? 0) > 0).length }
  }
  const refreshBadges = async () => { await qc.invalidateQueries({ queryKey: ['cafeteria-weeks'] }); await qc.invalidateQueries({ queryKey: ['cms-overview', 'cafeteria_week'] }) }

  const setCafStatus = useMutation({
    mutationFn: async ({ c, to }: { c: Cafeteria; to: 'active' | 'inactive' | 'archived' }) => {
      const { error } = await supabase.from('campus_cafeterias').update({ status: to }).eq('id', c.id)
      if (error) throw error
    },
    onSuccess: async (_d, { to }) => {
      setCafAct(null); setNotice(to === 'active' ? '운영 중으로 바꿨어요. 게시된 메뉴가 앱에 보여요.' : to === 'inactive' ? '비활성으로 바꿨어요. 앱에서 숨겨져요. 메뉴 기록은 그대로예요.' : '보관했어요. 앱에서 숨겨져요. 언제든 복원할 수 있어요.')
      await qc.invalidateQueries({ queryKey: ['cafeterias'] })
    },
    onError: (e) => { setCafAct(null); setNotice(errorMessage(e)) },
  })

  const periods = caf ? periodsOf(caf) : []
  const weeksOfCaf = (weeks.data ?? []).filter((w) => w.cafeteria_id === caf?.id)

  return (
    <>
      <PageHeader title="학식" description="대학교마다 학식 식당을 여러 곳 등록하고, 식당마다 한 주의 메뉴를 한꺼번에 입력해요. 조식 · 중식 · 석식은 하는 식사만 입력하면 돼요. 학생은 앱과 웹에서 식당을 골라 볼 수 있어요. 수정은 초안으로 저장되고, 게시하거나 예약해야 앱에 보여요."
        actions={<div className="flex gap-2"><Button variant="outline" onClick={() => setCsv(true)}><FileUp className="size-4" />CSV 일괄 등록</Button><Button onClick={() => setCafModal('new')}><Plus className="size-4" />학식 식당 추가</Button></div>} />
      {notice && <p role="status" className="mb-4 rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
      {legacy && (
        <p role="alert" className="mb-4 flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900"><AlertTriangle className="mt-0.5 size-4 shrink-0" />
          <span>데이터베이스에 학식 식당 관리 기능(마이그레이션 <b>20261113000100</b>)이 아직 적용되지 않았어요. 식당 목록은 그대로 볼 수 있고 모두 &lsquo;운영 중&rsquo;으로 취급해요.</span></p>)}
      {!legacy && !weekly && (
        <p role="alert" className="mb-4 flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900"><AlertTriangle className="mt-0.5 size-4 shrink-0" />
          <span>주간 식단 관리(마이그레이션 <b>20261118000100</b>)가 아직 적용되지 않았어요. 적용하면 한 주 전체 편집 · 게시 · CSV 가져오기를 쓸 수 있어요.</span></p>)}
      {(cafs.isLoading || unis.isLoading) && <Skeleton className="h-20 w-full" />}
      {cafs.error && <ErrorState error={cafs.error} onRetry={() => void cafs.refetch()} />}

      <Card className="mb-4 space-y-3">
        <div className="grid gap-3 sm:grid-cols-3">
          <Field label="대학교" htmlFor="cuni" hint="학식은 대학교별로 관리해요">
            <Select id="cuni" value={universityId} onChange={(e) => { setPickedUniversity(e.target.value); setPickedCafeteria('') }}>
              {unis.data?.map((u) => <option key={u.id} value={u.id}>{u.name_ko} (학식 {counts(u.id)}곳)</option>)}
            </Select>
          </Field>
          <Field label="식당 검색" htmlFor="csearch"><Input id="csearch" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="이름 · 위치" /></Field>
          <Field label="상태" htmlFor="cstatus"><Select id="cstatus" value={filter} onChange={(e) => setFilter(e.target.value as StatusFilter)} disabled={legacy}>
            {(Object.keys(FILTER_LABEL) as StatusFilter[]).map((s) => <option key={s} value={s}>{FILTER_LABEL[s]}</option>)}</Select></Field>
        </div>
        {university && (
          <div className="grid gap-3 sm:grid-cols-2" aria-label="대학교 현황">
            <div className="rounded-xl bg-page p-3"><div className="text-xs text-muted">등록된 학식 식당</div><div className="text-2xl font-bold">{ofUniversity.filter((c) => c.status !== 'archived').length}</div>
              <div className="text-xs text-muted">운영 중 {ofUniversity.filter((c) => c.status === 'active').length}곳{ofUniversity.some((c) => c.status === 'inactive') ? ` · 비활성 ${ofUniversity.filter((c) => c.status === 'inactive').length}곳` : ''}{ofUniversity.some((c) => c.status === 'archived') ? ` · 보관 ${ofUniversity.filter((c) => c.status === 'archived').length}곳` : ''}</div></div>
            <div className="rounded-xl bg-page p-3"><div className="text-xs text-muted">메뉴 관리</div><div className="text-lg font-bold">식당마다 한 주씩</div><div className="text-xs text-muted">하는 식사만 입력하면 돼요 · 입력하지 않은 식사는 앱에 나타나지 않아요</div></div>
          </div>)}
      </Card>

      {cafs.data && university && ofUniversity.length === 0 && <EmptyState>{university.name_ko}에 등록된 학식 식당이 없어요. 위의 &lsquo;학식 식당 추가&rsquo; 또는 &lsquo;CSV 일괄 등록&rsquo;으로 만들어 주세요.</EmptyState>}
      {cafs.data && ofUniversity.length > 0 && listed.length === 0 && <EmptyState>조건에 맞는 학식 식당이 없어요.</EmptyState>}
      <div className="mb-5 grid gap-3 md:grid-cols-2 xl:grid-cols-3" aria-label="학식 식당 목록">
        {listed.map((c) => {
          const st = stateOf(c.id)
          return (
            <Card key={c.id} className={`space-y-2 ${caf?.id === c.id ? 'ring-2 ring-brand-strong' : ''}`}>
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0"><div className="truncate text-base font-bold">{cafeteriaTitle(c)}</div><div className="text-xs text-muted">{kindLabel(c.kind)}{c.location_description ? ` · ${c.location_description}` : ''}</div></div>
                {!legacy && <Badge tone={c.status === 'active' ? 'green' : 'amber'}>{c.status === 'active' ? '운영 중' : c.status === 'inactive' ? '비활성' : '보관'}</Badge>}
              </div>
              <div className="flex flex-wrap gap-1.5">{periodsOf(c).map((p) => <span key={p} className="rounded-full bg-page px-2.5 py-1 text-xs">{PERIOD_LABEL[p]}</span>)}
                {daysOf(c).some((d) => d >= 6) && <span className="rounded-full bg-page px-2.5 py-1 text-xs">주말 운영</span>}</div>
              {(st.drafts > 0 || st.scheduled > 0 || st.failed > 0) && (
                <div className="flex flex-wrap gap-1">{st.drafts > 0 && <Badge tone="brand">게시 전 초안 {st.drafts}주</Badge>}{st.scheduled > 0 && <Badge tone="amber">예약 {st.scheduled}주</Badge>}{st.failed > 0 && <Badge tone="red">실패 {st.failed}주</Badge>}</div>)}
              <Button size="sm" variant={caf?.id === c.id ? 'soft' : 'outline'} aria-label={`${cafeteriaTitle(c)} 메뉴 관리`} onClick={() => { setPickedCafeteria(c.id); setTab('week') }}>메뉴 관리</Button>
            </Card>)
        })}
      </div>

      {caf && (
        <section aria-label={`${cafeteriaTitle(caf)} 관리`} className="space-y-3">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="mr-2 text-lg font-bold">{cafeteriaTitle(caf)}</h2>
            <div role="tablist" className="flex gap-1">
              {([['week', '주간 메뉴'], ['info', '식당 정보'], ['history', '게시 이력']] as const).map(([id, label]) => <Button key={id} role="tab" aria-selected={tab === id} size="sm" variant={tab === id ? 'soft' : 'outline'} onClick={() => setTab(id)}>{label}</Button>)}
            </div>
            <div className="ml-auto flex flex-wrap gap-2">
              <Button size="sm" variant="outline" onClick={() => setCafModal('edit')}><Pencil className="size-3.5" />식당 정보 수정</Button>
              {!legacy && caf.status !== 'active' && <Button size="sm" variant="soft" onClick={() => setCafAct({ c: caf, to: 'active' })}><Power className="size-3.5" />운영 중으로</Button>}
              {!legacy && caf.status === 'active' && <Button size="sm" variant="outline" onClick={() => setCafAct({ c: caf, to: 'inactive' })}><Power className="size-3.5" />비활성화</Button>}
              {!legacy && caf.status !== 'archived' && <Button size="sm" variant="outline" onClick={() => setCafAct({ c: caf, to: 'archived' })}><Archive className="size-3.5" />보관</Button>}
            </div>
          </div>
          {!legacy && caf.status !== 'active' && <p className="rounded-xl bg-page p-3 text-sm text-muted">이 식당은 {caf.status === 'inactive' ? '비활성' : '보관'} 상태라 앱에 보이지 않아요. 메뉴를 게시해 두고 준비가 되면 &lsquo;운영 중으로&rsquo;를 눌러 주세요.</p>}
          {tab === 'week' && <WeekEditor key={`${caf.id}`} cafeteria={{ id: caf.id, name: cafeteriaTitle(caf), names: [caf.name_ko, caf.name_en, caf.name_zh].filter((n): n is string => !!n), universityId: caf.university_id, universityName: caf.universities?.name_ko ?? university?.name_ko ?? '', mealPeriods: periods, operatingDays: daysOf(caf) }} week={week} onWeek={setWeek} onChanged={() => void refreshBadges()} />}
          {tab === 'info' && (
            <Card className="space-y-2 text-sm" aria-label="식당 정보">
              <div><b>대학교</b> {caf.universities?.name_ko ?? university?.name_ko}</div>
              <div><b>종류</b> {kindLabel(caf.kind)}{caf.location_description ? ` · ${caf.location_description}` : ''}</div>
              <div><b>상태</b> {legacy ? '운영 중 (상태 기능 미적용)' : CAF_STATUS[caf.status]}</div>
              <div><b>운영 식사</b> {periods.map((p) => PERIOD_LABEL[p]).join(' · ')}</div>
              <div><b>운영 요일</b> {daysOf(caf).map((d) => DAYS.find((x) => x.value === d)?.label).join(' ')}</div>
              {caf.operating_note && <div><b>운영 안내</b> {caf.operating_note}</div>}
              {caf.photo_url && <img src={caf.photo_url} alt="식당 사진" className="aspect-[16/8] w-full max-w-md rounded-xl object-cover" />}
              {(caf.name_en || caf.name_zh) && <div className="text-muted">{[caf.name_en, caf.name_zh].filter(Boolean).join(' · ')}</div>}
            </Card>)}
          {tab === 'history' && <CafeteriaHistory weeks={weeksOfCaf} onOpenWeek={(m) => { if (m) setWeek(m); setTab('week') }} />}
          {tab === 'week' && weeksOfCaf.length > 0 && <p className="text-xs text-muted">이 식당의 주간 게시 기록 {weeksOfCaf.length}주 · 마지막 게시 {formatKst(weeksOfCaf.map((w) => ov.get(w.id)?.last_published_at).filter(Boolean).sort().at(-1) ?? null)}</p>}
        </section>)}
      {!caf && listed.length > 0 && <EmptyState>식당 카드의 &lsquo;메뉴 관리&rsquo;를 누르면 한 주 메뉴를 입력할 수 있어요.</EmptyState>}

      {cafModal && (
        <CafeteriaFormModal cafeteria={cafModal === 'edit' ? caf : null} existing={all} universities={(unis.data ?? []).map((u) => ({ id: u.id, name_ko: u.name_ko }))} defaultUniversity={universityId} legacy={legacy} weekly={weekly}
          onClose={() => setCafModal(null)}
          onSaved={(id, msg, uni) => { setCafModal(null); setNotice(msg); setPickedUniversity(uni); setPickedCafeteria(id); setFilter('live') }} />)}
      {csv && <CsvImport onClose={() => setCsv(false)} onDone={() => { void qc.invalidateQueries({ queryKey: ['cafeterias'] }); void refreshBadges() }} />}
      <ConfirmDialog open={!!cafAct} busy={setCafStatus.isPending} danger={cafAct?.to === 'archived'}
        title={cafAct ? `"${cafeteriaTitle(cafAct.c)}" ${cafAct.to === 'active' ? '다시 운영 중으로?' : cafAct.to === 'inactive' ? '비활성화할까요?' : '보관할까요?'}` : ''}
        description={cafAct?.to === 'active' ? '앱의 학식 화면에 이 식당과 게시된 메뉴가 보여요.' : '앱의 학식 화면에서 이 식당과 메뉴가 숨겨져요. 메뉴 기록은 지워지지 않아요.'}
        confirmLabel={cafAct?.to === 'active' ? '운영 중으로' : cafAct?.to === 'inactive' ? '비활성화' : '보관'}
        onCancel={() => setCafAct(null)} onConfirm={() => cafAct && setCafStatus.mutate({ c: cafAct.c, to: cafAct.to })} />
    </>
  )
}
