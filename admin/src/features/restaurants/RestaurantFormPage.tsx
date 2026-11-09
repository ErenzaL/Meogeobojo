import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Controller, useForm } from 'react-hook-form'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { Button, Card, ConfirmDialog, ErrorState, Field, Input, PageHeader, Select, Skeleton, Textarea } from '@/components/ui'
import { supabase } from '@/lib/supabase'
import { errorMessage } from '@/lib/utils'
import { useUniversities } from './RestaurantsPage'
import { BUSINESS_LABEL, BUSINESS_STATUSES, VISIBILITIES, VISIBILITY_LABEL, emptyRestaurantForm, fromRow, restaurantSchema, toRow, type RestaurantForm } from './schema'

async function loadRestaurant(id: string) {
  const [r, links] = await Promise.all([
    supabase.from('restaurant_overrides').select('*').eq('id', id).single(),
    supabase.from('restaurant_university_links').select('university_id').eq('restaurant_id', id),
  ])
  if (r.error) throw r.error
  if (links.error) throw links.error
  return fromRow(r.data, links.data.map((l) => l.university_id as string))
}

export default function RestaurantFormPage() {
  const { id } = useParams()
  const isNew = !id || id === 'new'
  const nav = useNavigate()
  const qc = useQueryClient()
  const unis = useUniversities()
  const [confirmValues, setConfirmValues] = useState<RestaurantForm | null>(null)
  const [saved, setSaved] = useState(false)

  const existing = useQuery({ queryKey: ['restaurant', id], enabled: !isNew, queryFn: () => loadRestaurant(id!) })
  const form = useForm<RestaurantForm>({ resolver: zodResolver(restaurantSchema), defaultValues: emptyRestaurantForm })
  const { register, control, handleSubmit, reset, formState: { errors, isDirty } } = form
  useEffect(() => { if (existing.data) reset(existing.data) }, [existing.data, reset])

  const save = useMutation({
    mutationFn: async (v: RestaurantForm) => {
      const row = toRow(v)
      let rid = id
      if (isNew) {
        const { data, error } = await supabase.from('restaurant_overrides').insert(row).select('id').single()
        if (error) throw error
        rid = data.id as string
      } else {
        const { error } = await supabase.from('restaurant_overrides').update(row).eq('id', id!)
        if (error) throw error
      }
      // Sync university links: add the new ones first, then remove the dropped ones.
      const before = new Set(existing.data?.university_ids ?? [])
      const after = new Set(v.university_ids)
      const add = [...after].filter((u) => !before.has(u)).map((u) => ({ restaurant_id: rid, university_id: u }))
      const drop = [...before].filter((u) => !after.has(u))
      if (add.length) { const { error } = await supabase.from('restaurant_university_links').insert(add); if (error) throw error }
      if (drop.length) { const { error } = await supabase.from('restaurant_university_links').delete().eq('restaurant_id', rid!).in('university_id', drop); if (error) throw error }
      return rid!
    },
    onSuccess: async (rid) => {
      setConfirmValues(null); setSaved(true)
      await qc.invalidateQueries({ queryKey: ['restaurants'] })
      await qc.invalidateQueries({ queryKey: ['restaurant', rid] })
      if (isNew) nav(`/restaurants/${rid}`, { replace: true })
    },
  })

  const dupMessage = (e: unknown) =>
    typeof e === 'object' && e && 'code' in e && (e as { code: string }).code === '23505'
      ? '이미 등록된 카카오 장소 ID예요. 기존 식당을 편집해 주세요.' : errorMessage(e)

  if (!isNew && existing.isLoading) return <Skeleton className="h-96 w-full" />
  if (!isNew && existing.error) return <ErrorState error={existing.error} onRetry={() => void existing.refetch()} />

  return (
    <form onSubmit={handleSubmit((v) => { setSaved(false); setConfirmValues(v) })} className="max-w-4xl space-y-6">
      <Link to="/restaurants" className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><ArrowLeft className="size-4" />식당 목록</Link>
      <PageHeader title={isNew ? '식당 추가' : '식당 편집'} description="저장하면 앱 사용자에게 바로 반영돼요 (공개 상태일 때)."
        actions={<Button type="submit" disabled={save.isPending || (!isNew && !isDirty)}>저장</Button>} />
      {saved && <p role="status" className="rounded-xl bg-green-50 p-3 text-sm text-green-800">저장했어요.</p>}
      {save.isError && <ErrorState error={new Error(dupMessage(save.error))} />}

      <Card className="grid gap-4 sm:grid-cols-2">
        <Field label="이름 (한국어)" htmlFor="name_ko" error={errors.name_ko?.message}><Input id="name_ko" {...register('name_ko')} /></Field>
        <Field label="이름 (영어)" htmlFor="name_en" error={errors.name_en?.message}><Input id="name_en" {...register('name_en')} /></Field>
        <Field label="카카오 장소 ID" htmlFor="kakao_place_id" hint="카카오 식당을 보강할 때 입력해요. 직접 만든 식당은 비워 두세요." error={errors.kakao_place_id?.message}><Input id="kakao_place_id" {...register('kakao_place_id')} /></Field>
        <Field label="카테고리" htmlFor="category" error={errors.category?.message}><Input id="category" {...register('category')} /></Field>
        <Field label="주소" htmlFor="address" error={errors.address?.message}><Input id="address" {...register('address')} /></Field>
        <Field label="전화번호" htmlFor="phone" error={errors.phone?.message}><Input id="phone" {...register('phone')} /></Field>
        <Field label="위도" htmlFor="latitude" error={errors.latitude?.message}><Input id="latitude" inputMode="decimal" {...register('latitude')} /></Field>
        <Field label="경도" htmlFor="longitude" error={errors.longitude?.message}><Input id="longitude" inputMode="decimal" {...register('longitude')} /></Field>
      </Card>

      <Card className="space-y-4">
        <Field label="설명" htmlFor="description" error={errors.description?.message}><Textarea id="description" {...register('description')} /></Field>
        <Field label="대표 이미지 주소" htmlFor="image_url" hint="https:// 로 시작해야 해요." error={errors.image_url?.message}><Input id="image_url" {...register('image_url')} /></Field>
        <Field label="식사 목적 (쉼표로 구분)" htmlFor="dining_purposes" error={errors.dining_purposes?.message}><Input id="dining_purposes" placeholder="혼밥, 회식, 데이트" {...register('dining_purposes')} /></Field>
      </Card>

      <Card className="grid gap-4 sm:grid-cols-3">
        <Field label="최저 가격 (원)" htmlFor="price_min_krw" error={errors.price_min_krw?.message}><Input id="price_min_krw" inputMode="numeric" {...register('price_min_krw')} /></Field>
        <Field label="최고 가격 (원)" htmlFor="price_max_krw" error={errors.price_max_krw?.message}><Input id="price_max_krw" inputMode="numeric" {...register('price_max_krw')} /></Field>
        <Field label="1인 평균 (원)" htmlFor="avg_cost_krw" error={errors.avg_cost_krw?.message}><Input id="avg_cost_krw" inputMode="numeric" {...register('avg_cost_krw')} /></Field>
        <Field label="브레이크타임" htmlFor="break_time" error={errors.break_time?.message}><Input id="break_time" placeholder="15:00-17:00" {...register('break_time')} /></Field>
        <Field label="주문 마감 (HH:MM)" htmlFor="last_order_time" error={errors.last_order_time?.message}><Input id="last_order_time" placeholder="21:30" {...register('last_order_time')} /></Field>
        <Field label="영업 상태" htmlFor="business_status">
          <Select id="business_status" {...register('business_status')}><option value="">알 수 없음</option>{BUSINESS_STATUSES.map((s) => <option key={s} value={s}>{BUSINESS_LABEL[s]}</option>)}</Select>
        </Field>
      </Card>

      <Card className="space-y-4">
        <Field label="공개 상태" htmlFor="visibility" hint="초안은 관리자만 볼 수 있어요. 숨김·보관은 앱에서 이 식당을 감춰요.">
          <Select id="visibility" {...register('visibility')}>{VISIBILITIES.map((v) => <option key={v} value={v}>{VISIBILITY_LABEL[v]}</option>)}</Select>
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

      <ConfirmDialog open={!!confirmValues} busy={save.isPending} title={isNew ? '식당을 추가할까요?' : '변경 사항을 저장할까요?'}
        description={confirmValues?.visibility === 'published' ? '공개 상태라 앱 사용자에게 바로 보여요.' : undefined}
        confirmLabel="저장" onConfirm={() => confirmValues && save.mutate(confirmValues)} onCancel={() => setConfirmValues(null)} />
    </form>
  )
}
