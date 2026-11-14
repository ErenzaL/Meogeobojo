import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, CheckCircle2, RefreshCw, XCircle } from 'lucide-react'
import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Badge, Button, Card, ConfirmDialog, ErrorState, Skeleton } from '@/components/ui'
import { cmsCancelJob, cmsPublish, cmsRetryJob, cmsState, formatKst, KIND_LABEL } from '@/lib/cms'
import { basicCounts, BUILD, cmsHealth, isMissingFunction, TYPE_LABEL, TYPE_ROUTE, type CmsHealth, type HealthDraft, type HealthFailed, type HealthJob } from '@/lib/cmsHealth'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'

type Level = 'ok' | 'warn' | 'bad'
const ICON = { ok: CheckCircle2, warn: AlertTriangle, bad: XCircle } as const
const TONE = { ok: 'text-green-700', warn: 'text-amber-700', bad: 'text-red-700' } as const
const ago = (iso: string | null | undefined) => {
  if (!iso) return '기록 없음'
  const m = Math.round((Date.now() - new Date(iso).getTime()) / 60000)
  return m < 1 ? '방금 전' : m < 60 ? `${m}분 전` : m < 2880 ? `${Math.round(m / 60)}시간 전` : `${Math.round(m / 1440)}일 전`
}

/** Health checks, worst first. Each line says what is wrong and what to do about it. */
export function healthChecks(h: CmsHealth): { level: Level; title: string; detail: string }[] {
  const out: { level: Level; title: string; detail: string }[] = []
  const c = h.cron
  if (!c.available) out.push({ level: 'bad', title: '예약 게시 스케줄러 (pg_cron)', detail: 'pg_cron이 꺼져 있어요. 예약 게시가 실행되지 않아요. Supabase 대시보드 → Database → Extensions에서 pg_cron을 켜고 마이그레이션 20261115000100을 다시 실행해 주세요.' })
  else if (!c.job_found) out.push({ level: 'bad', title: '예약 게시 스케줄러 (pg_cron)', detail: "cms-run-due-jobs 작업이 등록되지 않았어요. 마이그레이션 20261115000100을 다시 실행해 등록해 주세요." })
  else if (c.active === false) out.push({ level: 'bad', title: '예약 게시 스케줄러 (pg_cron)', detail: 'cms-run-due-jobs 작업이 비활성이에요.' })
  else if (c.error) out.push({ level: 'warn', title: '예약 게시 스케줄러 (pg_cron)', detail: `작업은 있지만 실행 기록을 읽지 못했어요: ${c.error}` })
  else {
    const runs = c.recent_runs ?? []
    const failedRuns = runs.filter((r) => r.status === 'failed').length
    if (runs.length === 0) out.push({ level: 'warn', title: '예약 게시 스케줄러 (pg_cron)', detail: `${c.schedule ?? ''} 일정으로 등록됐지만 아직 실행 기록이 없어요. 1~2분 뒤 새로고침해 보세요.` })
    else if (failedRuns > 0) out.push({ level: 'warn', title: '예약 게시 스케줄러 (pg_cron)', detail: `최근 ${runs.length}번 중 ${failedRuns}번 실패했어요: ${runs.find((r) => r.status === 'failed')?.message ?? ''}` })
    else out.push({ level: 'ok', title: '예약 게시 스케줄러 (pg_cron)', detail: `${c.schedule} 일정으로 동작 중 · 마지막 성공 ${ago(c.last_success_at)}` })
  }
  if (h.jobs.overdue > 0) out.push({ level: 'bad', title: '예약 게시 지연', detail: `실행 시각이 3분 넘게 지났는데 아직 실행되지 않은 예약이 ${h.jobs.overdue}건 있어요. 스케줄러가 멈췄을 수 있어요.` })
  if (h.jobs.stuck > 0) out.push({ level: 'warn', title: '멈춘 작업', detail: `10분 넘게 실행 중인 작업이 ${h.jobs.stuck}건 있어요.` })
  if (h.jobs.failed > 0) out.push({ level: 'warn', title: '실패한 예약 게시', detail: `${h.jobs.failed}건이 실패했어요. 아래에서 원인을 확인하고 다시 시도하거나 취소해 주세요. 앱의 라이브 내용은 바뀌지 않았어요.` })
  if (!h.realtime.publication) out.push({ level: 'warn', title: '앱 실시간 갱신', detail: 'supabase_realtime이 없어요. 앱은 새로고침해야 게시된 내용을 가져와요.' })
  else if (h.realtime.missing.length > 0) out.push({ level: 'warn', title: '앱 실시간 갱신', detail: `실시간 목록에 빠진 테이블: ${h.realtime.missing.join(', ')}. 마이그레이션 20261112000100을 적용하면 앱이 새로고침 없이 갱신돼요. 지금은 앱을 새로고침해야 반영돼요.` })
  else out.push({ level: 'ok', title: '앱 실시간 갱신', detail: '앱이 게시된 내용을 실시간으로 받아요 (실패하면 새로고침으로 가져와요).' })
  if (h.guards.missing.length > 0) out.push({ level: 'bad', title: '라이브 내용 보호', detail: `게시 없이 라이브 내용을 바꿀 수 있는 곳이 있어요 (보호 장치 없음: ${h.guards.missing.join(', ')}). 마이그레이션 20261115000100을 확인해 주세요.` })
  else out.push({ level: 'ok', title: '라이브 내용 보호', detail: '라이브 내용은 게시를 통해서만 바뀌어요.' })
  if (!h.schema.cafeteria_status) out.push({ level: 'bad', title: '학식 식당 상태', detail: "campus_cafeterias.status 열이 없어요. 마이그레이션 20261113000100을 적용해 주세요 (Admin은 열이 없어도 학식을 열 수 있어요)." })
  if (!h.schema.contributions) out.push({ level: 'warn', title: '학생 기여', detail: '마이그레이션 20261114000100이 적용되지 않은 것 같아요.' })
  const rank = { bad: 0, warn: 1, ok: 2 } as const
  return out.sort((a, b) => rank[a.level] - rank[b.level])
}

function usePeople(ids: (string | null | undefined)[]) {
  const list = [...new Set(ids.filter((x): x is string => !!x))].sort()
  return useQuery({
    queryKey: ['people', list.join(',')], enabled: list.length > 0, staleTime: 5 * 60_000,
    queryFn: async () => {
      const { data } = await supabase.from('profiles').select('id,nickname').in('id', list)
      return Object.fromEntries(((data ?? []) as { id: string; nickname: string | null }[]).map((p) => [p.id, p.nickname ?? p.id.slice(0, 8)]))
    },
  })
}

const draftKey = (d: Pick<HealthDraft, 'entity_type' | 'entity_id'>) => `${d.entity_type}:${d.entity_id}`
/** A draft can be published from the list when the live content has not changed under it and it
 *  really differs from live. Others need a look first (the publish itself would refuse a stale one). */
export const canBulkPublish = (d: HealthDraft) => !d.stale && d.has_changes

/** Global publishing management: what is waiting, what is scheduled, what ran, and whether the
 *  machinery that publishes is healthy. Every action calls an existing authorized cms_* RPC. */
export default function PublishingCenter() {
  const qc = useQueryClient()
  const [notice, setNotice] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null)
  const [cancel, setCancel] = useState<HealthJob | null>(null)
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const [confirmPublish, setConfirmPublish] = useState(false)
  const health = useQuery({ queryKey: ['cms-health'], queryFn: cmsHealth, refetchInterval: 60_000, retry: false })
  const missing = isMissingFunction(health.error)
  const counts = useQuery({ queryKey: ['cms-basic-counts'], enabled: missing, queryFn: basicCounts, retry: false })
  const h = health.data
  const people = usePeople([...(h?.drafts.map((d) => d.updated_by) ?? []), ...(h?.scheduled.map((d) => d.created_by) ?? []), ...(h?.failed.map((d) => d.created_by) ?? []), ...(h?.recent.map((d) => d.published_by) ?? [])])
  const who = (u: string | null | undefined) => (u ? people.data?.[u] ?? u.slice(0, 8) : '—')
  const refresh = async () => { await qc.invalidateQueries({ queryKey: ['cms-health'] }); await qc.invalidateQueries({ queryKey: ['cms-overview'] }); await qc.invalidateQueries({ queryKey: ['cms'] }) }
  const cancelJob = useMutation({
    mutationFn: (j: HealthJob) => cmsCancelJob(j.id, '예약 취소'),
    onSuccess: async () => { setCancel(null); setNotice({ tone: 'ok', text: '예약을 취소했어요. 라이브 내용은 바뀌지 않았어요.' }); await refresh() },
    onError: (e) => { setCancel(null); setNotice({ tone: 'bad', text: errorMessage(e) }) },
  })
  const retryJob = useMutation({
    mutationFn: (j: HealthFailed) => cmsRetryJob(j.id),
    onSuccess: async () => { setNotice({ tone: 'ok', text: '다시 시도하도록 예약했어요. 1분 안에 서버가 실행해요.' }); await refresh() },
    onError: (e) => setNotice({ tone: 'bad', text: errorMessage(e) }),
  })
  const dropFailed = useMutation({
    mutationFn: (j: HealthFailed) => cmsCancelJob(j.id, '실패한 예약 취소'),
    onSuccess: async () => { setNotice({ tone: 'ok', text: '실패한 예약을 취소했어요.' }); await refresh() },
    onError: (e) => setNotice({ tone: 'bad', text: errorMessage(e) }),
  })

  // Publishes one draft at a time with its current revision, so one failure never blocks the rest.
  const publishDrafts = useMutation({
    mutationFn: async ({ drafts, reason }: { drafts: HealthDraft[]; reason: string }) => {
      const failed: { draft: HealthDraft; message: string }[] = []
      let done = 0
      for (const d of drafts) {
        try {
          const st = await cmsState(d.entity_type, d.entity_id)
          if (!st.draft) throw new Error('게시할 초안이 없어요')
          await cmsPublish(d.entity_type, d.entity_id, st.draft.revision, reason)
          done++
        } catch (e) { failed.push({ draft: d, message: errorMessage(e) }) }
      }
      return { done, failed }
    },
    onSuccess: async ({ done, failed }) => {
      setConfirmPublish(false)
      setPicked(new Set(failed.map((f) => draftKey(f.draft))))
      setNotice(failed.length === 0
        ? { tone: 'ok', text: `초안 ${done}건을 게시했어요. 앱과 웹에 바로 반영돼요.` }
        : { tone: 'bad', text: `${done}건을 게시했고 ${failed.length}건은 게시하지 못했어요. ${failed.map((f) => `${f.draft.label}: ${f.message}`).join(' / ')}` })
      await refresh()
    },
    onError: (e) => { setConfirmPublish(false); setNotice({ tone: 'bad', text: errorMessage(e) }) },
  })
  const publishable = h?.drafts.filter(canBulkPublish) ?? []
  const chosen = publishable.filter((d) => picked.has(draftKey(d)))
  const allChosen = publishable.length > 0 && chosen.length === publishable.length
  const toggle = (d: HealthDraft) => setPicked((p) => { const n = new Set(p); if (n.has(draftKey(d))) n.delete(draftKey(d)); else n.add(draftKey(d)); return n })

  return (
    <section aria-label="게시 관리" className="mt-8 space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-bold">게시 관리</h2>
          <p className="text-sm text-muted">저장한 초안, 예약된 게시, 최근 게시와 게시 시스템의 상태를 한곳에서 봐요. 게시·예약은 각 관리 화면 오른쪽 위의 게시 도구에서 해요.</p>
        </div>
        <Button variant="outline" size="sm" disabled={health.isFetching} onClick={() => void refresh()}><RefreshCw className="size-4" />새로고침</Button>
      </div>

      <Card aria-label="콘텐츠 게시와 코드 배포" className="space-y-2 text-sm">
        <h3 className="font-bold">콘텐츠 게시 ≠ 코드 배포</h3>
        <ul className="list-disc space-y-1 pl-5 text-muted">
          <li><b className="text-ink">콘텐츠 게시</b>: 식당·메뉴·사진·미션·공지 같은 내용이에요. Supabase에 저장되고, 게시하면 앱과 웹이 <b>다시 빌드하지 않아도</b> 새로고침만으로 반영돼요.</li>
          <li><b className="text-ink">코드 배포</b>: 관리자·앱 화면 자체가 바뀌는 것이에요. GitHub에 올린 코드를 Render가 빌드해서 배포해요. 새 기능 화면은 배포해야 보여요.</li>
        </ul>
        <div className="rounded-xl bg-page p-3 text-xs">
          지금 열려 있는 관리자 코드: <code>{BUILD.commit === 'unknown' ? '알 수 없음' : BUILD.commit.slice(0, 7)}</code>{BUILD.builtAt && <> · 빌드 {formatKst(BUILD.builtAt)}</>}
          <br />Render의 서비스 화면에 표시된 커밋과 같은지 확인하세요. 다르면 아직 새 코드가 배포되지 않은 거예요.
        </div>
      </Card>

      {notice && <p role={notice.tone === 'bad' ? 'alert' : 'status'} className={`rounded-xl p-3 text-sm ${notice.tone === 'bad' ? 'bg-amber-50 text-amber-900' : 'bg-brand/30'}`}>{notice.text}</p>}
      {health.isLoading && <Skeleton className="h-40 w-full" />}
      {health.error && !missing && <ErrorState error={health.error} onRetry={() => void health.refetch()} />}
      {missing && (
        <Card role="alert" className="space-y-2 border-amber-300 bg-amber-50 text-sm text-amber-900">
          <p><b>게시 현황 보기(cms_health)가 아직 데이터베이스에 없어요.</b> 마이그레이션 <b>20261116000100</b>을 적용하면 초안·예약·최근 게시·스케줄러 상태를 여기서 볼 수 있어요. 게시 기능 자체는 이것 없이도 동작해요.</p>
          {counts.data && <p>현재 초안 {counts.data.drafts}건 · 예약 {counts.data.scheduled}건 · 실패 {counts.data.failed}건 · 게시 이력 {counts.data.versions}건</p>}
        </Card>)}

      {h && (
        <>
          <Card aria-label="동기화 상태" className="space-y-3">
            <div className="flex flex-wrap items-center gap-2"><h3 className="font-bold">동기화 상태</h3>
              {(() => { const worst = healthChecks(h)[0]?.level ?? 'ok'; return <Badge tone={worst === 'ok' ? 'green' : worst === 'warn' ? 'amber' : 'red'}>{worst === 'ok' ? '정상' : worst === 'warn' ? '확인 필요' : '문제 있음'}</Badge> })()}
              <span className="text-xs text-muted">{formatKst(h.generated_at)} 기준</span></div>
            <ul className="space-y-2 text-sm">
              {healthChecks(h).map((c) => { const I = ICON[c.level]; return <li key={c.title} className="flex items-start gap-2"><I className={`mt-0.5 size-4 shrink-0 ${TONE[c.level]}`} /><span><b>{c.title}</b> <span className="text-muted">{c.detail}</span></span></li> })}
            </ul>
            <p className="text-xs text-muted">다음 예약: {h.jobs.next_run_at ? formatKst(h.jobs.next_run_at) : '없음'} · 마지막 실행: {ago(h.jobs.last_executed_at)}</p>
          </Card>

          <Card aria-label="게시되지 않은 초안" className="space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h3 className="font-bold">게시되지 않은 초안 <span className="text-sm font-normal text-muted">{h.drafts.length}건</span></h3>
              {publishable.length > 0 && (
                <span className="flex flex-wrap items-center gap-2">
                  <label className="flex items-center gap-1.5 text-sm">
                    <input type="checkbox" className="size-4 accent-brand-strong" checked={allChosen} onChange={() => setPicked(allChosen ? new Set() : new Set(publishable.map(draftKey)))} />
                    전체 선택
                  </label>
                  <Button size="sm" disabled={chosen.length === 0 || publishDrafts.isPending} onClick={() => setConfirmPublish(true)}>
                    {chosen.length > 0 ? `선택한 ${chosen.length}건 게시` : '선택해서 게시'}
                  </Button>
                  <Button size="sm" variant="outline" disabled={publishDrafts.isPending} onClick={() => { setPicked(new Set(publishable.map(draftKey))); setConfirmPublish(true) }}>
                    모두 게시 ({publishable.length}건)
                  </Button>
                </span>)}
            </div>
            {h.drafts.length === 0 && <p className="text-sm text-muted">대기 중인 초안이 없어요.</p>}
            {h.drafts.length > 0 && <p className="text-xs text-muted">게시하면 앱과 웹에 바로 반영돼요. 라이브가 바뀌었거나 라이브와 같은 초안은 선택할 수 없어요. 열어서 확인해 주세요.</p>}
            <ul className="divide-y divide-line text-sm">
              {h.drafts.map((d) => (
                <li key={draftKey(d)} className="flex flex-wrap items-center justify-between gap-2 py-2">
                  <span className="flex items-center gap-2">
                    <input type="checkbox" className="size-4 accent-brand-strong" aria-label={`${d.label} 선택`} disabled={!canBulkPublish(d) || publishDrafts.isPending}
                      checked={canBulkPublish(d) && picked.has(draftKey(d))} onChange={() => toggle(d)} />
                    <span><Badge tone="neutral">{TYPE_LABEL[d.entity_type]}</Badge> <b>{d.label}</b> {d.stale && <Badge tone="amber">라이브가 바뀌었어요</Badge>} {!d.has_changes && <Badge tone="neutral">라이브와 같음</Badge>}
                      <span className="ml-2 text-xs text-muted">{formatKst(d.updated_at)} · {who(d.updated_by)}</span></span>
                  </span>
                  <Link className="text-sm font-semibold text-brand-strong underline" to={TYPE_ROUTE(d.entity_type, d.entity_id)}>열어서 게시하기</Link>
                </li>))}
            </ul>
          </Card>

          <Card aria-label="예약된 게시" className="space-y-2">
            <h3 className="font-bold">예약된 게시 <span className="text-sm font-normal text-muted">{h.scheduled.length}건</span></h3>
            {h.scheduled.length === 0 && <p className="text-sm text-muted">예약된 게시가 없어요.</p>}
            <ul className="divide-y divide-line text-sm">
              {h.scheduled.map((j) => (
                <li key={j.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
                  <span><Badge tone="neutral">{TYPE_LABEL[j.entity_type]}</Badge> <b>{j.label}</b> <Badge tone={j.overdue ? 'red' : 'amber'}>{j.action === 'unpublish' ? '게시 종료' : '게시'} {formatKst(j.run_at)}</Badge>
                    {j.overdue && <Badge tone="red">지연</Badge>} {j.unpublish_at && <span className="text-xs text-muted">종료 {formatKst(j.unpublish_at)}</span>}
                    <span className="ml-2 text-xs text-muted">{who(j.created_by)}{j.reason ? ` · ${j.reason}` : ''}</span></span>
                  <span className="flex items-center gap-2">
                    <Link className="text-sm font-semibold text-brand-strong underline" to={TYPE_ROUTE(j.entity_type, j.entity_id)}>열기</Link>
                    {j.status === 'scheduled' && <Button size="sm" variant="outline" onClick={() => setCancel(j)}>예약 취소</Button>}
                  </span>
                </li>))}
            </ul>
          </Card>

          {h.failed.length > 0 && (
            <Card aria-label="실패한 예약" className="space-y-2 border-red-200">
              <h3 className="font-bold text-red-800">실패한 예약 <span className="text-sm font-normal">{h.failed.length}건</span></h3>
              <ul className="divide-y divide-line text-sm">
                {h.failed.map((j) => (
                  <li key={j.id} className="space-y-1 py-2">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span><Badge tone="neutral">{TYPE_LABEL[j.entity_type]}</Badge> <b>{j.label}</b> <span className="text-xs text-muted">{formatKst(j.run_at)} · 시도 {j.attempts}회 · {who(j.created_by)}</span></span>
                      <span className="flex items-center gap-2">
                        <Link className="text-sm font-semibold text-brand-strong underline" to={TYPE_ROUTE(j.entity_type, j.entity_id)}>열기</Link>
                        <Button size="sm" disabled={retryJob.isPending} onClick={() => retryJob.mutate(j)}>다시 시도</Button>
                        <Button size="sm" variant="outline" disabled={dropFailed.isPending} onClick={() => dropFailed.mutate(j)}>취소</Button>
                      </span>
                    </div>
                    <p className="rounded-lg bg-red-50 p-2 text-xs text-red-800">{j.last_error ?? '원인 기록 없음'}</p>
                  </li>))}
              </ul>
            </Card>)}

          <Card aria-label="최근 게시" className="space-y-2">
            <h3 className="font-bold">최근 게시 <span className="text-sm font-normal text-muted">최근 {h.recent.length}건</span></h3>
            {h.recent.length === 0 && <p className="text-sm text-muted">아직 게시한 적이 없어요.</p>}
            <ul className="divide-y divide-line text-sm">
              {h.recent.map((r) => (
                <li key={`${r.entity_type}:${r.entity_id}:${r.version}`} className="flex flex-wrap items-center justify-between gap-2 py-2">
                  <span><Badge tone="neutral">{TYPE_LABEL[r.entity_type]}</Badge> <b>{r.label}</b> <Badge tone="brand">v{r.version} · {KIND_LABEL[r.kind as keyof typeof KIND_LABEL] ?? r.kind}</Badge>
                    {r.job_id && <Badge tone="amber">예약 실행</Badge>}
                    <span className="ml-2 text-xs text-muted">{formatKst(r.published_at)} · {who(r.published_by)}{r.reason ? ` · ${r.reason}` : ''}</span></span>
                  <Link className="text-sm font-semibold text-brand-strong underline" to={TYPE_ROUTE(r.entity_type, r.entity_id)}>이력·복원</Link>
                </li>))}
            </ul>
          </Card>
        </>)}

      <ConfirmDialog open={confirmPublish} busy={publishDrafts.isPending} title={`초안 ${chosen.length}건을 게시할까요?`}
        description={`${chosen.slice(0, 5).map((d) => d.label).join(', ')}${chosen.length > 5 ? ` 외 ${chosen.length - 5}건` : ''} — 앱과 웹에 바로 반영돼요. 이전 버전은 각 화면의 게시 이력에서 복원할 수 있어요.`}
        confirmLabel={`${chosen.length}건 게시`} onCancel={() => setConfirmPublish(false)}
        onConfirm={() => publishDrafts.mutate({ drafts: chosen, reason: '설정에서 초안 일괄 게시' })} />
      <ConfirmDialog open={!!cancel} busy={cancelJob.isPending} title="예약을 취소할까요?" description={cancel ? `${cancel.label} — ${formatKst(cancel.run_at)} 게시가 취소돼요. 라이브 내용은 바뀌지 않고, 초안은 그대로 남아요.` : undefined}
        confirmLabel="예약 취소" danger onCancel={() => setCancel(null)} onConfirm={() => cancel && cancelJob.mutate(cancel)} />
    </section>
  )
}
