import { describe, expect, it } from 'vitest'
import { fitWithin, imagePath, storagePathFromUrl, validateImageFile } from './images'

describe('image helpers', () => {
  it('shrinks large images to a 1600px longest side and never scales up', () => {
    expect(fitWithin(4000, 3000)).toEqual({ width: 1600, height: 1200 })
    expect(fitWithin(3000, 4000)).toEqual({ width: 1200, height: 1600 })
    expect(fitWithin(800, 600)).toEqual({ width: 800, height: 600 })
    expect(fitWithin(1600, 1600)).toEqual({ width: 1600, height: 1600 })
  })
  it('validates type and size', () => {
    expect(validateImageFile({ type: 'image/webp', size: 10 })).toBeNull()
    expect(validateImageFile({ type: 'application/pdf', size: 10 })).toBeTruthy()
    expect(validateImageFile({ type: 'image/png', size: 6 * 1024 * 1024 })).toBeTruthy()
  })
  it('builds unique paths so a replaced photo never reuses a cached URL', () => {
    const a = imagePath('restaurants/r1', 'image/jpeg'); const b = imagePath('restaurants/r1', 'image/jpeg')
    expect(a).toMatch(/^restaurants\/r1\/[0-9a-f-]{36}\.jpg$/)
    expect(a).not.toBe(b)
    expect(imagePath('menus/x', 'image/webp')).toMatch(/\.webp$/)
  })
  it('recognises only our own storage URLs', () => {
    expect(storagePathFromUrl('https://p.supabase.co/storage/v1/object/public/restaurant-images/menus/r/a%20b.jpg?t=1')).toBe('menus/r/a b.jpg')
    expect(storagePathFromUrl('https://example.org/photo.jpg')).toBeNull()
    expect(storagePathFromUrl(null)).toBeNull()
  })
})
