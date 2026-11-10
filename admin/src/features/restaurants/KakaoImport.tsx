import { useQueryClient } from '@tanstack/react-query'
import { CloudDownload } from 'lucide-react'
import { useState } from 'react'
import { Badge, Button, Card, Field, Select } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import { chunk, collectKakaoPlaces, KAKAO_QUERIES, type KakaoDoc } from './kakao'

type Uni = { id: string; name_ko: string; is_active: boolean; latitude?: number | null; longitude?: number | null }
type Managed = Record<string, { visibility: string }>
type Stage =
  | { s: 'idle' }
  | { s: 'collecting'; done: number; total: number }
  | { s: 'preview'; uni: Uni; places: KakaoDoc[]; managed: Managed; failed: string[] }
  | { s: 'saving' }
  | { s: 'done'; text: string }
  | { s: 'error'; text: string }

const MISSING_FN = /admin_register_kakao_places|PGRST202|42883|schema cache/i
const STATUS_LABEL: Record<string, string> = { draft: '초안', published: '공개', hidden: '숨김', archived: '보관' }

/**
 * 카카오 식당 불러오기. Searches the campus area with the SAME deployed
 * `search_restaurants` function the app uses (no Kakao key in the browser) and
 * lists the live results. The admin ticks the places to manage; only then does
 * the server function `admin_register_kakao_places` store the place ID and its
 * name as a label (admin only, deduplicated by Kakao place ID, audited).
 *
 * Kakao's own data (address, phone, coordinates, category) lives only in this
 * component's memory for the preview and is never saved: Kakao's policy
 * restricts caching of Local API results.
 */
export default function KakaoImport({ universities }: { universities: Uni[] }) {
  const qc = useQueryClient()
  const [uniId, setUniId] = useState('')
  const [stage, setStage] = useState<Stage>({ s: 'idle' })
  const [picked, setPicked] = useState<Set<string>>(new Set())
  const usable = universities.filter((u) => u.latitude != null && u.longitude != null)

  const collect = async () => {
    const uni = usable.find((u) => u.id === uniId)
    if (!uni) return
    setPicked(new Set())
    setStage({ s: 'collecting', done: 0, total: KAKAO_QUERIES.length })
    try {
      const { places, failed } = await collectKakaoPlaces(
        { latitude: uni.latitude!, longitude: uni.longitude! },
        (body) => supabase.functions.invoke('search_restaurants', { body }),
        (done, total) => setStage({ s: 'collecting', done, total }),
      )
      if (places.length === 0) return setStage({ s: 'error', text: failed.length ? '카카오 검색에 실패했어요. 잠시 뒤 다시 시도해 주세요.' : '가져올 식당을 찾지 못했어요.' })
      const managed: Managed = {}
      for (const ids of chunk(places.map((p) => p.id), 200)) {
        const { data, error } = await supabase.from('restaurant_overrides').select('kakao_place_id,visibility').in('kakao_place_id', ids)
        if (error) throw error
        for (const r of data as { kakao_place_id: string; visibility: string }[]) managed[r.kakao_place_id] = { visibility: r.visibility }
      }
      setStage({ s: 'preview', uni, places, managed, failed })
    } catch (e) { setStage({ s: 'error', text: errorMessage(e) }) }
  }

  const toggle = (id: string) => setPicked((p) => { const n = new Set(p); if (!n.delete(id)) n.add(id); return n })

  const register = async (uni: Uni, places: KakaoDoc[]) => {
    setStage({ s: 'saving' })
    try {
      // Only what the server needs to validate and label the place.
      const chosen = places.filter((p) => picked.has(p.id)).map((p) => ({ id: p.id, place_name: p.place_name, category_group_code: p.category_group_code, x: p.x, y: p.y }))
      let added = 0; let already = 0; let skipped = 0
      for (const part of chunk(chosen, 200)) {
        const { data, error } = await supabase.rpc('admin_register_kakao_places', { p_university: uni.id, p_places: part })
        if (error) throw error
        const r = data as { added: number; already_managed: number; skipped: number }
        added += r.added; already += r.already_managed; skipped += r.skipped
      }
      await qc.invalidateQueries({ queryKey: ['restaurants'] })
      setPicked(new Set())
      setStage({ s: 'done', text: `${uni.name_ko}: ${added}곳을 초안으로 등록했어요.${already ? ` 이미 관리 중인 ${already}곳은 그대로 뒀어요.` : ''}${skipped ? ` 식당이 아니거나 좌표가 올바르지 않은 ${skipped}곳은 제외했어요.` : ''} 앱에는 공개하기 전까지 보이는 정보가 바뀌지 않아요.` })
    } catch (e) {
      const m = errorMessage(e)
      setStage({ s: 'error', text: MISSING_FN.test(m) ? '서버에 등록 기능이 아직 없어요. Supabase에 마이그레이션 20261111000100을 먼저 적용해 주세요.' : m })
    }
  }

  return (
    <Card className="mb-5 space-y-3">
      <div className="flex flex-wrap items-end gap-3">
        <Field label="카카오 식당 불러오기 · 대학교" htmlFor="kuni">
          <Select id="kuni" value={uniId} onChange={(e) => { setUniId(e.target.value); setStage({ s: 'idle' }) }}>
            <option value="">대학교 선택</option>
            {usable.map((u) => <option key={u.id} value={u.id}>{u.name_ko}{u.is_active ? '' : ' (비활성)'}</option>)}
          </Select>
        </Field>
        <Button disabled={!uniId || stage.s === 'collecting' || stage.s === 'saving'} onClick={() => void collect()}><CloudDownload className="size-4" />카카오에서 찾기</Button>
      </div>
      <p className="text-xs text-muted">앱과 같은 카카오 검색(캠퍼스 좌표 기준)을 지금 실행해 결과를 보여줘요. 키워드당 최대 15곳이라 가까운 곳 위주예요. 고른 식당은 <b>장소 ID와 이름(관리용 표시)만</b> 저장되고, 주소·전화·좌표 같은 카카오 정보는 저장하지 않고 필요할 때 다시 불러와요.</p>
      {stage.s === 'collecting' && <p role="status" className="text-sm">카카오 검색 중… {stage.done}/{stage.total}</p>}
      {stage.s === 'preview' && <Preview stage={stage} picked={picked} toggle={toggle} setPicked={setPicked} onRegister={() => void register(stage.uni, stage.places)} onCancel={() => setStage({ s: 'idle' })} />}
      {stage.s === 'saving' && <p role="status" className="text-sm">등록 중…</p>}
      {stage.s === 'done' && <p role="status" className="rounded-xl bg-brand/30 p-3 text-sm">{stage.text}</p>}
      {stage.s === 'error' && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{stage.text}</p>}
    </Card>
  )
}

function Preview({ stage, picked, toggle, setPicked, onRegister, onCancel }: {
  stage: Extract<Stage, { s: 'preview' }>; picked: Set<string>; toggle: (id: string) => void
  setPicked: (s: Set<string>) => void; onRegister: () => void; onCancel: () => void
}) {
  const fresh = stage.places.filter((p) => !stage.managed[p.id])
  const managedCount = stage.places.length - fresh.length
  return (
    <div className="space-y-2" role="group" aria-label="찾은 식당">
      <div role="status" className="text-sm">
        <b>{stage.places.length}곳</b>을 찾았어요. 이미 관리 중 {managedCount}곳, 새 식당 {fresh.length}곳.
        {stage.failed.length > 0 && ` (검색 실패 키워드: ${stage.failed.join(', ')})`}
      </div>
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
