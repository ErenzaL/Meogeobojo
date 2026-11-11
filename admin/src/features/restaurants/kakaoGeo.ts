/**
 * Geometry for the Kakao scan. Everything is metres. The same haversine (Earth radius 6371008.8 m) runs in the
 * Edge Function (`supabase/functions/admin_kakao_search/core.ts`); a test pins the two together.
 */
export const EARTH_RADIUS_M = 6371008.8
const rad = (d: number) => (d * Math.PI) / 180
const deg = (r: number) => (r * 180) / Math.PI

/** Great-circle distance between two WGS84 points. */
export function haversineM(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const dLat = rad(bLat - aLat)
  const dLng = rad(bLng - aLng)
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(aLat)) * Math.cos(rad(bLat)) * Math.sin(dLng / 2) ** 2
  return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)))
}

export type Campus = { id: string; name: string; latitude: number; longitude: number; radiusM: number }

/**
 * A square of the search grid, in metres east (dx) / north (dy) of the campus centre. `half` is half its side.
 * Kakao is asked for the circle that circumscribes the square (centre + radius are the documented, unambiguous
 * parameters; `rect` is not used), so the squares tile the area with no gaps; neighbouring circles overlap, which
 * deduplication by place id absorbs.
 */
export type Cell = { dx: number; dy: number; half: number; depth: number }

/** The square that bounds the campus circle. */
export const rootCell = (c: Campus): Cell => ({ dx: 0, dy: 0, half: c.radiusM, depth: 0 })

/** The four quarters of a square. */
export const childCells = (c: Cell): Cell[] => {
  const h = c.half / 2
  return [
    { dx: c.dx - h, dy: c.dy + h, half: h, depth: c.depth + 1 },
    { dx: c.dx + h, dy: c.dy + h, half: h, depth: c.depth + 1 },
    { dx: c.dx - h, dy: c.dy - h, half: h, depth: c.depth + 1 },
    { dx: c.dx + h, dy: c.dy - h, half: h, depth: c.depth + 1 },
  ]
}

/** A square can hold a place inside the campus circle only if its nearest point is within the radius. */
export function cellTouchesCampus(c: Cell, campus: Campus): boolean {
  const nx = Math.max(Math.abs(c.dx) - c.half, 0)
  const ny = Math.max(Math.abs(c.dy) - c.half, 0)
  return Math.hypot(nx, ny) <= campus.radiusM
}

/** Where the cell's centre is on the globe. */
export function cellCentre(c: Cell, campus: Campus): { lat: number; lng: number } {
  const lat = campus.latitude + deg(c.dy / EARTH_RADIUS_M)
  const lng = campus.longitude + deg(c.dx / (EARTH_RADIUS_M * Math.cos(rad(campus.latitude))))
  return { lat, lng }
}

/**
 * Radius of the circle that covers the whole square: half the diagonal, plus 1 % + 1 m so the flat-earth
 * conversion above can never leave a sliver uncovered.
 */
export const cellRadiusM = (c: Cell): number => Math.ceil(c.half * Math.SQRT2 * 1.01) + 1

/** Distance of a Kakao place (x = longitude, y = latitude, as text) from the campus centre, or null if unusable. */
export function placeDistanceM(d: { x?: string; y?: string }, campus: Campus): number | null {
  const lng = Number(d.x)
  const lat = Number(d.y)
  if (d.x == null || d.y == null || d.x === '' || d.y === '' || !Number.isFinite(lat) || !Number.isFinite(lng)) return null
  if (lat < 33 || lat > 39 || lng < 124 || lng > 132) return null
  return haversineM(campus.latitude, campus.longitude, lat, lng)
}
