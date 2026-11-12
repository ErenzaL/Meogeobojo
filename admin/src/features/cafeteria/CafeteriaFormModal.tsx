import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { Button, ConfirmDialog, Field, Input, Modal, Select, Textarea } from '@/components/ui'
import { ALLOWED_IMAGE_TYPES, BUCKET, imagePath, prepareImage } from '@/lib/images'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import { cafeteriaRow, cafeteriaToForm, DAYS, emptyCafeteriaForm, kindLabel, KINDS, PERIOD_LABEL, PERIODS, STATUS_LABEL, STATUSES, validateCafeteria, type Cafeteria, type CafeteriaForm } from './model'

type Uni = { id: string; name_ko: string }

/** Create (cafeteria = null) or edit one campus cafeteria in `campus_cafeterias`.
 *  Names are optional: leave them empty unless an official source gives them. */
export default function CafeteriaFormModal({ cafeteria, existing = [], universities, defaultUniversity, legacy = false, weekly = true, onClose, onSaved }: {
  cafeteria: Cafeteria | null; existing?: Cafeteria[]; legacy?: boolean; weekly?: boolean; universities: Uni[]; defaultUniversity: string; onClose: () => void; onSaved: (id: string, msg: string, universityId: string) => void
}) {
  const qc = useQueryClient()
  const isNew = cafeteria === null
  const [f, setF] = useState<CafeteriaForm>(() => (cafeteria ? cafeteriaToForm(cafeteria) : emptyCafeteriaForm(defaultUniversity)))
  const [errors, setErrors] = useState<Record<string, string>>({})
  const [err, setErr] = useState<string | null>(null)
  const [moveAsk, setMoveAsk] = useState(false)
  const [uploaded, setUploaded] = useState<string | null>(null) // a file uploaded in this dialog and not saved yet
  const set = <K extends keyof CafeteriaForm>(k: K, v: CafeteriaForm[K]) => setF((p) => ({ ...p, [k]: v }))

  const save = useMutation({
    mutationFn: async () => {
      const e = validateCafeteria(f); setErrors(e)
      if (Object.keys(e).length) throw new Error('입력값을 확인해 주세요')
      // A database without the cafeteria-management migration has no status / operating_note columns.
      const { status: _s, operating_note: _o, ...legacyRow } = cafeteriaRow(f)
      void _s; void _o
      // columns added by 20261118000100 (meal periods, weekdays, photo): left out on a database that does not have them yet
      const { meal_periods: _m, operating_days: _d, photo_url: _pu, photo_path: _pp, ...noWeekly } = legacy ? legacyRow : cafeteriaRow(f)
      void _m; void _d; void _pu; void _pp
      const row = legacy ? legacyRow : weekly ? cafeteriaRow(f) : noWeekly
      if (isNew) {
        const { data, error } = await supabase.from('campus_cafeterias').insert(row).select('id').single()
        if (error) throw error
        return (data as { id: string }).id
      }
      const { error } = await supabase.from('campus_cafeterias').update(row).eq('id', cafeteria.id)
      if (error) throw error
      // the replaced photo file is not referenced by anything else (cafeteria info has no version history): remove it
      if (weekly && cafeteria.photo_path && cafeteria.photo_path !== f.photo_path) await supabase.storage.from(BUCKET).remove([cafeteria.photo_path])
      return cafeteria.id
    },
    onSuccess: async (id) => { setUploaded(null); await qc.invalidateQueries({ queryKey: ['cafeterias'] }); onSaved(id, isNew ? '학식 식당을 만들었어요. 비활성 상태라 앱에는 아직 보이지 않아요. 메뉴를 채운 뒤 \'운영 중으로\'를 눌러 주세요.' : '학식 식당 정보를 저장했어요.', f.university_id) },
    onError: (e) => setErr(typeof e === 'object' && e && 'code' in e && (e as { code: string }).code === '23505' ? '이 대학교에 같은 이름의 학식 식당이 이미 있어요.' : errorMessage(e)),
  })

  const upload = async (file: File) => {
    try {
      setErr(null)
      const img = await prepareImage(file)
      const path = imagePath('cafeterias', img.type)
      const up = await supabase.storage.from(BUCKET).upload(path, img.blob, { contentType: img.type })
      if (up.error) throw up.error
      if (uploaded) await supabase.storage.from(BUCKET).remove([uploaded]) // an earlier unsaved pick would be an orphan
      setUploaded(path)
      setF((p) => ({ ...p, photo_url: supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl, photo_path: path }))
    } catch (e) { setErr(errorMessage(e)) }
  }
  const close = () => { if (uploaded) void supabase.storage.from(BUCKET).remove([uploaded]); onClose() }
  const toggle = <T,>(list: T[], v: T) => (list.includes(v) ? list.filter((x) => x !== v) : [...list, v])
  const wantsMove = !isNew && f.university_id !== cafeteria.university_id
  const siblings = existing.filter((c) => c.university_id === f.university_id && c.status !== 'archived' && c.id !== cafeteria?.id)
  const needsName = f.name_ko.trim() === '' && siblings.length > 0

  return (
    <Modal open title={isNew ? '학식 식당 추가' : '학식 식당 수정'} onClose={close}>
      <div className="space-y-3">
        <Field label="대학교" htmlFor="cf_uni" error={errors.university_id}>
          <Select id="cf_uni" value={f.university_id} onChange={(e) => set('university_id', e.target.value)}>
            <option value="">선택하세요</option>{universities.map((u) => <option key={u.id} value={u.id}>{u.name_ko}</option>)}
          </Select>
        </Field>
        {wantsMove && <p role="status" className="rounded-xl bg-amber-50 p-3 text-xs text-amber-900">다른 대학교로 옮기면 이 식당과 메뉴가 그 대학교 학생에게만 보여요. 메뉴 기록은 그대로 따라가요. 저장할 때 한 번 더 확인해요.</p>}
        <Field label="이름 (한국어)" htmlFor="cf_ko" error={errors.name_ko} hint="공식 이름을 알 때만 입력하세요. 비워 두면 종류로 표시돼요.">
          <Input id="cf_ko" value={f.name_ko} onChange={(e) => set('name_ko', e.target.value)} />
        </Field>
        {needsName && <p role="status" className="rounded-xl bg-amber-50 p-3 text-xs text-amber-900">이 대학교에는 학식 식당이 여러 곳이에요. 학생이 앱에서 식당을 고를 때 이 이름이 보이니, 이름을 적어 주세요. 비워 두면 &lsquo;{kindLabel(f.kind)}&rsquo;으로만 표시돼 구분하기 어려워요.</p>}
        <div className="grid grid-cols-2 gap-3">
          <Field label="영어 이름 (선택)" htmlFor="cf_en" error={errors.name_en}><Input id="cf_en" value={f.name_en} onChange={(e) => set('name_en', e.target.value)} /></Field>
          <Field label="중국어 이름 (선택)" htmlFor="cf_zh" error={errors.name_zh}><Input id="cf_zh" value={f.name_zh} onChange={(e) => set('name_zh', e.target.value)} /></Field>
        </div>
        <Field label="종류" htmlFor="cf_kind"><Select id="cf_kind" value={f.kind} onChange={(e) => set('kind', e.target.value as CafeteriaForm['kind'])}>{KINDS.map((k) => <option key={k.value} value={k.value}>{k.label}</option>)}</Select></Field>
        <p className="-mt-1 text-xs text-muted">식당은 등록한 순서대로 나와요 (먼저 등록한 식당이 위). 앱에서 처음 보이는 식당은 학생식당 중 가장 먼저 등록한 식당이에요.</p>
        <Field label="위치 / 건물 설명 (선택)" htmlFor="cf_loc"><Input id="cf_loc" value={f.location} onChange={(e) => set('location', e.target.value)} placeholder="예: 학생회관 1층" /></Field>
        {!weekly && <p className="rounded-xl bg-amber-50 p-3 text-xs text-amber-900">운영 식사·요일·사진은 데이터베이스 업데이트(20261118000100) 뒤에 쓸 수 있어요.</p>}
        <fieldset className="space-y-1" disabled={!weekly}><legend className="text-sm font-medium">운영하는 식사</legend>
          <div className="flex gap-4 text-sm">{PERIODS.map((p) => <label key={p} className="flex items-center gap-1.5"><input type="checkbox" aria-label={`운영 식사 ${PERIOD_LABEL[p]}`} checked={f.meal_periods.includes(p)} onChange={() => set('meal_periods', toggle(f.meal_periods, p))} />{PERIOD_LABEL[p]}</label>)}</div>
          {errors.meal_periods && <p className="text-xs text-red-600">{errors.meal_periods}</p>}
          <p className="text-xs text-muted">모든 식당이 세 끼를 다 하지는 않아요. 켜지 않은 식사는 메뉴 입력 칸에 나오지 않아요. 켜 두어도 메뉴를 입력하지 않은 식사는 앱과 웹에 나타나지 않아요.</p></fieldset>
        <fieldset className="space-y-1" disabled={!weekly}><legend className="text-sm font-medium">운영하는 요일</legend>
          <div className="flex flex-wrap gap-3 text-sm">{DAYS.map((d) => <label key={d.value} className="flex items-center gap-1.5"><input type="checkbox" aria-label={`운영 요일 ${d.label}`} checked={f.operating_days.includes(d.value)} onChange={() => set('operating_days', toggle(f.operating_days, d.value))} />{d.label}</label>)}</div>
          {errors.operating_days && <p className="text-xs text-red-600">{errors.operating_days}</p>}</fieldset>
        <div className="space-y-1" aria-label="식당 사진"><div className="text-sm font-medium">식당 사진 (선택)</div>
          {f.photo_url && <img src={f.photo_url} alt="식당 사진" className="aspect-[16/8] w-full rounded-xl object-cover" />}
          <div className="flex items-center gap-3"><label className={`cursor-pointer text-sm font-semibold text-brand-strong ${weekly ? '' : 'pointer-events-none opacity-50'}`}>{f.photo_url ? '사진 교체' : '사진 올리기'}
            <input type="file" accept={ALLOWED_IMAGE_TYPES.join(',')} hidden aria-label="식당 사진 올리기" disabled={!weekly} onChange={(e) => { const file = e.target.files?.[0]; if (file) void upload(file); e.target.value = '' }} /></label>
            {f.photo_url && <button type="button" className="text-sm font-semibold text-red-600" onClick={() => { if (uploaded) { void supabase.storage.from(BUCKET).remove([uploaded]); setUploaded(null) } setF((p) => ({ ...p, photo_url: null, photo_path: null })) }}>사진 삭제</button>}</div></div>
        {legacy && <p className="rounded-xl bg-amber-50 p-3 text-xs text-amber-900">운영 안내와 상태는 데이터베이스 업데이트(20261113000100) 뒤에 쓸 수 있어요.</p>}
        <Field label="운영 안내 (선택)" htmlFor="cf_note" error={errors.operating_note} hint="확인된 운영 정보만 적어 주세요. 앱의 학식 화면에 보여요.">
          <Textarea id="cf_note" className="min-h-16" disabled={legacy} value={f.operating_note} onChange={(e) => set('operating_note', e.target.value)} />
        </Field>
        <Field label="상태" htmlFor="cf_status" hint="비활성·보관하면 앱에서 이 식당과 메뉴가 숨겨져요. 메뉴 기록은 지워지지 않아요.">
          <Select id="cf_status" disabled={legacy} value={f.status} onChange={(e) => set('status', e.target.value as CafeteriaForm['status'])}>{STATUSES.map((s) => <option key={s} value={s}>{STATUS_LABEL[s]}</option>)}</Select>
        </Field>
        {err && <p role="alert" className="text-sm text-red-600">{err}</p>}
        <div className="flex justify-end gap-2">
          <Button variant="outline" onClick={close} disabled={save.isPending}>취소</Button>
          <Button onClick={() => { setErr(null); if (wantsMove) setMoveAsk(true); else save.mutate() }} disabled={save.isPending}>{isNew ? '추가' : '저장'}</Button>
        </div>
      </div>
      <ConfirmDialog open={moveAsk} title="다른 대학교로 옮길까요?" description={`"${f.name_ko || '이 식당'}"과(와) 메뉴 기록이 선택한 대학교로 옮겨져요. 원래 대학교 학생에게는 더 이상 보이지 않아요.`} confirmLabel="옮기고 저장" danger
        onCancel={() => setMoveAsk(false)} onConfirm={() => { setMoveAsk(false); save.mutate() }} />
    </Modal>
  )
}
