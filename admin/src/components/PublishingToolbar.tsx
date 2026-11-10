import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, CalendarClock, Eye, History, RotateCcw, Save, Send, Undo2, XCircle } from 'lucide-react'
import { useState } from 'react'
import { Badge, Button, ConfirmDialog, EmptyState, ErrorState, Field, Input, Modal, Skeleton, Textarea } from '@/components/ui'
import {
  cmsCancelJob, cmsPublish, cmsRebaseDraft, cmsReschedule, cmsRetryJob, cmsRollback, cmsSchedule, cmsUnpublish, cmsVersions, diffSnapshots, formatKst,
  isConflict, isLiveVisible, isoToKst, JOB_LABEL, KIND_LABEL, kstToIso, showValue, type Change, type CmsState, type EntityType, type Job,
} from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'

const VIS_LABEL: Record<string, string> = { draft: '초안', published: '공개', hidden: '숨김', archived: '보관', closed: '운영 안 함', no_menu: '메뉴 없음' }
const short = (id: string | null) => (id ? id.slice(0, 8) : '—')

/** Display names for admin user ids (profiles are readable by admins). */
function usePeople(ids: (string | null | undefined)[]) {
  const list = [...new Set(ids.filter((x): x is string => !!x))]
  return useQuery({
    queryKey: ['people', list.join(',')], enabled: list.length > 0, staleTime: 5 * 60_000,
    queryFn: async () => {
      const { data } = await supabase.from('profiles').select('id,nickname').in('id', list)
      return Object.fromEntries(((data ?? []) as { id: string; nickname: string | null }[]).map((p) => [p.id, p.nickname ?? short(p.id)]))
    },
  })
}

function ChangeList({ changes }: { changes: Change[] }) {
  if (changes.length === 0) return <p className="rounded-xl bg-page p-3 text-sm text-muted">라이브와 같은 내용이에요. 바뀌는 항목이 없어요.</p>
  return (
    <ul aria-label="바뀌는 항목" className="max-h-56 space-y-1.5 overflow-auto rounded-xl bg-page p-3 text-sm">
      {changes.map((c) => (
        <li key={c.key}><b>{c.label}</b>: <span className="text-muted line-through">{showValue(c.from)}</span> → <span>{showValue(c.to)}</span></li>))}
    </ul>)
}

type Props = {
  type: EntityType; id: string; state: CmsState | undefined; loading: boolean; error: unknown
  /** The form has unsaved edits. */ dirty: boolean; saving: boolean
  onSaveDraft: () => void; onPreview: () => void; onChanged: () => Promise<unknown> | void; onConflict: () => void
  /** Shown above the buttons: save errors, etc. */ message?: { tone: 'ok' | 'bad'; text: string } | null
}

/** The publishing toolbar: status + Save Draft / Preview / Publish now / Schedule /
 *  Cancel schedule / Unpublish / Restore / History. Every rule is enforced by the
 *  database; this only drives it and explains the result. */
export default function PublishingToolbar({ type, id, state, loading, error, dirty, saving, onSaveDraft, onPreview, onChanged, onConflict, message }: Props) {
  const qc = useQueryClient()
  const [modal, setModal] = useState<'publish' | 'schedule' | 'unpublish' | null>(null)
  const [historyOpen, setHistoryOpen] = useState(false)
  const [note, setNote] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null)
  const [reason, setReason] = useState('')
  const [sched, setSched] = useState({ date: '', time: '07:00', endOn: false, endDate: '', endTime: '23:00' })
  const [rollbackTo, setRollbackTo] = useState<number | null>(null)
  const [rescheduling, setRescheduling] = useState<Job | null>(null)
  const [openedAt, setOpenedAt] = useState(0) // when the schedule dialog opened (the minimum lead time is checked against it; the server re-checks)

  const draft = state?.draft ?? null
  const scheduled = state?.jobs.find((j) => j.action === 'publish' && j.status === 'scheduled') ?? null
  const failed = state?.jobs.filter((j) => j.status === 'failed') ?? []
  const changes = draft ? diffSnapshots(state!.live, draft.data) : []
  const people = usePeople([state?.last_published?.by, draft?.updated_by, ...(state?.jobs.map((j) => j.created_by) ?? [])])
  const who = (u: string | null | undefined) => (u ? people.data?.[u] ?? short(u) : '—')
  const canAct = !!draft && !dirty && !saving && !draft.stale

  const done = async (text: string) => {
    setNote({ tone: 'ok', text }); setModal(null); setReason(''); setRollbackTo(null); setRescheduling(null)
    await onChanged(); await qc.invalidateQueries({ queryKey: ['cms-versions', type, id] }); await qc.invalidateQueries({ queryKey: ['restaurants'] })
  }
  const fail = (e: unknown) => {
    if (isConflict(e)) { setModal(null); setNote({ tone: 'bad', text: errorMessage(e) }); onConflict() } else setNote({ tone: 'bad', text: errorMessage(e) })
  }

  const publish = useMutation({ mutationFn: () => cmsPublish(type, id, draft!.revision, reason), onSuccess: (v) => done(`버전 ${v}을 게시했어요. 앱에서 새로고침하면 바로 보여요.`), onError: fail })
  const schedule = useMutation({
    mutationFn: () => {
      const run = kstToIso(sched.date, sched.time)
      const end = sched.endOn ? kstToIso(sched.endDate, sched.endTime) : null
      return cmsSchedule(type, id, draft!.revision, run, end, reason)
    },
    onSuccess: () => done('게시를 예약했어요. 서버가 그 시각에 자동으로 게시해요 (이 화면을 닫아도 돼요).'), onError: fail,
  })
  const unpublish = useMutation({ mutationFn: (r: string) => cmsUnpublish(type, id, r), onSuccess: (v) => done(`게시를 중단했어요 (버전 ${v}). 앱에서 숨겨져요. 내용은 지워지지 않고 이력에 남아요.`), onError: fail })
  const cancel = useMutation({ mutationFn: (j: Job) => cmsCancelJob(j.id, '예약 취소'), onSuccess: () => done('예약을 취소했어요. 라이브는 바뀌지 않았어요.'), onError: fail })
  const retry = useMutation({ mutationFn: (j: Job) => cmsRetryJob(j.id), onSuccess: () => done('다시 시도하도록 예약했어요. 1분 안에 서버가 실행해요.'), onError: fail })
  const rebase = useMutation({ mutationFn: () => cmsRebaseDraft(type, id, draft!.revision), onSuccess: () => done('초안을 최신 라이브 기준으로 맞췄어요. 이제 게시할 수 있어요.'), onError: fail })
  const rollback = useMutation({ mutationFn: (r: string) => cmsRollback(type, id, rollbackTo!, r), onSuccess: (v) => done(`이전 버전을 새 버전 ${v}으로 복원했어요.`), onError: fail })
  const resched = useMutation({
    mutationFn: () => cmsReschedule(rescheduling!.id, kstToIso(sched.date, sched.time), sched.endOn ? kstToIso(sched.endDate, sched.endTime) : null),
    onSuccess: () => done('예약 시간을 바꿨어요.'), onError: fail,
  })

  const openSchedule = () => { setOpenedAt(Date.now()); setSched({ date: '', time: '07:00', endOn: false, endDate: '', endTime: '23:00' }); setReason(''); setModal('schedule') }
  const schedError = (() => {
    if (!sched.date || !/^\d{2}:\d{2}$/.test(sched.time)) return '게시 날짜와 시간을 선택해 주세요'
    try {
      const run = new Date(kstToIso(sched.date, sched.time)).getTime()
      if (run < openedAt + 60_000) return '예약 시각은 지금부터 1분 이후여야 해요'
      if (sched.endOn) {
        if (!sched.endDate) return '게시 종료 날짜를 선택해 주세요'
        if (new Date(kstToIso(sched.endDate, sched.endTime)).getTime() <= run) return '게시 종료 시각은 게시 시각보다 늦어야 해요'
      }
    } catch { return '날짜와 시간 형식이 올바르지 않아요' }
    return null
  })()

  if (loading) return <Skeleton className="mb-5 h-24 w-full" />
  if (error) return <div className="mb-5"><ErrorState error={error as Error} /></div>
  if (!state) return null
  const visible = isLiveVisible(type, state.live)
  const vis = type === 'restaurant_menus' ? (visible ? 'published' : 'no_menu') : String(state.live.visibility ?? state.live.status ?? '')
  const msg = message ?? note

  return (
    <section aria-label="게시 도구" className="mb-6 space-y-3 rounded-2xl border border-line bg-white p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <dl className="grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2" aria-label="게시 상태">
          <div className="flex items-center gap-2"><dt className="text-muted">라이브</dt><dd><Badge tone={visible ? 'green' : vis === 'draft' ? 'neutral' : 'amber'}>{VIS_LABEL[vis] ?? vis}</Badge> <span className="text-muted">v{state.live_version}</span></dd></div>
          <div className="flex items-center gap-2"><dt className="text-muted">초안</dt><dd>{draft ? (draft.has_changes ? <Badge tone="brand">게시되지 않은 변경 {changes.length}건</Badge> : <Badge tone="neutral">라이브와 같음</Badge>) : <Badge tone="neutral">없음</Badge>}{dirty && <span className="ml-2 text-xs text-amber-700">저장하지 않은 수정</span>}</dd></div>
          <div className="flex gap-2"><dt className="text-muted">마지막 저장</dt><dd>{draft ? `${formatKst(draft.updated_at)} · ${who(draft.updated_by)}` : '—'}</dd></div>
          <div className="flex gap-2"><dt className="text-muted">마지막 게시</dt><dd>{state.last_published ? `${formatKst(state.last_published.at)} · ${who(state.last_published.by)} (${KIND_LABEL[state.last_published.kind as keyof typeof KIND_LABEL] ?? state.last_published.kind})` : '게시한 적 없음'}</dd></div>
          {scheduled && <div className="flex gap-2 sm:col-span-2"><dt className="text-muted">예약</dt><dd><Badge tone="amber">{formatKst(scheduled.run_at)}</Badge>{scheduled.unpublish_at && <span className="ml-2 text-xs text-muted">종료 {formatKst(scheduled.unpublish_at)}</span>} <span className="text-xs text-muted">· {who(scheduled.created_by)}</span></dd></div>}
        </dl>
        <div className="flex flex-wrap justify-end gap-2">
          <Button variant="outline" onClick={onSaveDraft} disabled={saving || (!dirty && !!draft)}><Save className="size-4" />{saving ? '저장 중…' : '초안 저장'}</Button>
          <Button variant="outline" onClick={onPreview} disabled={!draft || dirty} title={dirty ? '먼저 초안을 저장해 주세요' : undefined}><Eye className="size-4" />미리보기</Button>
          <Button onClick={() => { setReason(''); setModal('publish') }} disabled={!canAct || !!scheduled} title={scheduled ? '예약을 취소한 뒤 지금 게시할 수 있어요' : undefined}><Send className="size-4" />지금 게시</Button>
          <Button variant="soft" onClick={openSchedule} disabled={!canAct || !!scheduled}><CalendarClock className="size-4" />예약 게시</Button>
          {scheduled && <Button variant="outline" onClick={() => cancel.mutate(scheduled)} disabled={cancel.isPending}><XCircle className="size-4" />예약 취소</Button>}
          {visible && <Button variant="outline" onClick={() => { setReason(''); setModal('unpublish') }}><Undo2 className="size-4" />게시 중단</Button>}
          <Button variant="ghost" onClick={() => setHistoryOpen((o) => !o)} aria-expanded={historyOpen}><History className="size-4" />게시 이력</Button>
        </div>
      </div>
      {draft?.stale && (
        <p role="alert" className="flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900"><AlertTriangle className="mt-0.5 size-4 shrink-0" />이 초안을 만든 뒤 라이브 내용이 바뀌었어요 (다른 관리자의 게시, 복원 또는 중단). 게시하려면 초안을 최신 라이브 기준으로 다시 맞춰야 해요.
          <Button size="sm" variant="outline" className="ml-auto" disabled={rebase.isPending} onClick={() => rebase.mutate()}>최신 기준으로 맞추기</Button></p>)}
      {failed.length > 0 && <p role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-800">예약 게시 {failed.length}건이 실패했어요. 아래 &lsquo;게시 이력&rsquo;에서 원인을 확인하고 다시 시도하거나 취소해 주세요.</p>}
      {msg && <p role={msg.tone === 'bad' ? 'alert' : 'status'} className={`rounded-xl p-3 text-sm ${msg.tone === 'bad' ? 'bg-amber-50 text-amber-900' : 'bg-brand/30'}`}>{msg.text}</p>}
      {historyOpen && <History2 type={type} id={id} state={state} who={who} onRollback={(v) => { setReason(''); setRollbackTo(v) }} onRetry={(j) => retry.mutate(j)} onCancel={(j) => cancel.mutate(j)} onReschedule={(j) => { setOpenedAt(Date.now()); const r = isoToKst(j.run_at); const e = j.unpublish_at ? isoToKst(j.unpublish_at) : null; setSched({ date: r.date, time: r.time, endOn: !!e, endDate: e?.date ?? '', endTime: e?.time ?? '23:00' }); setRescheduling(j) }} />}

      <Modal open={modal === 'publish'} title="지금 게시할까요?" onClose={() => setModal(null)}>
        <div className="space-y-3">
          <p className="text-sm text-muted">게시하면 앱 사용자에게 바로 보여요 (새로고침하면 반영돼요). 이전 버전은 이력에 남아 언제든 복원할 수 있어요.</p>
          <ChangeList changes={changes} />
          <Field label="게시 메모 (선택)" htmlFor="pub_reason"><Textarea id="pub_reason" className="min-h-16" value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
          <div className="flex justify-end gap-2"><Button variant="outline" onClick={() => setModal(null)} disabled={publish.isPending}>취소</Button><Button onClick={() => publish.mutate()} disabled={publish.isPending}>지금 게시</Button></div>
        </div>
      </Modal>

      <Modal open={modal === 'schedule' || !!rescheduling} title={rescheduling ? '예약 시간 바꾸기' : '예약 게시'} onClose={() => { setModal(null); setRescheduling(null) }}>
        <div className="space-y-3">
          {!rescheduling && <><p className="text-sm text-muted">지금 저장된 초안이 그대로 예약돼요. 예약한 뒤에 초안을 더 고쳐도 예약된 내용은 바뀌지 않아요. 서버가 정해진 시각에 게시하므로 이 화면을 닫아도 돼요.</p><ChangeList changes={changes} /></>}
          <div className="grid grid-cols-2 gap-3">
            <Field label="게시 날짜" htmlFor="sc_date"><Input id="sc_date" type="date" value={sched.date} onChange={(e) => setSched({ ...sched, date: e.target.value })} /></Field>
            <Field label="게시 시간" htmlFor="sc_time"><Input id="sc_time" type="time" value={sched.time} onChange={(e) => setSched({ ...sched, time: e.target.value })} /></Field>
          </div>
          <p className="text-xs text-muted">시간대: Asia/Seoul (KST, UTC+9). 데이터베이스에는 UTC로 저장돼요.</p>
          <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={sched.endOn} onChange={(e) => setSched({ ...sched, endOn: e.target.checked })} />게시 종료 시각도 정하기 (자동으로 앱에서 숨겨요)</label>
          {sched.endOn && (
            <div className="grid grid-cols-2 gap-3">
              <Field label="종료 날짜" htmlFor="sc_end_date"><Input id="sc_end_date" type="date" value={sched.endDate} onChange={(e) => setSched({ ...sched, endDate: e.target.value })} /></Field>
              <Field label="종료 시간" htmlFor="sc_end_time"><Input id="sc_end_time" type="time" value={sched.endTime} onChange={(e) => setSched({ ...sched, endTime: e.target.value })} /></Field>
            </div>)}
          {!rescheduling && <Field label="메모 (선택)" htmlFor="sc_reason"><Textarea id="sc_reason" className="min-h-14" value={reason} onChange={(e) => setReason(e.target.value)} /></Field>}
          {schedError && <p className="text-xs text-red-600">{schedError}</p>}
          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => { setModal(null); setRescheduling(null) }}>취소</Button>
            <Button disabled={!!schedError || schedule.isPending || resched.isPending} onClick={() => (rescheduling ? resched.mutate() : schedule.mutate())}>{rescheduling ? '시간 바꾸기' : '예약하기'}</Button>
          </div>
        </div>
      </Modal>

      <ConfirmDialog open={modal === 'unpublish'} askReason danger busy={unpublish.isPending} title="게시를 중단할까요?"
        description="앱에서 이 항목이 숨겨져요 (식단은 초안 상태가 돼요). 내용은 지워지지 않고, 이력에서 다시 복원할 수 있어요."
        confirmLabel="게시 중단" onCancel={() => setModal(null)} onConfirm={(r) => unpublish.mutate(r)} />
      <ConfirmDialog open={rollbackTo !== null} askReason busy={rollback.isPending} title={`버전 ${rollbackTo}으로 복원할까요?`}
        description="그 버전의 내용이 새 버전으로 게시돼요. 이후 버전은 이력에 그대로 남아요."
        confirmLabel="복원" onCancel={() => setRollbackTo(null)} onConfirm={(r) => rollback.mutate(r)} />
    </section>
  )
}

function History2({ type, id, state, who, onRollback, onRetry, onCancel, onReschedule }: {
  type: EntityType; id: string; state: CmsState; who: (u: string | null | undefined) => string
  onRollback: (v: number) => void; onRetry: (j: Job) => void; onCancel: (j: Job) => void; onReschedule: (j: Job) => void
}) {
  const q = useQuery({ queryKey: ['cms-versions', type, id], queryFn: () => cmsVersions(type, id) })
  const jobs = state.jobs.filter((j) => j.status !== 'published' || j.action === 'publish')
  return (
    <div aria-label="게시 이력" className="space-y-4 border-t border-line pt-3">
      {jobs.length > 0 && (
        <div className="space-y-2">
          <h3 className="text-sm font-bold">예약</h3>
          {jobs.map((j) => (
            <div key={j.id} className="flex flex-wrap items-center gap-2 rounded-xl border border-line p-2 text-sm">
              <Badge tone={j.status === 'failed' ? 'red' : j.status === 'scheduled' ? 'amber' : j.status === 'published' ? 'green' : 'neutral'}>{JOB_LABEL[j.status]}</Badge>
              <span>{j.action === 'publish' ? '게시' : '게시 종료'} · {formatKst(j.run_at)}</span>
              <span className="text-xs text-muted">{who(j.created_by)}{j.reason ? ` · ${j.reason}` : ''}</span>
              {j.status === 'failed' && <span className="basis-full text-xs text-red-700">원인: {j.last_error}</span>}
              <span className="ml-auto flex gap-2">
                {j.status === 'failed' && <Button size="sm" variant="outline" onClick={() => onRetry(j)}><RotateCcw className="size-3.5" />다시 시도</Button>}
                {j.status === 'scheduled' && j.action === 'publish' && <Button size="sm" variant="outline" onClick={() => onReschedule(j)}>시간 변경</Button>}
                {(j.status === 'scheduled' || j.status === 'failed') && <Button size="sm" variant="ghost" onClick={() => onCancel(j)}>취소</Button>}
              </span>
            </div>))}
        </div>)}
      <div className="space-y-2">
        <h3 className="text-sm font-bold">버전</h3>
        {q.isLoading && <Skeleton className="h-16 w-full" />}
        {q.error && <ErrorState error={q.error} onRetry={() => void q.refetch()} />}
        {q.data?.length === 0 && <EmptyState>아직 게시한 적이 없어요. 게시하면 여기에 버전이 쌓여요.</EmptyState>}
        {q.data?.map((v) => (
          <div key={v.id} className="flex flex-wrap items-center gap-2 rounded-xl border border-line p-2 text-sm">
            <Badge tone="brand">v{v.version}</Badge><span>{KIND_LABEL[v.kind]}{v.rolled_back_from ? ` (v${v.rolled_back_from}에서)` : ''}</span>
            <span className="text-xs text-muted">{formatKst(v.published_at)} · {who(v.published_by)}{v.reason ? ` · ${v.reason}` : ''}</span>
            {v.version !== state.live_version && <Button size="sm" variant="outline" className="ml-auto" onClick={() => onRollback(v.version)}><RotateCcw className="size-3.5" />이 버전으로 복원</Button>}
            {v.version === state.live_version && <Badge tone="green">현재 라이브</Badge>}
          </div>))}
      </div>
    </div>
  )
}
