import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, Trash2 } from 'lucide-react'
import { useMemo, useState } from 'react'
import { Controller, useForm } from 'react-hook-form'
import { Link, useNavigate, useParams } from 'react-router-dom'
import PublishingToolbar from '@/components/PublishingToolbar'
import { Button, Card, ErrorState, Field, Input, PageHeader, Select, Skeleton, Textarea } from '@/components/ui'
import { useAuth } from '@/lib/auth'
import { cmsSaveDraft, cmsState, isConflict } from '@/lib/cms'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import DeleteRestaurantsDialog from './DeleteRestaurantsDialog'
import KakaoSourceCard from './KakaoSourceCard'
import RestaurantPreview from './RestaurantPreview'
import { useUniversities } from './RestaurantsPage'
import { BUSINESS_LABEL, BUSINESS_STATUSES, VISIBILITIES, VISIBILITY_LABEL, emptyRestaurantForm, fromRow, restaurantSchema, snapshotFromForm, toRow, type RestaurantForm } from './schema'

const TYPE = 'restaurant' as const
type Msg = { tone: 'ok' | 'bad'; text: string }

export default function RestaurantFormPage() {
  const { id } = useParams()
  const isNew = !id || id === 'new'
  return isNew ? <NewRestaurant /> : <EditRestaurant id={id} />
}

function FormFields({ register, control, errors, unis, existing }: { register: ReturnType<typeof useForm<RestaurantForm>>['register']; control: ReturnType<typeof useForm<RestaurantForm>>['control']; errors: ReturnType<typeof useForm<RestaurantForm>>['formState']['errors']; unis: ReturnType<typeof useUniversities>; existing: boolean }) {
  return (
    <>
      <Card className="grid gap-4 sm:grid-cols-2">
        <Field label="이름 (한국어)" htmlFor="name_ko" error={errors.name_ko?.message}><Input id="name_ko" {...register('name_ko')} /></Field>
        <Field label="이름 (영어)" htmlFor="name_en" error={errors.name_en?.message}><Input id="name_en" {...register('name_en')} /></Field>
        <Field label="카카오 장소 ID" htmlFor="kakao_place_id" hint={existing ? '식당의 식별자라서 바꿀 수 없어요.' : '카카오 식당을 보강할 때 입력해요. 직접 만든 식당은 비워 두세요.'} error={errors.kakao_place_id?.message}><Input id="kakao_place_id" disabled={existing} {...register('kakao_place_id')} /></Field>
        <Field label="카테고리" htmlFor="category" error={errors.category?.message}><Input id="category" {...register('category')} /></Field>
        <Field label="주소" htmlFor="address" error={errors.address?.message}><Input id="address" {...register('address')} /></Field>
        <Field label="전화번호" htmlFor="phone" error={errors.phone?.message}><Input id="phone" {...register('phone')} /></Field>
        <Field label="위도" htmlFor="latitude" error={errors.latitude?.message}><Input id="latitude" inputMode="decimal" {...register('latitude')} /></Field>
        <Field label="경도" htmlFor="longitude" error={errors.longitude?.message}><Input id="longitude" inputMode="decimal" {...register('longitude')} /></Field>
      </Card>
      <Card className="space-y-4">
        <Field label="설명" htmlFor="description" error={errors.description?.message}><Textarea id="description" {...register('description')} /></Field>
        <Field label="대표 이미지 주소" htmlFor="image_url" hint={existing ? '대표 사진은 사진 관리에서 올리고 게시해요.' : 'https:// 로 시작해야 해요.'} error={errors.image_url?.message}><Input id="image_url" disabled={existing} {...register('image_url')} /></Field>
        <Field label="식사 목적 (쉼표로 구분)" htmlFor="dining_purposes" error={errors.dining_purposes?.message}><Input id="dining_purposes" placeholder="혼밥, 회식, 데이트" {...register('dining_purposes')} /></Field>
      </Card>
      <Card className="grid gap-4 sm:grid-cols-3">
        <Field label="최저 가격 (원)" htmlFor="price_min_krw" error={errors.price_min_krw?.message}><Input id="price_min_krw" inputMode="numeric" {...register('price_min_krw')} /></Field>
        <Field label="최고 가격 (원)" htmlFor="price_max_krw" error={errors.price_max_krw?.message}><Input id="price_max_krw" inputMode="numeric" {...register('price_max_krw')} /></Field>
        <Field label="1인 평균 (원)" htmlFor="avg_cost_krw" error={errors.avg_cost_krw?.message}><Input id="avg_cost_krw" inputMode="numeric" {...register('avg_cost_krw')} /></Field>
        <Field label="브레이크타임" htmlFor="break_time" error={errors.break_time?.message}><Input id="break_time" placeholder="15:00-17:00" {...register('break_time')} /></Field>
        <Field label="영업 시작 (HH:MM)" htmlFor="open_time" hint="주문 마감과 함께 있어야 앱이 '지금 주문 가능'을 확인할 수 있어요." error={errors.open_time?.message}><Input id="open_time" placeholder="11:00" {...register('open_time')} /></Field>
        <Field label="주문 마감 (HH:MM)" htmlFor="last_order_time" error={errors.last_order_time?.message}><Input id="last_order_time" placeholder="21:30" {...register('last_order_time')} /></Field>
        <Field label="영업 상태" htmlFor="business_status">
          <Select id="business_status" {...register('business_status')}><option value="">알 수 없음</option>{BUSINESS_STATUSES.map((s) => <option key={s} value={s}>{BUSINESS_LABEL[s]}</option>)}</Select>
        </Field>
      </Card>
      <Card className="space-y-4">
        <Field label="추천 식당으로 노출" htmlFor="featured" hint="켜면 앱 홈의 '오늘의 추천' 목록에서 맨 앞에 보여요. 추천 순위 자체는 바뀌지 않아요. 공개 상태일 때만 적용돼요.">
          <label className="flex items-center gap-2 text-sm"><input id="featured" type="checkbox" {...register('featured')} />추천 식당</label>
        </Field>
        <Field label="추천 표시 순서" htmlFor="display_order" hint="작을수록 먼저 (비우면 마지막)" error={errors.display_order?.message}><Input id="display_order" inputMode="numeric" {...register('display_order')} /></Field>
        <Field label="공개 상태" htmlFor="visibility" hint={existing ? '게시할 때 적용돼요. 초안은 관리자만 볼 수 있고, 숨김·보관은 앱에서 이 식당을 감춰요.' : '새 식당은 항상 초안으로 시작해요. 게시는 저장한 뒤 상단 도구에서 해요.'}>
          <Select id="visibility" disabled={!existing} {...register('visibility')}>{VISIBILITIES.map((v) => <option key={v} value={v}>{VISIBILITY_LABEL[v]}</option>)}</Select>
        </Field>
        <fieldset>
          <legend className="mb-2 text-sm font-medium">연결된 대학교</legend>
          <Controller control={control} name="university_ids" render={({ field }) => (
            <div className="flex flex-wrap gap-2">
              {unis.data?.map((u) => {
                const on = field.value.includes(u.id)
                return (
                  <label key={u.id} className={`cursor-pointer rounded-xl border px-3 py-1.5 text-sm ${on ? 'border-ink bg-ink text-white' : 'border-line bg-white'}`}>
                    <input type="checkbox" className="sr-only" checked={on}
                      onChange={() => field.onChange(on ? field.value.filter((x) => x !== u.id) : [...field.value, u.id])} />{u.name_ko}
                  </label>)
              })}
            </div>)} />
        </fieldset>
      </Card>
    </>
  )
}

/** A new restaurant is created as a DRAFT row (never visible in the app). It is
 *  then edited and published like any other. */
function NewRestaurant() {
  const nav = useNavigate()
  const qc = useQueryClient()
  const unis = useUniversities()
  const form = useForm<RestaurantForm>({ resolver: zodResolver(restaurantSchema), defaultValues: emptyRestaurantForm })
  const { register, control, handleSubmit, formState: { errors } } = form
  const create = useMutation({
    mutationFn: async (v: RestaurantForm) => {
      const { data, error } = await supabase.from('restaurant_overrides').insert({ ...toRow(v), visibility: 'draft', featured: false }).select('id').single()
      if (error) throw error
      const rid = (data as { id: string }).id
      const links = v.university_ids.map((u) => ({ restaurant_id: rid, university_id: u }))
      if (links.length) { const r = await supabase.from('restaurant_university_links').insert(links); if (r.error) throw r.error }
      return rid
    },
    onSuccess: async (rid) => { await qc.invalidateQueries({ queryKey: ['restaurants'] }); nav(`/restaurants/${rid}`, { replace: true }) },
  })
  const dup = (e: unknown) => (typeof e === 'object' && e && 'code' in e && (e as { code: string }).code === '23505' ? '이미 등록된 카카오 장소 ID예요. 기존 식당을 편집해 주세요.' : errorMessage(e))
  return (
    <form onSubmit={handleSubmit((v) => create.mutate(v))} className="max-w-4xl space-y-6">
      <Link to="/restaurants" className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><ArrowLeft className="size-4" />식당 목록</Link>
      <PageHeader title="식당 추가" description="초안으로 만들어져요. 만든 뒤 내용을 다듬고 게시해야 앱에 보여요."
        actions={<Button type="submit" disabled={create.isPending}>초안으로 만들기</Button>} />
      {create.isError && <ErrorState error={new Error(dup(create.error))} />}
      <FormFields register={register} control={control} errors={errors} unis={unis} existing={false} />
    </form>
  )
}

function EditRestaurant({ id }: { id: string }) {
  const qc = useQueryClient()
  const nav = useNavigate()
  const { can } = useAuth()
  const [deleting, setDeleting] = useState(false)
  const unis = useUniversities()
  const [message, setMessage] = useState<Msg | null>(null)
  const [previewing, setPreviewing] = useState(false)
  // The server draft revision my unsaved edits are based on (null: no unsaved edits).
  const [editBase, setEditBase] = useState<number | null>(null)

  const cms = useQuery({ queryKey: ['cms', TYPE, id], queryFn: () => cmsState(TYPE, id) })
  const identity = useQuery({
    queryKey: ['restaurant-identity', id],
    queryFn: async () => {
      const { data, error } = await supabase.from('restaurant_overrides').select('kakao_place_id,image_url').eq('id', id).single()
      if (error) throw error
      return data as { kakao_place_id: string | null; image_url: string | null }
    },
  })
  const state = cms.data
  const base = state ? (state.draft?.data ?? state.live) : null
  const serverRev = state ? (state.draft?.revision ?? 0) : 0
  const initial = useMemo(
    () => (base && identity.data ? fromRow({ ...base, kakao_place_id: identity.data.kakao_place_id, image_url: identity.data.image_url }, (base.university_ids as string[]) ?? []) : undefined),
    [base, identity.data],
  )

  // `values` keeps the form in step with the server draft; edits in progress are kept.
  const form = useForm<RestaurantForm>({ resolver: zodResolver(restaurantSchema), defaultValues: emptyRestaurantForm, values: initial, resetOptions: { keepDirtyValues: true } })
  const { register, control, handleSubmit, reset, formState: { errors, isDirty } } = form
  const conflict = editBase !== null && editBase !== serverRev
  const refresh = async () => { await qc.invalidateQueries({ queryKey: ['cms', TYPE, id] }); await qc.invalidateQueries({ queryKey: ['restaurant-identity', id] }) }

  const save = useMutation({
    mutationFn: async (v: RestaurantForm) => {
      if (!base) throw new Error('불러오는 중이에요')
      return cmsSaveDraft(TYPE, id, snapshotFromForm(v, base), editBase ?? serverRev)
    },
    onSuccess: async (_r, v) => {
      setMessage({ tone: 'ok', text: '초안을 저장했어요. 앱에는 아직 보이지 않아요. 게시하면 반영돼요.' })
      setEditBase(null)
      reset(v)
      await refresh()
    },
    onError: async (e) => {
      setMessage({ tone: 'bad', text: errorMessage(e) })
      if (isConflict(e)) await refresh() // the banner below offers the choice; nothing is overwritten
    },
  })

  if (cms.isLoading || identity.isLoading) return <Skeleton className="h-96 w-full" />
  if (cms.error) return <ErrorState error={cms.error} onRetry={() => void cms.refetch()} />
  const title = String((state?.draft?.data ?? state?.live)?.name_ko ?? '식당 편집')
  // A save that lost a race (conflict) leaves the edits in place and flags them.
  const dirty = isDirty || editBase !== null

  return (
    <form onSubmit={handleSubmit((v) => save.mutate(v))} onChange={() => setEditBase((b) => b ?? serverRev)} className="max-w-4xl space-y-6">
      <Link to="/restaurants" className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><ArrowLeft className="size-4" />식당 목록</Link>
      <PageHeader title={title} description="수정은 초안으로 저장돼요. 게시하기 전에는 앱 사용자에게 보이지 않아요." />
      <PublishingToolbar type={TYPE} id={id} state={state} loading={false} error={null} dirty={dirty} saving={save.isPending}
        message={message} onSaveDraft={() => void handleSubmit((v) => save.mutate(v))()} onPreview={() => setPreviewing(true)}
        onChanged={async () => { await refresh(); setMessage(null) }} onConflict={() => void refresh()} />
      {conflict && (
        <div role="alert" className="space-y-2 rounded-xl bg-amber-50 p-4 text-sm text-amber-900">
          <p><b>다른 관리자가 이 식당의 초안을 먼저 저장했어요.</b> 내 수정과 겹칠 수 있어서 자동으로 덮어쓰지 않았어요.</p>
          <div className="flex flex-wrap gap-2">
            <Button type="button" size="sm" variant="outline" onClick={() => { reset(initial); setEditBase(null); setMessage(null) }}>최신 초안 불러오기 (내 수정 버리기)</Button>
            <Button type="button" size="sm" onClick={() => { setEditBase(serverRev); setMessage({ tone: 'ok', text: '최신 초안을 기준으로 이어서 저장할 수 있어요. 저장하면 내 수정이 최신 초안을 덮어써요.' }) }}>내 수정으로 덮어쓰기</Button>
          </div>
        </div>)}
      <KakaoSourceCard id={id} />
      <FormFields register={register} control={control} errors={errors} unis={unis} existing />
      {can('super_admin') && (
        <Card className="space-y-2 border-red-200" aria-label="위험 구역">
          <h2 className="font-bold text-red-700">식당 삭제</h2>
          <p className="text-sm text-muted">이 식당과 메뉴·사진 정보·대학교 연결을 지워요. 되돌릴 수 없어요. 앱에서 감추기만 하려면 삭제 대신 공개 상태를 &lsquo;숨김&rsquo;으로 바꾸세요. 공개 중인 식당은 먼저 숨겨야 삭제할 수 있어요.</p>
          <Button type="button" variant="danger" onClick={() => setDeleting(true)}><Trash2 className="size-4" />이 식당 삭제…</Button>
        </Card>)}
      {deleting && (
        <DeleteRestaurantsDialog ids={[id]} onClose={(deletedIds) => {
          setDeleting(false)
          if (deletedIds.length > 0) { void qc.invalidateQueries({ queryKey: ['restaurants'] }); void qc.invalidateQueries({ queryKey: ['restaurant-coverage'] }); nav('/restaurants', { replace: true }) }
        }} />)}
      {state && <RestaurantPreview open={previewing} live={state.live} draft={state.draft?.data ?? state.live} onClose={() => setPreviewing(false)} />}
    </form>
  )
}
