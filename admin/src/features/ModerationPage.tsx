import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, PageHeader, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage, formatDateTime } from '@/lib/utils'

type Review = { id: string; kakao_place_id: string; rating: number; body: string | null; moderation_status: 'visible' | 'hidden' | 'removed'; moderation_reason: string | null; created_at: string }
// 문의 및 제안 arrive as reports of type 'feedback' whose target is the category (migration 20261121000100).
const TARGET_LABEL: Record<string, string> = { feedback: '문의·제안', review: '리뷰', restaurant: '식당', user: '사용자', question: '문의', suggestion: '제안', bug: '오류 신고' }
type Report = { id: string; target_type: string; target_id: string; reason: string; description: string | null; status: 'open' | 'resolved' | 'dismissed'; resolution_notes: string | null; created_at: string }

export default function ModerationPage() {
  const qc = useQueryClient()
  const [tab, setTab] = useState<'reports' | 'reviews'>('reports')
  const [notice, setNotice] = useState<string | null>(null)
  const [act, setAct] = useState<{ kind: 'review'; r: Review; to: Review['moderation_status'] } | { kind: 'report'; r: Report; to: Report['status'] } | null>(null)

  const reports = useQuery({ queryKey: ['reports'], enabled: tab === 'reports', queryFn: async () => {
    const { data, error } = await supabase.from('reports').select('*').order('status').order('created_at', { ascending: false }).limit(100)
    if (error) throw error
    return data as Report[]
  } })
  const reviews = useQuery({ queryKey: ['reviews-mod'], enabled: tab === 'reviews', queryFn: async () => {
    const { data, error } = await supabase.from('student_reviews').select('id,kakao_place_id,rating,body,moderation_status,moderation_reason,created_at').order('created_at', { ascending: false }).limit(100)
    if (error) throw error
    return data as Review[]
  } })

  const run = useMutation({
    mutationFn: async ({ a, reason }: { a: NonNullable<typeof act>; reason: string }) => {
      const { error } = a.kind === 'review'
        ? await supabase.rpc('admin_moderate_review', { p_review: a.r.id, p_status: a.to, p_reason: reason })
        : await supabase.rpc('admin_resolve_report', { p_report: a.r.id, p_status: a.to, p_notes: reason })
      if (error) throw error
    },
    onSuccess: async () => { setAct(null); setNotice('처리했어요. 활동 기록에 사유가 남았어요.'); await qc.invalidateQueries({ queryKey: ['reports'] }); await qc.invalidateQueries({ queryKey: ['reviews-mod'] }) },
    onError: (e) => { setAct(null); setNotice(errorMessage(e)) },
  })
  const q = tab === 'reports' ? reports : reviews
  return (
    <>
      <PageHeader title="리뷰·신고" description="처리할 때마다 사유가 활동 기록에 남아요." />
      {notice && <p role="status" className="mb-4 rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
      <div className="mb-4 flex gap-2">
        {(['reports', 'reviews'] as const).map((t) => <Button key={t} variant={tab === t ? 'soft' : 'outline'} onClick={() => setTab(t)}>{t === 'reports' ? '신고' : '리뷰'}</Button>)}
      </div>
      {q.isLoading && <Skeleton className="h-32 w-full" />}
      {q.error && <ErrorState error={q.error} onRetry={() => void q.refetch()} />}
      {tab === 'reports' && reports.data?.length === 0 && <EmptyState>접수된 신고가 없어요.</EmptyState>}
      {tab === 'reviews' && reviews.data?.length === 0 && <EmptyState>리뷰가 없어요.</EmptyState>}
      <div className="space-y-3">
        {tab === 'reports' && reports.data?.map((r) => (
          <Card key={r.id} className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <div className="font-semibold">{r.reason} <Badge tone={r.status === 'open' ? 'amber' : r.status === 'resolved' ? 'green' : 'neutral'}>{({ open: '대기', resolved: '처리됨', dismissed: '기각' })[r.status]}</Badge></div>
              <div className="text-sm text-muted">{TARGET_LABEL[r.target_type] ?? r.target_type} · {TARGET_LABEL[r.target_id] ?? r.target_id} · {formatDateTime(r.created_at)}</div>
              {r.description && <p className="mt-1 text-sm">{r.description}</p>}
              {r.resolution_notes && <p className="mt-1 text-xs text-muted">처리 메모: {r.resolution_notes}</p>}
            </div>
            {r.status === 'open' && <div className="flex gap-2"><Button size="sm" onClick={() => setAct({ kind: 'report', r, to: 'resolved' })}>처리 완료</Button><Button size="sm" variant="outline" onClick={() => setAct({ kind: 'report', r, to: 'dismissed' })}>기각</Button></div>}
          </Card>))}
        {tab === 'reviews' && reviews.data?.map((r) => (
          <Card key={r.id} className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <div className="font-semibold">★ {r.rating} <Badge tone={r.moderation_status === 'visible' ? 'green' : 'red'}>{({ visible: '공개', hidden: '숨김', removed: '삭제됨' })[r.moderation_status]}</Badge></div>
              <p className="text-sm">{r.body ?? '(내용 없음)'}</p>
              <div className="text-xs text-muted">{r.kakao_place_id} · {formatDateTime(r.created_at)}{r.moderation_reason ? ` · 사유: ${r.moderation_reason}` : ''}</div>
            </div>
            <div className="flex gap-2">
              {r.moderation_status === 'visible'
                ? <><Button size="sm" variant="outline" onClick={() => setAct({ kind: 'review', r, to: 'hidden' })}>숨기기</Button><Button size="sm" variant="danger" onClick={() => setAct({ kind: 'review', r, to: 'removed' })}>삭제</Button></>
                : <Button size="sm" variant="soft" onClick={() => setAct({ kind: 'review', r, to: 'visible' })}>다시 공개</Button>}
            </div>
          </Card>))}
      </div>
      <ConfirmDialog open={!!act} askReason busy={run.isPending} title="사유를 입력해 주세요" description="입력한 사유는 활동 기록에 저장돼요." confirmLabel="처리"
        danger={act?.to === 'removed'} onCancel={() => setAct(null)} onConfirm={(reason) => act && run.mutate({ a: act, reason })} />
    </>
  )
}
