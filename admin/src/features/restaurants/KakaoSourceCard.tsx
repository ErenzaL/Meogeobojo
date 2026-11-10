import { useQuery } from '@tanstack/react-query'
import { Card, Skeleton } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import type { KakaoDoc } from './kakao'

type Place = { name: string; kakao: string | null; campus: { latitude: number; longitude: number } | null }

/**
 * What Kakao says about this place RIGHT NOW. Fetched live through the app's
 * `search_restaurants` function around the linked campus and shown read-only.
 * It is never saved (Kakao restricts caching of its place data); only the ID
 * and the admin-edited fields below are stored.
 */
export default function KakaoSourceCard({ id }: { id: string }) {
  const place = useQuery({
    queryKey: ['kakao-place', id],
    queryFn: async (): Promise<Place | null> => {
      const [r, links] = await Promise.all([
        supabase.from('restaurant_overrides').select('name_ko,kakao_place_id').eq('id', id).single(),
        supabase.from('restaurant_university_links').select('universities(latitude,longitude)').eq('restaurant_id', id),
      ])
      const row = r.data as { name_ko: string; kakao_place_id: string | null } | null
      if (!row?.kakao_place_id) return null
      const u = ((links.data ?? []) as unknown as { universities: { latitude: number | null; longitude: number | null } | null }[])
        .map((l) => l.universities).find((x) => x && x.latitude != null && x.longitude != null)
      return { name: row.name_ko, kakao: row.kakao_place_id, campus: u ? { latitude: u.latitude!, longitude: u.longitude! } : null }
    },
  })
  const p = place.data
  const live = useQuery({
    queryKey: ['kakao-live', p?.kakao, p?.campus?.latitude],
    enabled: !!p?.kakao && !!p.campus,
    staleTime: 5 * 60_000,
    queryFn: async (): Promise<KakaoDoc | null> => {
      const { data } = await supabase.functions.invoke('search_restaurants', { body: { query: p!.name, latitude: p!.campus!.latitude, longitude: p!.campus!.longitude } })
      const docs = ((data as { restaurants?: KakaoDoc[] } | null)?.restaurants ?? [])
      return docs.find((d) => String(d.id) === p!.kakao) ?? null
    },
  })
  if (!p?.kakao) return null
  const d = live.data
  const rows: [string, string | undefined][] = d ? [
    ['이름', d.place_name], ['카테고리', d.category_name], ['도로명 주소', d.road_address_name], ['지번 주소', d.address_name],
    ['전화', d.phone], ['위도 / 경도', d.y && d.x ? `${d.y} / ${d.x}` : undefined],
  ] : []
  return (
    <Card aria-label="카카오 실시간 정보" className="space-y-2">
      <h2 className="font-bold">카카오 실시간 정보 <span className="text-sm font-normal text-muted">읽기 전용 · 저장하지 않아요</span></h2>
      {!p.campus && <p className="text-sm text-muted">연결된 대학교가 없어 카카오에서 찾을 수 없어요. 대학교를 연결하면 이 정보를 불러와요.</p>}
      {p.campus && live.isLoading && <Skeleton className="h-16 w-full" />}
      {p.campus && !live.isLoading && !d && <p className="text-sm text-muted">카카오에서 이 장소를 지금 찾지 못했어요. 이름을 바꿨거나 캠퍼스에서 멀 수 있어요.</p>}
      {d && (
        <dl className="grid gap-x-4 gap-y-1 text-sm sm:grid-cols-[8rem_1fr]">
          {rows.filter(([, v]) => v).map(([k, v]) => <div key={k} className="contents"><dt className="text-muted">{k}</dt><dd>{v}</dd></div>)}
          {d.place_url && <div className="contents"><dt className="text-muted">카카오맵</dt><dd><a className="text-brand-strong underline" href={d.place_url.replace(/^http:/, 'https:')} target="_blank" rel="noreferrer">장소 페이지</a></dd></div>}
        </dl>)}
      <p className="text-xs text-muted">아래 입력칸은 우리가 관리하는 값이에요. 앱에서는 공개된 식당의 여기 값이 카카오 원본보다 우선해요.</p>
    </Card>
  )
}
