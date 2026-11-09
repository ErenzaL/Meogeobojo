import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Badge, Button, Card, EmptyState, ErrorState, Field, Input, PageHeader, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'

type Uni = { id: string; name_ko: string; name_en: string | null; city: string | null; address: string | null; latitude: number | null; longitude: number | null; is_active: boolean; search_radius_m: number }

/** Validates campus coordinates and radius (also enforced by CHECK constraints). */
export function validateUniversity(v: { name_ko: string; latitude: string; longitude: string; radius: string }): Record<string, string> {
  const e: Record<string, string> = {}
  if (!v.name_ko.trim()) e.name_ko = '이름을 입력해 주세요'
  const lat = Number(v.latitude), lng = Number(v.longitude), r = Number(v.radius)
  if (v.latitude === '' || Number.isNaN(lat) || lat < -90 || lat > 90) e.latitude = '위도는 -90 ~ 90 사이여야 해요'
  if (v.longitude === '' || Number.isNaN(lng) || lng < -180 || lng > 180) e.longitude = '경도는 -180 ~ 180 사이여야 해요'
  if (!Number.isInteger(r) || r < 100 || r > 5000) e.radius = '검색 반경은 100 ~ 5000 m 사이여야 해요'
  return e
}

export default function UniversitiesPage() {
  const qc = useQueryClient()
  const list = useQuery({
    queryKey: ['universities-admin'],
    queryFn: async () => {
      const { data, error } = await supabase.from('universities').select('*').order('name_ko')
      if (error) throw error
      return data as Uni[]
    },
  })
  const [editing, setEditing] = useState<Uni | null>(null)
  const [form, setForm] = useState({ name_ko: '', name_en: '', address: '', latitude: '', longitude: '', radius: '1500', is_active: true })
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [notice, setNotice] = useState<string | null>(null)

  const start = (u: Uni) => {
    setEditing(u); setErrors({}); setNotice(null)
    setForm({ name_ko: u.name_ko, name_en: u.name_en ?? '', address: u.address ?? '', latitude: String(u.latitude ?? ''), longitude: String(u.longitude ?? ''), radius: String(u.search_radius_m), is_active: u.is_active })
  }
  const save = useMutation({
    mutationFn: async () => {
      const e = validateUniversity(form); setErrors(e)
      if (Object.keys(e).length) throw new Error('입력값을 확인해 주세요')
      const { error } = await supabase.from('universities').update({
        name_ko: form.name_ko.trim(), name_en: form.name_en.trim() || null, address: form.address.trim() || null,
        latitude: Number(form.latitude), longitude: Number(form.longitude), search_radius_m: Number(form.radius), is_active: form.is_active,
      }).eq('id', editing!.id)
      if (error) throw error
    },
    onSuccess: async () => { setNotice('저장했어요.'); setEditing(null); await qc.invalidateQueries({ queryKey: ['universities-admin'] }); await qc.invalidateQueries({ queryKey: ['universities'] }) },
    onError: (e) => setNotice(errorMessage(e)),
  })

  if (list.isLoading) return <Skeleton className="h-64 w-full" />
  if (list.error) return <ErrorState error={list.error} onRetry={() => void list.refetch()} />
  return (
    <>
      <PageHeader title="대학교" description="캠퍼스 좌표, 식당 검색 반경, 활성 상태를 관리해요. 식당 연결은 식당 편집 화면에서 해요." />
      {notice && <p role="status" className="mb-4 rounded-xl bg-brand/30 p-3 text-sm">{notice}</p>}
      {list.data?.length === 0 && <EmptyState>등록된 대학교가 없어요.</EmptyState>}
      <div className="grid gap-4 lg:grid-cols-[1fr_22rem]">
        <div className="space-y-3">
          {list.data?.map((u) => (
            <Card key={u.id} className="flex items-center justify-between gap-3">
              <div>
                <div className="font-semibold">{u.name_ko} {!u.is_active && <Badge tone="amber">비활성</Badge>}</div>
                <div className="text-xs text-muted">{u.city ?? '—'} · {u.latitude?.toFixed(5)}, {u.longitude?.toFixed(5)} · 반경 {u.search_radius_m}m</div>
              </div>
              <Button size="sm" variant="outline" onClick={() => start(u)}>편집</Button>
            </Card>))}
        </div>
        {editing && (
          <Card className="space-y-3 self-start">
            <h2 className="font-bold">{editing.name_ko} 편집</h2>
            <Field label="이름" htmlFor="u_name" error={errors.name_ko}><Input id="u_name" value={form.name_ko} onChange={(e) => setForm({ ...form, name_ko: e.target.value })} /></Field>
            <Field label="영문 이름" htmlFor="u_en"><Input id="u_en" value={form.name_en} onChange={(e) => setForm({ ...form, name_en: e.target.value })} /></Field>
            <Field label="주소" htmlFor="u_addr"><Input id="u_addr" value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} /></Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="위도" htmlFor="u_lat" error={errors.latitude}><Input id="u_lat" value={form.latitude} onChange={(e) => setForm({ ...form, latitude: e.target.value })} /></Field>
              <Field label="경도" htmlFor="u_lng" error={errors.longitude}><Input id="u_lng" value={form.longitude} onChange={(e) => setForm({ ...form, longitude: e.target.value })} /></Field>
            </div>
            <Field label="검색 반경 (m)" htmlFor="u_r" error={errors.radius}><Input id="u_r" value={form.radius} onChange={(e) => setForm({ ...form, radius: e.target.value })} /></Field>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={form.is_active} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} />활성화 (앱에 표시)</label>
            <div className="flex gap-2"><Button disabled={save.isPending} onClick={() => save.mutate()}>저장</Button><Button variant="outline" onClick={() => setEditing(null)}>취소</Button></div>
          </Card>)}
      </div>
    </>
  )
}
