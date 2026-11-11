import { useQueryClient } from '@tanstack/react-query'
import { CloudDownload } from 'lucide-react'
import { useRef, useState } from 'react'
import { Badge, Button, Card, Field, Select } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import { chunk, collectKakaoPlaces, KAKAO_QUERIES, type KakaoDoc, withinRadius } from './kakao'
import { describeError, type ImportStage, type FnProbe, probeFunction, redact, statusOf } from './kakaoDiag'
import type { Campus } from './kakaoGeo'
import { clearJob, hasUnfinishedWork, jobMatchesCampus, jobSummary, loadJob, saveJob } from './kakaoJobStore'
import { type JobState, makeSupabaseSearch, newJob, newMemory, type Progress, runJob, type ScanMemory, type ScanResult } from './kakaoScan'

type Uni = { id: string; name_ko: string; is_active: boolean; latitude?: number | null; longitude?: number | null; search_radius_m?: number | null }
type Managed = Record<string, { visibility: string }>
/** What the preview needs to say about how the places were found. */
type Report =
  | { kind: 'grid'; scan: ScanResult }
  | { kind: 'legacy'; outside: number; failed: string[]; why: string }
type Stage =
  | { s: 'idle' }
  | { s: 'collecting'; progress: Progress | null; legacy: { done: number; total: number } | null; cancelling: boolean; note?: string }
  | { s: 'preview'; campus: Campus; places: KakaoDoc[]; managed: Managed; report: Report }
  | { s: 'saving' }
  | { s: 'done'; text: string }
  | { s: 'error'; text: string; hint?: string }
type RunMode = 'new' | 'resume-stored' | 'continue-session'

const MISSING_FN = /admin_register_kakao_places|PGRST202|42883|schema cache/i
const STATUS_LABEL: Record<string, string> = { draft: '초안', published: '공개', hidden: '숨김', archived: '보관' }
const FAIL_LABEL: Record<string, string> = { rate_limited: '요청 제한(429)', unavailable: '카카오 응답 없음', network: '네트워크', timeout: '시간 초과', rejected: '거절됨', not_deployed: '함수 미배포', forbidden: '권한 없음', aborted: '중단' }
const FUNCTION = 'admin_kakao_search'

const env = import.meta.env as Record<string, string | undefined>
/** Is the function on this project? (Only when the Admin is configured with a project URL and key; otherwise assume yes.) */
const defaultProbe = (): Promise<FnProbe> =>
  env.VITE_SUPABASE_URL && env.VITE_SUPABASE_ANON_KEY ? probeFunction(env.VITE_SUPABASE_URL, FUNCTION, env.VITE_SUPABASE_ANON_KEY) : Promise.resolve({ state: 'deployed' })

/**
 * 카카오 식당 불러오기. The university's centre and radius (`search_radius_m`) are read from Supabase at the moment of
 * the search and cover the WHOLE circle: the admin-only `admin_kakao_search` function is asked, one page at a time,
 * for a grid of areas, each split further while Kakao reports more places than it will hand out (at most 45 per
 * search), see `kakaoScan.ts`. The scan is a JOB: it has an id, remembers which squares are done / failed / pending and
 * the page cursor of each, is saved in this browser after every few squares, and can be continued instead of
 * restarted. No Kakao key is in the browser. The live results are listed; the admin ticks the places to manage; only
 * then does `admin_register_kakao_places` store the place ID and its name as a label (admin only, deduplicated by
 * Kakao place ID, existing restaurants untouched, audited).
 *
 * Kakao's own data (address, phone, coordinates, category) lives only in this component's memory for the preview and
 * is never saved, not even in the saved job (Kakao's terms allow real-time use of Local API results, not storing
 * them). So after a page reload a continued scan lists only the places of the squares it still had to search.
 *
 * If `admin_kakao_search` is not deployed on the project (checked first, with its HTTP status), the old keyword search
 * (15 per keyword, nearest first) runs instead, still limited to the radius, and the screen says plainly why and that
 * coverage is partial.
 */
export default function KakaoImport({ universities, probe = defaultProbe }: { universities: Uni[]; probe?: () => Promise<FnProbe> }) {
  const qc = useQueryClient()
  const [uniId, setUniId] = useState('')
  const [stage, setStage] = useState<Stage>({ s: 'idle' })
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const [, refresh] = useState(0)
  const abort = useRef<AbortController | null>(null)
  /** The job of this page session with the places it has found: lets "continue" keep partial results. */
  const session = useRef<{ job: JobState; memory: ScanMemory } | null>(null)
  const usable = universities.filter((u) => u.latitude != null && u.longitude != null)

  // An unfinished job of this university from an earlier visit is offered for continuing (read from this browser on each render).
  const storedJob = uniId && stage.s === 'idle' ? loadJob(uniId) : null
  const stored = storedJob && hasUnfinishedWork(storedJob) ? jobSummary(storedJob) : null

  const lookupManaged = async (places: KakaoDoc[]): Promise<Managed> => {
    const managed: Managed = {}
    for (const ids of chunk(places.map((p) => p.id), 200)) {
      const { data, error } = await supabase.from('restaurant_overrides').select('kakao_place_id,visibility').in('kakao_place_id', ids)
      if (error) throw error
      for (const r of data as { kakao_place_id: string; visibility: string }[]) managed[r.kakao_place_id] = { visibility: r.visibility }
    }
    return managed
  }

  const collect = async (mode: RunMode) => {
    if (!uniId) return
    setPicked(new Set())
    const ctl = new AbortController()
    abort.current = ctl
    let where: ImportStage = 'university'
    let jobId: string | undefined
    setStage({ s: 'collecting', progress: null, legacy: null, cancelling: false })
    try {
      // The university row is the authority: read it NOW, not from a list loaded earlier.
      const { data: row, error: rowErr } = await supabase.from('universities').select('id,name_ko,latitude,longitude,search_radius_m').eq('id', uniId).single()
      if (rowErr) throw rowErr
      const u = row as Uni | null
      const radius = Number(u?.search_radius_m)
      if (!u || u.latitude == null || u.longitude == null || !Number.isInteger(radius) || radius < 100 || radius > 5000) {
        return setStage({ s: 'error', text: describeError({ stage: 'university', message: '이 대학교의 좌표 또는 검색 반경(search_radius_m)을 읽지 못했어요. 대학교 페이지에서 값을 확인해 주세요. (반경은 100~5000m)' }) })
      }
      const campus: Campus = { id: u.id, name: u.name_ko, latitude: Number(u.latitude), longitude: Number(u.longitude), radiusM: radius }

      // Which job? A new one, the one saved in this browser, or the one of this page session.
      let job: JobState | null = null
      let memory = newMemory()
      if (mode === 'resume-stored') job = loadJob(campus.id)
      if (mode === 'continue-session' && session.current?.job.campus.id === campus.id) { job = session.current.job; memory = session.current.memory }
      if (job && !jobMatchesCampus(job, campus)) {
        clearJob(campus.id); session.current = null
        return setStage({ s: 'error', text: describeError({ stage: 'university', jobId: job.id, message: `대학교 좌표 또는 반경이 바뀌어(${job.campus.radiusM}m → ${campus.radiusM}m) 이전 작업을 이어갈 수 없어요. 새로 시작해 주세요.` }) })
      }
      if (!job) { job = newJob(campus); clearJob(campus.id) }
      jobId = job.id
      setStage({ s: 'collecting', progress: null, legacy: null, cancelling: false })

      let scan: ScanResult | null = null
      let reason = ''
      where = 'function_check'
      const fn = await probe()
      if (fn.state === 'not_deployed') {
        reason = `HTTP ${fn.status ?? 404} NOT_FOUND — ${FUNCTION} 함수가 이 Supabase 프로젝트에 배포되어 있지 않아요`
      } else {
        where = 'grid_search'
        const search = makeSupabaseSearch((name, o) => supabase.functions.invoke(name, o), probe)
        scan = await runJob(job, search, {
          signal: ctl.signal, memory,
          onProgress: (progress) => setStage((s) => (s.s === 'collecting' ? { ...s, progress } : s)),
          onCheckpoint: (j) => (j.status === 'complete' ? clearJob(campus.id) : saveJob(j)),
        })
        session.current = { job: scan.job, memory }
        if (scan.job.status === 'complete') clearJob(campus.id)
        else if (hasUnfinishedWork(scan.job)) saveJob(scan.job)
        if (scan.stoppedBy === 'not_deployed') reason = `HTTP ${scan.errors[0]?.status ?? 404} ${scan.errors[0]?.code ?? 'NOT_FOUND'} — ${FUNCTION} 함수가 이 Supabase 프로젝트에 배포되어 있지 않아요`
      }

      let places: KakaoDoc[] = scan?.places ?? []
      let report: Report | null = scan && !reason ? { kind: 'grid', scan } : null
      if (reason) {
        // The new function is not on this project: fall back to the old keyword search, but never beyond the radius.
        where = 'legacy_search'
        session.current = null; clearJob(campus.id)
        setStage({ s: 'collecting', progress: null, legacy: { done: 0, total: KAKAO_QUERIES.length }, cancelling: false, note: reason })
        const old = await collectKakaoPlaces(
          { latitude: campus.latitude, longitude: campus.longitude },
          (body) => supabase.functions.invoke('search_restaurants', { body }),
          (done, total) => setStage({ s: 'collecting', progress: null, legacy: { done, total }, cancelling: false, note: reason }),
        )
        const kept = withinRadius(old.places, campus)
        places = kept.places
        report = { kind: 'legacy', outside: kept.outside, failed: old.failed, why: reason }
        if (places.length === 0) {
          return setStage({ s: 'error', text: describeError({ stage: 'legacy_search', status: old.lastError?.status, message: old.lastError?.message ?? '기존 검색에서도 결과를 받지 못했어요', jobId }), hint: `${reason}. 기존 방식 검색도 실패했어요.` })
        }
      }
      if (places.length === 0 && report?.kind === 'grid') {
        const e = report.scan.errors[0]
        if (e) return setStage({ s: 'error', text: describeError({ stage: e.stage, status: e.status, code: e.code, message: e.message, jobId }), hint: `${report.scan.warnings.join(' ')} 성공한 구역이 없어 보여드릴 결과가 없어요.` })
        if (report.scan.stoppedBy) return setStage({ s: 'error', text: describeError({ stage: 'grid_search', message: report.scan.warnings.join(' ') || '검색이 중단됐어요', jobId }) })
        return setStage({ s: 'error', text: `반경 ${campus.radiusM}m 안에서 가져올 식당을 찾지 못했어요. (작업 ID ${jobId.slice(0, 8)})` })
      }
      where = 'managed_lookup'
      setStage({ s: 'preview', campus, places, managed: await lookupManaged(places), report: report! })
    } catch (e) {
      setStage({ s: 'error', text: describeError({ stage: where, status: statusOf(e) ?? (typeof e === 'object' && e && 'status' in e ? Number((e as { status: unknown }).status) || undefined : undefined), code: typeof e === 'object' && e && 'code' in e ? String((e as { code: unknown }).code) : undefined, message: errorMessage(e), jobId }) })
    } finally { abort.current = null }
  }

  const cancel = () => {
    abort.current?.abort()
    setStage((s) => (s.s === 'collecting' ? { ...s, cancelling: true } : s))
  }

  const toggle = (id: string) => setPicked((p) => { const n = new Set(p); if (!n.delete(id)) n.add(id); return n })

  const register = async (campus: Campus, places: KakaoDoc[], managed: Managed) => {
    setStage({ s: 'saving' })
    try {
      // Only what the server needs to validate and label the place. Places that are already managed are never sent:
      // their name, menus, prices, photos and publication state stay exactly as the admins left them.
      const chosen = places.filter((p) => picked.has(p.id) && !managed[p.id]).map((p) => ({ id: p.id, place_name: p.place_name, category_group_code: p.category_group_code, x: p.x, y: p.y }))
      let added = 0; let already = 0; let skipped = 0
      for (const part of chunk(chosen, 200)) {
        const { data, error } = await supabase.rpc('admin_register_kakao_places', { p_university: campus.id, p_places: part })
        if (error) throw error
        const r = data as { added: number; already_managed: number; skipped: number }
        added += r.added; already += r.already_managed; skipped += r.skipped
      }
      await qc.invalidateQueries({ queryKey: ['restaurants'] })
      setPicked(new Set())
      setStage({ s: 'done', text: `${campus.name}: ${added}곳을 초안으로 등록했어요.${already ? ` 이미 관리 중인 ${already}곳은 그대로 뒀어요.` : ''}${skipped ? ` 식당이 아니거나 좌표가 올바르지 않은 ${skipped}곳은 제외했어요.` : ''} 앱에는 공개하기 전까지 보이는 정보가 바뀌지 않아요.` })
    } catch (e) {
      const m = errorMessage(e)
      setStage({ s: 'error', text: MISSING_FN.test(m) ? '서버에 등록 기능이 아직 없어요. Supabase에 마이그레이션 20261111000100을 먼저 적용해 주세요.' : describeError({ stage: 'register', status: statusOf(e), message: m }) })
    }
  }

  const busy = stage.s === 'collecting' || stage.s === 'saving'
  return (
    <Card className="mb-5 space-y-3">
      <div className="flex flex-wrap items-end gap-3">
        <Field label="카카오 식당 불러오기 · 대학교" htmlFor="kuni">
          <Select id="kuni" value={uniId} onChange={(e) => { setUniId(e.target.value); setStage({ s: 'idle' }); session.current = null }}>
            <option value="">대학교 선택</option>
            {usable.map((u) => <option key={u.id} value={u.id}>{u.name_ko}{u.search_radius_m ? ` · 반경 ${u.search_radius_m}m` : ''}{u.is_active ? '' : ' (비활성)'}</option>)}
          </Select>
        </Field>
        <Button disabled={!uniId || busy} onClick={() => void collect('new')}><CloudDownload className="size-4" />카카오에서 찾기</Button>
        {stage.s === 'collecting' && <Button variant="outline" disabled={stage.cancelling} onClick={cancel}>{stage.cancelling ? '중단하는 중…' : '중단'}</Button>}
      </div>
      <p className="text-xs text-muted">대학교의 <b>검색 반경(search_radius_m)</b> 전체를 구역으로 나눠 카카오에서 찾아요(검색 한 번에 카카오가 알려주는 곳은 최대 45곳이라, 꽉 찬 구역은 더 잘게 나눠요). 작은 요청으로 나눠 진행하고, 중간에 실패해도 성공한 구역은 그대로 두고 남은 구역만 이어서 할 수 있어요. 고른 식당은 <b>장소 ID와 이름(관리용 표시)만</b> 저장되고, 주소·전화·좌표 같은 카카오 정보는 저장하지 않고 필요할 때 다시 불러와요. 이미 관리 중인 식당은 건드리지 않아요.</p>
      {stored && stage.s === 'idle' && (
        <div role="status" aria-label="이어서 할 작업" className="space-y-2 rounded-xl border border-line bg-white p-3 text-sm">
          <div>끝나지 않은 작업이 있어요 <span className="text-xs text-muted">(작업 ID {stored.jobId.slice(0, 8)} · 반경 {stored.radiusM}m)</span></div>
          <div className="text-xs text-muted">검색 구역 {stored.done}/{stored.total} 완료 · 실패 {stored.failed} · 남음 {stored.pending}. 카카오 정책상 이전에 찾은 식당 목록은 저장하지 않아서, 이어서 하면 <b>남은 구역의 결과만</b> 목록에 나와요(이미 등록한 식당은 그대로예요).</div>
          <div className="flex gap-2">
            <Button size="sm" disabled={busy} onClick={() => void collect('resume-stored')}>이어서 하기</Button>
            <Button size="sm" variant="ghost" onClick={() => { clearJob(uniId); refresh((n) => n + 1) }}>작업 버리기</Button>
          </div>
        </div>
      )}
      {stage.s === 'collecting' && <Collecting stage={stage} />}
      {stage.s === 'preview' && <Preview stage={stage} picked={picked} toggle={toggle} setPicked={setPicked} onRegister={() => void register(stage.campus, stage.places, stage.managed)} onCancel={() => setStage({ s: 'idle' })} onContinue={() => void collect('continue-session')} />}
      {stage.s === 'saving' && <p role="status" className="text-sm">등록 중…</p>}
      {stage.s === 'done' && <p role="status" className="rounded-xl bg-brand/30 p-3 text-sm">{stage.text}</p>}
      {stage.s === 'error' && (
        <div role="alert" className="space-y-1 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">
          <div>카카오 식당 불러오기에 실패했어요.</div>
          <div className="text-xs">{stage.text}</div>
          {stage.hint && <div className="text-xs">{redact(stage.hint)}</div>}
        </div>
      )}
    </Card>
  )
}

function Collecting({ stage }: { stage: Extract<Stage, { s: 'collecting' }> }) {
  if (stage.legacy) return (
    <div role="status" className="space-y-1 text-sm">
      <div>기존 방식으로 카카오 검색 중… {stage.legacy.done}/{stage.legacy.total}</div>
      {stage.note && <div className="text-xs text-muted">{redact(stage.note)}</div>}
    </div>
  )
  const p = stage.progress
  if (!p) return <p role="status" className="text-sm">대학교 설정과 검색 함수를 확인하는 중…</p>
  const total = p.cellsDone + p.cellsQueued
  return (
    <div role="status" className="space-y-1 text-sm">
      <div>{p.phase === 'keywords' ? '꽉 찬 구역을 키워드로 다시 찾는 중…' : '카카오 검색 중…'} 반경 <b>{p.radiusM}m</b> <span className="text-xs text-muted">(작업 ID {p.jobId.slice(0, 8)})</span></div>
      <div className="text-xs text-muted">검색 구역 {p.cellsDone}/{total} · 꽉 찬 구역 {p.cellsSaturated} · 카카오 호출 {p.kakaoCalls}회 (요청 {p.invocations}회, 재시도 {p.retries}회, 동시 {p.concurrency}개) · 찾은 곳 {p.unique}곳 (반경 밖 제외 {p.outside}) · 실패 {p.failed}</div>
    </div>
  )
}

function Preview({ stage, picked, toggle, setPicked, onRegister, onCancel, onContinue }: {
  stage: Extract<Stage, { s: 'preview' }>; picked: Set<string>; toggle: (id: string) => void
  setPicked: (s: Set<string>) => void; onRegister: () => void; onCancel: () => void; onContinue: () => void
}) {
  const fresh = stage.places.filter((p) => !stage.managed[p.id])
  const managedCount = stage.places.length - fresh.length
  const r = stage.report
  const left = r.kind === 'grid' ? r.scan.job.tasks.filter((t) => t.status !== 'done').length : 0
  return (
    <div className="space-y-2" role="group" aria-label="찾은 식당">
      <div role="status" className="text-sm">
        반경 <b>{stage.campus.radiusM}m</b> 안에서 <b>{stage.places.length}곳</b>을 찾았어요. 이미 관리 중 {managedCount}곳, 새 식당 {fresh.length}곳.
      </div>
      {r.kind === 'grid' ? (
        <div className="space-y-1 rounded-xl border border-line bg-white p-3 text-xs" aria-label="검색 범위 보고">
          <div>작업 ID {r.scan.job.id.slice(0, 8)} · 검색한 구역 {r.scan.progress.cellsDone}개 · 카카오 호출 {r.scan.progress.kakaoCalls}회 (요청 {r.scan.progress.invocations}회, 재시도 {r.scan.progress.retries}회) · 반경 밖이라 제외 {r.scan.progress.outside}곳 · 실패한 검색 {r.scan.failedCells.length}건 · 남은 구역 {r.scan.unsearchedCells}개 · 가장 잘게 나눠도 꽉 찬 구역 {r.scan.saturatedCells.length}개</div>
          {r.scan.complete
            ? <div className="text-green-800">모든 구역을 카카오 노출 한도 안에서 끝까지 읽었어요. 다만 카카오가 API로 알려주지 않는 장소는 찾을 수 없어요(카카오맵과 결과가 다를 수 있어요).</div>
            : (
              <div role="alert" className="space-y-1 text-amber-900">
                <ul className="list-disc space-y-0.5 pl-4">{r.scan.warnings.map((w) => <li key={w}>{w}</li>)}<li><b>일부만 찾은 결과예요.</b> 빠진 곳이 있을 수 있어요.</li></ul>
                {r.scan.errors.length > 0 && (
                  <ul aria-label="실패 내용" className="list-disc space-y-0.5 pl-4">
                    {r.scan.errors.slice(0, 4).map((e) => <li key={`${e.stage}${e.kind}${e.status}${e.code}`}>{describeError({ stage: e.stage, status: e.status, code: e.code, message: e.message })} × {e.count} ({FAIL_LABEL[e.kind] ?? e.kind})</li>)}
                  </ul>
                )}
              </div>)}
          {left > 0 && <Button size="sm" variant="outline" onClick={onContinue}>{r.scan.failedCells.length > 0 ? `실패한 구역·남은 구역 이어서 하기 (${left})` : `남은 구역 이어서 하기 (${left})`}</Button>}
        </div>
      ) : (
        <div role="alert" className="space-y-1 rounded-xl bg-amber-50 p-3 text-xs text-amber-900">
          <div><b>일부만 찾은 결과예요.</b> 구역 검색 함수(<code>admin_kakao_search</code>)를 쓰지 못해 기존 방식(키워드당 최대 15곳, 가까운 곳 위주)으로 찾았어요. 반경 {stage.campus.radiusM}m 밖 {r.outside}곳은 제외했어요. 함수를 배포하면 반경 전체를 훑어요(supabase/README.md).</div>
          <div>이유: {redact(r.why)}</div>
          {r.failed.length > 0 && <div>검색 실패 키워드: {r.failed.join(', ')}</div>}
        </div>
      )}
      <p className="text-xs text-muted">반경과 좌표는 지금 Supabase의 대학교 설정이에요. 대학교 페이지에서 반경을 고치고 <b>게시하지 않았다면</b> 이전 값이에요.</p>
      <div className="flex flex-wrap gap-2">
        <Button size="sm" variant="outline" onClick={() => setPicked(new Set(fresh.map((p) => p.id)))}>새 식당 모두 선택</Button>
        <Button size="sm" variant="ghost" onClick={() => setPicked(new Set())}>선택 해제</Button>
      </div>
      <ul className="max-h-80 divide-y divide-line overflow-auto rounded-xl border border-line bg-white text-sm">
        {stage.places.map((p) => {
          const m = stage.managed[p.id]
          return (
            <li key={p.id} className="flex items-center gap-3 px-3 py-2">
              <input type="checkbox" aria-label={`${p.place_name} 선택`} disabled={!!m} checked={picked.has(p.id)} onChange={() => toggle(p.id)} />
              <div className="min-w-0 flex-1">
                <div className="truncate font-medium">{p.place_name}</div>
                <div className="truncate text-xs text-muted">{p.category_name?.replace(/^음식점 > /, '')} · {p.road_address_name || p.address_name} · {p.distance ? `${p.distance}m` : ''}</div>
              </div>
              {m ? <Badge tone="green">관리 중 · {STATUS_LABEL[m.visibility] ?? m.visibility}</Badge> : <Badge tone="neutral">새 식당</Badge>}
            </li>)
        })}
      </ul>
      <div className="flex gap-2">
        <Button disabled={picked.size === 0} onClick={onRegister}>{picked.size}곳 등록하기</Button>
        <Button variant="outline" onClick={onCancel}>닫기</Button>
      </div>
    </div>
  )
}
