import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef, SortingState } from '@tanstack/react-table'
import { Download, Pencil, Plus, Search, Upload } from 'lucide-react'
import { useMemo, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { DataTable } from '@/components/DataTable'
import { Badge, Button, ConfirmDialog, ErrorState, Input, PageHeader, Select } from '@/components/ui'
import { useAuth } from '@/lib/auth'
import { cmsOverview, cmsSetVisibility, formatKst, type OverviewRow } from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import { errorMessage, formatDateTime } from '@/lib/utils'
import KakaoImport from './KakaoImport'
import { buildCsv, parseRestaurantCsv, toRow, type ParsedRow } from './csv'
import { VISIBILITIES, VISIBILITY_LABEL, type Visibility } from './schema'

type Row = {
  id: string; kakao_place_id: string | null; name_ko: string; category: string | null; address: string | null
  visibility: Visibility; updated_at: string; description: string | null; image_url?: string | null
  restaurant_university_links?: { universities: { name_ko: string } | null }[]
}
const PAGE = 20
const tone = { draft: 'neutral', published: 'green', hidden: 'amber', archived: 'red' } as const
const clean = (s: string) => s.replace(/[%,()*\\]/g, ' ').trim()

export function useUniversities() {
  return useQuery({
    queryKey: ['universities'],
    queryFn: async () => {
      const { data, error } = await supabase.from('universities').select('id,name_ko,is_active,latitude,longitude,search_radius_m').order('name_ko')
      if (error) throw error
      return data as { id: string; name_ko: string; is_active: boolean; latitude: number | null; longitude: number | null }[]
    },
  })
}

/** Photo / menu coverage over every managed restaurant (real counts, one pass). */
export function useCoverage() {
  return useQuery({
    queryKey: ['restaurant-coverage'],
    queryFn: async () => {
      const [r, m] = await Promise.all([
        supabase.from('restaurant_overrides').select('id,image_url,visibility').limit(5000),
        supabase.from('restaurant_menus').select('restaurant_id').limit(20000),
      ])
      if (r.error) throw r.error
      if (m.error) throw m.error
      const rows = r.data as { id: string; image_url: string | null; visibility: string }[]
      const menuIds = [...new Set((m.data as { restaurant_id: string | null }[]).map((x) => x.restaurant_id).filter((x): x is string => !!x))]
      const withMenu = new Set(menuIds)
      return {
        total: rows.length, withPhoto: rows.filter((x) => x.image_url).length, withMenu: rows.filter((x) => withMenu.has(x.id)).length,
        published: rows.filter((x) => x.visibility === 'published').length, menuIds,
      }
    },
  })
}

export default function RestaurantsPage() {
  const qc = useQueryClient()
  const { can } = useAuth()
  const [page, setPage] = useState(0)
  const [search, setSearch] = useState('')
  const [visibility, setVisibility] = useState('')
  const [university, setUniversity] = useState('')
  const [category, setCategory] = useState('')
  const [photo, setPhoto] = useState('')
  const [pub, setPub] = useState('')
  const [menu, setMenu] = useState('')
  const [sorting, setSorting] = useState<SortingState>([{ id: 'updated_at', desc: true }])
  const [confirm, setConfirm] = useState<{ row: Row; to: Visibility } | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const unis = useUniversities()

  const sort = sorting[0] ?? { id: 'updated_at', desc: true }
  const overview = useQuery({ queryKey: ['cms-overview'], queryFn: () => cmsOverview('restaurant'), staleTime: 10_000 })
  const ov = useMemo(() => new Map<string, OverviewRow>((overview.data ?? []).map((r) => [r.entity_id, r])), [overview.data])
  const pubIds = (pred: (r: OverviewRow) => boolean) => (overview.data ?? []).filter(pred).map((r) => r.entity_id)
  const coverage = useCoverage()
  const menuIds = coverage.data?.menuIds
  const filters = { page, search, visibility, university, category, photo, menu, sort, menuIds: menu ? menuIds?.length : 0, pub, pubCount: overview.data?.length ?? 0 }
  const list = useQuery({
    queryKey: ['restaurants', filters],
    placeholderData: keepPreviousData,
    queryFn: async () => {
      let q = supabase
        .from('restaurant_overrides')
        .select(university ? '*, restaurant_university_links!inner(university_id, universities(name_ko))' : '*, restaurant_university_links(universities(name_ko))', { count: 'exact' })
      if (search.trim()) q = q.or(`name_ko.ilike.%${clean(search)}%,kakao_place_id.ilike.%${clean(search)}%`)
      if (visibility) q = q.eq('visibility', visibility)
      if (category.trim()) q = q.ilike('category', `%${clean(category)}%`)
      if (university) q = q.eq('restaurant_university_links.university_id', university)
      // publishing status: draft / scheduled / failed come from the publishing overview, published / archived from the live row
      if (pub === 'published') q = q.eq('visibility', 'published')
      if (pub === 'archived') q = q.in('visibility', ['archived', 'hidden'])
      if (pub === 'draft') { const ids = pubIds((r) => r.has_draft); q = ids.length ? q.or(`visibility.eq.draft,id.in.(${ids.join(',')})`) : q.eq('visibility', 'draft') }
      if (pub === 'scheduled' || pub === 'failed') {
        const ids = pubIds((r) => (pub === 'scheduled' ? r.scheduled_at !== null : r.failed_jobs > 0))
        q = q.in('id', ids.length ? ids : ['00000000-0000-0000-0000-000000000000'])
      }
      if (photo === 'none') q = q.is('image_url', null)
      if (photo === 'has') q = q.not('image_url', 'is', null)
      if (menu === 'has') q = q.in('id', menuIds?.length ? menuIds : ['00000000-0000-0000-0000-000000000000'])
      if (menu === 'none' && menuIds?.length) q = q.not('id', 'in', `(${menuIds.join(',')})`)
      const { data, error, count } = await q.order(sort.id, { ascending: !sort.desc }).range(page * PAGE, page * PAGE + PAGE - 1)
      if (error) throw error
      return { rows: data as unknown as Row[], total: count ?? 0 }
    },
  })

  // An immediate, versioned change (history + audit), not a silent edit of the live row.
  const setVis = useMutation({
    mutationFn: async ({ id, to, reason }: { id: string; to: Visibility; reason: string }) => { await cmsSetVisibility('restaurant', id, to, reason) },
    onSuccess: async () => { setConfirm(null); setNotice('공개 상태를 바꿨어요. 게시 이력에 남았어요.'); await qc.invalidateQueries({ queryKey: ['restaurants'] }); await qc.invalidateQueries({ queryKey: ['cms-overview'] }) },
    onError: (e) => { setConfirm(null); setNotice(errorMessage(e)) },
  })

  const columns = useMemo<ColumnDef<Row, unknown>[]>(() => [
    { accessorKey: 'name_ko', header: '이름', cell: ({ row: { original: r } }) => (
      <div className="flex items-center gap-3">
        {r.image_url ? <img src={r.image_url} alt="" className="size-10 rounded-lg object-cover" loading="lazy" /> : <span className="grid size-10 place-items-center rounded-lg bg-page text-[10px] text-muted" title="대표 사진 없음">없음</span>}
        <div><Link className="font-semibold hover:underline" to={`/restaurants/${r.id}`}>{r.name_ko}</Link>
          <div className="text-xs text-muted">{r.kakao_place_id ? `Kakao ID ${r.kakao_place_id}` : '직접 등록'}</div></div></div>) },
    { accessorKey: 'category', header: '카테고리', enableSorting: false, cell: ({ getValue }) => (getValue() as string | null) ?? '—' },
    { id: 'university', header: '대학교', enableSorting: false, cell: ({ row: { original: r } }) => (r.restaurant_university_links?.map((l) => l.universities?.name_ko).filter(Boolean).join(', ') || '—') },
    { accessorKey: 'address', header: '주소', enableSorting: false, cell: ({ getValue }) => <span className="text-sm text-muted">{(getValue() as string | null) ?? '—'}</span> },
    { accessorKey: 'visibility', header: '라이브 상태', enableSorting: false, cell: ({ getValue }) => <Badge tone={tone[getValue() as Visibility]}>{VISIBILITY_LABEL[getValue() as Visibility]}</Badge> },
    { id: 'publishing', header: '게시', enableSorting: false, cell: ({ row: { original: r } }) => {
      const o = ov.get(r.id)
      if (!o) return <span className="text-xs text-muted">—</span>
      return (
        <div className="flex flex-wrap gap-1">
          {o.has_draft && <Badge tone="brand">초안 있음</Badge>}
          {o.scheduled_at && <Badge tone="amber">예약 {formatKst(o.scheduled_at)}</Badge>}
          {o.failed_jobs > 0 && <Badge tone="red">실패 {o.failed_jobs}</Badge>}
          {!o.has_draft && !o.scheduled_at && o.failed_jobs === 0 && <span className="text-xs text-muted">{o.live_version > 0 ? `v${o.live_version}` : '—'}</span>}
        </div>)
    } },
    { id: 'complete', header: '정보', enableSorting: false, cell: ({ row: { original: r } }) => (r.description ? <Badge tone="green">설명 있음</Badge> : <Badge tone="amber">설명 없음</Badge>) },
    { accessorKey: 'updated_at', header: '수정일', cell: ({ getValue }) => formatDateTime(getValue() as string) },
    { id: 'actions', header: '', enableSorting: false, cell: ({ row: { original: r } }) => (
      <div className="flex justify-end gap-1.5">
        <Link to={`/restaurants/${r.id}`}><Button size="sm" variant="outline"><Pencil className="size-3.5" />편집</Button></Link>
        {r.visibility !== 'published'
          ? <Button size="sm" variant="soft" onClick={() => setConfirm({ row: r, to: 'published' })}>공개</Button>
          : <Button size="sm" variant="outline" onClick={() => setConfirm({ row: r, to: 'hidden' })}>숨기기</Button>}
      </div>) },
  ], [ov])

  const fileRef = useRef<HTMLInputElement>(null)
  const [importRows, setImportRows] = useState<ParsedRow[] | null>(null)

  const exportCsv = async () => {
    setNotice(null)
    let q = supabase.from('restaurant_overrides').select('*').order('name_ko').limit(5000)
    if (visibility) q = q.eq('visibility', visibility)
    const { data, error } = await q
    if (error) return setNotice(errorMessage(error))
    const url = URL.createObjectURL(new Blob(['﻿' + buildCsv(data)], { type: 'text/csv;charset=utf-8' }))
    const a = document.createElement('a'); a.href = url; a.download = 'restaurants.csv'; a.click(); URL.revokeObjectURL(url)
  }

  const runImport = useMutation({
    mutationFn: async (rows: ParsedRow[]) => {
      const valid = rows.filter((r) => r.values && !r.duplicateInFile)
      const ids = valid.map((r) => r.values!.kakao_place_id).filter(Boolean)
      const existing = new Set<string>()
      for (let i = 0; i < ids.length; i += 200) {
        const { data, error } = await supabase.from('restaurant_overrides').select('kakao_place_id').in('kakao_place_id', ids.slice(i, i + 200))
        if (error) throw error
        data.forEach((d) => d.kakao_place_id && existing.add(d.kakao_place_id as string))
      }
      const fresh = valid.filter((r) => !existing.has(r.values!.kakao_place_id))
      for (let i = 0; i < fresh.length; i += 200) {
        const { error } = await supabase.from('restaurant_overrides').insert(fresh.slice(i, i + 200).map((r) => ({ ...toRow(r.values!), visibility: 'draft', featured: false })))  // imported places always start as drafts
        if (error) throw error
      }
      return { added: fresh.length, skippedDuplicates: valid.length - fresh.length, invalid: rows.length - valid.length }
    },
    onSuccess: async (r) => {
      setImportRows(null)
      setNotice(`${r.added}개를 초안으로 추가했어요. 이미 있는 ${r.skippedDuplicates}개는 건너뛰었고, 오류 ${r.invalid}개는 제외했어요.`)
      await qc.invalidateQueries({ queryKey: ['restaurants'] })
    },
    onError: (e) => setNotice(errorMessage(e)),
  })

  return (
    <>
      <PageHeader title="식당" description="카카오에서 가져온 식당에 우리가 추가·수정한 정보를 관리해요."
        actions={<>
          <Button variant="outline" onClick={() => void exportCsv()}><Download className="size-4" />CSV 내보내기</Button>
          {can('admin') && <Button variant="outline" onClick={() => fileRef.current?.click()}><Upload className="size-4" />CSV 가져오기</Button>}
          {can('admin') && <Link to="/restaurants/new"><Button><Plus className="size-4" />식당 추가</Button></Link>}
          <input ref={fileRef} type="file" accept=".csv,text/csv" hidden data-testid="csv-input"
            onChange={async (e) => { const f = e.target.files?.[0]; if (f) setImportRows(parseRestaurantCsv(await f.text())); e.target.value = '' }} />
        </>} />
      {notice && <p role="status" className="mb-4 rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
      <div className="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <div className="relative sm:col-span-2 lg:col-span-1">
          <Search className="pointer-events-none absolute left-3 top-3 size-4 text-muted" />
          <Input aria-label="식당 검색" className="pl-9" placeholder="이름 또는 Kakao ID 검색" value={search} onChange={(e) => { setSearch(e.target.value); setPage(0) }} />
        </div>
        <Select aria-label="공개 상태" value={visibility} onChange={(e) => { setVisibility(e.target.value); setPage(0) }}>
          <option value="">모든 상태</option>{VISIBILITIES.map((v) => <option key={v} value={v}>{VISIBILITY_LABEL[v]}</option>)}
        </Select>
        <Select aria-label="대학교" value={university} onChange={(e) => { setUniversity(e.target.value); setPage(0) }}>
          <option value="">모든 대학교</option>{unis.data?.map((u) => <option key={u.id} value={u.id}>{u.name_ko}</option>)}
        </Select>
        <Input aria-label="카테고리" placeholder="카테고리 (예: 한식)" value={category} onChange={(e) => { setCategory(e.target.value); setPage(0) }} />
        <Select aria-label="게시 상태 필터" value={pub} onChange={(e) => { setPub(e.target.value); setPage(0) }}>
          <option value="">게시: 전체</option><option value="draft">초안</option><option value="scheduled">예약됨</option><option value="published">게시됨</option><option value="archived">보관·숨김</option><option value="failed">실패</option>
        </Select>
        <Select aria-label="사진 필터" value={photo} onChange={(e) => { setPhoto(e.target.value); setPage(0) }}>
          <option value="">사진: 전체</option><option value="none">대표 사진 없음</option><option value="has">대표 사진 있음</option>
        </Select>
        <Select aria-label="메뉴 필터" value={menu} onChange={(e) => { setMenu(e.target.value); setPage(0) }}>
          <option value="">메뉴: 전체</option><option value="none">메뉴 없음</option><option value="has">메뉴 있음</option>
        </Select>
      </div>
      {coverage.data && (
        <p role="status" aria-label="사진·메뉴 현황" className="mb-4 flex flex-wrap gap-x-6 gap-y-1 rounded-xl bg-white p-3 text-sm ring-1 ring-line">
          <span>관리 중 <b>{coverage.data.total}</b>곳 (공개 {coverage.data.published})</span>
          <span>대표 사진 <b>{coverage.data.withPhoto}</b> / 없음 <b>{coverage.data.total - coverage.data.withPhoto}</b></span>
          <span>메뉴 <b>{coverage.data.withMenu}</b> / 없음 <b>{coverage.data.total - coverage.data.withMenu}</b></span>
        </p>)}
      {coverage.isError && <p role="alert" className="mb-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">사진·메뉴 현황을 불러오지 못했어요: {errorMessage(coverage.error)}</p>}
      {can('admin') && <KakaoImport universities={unis.data ?? []} />}
      <DataTable columns={columns} rows={list.data?.rows} total={list.data?.total} page={page} pageSize={PAGE} onPage={setPage}
        loading={list.isLoading} error={list.error} onRetry={() => void list.refetch()} sorting={sorting} onSorting={(s) => { setSorting(s); setPage(0) }}
        empty="조건에 맞는 식당이 없어요. 위의 '카카오 식당 불러오기'로 대학교 주변 식당을 불러올 수 있어요." />

      <ConfirmDialog open={!!confirm} busy={setVis.isPending} askReason
        title={confirm?.to === 'published' ? '이 식당을 공개할까요?' : '이 식당을 숨길까요?'}
        description={confirm ? `${confirm.row.name_ko} — ${confirm.to === 'published' ? '앱 사용자에게 보여요.' : '앱에서 이 식당이 숨겨져요.'}` : undefined}
        confirmLabel={confirm?.to === 'published' ? '공개' : '숨기기'} danger={confirm?.to !== 'published'}
        onConfirm={(reason) => confirm && setVis.mutate({ id: confirm.row.id, to: confirm.to, reason })} onCancel={() => setConfirm(null)} />

      {importRows && (
        <ConfirmDialog open title="CSV 가져오기 미리보기" confirmLabel="가져오기" busy={runImport.isPending}
          description={`전체 ${importRows.length}행 · 정상 ${importRows.filter((r) => r.values && !r.duplicateInFile).length}행 · 오류/중복 ${importRows.filter((r) => !r.values || r.duplicateInFile).length}행. 새 식당은 초안으로 추가되고, 이미 있는 Kakao ID는 건너뛰어요. 기존 데이터는 바뀌지 않아요.`}
          onConfirm={() => runImport.mutate(importRows)} onCancel={() => setImportRows(null)} />
      )}
      {list.isError && null}
      {runImport.isError && <ErrorState error={runImport.error} />}
    </>
  )
}
