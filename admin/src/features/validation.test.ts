import { describe, expect, it } from 'vitest'
import { THOUSAND_WON_BADGE, parseItems, validateMeal, type MealForm } from './CafeteriaPage'
import { MAX_IMAGE_BYTES, validateImageFile } from './MenusPage'
import { validateUniversity } from './UniversitiesPage'

const meal: MealForm = { date: '2026-11-10', type: 'breakfast', option: '', items: '북엇국\n시금치나물', price: '1000', start: '08:00', end: '09:30', badge: THOUSAND_WON_BADGE, status: 'published', source: '', notice: '' }

describe('cafeteria meals', () => {
  it('first line is the main dish', () => expect(parseItems('북엇국\n\n 시금치나물 ')).toEqual([{ name_ko: '북엇국', kind: 'main' }, { name_ko: '시금치나물', kind: 'side' }]))
  it('accepts a 천원의 아침밥 entry', () => expect(validateMeal(meal)).toEqual({}))
  it('published needs at least one item (matches the DB check)', () => expect(validateMeal({ ...meal, items: '  ' }).items).toBeTruthy())
  it('closed rows need no items', () => expect(validateMeal({ ...meal, items: '', status: 'closed' })).toEqual({}))
  it('rejects bad price, times, order and non-https source', () => {
    const e = validateMeal({ ...meal, price: '-1', start: '10:00', end: '09:00', source: 'http://x' })
    expect(Object.keys(e).sort()).toEqual(['end', 'price', 'source'])
  })
})

describe('universities', () => {
  const ok = { name_ko: '순천향대학교', latitude: '36.77', longitude: '126.93', radius: '1500' }
  it('accepts valid campus data', () => expect(validateUniversity(ok)).toEqual({}))
  it('validates coordinates and radius', () => {
    const e = validateUniversity({ name_ko: '', latitude: '91', longitude: '', radius: '50' })
    expect(Object.keys(e).sort()).toEqual(['latitude', 'longitude', 'name_ko', 'radius'])
  })
})

describe('menu photos', () => {
  it('allows jpg/png/webp up to 5MB only', () => {
    expect(validateImageFile({ type: 'image/png', size: 1000 })).toBeNull()
    expect(validateImageFile({ type: 'image/gif', size: 1000 })).toBeTruthy()
    expect(validateImageFile({ type: 'image/jpeg', size: MAX_IMAGE_BYTES + 1 })).toBeTruthy()
  })
})
