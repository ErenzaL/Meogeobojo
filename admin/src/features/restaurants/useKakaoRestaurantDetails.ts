import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { probeFunction } from './kakaoDiag'
import { createLimiter, lookupKakaoPlace, type CampusCtx, type KakaoLive, type LookupFailKind, type LookupResult, type Searchers } from './kakaoLookup'
import { makeSupabaseSearch } from './kakaoScan'

/** Where to look: the restaurant's linked universities and, when it has them, its own stored coordinates. */
export type KakaoLocation = { campuses: CampusCtx[]; near?: { latitude: number; longitude: number } | null }

export type KakaoLiveStatus =
  | 'idle'        // no place id (a hand-made restaurant), or lookups are switched off
  | 'loading'
  | 'verified'    // a Kakao place with exactly this id was found
  | 'not_found'   // searched; no place with this id came back
  | 'no_context'  // no linked university and no coordinates: nowhere to search
  | 'error'       // Kakao / the function could not be reached (see errorKind)

export type KakaoRestaurantDetails = {
  place: KakaoLive | null
  status: KakaoLiveStatus
  isLoading: boolean
  isFetching: boolean
  errorKind: LookupFailKind | null
  errorMessage: string | null
  /** Why a not-found result may be only partial (the admin search function is not deployed). */
  adminSearchUnavailable: boolean
  /** When this session last got a verified answer from Kakao (ms since epoch), else null. */
  lastSuccessAt: number | null
  refresh: () => Promise<void>
}

/** One limiter for the whole page: a long list never has more than this many lookups in flight. */
const limit = createLimiter(3)
export const STALE_MS = 10 * 60_000

const env = import.meta.env as Record<string, string | undefined>
function defaultSearchers(): Searchers {
  const probe = () => (env.VITE_SUPABASE_URL && env.VITE_SUPABASE_ANON_KEY ? probeFunction(env.VITE_SUPABASE_URL, 'admin_kakao_search', env.VITE_SUPABASE_ANON_KEY) : Promise.resolve({ state: 'deployed' as const }))
  return {
    publicSearch: (body) => supabase.functions.invoke('search_restaurants', { body }),
    adminSearch: makeSupabaseSearch((name, o) => supabase.functions.invoke(name, o), probe),
  }
}

const locationKey = (l: KakaoLocation | null | undefined) =>
  l ? `${l.campuses.map((c) => `${c.id}:${c.radiusM}`).sort().join('|')}@${l.near ? `${l.near.latitude.toFixed(4)},${l.near.longitude.toFixed(4)}` : '-'}` : 'none'

/**
 * Live Kakao details for one restaurant: `useKakaoRestaurantDetails(kakaoPlaceId, restaurantName, location)`.
 *
 * - Verified by the Kakao place id only (see `lookupKakaoPlace`); a name match is never accepted.
 * - Cached per place id (and location) for 10 minutes, so the form, the list and a re-opened page share one lookup,
 *   and every lookup goes through one shared concurrency limiter.
 * - Read-only. The result lives in React Query's memory: it is not written to Supabase, to a form, to a draft or to storage.
 * - `refresh()` forces a new lookup. The result of a failed refresh replaces nothing the admin typed.
 */
export function useKakaoRestaurantDetails(
  kakaoPlaceId: string | null | undefined, restaurantName: string, location: KakaoLocation | null | undefined,
  options: { enabled?: boolean; searchers?: Searchers } = {},
): KakaoRestaurantDetails {
  const qc = useQueryClient()
  const placeId = kakaoPlaceId?.trim() || null
  const enabled = (options.enabled ?? true) && !!placeId && !!location
  const key = useMemo(() => ['kakao-live', placeId, locationKey(location)] as const, [placeId, location])
  const q = useQuery<LookupResult>({
    queryKey: key,
    enabled,
    staleTime: STALE_MS,
    gcTime: 30 * 60_000,
    retry: false,
    refetchOnWindowFocus: false,
    queryFn: ({ signal }) => limit(() => lookupKakaoPlace({ placeId: placeId!, name: restaurantName, campuses: location!.campuses, near: location!.near }, options.searchers ?? defaultSearchers(), signal)),
  })
  const refresh = useCallback(async () => { await qc.invalidateQueries({ queryKey: key, exact: true }) }, [qc, key])
  const r = q.data
  const status: KakaoLiveStatus = !placeId || (options.enabled === false) ? 'idle'
    : !location ? 'no_context'
    : q.isPending ? 'loading'
    : q.isError ? 'error'
    : r?.status ?? 'idle'
  return {
    place: r?.status === 'verified' ? r.place : null,
    status,
    isLoading: enabled && q.isPending,
    isFetching: q.isFetching,
    errorKind: r?.status === 'error' ? r.kind : q.isError ? 'unavailable' : null,
    errorMessage: r?.status === 'error' ? r.message : q.isError ? String((q.error as Error)?.message ?? 'error') : null,
    adminSearchUnavailable: r?.status === 'not_found' && r.adminSearch === 'unavailable',
    lastSuccessAt: r?.status === 'verified' ? q.dataUpdatedAt : null,
    refresh,
  }
}

/** The restaurant's own stored data a lookup needs: name, place id, coordinates and the linked universities' circles. */
export type KakaoSubject = { name: string; placeId: string | null; location: KakaoLocation }
export function useKakaoSubject(restaurantId: string) {
  return useQuery({
    queryKey: ['kakao-subject', restaurantId],
    staleTime: 60_000,
    queryFn: async (): Promise<KakaoSubject> => {
      const [r, links] = await Promise.all([
        supabase.from('restaurant_overrides').select('name_ko,kakao_place_id,latitude,longitude').eq('id', restaurantId).single(),
        supabase.from('restaurant_university_links').select('universities(id,latitude,longitude,search_radius_m)').eq('restaurant_id', restaurantId),
      ])
      const row = r.data as { name_ko: string; kakao_place_id: string | null; latitude: number | null; longitude: number | null } | null
      const campuses = campusesOf(((links.data ?? []) as unknown as { universities: UniRow | null }[]).map((l) => l.universities))
      return {
        name: row?.name_ko ?? '', placeId: row?.kakao_place_id ?? null,
        location: { campuses, near: row && row.latitude != null && row.longitude != null ? { latitude: row.latitude, longitude: row.longitude } : null },
      }
    },
  })
}

export type UniRow = { id: string; latitude: number | null; longitude: number | null; search_radius_m?: number | null }
export const DEFAULT_RADIUS_M = 1500
/** University rows -> the circles a lookup may search (rows without coordinates are skipped; a missing radius is the project default). */
export const campusesOf = (rows: (UniRow | null | undefined)[]): CampusCtx[] =>
  rows.flatMap((u) => (u && u.latitude != null && u.longitude != null ? [{ id: u.id, latitude: u.latitude, longitude: u.longitude, radiusM: u.search_radius_m ?? DEFAULT_RADIUS_M }] : []))
