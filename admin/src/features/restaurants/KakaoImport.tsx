import { useQueryClient } from '@tanstack/react-query'
import { CloudDownload } from 'lucide-react'
import { useRef, useState } from 'react'
import { Badge, Button, Card, Field, Select } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import { chunk, collectKakaoPlaces, KAKAO_QUERIES, type KakaoDoc, withinRadius } from './kakao'
import type { Campus } from './kakaoGeo'
import { makeSupabaseSearch, type Progress, scanCampus, type ScanResult } from './kakaoScan'

type Uni = { id: string; name_ko: string; is_active: boolean; latitude?: number | null; longitude?: number | null; search_radius_m?: number | null }
type Managed = Record<string, { visibility: string }>
/** What the preview needs to say about how the places were found. */
type Report =
  | { kind: 'grid'; scan: ScanResult }
  | { kind: 'legacy'; outside: number; failed: string[] }
type Stage =
  | { s: 'idle' }
  | { s: 'collecting'; progress: Progress | null; legacy: { done: number; total: number } | null; cancelling: boolean }
  | { s: 'preview'; campus: Campus; places: KakaoDoc[]; managed: Managed; report: Report }
  | { s: 'saving' }
  | { s: 'done'; text: string }
  | { s: 'error'; text: string }

const MISSING_FN = /admin_register_kakao_places|PGRST202|42883|schema cache/i
const STATUS_LABEL: Record<string, string> = { draft: '초안', published: '공개', hidden: '숨김', archived: '보관' }
const FAIL_LABEL: Record<string, string> = { rate_limited: '요청 제한(429)', unavailable: '카카오 응답 없음', network: '네트워크', rejected: '거절됨', not_deployed: '함수 미배포', forbidden: '권한 없음', aborted: '중단' }

/**
 * 카카오 식당 불러오기. The university's centre and radius (`search_radius_m`) are read from Supabase at the moment
 * of the search and cover the WHOLE circle: the deployed-for-admins `admin_kakao_search` function is asked for a grid
 * of areas, each split further while Kakao reports more places than it will hand out (at most 45 per search), see
 * `kakaoScan.ts`. No Kakao key is in the browser. The live results are listed; the admin ticks the places to manage;
 * only then does `admin_register_kakao_places` store the place ID and its name as a label (admin only, deduplicated
 * by Kakao place ID, existing restaurants untouched, audited).
 *
 * Kakao's own data (address, phone, coordinates, category) lives only in this component's memory for the preview
 * and is never saved: Kakao's terms allow real-time use of Local API results, not storing them.
 *
 * If `admin_kakao_search` is not deployed on the project, the old keyword search (15 per keyword, nearest first) runs
 * instead, still limited to the radius, and the screen says plainly that coverage is partial.
 */
export default function KakaoImport({ universities }: { universities: Uni[] }) {
  const qc = useQueryClient()
  const [uniId, setUniId] = useState('')
  const [stage, setStage] = useState<Stage>({ s: 'idle' })
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const abort = useRef<AbortController | null>(null)
  const usable = universities.filter((u) => u.latitude != null && u.longitude != null)

  const lookupManaged = async (places: KakaoDoc[]): Promise<Managed> => {
    const managed: Managed = {}
    for (const ids of chunk(places.map((p) => p.id), 200)) {
      const { data, error } = await supabase.from('restaurant_overrides').select('kakao_place_id,visibility').in('kakao_place_id', ids)
      if (error) throw error
      for (const r of data as { kakao_place_id: string; visibility: string }[]) managed[r.kakao_place_id] = { visibility: r.visibility }
    }
    return managed
  }

  const collect = async () => {
    if (!uniId) return
    setPicked(new Set())
    const ctl = new AbortController()
    abort.current = ctl
    setStage({ s: 'collecting', progress: null, legacy: null, cancelling: false })
    try {
      // The university row is the authority: read it NOW, not from a list loaded earlier.
      const { data: row, error: rowErr } = await supabase.from('universities').select('id,name_ko,latitude,longitude,search_radius_m').eq('id', uniId).single()
      if (rowErr) throw rowErr
      const u = row as Uni | null
      const radius = Number(u?.search_radius_m)
      if (!u || u.latitude == null || u.longitude == null || !Number.isInteger(radius) || radius < 100 || radius > 5000) {
        return setStage({ s: 'error', text: '이 대학교의 좌표 또는 검색 반경(search_radius_m)을 읽지 못했어요. 대학교 페이지에서 값을 확인해 주세요. (반경은 100~5000m)' })
      }
      const campus: Campus = { id: u.id, name: u.name_ko, latitude: Number(u.latitude), longitude: Number(u.longitude), radiusM: radius }

      const scan = await scanCampus(campus, makeSupabaseSearch((name, o) => supabase.functions.invoke(name, o)), {
        signal: ctl.signal,
        onProgress: (progress) => setStage((s) => (s.s === 'collecting' ? { ...s, progress } : s)),
      })

      let places: KakaoDoc[] = scan.places
      let report: Report = { kind: 'grid', scan }
      if (scan.stoppedBy === 'not_deployed') {
        // The new function is not on this project: fall back to the old keyword search, but never beyond the radius.
        setStage({ s: 'collecting', progress: null, legacy: { done: 0, total: KAKAO_QUERIES.length }, cancelling: false })
        const old = await collectKakaoPlaces(
          { latitude: campus.latitude, longitude: campus.longitude },
          (body) => supabase.functions.invoke('search_restaurants', { body }),
          (done, total) => setStage({ s: 'collecting', progress: null, legacy: { done, total }, cancelling: false }),
        )
        const kept = withinRadius(old.places, campus)
        places = kept.places
        report = { kind: 'legacy', outside: kept.outside, failed: old.failed }
      }
      if (places.length === 0) {
        const failed = report.kind === 'grid' ? report.scan.failedCells.length > 0 || report.scan.stoppedBy !== null : report.failed.length > 0
        return setStage({ s: 'error', text: failed ? '카카오 검색에 실패했거나 중단됐어요. 잠시 뒤 다시 시도해 주세요.' : `반경 ${campus.radiusM}m 안에서 가져올 식당을 찾지 못했어요.` })
      }
      setStage({ s: 'preview', campus, places, managed: await lookupManaged(places), report })
    } catch (e) { setStage({ s: 'error', text: errorMessage(e) }) }
    finally { abort.current = null }
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
      setStage({ s: 'error', text: MISSING_FN.test(m) ? '서버에 등록 기능이 아직 없어요. Supabase에 마이그레이션 20261111000100을 먼저 적용해 주세요.' : m })
    }
  }

  const busy = stage.s === 'collecting' || stage.s === 'saving'
  return (
    <Card className="mb-5 space-y-3">
      <div className="flex flex-wrap items-end gap-3">
        <Field label="카카오 식당 불러오기 · 대학교" htmlFor="kuni">
          <Select id="kuni" value={uniId} onChange={(e) => { setUniId(e.target.value); setStage({ s: 'idle' }) }}>
            <option value="">대학교 선택</option>
            {usable.map((u) => <option key={u.id} value={u.id}>{u.name_ko}{u.search_radius_m ? ` · 반경 ${u.search_radius_m}m` : ''}{u.is_active ? '' : ' (비활성)'}</option>)}
          </Select>
        </Field>
        <Button disabled={!uniId || busy} onClick={() => void collect()}><CloudDownload className="size-4" />카카오에서 찾기</Button>
        {stage.s === 'collecting' && <Button variant="outline" disabled={stage.cancelling} onClick={cancel}>{stage.cancelling ? '중단하는 중…' : '중단'}</Button>}
      </div>
      <p className="text-xs text-muted">대학교의 <b>검색 반경(search_radius_m)</b> 전체를 구역으로 나눠 카카오에서 찾아요(검색 한 번에 카카오가 알려주는 곳은 최대 45곳이라, 꽉 찬 구역은 더 잘게 나눠요). 고른 식당은 <b>장소 ID와 이름(관리용 표시)만</b> 저장되고, 주소·전화·좌표 같은 카카오 정보는 저장하지 않고 필요할 때 다시 불러와요. 이미 관리 중인 식당은 건드리지 않아요.</p>
      {stage.s === 'collecting' && <Collecting stage={stage} />}
      {stage.s === 'preview' && <Preview stage={stage} picked={picked} toggle={toggle} setPicked={setPicked} onRegister={() => void register(stage.campus, stage.places, stage.managed)} onCancel={() => setStage({ s: 'idle' })} />}
      {stage.s === 'saving' && <p role="status" className="text-sm">등록 중…</p>}
      {stage.s === 'done' && <p role="status" className="rounded-xl bg-brand/30 p-3 text-sm">{stage.text}</p>}
      {stage.s === 'error' && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{stage.text}</p>}
    </Card>
  )
}

function Collecting({ stage }: { stage: Extract<Stage, { s: 'collecting' }> }) {
  if (stage.legacy) return <p role="status" className="text-sm">기존 방식으로 카카오 검색 중… {stage.legacy.done}/{stage.legacy.total}</p>
  const p = stage.progress
  if (!p) return <p role="status" className="text-sm">대학교 설정을 읽는 중…</p>
  const total = p.cellsDone + p.cellsQueued
  return (
    <div role="status" className="space-y-1 text-sm">
      <div>{p.phase === 'keywords' ? '꽉 찬 구역을 키워드로 다시 찾는 중…' : '카카오 검색 중…'} 반경 <b>{p.radiusM}m</b></div>
      <div className="text-xs text-muted">검색 구역 {p.cellsDone}/{total} · 꽉 찬 구역 {p.cellsSaturated} · 카카오 호출 {p.kakaoCalls}회 (요청 {p.invocations}회, 재시도 {p.retries}회) · 찾은 곳 {p.unique}곳 (반경 밖 제외 {p.outside}) · 실패 {p.failed}</div>
    </div>
  )
}

function Preview({ stage, picked, toggle, setPicked, onRegister, onCancel }: {
  stage: Extract<Stage, { s: 'preview' }>; picked: Set<string>; toggle: (id: string) => void
  setPicked: (s: Set<string>) => void; onRegister: () => void; onCancel: () => void
}) {
  const fresh = stage.places.filter((p) => !stage.managed[p.id])
  const managedCount = stage.places.length - fresh.length
  const r = stage.report
  const failedByKind = r.kind === 'grid' ? Object.entries(r.scan.failedCells.reduce<Record<string, number>>((a, f) => ({ ...a, [f.kind]: (a[f.kind] ?? 0) + 1 }), {})) : []
  return (
    <div className="space-y-2" role="group" aria-label="찾은 식당">
      <div role="status" className="text-sm">
        반경 <b>{stage.campus.radiusM}m</b> 안에서 <b>{stage.places.length}곳</b>을 찾았어요. 이미 관리 중 {managedCount}곳, 새 식당 {fresh.length}곳.
      </div>
      {r.kind === 'grid' ? (
        <div className="space-y-1 rounded-xl border border-line bg-white p-3 text-xs" aria-label="검색 범위 보고">
          <div>검색한 구역 {r.scan.progress.cellsDone}개 · 카카오 호출 {r.scan.progress.kakaoCalls}회 (요청 {r.scan.progress.invocations}회, 재시도 {r.scan.progress.retries}회) · 반경 밖이라 제외 {r.scan.progress.outside}곳 · 실패한 검색 {r.scan.failedCells.length}건{failedByKind.length > 0 && ` (${failedByKind.map(([k, n]) => `${FAIL_LABEL[k] ?? k} ${n}`).join(', ')})`} · 가장 잘게 나눠도 꽉 찬 구역 {r.scan.saturatedCells.length}개</div>
          {r.scan.complete
            ? <div className="text-green-800">모든 구역을 카카오 노출 한도 안에서 끝까지 읽었어요. 다만 카카오가 API로 알려주지 않는 장소는 찾을 수 없어요(카카오맵과 결과가 다를 수 있어요).</div>
            : <ul className="list-disc space-y-0.5 pl-4 text-amber-900" role="alert">{r.scan.warnings.map((w) => <li key={w}>{w}</li>)}<li>일부만 찾은 결과예요. 빠진 곳이 있을 수 있어요.</li></ul>}
        </div>
      ) : (
        <div role="alert" className="space-y-1 rounded-xl bg-amber-50 p-3 text-xs text-amber-900">
          <div><b>일부만 찾은 결과예요.</b> 구역 검색 함수(<code>admin_kakao_search</code>)가 이 프로젝트에 아직 배포되지 않아 기존 방식(키워드당 최대 15곳, 가까운 곳 위주)으로 찾았어요. 반경 {stage.campus.radiusM}m 밖 {r.outside}곳은 제외했어요. 함수를 배포하면 반경 전체를 훑어요(supabase/README.md).</div>
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
