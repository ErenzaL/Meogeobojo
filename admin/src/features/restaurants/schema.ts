import { z } from 'zod'

export const VISIBILITIES = ['draft', 'published', 'hidden', 'archived'] as const
export type Visibility = (typeof VISIBILITIES)[number]
export const VISIBILITY_LABEL: Record<Visibility, string> = {
  draft: '초안', published: '공개', hidden: '숨김', archived: '보관',
}
export const BUSINESS_STATUSES = ['open', 'temporarily_closed', 'closed'] as const
export const BUSINESS_LABEL: Record<(typeof BUSINESS_STATUSES)[number], string> = {
  open: '영업 중', temporarily_closed: '임시 휴업', closed: '폐업',
}

const digits = z.string().trim().regex(/^\d*$/, '숫자만 입력해 주세요')
const coord = (min: number, max: number, label: string) =>
  z.string().trim().refine((v) => v === '' || (!Number.isNaN(Number(v)) && Number(v) >= min && Number(v) <= max), `${label} 범위가 올바르지 않아요`)

export const restaurantSchema = z
  .object({
    name_ko: z.string().trim().min(1, '이름을 입력해 주세요').max(120),
    name_en: z.string().trim().max(120),
    kakao_place_id: z.string().trim().max(40),
    category: z.string().trim().max(80),
    address: z.string().trim().max(200),
    phone: z.string().trim().max(30),
    latitude: coord(-90, 90, '위도'),
    longitude: coord(-180, 180, '경도'),
    description: z.string().trim().max(2000, '2000자 이하로 입력해 주세요'),
    break_time: z.string().trim().max(60),
    last_order_time: z.string().trim().refine((v) => v === '' || /^([01]\d|2[0-3]):[0-5]\d$/.test(v), 'HH:MM 형식으로 입력해 주세요'),
    business_status: z.enum(['', ...BUSINESS_STATUSES]),
    price_min_krw: digits,
    price_max_krw: digits,
    avg_cost_krw: digits,
    dining_purposes: z.string().trim(),
    image_url: z.string().trim().refine((v) => v === '' || /^https:\/\/\S+$/.test(v), 'https:// 로 시작하는 주소여야 해요'),
    visibility: z.enum(VISIBILITIES),
    featured: z.boolean(),
    display_order: digits,
    university_ids: z.array(z.string()),
  })
  .refine((v) => v.price_min_krw === '' || v.price_max_krw === '' || Number(v.price_min_krw) <= Number(v.price_max_krw), {
    path: ['price_max_krw'], message: '최고 가격은 최저 가격보다 크거나 같아야 해요',
  })

export type RestaurantForm = z.infer<typeof restaurantSchema>

export const emptyRestaurantForm: RestaurantForm = {
  name_ko: '', name_en: '', kakao_place_id: '', category: '', address: '', phone: '', latitude: '', longitude: '',
  description: '', break_time: '', last_order_time: '', business_status: '', price_min_krw: '', price_max_krw: '',
  avg_cost_krw: '', dining_purposes: '', image_url: '', visibility: 'draft', featured: false, display_order: '', university_ids: [],
}

const nul = (s: string) => (s.trim() === '' ? null : s.trim())
const num = (s: string) => (s.trim() === '' ? null : Number(s))

/** Form values -> the restaurant_overrides row (empty strings become NULL). */
export function toRow(v: RestaurantForm) {
  return {
    name_ko: v.name_ko, name_en: nul(v.name_en), kakao_place_id: nul(v.kakao_place_id), category: nul(v.category),
    address: nul(v.address), phone: nul(v.phone), latitude: num(v.latitude), longitude: num(v.longitude),
    description: nul(v.description), break_time: nul(v.break_time),
    last_order_time: nul(v.last_order_time), business_status: v.business_status === '' ? null : v.business_status,
    price_min_krw: num(v.price_min_krw), price_max_krw: num(v.price_max_krw), avg_cost_krw: num(v.avg_cost_krw),
    dining_purposes: v.dining_purposes.split(',').map((s) => s.trim()).filter(Boolean),
    image_url: nul(v.image_url), visibility: v.visibility,
    featured: v.featured, display_order: num(v.display_order),
  }
}

type DbRow = Record<string, unknown>
const str = (x: unknown) => (x == null ? '' : String(x))

/** A restaurant_overrides row -> form values. */
export function fromRow(r: DbRow, universityIds: string[]): RestaurantForm {
  return {
    name_ko: str(r.name_ko), name_en: str(r.name_en), kakao_place_id: str(r.kakao_place_id), category: str(r.category),
    address: str(r.address), phone: str(r.phone), latitude: str(r.latitude), longitude: str(r.longitude),
    description: str(r.description), break_time: str(r.break_time), last_order_time: str(r.last_order_time).slice(0, 5),
    business_status: (BUSINESS_STATUSES as readonly string[]).includes(str(r.business_status)) ? (str(r.business_status) as RestaurantForm['business_status']) : '',
    price_min_krw: str(r.price_min_krw), price_max_krw: str(r.price_max_krw), avg_cost_krw: str(r.avg_cost_krw),
    dining_purposes: Array.isArray(r.dining_purposes) ? (r.dining_purposes as string[]).join(', ') : '',
    image_url: str(r.image_url), visibility: (VISIBILITIES as readonly string[]).includes(str(r.visibility)) ? (str(r.visibility) as Visibility) : 'draft',
    featured: r.featured === true, display_order: str(r.display_order),
    university_ids: universityIds,
  }
}

/** The publishable content (a snapshot) from the form: the base snapshot with the
 *  form-managed fields on top. Fields the form does not edit (opening hours) are
 *  carried over, so publishing never wipes them. Identity (Kakao id) and the
 *  cover image are not part of a snapshot: the Kakao id never changes and the
 *  cover is published from 사진 관리. */
export function snapshotFromForm(v: RestaurantForm, base: Record<string, unknown>): Record<string, unknown> {
  const { kakao_place_id: _k, image_url: _i, ...row } = toRow(v)
  void _k; void _i
  return { ...base, ...row, university_ids: v.university_ids }
}
