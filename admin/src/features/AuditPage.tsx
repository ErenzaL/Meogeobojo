import { keepPreviousData, useQuery } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { useMemo, useState } from 'react'
import { DataTable } from '@/components/DataTable'
import { PageHeader } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { formatDateTime } from '@/lib/utils'

type Entry = { id: number; actor_id: string | null; action: string; table_name: string | null; row_id: string | null; reason: string | null; created_at: string }
const PAGE = 25

export default function AuditPage() {
  const [page, setPage] = useState(0)
  const list = useQuery({
    queryKey: ['audit', page], placeholderData: keepPreviousData,
    queryFn: async () => {
      const { data, error, count } = await supabase.from('audit_log').select('id,actor_id,action,table_name,row_id,reason,created_at', { count: 'exact' }).order('id', { ascending: false }).range(page * PAGE, page * PAGE + PAGE - 1)
      if (error) throw error
      return { rows: data as Entry[], total: count ?? 0 }
    },
  })
  const columns = useMemo<ColumnDef<Entry, unknown>[]>(() => [
    { accessorKey: 'created_at', header: '시각', cell: ({ getValue }) => formatDateTime(getValue() as string) },
    { accessorKey: 'action', header: '작업' },
    { accessorKey: 'table_name', header: '대상', cell: ({ row: { original: e } }) => `${e.table_name ?? '—'} ${e.row_id ? `#${e.row_id.slice(0, 8)}` : ''}` },
    { accessorKey: 'actor_id', header: '실행자', cell: ({ getValue }) => (getValue() as string | null)?.slice(0, 8) ?? '시스템' },
    { accessorKey: 'reason', header: '사유', cell: ({ getValue }) => (getValue() as string | null) ?? '—' },
  ], [])
  return (
    <>
      <PageHeader title="활동 기록" description="관리자가 바꾼 모든 내용이 자동으로 기록돼요." />
      <DataTable columns={columns} rows={list.data?.rows} total={list.data?.total} page={page} pageSize={PAGE} onPage={setPage} loading={list.isLoading} error={list.error} onRetry={() => void list.refetch()} empty="기록이 아직 없어요." />
    </>
  )
}
