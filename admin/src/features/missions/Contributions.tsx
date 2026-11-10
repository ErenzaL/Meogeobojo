import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Badge, Button, Card, ConfirmDialog, EmptyState, ErrorState, Skeleton } from '@/components/ui'
import { ALLOWED_IMAGE_TYPES, BUCKET, imagePath, MAX_IMAGE_BYTES } from '@/lib/images'
import { supabase } from '@/lib/supabase'
import { errorMessage, formatDateTime } from '@/lib/utils'

export const PRIVATE_BUCKET = 'contribution-photos'
type Kind = 'menu_photo' | 'restaurant_photo' | 'info_correction'
type Contribution = { id: string; user_id: string; kind: Kind; kakao_place_id: string; payload: { path?: string; caption?: string; consent?: boolean } & Record<string, unknown>; status: string; created_at: string; reviewed_at?: string | null; review_note?: string | null }
const KIND_LABEL: Record<Kind, string> = { menu_photo: '메뉴 사진', restaurant_photo: '식당 사진', info_correction: '정보 수정' }
const isPhoto = (c: Contribution) => c.kind !== 'info_correction' && !!c.payload.path
const STATUS_LABEL: Record<string, string> = { pending: '검토 대기', approved: '승인', rejected: '반려' }

/** Review students' photos and corrections. A photo sits in a PRIVATE bucket; it
 *  is shown here through a short-lived signed link. Approving can also publish it
 *  to the restaurant's gallery (a copy in the public bucket, credited as a student
 *  photo); either way the contributor's mission progress updates in the database. */
export default function Contributions() {
  const qc = useQueryClient()
  const [notice, setNotice] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null)
  const [reject, setReject] = useState<Contribution | null>(null)
  const [history, setHistory] = useState(false)

  const q = useQuery({
    queryKey: ['contributions-pending'],
    queryFn: async () => {
      const { data, error } = await supabase.from('user_contributions').select('*').eq('status', 'pending').order('created_at')
      if (error) throw error
      return data as Contribution[]
    },
  })
  const past = useQuery({
    queryKey: ['contributions-history'], enabled: history,
    queryFn: async () => {
      const { data, error } = await supabase.from('user_contributions').select('*').neq('status', 'pending').order('reviewed_at', { ascending: false }).limit(30)
      if (error) throw error
      return data as Contribution[]
    },
  })
  const rows = q.data ?? []
  const ids = [...new Set(rows.map((c) => c.kakao_place_id))]
  // Which of these places are managed (so a photo can be published to a gallery).
  const places = useQuery({
    queryKey: ['contribution-places', ids.join(',')], enabled: ids.length > 0,
    queryFn: async () => {
      const { data, error } = await supabase.from('restaurant_overrides').select('id,name_ko,kakao_place_id').in('kakao_place_id', ids)
      if (error) throw error
      return Object.fromEntries((data as { id: string; name_ko: string; kakao_place_id: string }[]).map((r) => [r.kakao_place_id, r]))
    },
  })
  const signed = useQuery({
    queryKey: ['contribution-signed', rows.filter(isPhoto).map((c) => c.id).join(',')], enabled: rows.some(isPhoto), staleTime: 4 * 60_000,
    queryFn: async () => {
      const out: Record<string, string> = {}
      for (const c of rows.filter(isPhoto)) {
        const r = await supabase.storage.from(PRIVATE_BUCKET).createSignedUrl(c.payload.path!, 600)
        if (r.data?.signedUrl) out[c.id] = r.data.signedUrl
      }
      return out
    },
  })

  const done = async (text: string) => {
    setNotice({ tone: 'ok', text })
    await qc.invalidateQueries({ queryKey: ['contributions-pending'] })
    await qc.invalidateQueries({ queryKey: ['contributions-history'] })
  }
  const dropPrivate = async (c: Contribution) => { if (isPhoto(c)) await supabase.storage.from(PRIVATE_BUCKET).remove([c.payload.path!]) }

  const review = useMutation({
    mutationFn: async ({ c, status, note }: { c: Contribution; status: 'approved' | 'rejected'; note: string }) => {
      const { error } = await supabase.rpc('admin_review_contribution', { p_id: c.id, p_status: status, p_note: note || null })
      if (error) throw error
      if (status === 'rejected') await dropPrivate(c) // a rejected photo is not kept
    },
    onSuccess: async (_d, v) => { setReject(null); await done(v.status === 'approved' ? '승인했어요. 사용자의 미션 진행도에 바로 반영돼요.' : '반려했어요. 사유가 활동 기록에 남았어요.') },
    onError: (e) => { setReject(null); setNotice({ tone: 'bad', text: errorMessage(e) }) },
  })

  /** Publish a student photo to the restaurant's gallery, then approve it. If the
   *  approval fails, the gallery copy is rolled back so nothing is left half done. */
  const promote = useMutation({
    mutationFn: async (c: Contribution) => {
      const place = places.data?.[c.kakao_place_id]
      if (!place) throw new Error('이 식당은 아직 관리 목록에 없어요. 식당 → 카카오 식당 불러오기로 먼저 등록해 주세요.')
      const url = signed.data?.[c.id]
      if (!url) throw new Error('사진을 불러오지 못했어요. 새로고침 후 다시 시도해 주세요.')
      const res = await fetch(url)
      if (!res.ok) throw new Error('사진을 내려받지 못했어요.')
      const blob = await res.blob()
      if (!ALLOWED_IMAGE_TYPES.includes(blob.type)) throw new Error('JPG, PNG, WEBP 사진만 게시할 수 있어요.')
      if (blob.size > MAX_IMAGE_BYTES) throw new Error('사진이 5MB를 넘어요.')
      const last = await supabase.from('restaurant_photos').select('sort_order').eq('restaurant_id', place.id).order('sort_order', { ascending: false }).limit(1)
      if (last.error) throw last.error
      const order = ((last.data as { sort_order: number }[] | null)?.[0]?.sort_order ?? 0) + 1
      const path = imagePath(`restaurants/${place.id}`, blob.type)
      const up = await supabase.storage.from(BUCKET).upload(path, blob, { contentType: blob.type })
      if (up.error) throw up.error
      const publicUrl = supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl
      const ins = await supabase.from('restaurant_photos').insert({
        restaurant_id: place.id, kind: 'gallery', storage_path: path, url: publicUrl, caption: c.payload.caption || null,
        sort_order: order, source: 'student', credit: '학생 제공', bytes: blob.size,
      })
      if (ins.error) { await supabase.storage.from(BUCKET).remove([path]); throw ins.error }
      const rv = await supabase.rpc('admin_review_contribution', { p_id: c.id, p_status: 'approved', p_note: '갤러리에 게시' })
      if (rv.error) {
        await supabase.from('restaurant_photos').delete().eq('storage_path', path)
        await supabase.storage.from(BUCKET).remove([path])
        throw rv.error
      }
      await dropPrivate(c) // the public copy is the only one now
    },
    onSuccess: async () => { await done('갤러리에 게시하고 승인했어요. 앱 식당 상세에 바로 보여요.') },
    onError: (e) => setNotice({ tone: 'bad', text: errorMessage(e) }),
  })

  if (q.isLoading) return <Skeleton className="h-32 w-full" />
  if (q.error) return <ErrorState error={q.error} onRetry={() => void q.refetch()} />
  const busy = review.isPending || promote.isPending
  return (
    <>
      {notice && <p role={notice.tone === 'bad' ? 'alert' : 'status'} className={`mb-4 rounded-xl p-3 text-sm ${notice.tone === 'bad' ? 'bg-amber-50 text-amber-900' : 'bg-brand/30'}`}>{notice.text}</p>}
      {rows.length === 0 && <EmptyState>검토할 기여가 없어요.</EmptyState>}
      <div className="space-y-3">
        {rows.map((c) => {
          const place = places.data?.[c.kakao_place_id]
          return (
            <Card key={c.id} className="flex flex-wrap items-start justify-between gap-3">
              <div className="flex min-w-0 gap-3">
                {isPhoto(c) && (signed.data?.[c.id]
                  ? <img src={signed.data[c.id]} alt={`${KIND_LABEL[c.kind]} 제출 사진`} className="size-24 rounded-xl object-cover" />
                  : <span className="grid size-24 place-items-center rounded-xl bg-page text-xs text-muted">{signed.isLoading ? '불러오는 중' : '사진 없음'}</span>)}
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2 font-semibold"><Badge tone="brand">{KIND_LABEL[c.kind]}</Badge>{place?.name_ko ?? `식당 ${c.kakao_place_id}`}{!place && <Badge tone="amber">관리 목록에 없음</Badge>}</div>
                  <div className="text-xs text-muted">{formatDateTime(c.created_at)} · 사용자 {c.user_id}</div>
                  {c.payload.caption && <p className="mt-1 text-sm">{c.payload.caption}</p>}
                  {isPhoto(c) && <p className="text-xs text-muted">{c.payload.consent ? '게시 동의함' : '게시 동의 없음'}</p>}
                  {!isPhoto(c) && <pre className="mt-1 max-w-xl overflow-x-auto rounded-lg bg-page p-2 text-xs">{JSON.stringify(c.payload, null, 1)}</pre>}
                </div>
              </div>
              <div className="flex flex-wrap gap-2">
                {isPhoto(c) && <Button size="sm" disabled={busy || !place} title={place ? undefined : '식당을 먼저 관리 목록에 등록해야 해요'} onClick={() => promote.mutate(c)}>갤러리에 올리고 승인</Button>}
                <Button size="sm" variant={isPhoto(c) ? 'outline' : 'primary'} disabled={busy} onClick={() => review.mutate({ c, status: 'approved', note: '' })}>{isPhoto(c) ? '승인만 (미션 반영)' : '승인'}</Button>
                <Button size="sm" variant="outline" disabled={busy} onClick={() => setReject(c)}>반려</Button>
              </div>
            </Card>)
        })}
      </div>
      <div className="mt-6">
        <Button variant="ghost" size="sm" onClick={() => setHistory((h) => !h)}>{history ? '처리 내역 숨기기' : '최근 처리 내역 보기'}</Button>
        {history && (
          <div className="mt-2 space-y-2" aria-label="처리 내역">
            {past.isLoading && <Skeleton className="h-12 w-full" />}
            {past.error && <ErrorState error={past.error} onRetry={() => void past.refetch()} />}
            {past.data?.length === 0 && <EmptyState>처리한 기여가 아직 없어요.</EmptyState>}
            {past.data?.map((c) => (
              <div key={c.id} className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-line bg-white px-3 py-2 text-sm">
                <span>{KIND_LABEL[c.kind]} · 식당 {c.kakao_place_id}</span>
                <span className="text-xs text-muted"><Badge tone={c.status === 'approved' ? 'green' : 'amber'}>{STATUS_LABEL[c.status] ?? c.status}</Badge> {formatDateTime(c.reviewed_at)}{c.review_note ? ` · ${c.review_note}` : ''}</span>
              </div>))}
          </div>)}
      </div>
      <ConfirmDialog open={!!reject} askReason danger busy={review.isPending} title="기여 반려" description="반려 사유는 활동 기록에 남고 사용자에게 보여요. 반려된 사진은 삭제돼요."
        confirmLabel="반려" onCancel={() => setReject(null)} onConfirm={(note) => reject && review.mutate({ c: reject, status: 'rejected', note })} />
    </>
  )
}
