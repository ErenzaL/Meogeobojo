import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, PageHeader, Skeleton } from '@/components/ui'
import { useAuth } from '@/lib/auth'
import { supabase } from '@/lib/supabase'
import { errorMessage, formatDateTime } from '@/lib/utils'
import ReviewsTab from './reviews/ReviewsTab'

// 문의 및 제안 arrive as reports of type 'feedback' whose target is the category (migration 20261121000100).
const TARGET_LABEL: Record<string, string> = { feedback: '문의·제안', review: '리뷰', restaurant: '식당', user: '사용자', question: '문의', suggestion: '제안', bug: '오류 신고' }
type Report = { id: string; target_type: string; target_id: string; reason: string; description: string | null; status: 'open' | 'resolved' | 'dismissed'; resolution_notes: string | null; created_at: string }

/** 신고 and 리뷰. The 리뷰 tab (every restaurant's reviews, CSV 가져오기 / 내보내기, moderation) is shared with each restaurant's page (ReviewsPanel). */
export default function ModerationPage() {
  const qc = useQueryClient()
  const { can } = useAuth()
  // the tab lives in the address (?tab=reviews), so coming back from a restaurant's review page lands on the reviews
  const [params, setParams] = useSearchParams()
  const tab: 'reports' | 'reviews' = params.get('tab') === 'reviews' ? 'reviews' : 'reports'
  const setTab = (t: 'reports' | 'reviews') => setParams(t === 'reviews' ? { tab: 'reviews' } : {}, { replace: true })
  const [notice, setNotice] = useState<string | null>(null)
  const [act, setAct] = useState<{ r: Report; to: Report['status'] } | null>(null)

  const reports = useQuery({ queryKey: ['reports'], enabled: tab === 'reports', queryFn: async () => {
    const { data, error } = await supabase.from('reports').select('*').order('status').order('created_at', { ascending: false }).limit(100)
    if (error) throw error
    return data as Report[]
  } })

  const run = useMutation({
    mutationFn: async ({ a, reason }: { a: NonNullable<typeof act>; reason: string }) => {
      const { error } = await supabase.rpc('admin_resolve_report', { p_report: a.r.id, p_status: a.to, p_notes: reason })
      if (error) throw error
    },
    onSuccess: async () => { setAct(null); setNotice('처리했어요. 활동 기록에 사유가 남았어요.'); await qc.invalidateQueries({ queryKey: ['reports'] }) },
    onError: (e) => { setAct(null); setNotice(errorMessage(e)) },
  })
  return (
    <>
      <PageHeader title="리뷰·신고" description="처리할 때마다 사유가 활동 기록에 남아요." />
      <div className="mb-4 flex gap-2">
        {(['reports', 'reviews'] as const).map((t) => <Button key={t} variant={tab === t ? 'soft' : 'outline'} onClick={() => setTab(t)}>{t === 'reports' ? '신고' : '리뷰'}</Button>)}
      </div>
      {tab === 'reviews' && <ReviewsTab canImport={can('admin')} />}
      {tab === 'reports' && (
        <>
          {notice && <p role="status" className="mb-4 rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
          {reports.isLoading && <Skeleton className="h-32 w-full" />}
          {reports.error && <ErrorState error={reports.error} onRetry={() => void reports.refetch()} />}
          {reports.data?.length === 0 && <EmptyState>접수된 신고가 없어요.</EmptyState>}
          <div className="space-y-3">
            {reports.data?.map((r) => (
              <Card key={r.id} className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <div className="font-semibold">{r.reason} <Badge tone={r.status === 'open' ? 'amber' : r.status === 'resolved' ? 'green' : 'neutral'}>{({ open: '대기', resolved: '처리됨', dismissed: '기각' })[r.status]}</Badge></div>
                  <div className="text-sm text-muted">{TARGET_LABEL[r.target_type] ?? r.target_type} · {TARGET_LABEL[r.target_id] ?? r.target_id} · {formatDateTime(r.created_at)}</div>
                  {r.description && <p className="mt-1 text-sm">{r.description}</p>}
                  {r.resolution_notes && <p className="mt-1 text-xs text-muted">처리 메모: {r.resolution_notes}</p>}
                </div>
                {r.status === 'open' && <div className="flex gap-2"><Button size="sm" onClick={() => setAct({ r, to: 'resolved' })}>처리 완료</Button><Button size="sm" variant="outline" onClick={() => setAct({ r, to: 'dismissed' })}>기각</Button></div>}
              </Card>))}
          </div>
          <ConfirmDialog open={!!act} askReason busy={run.isPending} title="사유를 입력해 주세요" description="입력한 사유는 활동 기록에 저장돼요." confirmLabel="처리"
            onCancel={() => setAct(null)} onConfirm={(reason) => act && run.mutate({ a: act, reason })} />
        </>)}
    </>
  )
}
