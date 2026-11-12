import { useQueryClient } from '@tanstack/react-query'
import { Download, FileDown, Loader2, Upload } from 'lucide-react'
import { useEffect, useMemo, useRef, useState, type DragEvent } from 'react'
import { Badge, Button, Field, Textarea } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import { fetchExportItems, fetchExportRestaurants, fetchMenuOwners, fetchMenuState, fetchRestaurantById, fetchRestaurantsByPlaceIds, publishDeps, saveDeps } from './menuData'
import { buildMenuCsv, EXPORT_COLUMNS, MAX_FILE_BYTES, parseMenuCsv, TEMPLATE_COLUMNS, templateCsv, type ParsedMenuCsv } from './menuCsv'
import { exportRows, type ExportSource } from './menuExport'
import { applyPlan, buildPlan, publishSaved, type ImportMode, type ImportScope, type MenuState, type Plan, type PlanOptions, type PlanRow, type PublishResult, type RestaurantRef, type RowAction, type SavedRestaurant, type SaveFailure } from './menuImport'

/** Starts a browser download of [text] (UTF-8 with a BOM, so Excel shows Korean correctly). */
export function downloadText(name: string, text: string) {
  const url = URL.createObjectURL(new Blob([text], { type: 'text/csv;charset=utf-8' }))
  const a = document.createElement('a')
  a.href = url; a.download = name; a.click()
  URL.revokeObjectURL(url)
}
const today = () => new Date().toISOString().slice(0, 10).replace(/-/g, '')

type Selected = { id: string; name_ko: string } | null

/** 메뉴·가격 CSV: 양식 다운로드 / 가져오기 / 내보내기. */
type School = { id: string; name: string } | null

export default function MenuCsvTools({ selected, search, university = null }: { selected: Selected; search: string; university?: School }) {
  const [dialog, setDialog] = useState<'import' | 'export' | null>(null)
  const qc = useQueryClient()
  const refresh = () => { void qc.invalidateQueries({ queryKey: ['cms', 'restaurant_menus'] }); void qc.invalidateQueries({ queryKey: ['cms-overview', 'restaurant_menus'] }); void qc.invalidateQueries({ queryKey: ['menus'] }) }
  return (
    <>
      <Button variant="outline" onClick={() => downloadText('meogeobojo_menu_import_template.csv', templateCsv())}><FileDown className="size-4" />CSV 양식 다운로드</Button>
      <Button variant="outline" onClick={() => setDialog('import')}><Upload className="size-4" />CSV 가져오기</Button>
      <Button variant="outline" onClick={() => setDialog('export')}><Download className="size-4" />CSV 내보내기</Button>
      {dialog === 'import' && <ImportDialog selected={selected} onClose={(changed) => { setDialog(null); if (changed) refresh() }} />}
      {dialog === 'export' && <ExportDialog selected={selected} search={search} university={university} onClose={() => setDialog(null)} />}
    </>
  )
}

// ---------------------------------------------------------------------------------------------------------------------
// import
// ---------------------------------------------------------------------------------------------------------------------
type Ctx = { restaurants: Map<string, RestaurantRef>; states: Map<string, MenuState>; owners: Map<string, string>; selected: RestaurantRef | null }
type Step =
  | { s: 'pick'; error?: string }
  | { s: 'loading'; text: string }
  | { s: 'preview' }
  | { s: 'saving'; done: number; total: number }
  | { s: 'done' }

const ACTION_LABEL: Record<RowAction, { text: string; tone: 'green' | 'brand' | 'neutral' | 'amber' | 'red' }> = {
  add: { text: '추가', tone: 'green' }, update: { text: '갱신', tone: 'brand' }, unchanged: { text: '변경 없음', tone: 'neutral' }, duplicate: { text: '중복', tone: 'amber' },
  invalid: { text: '오류', tone: 'red' }, unmatched: { text: '식당 없음', tone: 'red' }, name_mismatch: { text: '이름 불일치', tone: 'amber' },
}
const MAX_SHOWN = 200
const won = (n: number | null) => (n == null ? '미정' : `${n.toLocaleString('ko-KR')}원`)

function ImportDialog({ selected, onClose }: { selected: Selected; onClose: (changed: boolean) => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => { const d = ref.current; if (d && !d.open) d.showModal?.() }, [])
  const [step, setStep] = useState<Step>({ s: 'pick' })
  const [fileName, setFileName] = useState('')
  const [parsed, setParsed] = useState<ParsedMenuCsv | null>(null)
  const [ctx, setCtx] = useState<Ctx | null>(null)
  const [mode, setMode] = useState<ImportMode>('append')
  const [scope, setScope] = useState<ImportScope>('file')
  const [allowMismatch, setAllowMismatch] = useState(false)
  const [onlyIssues, setOnlyIssues] = useState(false)
  const [drag, setDrag] = useState(false)
  const [saved, setSaved] = useState<SavedRestaurant[]>([])
  const [failed, setFailed] = useState<SaveFailure[]>([])
  const [untouched, setUntouched] = useState(0)
  const [stopped, setStopped] = useState<string | null>(null)
  const [publishReason, setPublishReason] = useState('메뉴 CSV 가져오기')
  const [publishOpen, setPublishOpen] = useState(false)
  const [publishing, setPublishing] = useState(false)
  const [published, setPublished] = useState<PublishResult | null>(null)
  const changed = useRef(false)
  const abort = useRef<AbortController | null>(null)
  const fileInput = useRef<HTMLInputElement>(null)

  const opts: PlanOptions = useMemo(() => ({ mode, scope, selected: ctx?.selected ?? null, allowNameMismatch: allowMismatch }), [mode, scope, ctx?.selected, allowMismatch])
  const plan: Plan | null = useMemo(() => (parsed && ctx ? buildPlan(parsed.rows, ctx.restaurants, ctx.states, ctx.owners, opts) : null), [parsed, ctx, opts])

  const readFile = async (file: File) => {
    if (file.size > MAX_FILE_BYTES) return setStep({ s: 'pick', error: `파일이 너무 커요 (${Math.round(file.size / 1024 / 1024)}MB). ${MAX_FILE_BYTES / 1024 / 1024}MB 이하로 나눠 주세요.` })
    setFileName(file.name)
    setStep({ s: 'loading', text: '파일을 읽는 중…' })
    try {
      const p = parseMenuCsv(await file.text())
      if (p.fatal) return setStep({ s: 'pick', error: p.fatal })
      setParsed(p)
      // what the plan needs to know: the restaurants of the file, their menu lists, and who owns the menu ids in it
      setStep({ s: 'loading', text: '식당과 기존 메뉴를 확인하는 중…' })
      const usable = p.rows.filter((r) => r.errors.length === 0)
      const restaurants = await fetchRestaurantsByPlaceIds(usable.map((r) => r.kakaoPlaceId).filter(Boolean))
      const sel = selected ? await fetchRestaurantById(selected.id) : null
      const need = new Map<string, RestaurantRef>()
      for (const r of restaurants.values()) need.set(r.id, r)
      if (sel) need.set(sel.id, sel)
      const states = new Map<string, MenuState>()
      const list = [...need.values()]
      let next = 0
      await Promise.all(Array.from({ length: Math.min(4, list.length) }, async () => {
        while (next < list.length) {
          const r = list[next++]
          states.set(r.id, await fetchMenuState(r.id))
          setStep({ s: 'loading', text: `기존 메뉴를 확인하는 중… ${states.size}/${list.length}` })
        }
      }))
      const owners = await fetchMenuOwners(usable.map((r) => r.menuId).filter(Boolean))
      setCtx({ restaurants, states, owners, selected: sel })
      setScope(sel && usable.every((r) => !r.kakaoPlaceId) ? 'selected' : 'file') // a file with no place ids can only mean the selected restaurant
      setStep({ s: 'preview' })
    } catch (e) { setStep({ s: 'pick', error: errorMessage(e) }) }
  }
  const onDrop = (e: DragEvent) => { e.preventDefault(); setDrag(false); const f = e.dataTransfer.files?.[0]; if (f) void readFile(f) }

  const save = async (only?: Set<string>) => {
    if (!plan) return
    const ctl = new AbortController(); abort.current = ctl
    setStep({ s: 'saving', done: 0, total: only?.size ?? plan.counts.restaurantsToSave })
    try {
      const res = await applyPlan(plan, opts, ctx!.owners, saveDeps, { signal: ctl.signal, only, onProgress: (p) => setStep({ s: 'saving', done: p.done, total: p.total }) })
      setSaved((prev) => [...prev.filter((s) => !res.saved.some((n) => n.restaurantId === s.restaurantId)), ...res.saved])
      setFailed(res.failed)
      setUntouched((n) => n + res.untouched)
      setStopped(res.stoppedBy === 'forbidden' ? '관리자 권한이 확인되지 않아 멈췄어요. 이미 저장된 식당은 그대로예요.' : res.stoppedBy === 'cancelled' ? '중단했어요. 이미 저장된 식당은 그대로예요.' : null)
      if (res.saved.length > 0) changed.current = true
      setStep({ s: 'done' })
    } catch (e) { setStopped(errorMessage(e)); setStep({ s: 'done' }) }
    finally { abort.current = null }
  }

  const doPublish = async () => {
    if (!publishReason.trim()) return
    setPublishing(true)
    try {
      const res = await publishSaved(saved, publishReason.trim(), publishDeps)
      setPublished(res)
      if (res.published.length > 0) changed.current = true
    } finally { setPublishing(false) }
  }

  const errorCsv = () => {
    if (!plan) return
    const bad = plan.rows.filter((r) => ['invalid', 'unmatched', 'name_mismatch', 'duplicate'].includes(r.action))
    downloadText(`menu-import-errors-${today()}.csv`, buildMenuCsv(bad.map((r) => ({
      kakao_place_id: r.csv.kakaoPlaceId, restaurant_name: r.csv.restaurantName, menu_name: r.csv.menuName, price_krw: r.csv.priceRaw, menu_category: r.csv.category,
      description: r.csv.description, is_available: r.csv.availableRaw, menu_id: r.csv.menuId, error: r.messages.join(' / '),
    })), [...TEMPLATE_COLUMNS, 'menu_id', 'error']))
  }

  const reset = () => { setParsed(null); setCtx(null); setFileName(''); setStep({ s: 'pick' }); setSaved([]); setFailed([]); setUntouched(0); setStopped(null); setPublished(null); setPublishOpen(false) }
  const busy = step.s === 'saving' || step.s === 'loading' || publishing
  const close = () => onClose(changed.current)

  return (
    <dialog ref={ref} aria-label="메뉴 CSV 가져오기" onCancel={(e) => { if (busy) e.preventDefault(); else close() }} className="m-auto w-[min(60rem,96vw)] rounded-2xl border border-line p-6 backdrop:bg-black/40">
      <div className="space-y-4">
        <div className="flex items-start justify-between gap-3">
          <h2 className="text-lg font-bold">메뉴 CSV 가져오기</h2>
          <Button size="sm" variant="ghost" disabled={busy} onClick={close}>닫기</Button>
        </div>
        <p className="text-xs text-muted">가져온 메뉴는 <b>초안</b>으로만 저장돼요. 자동으로 게시하지 않고, 이미 게시된 메뉴와 식당의 공개 상태는 바뀌지 않아요. 기존 메뉴는 삭제되지 않아요.</p>

        {step.s === 'pick' && (
          <div className="space-y-3">
            <div role="button" tabIndex={0} aria-label="CSV 파일 올리기 영역" onClick={() => fileInput.current?.click()} onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') fileInput.current?.click() }}
              onDragOver={(e) => { e.preventDefault(); setDrag(true) }} onDragLeave={() => setDrag(false)} onDrop={onDrop}
              className={`grid cursor-pointer place-items-center rounded-2xl border-2 border-dashed p-10 text-center text-sm ${drag ? 'border-brand-strong bg-brand/10' : 'border-line bg-page/40'}`}>
              <div><Upload className="mx-auto mb-2 size-6 text-muted" /><div className="font-medium">CSV 파일을 여기에 끌어다 놓거나 눌러서 고르세요</div><div className="mt-1 text-xs text-muted">UTF-8 (BOM 있어도 돼요) · 쉼표로 구분 · {MAX_FILE_BYTES / 1024 / 1024}MB 이하</div></div>
              <input ref={fileInput} type="file" accept=".csv,text/csv" hidden aria-label="CSV 파일 선택" onChange={(e) => { const f = e.target.files?.[0]; if (f) void readFile(f); e.target.value = '' }} />
            </div>
            <p className="text-xs text-muted">열: {TEMPLATE_COLUMNS.join(', ')} (선택: menu_id). 식당은 <b>kakao_place_id</b>로만 찾아요. 가격을 모르면 비워 두세요(0원이 아니라 &lsquo;가격 미정&rsquo;으로 저장돼요).</p>
            {step.error && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{step.error}</p>}
          </div>)}

        {step.s === 'loading' && <p role="status" className="text-sm"><Loader2 className="mr-2 inline size-4 animate-spin" />{step.text}</p>}

        {step.s === 'preview' && plan && parsed && (() => {
          const c = plan.counts
          const importable = c.add + c.update
          const shown = plan.rows.filter((r) => !onlyIssues || !['add', 'update', 'unchanged'].includes(r.action))
          return (
            <div className="space-y-3">
              <div className="flex flex-wrap items-center gap-3 text-sm"><span className="font-medium">{fileName}</span><Button size="sm" variant="ghost" onClick={reset}>다른 파일 고르기</Button></div>
              <div className="grid gap-3 rounded-xl border border-line bg-white p-3 text-sm sm:grid-cols-2">
                <fieldset className="space-y-1"><legend className="mb-1 text-xs font-semibold text-muted">가져오기 방식</legend>
                  <label className="flex items-start gap-2"><input type="radio" name="mode" checked={mode === 'append'} onChange={() => setMode('append')} /><span><b>추가</b> — 새 메뉴만 넣어요. 이미 있는 메뉴는 건너뛰고 바꾸지 않아요.</span></label>
                  <label className="flex items-start gap-2"><input type="radio" name="mode" checked={mode === 'update'} onChange={() => setMode('update')} /><span><b>갱신</b> — 이미 있는 메뉴는 파일에 적힌 값으로 바꾸고(빈 칸은 그대로), 없는 메뉴는 추가해요. 메뉴 ID가 있으면 ID로, 없으면 메뉴 이름이 똑같은 것으로 찾아요.</span></label>
                </fieldset>
                <fieldset className="space-y-1"><legend className="mb-1 text-xs font-semibold text-muted">대상 식당</legend>
                  <label className="flex items-start gap-2"><input type="radio" name="scope" checked={scope === 'file'} onChange={() => setScope('file')} /><span><b>파일에 있는 모든 식당</b> (kakao_place_id 기준)</span></label>
                  <label className={`flex items-start gap-2 ${ctx?.selected ? '' : 'opacity-50'}`}><input type="radio" name="scope" disabled={!ctx?.selected} checked={scope === 'selected'} onChange={() => setScope('selected')} /><span><b>선택한 식당만</b>{ctx?.selected ? ` (${ctx.selected.name_ko})` : ' (식당을 먼저 선택하세요)'} — 장소 ID가 비어 있는 줄은 이 식당으로 봐요</span></label>
                  {c.nameMismatch > 0 && <label className="flex items-start gap-2 pt-1 text-amber-900"><input type="checkbox" checked={allowMismatch} onChange={(e) => setAllowMismatch(e.target.checked)} /><span>식당 이름이 달라도 장소 ID가 맞으면 가져오기 ({c.nameMismatch}줄)</span></label>}
                </fieldset>
              </div>

              <div role="status" aria-label="가져오기 미리보기 요약" className="space-y-1 rounded-xl border border-line bg-white p-3 text-sm">
                <div>전체 <b>{c.rows}줄</b> · 가져올 수 있는 줄 <b>{importable}</b> (추가 {c.add} · 갱신 {c.update}) · 변경 없음 {c.unchanged} · 오류 <b>{c.invalid + c.unmatched}</b> · 중복 {c.duplicate}{c.nameMismatch > 0 && <> · 이름 불일치(제외) {c.nameMismatch}</>}</div>
                <div>찾은 식당 <b>{c.matchedRestaurants}곳</b> · 찾지 못한 식당 <b>{c.unmatchedRestaurants}곳</b>{plan.unmatchedIds.length > 0 && <span className="text-xs text-muted"> ({plan.unmatchedIds.slice(0, 8).map((u) => u.kakaoPlaceId).join(', ')}{plan.unmatchedIds.length > 8 ? ' …' : ''})</span>} · 초안으로 저장할 식당 {c.restaurantsToSave}곳</div>
                {plan.restaurants.some((r) => r.hasDraft && r.adds + r.updates > 0) && <div className="text-xs text-amber-900">{plan.restaurants.filter((r) => r.hasDraft && r.adds + r.updates > 0).length}곳은 이미 저장된 초안이 있어요. 그 초안 위에 합쳐지고, 기존 내용은 지워지지 않아요.</div>}
                {parsed.ignoredColumns.length > 0 && <div className="text-xs text-muted">무시한 열: {parsed.ignoredColumns.join(', ')}</div>}
              </div>

              <label className="flex items-center gap-2 text-xs text-muted"><input type="checkbox" checked={onlyIssues} onChange={(e) => setOnlyIssues(e.target.checked)} />문제 있는 줄만 보기</label>
              <div className="max-h-96 overflow-auto rounded-xl border border-line bg-white">
                <table aria-label="미리보기" className="w-full text-xs">
                  <thead className="sticky top-0 border-b border-line bg-page text-left text-muted"><tr>{['줄', '결과', '식당', '메뉴', '가격', '분류', '설명', '판매', '내용'].map((h) => <th key={h} className="px-3 py-2 font-medium">{h}</th>)}</tr></thead>
                  <tbody>
                    {shown.slice(0, MAX_SHOWN).map((r) => <PreviewRow key={r.line} r={r} />)}
                  </tbody>
                </table>
              </div>
              {shown.length > MAX_SHOWN && <p className="text-xs text-muted">처음 {MAX_SHOWN}줄만 보여줘요 (전체 {shown.length}줄). 요약 숫자는 모든 줄 기준이에요.</p>}

              <div className="flex flex-wrap justify-end gap-2">
                {c.invalid + c.unmatched + c.duplicate + c.nameMismatch > 0 && <Button variant="outline" onClick={errorCsv}>문제 있는 줄 CSV 내려받기</Button>}
                <Button variant="outline" onClick={close}>취소</Button>
                <Button disabled={importable === 0} onClick={() => void save()}>{importable === 0 ? '가져올 메뉴가 없어요' : `초안으로 저장 (메뉴 ${importable}개, 식당 ${c.restaurantsToSave}곳)`}</Button>
              </div>
            </div>)
        })()}

        {step.s === 'saving' && (
          <div className="space-y-3">
            <div role="progressbar" aria-label="진행률" aria-valuemin={0} aria-valuemax={step.total} aria-valuenow={step.done} className="h-2 overflow-hidden rounded-full bg-page"><div className="h-full bg-brand-strong transition-all" style={{ width: `${step.total ? Math.round((step.done / step.total) * 100) : 0}%` }} /></div>
            <p role="status" className="text-sm">초안으로 저장하는 중… 식당 {step.done}/{step.total}곳</p>
            <div className="flex justify-end"><Button variant="outline" onClick={() => abort.current?.abort()}>중단</Button></div>
          </div>)}

        {step.s === 'done' && (
          <div className="space-y-3">
            <h3 className="font-bold">{stopped ? '중간에 멈췄어요' : failed.length > 0 ? '일부만 저장했어요' : '초안으로 저장했어요'}</h3>
            <p role="status" aria-label="가져오기 결과" className="rounded-xl border border-line bg-white p-3 text-sm">
              초안으로 저장한 식당 <b>{saved.length}곳</b> · 메뉴 추가 <b>{saved.reduce((n, s) => n + s.added, 0)}개</b> · 갱신 <b>{saved.reduce((n, s) => n + s.updated, 0)}개</b> · 바뀐 게 없어 건너뛴 식당 {untouched}곳 · 저장 못 한 식당 <b>{failed.length}곳</b>
              <span className="mt-1 block text-xs text-muted">아직 게시하지 않았어요: 앱과 웹에는 보이지 않아요. 메뉴·가격 화면에서 식당을 골라 게시하거나, 아래에서 한꺼번에 게시할 수 있어요.</span>
            </p>
            {stopped && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-xs text-amber-900">{stopped}</p>}
            {failed.length > 0 && (
              <ul aria-label="저장하지 못한 식당" className="max-h-40 divide-y divide-line overflow-auto rounded-xl border border-line bg-white text-xs">
                {failed.map((f) => <li key={f.restaurantId} className="px-3 py-2"><b>{f.name}</b> <span className="text-muted">ID {f.restaurantId}</span><div className="text-amber-900">{f.message}</div></li>)}
              </ul>)}
            {published && (
              <p role="status" aria-label="게시 결과" className="rounded-xl border border-line bg-white p-3 text-sm">게시한 식당 <b>{published.published.length}곳</b> · 게시 못 한 식당 <b>{published.failed.length}곳</b>
                {published.failed.length > 0 && <span className="block text-xs text-amber-900">{published.failed.map((f) => `${f.name}: ${f.message}`).join(' / ')}</span>}</p>)}
            {publishOpen && !published && saved.length > 0 && (
              <div className="space-y-2 rounded-xl border border-line bg-white p-3" role="group" aria-label="가져온 메뉴 게시">
                <p className="text-sm"><b>{saved.length}곳</b>의 메뉴 초안을 게시할까요? 기존 게시 기능(검증·게시 이력·감사 기록)으로 식당마다 처리하고, 식당의 공개 상태는 바뀌지 않아요.</p>
                {saved.some((s) => s.hadDraft) && <p className="text-xs text-amber-900">{saved.filter((s) => s.hadDraft).length}곳은 가져오기 전에 이미 초안이 있었어요. 그 초안 전체(가져온 메뉴 포함)가 함께 게시돼요.</p>}
                <Field label="사유 (필수, 게시 이력에 남아요)" htmlFor="menu-publish-reason"><Textarea id="menu-publish-reason" value={publishReason} onChange={(e) => setPublishReason(e.target.value)} /></Field>
                <div className="flex justify-end gap-2"><Button variant="outline" onClick={() => setPublishOpen(false)}>취소</Button><Button disabled={publishing || !publishReason.trim()} onClick={() => void doPublish()}>{publishing && <Loader2 className="size-4 animate-spin" />}{saved.length}곳 게시</Button></div>
              </div>)}
            <div className="flex flex-wrap justify-end gap-2">
              {failed.length > 0 && <Button variant="outline" onClick={() => void save(new Set(failed.map((f) => f.restaurantId)))}>저장 못 한 식당 다시 시도 ({failed.length})</Button>}
              {saved.length > 0 && !published && !publishOpen && <Button variant="outline" onClick={() => setPublishOpen(true)}>가져온 {saved.length}곳 메뉴 게시…</Button>}
              <Button variant="outline" onClick={reset}>다른 파일 가져오기</Button>
              <Button onClick={close}>닫기</Button>
            </div>
          </div>)}
      </div>
    </dialog>
  )
}

function PreviewRow({ r }: { r: PlanRow }) {
  const a = ACTION_LABEL[r.action]
  return (
    <tr className="border-b border-line align-top last:border-0">
      <td className="px-3 py-2 tabular-nums text-muted">{r.line}</td>
      <td className="px-3 py-2"><Badge tone={a.tone}>{a.text}</Badge></td>
      <td className="px-3 py-2">{r.restaurantName || r.csv.restaurantName || (r.csv.kakaoPlaceId ? `ID ${r.csv.kakaoPlaceId}` : '—')}</td>
      <td className="px-3 py-2 font-medium">{r.menuName || '—'}</td>
      <td className="px-3 py-2 tabular-nums">{r.csv.price == null ? '미정' : won(r.csv.price)}</td>
      <td className="px-3 py-2">{r.csv.category || '—'}</td>
      <td className="max-w-48 truncate px-3 py-2" title={r.csv.description}>{r.csv.description || '—'}</td>
      <td className="px-3 py-2">{r.csv.available == null ? '—' : r.csv.available ? '판매 중' : '품절'}</td>
      <td className="px-3 py-2">
        {r.changes.length > 0 && <ul className="mb-1 space-y-0.5">{r.changes.map((c) => <li key={c.field}><span className="text-muted">{c.field}:</span> {c.from} → <b>{c.to}</b></li>)}</ul>}
        {r.messages.map((m) => <div key={m} className={r.action === 'invalid' || r.action === 'unmatched' ? 'text-red-700' : r.action === 'add' || r.action === 'update' || r.action === 'unchanged' ? 'text-muted' : 'text-amber-900'}>{m}</div>)}
      </td>
    </tr>
  )
}

// ---------------------------------------------------------------------------------------------------------------------
// export
// ---------------------------------------------------------------------------------------------------------------------
type ExportScope = 'selected' | 'university' | 'search' | 'all'

function ExportDialog({ selected, search, university, onClose }: { selected: Selected; search: string; university: School; onClose: () => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => { const d = ref.current; if (d && !d.open) d.showModal?.() }, [])
  const [scope, setScope] = useState<ExportScope>(selected ? 'selected' : university ? 'university' : 'all')
  const [source, setSource] = useState<ExportSource>('editing')
  const [archived, setArchived] = useState(false)
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<{ ok: boolean; text: string } | null>(null)

  const run = async () => {
    setBusy(true); setResult(null)
    try {
      const restaurants = await fetchExportRestaurants(scope === 'selected' && selected ? { restaurantId: selected.id } : scope === 'university' && university ? { universityId: university.id } : scope === 'search' ? { search } : 'all')
      const items = await fetchExportItems(restaurants.map((r) => r.id), source)
      const rows = exportRows(restaurants, items, archived)
      downloadText(`menus-${scope}-${today()}.csv`, buildMenuCsv(rows, EXPORT_COLUMNS))
      const noId = restaurants.filter((r) => !r.kakao_place_id && (items.get(r.id)?.length ?? 0) > 0).length
      setResult({ ok: true, text: `식당 ${restaurants.length}곳, 메뉴 ${rows.length}개를 내보냈어요.${rows.length === 0 ? ' (내보낼 메뉴가 없어요)' : ''}${noId > 0 ? ` 장소 ID가 없는 식당 ${noId}곳은 kakao_place_id 칸이 비어 있어요(그 줄은 “선택한 식당만”으로만 가져올 수 있어요).` : ''}` })
    } catch (e) { setResult({ ok: false, text: errorMessage(e) }) } finally { setBusy(false) }
  }

  return (
    <dialog ref={ref} aria-label="메뉴 CSV 내보내기" onCancel={(e) => { if (busy) e.preventDefault(); else onClose() }} className="m-auto w-[min(32rem,94vw)] rounded-2xl border border-line p-6 backdrop:bg-black/40">
      <div className="space-y-4">
        <h2 className="text-lg font-bold">메뉴 CSV 내보내기</h2>
        <fieldset className="space-y-1 text-sm"><legend className="mb-1 text-xs font-semibold text-muted">내보낼 식당</legend>
          <label className={`flex items-center gap-2 ${selected ? '' : 'opacity-50'}`}><input type="radio" name="escope" disabled={!selected} checked={scope === 'selected'} onChange={() => setScope('selected')} />선택한 식당{selected ? ` (${selected.name_ko})` : ' (식당을 먼저 선택하세요)'}</label>
          <label className={`flex items-center gap-2 ${university ? '' : 'opacity-50'}`}><input type="radio" name="escope" disabled={!university} checked={scope === 'university'} onChange={() => setScope('university')} />선택한 대학교의 식당{university ? ` (${university.name})` : ' (위에서 대학교를 먼저 고르세요)'}</label>
          <label className="flex items-center gap-2"><input type="radio" name="escope" checked={scope === 'search'} onChange={() => setScope('search')} />검색한 식당{search.trim() ? ` (“${search.trim()}”)` : ' (검색어가 없으면 전체)'}</label>
          <label className="flex items-center gap-2"><input type="radio" name="escope" checked={scope === 'all'} onChange={() => setScope('all')} />모든 식당</label>
        </fieldset>
        <fieldset className="space-y-1 text-sm"><legend className="mb-1 text-xs font-semibold text-muted">어떤 메뉴를</legend>
          <label className="flex items-start gap-2"><input type="radio" name="esource" checked={source === 'editing'} onChange={() => setSource('editing')} /><span>편집 중인 내용 <span className="text-xs text-muted">(초안이 있으면 초안, 없으면 게시된 메뉴 · 다시 가져오기에 알맞아요)</span></span></label>
          <label className="flex items-start gap-2"><input type="radio" name="esource" checked={source === 'published'} onChange={() => setSource('published')} /><span>게시된 메뉴만</span></label>
        </fieldset>
        <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={archived} onChange={(e) => setArchived(e.target.checked)} />보관된 메뉴도 포함</label>
        <p className="text-xs text-muted">열: {EXPORT_COLUMNS.join(', ')}. menu_id와 식당 연결(kakao_place_id)이 들어 있어서, 고친 뒤 “갱신”으로 다시 가져오면 같은 메뉴가 바뀌어요. 가격을 모르는 메뉴는 가격 칸이 비어 있어요.</p>
        {result && <p role={result.ok ? 'status' : 'alert'} className={`rounded-xl p-3 text-sm ${result.ok ? 'bg-brand/30' : 'bg-amber-50 text-amber-900'}`}>{result.text}</p>}
        <div className="flex justify-end gap-2"><Button variant="outline" disabled={busy} onClick={onClose}>닫기</Button><Button disabled={busy} onClick={() => void run()}>{busy && <Loader2 className="size-4 animate-spin" />}내보내기</Button></div>
      </div>
    </dialog>
  )
}
