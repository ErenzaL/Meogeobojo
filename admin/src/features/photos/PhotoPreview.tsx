import { ImageOff } from 'lucide-react'
import { Modal } from '@/components/ui'
import { diffSnapshots, showValue, type PhotoItem, type Snapshot } from '@/lib/cms'
import { shownInApp } from './photo'

/** The restaurant's photos as students will see them after publishing, and what differs from now. */
export default function PhotoPreview({ open, live, draft, onClose }: { open: boolean; live: Snapshot; draft: Snapshot; onClose: () => void }) {
  const changes = diffSnapshots(live, draft)
  const { cover, gallery } = shownInApp((draft.photos as PhotoItem[]) ?? [])
  return (
    <Modal open={open} title="미리보기" onClose={onClose}>
      <div className="space-y-4">
        <div aria-label="앱 사진 미리보기" className="space-y-2 rounded-2xl border border-line bg-white p-4 shadow-sm">
          {cover ? <img src={cover.url} alt="대표 사진 미리보기" className="aspect-[16/10] w-full rounded-xl object-cover" /> : <div className="grid aspect-[16/10] w-full place-items-center rounded-xl bg-page text-sm text-muted"><span><ImageOff className="mx-auto mb-1 size-5" />앱에는 기본 이미지가 보여요</span></div>}
          <div className="grid grid-cols-3 gap-2">{gallery.map((p) => <img key={p.id} src={p.url} alt={p.caption || '갤러리 사진 미리보기'} className="aspect-square w-full rounded-lg object-cover" />)}</div>
          {gallery.length === 0 && <p className="text-sm text-muted">갤러리 사진이 없어요.</p>}
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
