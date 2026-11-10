import { useState } from 'react'
import { Button, Field, Input, Modal, Select, Textarea } from '@/components/ui'
import { MEAL_LABEL, MEAL_TYPES } from './meal'
import { dayName, type MealPeriod, type MealStatus } from './week'

const Days = ({ dates, value, onChange, label }: { dates: string[]; value: string[]; onChange: (v: string[]) => void; label: string }) => (
  <fieldset className="space-y-1"><legend className="text-sm font-medium">{label}</legend>
    <div className="flex flex-wrap gap-3 text-sm">{dates.map((d) => (
      <label key={d} className="flex items-center gap-1.5"><input type="checkbox" aria-label={`${label} ${d}`} checked={value.includes(d)} onChange={(e) => onChange(e.target.checked ? [...value, d] : value.filter((x) => x !== d))} />{dayName(d)} {d.slice(5)}</label>))}</div>
  </fieldset>)

/** 요일 복사: one day's menus onto other days. */
export function CopyDayDialog({ open, dates, onClose, onApply }: { open: boolean; dates: string[]; onClose: () => void; onApply: (from: string, to: string[], overwrite: boolean) => void }) {
  const [from, setFrom] = useState(dates[0] ?? '')
  const [to, setTo] = useState<string[]>([])
  const [overwrite, setOverwrite] = useState(false)
  return (
    <Modal open={open} title="요일 복사" onClose={onClose}>
      <div className="space-y-3">
        <Field label="복사할 요일" htmlFor="cd_from"><Select id="cd_from" value={from} onChange={(e) => { setFrom(e.target.value); setTo((t) => t.filter((d) => d !== e.target.value)) }}>{dates.map((d) => <option key={d} value={d}>{dayName(d)} {d.slice(5)}</option>)}</Select></Field>
        <Days dates={dates.filter((d) => d !== from)} value={to} onChange={setTo} label="붙여넣을 요일" />
        <label className="flex items-start gap-2 text-sm"><input type="checkbox" checked={overwrite} onChange={(e) => setOverwrite(e.target.checked)} />
          <span>그 요일에 이미 있는 메뉴를 덮어써요 <span className="text-xs text-muted">(끄면 비어 있는 칸만 채워요). 천원의 아침밥·출처·품절 표시는 복사하지 않아요.</span></span></label>
        <div className="flex justify-end gap-2"><Button variant="outline" onClick={onClose}>취소</Button><Button disabled={to.length === 0} onClick={() => { onApply(from, to, overwrite); onClose() }}>복사</Button></div>
      </div>
    </Modal>)
}

/** 전주 복사: another week's menus shifted onto this week. */
export function CopyWeekDialog({ open, thisMonday, previousMonday, nextMonday, busy, onClose, onApply }: { open: boolean; thisMonday: string; previousMonday: string; nextMonday: string; busy: boolean; onClose: () => void; onApply: (source: string, overwrite: boolean) => void }) {
  const [source, setSource] = useState(previousMonday)
  const [overwrite, setOverwrite] = useState(false)
  return (
    <Modal open={open} title="다른 주 복사" onClose={onClose}>
      <div className="space-y-3">
        <p className="text-sm text-muted">{thisMonday} 주에 다른 주의 식단을 날짜만 옮겨서 가져와요. 저장하기 전에는 초안에도 반영되지 않아요.</p>
        <Field label="가져올 주" htmlFor="cw_src"><Select id="cw_src" value={source} onChange={(e) => setSource(e.target.value)}>
          <option value={previousMonday}>지난주 ({previousMonday} ~)</option><option value={nextMonday}>다음 주 ({nextMonday} ~)</option></Select></Field>
        <label className="flex items-start gap-2 text-sm"><input type="checkbox" checked={overwrite} onChange={(e) => setOverwrite(e.target.checked)} />
          <span>이 주에 이미 있는 메뉴를 모두 바꿔요 <span className="text-xs text-muted">(끄면 비어 있는 칸만 채워요)</span></span></label>
        <div className="flex justify-end gap-2"><Button variant="outline" onClick={onClose}>취소</Button><Button disabled={busy} onClick={() => onApply(source, overwrite)}>{busy ? '불러오는 중…' : '가져오기'}</Button></div>
      </div>
    </Modal>)
}

/** 공통 운영 시간: one serving time for several weekdays. */
export function HoursDialog({ open, dates, periods, onClose, onApply }: { open: boolean; dates: string[]; periods: MealPeriod[]; onClose: () => void; onApply: (dates: string[], periods: MealPeriod[], start: string, end: string) => void }) {
  const [days, setDays] = useState<string[]>(dates.slice(0, 5))
  const [ps, setPs] = useState<MealPeriod[]>([]) // chosen explicitly: breakfast, lunch and dinner usually differ
  const [start, setStart] = useState('11:30')
  const [end, setEnd] = useState('13:30')
  const ok = /^([01]\d|2[0-3]):[0-5]\d$/.test(start) && /^([01]\d|2[0-3]):[0-5]\d$/.test(end) && start < end && days.length > 0 && ps.length > 0
  return (
    <Modal open={open} title="공통 운영 시간 적용" onClose={onClose}>
      <div className="space-y-3">
        <Days dates={dates} value={days} onChange={setDays} label="적용할 요일" />
        <fieldset className="space-y-1"><legend className="text-sm font-medium">적용할 식사</legend>
          <div className="flex gap-4 text-sm">{MEAL_TYPES.filter((t) => periods.includes(t)).map((t) => (
            <label key={t} className="flex items-center gap-1.5"><input type="checkbox" aria-label={`적용할 식사 ${MEAL_LABEL[t]}`} checked={ps.includes(t)} onChange={(e) => setPs(e.target.checked ? [...ps, t] : ps.filter((x) => x !== t))} />{MEAL_LABEL[t]}</label>))}</div></fieldset>
        <div className="grid grid-cols-2 gap-3">
          <Field label="시작" htmlFor="hr_s"><Input id="hr_s" value={start} onChange={(e) => setStart(e.target.value)} /></Field>
          <Field label="종료" htmlFor="hr_e" error={start >= end ? '종료는 시작보다 늦어야 해요' : undefined}><Input id="hr_e" value={end} onChange={(e) => setEnd(e.target.value)} /></Field>
        </div>
        <p className="text-xs text-muted">{ps.length === 0 ? '적용할 식사를 하나 이상 골라 주세요. ' : ''}이미 적힌 메뉴의 이용 시간만 바뀌어요. 메뉴가 없는 칸은 그대로예요.</p>
        <div className="flex justify-end gap-2"><Button variant="outline" onClick={onClose}>취소</Button><Button disabled={!ok} onClick={() => { onApply(days, ps, start, end); onClose() }}>적용</Button></div>
      </div>
    </Modal>)
}

/** 일괄 수정: the same change on every selected menu. Empty fields change nothing. */
export function BulkDialog({ open, count, onClose, onApply }: { open: boolean; count: number; onClose: () => void; onApply: (patch: { price?: number | null; start?: string; end?: string; status?: MealStatus; soldOut?: boolean }) => void }) {
  const [price, setPrice] = useState('')
  const [start, setStart] = useState('')
  const [end, setEnd] = useState('')
  const [status, setStatus] = useState<'' | MealStatus>('')
  const [sold, setSold] = useState<'' | 'yes' | 'no'>('')
  const priceBad = price !== '' && !/^\d+$/.test(price.replace(/[,\s]/g, ''))
  const timeBad = (!!start !== !!end) || (!!start && (!/^([01]\d|2[0-3]):[0-5]\d$/.test(start) || !/^([01]\d|2[0-3]):[0-5]\d$/.test(end) || start >= end))
  return (
    <Modal open={open} title={`선택한 ${count}개 메뉴 일괄 수정`} onClose={onClose}>
      <div className="space-y-3">
        <p className="text-xs text-muted">비워 둔 항목은 바꾸지 않아요.</p>
        <Field label="가격 (원)" htmlFor="bk_p" error={priceBad ? '0 이상의 정수' : undefined}><Input id="bk_p" inputMode="numeric" value={price} onChange={(e) => setPrice(e.target.value)} /></Field>
        <div className="grid grid-cols-2 gap-3">
          <Field label="시작" htmlFor="bk_s"><Input id="bk_s" value={start} onChange={(e) => setStart(e.target.value)} /></Field>
          <Field label="종료" htmlFor="bk_e" error={timeBad ? '시작·종료를 함께, HH:MM' : undefined}><Input id="bk_e" value={end} onChange={(e) => setEnd(e.target.value)} /></Field>
        </div>
        <Field label="상태" htmlFor="bk_st"><Select id="bk_st" value={status} onChange={(e) => setStatus(e.target.value as '' | MealStatus)}><option value="">바꾸지 않음</option><option value="published">메뉴 공개</option><option value="closed">운영 안 함</option><option value="no_menu">메뉴 비공개</option></Select></Field>
        <Field label="품절 표시" htmlFor="bk_so"><Select id="bk_so" value={sold} onChange={(e) => setSold(e.target.value as '' | 'yes' | 'no')}><option value="">바꾸지 않음</option><option value="yes">품절로 표시</option><option value="no">품절 해제</option></Select></Field>
        <div className="flex justify-end gap-2"><Button variant="outline" onClick={onClose}>취소</Button>
          <Button disabled={priceBad || timeBad || (price === '' && !start && !status && !sold)} onClick={() => { onApply({ ...(price !== '' ? { price: Number(price.replace(/[,\s]/g, '')) } : {}), ...(start ? { start, end } : {}), ...(status ? { status } : {}), ...(sold ? { soldOut: sold === 'yes' } : {}) }); onClose() }}>적용</Button></div>
      </div>
    </Modal>)
}

/** 선택한 날만 게시: atomic, the other days stay in the draft. */
export function PublishDaysDialog({ open, dates, changed, busy, onClose, onPublish }: { open: boolean; dates: string[]; changed: string[]; busy: boolean; onClose: () => void; onPublish: (days: string[], reason: string) => void }) {
  const [days, setDays] = useState<string[]>(changed)
  const [reason, setReason] = useState('')
  return (
    <Modal open={open} title="선택한 날만 게시" onClose={onClose}>
      <div className="space-y-3">
        <p className="text-sm text-muted">고른 날의 변경만 한꺼번에(전부 성공하거나 전부 취소) 게시해요. 나머지 날의 수정은 초안에 남아요.</p>
        <Days dates={dates} value={days} onChange={setDays} label="게시할 날짜" />
        <p className="text-xs text-muted">변경이 있는 날: {changed.length ? changed.map((d) => `${dayName(d)} ${d.slice(5)}`).join(', ') : '없음'}</p>
        <Field label="게시 메모 (선택)" htmlFor="pd_r"><Textarea id="pd_r" className="min-h-14" value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        <div className="flex justify-end gap-2"><Button variant="outline" onClick={onClose}>취소</Button><Button disabled={busy || days.length === 0} onClick={() => onPublish(days, reason)}>{busy ? '게시 중…' : `${days.length}일 게시`}</Button></div>
      </div>
    </Modal>)
}
