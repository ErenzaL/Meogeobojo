import { Badge, Modal } from '@/components/ui'
import { diffSnapshots, showValue, type Snapshot } from '@/lib/cms'

const VIS: Record<string, string> = { draft: '초안', published: '공개', hidden: '숨김', archived: '보관' }
const won = (n: unknown) => (typeof n === 'number' ? `${n.toLocaleString('ko-KR')}원` : null)

/** What the pending draft will look like in the app, and exactly what changes
 *  against what is live now. Built from the SAVED draft (not from unsaved edits). */
export default function RestaurantPreview({ open, live, draft, onClose }: { open: boolean; live: Snapshot; draft: Snapshot; onClose: () => void }) {
  const changes = diffSnapshots(live, draft)
  const vis = String(draft.visibility ?? '')
  const purposes = Array.isArray(draft.dining_purposes) ? (draft.dining_purposes as string[]) : []
  const price = won(draft.price_min_krw)
  return (
    <Modal open={open} title="미리보기" onClose={onClose}>
      <div className="space-y-4">
        {vis !== 'published' && <p role="status" className="rounded-xl bg-amber-50 p-3 text-sm text-amber-900">이 초안의 공개 상태는 &lsquo;{VIS[vis] ?? vis}&rsquo;이라서, 게시해도 앱 목록에는 이 식당이 보이지 않아요.</p>}
        <div aria-label="앱 식당 카드 미리보기" className="rounded-2xl border border-line bg-white p-4 shadow-sm">
          <div className="mb-3 grid h-28 place-items-center rounded-xl bg-page text-xs text-muted">대표 사진은 사진 관리에서 게시해요</div>
          <div className="flex items-start justify-between gap-2">
            <div><div className="text-lg font-bold">{String(draft.name_ko ?? '')}</div>
              <div className="text-sm text-muted">{[draft.category, draft.address].filter(Boolean).join(' · ') || '카테고리·주소는 카카오 정보와 함께 보여요'}</div></div>
            {draft.featured === true && <Badge tone="brand">추천</Badge>}
          </div>
          {price && <div className="mt-2 text-sm">{price}부터</div>}
          {typeof draft.description === 'string' && draft.description && <p className="mt-2 text-sm">{draft.description}</p>}
          {purposes.length > 0 && <div className="mt-2 flex flex-wrap gap-1.5">{purposes.map((p) => <Badge key={p}>{p}</Badge>)}</div>}
          {draft.last_order_time ? <div className="mt-2 text-xs text-muted">주문 마감 {String(draft.last_order_time)}</div> : null}
        </div>
        <div>
          <h3 className="mb-1 text-sm font-bold">라이브와 달라지는 항목 ({changes.length})</h3>
          {changes.length === 0 ? <p className="rounded-xl bg-page p-3 text-sm text-muted">라이브와 같은 내용이에요.</p> : (
            <ul aria-label="달라지는 항목" className="space-y-1.5 rounded-xl bg-page p-3 text-sm">
              {changes.map((c) => <li key={c.key}><b>{c.label}</b>: <span className="text-muted line-through">{showValue(c.from)}</span> → {showValue(c.to)}</li>)}
            </ul>)}
        </div>
      </div>
    </Modal>
  )
}
