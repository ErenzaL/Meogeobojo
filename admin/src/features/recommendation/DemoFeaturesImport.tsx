import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useRef, useState } from 'react'
import { Badge, Button, Card } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import { chunk } from '../restaurants/kakao'
import { parseDemoCsv, type DemoParse } from './demoImport'

const TABLE = 'recommendation_demo_features'

/** 추천 page: development-only import of the simulated recommendation features. Writes to ONE table, nothing else. */
export default function DemoFeaturesImport() {
  const qc = useQueryClient()
  const fileRef = useRef<HTMLInputElement>(null)
  const [parsed, setParsed] = useState<DemoParse | null>(null)
  const [fileName, setFileName] = useState('')
  const [known, setKnown] = useState<Set<string>>(new Set())
  const [notice, setNotice] = useState<{ ok: boolean; text: string } | null>(null)

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
    const p = parseDemoCsv(await file.text())
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

  const valid = (parsed?.rows ?? []).filter((r) => r.row && !r.duplicate)
  const invalid = (parsed?.rows ?? []).filter((r) => !r.row)
  const dup = (parsed?.rows ?? []).filter((r) => r.row && r.duplicate)
  const unknownIds = valid.filter((r) => !known.has(r.row!.kakao_place_id))

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
    onSuccess: async (n) => { setNotice({ ok: true, text: `데모 데이터 ${n}곳을 저장했어요. 식당·메뉴·사진·공개 상태는 바뀌지 않았어요.` }); setParsed(null); await qc.invalidateQueries({ queryKey: ['demo-features-count'] }) },
    onError: (e) => setNotice({ ok: false, text: errorMessage(e) }),
  })
  const clear = useMutation({
    mutationFn: async () => { const { error } = await supabase.from(TABLE).delete().neq('kakao_place_id', ''); if (error) throw error },
    onSuccess: async () => { setNotice({ ok: true, text: '데모 데이터를 모두 지웠어요.' }); await qc.invalidateQueries({ queryKey: ['demo-features-count'] }) },
    onError: (e) => setNotice({ ok: false, text: errorMessage(e) }),
  })

  return (
    <Card aria-label="추천 데모 데이터" className="mb-6 max-w-3xl space-y-3 text-sm">
      <div className="flex flex-wrap items-center gap-2"><h2 className="font-bold">추천 데모 데이터 (개발용)</h2><Badge tone="amber">가상 데이터</Badge></div>
      <p className="text-muted">영업시간·주차·포장 같은 <b>가상</b> 값을 추천 시연용으로 따로 저장해요. 실제로 확인된 정보가 아니고, 식당 정보·메뉴·사진·공개 상태·관리자가 입력한 값은 바뀌지 않아요. 앱에서는 데모 모드를 켠 빌드에서만 읽고, 쓰는 곳에는 ‘데모 데이터’라고 표시해요. 가격은 게시된 메뉴로, 위치는 카카오 실시간 좌표로만 계산해요.</p>
      <p>현재 저장된 데모 데이터: {count.isLoading ? '확인 중…' : count.error ? '표를 읽을 수 없어요 (마이그레이션이 아직 적용되지 않았을 수 있어요)' : `${count.data}곳`}</p>
      <div className="flex flex-wrap gap-2">
        <Button variant="outline" onClick={() => fileRef.current?.click()}>데모 CSV 고르기</Button>
        <Button variant="outline" disabled={clear.isPending || !count.data} onClick={() => { if (window.confirm('저장된 추천 데모 데이터를 모두 지울까요? (식당 정보는 지워지지 않아요)')) clear.mutate() }}>데모 데이터 모두 지우기</Button>
        <input ref={fileRef} type="file" accept=".csv,text/csv" hidden data-testid="demo-csv-input" onChange={(e) => { const f = e.target.files?.[0]; if (f) void read(f); e.target.value = '' }} />
      </div>
      {parsed?.fatal && <p role="alert" className="rounded-xl bg-amber-50 p-3 text-amber-900">{parsed.fatal}</p>}
      {parsed && !parsed.fatal && (
        <div className="space-y-2" role="status" aria-label="데모 가져오기 미리보기">
          <div>파일 <b>{fileName}</b> · 전체 <b>{parsed.rows.length}줄</b> · 저장할 수 있는 줄 <b>{valid.length}</b> · 오류 <b>{invalid.length}</b>{dup.length > 0 && <> · 파일 안 중복 {dup.length}</>}</div>
          {unknownIds.length > 0 && <div className="text-xs text-amber-900">식당 목록에 없는 장소 ID {unknownIds.length}곳이 있어요. 저장은 되지만 앱에서는 그 식당이 보일 때만 쓰여요.</div>}
          {parsed.ignored.length > 0 && <ul className="list-disc pl-5 text-xs text-muted">{parsed.ignored.map((x) => <li key={x.column}><b>{x.column}</b>: {x.reason}</li>)}</ul>}
          {parsed.unknown.length > 0 && <div className="text-xs text-muted">알 수 없는 열 (무시했어요): {parsed.unknown.join(', ')}</div>}
          {invalid.length > 0 && <ul className="max-h-32 overflow-auto text-xs text-red-700">{invalid.slice(0, 20).map((r) => <li key={r.line}>{r.line}줄: {r.errors.join(' / ')}</li>)}</ul>}
          <Button disabled={valid.length === 0 || run.isPending} onClick={() => run.mutate()}>{valid.length === 0 ? '저장할 줄이 없어요' : `데모 데이터 ${valid.length}곳 저장`}</Button>
        </div>)}
      {notice && <p role={notice.ok ? 'status' : 'alert'} className={`rounded-xl p-3 ${notice.ok ? 'bg-brand/30' : 'bg-amber-50 text-amber-900'}`}>{notice.text}</p>}
    </Card>
  )
}
