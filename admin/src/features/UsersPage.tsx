import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import type { ColumnDef } from '@tanstack/react-table'
import { useMemo, useState } from 'react'
import { DataTable } from '@/components/DataTable'
import { Badge, Button, ConfirmDialog, Input, PageHeader } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage, formatDateTime } from '@/lib/utils'

type Profile = { id: string; nickname: string | null; account_status: 'active' | 'suspended'; preferred_language: string | null; created_at: string }
const PAGE = 20

/** Limited profile data only (no email, no credentials). Status changes go through a database function. */
export default function UsersPage() {
  const qc = useQueryClient()
  const [page, setPage] = useState(0)
  const [search, setSearch] = useState('')
  const [target, setTarget] = useState<Profile | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const list = useQuery({
    queryKey: ['users', page, search], placeholderData: keepPreviousData,
    queryFn: async () => {
      let q = supabase.from('profiles').select('id,nickname,account_status,preferred_language,created_at', { count: 'exact' })
      if (search.trim()) q = q.ilike('nickname', `%${search.trim().replace(/[%,()*\\]/g, ' ')}%`)
      const { data, error, count } = await q.order('created_at', { ascending: false }).range(page * PAGE, page * PAGE + PAGE - 1)
      if (error) throw error
      return { rows: data as Profile[], total: count ?? 0 }
    },
  })
  const change = useMutation({
    mutationFn: async ({ p, reason }: { p: Profile; reason: string }) => {
      const { error } = await supabase.rpc('admin_set_account_status', { p_user: p.id, p_status: p.account_status === 'active' ? 'suspended' : 'active', p_reason: reason })
      if (error) throw error
    },
    onSuccess: async () => { setTarget(null); setNotice('저장했어요. 활동 기록에 남았어요.'); await qc.invalidateQueries({ queryKey: ['users'] }) },
    onError: (e) => { setTarget(null); setNotice(errorMessage(e)) },
  })
  const columns = useMemo<ColumnDef<Profile, unknown>[]>(() => [
    { accessorKey: 'nickname', header: '닉네임', cell: ({ getValue }) => (getValue() as string | null) ?? '(없음)' },
    { accessorKey: 'account_status', header: '상태', cell: ({ getValue }) => getValue() === 'active' ? <Badge tone="green">정상</Badge> : <Badge tone="red">정지</Badge> },
    { accessorKey: 'preferred_language', header: '언어', cell: ({ getValue }) => (getValue() as string | null) ?? '—' },
    { accessorKey: 'created_at', header: '가입일', cell: ({ getValue }) => formatDateTime(getValue() as string) },
    { id: 'a', header: '', cell: ({ row: { original: p } }) => <div className="text-right"><Button size="sm" variant={p.account_status === 'active' ? 'outline' : 'soft'} onClick={() => setTarget(p)}>{p.account_status === 'active' ? '정지' : '정지 해제'}</Button></div> },
  ], [])
  return (
    <>
      <PageHeader title="사용자" description="비밀번호나 이메일 같은 민감 정보는 보여주지 않아요." />
      {notice && <p role="status" className="mb-4 rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
      <div className="mb-4 max-w-sm"><Input aria-label="닉네임 검색" placeholder="닉네임 검색" value={search} onChange={(e) => { setSearch(e.target.value); setPage(0) }} /></div>
      <DataTable columns={columns} rows={list.data?.rows} total={list.data?.total} page={page} pageSize={PAGE} onPage={setPage} loading={list.isLoading} error={list.error} onRetry={() => void list.refetch()} />
      <ConfirmDialog open={!!target} askReason busy={change.isPending} danger={target?.account_status === 'active'}
        title={target?.account_status === 'active' ? '계정을 정지할까요?' : '정지를 해제할까요?'} description={target?.nickname ?? target?.id}
        confirmLabel="확인" onCancel={() => setTarget(null)} onConfirm={(reason) => target && change.mutate({ p: target, reason })} />
    </>
  )
}
