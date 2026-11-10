import { Button, Field, Input, Select, Textarea } from '@/components/ui'
import { MEAL_LABEL, MEAL_STATUS_LABEL, MEAL_TYPES, THOUSAND_WON_BADGE, type MealForm } from './meal'

/** The meal's fields. [identity]: date / meal / corner are editable only while the
 *  meal is being created (they identify the meal and never change afterwards). */
export default function MealFields({ form, errors, set, identity }: { form: MealForm; errors: Record<string, string>; set: <K extends keyof MealForm>(k: K, v: MealForm[K]) => void; identity: boolean }) {
  return (
    <div className="space-y-3">
      {identity ? (
        <>
          <Field label="날짜" htmlFor="md" error={errors.date}><Input id="md" type="date" value={form.date} onChange={(e) => set('date', e.target.value)} /></Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="식사" htmlFor="mt"><Select id="mt" value={form.type} onChange={(e) => set('type', e.target.value as MealForm['type'])}>{MEAL_TYPES.map((t) => <option key={t} value={t}>{MEAL_LABEL[t]}</option>)}</Select></Field>
            <Field label="코너 (선택)" htmlFor="mo"><Input id="mo" value={form.option} onChange={(e) => set('option', e.target.value)} placeholder="B코너" /></Field>
          </div>
        </>
      ) : (
        <p className="rounded-xl bg-page p-3 text-sm" aria-label="식단 정보">{form.date} · {MEAL_LABEL[form.type]}{form.option ? ` (${form.option})` : ''} <span className="text-xs text-muted">날짜·식사·코너는 바꿀 수 없어요. 다른 날로 옮기려면 복제해 주세요.</span></p>
      )}
      <Field label="메뉴 (한 줄에 하나, 첫 줄이 메인)" htmlFor="mi" error={errors.items}><Textarea id="mi" value={form.items} onChange={(e) => set('items', e.target.value)} /></Field>
      <div className="grid grid-cols-3 gap-3">
        <Field label="가격(원)" htmlFor="mpz" error={errors.price}><Input id="mpz" inputMode="numeric" value={form.price} onChange={(e) => set('price', e.target.value)} /></Field>
        <Field label="시작" htmlFor="ms" error={errors.start}><Input id="ms" placeholder="08:00" value={form.start} onChange={(e) => set('start', e.target.value)} /></Field>
        <Field label="종료" htmlFor="me" error={errors.end}><Input id="me" placeholder="09:30" value={form.end} onChange={(e) => set('end', e.target.value)} /></Field>
      </div>
      <Field label="배지" htmlFor="mb" error={errors.badge} hint="공식 출처가 있을 때만 사용해요."><div className="flex gap-2"><Input id="mb" value={form.badge} onChange={(e) => set('badge', e.target.value)} /><Button type="button" variant="soft" size="sm" onClick={() => { set('badge', THOUSAND_WON_BADGE); if (identity) set('type', 'breakfast'); if (!form.price) set('price', '1000') }}>천원의 아침밥</Button></div></Field>
      <Field label="공지 (선택)" htmlFor="mnote" hint="식단 카드 아래에 보여요. 예: 방학 중 운영시간 변경"><Input id="mnote" maxLength={120} value={form.notice} onChange={(e) => set('notice', e.target.value)} /></Field>
      {!identity && (<Field label="게시할 때의 상태" htmlFor="mst" hint="게시하기 전에는 앱에 보이지 않아요."><Select id="mst" value={form.status} onChange={(e) => set('status', e.target.value as MealForm['status'])}>{Object.entries(MEAL_STATUS_LABEL).map(([v, l]) => <option key={v} value={v}>{l}</option>)}</Select></Field>)}
      <Field label="출처 주소" htmlFor="msrc" error={errors.source} hint={form.status === 'published' && !form.source.trim() ? '출처 없이 공개돼요. 가능하면 공식 주소를 적어 주세요.' : undefined}><Input id="msrc" placeholder="https://" value={form.source} onChange={(e) => set('source', e.target.value)} /></Field>
      <Field label="확인한 날짜" htmlFor="mver" error={errors.verified} hint="이 정보를 출처에서 확인한 날"><Input id="mver" type="date" value={form.verified} onChange={(e) => set('verified', e.target.value)} /></Field>
    </div>
  )
}
