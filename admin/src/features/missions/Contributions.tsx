import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage, formatDateTime } from '@/lib/utils'

type Contribution = { id: string; user_id: string; kind: 'menu_photo' | 'info_correction'; kakao_place_id: string; payload: Record<string, unknown>; status: string; created_at: string }

/** Approve or reject users' menu photos and corrections. Approving updates the
 *  contributor's mission progress at once (in the database). */
export default function Contributions() {
  const qc = useQueryClient()
  const [notice, setNotice] = useState<string | null>(null)
  const [reject, setReject] = useState<Contribution | null>(null)
  const q = useQuery({
    queryKey: ['contributions-pending'],
    queryFn: async () => {
      const { data, error } = await supabase.from('user_contributions').select('*').eq('status', 'pending').order('created_at')
      if (error) throw error
      return data as Contribution[]
    },
  })
  const review = useMutation({
    mutationFn: async ({ c, status, note }: { c: Contribution; status: 'approved' | 'rejected'; note: string }) => {
      const { error } = await supabase.rpc('admin_review_contribution', { p_id: c.id, p_status: status, p_note: note || null })
      if (error) throw error
    },
    onSuccess: async () => { setReject(null); setNotice('처리했어요.'); await qc.invalidateQueries({ queryKey: ['contributions-pending'] }) },
    onError: (e) => { setReject(null); setNotice(errorMessage(e)) },
  })
  if (q.isLoading) return <Skeleton className="h-32 w-full" />
  if (q.error) return <ErrorState error={q.error} onRetry={() => void q.refetch()} />
  return (
    <>
      {notice && <p role="status" className="mb-4 rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
      {q.data?.length === 0 && <EmptyState>검토할 기여가 없어요.</EmptyState>}
      <div className="space-y-3">
        {q.data?.map((c) => (
          <Card key={c.id} className="flex flex-wrap items-center justify-between gap-3">
            <div className="min-w-0">
              <div className="flex items-center gap-2 font-semibold"><Badge tone="brand">{c.kind === 'menu_photo' ? '메뉴 사진' : '정보 수정'}</Badge>식당 {c.kakao_place_id}</div>
              <div className="text-xs text-muted">{formatDateTime(c.created_at)} · 사용자 {c.user_id}</div>
              <pre className="mt-1 max-w-xl overflow-x-auto rounded-lg bg-page p-2 text-xs">{JSON.stringify(c.payload, null, 1)}</pre>
            </div>
            <div className="flex gap-2">
              <Button size="sm" disabled={review.isPending} onClick={() => review.mutate({ c, status: 'approved', note: '' })}>승인</Button>
              <Button size="sm" variant="outline" onClick={() => setReject(c)}>반려</Button>
            </div>
          </Card>))}
      </div>
      <ConfirmDialog open={!!reject} askReason danger busy={review.isPending} title="기여 반려" description="반려 사유는 활동 기록에 남아요. 반려된 기여는 미션에 반영되지 않아요."
        confirmLabel="반려" onCancel={() => setReject(null)} onConfirm={(note) => reject && review.mutate({ c: reject, status: 'rejected', note })} />
    </>
  )
}
