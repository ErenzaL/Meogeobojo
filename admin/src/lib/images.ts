/** Image helpers shared by the photo, menu and cafeteria screens. */
export const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp']
/** The Storage bucket refuses anything larger than this. */
export const MAX_IMAGE_BYTES = 5 * 1024 * 1024
/** A phone photo can be bigger than the bucket limit: it is resized before upload. */
export const MAX_SOURCE_BYTES = 25 * 1024 * 1024
export const BUCKET = 'restaurant-images'
const MAX_SIDE = 1600
const KEEP_AS_IS_BYTES = 1024 * 1024

/** Client-side pre-check; the bucket enforces the same limits. */
export const validateImageFile = (f: { type: string; size: number }): string | null =>
  !ALLOWED_IMAGE_TYPES.includes(f.type) ? 'JPG, PNG, WEBP 이미지만 올릴 수 있어요' : f.size > MAX_IMAGE_BYTES ? '이미지는 5MB 이하여야 해요' : null

/** Scale (w, h) down so the longer side is at most [max]; never scales up. */
export function fitWithin(w: number, h: number, max = MAX_SIDE) {
  const longest = Math.max(w, h)
  if (longest <= max) return { width: w, height: h }
  const k = max / longest
  return { width: Math.round(w * k), height: Math.round(h * k) }
}

/** "restaurants/<id>/<random>.webp": unique, so a replaced photo never reuses a cached URL. */
export const imagePath = (prefix: string, mime: string) => `${prefix}/${crypto.randomUUID()}.${mime === 'image/jpeg' ? 'jpg' : mime.split('/')[1]}`

/** The bucket path inside one of OUR public URLs, or null for any other link. */
export function storagePathFromUrl(url: string | null | undefined): string | null {
  const m = url?.match(new RegExp(`/storage/v1/object/public/${BUCKET}/(.+?)(?:\\?.*)?$`))
  return m ? decodeURIComponent(m[1]) : null
}

export type PreparedImage = { blob: Blob; type: string; width: number; height: number; bytes: number }

/**
 * Validates, then downsizes a large photo (longest side 1600px, WebP) so
 * uploads are fast and fit the bucket limit. Small files are kept untouched,
 * so a good image is never re-compressed for nothing.
 */
export async function prepareImage(file: File): Promise<PreparedImage> {
  if (!ALLOWED_IMAGE_TYPES.includes(file.type)) throw new Error('JPG, PNG, WEBP 이미지만 올릴 수 있어요')
  if (file.size > MAX_SOURCE_BYTES) throw new Error('이미지는 25MB 이하여야 해요')
  const bmp = await createImageBitmap(file)
  const { width, height } = fitWithin(bmp.width, bmp.height)
  const resized = width !== bmp.width || height !== bmp.height
  if (!resized && file.size <= KEEP_AS_IS_BYTES) {
    bmp.close()
    return { blob: file, type: file.type, width, height, bytes: file.size }
  }
  const canvas = document.createElement('canvas')
  canvas.width = width; canvas.height = height
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('이미지를 처리할 수 없어요')
  ctx.drawImage(bmp, 0, 0, width, height)
  bmp.close()
  const encode = (type: string, q: number) => new Promise<Blob | null>((res) => canvas.toBlob(res, type, q))
  const blob = (await encode('image/webp', 0.85)) ?? (await encode('image/jpeg', 0.88))
  if (!blob) throw new Error('이미지를 처리할 수 없어요')
  if (blob.size > MAX_IMAGE_BYTES) throw new Error('이미지가 너무 커요. 더 작은 사진을 써 주세요')
  return { blob, type: blob.type, width, height, bytes: blob.size }
}
