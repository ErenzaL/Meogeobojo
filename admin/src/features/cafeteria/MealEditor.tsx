import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ImageOff, X } from 'lucide-react'
import { useState } from 'react'
import PublishingToolbar from '@/components/PublishingToolbar'
import { Button, Card, ErrorState, Skeleton } from '@/components/ui'
import { cmsSaveDraft, cmsState, isConflict } from '@/lib/cms'
import { ALLOWED_IMAGE_TYPES, BUCKET, imagePath, prepareImage } from '@/lib/images'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import MealFields from './MealFields'
import MealPreview from './MealPreview'
import { mealFormFromSnapshot, snapshotFromMealForm, validateMeal, type Extra, type MealForm } from './meal'

const TYPE = 'cafeteria_meal' as const
type Msg = { tone: 'ok' | 'bad'; text: string }
type Photo = { url: string; path: string } | null

/** Edits ONE meal as a draft: saving never changes what students see. The toolbar
 *  publishes now, schedules, unpublishes, restores and shows the history. */
export default function MealEditor({ meal, cafeteriaId, onClose, onChanged }: {
  meal: { id: string; meal_date: string; meal_type: MealForm['type']; option_name: string }; cafeteriaId: string; onClose: () => void; onChanged: () => void
}) {
  const qc = useQueryClient()
  const [edited, setEdited] = useState<MealForm | null>(null) // null: nothing changed yet (the form shows the server draft/live)
  const [editBase, setEditBase] = useState<number | null>(null)
  const [photo, setPhoto] = useState<Photo | undefined>(undefined) // undefined: unchanged
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [message, setMessage] = useState<Msg | null>(null)
  const [previewing, setPreviewing] = useState(false)

  const cms = useQuery({ queryKey: ['cms', TYPE, meal.id], queryFn: () => cmsState(TYPE, meal.id) })
  const state = cms.data
  const base = state ? (state.draft?.data ?? state.live) : null
  const serverRev = state?.draft?.revision ?? 0
  const form = edited ?? (base ? mealFormFromSnapshot(base, meal) : null)
  const dirty = edited !== null || photo !== undefined
  const conflict = editBase !== null && editBase !== serverRev
  const shownPhoto = photo === undefined ? (((base?.extra as Extra | null) ?? {}).photo_url ?? null) : (photo?.url ?? null)

  const refresh = async () => { await qc.invalidateQueries({ queryKey: ['cms', TYPE, meal.id] }); await qc.invalidateQueries({ queryKey: ['cms-overview', TYPE, cafeteriaId] }); onChanged() }
  const set = <K extends keyof MealForm>(k: K, v: MealForm[K]) => { if (!form) return; setEdited({ ...form, [k]: v }); setEditBase((b) => b ?? serverRev) }

  const save = useMutation({
    mutationFn: async () => {
      if (!form || !base) throw new Error('불러오는 중이에요')
      const e = validateMeal(form); setErrors(e)
      if (Object.keys(e).length) throw new Error('입력값을 확인해 주세요')
      return cmsSaveDraft(TYPE, meal.id, snapshotFromMealForm(form, base, photo), editBase ?? serverRev)
    },
    onSuccess: async () => { setMessage({ tone: 'ok', text: '초안을 저장했어요. 앱에는 아직 보이지 않아요. 게시하면 반영돼요.' }); setEdited(null); setPhoto(undefined); setEditBase(null); await refresh() },
    onError: async (e) => { setMessage({ tone: 'bad', text: errorMessage(e) }); if (isConflict(e)) await refresh() },
  })

  const uploadPhoto = async (file: File) => {
    try {
      setMessage(null)
      const img = await prepareImage(file)
      const path = imagePath(`cafeteria/${cafeteriaId}`, img.type)
      const up = await supabase.storage.from(BUCKET).upload(path, img.blob, { contentType: img.type })
      if (up.error) throw up.error
      // an earlier UNSAVED upload is not referenced by anything: remove it
      if (photo?.path) await supabase.storage.from(BUCKET).remove([photo.path])
      setPhoto({ url: supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl, path }); setEditBase((b) => b ?? serverRev)
      setMessage({ tone: 'ok', text: '사진을 골랐어요. 초안을 저장하면 반영돼요. (게시 전에는 앱에 보이지 않아요)' })
    } catch (e) { setMessage({ tone: 'bad', text: errorMessage(e) }) }
  }
  const removePhoto = async () => {
    if (photo?.path) await supabase.storage.from(BUCKET).remove([photo.path]) // an unsaved upload
    setPhoto(null); setEditBase((b) => b ?? serverRev)
  }

  if (cms.isLoading) return <Skeleton className="h-64 w-full" />
  if (cms.error) return <ErrorState error={cms.error} onRetry={() => void cms.refetch()} />
  if (!state || !form || !base) return null

  return (
    <div className="space-y-3" aria-label="식단 편집">
      <div className="flex items-center justify-between"><h2 className="font-bold">식단 편집</h2><Button size="icon" variant="ghost" aria-label="편집 닫기" onClick={onClose}><X className="size-4" /></Button></div>
      <PublishingToolbar type={TYPE} id={meal.id} state={state} loading={false} error={null} dirty={dirty} saving={save.isPending} message={message}
        onSaveDraft={() => save.mutate()} onPreview={() => setPreviewing(true)} onChanged={async () => { await refresh(); setMessage(null) }} onConflict={() => void refresh()} />
      {conflict && (
        <div role="alert" className="space-y-2 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">
          <p><b>다른 관리자가 이 식단의 초안을 먼저 저장했어요.</b></p>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" onClick={() => { setEdited(null); setPhoto(undefined); setEditBase(null) }}>최신 초안 불러오기 (내 수정 버리기)</Button>
            <Button size="sm" onClick={() => setEditBase(serverRev)}>내 수정으로 덮어쓰기</Button>
          </div>
        </div>)}
      <Card className="space-y-3">
        <MealFields form={form} errors={errors} set={set} identity={false} />
        <div className="space-y-2" aria-label="음식 사진">
          <div className="text-sm font-medium">음식 사진</div>
          {shownPhoto ? <img src={shownPhoto} alt="현재 음식 사진" className="aspect-[16/10] w-full rounded-xl object-cover" /> : <div className="grid aspect-[16/10] w-full place-items-center rounded-xl bg-page text-sm text-muted"><span className="text-center"><ImageOff className="mx-auto mb-1 size-5" />사진 없음</span></div>}
          <div className="flex items-center gap-3">
            <label className="cursor-pointer text-sm font-semibold text-brand-strong">{shownPhoto ? '사진 교체' : '사진 올리기'}
              <input type="file" accept={ALLOWED_IMAGE_TYPES.join(',')} hidden aria-label="이 식단 사진 올리기" onChange={(e) => { const f = e.target.files?.[0]; if (f) void uploadPhoto(f); e.target.value = '' }} /></label>
            {shownPhoto && <button type="button" className="text-sm font-semibold text-red-600" onClick={() => void removePhoto()}>사진 삭제</button>}
          </div>
          <p className="text-xs text-muted">사진은 초안과 함께 저장되고, 게시해야 앱에 보여요. 게시된 사진 파일은 복원을 위해 지우지 않아요.</p>
        </div>
      </Card>
      <PreviewHost open={previewing} state={state} meal={meal} onClose={() => setPreviewing(false)} />
    </div>
  )
}

function PreviewHost({ open, state, meal, onClose }: { open: boolean; state: Awaited<ReturnType<typeof cmsState>>; meal: { meal_date: string; meal_type: MealForm['type']; option_name: string }; onClose: () => void }) {
  return <MealPreview open={open} live={state.live} draft={state.draft?.data ?? state.live} meal={meal} onClose={onClose} />
}
