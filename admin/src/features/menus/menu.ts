import type { MenuItem } from '@/lib/cms'

export const MENU_CATEGORIES = ['식사', '면류', '분식', '안주', '사이드', '음료', '디저트', '기타']
export type MenuDraft = { name: string; price: string; description: string; category: string; verified: string }
export const emptyMenuDraft: MenuDraft = { name: '', price: '', description: '', category: '', verified: '' }

/** Pure form check: unknown prices stay unknown (empty = null), never 0. */
export function validateMenu(d: MenuDraft): { error: string | null; price: number | null } {
  if (!d.name.trim()) return { error: '메뉴 이름을 입력해 주세요', price: null }
  const price = d.price.trim() === '' ? null : Number(d.price.replace(/[,\s]/g, ''))
  if (price != null && (!Number.isInteger(price) || price < 0)) return { error: '가격은 0 이상의 정수여야 해요', price: null }
  if (d.verified && !/^\d{4}-\d{2}-\d{2}$/.test(d.verified)) return { error: '가격 확인일 형식이 올바르지 않아요', price: null }
  if (d.verified && price == null) return { error: '가격이 없으면 확인일을 적을 수 없어요', price: null }
  return { error: null, price }
}

/** The order the database uses (sort_order, then id), so an unchanged list compares equal to live. */
export const sortItems = (xs: MenuItem[]) => [...xs].sort((a, b) => a.sort_order - b.sort_order || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))

/** The form's values as a menu line (id and sort order are kept for an existing line). */
export function itemFromDraft(d: MenuDraft, price: number | null, base: Partial<MenuItem> & { id: string; sort_order: number }): MenuItem {
  return {
    available: true, representative: false, recommended: false, status: 'active', image_url: null, ...base,
    name_ko: d.name.trim(), description_ko: d.description.trim() || null, price_krw: price, category: d.category || null,
    price_verified_on: price == null ? null : d.verified || null,
  }
}
export const draftFromItem = (m: MenuItem): MenuDraft => ({
  name: m.name_ko, price: m.price_krw == null ? '' : String(m.price_krw), description: m.description_ko ?? '', category: m.category ?? '', verified: m.price_verified_on ?? '',
})
