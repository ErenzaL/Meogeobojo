import { Loader2, Upload } from 'lucide-react'
import { useEffect, useMemo, useRef, useState, type DragEvent } from 'react'
import { Badge, Button } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import { fetchMenuOwners, fetchMenuState, fetchRestaurantById, saveDeps } from './menuData'
import { MAX_FILE_BYTES, parseMenuCsv, TEMPLATE_COLUMNS, templateCsv, type ParsedMenuCsv } from './menuCsv'
import { applyPlan, buildPlan, checkTarget, type ImportMode, type MenuState, type Plan, type PlanOptions, type RestaurantRef, type SaveResult, type TargetCheck } from './menuImport'
import { ACTION_LABEL, downloadText, won } from './MenuCsvTools'

/**
 * CSV import for ONE restaurant: the restaurant chosen on the 메뉴·가격 page is the only target. Every menu goes to that
 * restaurant's id (never matched by name). A file that names another restaurant / place id is refused before anything is
 * planned. The result is saved as the restaurant's menu DRAFT through the existing `cms_save_draft` (server-side checks,
 * admin-only, revision-checked); publishing stays with the page's publishing toolbar.
 */
type Step =
  | { s: 'pick'; error?: string }
  | { s: 'loading'; text: string }
  | { s: 'blocked'; check: TargetCheck }
  | { s: 'preview' }
  | { s: 'confirm-replace' }
  | { s: 'saving' }
  | { s: 'done'; result: SaveResult | null; error?: string }

const MODES: { id: ImportMode; label: string; help: string }[] = [
  { id: 'append', label: '새 메뉴만 추가', help: '이미 있는 메뉴는 건너뛰고 바꾸지 않아요.' },
  { id: 'update', label: '기존 메뉴 업데이트', help: '이미 있는 메뉴는 파일에 적힌 값으로 바꾸고(빈 칸은 그대로), 없는 메뉴는 추가해요.' },
  { id: 'replace', label: '전체 교체', help: '파일의 메뉴가 이 식당의 전체 메뉴 목록이 돼요. 파일에 없는 메뉴는 초안에서 빠져요 (게시하면 보관 처리되고, 삭제되지는 않아요).' },
]
const MAX_SHOWN = 200

export default function RestaurantMenuImport({ restaurantId, restaurantName, onClose }: { restaurantId: string; restaurantName: string; onClose: (changed: boolean) => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => { const d = ref.current; if (d && !d.open) d.showModal?.() }, [])
  const [step, setStep] = useState<Step>({ s: 'pick' })
  const [fileName, setFileName] = useState('')
  const [parsed, setParsed] = useState<ParsedMenuCsv | null>(null)
  const [ctx, setCtx] = useState<{ restaurant: RestaurantRef; state: MenuState; owners: Map<string, string>; notes: string[] } | null>(null)
  const [mode, setMode] = useState<ImportMode>('append')
  const [drag, setDrag] = useState(false)
  const changed = useRef(false)
  const submitting = useRef(false) // a double click must not save twice
  const fileInput = useRef<HTMLInputElement>(null)

  const opts: PlanOptions = useMemo(() => ({ mode, scope: 'selected', selected: ctx?.restaurant ?? null, allowNameMismatch: true }), [mode, ctx?.restaurant])
  const plan: Plan | null = useMemo(() => (parsed && ctx ? buildPlan(parsed.rows, new Map(), new Map([[ctx.restaurant.id, ctx.state]]), ctx.owners, opts) : null), [parsed, ctx, opts])
  const rp = plan?.restaurants[0] ?? null

  const readFile = async (file: File) => {
    if (file.size > MAX_FILE_BYTES) return setStep({ s: 'pick', error: `파일이 너무 커요 (${Math.round(file.size / 1024 / 1024)}MB). ${MAX_FILE_BYTES / 1024 / 1024}MB 이하로 나눠 주세요.` })
    setFileName(file.name); setParsed(null); setCtx(null)
    setStep({ s: 'loading', text: '파일을 읽는 중…' })
    try {
      const p = parseMenuCsv(await file.text())
      if (p.fatal) return setStep({ s: 'pick', error: p.fatal })
      setStep({ s: 'loading', text: '식당과 기존 메뉴를 확인하는 중…' })
      const restaurant = await fetchRestaurantById(restaurantId) // the id chosen on the page is authoritative
      if (!restaurant) return setStep({ s: 'pick', error: '선택한 식당을 찾을 수 없어요. 새로고침한 뒤 다시 시도해 주세요.' })
      const check = checkTarget(p.rows, restaurant)
      setParsed(p)
      if (check.blockers.length > 0) return setStep({ s: 'blocked', check })
      const [state, owners] = await Promise.all([fetchMenuState(restaurant.id), fetchMenuOwners(p.rows.map((r) => r.menuId).filter(Boolean))])
      setCtx({ restaurant, state, owners, notes: check.notes })
      setStep({ s: 'preview' })
    } catch (e) { setStep({ s: 'pick', error: errorMessage(e) }) }
  }
  const onDrop = (e: DragEvent) => { e.preventDefault(); setDrag(false); const f = e.dataTransfer.files?.[0]; if (f) void readFile(f) }

  const save = async () => {
    if (!plan || !ctx || submitting.current) return
    submitting.current = true
    setStep({ s: 'saving' })
    try {
      // applyPlan reads the restaurant's menus again and re-plans against what is there NOW (stale preview / concurrent edit safe)
      const result = await applyPlan(plan, opts, ctx.owners, saveDeps)
      if (result.saved.length > 0) changed.current = true
      setStep({ s: 'done', result })
    } catch (e) { setStep({ s: 'done', result: null, error: errorMessage(e) }) }
    finally { submitting.current = false }
  }

  const reset = () => { setParsed(null); setCtx(null); setFileName(''); setMode('append'); setStep({ s: 'pick' }) }
  const busy = step.s === 'loading' || step.s === 'saving'
  const close = () => onClose(changed.current)

  return (
    <dialog ref={ref} aria-label="식당 메뉴 CSV 가져오기" onCancel={(e) => { if (busy) e.preventDefault(); else close() }} className="m-auto w-[min(56rem,96vw)] rounded-2xl border border-line p-6 backdrop:bg-black/40">
      <div className="space-y-4">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h2 className="text-lg font-bold">CSV로 메뉴 가져오기</h2>
            <p className="text-sm">가져올 식당: <b data-testid="import-target">{restaurantName}</b> <span className="text-xs text-muted">이 식당의 메뉴만 바뀌어요. 다른 식당은 건드리지 않아요.</span></p>
          </div>
          <Button size="sm" variant="ghost" disabled={busy} onClick={close}>닫기</Button>
        </div>
        <p className="text-xs text-muted">가져온 메뉴는 <b>초안</b>으로만 저장돼요. 자동으로 게시하지 않아요. 저장한 뒤 위의 게시 도구로 검토하고 게시하세요. 기존 메뉴는 자동으로 삭제되지 않아요.</p>

        {step.s === 'pick' && (
          <div className="space-y-3">
            <div role="button" tabIndex={0} aria-label="CSV 파일 올리기 영역" onClick={() => fileInput.current?.click()} onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') fileInput.current?.click() }}
              onDragOver={(e) => { e.preventDefault(); setDrag(true) }} onDragLeave={() => setDrag(false)} onDrop={onDrop}
              className={`grid cursor-pointer place-items-center rounded-2xl border-2 border-dashed p-10 text-center text-sm ${drag ? 'border-brand-strong bg-brand/10' : 'border-line bg-page/40'}`}>
              <div><Upload className="mx-auto mb-2 size-6 text-muted" /><div className="font-medium">CSV 파일을 여기에 끌어다 놓거나 눌러서 고르세요</div><div className="mt-1 text-xs text-muted">UTF-8 (BOM 있어도 돼요) · 쉼표로 구분 · {MAX_FILE_BYTES / 1024 / 1024}MB 이하</div></div>
              <input ref={fileInput} type="file" accept=".csv,text/csv" hidden aria-label="CSV 파일 선택" onChange={(e) => { const f = e.target.files?.[0]; if (f) void readFile(f); e.target.value = '' }} />
            </div>
            <div className="flex flex-wrap items-center gap-3">
              <Button variant="outline" size="sm" onClick={() => downloadText('meogeobojo_menu_import_template.csv', templateCsv())}>CSV 양식 다운로드</Button>
              <span className="text-xs text-muted">열: {TEMPLATE_COLUMNS.join(', ')}. kakao_place_id와 restaurant_name은 비워도 돼요 (적었다면 이 식당과 같아야 해요). 가격은 8500 · 8,500 · 8,500원 모두 괜찮아요.</span>
            </div>
            {step.error && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{step.error}</p>}
          </div>)}

        {step.s === 'loading' && <p role="status" className="text-sm"><Loader2 className="mr-2 inline size-4 animate-spin" />{step.text}</p>}

        {step.s === 'blocked' && (
          <div className="space-y-3">
            <div role="alert" aria-label="다른 식당 파일" className="space-y-2 rounded-xl bg-red-50 p-3 text-sm text-red-900">
              <p><b>가져오기를 멈췄어요.</b> 이 파일은 <b>{restaurantName}</b>이(가) 아닌 다른 식당을 가리켜요. 아무것도 저장하지 않았어요.</p>
              <ul className="list-disc space-y-0.5 pl-5 text-xs">{step.check.blockers.slice(0, 10).map((b) => <li key={b.line}>{b.line}줄: {b.message}</li>)}</ul>
              {step.check.blockers.length > 10 && <p className="text-xs">…외 {step.check.blockers.length - 10}줄</p>}
            </div>
            <div className="flex justify-end gap-2"><Button variant="outline" onClick={close}>닫기</Button><Button onClick={reset}>다른 파일 고르기</Button></div>
          </div>)}

        {step.s === 'preview' && plan && parsed && ctx && (() => {
          const c = plan.counts
          const rowsAll = plan.rows
          const dupInFile = rowsAll.filter((r) => r.action === 'duplicate' && r.messages.some((m) => m.startsWith('파일 안에서'))).length
          const dupExisting = rowsAll.filter((r) => (r.action === 'duplicate' && !r.messages.some((m) => m.startsWith('파일 안에서'))) || r.action === 'update' || r.action === 'unchanged').length
          const skipped = c.duplicate + c.unchanged
          const bad = c.invalid + c.unmatched + c.nameMismatch
          const changes = c.add + c.update + c.remove
          const activeNow = ctx.state.items.filter((i) => i.status === 'active').length
          return (
            <div className="space-y-3">
              <div className="flex flex-wrap items-center gap-3 text-sm"><span>파일: <b data-testid="import-file">{fileName}</b></span><Button size="sm" variant="ghost" onClick={reset}>다른 파일 고르기</Button></div>
              <fieldset className="space-y-1 rounded-xl border border-line bg-white p-3 text-sm"><legend className="px-1 text-xs font-semibold text-muted">가져오기 방식</legend>
                {MODES.map((m) => (
                  <label key={m.id} className="flex items-start gap-2"><input type="radio" name="import-mode" checked={mode === m.id} onChange={() => setMode(m.id)} /><span><b>{m.label}</b>{m.id === 'append' && ' (기본)'} — {m.help}</span></label>))}
              </fieldset>

              <div role="status" aria-label="가져오기 미리보기 요약" className="space-y-1 rounded-xl border border-line bg-white p-3 text-sm">
                <div>전체 <b>{c.rows}줄</b> · 올바른 줄 <b>{c.rows - bad}</b> · 오류 <b>{bad}</b> · 중복 가능성 <b>{dupInFile + dupExisting}</b> (파일 안 {dupInFile} · 이 식당에 이미 있음 {dupExisting})</div>
                <div>가져오면: 추가 <b>{c.add}</b> · 갱신 <b>{c.update}</b> · 건너뜀 <b>{skipped}</b> · 초안에서 빠짐 <b>{c.remove}</b>{mode !== 'replace' && ' (이 방식은 빼지 않아요)'}</div>
                <div className="text-xs text-muted">이 식당의 현재 메뉴 {activeNow}개{ctx.state.hasDraft ? ' (저장된 초안 기준)' : ' (게시된 메뉴 기준)'}{rp ? ` → 가져온 뒤 ${rp.items.filter((i) => i.status === 'active').length}개` : ''}</div>
                {ctx.state.hasDraft && <div className="text-xs text-amber-900">이미 저장된 초안이 있어요. 그 초안 위에 합쳐져요.</div>}
                {ctx.notes.map((n) => <div key={n} className="text-xs text-muted">{n}</div>)}
                {parsed.ignoredColumns.length > 0 && <div className="text-xs text-muted">무시한 열: {parsed.ignoredColumns.join(', ')}</div>}
                {(parsed.blankRows ?? 0) > 0 && <div className="text-xs text-muted">식당만 적혀 있고 메뉴를 채우지 않은 줄 {parsed.blankRows}개는 건너뛰었어요.</div>}
              </div>

              {bad > 0 && <p role="alert" className="rounded-xl bg-red-50 p-3 text-sm text-red-900"><b>오류가 {bad}줄 있어서 가져올 수 없어요.</b> 아래 오류를 고친 뒤 파일을 다시 고르세요. 오류가 있는 채로 일부만 가져오지 않아요.</p>}

              <div className="max-h-80 overflow-auto rounded-xl border border-line bg-white">
                <table aria-label="미리보기" className="w-full text-xs">
                  <thead className="sticky top-0 border-b border-line bg-page text-left text-muted"><tr>{['줄', '결과', '메뉴', '가격', '분류', '판매', '내용'].map((h) => <th key={h} className="px-3 py-2 font-medium">{h}</th>)}</tr></thead>
                  <tbody>
                    {rowsAll.slice(0, MAX_SHOWN).map((r) => {
                      const a = ACTION_LABEL[r.action]
                      return (
                        <tr key={r.line} className="border-b border-line align-top last:border-0">
                          <td className="px-3 py-2 tabular-nums text-muted">{r.line}</td>
                          <td className="px-3 py-2"><Badge tone={a.tone}>{a.text}</Badge></td>
                          <td className="px-3 py-2 font-medium">{r.menuName || '—'}</td>
                          <td className="px-3 py-2 tabular-nums">{r.csv.price == null ? '미정' : won(r.csv.price)}</td>
                          <td className="px-3 py-2">{r.csv.category || '—'}</td>
                          <td className="px-3 py-2">{r.csv.available == null ? '—' : r.csv.available ? '판매 중' : '품절'}</td>
                          <td className="px-3 py-2">
                            {r.changes.length > 0 && <ul className="mb-1 space-y-0.5">{r.changes.map((x) => <li key={x.field}><span className="text-muted">{x.field}:</span> {x.from} → <b>{x.to}</b></li>)}</ul>}
                            {r.messages.map((m) => <div key={m} className={r.action === 'invalid' ? 'text-red-700' : 'text-muted'}>{m}</div>)}
                          </td>
                        </tr>)
                    })}
                    {rp?.removedItems.map((i) => (
                      <tr key={i.id} className="border-b border-line align-top last:border-0 bg-red-50/60">
                        <td className="px-3 py-2 text-muted">—</td><td className="px-3 py-2"><Badge tone="red">빠짐</Badge></td>
                        <td className="px-3 py-2 font-medium">{i.name_ko}</td><td className="px-3 py-2 tabular-nums">{i.price_krw == null ? '미정' : won(i.price_krw)}</td>
                        <td className="px-3 py-2">{i.category ?? '—'}</td><td className="px-3 py-2">{i.available ? '판매 중' : '품절'}</td>
                        <td className="px-3 py-2 text-muted">파일에 없어서 초안에서 빠져요 (게시하면 보관 처리돼요)</td>
                      </tr>))}
                  </tbody>
                </table>
              </div>
              {rowsAll.length > MAX_SHOWN && <p className="text-xs text-muted">처음 {MAX_SHOWN}줄만 보여줘요 (전체 {rowsAll.length}줄). 요약 숫자는 모든 줄 기준이에요.</p>}

              <div className="flex flex-wrap justify-end gap-2">
                <Button variant="outline" onClick={close}>취소</Button>
                <Button disabled={bad > 0 || changes === 0}
                  onClick={() => (mode === 'replace' ? setStep({ s: 'confirm-replace' }) : void save())}>
                  {bad > 0 ? '오류를 고쳐야 가져올 수 있어요' : changes === 0 ? '가져올 내용이 없어요' : mode === 'replace' ? '전체 교체 확인…' : `초안으로 가져오기 (추가 ${c.add} · 갱신 ${c.update})`}
                </Button>
              </div>
            </div>)
        })()}

        {step.s === 'confirm-replace' && plan && ctx && rp && (
          <div role="alertdialog" aria-label="전체 교체 확인" className="space-y-3 rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-950">
            <h3 className="font-bold">「{restaurantName}」의 메뉴를 전체 교체할까요?</h3>
            <p>현재 메뉴 <b>{ctx.state.items.filter((i) => i.status === 'active').length}개</b> 중 <b>{rp.removed}개</b>가 초안에서 빠지고, <b>{rp.updates}개</b>가 갱신되고, 새 메뉴 <b>{rp.adds}개</b>가 추가돼요. 영향받는 기존 메뉴는 모두 <b>{rp.removed + rp.updates}개</b>예요.</p>
            {rp.removed > 0 && <p className="text-xs">빠지는 메뉴: {rp.removedItems.slice(0, 12).map((i) => i.name_ko).join(', ')}{rp.removedItems.length > 12 ? ` 외 ${rp.removedItems.length - 12}개` : ''}</p>}
            <p className="text-xs">다른 식당은 바뀌지 않아요. 초안으로만 저장되고, 게시하기 전에는 앱·웹에 보이지 않아요. 게시된 메뉴는 삭제되지 않고 보관 처리돼요.</p>
            <div className="flex justify-end gap-2"><Button variant="outline" onClick={() => setStep({ s: 'preview' })}>돌아가기</Button><Button variant="danger" onClick={() => void save()}>{restaurantName} 메뉴 전체 교체</Button></div>
          </div>)}

        {step.s === 'saving' && <p role="status" className="text-sm"><Loader2 className="mr-2 inline size-4 animate-spin" />초안으로 저장하는 중…</p>}

        {step.s === 'done' && (() => {
          const r = step.result
          const saved = r?.saved[0]
          const failed = r?.failed[0]
          const c = plan?.counts
          const skipped = c ? c.duplicate + c.unchanged : 0
          return (
            <div className="space-y-3">
              <h3 className="font-bold">{step.error || failed ? '저장하지 못했어요' : saved ? '초안으로 저장했어요' : '바뀐 내용이 없어요'}</h3>
              <p role="status" aria-label="가져오기 결과" className="rounded-xl border border-line bg-white p-3 text-sm">
                식당 <b>{restaurantName}</b> · 추가 <b>{saved?.added ?? 0}개</b> · 갱신 <b>{saved?.updated ?? 0}개</b>{mode === 'replace' && <> · 초안에서 뺀 메뉴 <b>{saved?.removed ?? 0}개</b></>} · 건너뜀 <b>{skipped}개</b> · 실패 <b>{step.error || failed ? (c?.add ?? 0) + (c?.update ?? 0) + (c?.remove ?? 0) : (c?.invalid ?? 0)}개</b>
                {saved && <span className="mt-1 block text-xs text-muted">아직 게시하지 않았어요: 앱과 웹에는 보이지 않아요. 위의 게시 도구로 검토한 뒤 게시하세요.</span>}
                {!saved && !failed && !step.error && <span className="mt-1 block text-xs text-muted">파일의 내용이 이미 이 식당의 메뉴와 같아서 저장하지 않았어요.</span>}
              </p>
              {(step.error || failed) && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{step.error ?? failed?.message}{r?.stoppedBy === 'forbidden' && ' (관리자 권한이 필요해요)'}</p>}
              <div className="flex flex-wrap justify-end gap-2"><Button variant="outline" onClick={reset}>다른 파일 가져오기</Button><Button onClick={close}>닫기</Button></div>
            </div>)
        })()}
      </div>
    </dialog>
  )
}
