import { Badge, Modal } from '@/components/ui'
import { diffSnapshots, showValue, type Snapshot } from '@/lib/cms'
import { MEAL_LABEL, MEAL_TYPES, THOUSAND_WON_BADGE } from './meal'
import { dayName, mealsIn, weekCounts, type MealPeriod, type WeekMeal } from './week'

/** The week as students will see it (Monday-Friday and any weekend days with menus, breakfast / lunch / dinner),
 *  and exactly what differs from what is published now. */
export default function WeekPreview({ open, live, draft, dates, periods, onClose }: { open: boolean; live: Snapshot; draft: Snapshot; dates: string[]; periods: MealPeriod[]; onClose: () => void }) {
  const meals = ((draft.meals as WeekMeal[] | undefined) ?? [])
  const changes = diffSnapshots(live, draft)
  const c = weekCounts(meals)
  return (
    <Modal open={open} title="주간 미리보기" onClose={onClose}>
      <div className="space-y-4">
        <p className="text-sm text-muted">저장한 초안 기준이에요. 메뉴 {c.menus}개 · 요리 {c.dishes}개 · {c.days}일 · 천원의 아침밥 {c.thousandWon}일</p>
        <div className="overflow-x-auto" aria-label="앱 주간 식단 미리보기">
          <table className="w-full min-w-[40rem] border-separate border-spacing-1 text-xs">
            <thead><tr><th />{dates.map((d) => <th key={d} className="rounded bg-page px-1.5 py-1 text-left">{d.slice(5)} ({dayName(d)})</th>)}</tr></thead>
            <tbody>
              {MEAL_TYPES.filter((t) => periods.includes(t) || meals.some((m) => m.meal_type === t)).map((t) => (
                <tr key={t} className="align-top">
                  <th scope="row" className="rounded bg-page px-1.5 py-1 text-left">{MEAL_LABEL[t]}</th>
                  {dates.map((d) => {
                    const here = mealsIn(meals, d, t)
                    return (
                      <td key={d} className="rounded border border-line p-1.5">
                        {here.length === 0 && <span className="text-muted">등록된 식단 없음</span>}
                        {here.map((m) => (
                          <div key={`${m.option_name}`} className="mb-1.5 last:mb-0">
                            <div className="font-semibold">{m.option_name || ''} {m.badge === THOUSAND_WON_BADGE && <Badge tone="brand">천원의 아침밥</Badge>} {m.extra.sold_out && <Badge tone="amber">품절</Badge>}</div>
                            {m.status === 'published' ? <>
                              <div>{m.menu_items.filter((i) => !i.shared).map((i) => i.name_ko).join(', ')}</div>
                              {m.menu_items.some((i) => i.shared) && <div className="text-muted">공통: {m.menu_items.filter((i) => i.shared).map((i) => i.name_ko).join(', ')}</div>}
                              {m.extra.labels?.length && m.extra.labels_verified ? <Badge tone="brand">{m.extra.labels.join(' · ')}</Badge> : null}
                              {m.extra.origin && <div className="text-muted">원산지 표시 있음</div>}
                            </> : <div className="text-muted">{m.status === 'closed' ? '운영하지 않아요' : '메뉴가 공개되지 않았어요'}</div>}
                            <div className="text-muted">{m.price_krw != null ? `${m.price_krw.toLocaleString('ko-KR')}원` : '가격 미정'}{m.start_time && m.end_time ? ` · ${m.start_time}–${m.end_time}` : ''}</div>
                          </div>))}
                      </td>)
                  })}
                </tr>))}
            </tbody>
          </table>
        </div>
        <div>
          <h3 className="mb-1 text-sm font-bold">지금 게시된 내용과 달라지는 항목 ({changes.length})</h3>
          {changes.length === 0 ? <p className="rounded-xl bg-page p-3 text-sm text-muted">게시된 내용과 같아요.</p> : (
            <ul aria-label="달라지는 항목" className="max-h-60 space-y-1.5 overflow-auto rounded-xl bg-page p-3 text-sm">
              {changes.map((ch) => <li key={ch.key}><b>{ch.label}</b>: <span className="text-muted line-through">{showValue(ch.from)}</span> → {showValue(ch.to)}</li>)}
            </ul>)}
        </div>
      </div>
    </Modal>)
}
