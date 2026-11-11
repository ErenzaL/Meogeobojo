import { Loader2 } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { Button, Field, Textarea } from '@/components/ui'
import { cmsSetVisibility } from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import { type BulkProgress, type BulkResult, type BulkTarget, newTag, type RowInfo, runBulkVisibility } from './bulkVisibility'
import { chunk } from './kakao'
import type { Visibility } from './schema'

/** The database's current view of these restaurants (RLS applies: an admin sees all). */
export async function readRestaurantStatus(ids: string[]): Promise<RowInfo[]> {
  const { data, error } = await supabase.from('restaurant_overrides').select('id,name_ko,visibility').in('id', ids)
  if (error) throw error
  return data as RowInfo[]
}

type Preview = { total: number; missing: number; already: number; archived: number; willChange: number; noPhoto: number; noMenu: number; noDescription: number }

/** Exact numbers for the confirmation: what the action would do to THESE restaurants, read from the database now. */
async function loadPreview(ids: string[], to: BulkTarget): Promise<Preview> {
  const rows: { id: string; visibility: Visibility; image_url: string | null; description: string | null }[] = []
  const withMenu = new Set<string>()
  for (const part of chunk(ids, 200)) {
    const r = await supabase.from('restaurant_overrides').select('id,name_ko,visibility,image_url,description').in('id', part)
    if (r.error) throw r.error
    rows.push(...(r.data as typeof rows))
    const m = await supabase.from('restaurant_menus').select('restaurant_id').in('restaurant_id', part)
    if (m.error) throw m.error
    for (const x of m.data as { restaurant_id: string | null }[]) if (x.restaurant_id) withMenu.add(x.restaurant_id)
  }
  const p: Preview = { total: ids.length, missing: ids.length - rows.length, already: 0, archived: 0, willChange: 0, noPhoto: 0, noMenu: 0, noDescription: 0 }
  for (const r of rows) {
    const act = to === 'published' ? (r.visibility === 'published' ? 'already' : r.visibility === 'archived' ? 'archived' : 'change') : (r.visibility === 'published' ? 'change' : 'already')
    if (act === 'already') p.already++
    else if (act === 'archived') p.archived++
    else {
      p.willChange++
      if (!r.image_url) p.noPhoto++
      if (!withMenu.has(r.id)) p.noMenu++
      if (!(r.description ?? '').trim()) p.noDescription++
    }
  }
  return p
}

type Phase =
  | { s: 'loading' }
  | { s: 'confirm'; preview: Preview }
  | { s: 'running'; progress: BulkProgress | null; cancelling: boolean }
  | { s: 'done'; result: BulkResult }
  | { s: 'error'; text: string }

/**
 * Confirmation, progress and result of a bulk publish / hide. Every restaurant still goes through
 * `cms_set_visibility` (see bulkVisibility.ts); this dialog only shows what will happen, how far it is, and what failed.
 */
export default function BulkVisibilityDialog({ to, ids, onClose }: { to: BulkTarget; ids: string[]; onClose: (changed: boolean) => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  const abort = useRef<AbortController | null>(null)
  const changed = useRef(false)
  const [phase, setPhase] = useState<Phase>({ s: 'loading' })
  const [reason, setReason] = useState(to === 'published' ? '일괄 공개' : '일괄 숨김')
  const [reasonMissing, setReasonMissing] = useState(false)
  const publish = to === 'published'
  const verb = publish ? '공개' : '숨기기'

  useEffect(() => { const d = ref.current; if (d && !d.open) d.showModal?.() }, [])
  useEffect(() => {
    let live = true
    loadPreview(ids, to).then((preview) => { if (live) setPhase({ s: 'confirm', preview }) }).catch((e) => { if (live) setPhase({ s: 'error', text: errorMessage(e) }) })
    return () => { live = false }
  }, [ids, to])

  const run = async (list: string[]) => {
    const text = reason.trim()
    if (!text) { setReasonMissing(true); return }
    setReasonMissing(false)
    const ctl = new AbortController()
    abort.current = ctl
    setPhase({ s: 'running', progress: null, cancelling: false })
    try {
      const result = await runBulkVisibility(list, to, text, { readStatus: readRestaurantStatus, setVisibility: (id, t, r) => cmsSetVisibility('restaurant', id, t, r) }, {
        signal: ctl.signal, tag: newTag(),
        onProgress: (progress) => setPhase((p) => (p.s === 'running' ? { ...p, progress } : p)),
      })
      if (result.ok.length > 0) changed.current = true
      setPhase({ s: 'done', result })
    } catch (e) { setPhase({ s: 'error', text: errorMessage(e) }) }
    finally { abort.current = null }
  }

  const close = () => onClose(changed.current)
  const busy = phase.s === 'running'

  return (
    <dialog ref={ref} aria-label={`선택한 식당 ${verb}`} onCancel={(e) => { if (busy) e.preventDefault(); else close() }} className="m-auto w-[min(34rem,94vw)] rounded-2xl border border-line p-6 backdrop:bg-black/40">
      {phase.s === 'loading' && <p role="status" className="text-sm"><Loader2 className="mr-2 inline size-4 animate-spin" />선택한 식당의 현재 상태를 확인하는 중…</p>}

      {phase.s === 'error' && (
        <div className="space-y-4">
          <p role="alert" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">진행하지 못했어요: {phase.text}</p>
          <div className="flex justify-end"><Button variant="outline" onClick={close}>닫기</Button></div>
        </div>)}

      {phase.s === 'confirm' && (() => {
        const p = phase.preview
        const incomplete = publish && p.willChange > 0 && (p.noPhoto > 0 || p.noMenu > 0 || p.noDescription > 0)
        return (
          <div className="space-y-4">
            <h2 className="text-lg font-bold">선택한 식당 {p.total}곳을 {publish ? '공개' : '숨길'}까요?</h2>
            <ul aria-label="선택 내용" className="space-y-1 text-sm">
              <li>선택한 식당 <b>{p.total}곳</b></li>
              <li>{publish ? '이미 공개 중' : '이미 비공개'} <b>{p.already}곳</b> <span className="text-xs text-muted">(건너뛰어요)</span></li>
              {publish && <li>보관됨 <b>{p.archived}곳</b> <span className="text-xs text-muted">(일괄 공개에서 제외해요)</span></li>}
              {p.missing > 0 && <li>찾을 수 없음 <b>{p.missing}곳</b> <span className="text-xs text-muted">(삭제됐거나 볼 수 없어요)</span></li>}
              <li className="pt-1">이번에 {publish ? '공개' : '숨길'} 식당 <b className="text-base">{p.willChange}곳</b></li>
            </ul>
            {incomplete && (
              <div role="alert" aria-label="정보가 덜 채워진 식당" className="space-y-1 rounded-xl bg-amber-50 p-3 text-xs text-amber-900">
                <div><b>정보가 덜 채워진 식당이 포함돼 있어요.</b> 공개할 {p.willChange}곳 중 대표 사진 없음 {p.noPhoto}곳 · 메뉴 없음 {p.noMenu}곳 · 설명 없음 {p.noDescription}곳.</div>
                <div>사진·메뉴·설명은 공개의 필수 조건이 아니라서 이대로 공개돼요. 공개해도 가격·메뉴가 &apos;확인됨&apos;으로 표시되지는 않아요.</div>
              </div>)}
            {!publish && p.willChange > 0 && <p className="rounded-xl bg-amber-50 p-3 text-xs text-amber-900">앱과 웹에서 이 식당들이 바로 보이지 않게 돼요.</p>}
            {p.willChange > 0 && (
              <Field label="사유 (필수, 게시 이력에 남아요)" htmlFor="bulk-reason" error={reasonMissing ? '사유를 입력해 주세요' : undefined}>
                <Textarea id="bulk-reason" value={reason} onChange={(e) => setReason(e.target.value)} />
              </Field>)}
            <p className="text-xs text-muted">식당마다 기존 {verb} 기능과 같은 방법으로 처리해요(권한 확인·검증·게시 이력·감사 기록 포함). 10곳씩 나눠 진행하고, 그 사이에 다른 관리자가 바꾼 식당은 건너뛰어요.</p>
            <div className="flex justify-end gap-2">
              <Button variant="outline" onClick={close}>취소</Button>
              <Button variant={publish ? 'primary' : 'danger'} disabled={p.willChange === 0} onClick={() => void run(ids)}>{p.willChange === 0 ? `${verb}할 식당이 없어요` : `${p.willChange}곳 ${verb}`}</Button>
            </div>
          </div>)
      })()}

      {phase.s === 'running' && (() => {
        const g = phase.progress
        return (
          <div className="space-y-4">
            <h2 className="text-lg font-bold">{publish ? '공개' : '숨기기'} 진행 중…</h2>
            <div role="progressbar" aria-label="진행률" aria-valuemin={0} aria-valuemax={g?.total ?? ids.length} aria-valuenow={g?.processed ?? 0} className="h-2 overflow-hidden rounded-full bg-page">
              <div className="h-full bg-brand-strong transition-all" style={{ width: `${g && g.total ? Math.round((g.processed / g.total) * 100) : 0}%` }} />
            </div>
            <p role="status" className="text-sm">
              {g ? <>처리 {g.processed}/{g.total}곳 · 성공 <b>{g.ok}</b> · 건너뜀 {g.skipped} · 실패 <b>{g.failed}</b>{g.batches > 0 && <span className="text-xs text-muted"> (묶음 {g.batch}/{g.batches})</span>}</> : '상태를 확인하는 중…'}
            </p>
            <div className="flex justify-end">
              <Button variant="outline" disabled={phase.cancelling} onClick={() => { abort.current?.abort(); setPhase({ ...phase, cancelling: true }) }}>{phase.cancelling ? '중단하는 중…' : '중단'}</Button>
            </div>
          </div>)
      })()}

      {phase.s === 'done' && (() => {
        const r = phase.result
        const retryIds = [...r.failed.map((f) => f.id), ...r.notRun]
        return (
          <div className="space-y-4">
            <h2 className="text-lg font-bold">{r.stoppedBy ? '중간에 멈췄어요' : r.failed.length > 0 ? '일부만 처리했어요' : '모두 처리했어요'}</h2>
            <p role="status" aria-label="결과" className="text-sm">
              {publish ? '공개' : '숨김'} 성공 <b>{r.ok.length}곳</b> · 건너뜀 {r.skipped.length}곳 · 실패 <b>{r.failed.length}곳</b>{r.notRun.length > 0 && <> · 처리 못 함 {r.notRun.length}곳</>}
              <span className="block text-xs text-muted">작업 코드 {r.tag} (게시 이력의 사유에 들어 있어요)</span>
            </p>
            {r.stoppedBy === 'forbidden' && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-xs text-amber-900">관리자 권한이 확인되지 않아 멈췄어요. 다시 로그인한 뒤 시도해 주세요. 이미 처리된 식당은 그대로예요.</p>}
            {r.stoppedBy === 'cancelled' && <p className="rounded-xl bg-amber-50 p-3 text-xs text-amber-900">중단했어요. 이미 처리된 식당은 그대로예요.</p>}
            {r.failed.length > 0 && (
              <div className="space-y-1">
                <div className="text-sm font-medium">실패한 식당</div>
                <ul aria-label="실패한 식당" className="max-h-48 divide-y divide-line overflow-auto rounded-xl border border-line bg-white text-xs">
                  {r.failed.map((f) => (
                    <li key={f.id} className="px-3 py-2"><b>{f.name || '(이름 없음)'}</b> <span className="text-muted">ID {f.id}</span><div className="text-amber-900">{f.message}</div></li>))}
                </ul>
              </div>)}
            <div className="flex flex-wrap justify-end gap-2">
              {retryIds.length > 0 && <Button variant="outline" onClick={() => void run(retryIds)}>실패·남은 식당 다시 시도 ({retryIds.length})</Button>}
              <Button onClick={close}>닫기</Button>
            </div>
          </div>)
      })()}
    </dialog>
  )
}
