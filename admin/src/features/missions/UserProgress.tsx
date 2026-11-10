import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Input, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage, formatDateTime } from '@/lib/utils'

type Hit = { id: string; nickname: string | null }
type History = {
  progress: { mission_id: string; title: string; kind: string; period_key: string; progress: number; target: number; completed_at: string | null; revoked_at: string | null; version: number }[]
  transactions: { id: number; points: number; kind: string; reason: string | null; period_key: string | null; ref_id: number | null; created_at: string }[]
  badges: { badge_key: string; name: string | null; awarded_at: string; revoked_at: string | null }[]
  contributions: { id: string; kind: string; place: string; status: string; created_at: string }[]
  balance: number
}
type Suspicious = { user_id: string; reason: string; detail: string; last_seen: string }

const REASON: Record<string, string> = { many_events: '짧은 시간에 활동이 너무 많아요', rapid_completions: '짧은 시간에 미션을 연달아 완료했어요', many_pending: '검토 대기 기여가 많아요' }
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** Support / fraud view. There is deliberately NO way to edit progress or a
 *  balance: a bad reward is reversed with a reasoned, audited negative row. */
export default function UserProgress() {
  const qc = useQueryClient()
  const [term, setTerm] = useState('')
  const [user, setUser] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [act, setAct] = useState<{ kind: 'reward'; id: number } | { kind: 'badge'; key: string } | null>(null)

  const hits = useQuery({
    queryKey: ['mission-user-search', term],
    enabled: term.trim().length >= 2 && !UUID.test(term.trim()),
    queryFn: async () => {
      const { data, error } = await supabase.from('profiles').select('id,nickname').ilike('nickname', `%${term.trim()}%`).limit(10)
      if (error) throw error
      return data as Hit[]
    },
  })
  const suspicious = useQuery({
    queryKey: ['mission-suspicious'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('admin_suspicious_mission_activity', { p_hours: 24 })
      if (error) throw error
      return (data ?? []) as Suspicious[]
    },
  })
  const history = useQuery({
    queryKey: ['mission-user-history', user],
    enabled: !!user,
    queryFn: async () => {
      const { data, error } = await supabase.rpc('admin_user_missions', { p_user: user })
      if (error) throw error
      return data as History
    },
  })
  const revoke = useMutation({
    mutationFn: async ({ a, reason }: { a: NonNullable<typeof act>; reason: string }) => {
      const { error } = a.kind === 'reward'
        ? await supabase.rpc('admin_revoke_reward', { p_tx: a.id, p_reason: reason })
        : await supabase.rpc('admin_revoke_badge', { p_user: user, p_badge: a.key, p_reason: reason })
      if (error) throw error
    },
    onSuccess: async () => { setAct(null); setNotice('회수했어요. 마이너스 거래와 사유가 활동 기록에 남았어요.'); await qc.invalidateQueries({ queryKey: ['mission-user-history', user] }) },
    onError: (e) => { setAct(null); setNotice(errorMessage(e)) },
  })

  const h = history.data
  const revokedTx = new Set((h?.transactions ?? []).filter((t) => t.kind === 'revocation').map((t) => t.ref_id))
  const pick = (id: string) => { setUser(id); setNotice(null) }

  return (
    <div className="space-y-4">
      {notice && <p role="status" className="rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
      <Card className="space-y-3">
        <h3 className="font-bold">사용자 찾기</h3>
        <div className="flex gap-2">
          <Input aria-label="닉네임 또는 사용자 ID" placeholder="닉네임 (2자 이상) 또는 사용자 ID" value={term} onChange={(e) => setTerm(e.target.value)} />
          {UUID.test(term.trim()) && <Button onClick={() => pick(term.trim())}>조회</Button>}
        </div>
        {hits.data?.length === 0 && <p className="text-sm text-muted">일치하는 사용자가 없어요.</p>}
        <ul className="space-y-1">{hits.data?.map((u) => <li key={u.id}><button className="text-sm font-medium text-brand-strong underline" onClick={() => pick(u.id)}>{u.nickname ?? '(닉네임 없음)'}</button> <span className="text-xs text-muted">{u.id}</span></li>)}</ul>
      </Card>

      <Card className="space-y-3">
        <h3 className="font-bold">의심스러운 활동 (최근 24시간)</h3>
        {suspicious.isLoading && <Skeleton className="h-10 w-full" />}
        {suspicious.error && <ErrorState error={suspicious.error} />}
        {suspicious.data?.length === 0 && <p className="text-sm text-muted">지금은 없어요.</p>}
        <ul className="space-y-1.5">
          {suspicious.data?.map((s, i) => (
            <li key={`${s.user_id}-${i}`} className="flex flex-wrap items-center gap-2 text-sm">
              <Badge tone="amber">{REASON[s.reason] ?? s.reason}</Badge><span className="text-muted">{s.detail} · {formatDateTime(s.last_seen)}</span>
              <button className="font-medium text-brand-strong underline" onClick={() => pick(s.user_id)}>기록 보기</button>
            </li>))}
        </ul>
        <p className="text-xs text-muted">자동 판정이 아니에요. 사람이 확인할 단서예요.</p>
      </Card>

      {user && (
        <Card className="space-y-4">
          <h3 className="font-bold">사용자 {user}</h3>
          {history.isLoading && <Skeleton className="h-32 w-full" />}
          {history.error && <ErrorState error={history.error} onRetry={() => void history.refetch()} />}
          {h && (
            <>
              <p className="text-sm">포인트 잔액 <b>{h.balance}P</b></p>
              <section><h4 className="mb-1 text-sm font-semibold">미션 진행·완료 기록</h4>
                {h.progress.length === 0 ? <p className="text-sm text-muted">기록이 없어요.</p> :
                  <ul className="space-y-1 text-sm">{h.progress.map((p) => <li key={`${p.mission_id}-${p.period_key}`}>{p.title}{p.version > 1 ? ` v${p.version}` : ''} · {p.period_key} · {Math.min(p.progress, p.target)}/{p.target} {p.completed_at ? <Badge tone={p.revoked_at ? 'red' : 'green'}>{p.revoked_at ? '회수됨' : '완료'}</Badge> : null}</li>)}</ul>}
              </section>
              <section><h4 className="mb-1 text-sm font-semibold">포인트 거래</h4>
                {h.transactions.length === 0 ? <p className="text-sm text-muted">거래가 없어요.</p> :
                  <ul className="space-y-1 text-sm">{h.transactions.map((t) => (
                    <li key={t.id} className="flex flex-wrap items-center gap-2">
                      <span className={t.points < 0 ? 'text-red-700' : ''}>{t.points > 0 ? '+' : ''}{t.points}P</span><span className="text-muted">{t.kind === 'revocation' ? '회수' : '미션 보상'} · {t.reason ?? ''} · {formatDateTime(t.created_at)}</span>
                      {t.kind === 'mission_reward' && !revokedTx.has(t.id) && <Button size="sm" variant="outline" onClick={() => setAct({ kind: 'reward', id: t.id })}>회수</Button>}
                    </li>))}</ul>}
              </section>
              <section><h4 className="mb-1 text-sm font-semibold">뱃지</h4>
                {h.badges.length === 0 ? <p className="text-sm text-muted">뱃지가 없어요.</p> :
                  <ul className="space-y-1 text-sm">{h.badges.map((b) => <li key={b.badge_key} className="flex items-center gap-2">{b.name ?? b.badge_key} <span className="text-muted">{formatDateTime(b.awarded_at)}</span>{b.revoked_at ? <Badge tone="red">회수됨</Badge> : <Button size="sm" variant="outline" onClick={() => setAct({ kind: 'badge', key: b.badge_key })}>회수</Button>}</li>)}</ul>}
              </section>
              <section><h4 className="mb-1 text-sm font-semibold">기여</h4>
                {h.contributions.length === 0 ? <p className="text-sm text-muted">기여가 없어요.</p> :
                  <ul className="space-y-1 text-sm">{h.contributions.map((c) => <li key={c.id}>{c.kind === 'menu_photo' ? '메뉴 사진' : '정보 수정'} · {c.place} · {c.status}</li>)}</ul>}
              </section>
            </>)}
        </Card>)}
      {!user && !suspicious.data?.length && <EmptyState>사용자를 검색해 미션 기록과 포인트를 확인해 보세요.</EmptyState>}
      <ConfirmDialog open={!!act} askReason danger busy={revoke.isPending} title={act?.kind === 'reward' ? '보상 회수' : '뱃지 회수'}
        description="사유와 함께 활동 기록에 남아요. 회수한 보상은 같은 기간에 다시 지급되지 않아요. 포인트 잔액을 직접 바꾸는 기능은 없어요."
        confirmLabel="회수" onCancel={() => setAct(null)} onConfirm={(reason) => act && revoke.mutate({ a: act, reason })} />
    </div>
  )
}
