import { Trash2 } from 'lucide-react'
import { useState } from 'react'
import { Badge, Button, Input, Select, Textarea } from '@/components/ui'
import { MEAL_LABEL, MEAL_TYPES, THOUSAND_WON_BADGE } from './meal'
import { dayName, linesToText, type MenuLine, mealsIn, parseLines, slotKey, type MealPeriod, type MealStatus, type WeekMeal } from './week'

/** The text the admin is typing is kept as typed (trailing spaces, new lines); it is re-read from the menu only when the menu
 *  was changed from outside (copy tools, a loaded draft). */
function MenuText({ label, items, onChange }: { label: string; items: MenuLine[]; onChange: (items: MenuLine[]) => void }) {
  const [text, setText] = useState(linesToText(items))
  const [seen, setSeen] = useState(items)
  if (items !== seen) {
    setSeen(items)
    if (JSON.stringify(parseLines(text)) !== JSON.stringify(items)) setText(linesToText(items))
  }
  return <Textarea aria-label={label} className="min-h-14 text-xs" placeholder={'한 줄에 하나 (첫 줄이 메인)'} value={text} onChange={(e) => { setText(e.target.value); onChange(parseLines(e.target.value)) }} />
}

/** The option name is kept as typed. A name another option of the same meal already uses is flagged and NOT applied (and the field
 *  goes back to the real name when you leave it), so clearing the field to retype a name works. */
function OptionName({ label, name, clash, onRename }: { label: string; name: string; clash: (name: string) => boolean; onRename: (name: string) => void }) {
  const [text, setText] = useState(name)
  const [seen, setSeen] = useState(name)
  if (name !== seen) { setSeen(name); setText(name) }
  return (
    <div className="min-w-0 flex-1">
      <Input aria-label={label} className="h-8 text-xs" placeholder="코너 (선택)" maxLength={40} value={text} aria-invalid={clash(text)}
        onChange={(e) => { setText(e.target.value); if (!clash(e.target.value)) onRename(e.target.value) }} onBlur={() => setText(name)} />
      {clash(text) && <p role="alert" className="mt-0.5 text-red-600">같은 식사에 이미 있는 이름이에요</p>}
    </div>)
}

const STATUS_LABEL: Record<MealStatus, string> = { published: '메뉴 공개', closed: '운영 안 함', no_menu: '메뉴 비공개' }

/** The accessible name of one option, e.g. "2026-11-09 중식 (B코너)". */
export const optionLabel = (m: Pick<WeekMeal, 'date' | 'meal_type' | 'option_name'>) => `${m.date} ${MEAL_LABEL[m.meal_type]}${m.option_name ? ` (${m.option_name})` : ''}`

type Ops = {
  change: (key: string, patch: Partial<WeekMeal>) => void
  extra: (key: string, patch: Partial<WeekMeal['extra']>) => void
  rename: (key: string, name: string) => void
  taken: (m: WeekMeal, name: string) => boolean
  add: (date: string, type: MealPeriod) => void
  remove: (m: WeekMeal) => void
  askStatus: (m: WeekMeal, to: MealStatus) => void
  select: (key: string, on: boolean) => void
}

function OptionCard({ m, ops, selected, liveKeys, problem }: { m: WeekMeal; ops: Ops; selected: boolean; liveKeys: Set<string>; problem?: string }) {
  const key = slotKey(m)
  const L = optionLabel(m)
  const isNew = !liveKeys.has(key)
  const num = (v: string) => (v.trim() === '' ? null : Number(v.replace(/[,\s]/g, '')))
  return (
    <div className={`space-y-1.5 rounded-xl border p-2 text-xs ${problem ? 'border-red-400' : 'border-line'} ${selected ? 'bg-brand/10' : 'bg-white'}`} role="group" aria-label={L}>
      <div className="flex items-center gap-1.5">
        <input type="checkbox" aria-label={`${L} 선택`} checked={selected} onChange={(e) => ops.select(key, e.target.checked)} />
        <OptionName label={`${L} 옵션 이름`} name={m.option_name} clash={(n) => ops.taken(m, n)} onRename={(n) => ops.rename(key, n)} />
        {isNew && <Badge tone="neutral">새 메뉴</Badge>}
        {m.badge === THOUSAND_WON_BADGE && <Badge tone="brand">천원</Badge>}
      </div>
      {m.status === 'published' ? (
        <MenuText label={`${L} 메뉴`} items={m.menu_items} onChange={(menu_items) => ops.change(key, { menu_items })} />
      ) : <p className="rounded-lg bg-page p-2 text-muted">{STATUS_LABEL[m.status]}으로 표시돼요</p>}
      <div className="grid grid-cols-3 gap-1.5">
        <Input aria-label={`${L} 가격`} className="h-8 text-xs" inputMode="numeric" placeholder="가격(원)" value={m.price_krw ?? ''} onChange={(e) => ops.change(key, { price_krw: num(e.target.value) })} />
        <Input aria-label={`${L} 시작`} className="h-8 text-xs" placeholder="11:30" value={m.start_time ?? ''} onChange={(e) => ops.change(key, { start_time: e.target.value || null })} />
        <Input aria-label={`${L} 종료`} className="h-8 text-xs" placeholder="13:30" value={m.end_time ?? ''} onChange={(e) => ops.change(key, { end_time: e.target.value || null })} />
      </div>
      <Select aria-label={`${L} 상태`} className="h-8 text-xs" value={m.status} onChange={(e) => ops.askStatus(m, e.target.value as MealStatus)}>
        {(Object.keys(STATUS_LABEL) as MealStatus[]).map((s) => <option key={s} value={s}>{STATUS_LABEL[s]}</option>)}
      </Select>
      {m.meal_type === 'breakfast' && (
        <label className="flex items-center gap-1.5"><input type="checkbox" aria-label={`${L} 천원의 아침밥`} checked={m.badge === THOUSAND_WON_BADGE}
          onChange={(e) => ops.change(key, e.target.checked ? { badge: THOUSAND_WON_BADGE, price_krw: m.price_krw ?? 1000 } : { badge: null, source_url: null })} />천원의 아침밥</label>)}
      {m.badge === THOUSAND_WON_BADGE && <Input aria-label={`${L} 출처 주소`} className="h-8 text-xs" placeholder="공식 출처 https://" value={m.source_url ?? ''} onChange={(e) => ops.change(key, { source_url: e.target.value.trim() || null })} />}
      <Input aria-label={`${L} 공지`} className="h-8 text-xs" placeholder="특이사항 (선택)" value={m.extra.notice ?? ''} onChange={(e) => ops.extra(key, { notice: e.target.value })} />
      <div className="flex items-center justify-between">
        <label className="flex items-center gap-1.5"><input type="checkbox" aria-label={`${L} 품절`} checked={!!m.extra.sold_out} onChange={(e) => ops.extra(key, { sold_out: e.target.checked })} />품절</label>
        <Button size="sm" variant="ghost" aria-label={`${L} 삭제`} onClick={() => ops.remove(m)}><Trash2 className="size-3.5 text-red-600" />이 메뉴 삭제</Button>
      </div>
      {problem && <p role="alert" className="text-red-600">{problem}</p>}
    </div>
  )
}

/** Monday-Friday (and weekend) x breakfast/lunch/dinner: every cell lists its options and is edited in place. */
export default function WeekGrid({ dates, periods, meals, liveKeys, selected, problems, ops }: {
  dates: string[]; periods: MealPeriod[]; meals: WeekMeal[]; liveKeys: Set<string>; selected: Set<string>; problems: Map<string, string>; ops: Ops
}) {
  return (
    <div className="overflow-x-auto" aria-label="주간 식단표">
      <table className="w-full min-w-[56rem] table-fixed border-separate border-spacing-1.5 text-sm">
        <thead>
          <tr><th className="w-14" />{dates.map((d) => <th key={d} scope="col" className="rounded-lg bg-page px-2 py-1.5 text-left font-semibold">{d.slice(5).replace('-', '/')} ({dayName(d)})</th>)}</tr>
        </thead>
        <tbody>
          {MEAL_TYPES.filter((t) => periods.includes(t)).map((t) => (
            <tr key={t} className="align-top">
              <th scope="row" className="rounded-lg bg-page px-2 py-2 text-left font-semibold">{MEAL_LABEL[t]}</th>
              {dates.map((d) => {
                const here = mealsIn(meals, d, t)
                return (
                  <td key={d} aria-label={`${d} ${MEAL_LABEL[t]}`} className="space-y-1.5 rounded-xl bg-white/50 p-0.5">
                    {here.map((m, i) => <OptionCard key={`${d}|${t}|${i}`} m={m} ops={ops} selected={selected.has(slotKey(m))} liveKeys={liveKeys} problem={problems.get(slotKey(m))} />)}
                    <Button size="sm" variant={here.length ? 'ghost' : 'outline'} className="w-full border-dashed" aria-label={`${d} ${MEAL_LABEL[t]} ${here.length ? '옵션 추가' : '추가'}`} onClick={() => ops.add(d, t)}>
                      + {here.length ? '옵션 추가' : MEAL_LABEL[t] + ' 추가'}
                    </Button>
                  </td>)
              })}
            </tr>))}
        </tbody>
      </table>
    </div>
  )
}
