import { Badge, Modal } from '@/components/ui'
import { diffSnapshots, showValue, type Snapshot } from '@/lib/cms'
import { MEAL_LABEL, type Extra, type MealForm } from './meal'

type Item = { name_ko: string; kind?: string }

/** The student-facing meal card built from the SAVED draft, and exactly what
 *  differs from what is published now. */
export default function MealPreview({ open, live, draft, meal, onClose }: { open: boolean; live: Snapshot; draft: Snapshot; meal: { meal_date: string; meal_type: MealForm['type']; option_name: string }; onClose: () => void }) {
  const changes = diffSnapshots(live, draft)
  const items = (draft.menu_items as Item[]) ?? []
  const extra = (draft.extra as Extra | null) ?? {}
  const status = String(draft.status)
  return (
    <Modal open={open} title="미리보기" onClose={onClose}>
      <div className="space-y-4">
        {status === 'draft' && <p role="status" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">상태가 &lsquo;초안&rsquo;이라서, 게시해도 앱에는 이 식단이 보이지 않아요.</p>}
        {status === 'closed' && <p role="status" className="rounded-xl bg-page p-3 text-sm">앱에는 &lsquo;이 식사는 운영하지 않아요&rsquo;로 보여요.</p>}
        {status === 'no_menu' && <p role="status" className="rounded-xl bg-page p-3 text-sm">앱에는 &lsquo;메뉴가 공개되지 않았어요&rsquo;로 보여요.</p>}
        <div aria-label="앱 식단 카드 미리보기" className="rounded-2xl border border-line bg-white p-4 shadow-sm">
          {extra.photo_url && <img src={extra.photo_url} alt="식단 사진" className="mb-3 aspect-[16/10] w-full rounded-xl object-cover" />}
          <div className="mb-2 flex items-center justify-between"><span className="font-bold">{MEAL_LABEL[meal.meal_type]}{meal.option_name ? ` · ${meal.option_name}` : ''} <span className="text-xs font-normal text-muted">{meal.meal_date}</span></span>
            {draft.price_krw != null && <Badge tone="brand">{Number(draft.price_krw).toLocaleString('ko-KR')}원</Badge>}</div>
          {draft.start_time || draft.end_time ? <div className="mb-2 text-xs text-muted">{String(draft.start_time ?? '')}–{String(draft.end_time ?? '')}</div> : null}
          {draft.badge ? <div className="mb-2"><Badge tone="brand">{String(draft.badge)}</Badge></div> : null}
          <div className="flex flex-wrap gap-1.5">{items.map((i, k) => <span key={`${i.name_ko}-${k}`} className={`rounded-lg px-2.5 py-1 text-sm ${k === 0 ? 'bg-brand/40 font-semibold' : 'bg-page'}`}>{i.name_ko}</span>)}{items.length === 0 && <span className="text-sm text-muted">메뉴 없음</span>}</div>
          {extra.notice && <p className="mt-2 text-sm text-muted">{extra.notice}</p>}
          <p className="mt-2 border-t border-line pt-2 text-xs text-muted">{draft.verified_at ? `확인 ${String(draft.verified_at).slice(0, 10)}` : ''}{draft.source_url ? ' · 출처 있음' : ' · 출처 없음'}</p>
        </div>
        <div>
          <h3 className="mb-1 text-sm font-bold">지금 게시된 내용과 달라지는 항목 ({changes.length})</h3>
          {changes.length === 0 ? <p className="rounded-xl bg-page p-3 text-sm text-muted">게시된 내용과 같아요.</p> : (
            <ul aria-label="달라지는 항목" className="space-y-1.5 rounded-xl bg-page p-3 text-sm">
              {changes.map((c) => <li key={c.key}><b>{c.label}</b>: <span className="text-muted line-through">{showValue(c.from)}</span> → {showValue(c.to)}</li>)}
            </ul>)}
        </div>
      </div>
    </Modal>
  )
}
