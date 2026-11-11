import { Loader2 } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { Button, Input } from '@/components/ui'
import { cmsOverview } from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import { type DeleteProgress, type DeleteResult, deleteVerdict, type RestaurantRow, runDelete } from './deleteRestaurants'
import { chunk } from './kakao'

const CONFIRM_WORD = '삭제'

const readRows = async (ids: string[]): Promise<RestaurantRow[]> => {
  const { data, error } = await supabase.from('restaurant_overrides').select('id,name_ko,visibility').in('id', ids)
  if (error) throw error
  return data as RestaurantRow[]
}
const scheduledIds = async () => new Set((await cmsOverview('restaurant')).filter((o) => o.scheduled_at !== null).map((o) => o.entity_id))
/** Rows actually removed: row-level security deletes NOTHING (without an error) for a caller who may not delete. */
const deleteOne = async (id: string) => {
  const { data, error } = await supabase.from('restaurant_overrides').delete().eq('id', id).select('id')
  if (error) throw error
  return (data ?? []).length
}

type Preview = { total: number; deletable: RestaurantRow[]; published: number; scheduled: number; gone: number; hiddenOrArchived: number; menus: number; photos: number }

async function loadPreview(ids: string[]): Promise<Preview> {
  const unique = [...new Set(ids)]
  const rows: RestaurantRow[] = []
  for (const part of chunk(unique, 200)) rows.push(...(await readRows(part)))
  const scheduled = await scheduledIds()
  const p: Preview = { total: unique.length, deletable: [], published: 0, scheduled: 0, gone: unique.length - rows.length, hiddenOrArchived: 0, menus: 0, photos: 0 }
  for (const r of rows) {
    const v = deleteVerdict(r, scheduled)
    if (v === 'published') p.published++
    else if (v === 'scheduled') p.scheduled++
    else { p.deletable.push(r); if (r.visibility === 'hidden' || r.visibility === 'archived') p.hiddenOrArchived++ }
  }
  // what goes with them (the database removes these rows together with the restaurant)
  for (const part of chunk(p.deletable.map((r) => r.id), 200)) {
    const m = await supabase.from('restaurant_menus').select('id').in('restaurant_id', part)
    if (m.error) throw m.error
    p.menus += (m.data ?? []).length
    const ph = await supabase.from('restaurant_photos').select('id').in('restaurant_id', part)
    if (ph.error) throw ph.error
    p.photos += (ph.data ?? []).length
  }
  return p
}

type Phase =
  | { s: 'loading' }
  | { s: 'confirm'; preview: Preview }
  | { s: 'running'; progress: DeleteProgress | null; cancelling: boolean }
  | { s: 'done'; result: DeleteResult }
  | { s: 'error'; text: string }

/**
 * Confirmation, progress and result of deleting restaurants. Super admins only (the database enforces it; the Admin also
 * hides the buttons from everyone else). Deleting is permanent: there is no undo button, the database keeps an audit record of
 * who did it and the whole deleted row.
 */
export default function DeleteRestaurantsDialog({ ids, onClose }: { ids: string[]; onClose: (deletedIds: string[]) => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  const abort = useRef<AbortController | null>(null)
  const deleted = useRef<string[]>([])
  const [phase, setPhase] = useState<Phase>({ s: 'loading' })
  const [typed, setTyped] = useState('')
  const [ack, setAck] = useState(false)

  useEffect(() => { const d = ref.current; if (d && !d.open) d.showModal?.() }, [])
  useEffect(() => {
    let live = true
    loadPreview(ids).then((preview) => { if (live) setPhase({ s: 'confirm', preview }) }).catch((e) => { if (live) setPhase({ s: 'error', text: errorMessage(e) }) })
    return () => { live = false }
  }, [ids])

  const run = async (list: string[]) => {
    const ctl = new AbortController()
    abort.current = ctl
    setPhase({ s: 'running', progress: null, cancelling: false })
    try {
      const result = await runDelete(list, { readRows, scheduledIds, deleteOne }, { signal: ctl.signal, onProgress: (progress) => setPhase((p) => (p.s === 'running' ? { ...p, progress } : p)) })
      deleted.current = [...new Set([...deleted.current, ...result.deleted])]
      setPhase({ s: 'done', result })
    } catch (e) { setPhase({ s: 'error', text: errorMessage(e) }) }
    finally { abort.current = null }
  }

  const close = () => onClose(deleted.current)
  const busy = phase.s === 'running'
  const single = ids.length === 1

  return (
    <dialog ref={ref} aria-label="식당 삭제" onCancel={(e) => { if (busy) e.preventDefault(); else close() }} className="m-auto w-[min(34rem,94vw)] rounded-2xl border border-line p-6 backdrop:bg-black/40">
      {phase.s === 'loading' && <p role="status" className="text-sm"><Loader2 className="mr-2 inline size-4 animate-spin" />선택한 식당의 현재 상태를 확인하는 중…</p>}

      {phase.s === 'error' && (
        <div className="space-y-4">
          <p role="alert" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">진행하지 못했어요: {phase.text}</p>
          <div className="flex justify-end"><Button variant="outline" onClick={close}>닫기</Button></div>
        </div>)}

      {phase.s === 'confirm' && (() => {
        const p = phase.preview
        const n = p.deletable.length
        const needAck = p.hiddenOrArchived > 0
        const ready = n > 0 && typed.trim() === CONFIRM_WORD && (!needAck || ack)
        return (
          <div className="space-y-4">
            <h2 className="text-lg font-bold">{single && n === 1 ? `“${p.deletable[0].name_ko}”을(를) 삭제할까요?` : `선택한 식당 ${p.total}곳을 삭제할까요?`}</h2>
            <ul aria-label="삭제 내용" className="space-y-1 text-sm">
              {!single && <li>선택한 식당 <b>{p.total}곳</b></li>}
              {p.published > 0 && <li>공개 중 <b>{p.published}곳</b> <span className="text-xs text-muted">(삭제하지 않아요. 먼저 &lsquo;숨기기&rsquo;를 해 주세요)</span></li>}
              {p.scheduled > 0 && <li>예약 게시가 있는 식당 <b>{p.scheduled}곳</b> <span className="text-xs text-muted">(삭제하지 않아요. 예약을 먼저 취소해 주세요)</span></li>}
              {p.gone > 0 && <li>이미 없는 식당 <b>{p.gone}곳</b></li>}
              <li className="pt-1">삭제할 식당 <b className="text-base">{n}곳</b>{n > 0 && <span className="text-xs text-muted"> · 함께 지워지는 메뉴 {p.menus}개, 사진 정보 {p.photos}개, 대학교 연결</span>}</li>
            </ul>
            {n > 0 && n <= 8 && <ul aria-label="삭제할 식당" className="list-disc space-y-0.5 pl-5 text-sm">{p.deletable.map((r) => <li key={r.id}>{r.name_ko}</li>)}</ul>}
            {n > 8 && <p className="text-xs text-muted">{p.deletable.slice(0, 5).map((r) => r.name_ko).join(', ')} 외 {n - 5}곳</p>}
            {n > 0 && (
              <div role="alert" aria-label="삭제 주의" className="space-y-1 rounded-xl bg-amber-50 p-3 text-xs text-amber-900">
                <div><b>삭제는 되돌릴 수 없어요.</b> 식당 정보, 메뉴·가격, 사진 정보, 대학교 연결이 함께 지워져요. (사진 파일은 저장소에 남고, 게시 이력과 활동 기록은 남아요.)</div>
                <div>카카오에서 불러온 식당이라면 삭제해도 카카오에는 그대로 있어서, 다시 &lsquo;카카오 식당 불러오기&rsquo;에 새 식당으로 나타날 수 있어요. 앱에서 감추기만 하려면 삭제 대신 <b>숨기기</b>를 쓰세요.</div>
              </div>)}
            {needAck && (
              <label className="flex items-start gap-2 rounded-xl border border-amber-300 bg-amber-50 p-3 text-xs text-amber-900">
                <input type="checkbox" className="mt-0.5" checked={ack} onChange={(e) => setAck(e.target.checked)} />
                <span>숨김·보관 상태인 식당 <b>{p.hiddenOrArchived}곳</b>이 포함돼 있어요. 삭제하면 앱에서 이 식당들이 <b>다시 카카오 정보 그대로 보일 수 있다</b>는 것을 알고 있어요.</span>
              </label>)}
            {n > 0 && (
              <div className="space-y-1">
                <label htmlFor="delete-confirm" className="text-sm font-medium">확인을 위해 <b>{CONFIRM_WORD}</b>를 입력해 주세요</label>
                <Input id="delete-confirm" value={typed} onChange={(e) => setTyped(e.target.value)} autoComplete="off" />
              </div>)}
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={close}>취소</Button>
              <Button variant="danger" disabled={!ready} onClick={() => void run(p.deletable.map((r) => r.id))}>{n === 0 ? '삭제할 수 있는 식당이 없어요' : `${n}곳 삭제`}</Button>
            </div>
          </div>)
      })()}

      {phase.s === 'running' && (() => {
        const g = phase.progress
        return (
          <div className="space-y-4">
            <h2 className="text-lg font-bold">삭제하는 중…</h2>
            <div role="progressbar" aria-label="진행률" aria-valuemin={0} aria-valuemax={g?.total ?? ids.length} aria-valuenow={g?.processed ?? 0} className="h-2 overflow-hidden rounded-full bg-page">
              <div className="h-full bg-red-600 transition-all" style={{ width: `${g && g.total ? Math.round((g.processed / g.total) * 100) : 0}%` }} />
            </div>
            <p role="status" className="text-sm">{g ? <>처리 {g.processed}/{g.total}곳 · 삭제 <b>{g.deleted}</b> · 건너뜀 {g.skipped} · 실패 <b>{g.failed}</b></> : '상태를 확인하는 중…'}</p>
            <div className="flex justify-end"><Button variant="outline" disabled={phase.cancelling} onClick={() => { abort.current?.abort(); setPhase({ ...phase, cancelling: true }) }}>{phase.cancelling ? '중단하는 중…' : '중단'}</Button></div>
          </div>)
      })()}

      {phase.s === 'done' && (() => {
        const r = phase.result
        const retry = [...r.failed.map((f) => f.id), ...r.notRun]
        const by = (k: string) => r.skipped.filter((s) => s.reason === k).length
        return (
          <div className="space-y-4">
            <h2 className="text-lg font-bold">{r.stoppedBy ? '중간에 멈췄어요' : r.failed.length > 0 ? '일부만 삭제했어요' : '삭제했어요'}</h2>
            <p role="status" aria-label="삭제 결과" className="text-sm">
              삭제 <b>{r.deleted.length}곳</b> · 건너뜀 {r.skipped.length}곳{r.skipped.length > 0 && <span className="text-xs text-muted"> (공개 중 {by('published')}, 예약 있음 {by('scheduled')}, 이미 없음 {by('gone')})</span>} · 실패 <b>{r.failed.length}곳</b>{r.notRun.length > 0 && <> · 처리 못 함 {r.notRun.length}곳</>}
            </p>
            {r.stoppedBy === 'forbidden' && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-xs text-amber-900">삭제 권한이 없어서 멈췄어요. 식당 삭제는 최고 관리자만 할 수 있어요. 이미 삭제된 식당은 없어요.</p>}
            {r.stoppedBy === 'cancelled' && <p className="rounded-xl bg-amber-50 p-3 text-xs text-amber-900">중단했어요. 이미 삭제된 식당은 되돌릴 수 없어요.</p>}
            {r.failed.length > 0 && (
              <ul aria-label="삭제하지 못한 식당" className="max-h-48 divide-y divide-line overflow-auto rounded-xl border border-line bg-white text-xs">
                {r.failed.map((f) => <li key={f.id} className="px-3 py-2"><b>{f.name || '(이름 없음)'}</b> <span className="text-muted">ID {f.id}</span><div className="text-amber-900">{f.message}</div></li>)}
              </ul>)}
            <div className="flex flex-wrap justify-end gap-2">
              {retry.length > 0 && r.stoppedBy !== 'forbidden' && <Button variant="outline" onClick={() => void run(retry)}>실패·남은 식당 다시 시도 ({retry.length})</Button>}
              <Button onClick={close}>닫기</Button>
            </div>
          </div>)
      })()}
    </dialog>
  )
}
