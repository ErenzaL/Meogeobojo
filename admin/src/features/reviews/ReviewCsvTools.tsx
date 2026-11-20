import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Download, FileDown, Upload } from 'lucide-react'
import { useRef, useState } from 'react'
import { Badge, Button, Card } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import { downloadText } from '../menus/MenuCsvTools'
import { chunk } from '../restaurants/kakao'
import { parseReviewCsv, reviewExportCsv, reviewTemplateCsv, reviewTotals, type ImportRow, type ReviewParse, type StoredReview } from './reviewCsv'

/** Where an imported review came from, in words an admin knows. 'app' is what students write in the app. */
export const SOURCE_LABEL: Record<string, string> = { app: '앱 (학생)', kakao: '카카오맵', naver: '네이버', lemong: '레몽' }
export const sourceLabel = (s: string) => SOURCE_LABEL[s] ?? s
const SOURCES = ['app', 'kakao', 'naver', 'lemong'] as const
const CHUNK = 500 // the server takes at most 1000 per call

type Check = { new: number; existing: number; failed: number; undated: number; errors: { line: number; error: string }[] }
const ZERO: Check = { new: 0, existing: 0, failed: 0, undated: 0, errors: [] }
type Rpc = { new: number; existing: number; failed: number; undated: number; errors: Check['errors'] }

/** Runs the server import over [rows] in chunks. [dryRun]: counts only, nothing is written. */
async function runImport(rows: ImportRow[], dryRun: boolean, onProgress: (done: number) => void): Promise<Check> {
  const sum = { ...ZERO, errors: [] as Check['errors'] }
  let done = 0
  for (const part of chunk(rows, CHUNK)) {
    const { data, error } = await supabase.rpc('admin_import_reviews', { p_rows: part, p_dry_run: dryRun })
    if (error) throw error
    const r = data as Rpc
    sum.new += r.new; sum.existing += r.existing; sum.failed += r.failed; sum.undated += r.undated
    sum.errors.push(...r.errors)
    done += part.length
    onProgress(done)
  }
  return sum
}

const REVIEW_QUERIES = ['reviews-list', 'review-source-counts', 'review-stats', 'review-picker']

/**
 * CSV 가져오기 / 내보내기 for `student_reviews`, the one table the app, the website and this page all read.
 * Without [placeId]: every restaurant. With it: only that restaurant (a file's lines of other restaurants are skipped).
 */
export default function ReviewCsvTools({ canImport, placeId }: { canImport: boolean; placeId?: string }) {
  const qc = useQueryClient()
  const fileRef = useRef<HTMLInputElement>(null)
  const [parsed, setParsed] = useState<ReviewParse | null>(null)
  const [fileName, setFileName] = useState('')
  const [check, setCheck] = useState<Check | null>(null)
  const [checking, setChecking] = useState(false)
  const [unknownPlaces, setUnknownPlaces] = useState<number | null>(null)
  const [progress, setProgress] = useState(0)
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null)

  const counts = useQuery({
    queryKey: ['review-source-counts', placeId ?? 'all'],
    queryFn: async () => {
      const out: Record<string, number> = {}
      for (const s of SOURCES) {
        let q = supabase.from('student_reviews').select('id', { count: 'exact', head: true }).eq('source', s)
        if (placeId) q = q.eq('kakao_place_id', placeId)
        const { count, error } = await q
        if (error) throw error
        out[s] = count ?? 0
      }
      return out
    },
    retry: false,
  })

  const totals = parsed && !parsed.fatal ? reviewTotals(parsed) : null
  const sendable = (parsed?.rows ?? []).flatMap((r) => (r.row && !r.duplicate ? [r.row] : []))

  const read = async (file: File) => {
    setNotice(null); setCheck(null); setUnknownPlaces(null); setFileName(file.name)
    const p = parseReviewCsv(await file.text(), new Date(), placeId)
    setParsed(p)
    if (p.fatal) return
    const rows = p.rows.flatMap((r) => (r.row && !r.duplicate ? [r.row] : []))
    if (rows.length === 0) return
    // the server's own verdict (new / already there / refused) before anything is written
    setChecking(true); setProgress(0)
    try {
      setCheck(await runImport(rows, true, setProgress))
    } catch (e) {
      setNotice({ ok: false, text: `서버에서 확인하지 못했어요: ${errorMessage(e)} (마이그레이션 20261128000100이 적용됐는지 확인해 주세요)` })
    } finally { setChecking(false) }
    // places without a restaurant record still keep their reviews; they show once that place is on the map
    try {
      const ids = [...new Set(rows.map((r) => r.kakao_place_id))]
      const known = new Set<string>()
      for (const part of chunk(ids, 200)) {
        const { data, error } = await supabase.from('restaurant_overrides').select('kakao_place_id').in('kakao_place_id', part)
        if (error) throw error
        for (const r of data as { kakao_place_id: string | null }[]) if (r.kakao_place_id) known.add(r.kakao_place_id)
      }
      setUnknownPlaces(ids.filter((i) => !known.has(i)).length)
    } catch { setUnknownPlaces(null) }
  }

  const refresh = async () => { for (const k of REVIEW_QUERIES) await qc.invalidateQueries({ queryKey: [k] }) }

  const run = useMutation({
    mutationFn: () => { setProgress(0); return runImport(sendable, false, setProgress) },
    onSuccess: async (r) => {
      setNotice({ ok: r.failed === 0, text: `리뷰 ${r.new.toLocaleString()}개를 저장했어요${r.existing ? ` (이미 있던 ${r.existing.toLocaleString()}개는 그대로 뒀어요)` : ''}${r.failed ? ` · 서버가 거절한 ${r.failed}개` : ''}. 앱과 웹에는 바로 보여요.` })
      setParsed(null); setCheck(null)
      await refresh()
    },
    onError: async (e) => { setNotice({ ok: false, text: `${errorMessage(e)} — 일부는 이미 저장됐을 수 있어요. 같은 파일을 다시 가져와도 중복되지 않아요.` }); await refresh() },
  })

  const exportAll = useMutation({
    mutationFn: async () => {
      const out: StoredReview[] = []
      for (let from = 0; from < 100_000; from += 1000) {
        let q = supabase.from('student_reviews')
          .select('kakao_place_id,source,platform,rating,source_rating,body,created_at,source_review_id,moderation_status')
        if (placeId) q = q.eq('kakao_place_id', placeId)
        const { data, error } = await q.order('created_at', { ascending: false }).order('id').range(from, from + 999)
        if (error) throw error
        out.push(...(data as StoredReview[]))
        if ((data?.length ?? 0) < 1000) break
      }
      downloadText(`reviews-${placeId ? `${placeId}-` : ''}${new Date().toISOString().slice(0, 10)}.csv`, reviewExportCsv(out))
      return out.length
    },
    onSuccess: (n) => setNotice({ ok: true, text: `리뷰 ${n.toLocaleString()}개를 CSV로 내려받았어요. 학생 리뷰의 작성자는 담기지 않아요.` }),
    onError: (e) => setNotice({ ok: false, text: errorMessage(e) }),
  })

  const preview = (parsed?.rows ?? []).filter((r) => r.row).slice(0, 8)
  const invalid = (parsed?.rows ?? []).filter((r) => r.errors.length > 0)
  const busy = checking || run.isPending

  return (
    <Card aria-label="리뷰 CSV" className="mb-6 space-y-3 text-sm">
      <div className="flex flex-wrap items-center gap-2">
        <h2 className="font-bold">{placeId ? '이 식당의 리뷰 CSV' : '리뷰 CSV 가져오기 · 내보내기'}</h2>
        {counts.data && Object.entries(counts.data).map(([s, n]) => <Badge key={s} tone={s === 'app' ? 'brand' : 'neutral'}>{sourceLabel(s)} {n.toLocaleString()}</Badge>)}
      </div>
      <p className="text-muted">{placeId && <><b>이 식당({placeId})의 리뷰만</b> 가져오고 내려받아요. 다른 식당의 줄이 섞인 파일을 골라도 이 식당의 줄만 가져와요. 장소 ID 열이 비어 있거나 없어도 돼요. </>}가져온 리뷰는 학생이 앱에서 쓴 리뷰와 <b>같은 표</b>에 저장돼요. 그래서 앱·웹·관리자 화면이 항상 같은 리뷰를 보여줘요. 이미 있는 리뷰는 다시 가져와도 바뀌거나 중복되지 않고, 숨긴 리뷰는 숨김 그대로예요. 별점이 없는 리뷰(글만 있는 네이버 리뷰)도 가져와요.</p>
      <div className="flex flex-wrap gap-2">
        {canImport && <Button disabled={busy} onClick={() => fileRef.current?.click()}><Upload className="size-4" />CSV 가져오기</Button>}
        <Button variant="outline" onClick={() => downloadText(placeId ? `reviews_template_${placeId}.csv` : 'reviews_template.csv', reviewTemplateCsv())}><FileDown className="size-4" />CSV 양식</Button>
        <Button variant="outline" disabled={exportAll.isPending} onClick={() => exportAll.mutate()}><Download className="size-4" />CSV 내보내기</Button>
        <input ref={fileRef} type="file" accept=".csv,text/csv" hidden data-testid="review-csv-input" onChange={(e) => { const f = e.target.files?.[0]; if (f) void read(f); e.target.value = '' }} />
      </div>

      {parsed?.fatal && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-amber-900">{parsed.fatal}</p>}
      {parsed && totals && (
        <div className="space-y-2" role="status" aria-label="리뷰 가져오기 미리보기">
          <div>파일 <b>{fileName}</b> · 전체 <b>{totals.lines.toLocaleString()}줄</b> · 가져올 수 있는 리뷰 <b>{totals.importable.toLocaleString()}</b> ({totals.places}곳)
            {totals.duplicate > 0 && <> · 파일 안 중복 {totals.duplicate.toLocaleString()}</>}
            {totals.empty > 0 && <> · 별점도 글도 없어 건너뜀 {totals.empty}</>}
            {totals.otherPlace > 0 && <> · 다른 식당의 줄 {totals.otherPlace.toLocaleString()} (건너뜀)</>}
            {totals.restaurantOnly > 0 && <> · 식당 정보만 있는 줄 {totals.restaurantOnly}</>}
            {totals.app > 0 && <> · 앱에서 쓴 리뷰 {totals.app}</>}
            {totals.invalid > 0 && <> · 오류 <b>{totals.invalid}</b></>}</div>
          {checking && <div>서버에서 확인하는 중… {progress.toLocaleString()} / {sendable.length.toLocaleString()}</div>}
          {check && !checking && <div className="rounded-xl bg-brand/20 p-3">서버 확인: 새로 저장 <b>{check.new.toLocaleString()}</b> · 이미 있음 {check.existing.toLocaleString()}{check.failed > 0 && <> · 서버가 거절 <b>{check.failed}</b></>}</div>}
          {totals.inferredYear > 0 && <div className="text-xs text-muted">연도 없는 날짜(예: 10.29.목) {totals.inferredYear.toLocaleString()}개는 요일이 맞는 가장 최근 연도로 정했어요.</div>}
          {totals.undated > 0 && <div className="text-xs text-muted">날짜가 없는 {totals.undated.toLocaleString()}개는 가져온 시각으로 저장돼요.</div>}
          {unknownPlaces != null && unknownPlaces > 0 && <div className="text-xs text-amber-900">식당 정보에 없는 장소 {unknownPlaces}곳이 있어요. 리뷰는 저장되고, 그 식당이 지도·목록에 나올 때 함께 보여요.</div>}
          {parsed.unknown.length > 0 && <div className="text-xs text-muted">읽지 않은 열: {parsed.unknown.join(', ')}</div>}
          {preview.length > 0 && (
            <div className="overflow-auto rounded-xl border border-line">
              <table className="w-full min-w-[40rem] text-left text-xs">
                <thead className="bg-page text-muted"><tr>{['줄', '장소 ID', '출처', '별점', '리뷰', '날짜'].map((h) => <th key={h} className="px-2 py-1.5 font-medium">{h}</th>)}</tr></thead>
                <tbody>{preview.map((r) => (
                  <tr key={r.line} className="border-t border-line align-top">
                    <td className="px-2 py-1">{r.line}</td><td className="px-2 py-1">{r.row!.kakao_place_id}</td>
                    <td className="px-2 py-1">{sourceLabel(r.row!.source)}{r.row!.platform && ` · ${r.row!.platform}`}</td>
                    <td className="px-2 py-1">{r.row!.rating || '–'}</td>
                    <td className="max-w-[18rem] truncate px-2 py-1" title={r.row!.body}>{r.row!.body || '(글 없음)'}</td>
                    <td className="px-2 py-1">{r.row!.reviewed_at ? r.row!.reviewed_at.slice(0, 16).replace('T', ' ') : '–'}{r.inferredYear && ' (연도 추정)'}</td>
                  </tr>))}</tbody>
              </table>
            </div>)}
          {invalid.length > 0 && <ul className="max-h-32 overflow-auto text-xs text-red-700">{invalid.slice(0, 20).map((r) => <li key={r.line}>{r.line}줄: {r.errors.join(' / ')}</li>)}</ul>}
          {check && check.errors.length > 0 && <ul className="max-h-32 overflow-auto text-xs text-red-700">{check.errors.slice(0, 20).map((e) => <li key={e.line}>{e.line}줄 (서버): {e.error}</li>)}</ul>}
          <div className="flex flex-wrap items-center gap-2">
            <Button disabled={busy || !check || check.new === 0} onClick={() => run.mutate()}>
              {run.isPending ? `저장하는 중… ${progress.toLocaleString()} / ${sendable.length.toLocaleString()}` : !check ? '서버 확인 중' : check.new === 0 ? '새로 저장할 리뷰가 없어요' : `리뷰 ${check.new.toLocaleString()}개 저장`}
            </Button>
            <Button variant="outline" disabled={run.isPending} onClick={() => { setParsed(null); setCheck(null) }}>취소</Button>
          </div>
        </div>)}
      {notice && <p role={notice.ok ? 'status' : 'alert'} className={`rounded-xl p-3 ${notice.ok ? 'bg-brand/30' : 'bg-amber-50 text-amber-900'}`}>{notice.text}</p>}

    </Card>
  )
}
