import { ImageOff } from 'lucide-react'
import { Badge, Modal } from '@/components/ui'
import { diffSnapshots, showValue, type MenuItem, type Snapshot } from '@/lib/cms'
import { sortItems } from './menu'

/** The restaurant menu as students will see it after publishing (active lines only),
 *  and exactly what differs from what is published now. */
export default function MenuPreview({ open, live, draft, onClose }: { open: boolean; live: Snapshot; draft: Snapshot; onClose: () => void }) {
  const changes = diffSnapshots(live, draft)
  const shown = sortItems((draft.items as MenuItem[]) ?? []).filter((i) => i.status === 'active')
  return (
    <Modal open={open} title="미리보기" onClose={onClose}>
      <div className="space-y-4">
        <div aria-label="앱 메뉴 미리보기" className="space-y-2 rounded-2xl border border-line bg-white p-4 shadow-sm">
          {shown.length === 0 && <p className="text-sm text-muted">앱에는 메뉴가 보이지 않아요.</p>}
          {shown.map((i) => (
            <div key={i.id} className="flex items-center gap-3">
              {i.image_url ? <img src={i.image_url} alt={`${i.name_ko} 사진`} className="size-12 rounded-lg object-cover" /> : <span className="grid size-12 place-items-center rounded-lg bg-page text-muted"><ImageOff className="size-4" /></span>}
              <div className="min-w-0 flex-1">
                <div className="font-semibold">{i.name_ko} {i.representative && <Badge tone="brand">대표</Badge>} {i.recommended && <Badge tone="brand">추천</Badge>} {!i.available && <Badge tone="amber">품절</Badge>}</div>
                {i.description_ko && <div className="text-xs text-muted">{i.description_ko}</div>}
              </div>
              <span className="text-sm font-semibold">{i.price_krw != null ? `${i.price_krw.toLocaleString('ko-KR')}원` : '가격 미정'}</span>
            </div>))}
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
