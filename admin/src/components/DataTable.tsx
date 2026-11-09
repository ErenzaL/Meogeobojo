import { flexRender, getCoreRowModel, useReactTable, type ColumnDef, type SortingState } from '@tanstack/react-table'
import { ChevronDown, ChevronLeft, ChevronRight, ChevronUp } from 'lucide-react'
import { Button, EmptyState, ErrorState, Skeleton } from '@/components/ui'

type Props<T> = {
  columns: ColumnDef<T, unknown>[]
  rows: T[] | undefined
  total: number | undefined
  page: number
  pageSize: number
  onPage: (p: number) => void
  loading: boolean
  error?: unknown
  onRetry?: () => void
  sorting?: SortingState
  onSorting?: (s: SortingState) => void
  empty?: string
}

/** Server-side pagination and sorting: the parent runs the query for one page. */
export function DataTable<T>({ columns, rows, total, page, pageSize, onPage, loading, error, onRetry, sorting, onSorting, empty = '표시할 항목이 없어요.' }: Props<T>) {
  // TanStack Table returns unmemoizable functions; fine here (not passed to memoized children).
  // eslint-disable-next-line react-hooks/incompatible-library
  const table = useReactTable({
    data: rows ?? [],
    columns,
    getCoreRowModel: getCoreRowModel(),
    manualPagination: true,
    manualSorting: true,
    state: { sorting: sorting ?? [] },
    onSortingChange: (u) => onSorting?.(typeof u === 'function' ? u(sorting ?? []) : u),
  })
  if (error) return <ErrorState error={error} onRetry={onRetry} />
  const pages = total != null ? Math.max(1, Math.ceil(total / pageSize)) : 1
  return (
    <div className="space-y-3">
      <div className="overflow-x-auto rounded-2xl border border-line bg-white">
        <table className="w-full text-sm">
          <thead className="border-b border-line bg-page/60 text-left text-xs text-muted">
            {table.getHeaderGroups().map((hg) => (
              <tr key={hg.id}>
                {hg.headers.map((h) => {
                  const sortable = h.column.getCanSort() && onSorting
                  const dir = h.column.getIsSorted()
                  return (
                    <th key={h.id} className="px-4 py-3 font-medium">
                      {sortable ? (
                        <button className="inline-flex items-center gap-1" onClick={h.column.getToggleSortingHandler()}>
                          {flexRender(h.column.columnDef.header, h.getContext())}
                          {dir === 'asc' ? <ChevronUp className="size-3" /> : dir === 'desc' ? <ChevronDown className="size-3" /> : null}
                        </button>
                      ) : flexRender(h.column.columnDef.header, h.getContext())}
                    </th>
                  )
                })}
              </tr>
            ))}
          </thead>
          <tbody>
            {loading
              ? Array.from({ length: 5 }, (_, i) => (
                  <tr key={i} className="border-b border-line last:border-0">
                    <td colSpan={columns.length} className="px-4 py-3"><Skeleton className="h-5 w-full" /></td>
                  </tr>
                ))
              : table.getRowModel().rows.map((r) => (
                  <tr key={r.id} className="border-b border-line last:border-0 hover:bg-page/40">
                    {r.getVisibleCells().map((c) => (
                      <td key={c.id} className="px-4 py-3 align-middle">{flexRender(c.column.columnDef.cell, c.getContext())}</td>
                    ))}
                  </tr>
                ))}
          </tbody>
        </table>
      </div>
      {!loading && rows?.length === 0 && <EmptyState>{empty}</EmptyState>}
      <div className="flex items-center justify-between text-sm text-muted">
        <span>{total != null ? `총 ${total.toLocaleString('ko-KR')}개` : ''}</span>
        <div className="flex items-center gap-2">
          <Button size="icon" variant="outline" aria-label="이전 페이지" disabled={page <= 0} onClick={() => onPage(page - 1)}><ChevronLeft className="size-4" /></Button>
          <span>{page + 1} / {pages}</span>
          <Button size="icon" variant="outline" aria-label="다음 페이지" disabled={page + 1 >= pages} onClick={() => onPage(page + 1)}><ChevronRight className="size-4" /></Button>
        </div>
      </div>
    </div>
  )
}
