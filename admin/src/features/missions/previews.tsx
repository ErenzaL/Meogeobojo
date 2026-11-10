import { Check, Trophy } from 'lucide-react'
import { Card } from '@/components/ui'
import { MASCOT_LABEL, mascotSrc, type Campaign, type MascotKey } from './model'
import { isoToSeoulDate, isoToSeoulLastDay } from './schema'

/** How the campaign banner will look in the Flutter app. */
export function BannerPreview({ title, subtitle, color, mascot, startIso, endIso }: { title: string; subtitle?: string; color: string; mascot: string; startIso?: string; endIso?: string }) {
  const period = startIso && endIso ? `${isoToSeoulDate(startIso).replaceAll('-', '.')} – ${isoToSeoulLastDay(endIso).replaceAll('-', '.')}` : ''
  return (
    <div data-testid="banner-preview" className="flex items-center gap-3 rounded-3xl border p-5" style={{ borderColor: `${color}47`, background: `linear-gradient(135deg, ${color}29, ${color}0d)` }}>
      <div className="min-w-0 flex-1">
        <div className="truncate text-2xl font-extrabold">{title || '캠페인 이름'}</div>
        {subtitle && <div className="mt-1 text-sm">{subtitle}</div>}
        {period && <span className="mt-3 inline-block rounded-full bg-white/85 px-2.5 py-1 text-xs font-semibold text-muted">{period}</span>}
      </div>
      <img src={mascotSrc(mascot)} alt={MASCOT_LABEL[mascot as MascotKey] ?? mascot} className="size-24 object-contain" />
    </div>
  )
}

/** How a mission card will look in the app (progress shown as 0 / target). */
export function MissionPreview({ title, description, points, target, badge, badgeMascot }: { title: string; description?: string; points: number; target: number; badge?: boolean; badgeMascot?: string }) {
  return (
    <Card data-testid="mission-preview" className="flex items-start gap-3 !p-4">
      {badge
        ? <img src={mascotSrc(badgeMascot || 'cheer')} alt="" className="size-12 rounded-full border bg-page object-contain opacity-60 grayscale" />
        : <div className="grid size-12 shrink-0 place-items-center rounded-2xl bg-brand/40"><Trophy className="size-5" /></div>}
      <div className="min-w-0 flex-1">
        <div className="font-semibold">{title || '미션 제목'}</div>
        {description && <div className="mt-0.5 line-clamp-2 text-xs text-muted">{description}</div>}
        <div className="mt-2 flex items-center gap-2">
          <div className="h-1.5 flex-1 rounded-full bg-page"><div className="h-full w-0 rounded-full bg-brand-strong" /></div>
          <span className="text-xs font-semibold text-muted">0/{target || 1}</span>
        </div>
      </div>
      <span className="rounded-lg bg-brand/40 px-2 py-1 text-xs font-bold">{badge ? '한정 뱃지' : `+${points}P`}</span>
    </Card>
  )
}

export const DoneMark = () => <span className="inline-flex items-center gap-1 text-xs font-semibold text-green-700"><Check className="size-3.5" />완료</span>

export const campaignLabel = (c: Pick<Campaign, 'title' | 'slug'>) => `${c.title} (${c.slug})`
