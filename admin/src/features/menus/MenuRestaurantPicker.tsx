import { ChevronDown, ChevronRight } from 'lucide-react'
import { useMemo, useState } from 'react'
import { Badge, Card, EmptyState, ErrorState, Field, Input, Select, Skeleton } from '@/components/ui'
import type { OverviewRow } from '@/lib/cms'
import { VISIBILITY_LABEL } from '../restaurants/schema'
import { buildView, NO_UNIVERSITY, UNASSIGNED_LABEL, universityCounts, type MenuFilter, type PickerFilters, type PickerRestaurant, type PickerUniversity } from './restaurantPicker'

const visTone = { draft: 'neutral', published: 'green', hidden: 'amber', archived: 'red' } as const

type Props = {
  restaurants: PickerRestaurant[] | undefined
  universities: PickerUniversity[]
  menuCounts: Map<string, number>
  overview: Map<string, OverviewRow>
  loading: boolean
  error: unknown
  onRetry: () => void
  filters: PickerFilters
  onFilters: (f: PickerFilters) => void
  selectedId: string
  onSelect: (id: string) => void
}

/** Every managed restaurant, grouped by school, with search and school / menu filters. Selecting one opens its menu editor. */
export default function MenuRestaurantPicker({ restaurants, universities, menuCounts, overview, loading, error, onRetry, filters, onFilters, selectedId, onSelect }: Props) {
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set())
  const all = useMemo(() => restaurants ?? [], [restaurants])
  const counts = useMemo(() => universityCounts(all, universities), [all, universities])
  const view = useMemo(() => buildView(all, universities, menuCounts, filters), [all, universities, menuCounts, filters])
  const selected = all.find((r) => r.id === selectedId)
  const schoolName = (id: string) => universities.find((u) => u.id === id)?.name_ko
  const searching = filters.search.trim() !== ''
  const toggle = (key: string) => setCollapsed((s) => { const n = new Set(s); if (n.has(key)) n.delete(key); else n.add(key); return n })
  const set = (patch: Partial<PickerFilters>) => onFilters({ ...filters, ...patch })

  return (
    <Card className="mb-5 space-y-3">
      <div className="grid gap-3 sm:grid-cols-3">
        <Field label="식당 검색" htmlFor="rq"><Input id="rq" value={filters.search} onChange={(e) => set({ search: e.target.value })} placeholder="이름 또는 카테고리로 검색" /></Field>
        <Field label="대학교" htmlFor="ru">
          <Select id="ru" value={filters.university} onChange={(e) => set({ university: e.target.value })}>
            <option value="">전체 대학교 ({all.length})</option>
            {universities.map((u) => <option key={u.id} value={u.id}>{u.name_ko} ({counts.byUniversity.get(u.id) ?? 0})</option>)}
            <option value={NO_UNIVERSITY}>{UNASSIGNED_LABEL} ({counts.unassigned})</option>
          </Select>
        </Field>
        <Field label="메뉴" htmlFor="rm">
          <Select id="rm" value={filters.menu} onChange={(e) => set({ menu: e.target.value as MenuFilter })}>
            <option value="">전체</option><option value="none">메뉴 없는 식당</option><option value="has">메뉴 있는 식당</option>
          </Select>
        </Field>
      </div>

      {loading && <Skeleton className="h-40 w-full" />}
      {!loading && error != null && <ErrorState error={error} onRetry={onRetry} />}
      {!loading && error == null && (
        <>
          <p role="status" className="text-sm text-muted">
            전체 {all.length}곳 중 <b className="text-ink">{view.total}곳</b> · 메뉴 있음 {view.withMenu} / 없음 {view.withoutMenu}
          </p>
          {view.total === 0
            ? <EmptyState>{all.length === 0 ? '관리 중인 식당이 없어요. 식당 메뉴에서 먼저 식당을 추가하세요.' : '조건에 맞는 식당이 없어요.'}</EmptyState>
            : (
              <div role="group" aria-label="식당 목록" className="max-h-[22rem] space-y-3 overflow-y-auto rounded-xl border border-line">
                {view.groups.map((g) => {
                  const open = searching || !collapsed.has(g.key)
                  return (
                    <section key={g.key} aria-label={g.name}>
                      <button type="button" aria-expanded={open} aria-label={`${g.name} ${open ? '접기' : '펼치기'}`} onClick={() => toggle(g.key)}
                        className="sticky top-0 z-10 flex w-full items-center gap-2 border-b border-line bg-page px-3 py-2 text-left text-sm font-bold">
                        {open ? <ChevronDown className="size-4" /> : <ChevronRight className="size-4" />}
                        <span>{g.name}</span>
                        <span className="font-normal text-muted">{g.restaurants.length}곳 · 메뉴 없음 {g.restaurants.length - g.withMenu}</span>
                      </button>
                      {open && (
                        <ul>
                          {g.restaurants.map((r) => {
                            const n = menuCounts.get(r.id) ?? 0
                            const o = overview.get(r.id)
                            const active = r.id === selectedId
                            return (
                              <li key={r.id}>
                                <button type="button" aria-pressed={active} onClick={() => onSelect(r.id)}
                                  className={`flex w-full flex-wrap items-center gap-x-2 gap-y-1 px-3 py-2 text-left text-sm hover:bg-page ${active ? 'bg-brand/30 font-semibold' : ''}`}>
                                  <span className="min-w-0 flex-1 truncate">{r.name_ko}{r.category ? <span className="ml-2 text-xs font-normal text-muted">{r.category}</span> : null}</span>
                                  {r.visibility && <Badge tone={visTone[r.visibility]}>{VISIBILITY_LABEL[r.visibility]}</Badge>}
                                  {n > 0 ? <Badge tone="neutral">메뉴 {n}개</Badge> : <Badge tone="amber">메뉴 없음</Badge>}
                                  {o?.scheduled_at ? <Badge tone="brand">예약됨</Badge> : o?.has_draft ? <Badge tone="brand">초안 있음</Badge> : null}
                                </button>
                              </li>)
                          })}
                        </ul>)}
                    </section>)
                })}
              </div>)}
          <p className="text-sm text-muted" aria-live="polite">
            {selected
              ? <>선택한 식당: <b className="text-ink">{selected.name_ko}</b>{selected.universityIds.map(schoolName).filter(Boolean).length > 0 ? ` · ${selected.universityIds.map(schoolName).filter(Boolean).join(', ')}` : ''}</>
              : '식당을 고르면 메뉴가 보여요. 여러 대학교에 걸친 식당은 각 대학교에 모두 보여요.'}
          </p>
        </>)}
    </Card>
  )
}
