import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import PublishingCenter from '@/components/PublishingCenter'
import { Badge, Button, Card, ConfirmDialog, ErrorState, Field, Input, PageHeader, Select } from '@/components/ui'
import { useAuth } from '@/lib/auth'
import { ROLE_LABEL, type Role } from '@/lib/roles'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'

const NO_NAME = '(닉네임 없음)'

export default function SettingsPage() {
  const { state, can } = useAuth()
  const qc = useQueryClient()
  const [uid, setUid] = useState('')
  const [role, setRole] = useState<Role>('moderator')
  const [notice, setNotice] = useState<string | null>(null)
  const [revoke, setRevoke] = useState<string | null>(null)
  // each role holder with the nickname from their profile, so the list shows who is who (the id stays for copying)
  const roles = useQuery({ queryKey: ['roles'], enabled: can('super_admin'), queryFn: async () => {
    const { data, error } = await supabase.from('admin_roles').select('user_id,role,created_at').order('created_at')
    if (error) throw error
    const rows = data as { user_id: string; role: Role; created_at: string }[]
    // a failed name lookup must not hide the roles: the list then falls back to the ids
    const names = new Map<string, string>()
    if (rows.length > 0) {
      const { data: profiles } = await supabase.from('profiles').select('id,nickname').in('id', rows.map((r) => r.user_id))
      for (const p of (profiles ?? []) as { id: string; nickname: string | null }[]) if (p.nickname?.trim()) names.set(p.id, p.nickname.trim())
    }
    return rows.map((r) => ({ ...r, nickname: names.get(r.user_id) ?? null }))
  } })
  const holder = (id: string) => roles.data?.find((r) => r.user_id === id)
  const run = useMutation({
    mutationFn: async (fn: () => PromiseLike<{ error: unknown }>) => { const { error } = await fn(); if (error) throw error },
    onSuccess: async () => { setNotice('저장했어요.'); setRevoke(null); await qc.invalidateQueries({ queryKey: ['roles'] }) },
    onError: (e) => { setRevoke(null); setNotice(errorMessage(e)) },
  })
  if (state.status !== 'ready') return null
  return (
    <>
      <PageHeader title="설정" />
      <Card className="mb-5 max-w-xl text-sm">
        <div>로그인: <b>{state.email}</b></div>
        <div className="mt-1">내 역할: <Badge tone="brand">{ROLE_LABEL[state.role]}</Badge></div>
        <p className="mt-3 text-xs text-muted">권한은 데이터베이스(RLS)가 판단해요. 이 화면의 메뉴 숨김은 편의 기능일 뿐이에요.</p>
      </Card>
      {can('super_admin') && (
        <Card className="max-w-2xl space-y-4">
          <h2 className="font-bold">관리자 역할 (최고 관리자 전용)</h2>
          {notice && <p role="status" className="rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
          {roles.error && <ErrorState error={roles.error} />}
          <ul className="divide-y divide-line text-sm">
            {roles.data?.map((r) => (
              <li key={r.user_id} className="flex items-center justify-between gap-3 py-2">
                <span className="min-w-0">
                  <span className="font-semibold">{r.nickname ?? NO_NAME}</span> <Badge>{ROLE_LABEL[r.role]}</Badge>
                  <code className="block truncate text-xs text-muted">{r.user_id}</code>
                </span>
                <Button size="sm" variant="outline" onClick={() => setRevoke(r.user_id)}>해제</Button></li>))}
          </ul>
          <div className="grid gap-3 sm:grid-cols-[1fr_10rem_auto] sm:items-end">
            <Field label="사용자 ID (UUID)" htmlFor="gu"><Input id="gu" value={uid} onChange={(e) => setUid(e.target.value)} /></Field>
            <Field label="역할" htmlFor="gr"><Select id="gr" value={role} onChange={(e) => setRole(e.target.value as Role)}>{(Object.keys(ROLE_LABEL) as Role[]).map((r) => <option key={r} value={r}>{ROLE_LABEL[r]}</option>)}</Select></Field>
            <Button disabled={run.isPending || !/^[0-9a-f-]{36}$/i.test(uid.trim())} onClick={() => run.mutate(() => supabase.rpc('admin_grant_role', { p_user: uid.trim(), p_role: role }))}>부여</Button>
          </div>
        </Card>)}
      {can('admin') && <PublishingCenter />}
      <ConfirmDialog open={!!revoke} danger title="역할을 해제할까요?" description={revoke ? `${holder(revoke)?.nickname ?? NO_NAME} · ${revoke}` : undefined} confirmLabel="해제" onCancel={() => setRevoke(null)}
        onConfirm={() => revoke && run.mutate(() => supabase.rpc('admin_revoke_role', { p_user: revoke }))} />
    </>
  )
}
