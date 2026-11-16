import { Loader2, Upload } from 'lucide-react'
import { useEffect, useMemo, useRef, useState, type DragEvent } from 'react'
import { Badge, Button } from '@/components/ui'
import { errorMessage } from '@/lib/utils'
import { downloadText } from '../menus/MenuCsvTools'
import { restaurantTemplateCsv } from './csv'
import { applyImportPlan, buildImportPlan, MODE_LABEL, parseImport, reportColumns, type ApplyResult, type ColumnReport, type Existing, type ImportMode, type ImportPlan, type PlanRow, type RowKind } from './restaurantImport'
import { fetchExistingForPreview, importDeps, ownSupabaseHost } from './restaurantImportData'
import type { ParsedRow } from './csv'

/** The 식당 page's CSV 가져오기: pick a file, choose a mode, review exactly what would change, then 변경사항 적용하기. */
const MAX_BYTES = 5 * 1024 * 1024
const MAX_SHOWN = 250
const KIND: Record<RowKind, { text: string; tone: 'green' | 'brand' | 'neutral' | 'amber' | 'red' }> = {
  create: { text: '신규', tone: 'green' }, update: { text: '업데이트', tone: 'brand' }, unchanged: { text: '변경 없음', tone: 'neutral' },
  skipped_existing: { text: '건너뜀 (이미 있음)', tone: 'neutral' }, invalid: { text: '오류', tone: 'red' }, review: { text: '검토 필요', tone: 'amber' }, duplicate: { text: '파일 안 중복', tone: 'amber' },
}
const MODES: { id: ImportMode; help: string }[] = [
  { id: 'fill', help: '비어 있는 정보만 채워요. 이미 있는 값은 그대로 두고, CSV의 빈 칸으로 지우지 않아요. (기본, 가장 안전해요)' },
  { id: 'update', help: 'CSV에 적힌 값(빈 칸 제외)으로 기존 정보를 바꿔요. 바뀌는 내용을 미리 보고 확인한 뒤에만 적용돼요.' },
  { id: 'new_only', help: '아직 없는 식당만 추가하고, 이미 있는 식당은 오류 없이 건너뛰어요.' },
]
type Step = { s: 'pick'; error?: string } | { s: 'loading'; text: string } | { s: 'preview' } | { s: 'saving'; done: number; total: number } | { s: 'done'; result: ApplyResult | null; error?: string }

export default function RestaurantCsvImport({ onClose }: { onClose: (changed: boolean) => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => { const d = ref.current; if (d && !d.open) d.showModal?.() }, [])
  const [step, setStep] = useState<Step>({ s: 'pick' })
  const [fileName, setFileName] = useState('')
  const [parsed, setParsed] = useState<ParsedRow[] | null>(null)
  const [columns, setColumns] = useState<ColumnReport | null>(null)
  const [existing, setExisting] = useState<Map<string, Existing> | null>(null)
  const [mode, setMode] = useState<ImportMode>('fill')
  const [confirmed, setConfirmed] = useState(false)
  const [onlyChanges, setOnlyChanges] = useState(true)
  const [drag, setDrag] = useState(false)
  const changed = useRef(false)
  const submitting = useRef(false)
  const fileInput = useRef<HTMLInputElement>(null)
  const ownHost = useMemo(() => ownSupabaseHost(), [])

  const opts = useMemo(() => ({ mode, ownHost }), [mode, ownHost])
  const plan: ImportPlan | null = useMemo(() => (parsed && existing ? buildImportPlan(parsed, existing, opts) : null), [parsed, existing, opts])

  const readFile = async (file: File) => {
    if (file.size > MAX_BYTES) return setStep({ s: 'pick', error: `파일이 너무 커요 (${Math.round(file.size / 1024 / 1024)}MB). ${MAX_BYTES / 1024 / 1024}MB 이하로 나눠 주세요.` })
    setFileName(file.name); setParsed(null); setExisting(null); setConfirmed(false)
    setStep({ s: 'loading', text: '파일을 읽는 중…' })
    try {
      const text = await file.text()
      if (text.includes('�')) return setStep({ s: 'pick', error: '글자가 깨져 읽혔어요. 파일이 UTF-8이 아닌 것 같아요. 엑셀에서 “CSV UTF-8(쉼표로 분리)”로 다시 저장해 주세요.' })
      const cols = reportColumns(text)
      if (!cols.used.includes('name_ko') || !cols.used.includes('kakao_place_id')) return setStep({ s: 'pick', error: '머리글(첫 줄)에 kakao_place_id와 name_ko 열이 있어야 해요. “CSV 양식”의 열 이름을 그대로 써 주세요.' })
      const rows = parseImport(text)
      if (rows.length === 0) return setStep({ s: 'pick', error: '가져올 줄이 없어요. 양식을 내려받아 작성해 주세요.' })
      if (rows.length > 5000) return setStep({ s: 'pick', error: `한 번에 5,000줄까지 가져올 수 있어요 (지금 ${rows.length.toLocaleString('ko-KR')}줄).` })
      setStep({ s: 'loading', text: '이미 등록된 식당을 확인하는 중…' })
      const ids = rows.map((r) => r.values?.kakao_place_id.trim() ?? '').filter(Boolean)
      const found = await fetchExistingForPreview(ids)
      setColumns(cols); setParsed(rows); setExisting(found)
      setStep({ s: 'preview' })
    } catch (e) { setStep({ s: 'pick', error: errorMessage(e) }) }
  }
  const onDrop = (e: DragEvent) => { e.preventDefault(); setDrag(false); const f = e.dataTransfer.files?.[0]; if (f) void readFile(f) }

  const apply = async () => {
    if (!plan || submitting.current) return
    submitting.current = true
    setStep({ s: 'saving', done: 0, total: plan.counts.created + plan.counts.withUpdates })
    try {
      const result = await applyImportPlan(plan, opts, importDeps, { onProgress: (done, total) => setStep({ s: 'saving', done, total }) })
      if (result.counts.created + result.counts.updated > 0) changed.current = true
      setStep({ s: 'done', result })
    } catch (e) { setStep({ s: 'done', result: null, error: errorMessage(e) }) }
    finally { submitting.current = false }
  }

  const busy = step.s === 'loading' || step.s === 'saving'
  const close = () => onClose(changed.current)
  const reset = () => { setParsed(null); setExisting(null); setColumns(null); setFileName(''); setConfirmed(false); setStep({ s: 'pick' }) }

  return (
    <dialog ref={ref} aria-label="식당 CSV 가져오기" onCancel={(e) => { if (busy) e.preventDefault(); else close() }} className="m-auto w-[min(62rem,96vw)] rounded-2xl border border-line p-6 backdrop:bg-black/40">
      <div className="space-y-4">
        <div className="flex items-start justify-between gap-3">
          <h2 className="text-lg font-bold">식당 CSV 가져오기</h2>
          <Button size="sm" variant="ghost" disabled={busy} onClick={close}>닫기</Button>
        </div>
        <p className="text-xs text-muted">이미 있는 식당은 <b>오류가 아니라 업데이트 대상</b>이에요 (카카오 장소 ID로 찾아요). 식당 ID와 공개 상태는 바뀌지 않아요. 수정은 <b>초안</b>으로 저장되고 새 식당도 초안으로 추가돼요. 게시는 하지 않아요.</p>

        {step.s === 'pick' && (
          <div className="space-y-3">
            <div role="button" tabIndex={0} aria-label="CSV 파일 올리기 영역" onClick={() => fileInput.current?.click()} onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') fileInput.current?.click() }}
              onDragOver={(e) => { e.preventDefault(); setDrag(true) }} onDragLeave={() => setDrag(false)} onDrop={onDrop}
              className={`grid cursor-pointer place-items-center rounded-2xl border-2 border-dashed p-10 text-center text-sm ${drag ? 'border-brand-strong bg-brand/10' : 'border-line bg-page/40'}`}>
              <div><Upload className="mx-auto mb-2 size-6 text-muted" /><div className="font-medium">CSV 파일을 여기에 끌어다 놓거나 눌러서 고르세요</div><div className="mt-1 text-xs text-muted">UTF-8 (BOM 있어도 돼요) · {MAX_BYTES / 1024 / 1024}MB 이하</div></div>
              <input ref={fileInput} type="file" accept=".csv,text/csv" hidden aria-label="CSV 파일 선택" data-testid="csv-input" onChange={(e) => { const f = e.target.files?.[0]; if (f) void readFile(f); e.target.value = '' }} />
            </div>
            <Button size="sm" variant="outline" onClick={() => downloadText('restaurants_template.csv', restaurantTemplateCsv())}>CSV 양식 다운로드</Button>
            {step.error && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{step.error}</p>}
          </div>)}

        {step.s === 'loading' && <p role="status" className="text-sm"><Loader2 className="mr-2 inline size-4 animate-spin" />{step.text}</p>}

        {step.s === 'preview' && plan && columns && (() => {
          const c = plan.counts
          const writes = c.created + c.withUpdates
          const shown = plan.rows.filter((r) => !onlyChanges || !['unchanged', 'skipped_existing'].includes(r.kind))
          const needsConfirm = mode === 'update' && c.withUpdates > 0
          return (
            <div className="space-y-3">
              <div className="flex flex-wrap items-center gap-3 text-sm"><span>파일: <b data-testid="import-file">{fileName}</b></span><Button size="sm" variant="ghost" onClick={reset}>다른 파일 고르기</Button></div>
              <fieldset className="space-y-1 rounded-xl border border-line bg-white p-3 text-sm"><legend className="px-1 text-xs font-semibold text-muted">가져오기 방식</legend>
                {MODES.map((m) => (
                  <label key={m.id} className="flex items-start gap-2"><input type="radio" name="import-mode" checked={mode === m.id} onChange={() => { setMode(m.id); setConfirmed(false) }} /><span><b>{MODE_LABEL[m.id]}</b>{m.id === 'fill' && ' (기본)'} — {m.help}</span></label>))}
              </fieldset>

              <div role="status" aria-label="가져오기 미리보기 요약" className="space-y-1 rounded-xl border border-line bg-white p-3 text-sm">
                <div>전체 <b>{c.rows}줄</b> · 이미 있는 식당 <b>{c.matched}곳</b> · 신규 식당 <b>{c.created}곳</b></div>
                <div>정보를 채우거나 바꿀 식당 <b>{c.withUpdates}곳</b> · 변경 없음 <b>{c.unchanged}곳</b>{mode === 'new_only' && <> · 건너뜀(이미 있음) <b>{c.skippedExisting}곳</b></>}</div>
                <div>오류 <b>{c.invalid}줄</b> · 검토 필요(장소 ID 없음·형식 오류) <b>{c.review}줄</b> · 파일 안 중복 <b>{c.duplicate}줄</b> · 이름 충돌 가능성 <b>{c.conflicts}줄</b></div>
              </div>

              <div aria-label="열 확인" className="space-y-1 rounded-xl border border-line bg-white p-3 text-xs">
                <div><b>읽는 열</b>: {columns.used.join(', ') || '없음'}</div>
                {columns.notApplied.map((x) => <div key={x.column} className="text-muted"><b>{x.column}</b>: {x.reason}</div>)}
                {columns.legacy.length > 0 && <div className="text-amber-900"><b>읽지 않은 열</b> ({columns.legacy.length}개)
                  <ul className="ml-4 list-disc">{columns.legacy.map((x) => <li key={x.column}><b>{x.column}</b>: {x.reason}</li>)}</ul></div>}
                {columns.unknown.length > 0 && <div className="text-amber-900"><b>알 수 없는 열</b> (무시했어요): {columns.unknown.join(', ')}</div>}
              </div>

              <label className="flex items-center gap-2 text-xs text-muted"><input type="checkbox" checked={onlyChanges} onChange={(e) => setOnlyChanges(e.target.checked)} />변경되거나 문제 있는 줄만 보기</label>
              <div className="max-h-96 overflow-auto rounded-xl border border-line bg-white">
                <table aria-label="미리보기" className="w-full text-xs">
                  <thead className="sticky top-0 border-b border-line bg-page text-left text-muted"><tr>{['줄', '결과', '식당', '바뀌는 내용', '사진', '메모'].map((h) => <th key={h} className="px-3 py-2 font-medium">{h}</th>)}</tr></thead>
                  <tbody>{shown.slice(0, MAX_SHOWN).map((r) => <Row key={`${r.line}`} r={r} />)}</tbody>
                </table>
              </div>
              {shown.length > MAX_SHOWN && <p className="text-xs text-muted">처음 {MAX_SHOWN}줄만 보여줘요 (전체 {shown.length}줄). 요약 숫자는 모든 줄 기준이에요.</p>}

              {needsConfirm && <label className="flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900"><input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} /><span>위의 바뀌는 내용으로 기존 식당 {c.withUpdates}곳의 정보를 바꾸는 초안을 만드는 것을 확인했어요</span></label>}
              <div className="flex flex-wrap justify-end gap-2">
                <Button variant="outline" onClick={close}>취소</Button>
                <Button disabled={writes === 0 || (needsConfirm && !confirmed)} onClick={() => void apply()}>{writes === 0 ? '적용할 변경이 없어요' : '변경사항 적용하기'}</Button>
              </div>
            </div>)
        })()}

        {step.s === 'saving' && (
          <div className="space-y-2">
            <div role="progressbar" aria-label="진행률" aria-valuemin={0} aria-valuemax={step.total} aria-valuenow={step.done} className="h-2 overflow-hidden rounded-full bg-page"><div className="h-full bg-brand-strong transition-all" style={{ width: `${step.total ? Math.round((step.done / step.total) * 100) : 0}%` }} /></div>
            <p role="status" className="text-sm">초안으로 저장하는 중… {step.done}/{step.total}</p>
          </div>)}

        {step.s === 'done' && (() => {
          const r = step.result
          const problems = r?.outcomes.filter((o) => o.result === 'failed' || o.result === 'skipped') ?? []
          return (
            <div className="space-y-3">
              <h3 className="font-bold">{step.error ? '저장하지 못했어요' : r?.stoppedBy ? '중간에 멈췄어요' : '가져오기를 마쳤어요'}</h3>
              {r && <p role="status" aria-label="가져오기 결과" className="rounded-xl border border-line bg-white p-3 text-sm">
                신규 <b>{r.counts.created}</b> · 업데이트 <b>{r.counts.updated}</b> · 변경 없음 <b>{r.counts.unchanged}</b> · 건너뜀 <b>{r.counts.skipped}</b> · 실패 <b>{r.counts.failed}</b>
                <span className="mt-1 block text-xs text-muted">모두 초안으로 저장했어요. 아직 게시하지 않았어요. 설정의 초안 목록이나 각 식당에서 검토하고 게시하세요.</span></p>}
              {(step.error || r?.stoppedBy === 'forbidden') && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{step.error ?? '관리자 권한이 확인되지 않아 멈췄어요. 이미 저장된 식당은 그대로예요.'}</p>}
              {problems.length > 0 && (
                <ul aria-label="건너뛰거나 실패한 줄" className="max-h-48 divide-y divide-line overflow-auto rounded-xl border border-line bg-white text-xs">
                  {problems.map((o) => <li key={o.line} className="px-3 py-2"><b>{o.line}줄 {o.name}</b> <Badge tone={o.result === 'failed' ? 'red' : 'amber'}>{o.result === 'failed' ? '실패' : '건너뜀'}</Badge><div className="text-muted">{o.message}</div></li>)}
                </ul>)}
              <div className="flex flex-wrap justify-end gap-2"><Button variant="outline" onClick={reset}>다른 파일 가져오기</Button><Button onClick={close}>닫기</Button></div>
            </div>)
        })()}
      </div>
    </dialog>
  )
}

function imageText(r: PlanRow): string {
  const i = r.image
  switch (i.action) {
    case 'add': return '대표 사진 추가'
    case 'replace': return '대표 사진 교체 (이전 사진은 보관)'
    case 'same': return '이미 같은 사진이 있어요'
    case 'keep': return '기존 대표 사진 유지'
    case 'skip': return `가져오지 않음: ${i.reason}`
    default: return '—'
  }
}

function Row({ r }: { r: PlanRow }) {
  const k = KIND[r.kind]
  return (
    <tr className="border-b border-line align-top last:border-0">
      <td className="px-3 py-2 tabular-nums text-muted">{r.line}</td>
      <td className="px-3 py-2"><Badge tone={k.tone}>{k.text}</Badge></td>
      <td className="px-3 py-2"><div className="font-medium">{r.name || '—'}</div><div className="text-muted">{r.kakaoPlaceId ? `ID ${r.kakaoPlaceId}` : ''}{r.visibility ? ` · ${r.visibility === 'published' ? '공개 중' : r.visibility === 'draft' ? '초안' : r.visibility}` : ''}</div></td>
      <td className="px-3 py-2">{r.changes.length > 0 ? <ul className="space-y-0.5">{r.changes.map((c) => <li key={c.field}><span className="text-muted">{c.label}:</span> {c.from} → <b>{c.to}</b></li>)}</ul> : '—'}</td>
      <td className="px-3 py-2">{imageText(r)}</td>
      <td className="px-3 py-2">{[...r.errors, ...r.notes].map((m) => <div key={m} className={r.kind === 'invalid' ? 'text-red-700' : 'text-muted'}>{m}</div>)}</td>
    </tr>
  )
}
