import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useEffect, useRef, useState } from 'react'
import { Badge, Button, Card } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import { chunk } from '../restaurants/kakao'
import { downloadText } from '../menus/MenuCsvTools'
import { demoExportCsv, demoTemplateCsv, parseDemoCsv, type DemoParse, type ImportKind, type StoredDemoRow } from './demoImport'

const TABLE = 'recommendation_demo_features'

/** 추천 page: development-only import of the simulated recommendation features. Writes to ONE table, nothing else. */
export default function DemoFeaturesImport({ registerPicker }: { registerPicker?: (open: () => void) => void } = {}) {
  const qc = useQueryClient()
  const fileRef = useRef<HTMLInputElement>(null)
  const [parsed, setParsed] = useState<DemoParse | null>(null)
  const [fileName, setFileName] = useState('')
  const [kind, setKind] = useState<ImportKind>('file')
  const [text, setText] = useState('')
  const [known, setKnown] = useState<Set<string>>(new Set())
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null)
  // handed to the page header's button; the ref is only read when that button is clicked, never during render
  useEffect(() => {
    registerPicker?.(() => fileRef.current?.click())
  }, [registerPicker])

  const count = useQuery({
    queryKey: ['demo-features-count'],
    queryFn: async () => {
      const { count: n, error } = await supabase.from(TABLE).select('kakao_place_id', { count: 'exact', head: true })
      if (error) throw error
      return n ?? 0
    },
    retry: false,
  })

  const read = async (file: File) => {
    setNotice(null); setFileName(file.name)
    const t = await file.text()
    setText(t)
    await analyse(t, kind)
  }
  // choosing "real" / "demo" after the file is picked re-reads the same file, so the preview never shows a stale choice
  const analyse = async (t: string, k: ImportKind) => {
    const p = parseDemoCsv(t, k)
    setParsed(p)
    if (p.fatal) return
    try {
      const ids = p.rows.flatMap((r) => (r.row ? [r.row.kakao_place_id] : []))
      const found = new Set<string>()
      for (const part of chunk([...new Set(ids)], 200)) {
        const { data, error } = await supabase.from('restaurant_overrides').select('kakao_place_id').in('kakao_place_id', part)
        if (error) throw error
        for (const r of data as { kakao_place_id: string | null }[]) if (r.kakao_place_id) found.add(r.kakao_place_id)
      }
      setKnown(found)
    } catch { setKnown(new Set()) }
  }
  const pickKind = (k: ImportKind) => { setKind(k); if (text) void analyse(text, k) }

  const valid = (parsed?.rows ?? []).filter((r) => r.row && !r.duplicate)
  const invalid = (parsed?.rows ?? []).filter((r) => !r.row)
  const dup = (parsed?.rows ?? []).filter((r) => r.row && r.duplicate)
  const unknownIds = valid.filter((r) => !known.has(r.row!.kakao_place_id))
  const realCount = valid.filter((r) => !r.row!.demo_data).length
  const demoCount = valid.length - realCount

  const run = useMutation({
    mutationFn: async () => {
      let n = 0
      for (const part of chunk(valid.map((r) => r.row!), 200)) {
        const { error } = await supabase.from(TABLE).upsert(part, { onConflict: 'kakao_place_id' })
        if (error) throw error
        n += part.length
      }
      return n
    },
    onSuccess: async (n) => { setNotice({ ok: true, text: `${n}곳을 저장했어요 (실제 ${realCount}곳 · 데모 ${demoCount}곳). 식당·메뉴·사진·공개 상태는 바뀌지 않았어요.` }); setParsed(null); setText(''); await qc.invalidateQueries({ queryKey: ['demo-features-count'] }) },
    onError: (e) => setNotice({ ok: false, text: errorMessage(e) }),
  })
  const exportAll = useMutation({
    mutationFn: async () => {
      const out: StoredDemoRow[] = []
      for (let from = 0; from < 20000; from += 1000) {
        const { data, error } = await supabase.from(TABLE).select('kakao_place_id,name_ko,category_demo,open_time,last_order_time,break_time,no_break_time,parking,local_currency,fast_turnover,takeout,open_late,source,demo_data').order('kakao_place_id').range(from, from + 999)
        if (error) throw error
        out.push(...(data as StoredDemoRow[]))
        if ((data?.length ?? 0) < 1000) break
      }
      downloadText(`recommendation-features-${new Date().toISOString().slice(0, 10)}.csv`, demoExportCsv(out))
      return out.length
    },
    onSuccess: (n) => setNotice({ ok: true, text: `저장된 ${n}곳을 CSV로 내려받았어요. 고친 뒤 다시 가져올 수 있어요.` }),
    onError: (e) => setNotice({ ok: false, text: errorMessage(e) }),
  })
  const clear = useMutation({
    mutationFn: async () => { const { error } = await supabase.from(TABLE).delete().neq('kakao_place_id', ''); if (error) throw error },
    onSuccess: async () => { setNotice({ ok: true, text: '데모 데이터를 모두 지웠어요.' }); await qc.invalidateQueries({ queryKey: ['demo-features-count'] }) },
    onError: (e) => setNotice({ ok: false, text: errorMessage(e) }),
  })

  return (
    <Card aria-label="추천 데모 데이터" id="recommendation-csv-import" className="mb-6 max-w-3xl space-y-3 text-sm">
      <div className="flex flex-wrap items-center gap-2"><h2 className="font-bold">추천 정보 CSV 가져오기</h2><Badge tone="neutral">실제 · 데모</Badge></div>
      <p className="text-muted">영업시간·주차·포장 같은 값을 식당별로 저장해요. <b>실제 데이터</b>(demo_data = FALSE)는 모든 앱·웹에서 쓰이고 따로 표시하지 않아요. <b>데모 데이터</b>(demo_data = TRUE)는 가상 값이라 데모 모드를 켠 빌드에서만 쓰이고 ‘데모 데이터’라고 표시돼요. 같은 식당에 다시 가져오면 그 줄이 바뀌어요(실제 줄이 데모 줄을 대신해요). 식당 정보·메뉴·사진·공개 상태·식당에 직접 입력한 값은 바뀌지 않고, 식당에 직접 입력한 값이 항상 먼저예요. 가격은 게시된 메뉴로, 위치는 카카오 실시간 좌표로만 계산해요.</p>
      <div className="flex flex-wrap items-center gap-2" role="radiogroup" aria-label="가져올 데이터의 종류">
        <span className="text-muted">이 파일의 줄은:</span>
        {([['file', '파일의 demo_data 열대로'], ['real', '모두 실제 데이터'], ['demo', '모두 데모 데이터']] as const).map(([k, label]) => (
          <label key={k} className="flex items-center gap-1"><input type="radio" name="import-kind" checked={kind === k} onChange={() => pickKind(k)} />{label}</label>
        ))}
      </div>
      <p>현재 저장된 데모 데이터: {count.isLoading ? '확인 중…' : count.error ? '표를 읽을 수 없어요 (마이그레이션이 아직 적용되지 않았을 수 있어요)' : `${count.data}곳`}</p>
      <div className="flex flex-wrap gap-2">
        <Button onClick={() => fileRef.current?.click()}>CSV 고르기</Button>
        <Button variant="outline" onClick={() => downloadText('recommendation-features-template.csv', demoTemplateCsv())}>CSV 양식 내려받기</Button>
        <Button variant="outline" disabled={exportAll.isPending || !count.data} onClick={() => exportAll.mutate()}>저장된 데이터 내려받기</Button>
        <Button variant="outline" disabled={clear.isPending || !count.data} onClick={() => { if (window.confirm('저장된 추천 데모 데이터를 모두 지울까요? (식당 정보는 지워지지 않아요)')) clear.mutate() }}>데모 데이터 모두 지우기</Button>
        <input ref={fileRef} type="file" accept=".csv,text/csv" hidden data-testid="demo-csv-input" onChange={(e) => { const f = e.target.files?.[0]; if (f) void read(f); e.target.value = '' }} />
      </div>
      {parsed?.fatal && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-amber-900">{parsed.fatal}</p>}
      {parsed && !parsed.fatal && (
        <div className="space-y-2" role="status" aria-label="데모 가져오기 미리보기">
          <div>파일 <b>{fileName}</b> · 전체 <b>{parsed.rows.length}줄</b> · 저장할 수 있는 줄 <b>{valid.length}</b> (실제 <b>{realCount}</b> · 데모 <b>{demoCount}</b>) · 오류 <b>{invalid.length}</b>{dup.length > 0 && <> · 파일 안 중복 {dup.length}</>}</div>
          {unknownIds.length > 0 && <div className="text-xs text-amber-900">식당 목록에 없는 장소 ID {unknownIds.length}곳이 있어요. 저장은 되지만 앱에서는 그 식당이 보일 때만 쓰여요.</div>}
          {parsed.ignored.length > 0 && <ul className="list-disc pl-5 text-xs text-muted">{parsed.ignored.map((x) => <li key={x.column}><b>{x.column}</b>: {x.reason}</li>)}</ul>}
          {parsed.unknown.length > 0 && <div className="text-xs text-muted">알 수 없는 열 (무시했어요): {parsed.unknown.join(', ')}</div>}
          {invalid.length > 0 && <ul className="max-h-32 overflow-auto text-xs text-red-700">{invalid.slice(0, 20).map((r) => <li key={r.line}>{r.line}줄: {r.errors.join(' / ')}</li>)}</ul>}
          <Button disabled={valid.length === 0 || run.isPending} onClick={() => run.mutate()}>{valid.length === 0 ? '저장할 줄이 없어요' : `${valid.length}곳 저장 (실제 ${realCount} · 데모 ${demoCount})`}</Button>
        </div>)}
      {notice && <p role={notice.ok ? 'status' : 'alert'} className={`rounded-xl p-3 ${notice.ok ? 'bg-brand/30' : 'bg-amber-50 text-amber-900'}`}>{notice.text}</p>}
    </Card>
  )
}
