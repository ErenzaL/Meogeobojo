import type { PhotoItem } from '@/lib/cms'

/** The order the database uses (sort_order, then id), so an unchanged list compares equal to live. */
export const sortPhotos = (xs: PhotoItem[]) => [...xs].sort((a, b) => a.sort_order - b.sort_order || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))

/** What the student app shows for a restaurant, in order: the live cover, then live gallery photos. */
export const shownInApp = (photos: PhotoItem[]) => ({
  cover: photos.find((p) => p.kind === 'cover' && p.status === 'published') ?? null,
  gallery: sortPhotos(photos.filter((p) => p.kind === 'gallery' && p.status === 'published')),
})
