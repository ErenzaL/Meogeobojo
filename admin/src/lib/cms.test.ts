import { describe, expect, it } from 'vitest'
import { diffSnapshots, formatKst, isConflict, isoToKst, kstToIso, showValue } from './cms'

describe('Asia/Seoul <-> UTC', () => {
  it('7 AM Seoul is 22:00 UTC the day before', () => {
    expect(kstToIso('2026-11-20', '07:00')).toBe('2026-11-19T22:00:00.000Z')
    expect(kstToIso('2026-11-20', '00:00')).toBe('2026-11-19T15:00:00.000Z')
    expect(kstToIso('2026-12-31', '23:59')).toBe('2026-12-31T14:59:00.000Z')
  })
  it('crosses month and year boundaries', () => {
    expect(kstToIso('2027-01-01', '08:00')).toBe('2026-12-31T23:00:00.000Z')
    expect(kstToIso('2026-03-01', '05:00')).toBe('2026-02-28T20:00:00.000Z')
  })
  it('round-trips', () => {
    for (const [d, t] of [['2026-11-20', '07:00'], ['2026-01-01', '00:00'], ['2026-06-30', '23:59']]) {
      expect(isoToKst(kstToIso(d, t))).toEqual({ date: d, time: t })
    }
  })
  it('shows Seoul time, not the browser time zone', () => {
    expect(formatKst('2026-11-19T22:00:00Z')).toBe('2026.11.20 07:00 (KST)')
    expect(formatKst(null)).toBe('—')
  })
  it('rejects malformed input', () => {
    expect(() => kstToIso('11/20/2026', '07:00')).toThrow()
    expect(() => kstToIso('2026-11-20', '7am')).toThrow()
    expect(() => kstToIso('2026-11-20', '24:00')).toThrow()
  })
})

describe('diffSnapshots', () => {
  const live = { name_ko: '옛 이름', description: null, price_min_krw: 8000, dining_purposes: ['혼밥'], featured: false, visibility: 'published', university_ids: ['u1'] }
  it('lists only what changed, with labels', () => {
    const d = diffSnapshots(live, { ...live, name_ko: '새 이름', price_min_krw: 9000, dining_purposes: ['혼밥', '회식'] })
    expect(d.map((c) => c.key)).toEqual(['name_ko', 'price_min_krw', 'dining_purposes'])
    expect(d[0]).toMatchObject({ label: '이름', from: '옛 이름', to: '새 이름' })
  })
  it('an empty string equals a missing value', () => {
    expect(diffSnapshots(live, { ...live, description: '' })).toEqual([])
  })
  it('nothing changed means no difference', () => expect(diffSnapshots(live, { ...live })).toEqual([]))
  it('detects campus link changes and visibility', () => {
    expect(diffSnapshots(live, { ...live, university_ids: ['u1', 'u2'], visibility: 'hidden' }).map((c) => c.key)).toEqual(['visibility', 'university_ids'])
  })
  it('renders values readably', () => {
    expect(showValue(null)).toBe('(비어 있음)'); expect(showValue(true)).toBe('예'); expect(showValue(['a', 'b'])).toBe('a, b'); expect(showValue([])).toBe('(없음)')
  })
})

describe('errors', () => {
  it('recognises the database conflict code', () => {
    expect(isConflict({ code: '40001', message: 'x' })).toBe(true)
    expect(isConflict({ code: '42501' })).toBe(false)
    expect(isConflict(new Error('x'))).toBe(false)
  })
})
