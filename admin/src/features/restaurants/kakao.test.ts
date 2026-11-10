import { describe, expect, it } from 'vitest'
import { chunk, collectKakaoPlaces, KAKAO_QUERIES, type Invoke } from './kakao'

const doc = (id: string, over: Record<string, unknown> = {}) => ({ id, place_name: `식당${id}`, category_group_code: 'FD6', distance: '100', x: '126.9', y: '36.7', ...over })
const campus = { latitude: 36.77, longitude: 126.93 }

describe('collectKakaoPlaces', () => {
  it('sends the campus coordinates with every keyword the app uses', async () => {
    const seen: unknown[] = []
    const invoke: Invoke = async (b) => { seen.push(b); return { data: { success: true, restaurants: [] }, error: null } }
    await collectKakaoPlaces(campus, invoke)
    expect(seen).toHaveLength(KAKAO_QUERIES.length)
    expect(seen[0]).toMatchObject({ latitude: 36.77, longitude: 126.93 })
    expect(KAKAO_QUERIES).toEqual(expect.arrayContaining(['한식', '카페', '치킨집', '아시아음식', '샐러드']))
  })

  it('merges by Kakao id, keeps food/cafe only and orders by distance', async () => {
    const invoke: Invoke = async ({ query }) => ({
      data: { success: true, restaurants: query === '한식'
        ? [doc('1', { distance: '300' }), doc('2', { distance: '50' }), doc('9', { category_group_code: 'CS2' })]
        : [doc('1', { distance: '300' }), doc('3', { category_group_code: 'CE7', distance: '120' })] }, error: null,
    })
    const { places, failed } = await collectKakaoPlaces(campus, invoke, undefined, ['한식', '카페'])
    expect(places.map((p) => p.id)).toEqual(['2', '3', '1'])
    expect(failed).toEqual([])
  })

  it('reports a failed keyword without losing the others, and counts progress', async () => {
    const progress: number[] = []
    const invoke: Invoke = async ({ query }) => query === '중식' ? { data: null, error: new Error('429') } : { data: { success: true, restaurants: [doc(query)] }, error: null }
    const { places, failed } = await collectKakaoPlaces(campus, invoke, (d) => progress.push(d), ['한식', '중식', '일식'])
    expect(failed).toEqual(['중식'])
    expect(places).toHaveLength(2)
    expect(progress.at(-1)).toBe(3)
  })

  it('treats success:false as a failure', async () => {
    const { places, failed } = await collectKakaoPlaces(campus, async () => ({ data: { success: false }, error: null }), undefined, ['한식'])
    expect(places).toEqual([]); expect(failed).toEqual(['한식'])
  })
})

describe('chunk', () => {
  it('splits into batches', () => expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]))
  it('handles empty', () => expect(chunk([], 3)).toEqual([]))
})
