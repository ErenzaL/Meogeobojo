import { Card, PageHeader } from '@/components/ui'

/** No analytics events are collected yet, so there is nothing real to chart. */
export default function AnalyticsPage() {
  return (
    <>
      <PageHeader title="분석" description="실제로 수집된 데이터만 보여줘요." />
      <Card className="max-w-2xl space-y-3 text-sm">
        <p className="font-semibold">아직 수집 중인 분석 이벤트가 없어요.</p>
        <p className="text-muted">가짜 지표를 보여주지 않아요. 아래 데이터가 쌓이면 이 화면에 연결할 수 있어요.</p>
        <ul className="list-disc space-y-1 pl-5 text-muted">
          <li>일별 신규 가입 — <code>profiles.created_at</code> (이미 있음, 집계 쿼리만 추가하면 돼요)</li>
          <li>추천 요청 수 · 지연 시간 · 오류율 — 추천 API 연동 단계에서 <code>recommendation_requests</code> 텔레메트리 테이블로 수집 예정</li>
          <li>식당 상세 조회 · 길찾기 클릭 — 앱에서 이벤트를 보내는 기능이 필요해요</li>
        </ul>
        <p className="text-muted">개요 화면의 숫자는 모두 실제 데이터베이스 집계예요.</p>
      </Card>
    </>
  )
}
