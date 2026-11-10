import { useMutation } from '@tanstack/react-query'
import { Download, FileUp } from 'lucide-react'
import { useMemo, useState } from 'react'
import { Badge, Button, Field, Modal, Select } from '@/components/ui'
import { isMissingFunction } from '@/lib/cmsHealth'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import { decodeProblem, normalizeRow, parseCsv, REQUIRED, templateBlob, toRpcRow, toTable, type ImportRow } from './csv'

type Mode = 'create_only' | 'update_only' | 'upsert'
type Entry = { line: number; status: 'create' | 'update' | 'unchanged' | 'skip' | 'error'; message?: string | null; university?: string; cafeteria?: string; date?: string; meal_type?: string; option?: string; new_cafeteria?: boolean }
type Result = {
  dry_run: boolean; mode: Mode; multi_university: boolean; universities: string[]; new_cafeterias: { university: string; name: string }[]
  summary: { created: number; updated: number; unchanged: number; skipped: number; failed: number; cafeterias_created: number; weeks_changed: number }; rows: Entry[]
}
const MODE_LABEL: Record<Mode, string> = { create_only: '새 식단만 만들기 (이미 있으면 건너뜀)', update_only: '이미 있는 식단만 수정 (없으면 건너뜀)', upsert: '만들고 수정하기 (있으면 수정, 없으면 생성)' }
const STATUS: Record<Entry['status'], { label: string; tone: 'green' | 'brand' | 'neutral' | 'amber' | 'red' }> = {
  create: { label: '새로 만듦', tone: 'green' }, update: { label: '수정', tone: 'brand' }, unchanged: { label: '변경 없음', tone: 'neutral' }, skip: { label: '건너뜀', tone: 'amber' }, error: { label: '오류', tone: 'red' },
}
const MEAL: Record<string, string> = { breakfast: '조식', lunch: '중식', dinner: '석식' }

const download = () => {
  const url = URL.createObjectURL(templateBlob())
  const a = document.createElement('a'); a.href = url; a.download = 'cafeteria_weekly_template.csv'; a.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

/** CSV bulk import. The browser parses and previews; the server (cafeteria_import) validates, resolves universities and
 *  cafeterias, detects duplicates and writes DRAFTS only. Nothing is published: an admin reviews each week, then publishes. */
export default function CsvImport({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const [fileName, setFileName] = useState('')
  const [rows, setRows] = useState<ImportRow[]>([])
  const [fatal, setFatal] = useState<string | null>(null)
  const [warn, setWarn] = useState<string | null>(null)
  const [mode, setMode] = useState<Mode>('create_only')
  const [createMissing, setCreateMissing] = useState(false)
  const [multiOk, setMultiOk] = useState(false)
  const [preview, setPreview] = useState<Result | null>(null)
  const [done, setDone] = useState<Result | null>(null)
  const [onlyErrors, setOnlyErrors] = useState(false)

  const clientOk = rows.filter((r) => r.errors.length === 0)
  const call = async (dry: boolean, opts = { mode, createMissing, multiOk }) => {
    const { data, error } = await supabase.rpc('cafeteria_import', { p_rows: clientOk.map(toRpcRow), p_mode: opts.mode, p_dry_run: dry, p_create_missing: opts.createMissing, p_allow_multi_university: opts.multiOk })
    if (error) throw error
    return data as Result
  }
  const previewMut = useMutation({
    mutationFn: (o: { mode: Mode; createMissing: boolean; multiOk: boolean }) => call(true, o),
    onSuccess: (r) => { setPreview(r); setFatal(null) },
    onError: (e) => setFatal(isMissingFunction(e) ? '가져오기 기능이 아직 데이터베이스에 없어요. 마이그레이션 20261118000100을 적용해 주세요.' : errorMessage(e)),
  })
  const applyMut = useMutation({
    mutationFn: () => call(false),
    onSuccess: (r) => { setDone(r); onDone() },
    onError: (e) => setFatal(errorMessage(e)),
  })

  const load = async (file: File) => {
    setFatal(null); setWarn(null); setPreview(null); setDone(null); setMultiOk(false)
    setFileName(file.name)
    const text = await file.text()
    const bad = decodeProblem(text)
    if (bad) { setRows([]); return setFatal(bad) }
    const table = toTable(parseCsv(text))
    if (table.missing.length) { setRows([]); return setFatal(`필수 열이 없어요: ${table.missing.join(', ')}. 예시 파일을 내려받아 열 이름을 확인해 주세요.`) }
    if (table.rows.length === 0) { setRows([]); return setFatal('데이터 행이 없어요.') }
    if (table.rows.length > 2000) { setRows([]); return setFatal('한 번에 2000행까지 가져올 수 있어요. 파일을 나눠 주세요.') }
    if (table.unknown.length) setWarn(`알 수 없는 열은 무시해요: ${table.unknown.join(', ')}`)
    const parsed = table.rows.map(normalizeRow)
    setRows(parsed)
    const ok = parsed.filter((r) => r.errors.length === 0)
    if (ok.length) {
      try { const { data, error } = await supabase.rpc('cafeteria_import', { p_rows: ok.map(toRpcRow), p_mode: mode, p_dry_run: true, p_create_missing: createMissing, p_allow_multi_university: false }); if (error) throw error; setPreview(data as Result) }
      catch (e) { setFatal(isMissingFunction(e) ? '가져오기 기능이 아직 데이터베이스에 없어요. 마이그레이션 20261118000100을 적용해 주세요.' : errorMessage(e)) }
    }
  }

  // one table: the browser's own findings and the server's per-row result
  const table = useMemo(() => {
    const server = new Map((preview?.rows ?? []).map((e) => [e.line, e]))
    return rows.map((r) => {
      if (r.errors.length) return { r, e: { line: r.line, status: 'error', message: r.errors.join(' · ') } as Entry }
      return { r, e: server.get(r.line) ?? ({ line: r.line, status: 'skip', message: '확인 중…' } as Entry) }
    })
  }, [rows, preview])
  const shown = (onlyErrors ? table.filter((t) => t.e.status === 'error') : table).slice(0, 300)
  const s = preview?.summary
  const clientErrors = rows.length - clientOk.length
  const failed = (s?.failed ?? 0) + clientErrors
  const toApply = (s?.created ?? 0) + (s?.updated ?? 0)
  const needsMulti = !!preview?.multi_university
  const needsCreate = (preview?.new_cafeterias.length ?? 0) > 0
  const canApply = !!preview && toApply > 0 && (!needsMulti || multiOk) && (!needsCreate || createMissing) && !applyMut.isPending

  return (
    <Modal open title="CSV 일괄 등록" onClose={onClose}>
      <div className="space-y-3" aria-label="CSV 가져오기">
        {done ? (
          <div className="space-y-3">
            <p role="status" className="rounded-xl bg-brand/30 p-3 text-sm"><b>초안으로 저장했어요.</b> 앱에는 아직 보이지 않아요. 각 식당의 주간 메뉴에서 미리보기로 확인한 뒤 게시해 주세요.</p>
            <ul aria-label="가져오기 결과" className="grid grid-cols-2 gap-2 text-sm sm:grid-cols-3">
              <li>새로 만듦 <b>{done.summary.created}</b></li><li>수정 <b>{done.summary.updated}</b></li><li>변경 없음 <b>{done.summary.unchanged}</b></li>
              <li>건너뜀 <b>{done.summary.skipped}</b></li><li>실패 <b>{done.summary.failed + clientErrors}</b></li><li>초안이 생긴 주 <b>{done.summary.weeks_changed}</b></li>
              {done.summary.cafeterias_created > 0 && <li className="col-span-2 sm:col-span-3">새 식당 <b>{done.summary.cafeterias_created}</b>곳을 비활성으로 만들었어요. 메뉴를 확인한 뒤 &lsquo;운영 중으로&rsquo;를 눌러 주세요.</li>}
            </ul>
            <div className="flex justify-end"><Button onClick={onClose}>닫기</Button></div>
          </div>
        ) : (
          <>
            <p className="text-xs text-muted">필수 열: {REQUIRED.join(', ')}. 선택 열: side_dishes·soup·rice·kimchi·salad·dessert·shared(한 칸에 여러 메뉴는 <code>/</code> 또는 <code>|</code>로 구분), origin, labels·labels_verified, meal_option, program, description, notes, location, source_url, university_id, cafeteria_id. 한 줄은 정확히 한 식당 · 한 날짜 · 한 식사 · 한 옵션이에요. 가져온 내용은 초안으로만 저장돼요.</p>
            <div className="flex flex-wrap items-center gap-2">
              <Button variant="outline" size="sm" onClick={download}><Download className="size-4" />예시 파일 내려받기</Button>
              <label className="inline-flex h-9 cursor-pointer items-center gap-2 rounded-xl bg-brand px-3 text-sm font-semibold text-brand-ink"><FileUp className="size-4" />CSV 파일 선택
                <input type="file" accept=".csv,text/csv" hidden aria-label="CSV 파일 선택" onChange={(e) => { const f = e.target.files?.[0]; if (f) void load(f); e.target.value = '' }} /></label>
              {fileName && <span className="text-xs text-muted">{fileName} · {rows.length}행</span>}
            </div>
            {fatal && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">{fatal}</p>}
            {warn && <p role="status" className="rounded-xl bg-page p-3 text-xs">{warn}</p>}
            {rows.length > 0 && (
              <>
                <div className="grid gap-3 sm:grid-cols-2">
                  <Field label="가져오기 방식" htmlFor="imp_mode"><Select id="imp_mode" value={mode} onChange={(e) => { const m = e.target.value as Mode; setMode(m); previewMut.mutate({ mode: m, createMissing, multiOk: false }) }}>
                    {(Object.keys(MODE_LABEL) as Mode[]).map((m) => <option key={m} value={m}>{MODE_LABEL[m]}</option>)}</Select></Field>
                  <label className="flex items-start gap-2 self-end text-sm"><input type="checkbox" checked={createMissing} onChange={(e) => { setCreateMissing(e.target.checked); previewMut.mutate({ mode, createMissing: e.target.checked, multiOk: false }) }} />
                    <span>없는 식당은 새로 만들기 <span className="text-xs text-muted">(비활성으로 만들어져요)</span></span></label>
                </div>
                {s && (
                  <ul aria-label="미리보기 요약" className="grid grid-cols-2 gap-2 rounded-xl bg-page p-3 text-sm sm:grid-cols-5">
                    <li>새로 만듦 <b>{s.created}</b></li><li>수정 <b>{s.updated}</b></li><li>변경 없음 <b>{s.unchanged}</b></li><li>건너뜀 <b>{s.skipped}</b></li><li>오류 <b className={failed ? 'text-red-600' : ''}>{failed}</b></li>
                  </ul>)}
                {needsCreate && <p role="status" className="rounded-xl bg-amber-50 p-3 text-xs text-amber-900">새로 만들 식당: {preview!.new_cafeterias.map((c) => `${c.university} · ${c.name}`).join(', ')}. {createMissing ? '비활성 상태로 만들어요.' : '"없는 식당은 새로 만들기"를 켜야 가져올 수 있어요.'}</p>}
                {needsMulti && (
                  <label className="flex items-start gap-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900"><input type="checkbox" aria-label="여러 대학교 변경 확인" checked={multiOk} onChange={(e) => setMultiOk(e.target.checked)} />
                    <span><b>여러 대학교의 식단을 한 번에 바꿔요:</b> {preview!.universities.join(', ')}. 확인했어요.</span></label>)}
                <label className="flex items-center gap-2 text-xs"><input type="checkbox" checked={onlyErrors} onChange={(e) => setOnlyErrors(e.target.checked)} />오류가 있는 행만 보기</label>
                <div className="max-h-72 overflow-auto rounded-xl border border-line" aria-label="가져오기 미리보기">
                  <table className="w-full text-left text-xs">
                    <thead className="sticky top-0 bg-page"><tr><th className="p-2">행</th><th>결과</th><th>대학교 · 식당</th><th>날짜</th><th>식사</th><th>메뉴</th><th>가격</th><th>메시지</th></tr></thead>
                    <tbody>{shown.map(({ r, e }) => (
                      <tr key={r.line} className="border-t border-line align-top">
                        <td className="p-2">{r.line}</td><td><Badge tone={STATUS[e.status].tone}>{STATUS[e.status].label}</Badge></td>
                        <td>{e.university ?? r.university} · {e.cafeteria ?? r.cafeteria_name}{e.new_cafeteria ? ' (새 식당)' : ''}</td><td>{r.date}</td>
                        <td>{MEAL[r.meal_type] ?? r.meal_type}{r.meal_option ? ` (${r.meal_option})` : ''}{r.program ? ` · ${r.program}` : ''}</td><td>{r.menu_name}{r.dishes.length > 0 && <span className="text-muted"> 외 {r.dishes.length}개 ({r.dishes.map((x) => x.name_ko).join(', ')})</span>}{r.labels.length > 0 && <Badge tone="brand">{r.labels.join(' · ')}</Badge>}</td>
                        <td>{r.price ? `${Number(r.price).toLocaleString('ko-KR')}원` : '미정'}</td><td className={e.status === 'error' ? 'text-red-700' : 'text-muted'}>{e.message ?? ''}</td>
                      </tr>))}</tbody>
                  </table>
                  {table.length > 300 && <p className="p-2 text-xs text-muted">처음 300행만 보여요 ({table.length}행 중).</p>}
                </div>
                <div className="flex items-center justify-between gap-2">
                  <span className="text-xs text-muted">{failed > 0 ? `오류가 있는 ${failed}행은 가져오지 않아요.` : '모든 행이 올바르게 보여요.'}</span>
                  <div className="flex gap-2"><Button variant="outline" onClick={onClose}>취소</Button>
                    <Button disabled={!canApply} onClick={() => applyMut.mutate()}>{applyMut.isPending ? '저장 중…' : failed > 0 ? `오류 없는 ${toApply}행만 초안으로 가져오기` : `${toApply}행을 초안으로 가져오기`}</Button></div>
                </div>
              </>)}
          </>)}
      </div>
    </Modal>
  )
}
