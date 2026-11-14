import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef, SortingState } from '@tanstack/react-table'
import { Download, Pencil, Plus, Search, Trash2, Upload } from 'lucide-react'
import { useMemo, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { DataTable } from '@/components/DataTable'
import { Badge, Button, ConfirmDialog, ErrorState, Input, PageHeader, Select } from '@/components/ui'
import { useAuth } from '@/lib/auth'
import { cmsOverview, cmsSetVisibility, formatKst, type OverviewRow } from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import { errorMessage, formatDateTime } from '@/lib/utils'
import BulkVisibilityDialog from './BulkVisibilityDialog'
import DeleteRestaurantsDialog from './DeleteRestaurantsDialog'
import KakaoImport from './KakaoImport'
import { buildCsv, parseRestaurantCsv, toRow, type ParsedRow } from './csv'
import { KakaoLiveCell } from './KakaoLiveUi'
import { campusesOf } from './useKakaoRestaurantDetails'
import { VISIBILITIES, VISIBILITY_LABEL, type Visibility } from './schema'

type Row = {
  id: string; kakao_place_id: string | null; name_ko: string; category: string | null; address: string | null
  visibility: Visibility; updated_at: string; description: string | null; image_url?: string | null; latitude?: number | null; longitude?: number | null
  restaurant_university_links?: { university_id?: string; universities: { name_ko: string } | null }[]
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
      return data as { id: string; name_ko: string; is_active: boolean; latitude: number | null; longitude: number | null; search_radius_m?: number | null }[]
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
  const [showKakao, setShowKakao] = useState(false) // live Kakao info per row: off until asked, so a long list never calls Kakao by itself
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
  type QB = ReturnType<ReturnType<typeof supabase.from>['select']>
  /** The page's search + filters, applied to a query. The list AND "select every matching result" use this one function, so they can never disagree. */
  const applyFilters = (q: QB): QB => {
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
    return q
  }
  const list = useQuery({
    queryKey: ['restaurants', filters],
    placeholderData: keepPreviousData,
    queryFn: async () => {
      const q = applyFilters(supabase
        .from('restaurant_overrides')
        .select(university ? '*, restaurant_university_links!inner(university_id, universities(name_ko))' : '*, restaurant_university_links(university_id, universities(name_ko))', { count: 'exact' }))
      const { data, error, count } = await q.order(sort.id, { ascending: !sort.desc }).range(page * PAGE, page * PAGE + PAGE - 1)
      if (error) throw error
      return { rows: data as unknown as Row[], total: count ?? 0 }
    },
  })

  // ---- bulk selection (admins only). The selection is a set of restaurant ids that survives paging, sorting and filter changes.
  const canBulk = can('admin')
  type Sel = { ids: Set<string>; kind: 'custom' | 'page' | 'filtered' | 'all'; key: string; count: number }
  const [sel, setSel] = useState<Sel>({ ids: new Set(), kind: 'custom', key: '', count: 0 })
  const [selecting, setSelecting] = useState(false)
  const [bulk, setBulk] = useState<'published' | 'hidden' | null>(null)
  // deleting restaurants is for super admins only (the database enforces it; the buttons are simply not shown to anyone else)
  const canDelete = can('super_admin')
  const [del, setDel] = useState<string[] | null>(null)
  const filterKey = JSON.stringify([search, visibility, university, category, photo, menu, pub])
  const viewKey = JSON.stringify([page, filterKey, sort])
  const pageIds = (list.data?.rows ?? []).map((r) => r.id)
  // How the selection was made only counts while it still describes what is on screen.
  const kind: Sel['kind'] = sel.ids.size === 0 ? 'custom' : sel.kind === 'page' && sel.key !== viewKey ? 'custom' : sel.kind === 'filtered' && sel.key !== filterKey ? 'custom' : sel.kind
  const onPageSelected = pageIds.filter((id) => sel.ids.has(id)).length
  const toggleRow = (id: string) => setSel((p) => { const ids = new Set(p.ids); if (!ids.delete(id)) ids.add(id); return { ids, kind: 'custom', key: '', count: ids.size } })
  const togglePage = () => setSel((p) => {
    const ids = new Set(p.ids)
    if (pageIds.length > 0 && pageIds.every((id) => ids.has(id))) pageIds.forEach((id) => ids.delete(id)); else pageIds.forEach((id) => ids.add(id))
    return { ids, kind: ids.size === pageIds.length && pageIds.every((id) => ids.has(id)) ? 'page' : 'custom', key: viewKey, count: ids.size }
  })
  const selectPageOnly = () => setSel({ ids: new Set(pageIds), kind: 'page', key: viewKey, count: pageIds.length })
  const clearSel = () => setSel({ ids: new Set(), kind: 'custom', key: '', count: 0 })
  /** Every id (not just this page), 1000 at a time, with the same filters as the list. */
  const collectIds = async (scope: 'filtered' | 'all') => {
    const out: string[] = []
    for (let from = 0; from < 5000; from += 1000) {
      const base = supabase.from('restaurant_overrides').select(scope === 'filtered' && university ? 'id,restaurant_university_links!inner(university_id)' : 'id') as unknown as QB
      const q = scope === 'filtered' ? applyFilters(base) : base
      const { data, error } = await q.order('id').range(from, from + 999)
      if (error) throw error
      out.push(...(data as unknown as { id: string }[]).map((r) => r.id))
      if (data.length < 1000) break
    }
    return out
  }
  const selectMatching = async (scope: 'filtered' | 'all') => {
    setSelecting(true); setNotice(null)
    try {
      const ids = await collectIds(scope)
      setSel({ ids: new Set(ids), kind: scope, key: scope === 'filtered' ? filterKey : '', count: ids.length })
      if (ids.length >= 5000) setNotice('5,000곳까지만 선택해요. 필터로 범위를 줄여 주세요.')
    } catch (e) { setNotice(errorMessage(e)) } finally { setSelecting(false) }
  }

  // An immediate, versioned change (history + audit), not a silent edit of the live row.
  const setVis = useMutation({
    mutationFn: async ({ id, to, reason }: { id: string; to: Visibility; reason: string }) => { await cmsSetVisibility('restaurant', id, to, reason) },
    onSuccess: async () => { setConfirm(null); setNotice('공개 상태를 바꿨어요. 게시 이력에 남았어요.'); await qc.invalidateQueries({ queryKey: ['restaurants'] }); await qc.invalidateQueries({ queryKey: ['cms-overview'] }) },
    onError: (e) => { setConfirm(null); setNotice(errorMessage(e)) },
  })

  const columns = useMemo<ColumnDef<Row, unknown>[]>(() => [
    ...(canBulk ? [{
      id: 'select', enableSorting: false,
      header: () => (
        <input type="checkbox" aria-label="이 페이지 모두 선택/해제 (표 머리글)" title="이 페이지의 식당을 선택에 더하거나 빼요"
          checked={pageIds.length > 0 && pageIds.every((id) => sel.ids.has(id))}
          ref={(el) => { if (el) el.indeterminate = pageIds.some((id) => sel.ids.has(id)) && !pageIds.every((id) => sel.ids.has(id)) }}
          onChange={togglePage} />),
      cell: ({ row: { original: r } }: { row: { original: Row } }) => <input type="checkbox" aria-label={`${r.name_ko} 선택`} checked={sel.ids.has(r.id)} onChange={() => toggleRow(r.id)} />,
    } as ColumnDef<Row, unknown>] : []),
    { accessorKey: 'name_ko', header: '이름', cell: ({ row: { original: r } }) => (
      <div className="flex items-center gap-3">
        {r.image_url ? <img src={r.image_url} alt="" className="size-10 rounded-lg object-cover" loading="lazy" /> : <span className="grid size-10 place-items-center rounded-lg bg-page text-[10px] text-muted" title="대표 사진 없음">없음</span>}
        <div><Link className="font-semibold hover:underline" to={`/restaurants/${r.id}`}>{r.name_ko}</Link>
          <div className="text-xs text-muted">{r.kakao_place_id ? `Kakao ID ${r.kakao_place_id}` : '직접 등록'}</div></div></div>) },
    { accessorKey: 'category', header: '카테고리', enableSorting: false, cell: ({ getValue }) => (getValue() as string | null) ?? '—' },
    { id: 'kakao', header: '카카오 실시간', enableSorting: false, cell: ({ row: { original: r } }) => {
      const byId = new Map((unis.data ?? []).map((u) => [u.id, u]))
      const campuses = campusesOf((r.restaurant_university_links ?? []).map((l) => (l.university_id ? byId.get(l.university_id) : undefined)))
      return <KakaoLiveCell placeId={r.kakao_place_id} name={r.name_ko} enabled={showKakao} location={{ campuses, near: r.latitude != null && r.longitude != null ? { latitude: r.latitude, longitude: r.longitude } : null }} />
    } },
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
        {canDelete && <Button size="icon" variant="ghost" aria-label={`${r.name_ko} 삭제`} disabled={r.visibility === 'published'} title={r.visibility === 'published' ? '공개 중인 식당은 먼저 숨기기를 해 주세요' : '식당 삭제'} onClick={() => setDel([r.id])}><Trash2 className="size-4 text-red-600" /></Button>}
        {r.visibility !== 'published'
          ? <Button size="sm" variant="soft" onClick={() => setConfirm({ row: r, to: 'published' })}>공개</Button>
          : <Button size="sm" variant="outline" onClick={() => setConfirm({ row: r, to: 'hidden' })}>숨기기</Button>}
      </div>) },
  // eslint-disable-next-line react-hooks/exhaustive-deps
  ], [ov, canBulk, canDelete, sel.ids, list.data?.rows, viewKey, showKakao, unis.data])

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
      <div className="mb-3 flex flex-wrap items-center gap-3 text-sm">
        <label className="flex items-center gap-2"><input type="checkbox" checked={showKakao} onChange={(e) => setShowKakao(e.target.checked)} />카카오 실시간 정보 보기 (이 페이지 {PAGE}곳까지)</label>
        <span className="text-xs text-muted">켜면 지금 보이는 식당만 카카오에서 조회해요 (동시에 3건, 10분간 기억). 저장하지 않아요.</span>
      </div>
      {coverage.data && (
        <p role="status" aria-label="사진·메뉴 현황" className="mb-4 flex flex-wrap gap-x-6 gap-y-1 rounded-xl bg-white p-3 text-sm ring-1 ring-line">
          <span>관리 중 <b>{coverage.data.total}</b>곳 (공개 {coverage.data.published})</span>
          <span>대표 사진 <b>{coverage.data.withPhoto}</b> / 없음 <b>{coverage.data.total - coverage.data.withPhoto}</b></span>
          <span>메뉴 <b>{coverage.data.withMenu}</b> / 없음 <b>{coverage.data.total - coverage.data.withMenu}</b></span>
        </p>)}
      {coverage.isError && <p role="alert" className="mb-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">사진·메뉴 현황을 불러오지 못했어요: {errorMessage(coverage.error)}</p>}
      {can('admin') && <KakaoImport universities={unis.data ?? []} />}
      {canBulk && (
        <div className="mb-3 space-y-2 rounded-2xl border border-line bg-white p-3" role="group" aria-label="일괄 선택과 공개">
          <div className="flex flex-wrap items-center gap-2">
            <Button size="sm" variant="outline" disabled={selecting} onClick={() => void selectMatching('all')}>전체 선택 ({coverage.data?.total ?? '…'}곳)</Button>
            <Button size="sm" variant="outline" disabled={selecting || pageIds.length === 0} onClick={selectPageOnly}>현재 페이지 전체 선택 ({pageIds.length}곳)</Button>
            <Button size="sm" variant="outline" disabled={selecting || !list.data?.total} onClick={() => void selectMatching('filtered')}>검색/필터 결과 전체 선택 ({list.data?.total ?? 0}곳)</Button>
            <Button size="sm" variant="ghost" disabled={sel.ids.size === 0} onClick={clearSel}>선택 해제</Button>
            <span className="mx-1 hidden h-5 w-px bg-line sm:block" />
            <Button size="sm" variant="soft" disabled={sel.ids.size === 0 || selecting} onClick={() => setBulk('published')}>선택한 식당 공개</Button>
            <Button size="sm" variant="outline" disabled={sel.ids.size === 0 || selecting} onClick={() => setBulk('hidden')}>선택한 식당 비공개</Button>
            {canDelete && <Button size="sm" variant="danger" disabled={sel.ids.size === 0 || selecting} onClick={() => setDel([...sel.ids])}><Trash2 className="size-3.5" />선택한 식당 삭제</Button>}
          </div>
          <p role="status" aria-label="선택 현황" className="text-sm">
            {selecting ? '선택하는 중…' : <>선택한 식당 <b>{sel.ids.size}곳</b>
              {sel.ids.size > 0 && <span className="text-xs text-muted"> · {kind === 'page' ? `선택 방식: 현재 페이지 ${sel.count}곳` : kind === 'filtered' ? `선택 방식: 검색/필터 결과 전체 ${sel.count}곳` : kind === 'all' ? `선택 방식: 전체 ${sel.count}곳` : `선택 방식: 직접 선택 (이 페이지 ${onPageSelected}곳 포함, 다른 페이지·필터에서 고른 식당도 포함돼요)`}</span>}
            </>}
          </p>
        </div>)}
      <DataTable columns={columns} rows={list.data?.rows} total={list.data?.total} page={page} pageSize={PAGE} onPage={setPage}
        loading={list.isLoading} error={list.error} onRetry={() => void list.refetch()} sorting={sorting} onSorting={(s) => { setSorting(s); setPage(0) }}
        empty="조건에 맞는 식당이 없어요. 위의 '카카오 식당 불러오기'로 대학교 주변 식당을 불러올 수 있어요." />

      {bulk && (
        <BulkVisibilityDialog to={bulk} ids={[...sel.ids]} onClose={(changed) => {
          setBulk(null)
          if (changed) {
            clearSel()
            setNotice('일괄 처리가 끝났어요. 목록과 공개 수를 새로 불러왔어요.')
            void qc.invalidateQueries({ queryKey: ['restaurants'] }); void qc.invalidateQueries({ queryKey: ['cms-overview'] }); void qc.invalidateQueries({ queryKey: ['restaurant-coverage'] })
          }
        }} />)}

      {del && (
        <DeleteRestaurantsDialog ids={del} onClose={(deletedIds) => {
          setDel(null)
          if (deletedIds.length > 0) {
            const gone = new Set(deletedIds)
            setSel((p) => { const ids = new Set([...p.ids].filter((id) => !gone.has(id))); return { ids, kind: 'custom', key: '', count: ids.size } })
            setNotice(`${deletedIds.length}곳을 삭제했어요. 목록과 공개 수를 새로 불러왔어요.`)
            void qc.invalidateQueries({ queryKey: ['restaurants'] }); void qc.invalidateQueries({ queryKey: ['cms-overview'] }); void qc.invalidateQueries({ queryKey: ['restaurant-coverage'] })
          }
        }} />)}

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
