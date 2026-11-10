import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Button, Field, Input, Modal, Select, Textarea } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import { cafeteriaRow, cafeteriaToForm, emptyCafeteriaForm, KINDS, STATUS_LABEL, STATUSES, validateCafeteria, type Cafeteria, type CafeteriaForm } from './model'

type Uni = { id: string; name_ko: string }

/** Create (cafeteria = null) or edit one campus cafeteria in `campus_cafeterias`.
 *  Names are optional: leave them empty unless an official source gives them. */
export default function CafeteriaFormModal({ cafeteria, universities, defaultUniversity, onClose, onSaved }: {
  cafeteria: Cafeteria | null; universities: Uni[]; defaultUniversity: string; onClose: () => void; onSaved: (id: string, msg: string, universityId: string) => void
}) {
  const qc = useQueryClient()
  const isNew = cafeteria === null
  const [f, setF] = useState<CafeteriaForm>(() => (cafeteria ? cafeteriaToForm(cafeteria) : emptyCafeteriaForm(defaultUniversity)))
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [err, setErr] = useState<string | null>(null)
  const set = <K extends keyof CafeteriaForm>(k: K, v: CafeteriaForm[K]) => setF((p) => ({ ...p, [k]: v }))

  const save = useMutation({
    mutationFn: async () => {
      const e = validateCafeteria(f); setErrors(e)
      if (Object.keys(e).length) throw new Error('입력값을 확인해 주세요')
      const row = cafeteriaRow(f)
      if (isNew) {
        const { data, error } = await supabase.from('campus_cafeterias').insert(row).select('id').single()
        if (error) throw error
        return (data as { id: string }).id
      }
      const { error } = await supabase.from('campus_cafeterias').update(row).eq('id', cafeteria.id)
      if (error) throw error
      return cafeteria.id
    },
    onSuccess: async (id) => { await qc.invalidateQueries({ queryKey: ['cafeterias'] }); onSaved(id, isNew ? '학식 식당을 만들었어요. 메뉴를 추가하면 앱에 보여요.' : '학식 식당 정보를 저장했어요.', f.university_id) },
    onError: (e) => setErr(typeof e === 'object' && e && 'code' in e && (e as { code: string }).code === '23505' ? '이 대학교에 같은 이름의 학식 식당이 이미 있어요.' : errorMessage(e)),
  })

  return (
    <Modal open title={isNew ? '학식 식당 추가' : '학식 식당 수정'} onClose={onClose}>
      <div className="space-y-3">
        <Field label="대학교" htmlFor="cf_uni" error={errors.university_id}>
          <Select id="cf_uni" value={f.university_id} disabled={!isNew} onChange={(e) => set('university_id', e.target.value)}>
            <option value="">선택하세요</option>{universities.map((u) => <option key={u.id} value={u.id}>{u.name_ko}</option>)}
          </Select>
        </Field>
        <Field label="이름 (한국어)" htmlFor="cf_ko" error={errors.name_ko} hint="공식 이름을 알 때만 입력하세요. 비워 두면 종류로 표시돼요.">
          <Input id="cf_ko" value={f.name_ko} onChange={(e) => set('name_ko', e.target.value)} />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="영어 이름 (선택)" htmlFor="cf_en" error={errors.name_en}><Input id="cf_en" value={f.name_en} onChange={(e) => set('name_en', e.target.value)} /></Field>
          <Field label="중국어 이름 (선택)" htmlFor="cf_zh" error={errors.name_zh}><Input id="cf_zh" value={f.name_zh} onChange={(e) => set('name_zh', e.target.value)} /></Field>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <Field label="종류" htmlFor="cf_kind"><Select id="cf_kind" value={f.kind} onChange={(e) => set('kind', e.target.value as CafeteriaForm['kind'])}>{KINDS.map((k) => <option key={k.value} value={k.value}>{k.label}</option>)}</Select></Field>
          <Field label="표시 순서" htmlFor="cf_order" error={errors.sort_order} hint="작을수록 먼저"><Input id="cf_order" inputMode="numeric" value={f.sort_order} onChange={(e) => set('sort_order', e.target.value)} /></Field>
        </div>
        <Field label="위치 / 건물 설명 (선택)" htmlFor="cf_loc"><Input id="cf_loc" value={f.location} onChange={(e) => set('location', e.target.value)} placeholder="예: 학생회관 1층" /></Field>
        <Field label="운영 안내 (선택)" htmlFor="cf_note" error={errors.operating_note} hint="확인된 운영 정보만 적어 주세요. 앱의 학식 화면에 보여요.">
          <Textarea id="cf_note" className="min-h-16" value={f.operating_note} onChange={(e) => set('operating_note', e.target.value)} />
        </Field>
        <Field label="상태" htmlFor="cf_status" hint="비활성·보관하면 앱에서 이 식당과 메뉴가 숨겨져요. 메뉴 기록은 지워지지 않아요.">
          <Select id="cf_status" value={f.status} onChange={(e) => set('status', e.target.value as CafeteriaForm['status'])}>{STATUSES.map((s) => <option key={s} value={s}>{STATUS_LABEL[s]}</option>)}</Select>
        </Field>
        {err && <p role="alert" className="text-sm text-red-600">{err}</p>}
        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={onClose} disabled={save.isPending}>취소</Button>
          <Button onClick={() => { setErr(null); save.mutate() }} disabled={save.isPending}>{isNew ? '추가' : '저장'}</Button>
        </div>
      </div>
    </Modal>
  )
}
