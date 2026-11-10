import { Field, Input, Select, Textarea } from '@/components/ui'
import { ACTIONS, CONTRIBUTION_KINDS, EVENTS, ICONS, ICON_LABEL, KINDS, MASCOTS, MASCOT_LABEL, RULES, STATUS_LABEL, type Campaign, type University } from './model'
import type { MissionForm as Form } from './schema'

/** The mission form controls, shared by "create" and "edit as draft". */
export default function MissionFields({ f, set, errors, isNew, campaigns, universities, statusLabel }: {
  f: Form; set: (patch: Partial<Form>) => void; errors: Record<string, string>; isNew: boolean; campaigns: Campaign[]; universities: University[]; statusLabel?: string
}) {
  const rule = f.rule_type
  return (
    <>
        {!isNew && <p className="rounded-xl bg-page p-3 text-xs text-muted">진행 기록이 있는 미션의 <b>목표·보상·조건·대상·기간</b>을 바꾸면 기존 미션은 보관되고 새 버전이 만들어져요. 이미 완료한 사용자의 완료 상태와 포인트는 그대로 유지되고, 같은 보상이 다시 지급되지 않아요.</p>}
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="식별자 (slug)" htmlFor="m_slug" error={errors.slug} hint="만든 뒤에는 바꿀 수 없어요"><Input id="m_slug" value={f.slug} disabled={!isNew} onChange={(e) => set({ slug: e.target.value })} /></Field>
          <Field label="유형" htmlFor="m_kind"><Select id="m_kind" value={f.kind} onChange={(e) => set({ kind: e.target.value as Form['kind'] })}>{KINDS.map((k) => <option key={k.value} value={k.value}>{k.label}</option>)}</Select></Field>
        </div>
        <Field label="제목" htmlFor="m_title" error={errors.title}><Input id="m_title" value={f.title} onChange={(e) => set({ title: e.target.value })} /></Field>
        <Field label="설명 (완료 조건을 알려주세요)" htmlFor="m_desc" error={errors.description}><Textarea id="m_desc" value={f.description} onChange={(e) => set({ description: e.target.value })} /></Field>
        <div className="grid gap-3 sm:grid-cols-3">
          <Field label="캠페인" htmlFor="m_camp" error={errors.campaign_id}>
            <Select id="m_camp" value={f.campaign_id} onChange={(e) => set({ campaign_id: e.target.value })}>
              <option value="">없음</option>{campaigns.map((c) => <option key={c.id} value={c.id}>{c.title}</option>)}
            </Select>
          </Field>
          <Field label="아이콘" htmlFor="m_icon"><Select id="m_icon" value={f.icon} onChange={(e) => set({ icon: e.target.value })}>{ICONS.map((i) => <option key={i} value={i}>{ICON_LABEL[i]}</option>)}</Select></Field>
          <Field label="카테고리 (선택)" htmlFor="m_cat"><Input id="m_cat" value={f.category} onChange={(e) => set({ category: e.target.value })} /></Field>
        </div>
        <div className="grid gap-3 sm:grid-cols-3">
          <Field label="보상 포인트" htmlFor="m_pts" error={errors.reward_points}><Input id="m_pts" inputMode="numeric" value={f.reward_points} onChange={(e) => set({ reward_points: e.target.value })} /></Field>
          <Field label="목표 횟수" htmlFor="m_target" error={errors.target_count}><Input id="m_target" inputMode="numeric" value={f.target_count} onChange={(e) => set({ target_count: e.target.value })} /></Field>
          <Field label="정렬 순서" htmlFor="m_order"><Input id="m_order" inputMode="numeric" value={f.sort_order} onChange={(e) => set({ sort_order: e.target.value })} /></Field>
        </div>

        <fieldset className="space-y-3 rounded-xl border border-line p-3">
          <legend className="px-1 text-sm font-semibold">완료 조건 (서버가 실제 데이터로 계산해요)</legend>
          <Field label="규칙" htmlFor="m_rule" error={errors.rule_type}><Select id="m_rule" value={rule} onChange={(e) => set({ rule_type: e.target.value as Form['rule_type'] })}>{RULES.map((r) => <option key={r.value} value={r.value}>{r.label}</option>)}</Select></Field>
          {(rule === 'activity_days' || rule === 'activity_refs') && (
            <Field label="활동 종류" htmlFor="m_event" error={errors.event}><Select id="m_event" value={f.event} onChange={(e) => set({ event: e.target.value })}>{EVENTS.map((x) => <option key={x.value} value={x.value}>{x.label}</option>)}</Select></Field>)}
          {rule === 'activity_refs' && <Field label="제외할 항목 (쉼표로 구분)" htmlFor="m_exclude" hint="예: all (전체 카테고리는 세지 않아요)"><Input id="m_exclude" value={f.exclude} onChange={(e) => set({ exclude: e.target.value })} /></Field>}
          {rule === 'favorite_cheap' && <Field label="최대 가격 (원)" htmlFor="m_price" error={errors.max_price_krw} hint="관리자가 공개한 가격 정보가 있는 식당만 세어요"><Input id="m_price" inputMode="numeric" value={f.max_price_krw} onChange={(e) => set({ max_price_krw: e.target.value })} /></Field>}
          {rule === 'review_valid' && <Field label="최소 글자 수" htmlFor="m_chars" error={errors.min_chars}><Input id="m_chars" inputMode="numeric" value={f.min_chars} onChange={(e) => set({ min_chars: e.target.value })} /></Field>}
          {rule === 'contribution_approved' && <Field label="기여 종류" htmlFor="m_ckind" error={errors.contribution_kind}><Select id="m_ckind" value={f.contribution_kind} onChange={(e) => set({ contribution_kind: e.target.value })}>{CONTRIBUTION_KINDS.map((x) => <option key={x.value} value={x.value}>{x.label}</option>)}</Select></Field>}
        </fieldset>

        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="대상 캠퍼스" htmlFor="m_uni"><Select id="m_uni" value={f.university_id} onChange={(e) => set({ university_id: e.target.value })}><option value="">모든 캠퍼스</option>{universities.map((u) => <option key={u.id} value={u.id}>{u.name_ko}</option>)}</Select></Field>
          <Field label="버튼 동작" htmlFor="m_action"><Select id="m_action" value={f.action_key} onChange={(e) => set({ action_key: e.target.value })}>{ACTIONS.map((a) => <option key={a.value} value={a.value}>{a.label}</option>)}</Select></Field>
          <Field label="시작일 (한국 시간, 비우면 캠페인 기간)" htmlFor="m_start" error={errors.start_date}><Input id="m_start" type="date" value={f.start_date} onChange={(e) => set({ start_date: e.target.value })} /></Field>
          <Field label="종료일 (포함)" htmlFor="m_end" error={errors.end_date}><Input id="m_end" type="date" value={f.end_date} onChange={(e) => set({ end_date: e.target.value })} /></Field>
        </div>
        {(f.kind === 'daily' || f.kind === 'weekly') && <p className="text-xs text-muted">{f.kind === 'daily' ? '매일 0시(한국 시간)에 새로 시작해요. 하루에 한 번만 보상해요.' : '매주 월요일 0시(한국 시간)에 새로 시작해요. 한 주에 한 번만 보상해요.'}</p>}

        <fieldset className="space-y-3 rounded-xl border border-line p-3">
          <legend className="px-1 text-sm font-semibold">뱃지 보상 (선택)</legend>
          <div className="grid gap-3 sm:grid-cols-3">
            <Field label="뱃지 키" htmlFor="m_bkey" error={errors.badge_key} hint="사용자당 한 번만 받아요"><Input id="m_bkey" value={f.badge_key} onChange={(e) => set({ badge_key: e.target.value })} /></Field>
            <Field label="뱃지 이름" htmlFor="m_bname"><Input id="m_bname" value={f.badge_name} onChange={(e) => set({ badge_name: e.target.value })} /></Field>
            <Field label="마스코트" htmlFor="m_bmascot"><Select id="m_bmascot" value={f.badge_mascot} onChange={(e) => set({ badge_mascot: e.target.value })}><option value="">없음</option>{MASCOTS.map((m) => <option key={m} value={m}>{MASCOT_LABEL[m]}</option>)}</Select></Field>
          </div>
        </fieldset>

        {!isNew && <Field label={statusLabel ?? '상태'} htmlFor="m_status" hint="게시한 뒤의 상태예요. 운영 중으로 게시하면 기간이 되는 즉시 앱에 나타나요. 기간 밖이면 예약돼요.">
          <Select id="m_status" value={f.status} onChange={(e) => set({ status: e.target.value })}>{(['draft', 'active', 'paused'] as const).map((s) => <option key={s} value={s}>{STATUS_LABEL[s]}</option>)}</Select>
        </Field>}
    </>
  )
}
